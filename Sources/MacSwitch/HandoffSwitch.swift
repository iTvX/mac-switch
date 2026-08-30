import CoreFoundation
import CSystemNotify
import Darwin
import Foundation
import OSLog

enum HandoffPreferenceKey: String, CaseIterable, Sendable {
    case advertising = "ActivityAdvertisingAllowed"
    case receiving = "ActivityReceivingAllowed"
}

struct HandoffPreferenceState: Equatable, Sendable {
    let rawAdvertising: Bool?
    let rawReceiving: Bool?
    let advertising: Bool
    let receiving: Bool
    let isManaged: Bool
    let didSynchronize: Bool
    let notificationContractAvailable: Bool
    let observesExternalChanges: Bool

    var isEnabled: Bool {
        advertising && receiving
    }

    var isConsistent: Bool {
        advertising == receiving
    }

    var isAvailable: Bool {
        didSynchronize && notificationContractAvailable && !isManaged
    }
}

enum HandoffStatePolicy {
    // Apple enables Handoff by default, so an unset preference means enabled.
    static let defaultEnabledWhenUnset = true

    static func effectiveValue(_ value: Bool?) -> Bool {
        value ?? defaultEnabledWhenUnset
    }

    static func isEnabled(advertising: Bool?, receiving: Bool?) -> Bool {
        effectiveValue(advertising) && effectiveValue(receiving)
    }
}

protocol HandoffPreferencesClientProtocol: AnyObject, Sendable {
    var supportsChangeNotification: Bool { get }
    func synchronize() -> Bool
    func rawValue(for key: HandoffPreferenceKey) -> Bool?
    func effectiveValue(for key: HandoffPreferenceKey) -> Bool?
    func isForced(_ key: HandoffPreferenceKey) -> Bool
    func setRawValues(advertising: Bool?, receiving: Bool?)
    func postChangeNotification() -> Bool
    func observeChanges(_ handler: @escaping @Sendable () -> Void) -> (any HandoffChangeObservation)?
}

protocol HandoffChangeObservation: AnyObject, Sendable {}

enum HandoffDarwinNotification {
    private static let userActivityFramework = "/System/Library/PrivateFrameworks/UserActivity.framework/UserActivity"
    private static let exportedName = "UAUserActivityManagerActivityContinuationIsEnabledChangedNotification"
    private static let maximumNameLength = 512

    static let resolvedName: String? = {
        guard let handle = dlopen(userActivityFramework, RTLD_LAZY) else {
            return nil
        }
        defer { dlclose(handle) }
        guard let symbol = dlsym(handle, exportedName) else {
            return nil
        }
        guard let pointer = symbol.load(as: Optional<UnsafePointer<CChar>>.self) else {
            return nil
        }
        let length = strnlen(pointer, maximumNameLength)
        guard length > 0, length < maximumNameLength else { return nil }
        let resolved = String(cString: pointer)
        guard resolved.hasSuffix("ActivityContinuationIsEnabledChangedNotification") else {
            return nil
        }
        return resolved
    }()

    static var isSupported: Bool { resolvedName != nil }

    static func post() -> Bool {
        guard let resolvedName else { return false }
        return resolvedName.withCString { MSNotifyPost($0) == 0 }
    }
}

enum HandoffRuntimeCompatibility {
    // Global Handoff has no public setter. Fail closed until each major macOS
    // version is verified against the native AirDrop & Continuity extension.
    static let verifiedMajorVersions: Set<Int> = [14, 15, 26]

    static var supportsCurrentSystem: Bool {
        supports(
            osVersion: ProcessInfo.processInfo.operatingSystemVersion,
            notificationContractAvailable: HandoffDarwinNotification.isSupported
        )
    }

    static func supports(
        osVersion: OperatingSystemVersion,
        notificationContractAvailable: Bool
    ) -> Bool {
        verifiedMajorVersions.contains(osVersion.majorVersion) && notificationContractAvailable
    }
}

private final class CoreFoundationHandoffPreferencesClient: HandoffPreferencesClientProtocol, @unchecked Sendable {
    private let domain = "com.apple.coreservices.useractivityd" as CFString

    var supportsChangeNotification: Bool {
        HandoffRuntimeCompatibility.supportsCurrentSystem
    }

