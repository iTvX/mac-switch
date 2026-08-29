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

    var isEnabled: Bool {
        advertising && receiving
    }

    var isConsistent: Bool {
        advertising == receiving
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
    func synchronize() -> Bool
    func rawValue(for key: HandoffPreferenceKey) -> Bool?
    func effectiveValue(for key: HandoffPreferenceKey) -> Bool?
    func isForced(_ key: HandoffPreferenceKey) -> Bool
    func setRawValue(_ value: Bool?, for key: HandoffPreferenceKey)
    func postChangeNotification() -> Bool
}

private enum HandoffDarwinNotification {
    private static let fallbackName = "LSUserActivityManagerActivityContinuationIsEnabledChangedNotification"
    private static let userActivityFramework = "/System/Library/PrivateFrameworks/UserActivity.framework/UserActivity"
    private static let exportedName = "UAUserActivityManagerActivityContinuationIsEnabledChangedNotification"

    static let name: String = {
        guard let handle = dlopen(userActivityFramework, RTLD_LAZY) else {
            return fallbackName
        }
        defer { dlclose(handle) }
        guard let symbol = dlsym(handle, exportedName) else {
            return fallbackName
        }
        guard let pointer = symbol.load(as: Optional<UnsafePointer<CChar>>.self) else {
            return fallbackName
        }
        let resolved = String(cString: pointer)
        return resolved.isEmpty ? fallbackName : resolved
    }()

    static func post() -> Bool {
        name.withCString { MSNotifyPost($0) == 0 }
    }
}

private final class CoreFoundationHandoffPreferencesClient: HandoffPreferencesClientProtocol, @unchecked Sendable {
    private let domain = "com.apple.coreservices.useractivityd" as CFString

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

    func setRawValue(_ value: Bool?, for key: HandoffPreferenceKey) {
        let preferenceValue: CFPropertyList?
        if let value {
            preferenceValue = value ? kCFBooleanTrue : kCFBooleanFalse
        } else {
            preferenceValue = nil
        }
        CFPreferencesSetValue(
            key.rawValue as CFString,
            preferenceValue,
            domain,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        )
    }

    func postChangeNotification() -> Bool {
        HandoffDarwinNotification.post()
    }

    private func booleanValue(_ value: CFPropertyList?) -> Bool? {
        guard let value, CFGetTypeID(value as CFTypeRef) == CFBooleanGetTypeID() else {
            return nil
        }
        return CFBooleanGetValue(unsafeDowncast(value, to: CFBoolean.self))
    }
}

private final class HandoffNotificationObserver: @unchecked Sendable {
    private var token: Int32 = -1

    init?(handler: @escaping @Sendable () -> Void) {
        var registeredToken: Int32 = -1
        let status = HandoffDarwinNotification.name.withCString { name in
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
    private let lock = NSLock()
    private var notificationObserver: HandoffNotificationObserver?

    init(client: any HandoffPreferencesClientProtocol = CoreFoundationHandoffPreferencesClient()) {
        self.client = client
    }

    func observeStatusChanges(_ handler: @escaping @Sendable () -> Void) {
        notificationObserver = HandoffNotificationObserver(handler: handler)
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
        } else if !state.isConsistent {
            warning = "Handoff settings are inconsistent; toggle to repair them"
        } else {
            warning = nil
        }

        return SwitchSnapshot(
            isOn: state.isEnabled,
            isAvailable: !state.isManaged,
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

            client.setRawValue(enabled, for: .advertising)
            client.setRawValue(enabled, for: .receiving)

            guard client.synchronize() else {
                return rollback(
                    advertising: originalAdvertising,
                    receiving: originalReceiving,
                    reason: "preferences could not be saved"
                )
            }

            let updated = readState(synchronize: false)
            guard updated.rawAdvertising == enabled,
                  updated.rawReceiving == enabled,
                  updated.advertising == enabled,
                  updated.receiving == enabled
            else {
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
            didSynchronize: didSynchronize
        )
    }

    private func rollback(advertising: Bool?, receiving: Bool?, reason: String) -> String {
        client.setRawValue(advertising, for: .advertising)
        client.setRawValue(receiving, for: .receiving)
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