    func synchronize() -> Bool {
        CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
    }

    func rawValue(for key: HandoffPreferenceKey) -> Bool? {
        booleanValue(
            CFPreferencesCopyValue(
                key.rawValue as CFString,
                domain,
                kCFPreferencesCurrentUser,
                kCFPreferencesCurrentHost
            )
        )
    }

    func effectiveValue(for key: HandoffPreferenceKey) -> Bool? {
        booleanValue(CFPreferencesCopyAppValue(key.rawValue as CFString, domain))
    }

    func isForced(_ key: HandoffPreferenceKey) -> Bool {
        CFPreferencesAppValueIsForced(key.rawValue as CFString, domain)
    }

    func setRawValues(advertising: Bool?, receiving: Bool?) {
        var valuesToSet: [String: Any] = [:]
        var keysToRemove: [String] = []
        for (key, value) in [
            (HandoffPreferenceKey.advertising, advertising),
            (HandoffPreferenceKey.receiving, receiving)
        ] {
            if let value {
                valuesToSet[key.rawValue] = value
            } else {
                keysToRemove.append(key.rawValue)
            }
        }
        CFPreferencesSetMultiple(
            valuesToSet as CFDictionary,
            keysToRemove as CFArray,
            domain,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        )
    }

    func postChangeNotification() -> Bool {
        HandoffDarwinNotification.post()
    }

    func observeChanges(_ handler: @escaping @Sendable () -> Void) -> (any HandoffChangeObservation)? {
        HandoffNotificationObserver(handler: handler)
    }

    private func booleanValue(_ value: CFPropertyList?) -> Bool? {
        guard let value, CFGetTypeID(value as CFTypeRef) == CFBooleanGetTypeID() else {
            return nil
        }
        return CFBooleanGetValue(unsafeDowncast(value, to: CFBoolean.self))
    }
}

private final class HandoffNotificationObserver: HandoffChangeObservation, @unchecked Sendable {
    private var token: Int32 = -1

    init?(handler: @escaping @Sendable () -> Void) {
        guard let notificationName = HandoffDarwinNotification.resolvedName else {
            return nil
        }
        var registeredToken: Int32 = -1
        let status = notificationName.withCString { name in
            MSNotifyRegisterDispatch(name, &registeredToken, DispatchQueue.global(qos: .utility)) { _ in
                handler()
            }
        }
        guard status == 0 else { return nil }
        token = registeredToken
    }

    deinit {
        if token >= 0 {
            MSNotifyCancel(token)
        }
    }
}

private let handoffLogger = Logger(subsystem: "com.maxyu.macswitch", category: "Handoff")

final class HandoffSwitch: @unchecked Sendable {
    private let client: any HandoffPreferencesClientProtocol
    private let waitForPropagation: @Sendable () -> Void
    private let lock = NSLock()
    private var notificationObserver: (any HandoffChangeObservation)?
    private var observationRegistrationSucceeded: Bool?

    init(
        client: any HandoffPreferencesClientProtocol = CoreFoundationHandoffPreferencesClient(),
        waitForPropagation: @escaping @Sendable () -> Void = {
            Thread.sleep(forTimeInterval: 0.15)
        }
    ) {
        self.client = client
        self.waitForPropagation = waitForPropagation
    }

    @discardableResult
    func observeStatusChanges(_ handler: @escaping @Sendable () -> Void) -> Bool {
        let observer = client.observeChanges(handler)
        lock.withLock {
            notificationObserver = observer
            observationRegistrationSucceeded = observer != nil
        }
        return observer != nil
    }

    func currentState() -> HandoffPreferenceState {
        lock.withLock {
            readState(synchronize: true)
        }
    }

    func snapshot() -> SwitchSnapshot {
        let state = currentState()
        let warning: String?
        if state.isManaged {
            warning = "Handoff is managed by your organization"
        } else if !state.didSynchronize {
            warning = "Handoff status could not be refreshed"
        } else if !state.notificationContractAvailable {
            warning = "Handoff control is unavailable on this macOS version"
        } else if !state.isConsistent {
            warning = "Handoff settings are inconsistent; toggle to repair them"
        } else if !state.observesExternalChanges {
            warning = "Automatic Handoff status updates are unavailable; use Refresh"
        } else {
            warning = nil
        }

        return SwitchSnapshot(
            isOn: state.isEnabled,
            isAvailable: state.isAvailable,
            subtitle: nil,
            warning: warning
        )
    }

    func setEnabled(_ enabled: Bool) -> String? {
        lock.withLock {
            guard client.synchronize() else {
                return "Handoff settings could not be refreshed. No changes were made."
            }

            let originalAdvertising = client.rawValue(for: .advertising)
            let originalReceiving = client.rawValue(for: .receiving)
            let initial = readState(synchronize: false)
            guard !initial.isManaged else {
                return "Handoff is managed by your organization."
            }
            guard initial.isEnabled != enabled || !initial.isConsistent else {
                return nil
            }
            guard initial.notificationContractAvailable else {
                return "Handoff control is unavailable on this macOS version. Use AirDrop & Handoff in System Settings."
            }

            client.setRawValues(advertising: enabled, receiving: enabled)

            guard client.synchronize() else {
                return rollback(
                    advertising: originalAdvertising,
                    receiving: originalReceiving,
                    reason: "preferences could not be saved"
                )
            }

            let updated = readState(synchronize: false)
            guard state(updated, matches: enabled) else {
                return rollback(
                    advertising: originalAdvertising,
                    receiving: originalReceiving,
                    reason: "macOS did not apply both Handoff settings"
                )
            }

            guard client.postChangeNotification() else {
                return rollback(
                    advertising: originalAdvertising,
                    receiving: originalReceiving,
                    reason: "the Handoff service could not be notified"
                )
            }

            waitForPropagation()
            guard client.synchronize() else {
                return rollback(
                    advertising: originalAdvertising,
                    receiving: originalReceiving,
                    reason: "the updated Handoff status could not be verified"
                )
            }
            let verified = readState(synchronize: false)
            guard state(verified, matches: enabled) else {
                return rollback(
                    advertising: originalAdvertising,
                    receiving: originalReceiving,
                    reason: "the Handoff setting did not remain applied"
                )
            }

            handoffLogger.info("Handoff changed to enabled=\(enabled, privacy: .public)")
            return nil
        }
    }

    private func readState(synchronize: Bool) -> HandoffPreferenceState {
        let didSynchronize = synchronize ? client.synchronize() : true
        let rawAdvertising = client.rawValue(for: .advertising)
        let rawReceiving = client.rawValue(for: .receiving)
        let advertising = HandoffStatePolicy.effectiveValue(
            client.effectiveValue(for: .advertising) ?? rawAdvertising
        )
        let receiving = HandoffStatePolicy.effectiveValue(
            client.effectiveValue(for: .receiving) ?? rawReceiving
        )
        return HandoffPreferenceState(
            rawAdvertising: rawAdvertising,
            rawReceiving: rawReceiving,
            advertising: advertising,
            receiving: receiving,
            isManaged: client.isForced(.advertising) || client.isForced(.receiving),
            didSynchronize: didSynchronize,
            notificationContractAvailable: client.supportsChangeNotification,
            observesExternalChanges: observationRegistrationSucceeded != false
        )
    }

    private func state(_ state: HandoffPreferenceState, matches enabled: Bool) -> Bool {
        state.rawAdvertising == enabled
            && state.rawReceiving == enabled
            && state.advertising == enabled
            && state.receiving == enabled
    }

    private func rollback(advertising: Bool?, receiving: Bool?, reason: String) -> String {
        client.setRawValues(advertising: advertising, receiving: receiving)
        let synchronized = client.synchronize()
        let valuesRestored = client.rawValue(for: .advertising) == advertising
            && client.rawValue(for: .receiving) == receiving
        let serviceNotified = client.postChangeNotification()
        let restored = synchronized && valuesRestored && serviceNotified

        handoffLogger.error(
            "Handoff update failed: \(reason, privacy: .public); rollback=\(restored, privacy: .public)"
        )
        if restored {
            return "Handoff could not be updated. Previous settings were restored."
        }
        return "Handoff could not be updated, and the previous settings could not be fully restored. Check AirDrop & Handoff in System Settings."
    }
}
