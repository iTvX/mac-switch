import Foundation
import XCTest
@testable import MacSwitch

@MainActor
final class ModeRecoveryBehaviorTests: XCTestCase {
    func testModeRestoresMicrophoneAAfterDefaultMovesToB() async throws {
        let controller = RecoveryController()
        controller.microphones.add(1, uid: "A", channels: 8, mute: true)
        controller.microphones.add(2, uid: "B", channels: 2, mute: true)
        XCTAssertNil(controller.microphone.setEnabled(true))
        let store = SwitchStore(controller: controller, defaults: InMemoryUserDefaults(), enableRuntimeServices: false)
        let mode = try makeMode(store, [.init(kind: .muteMicrophone, targetIsOn: false)])
        store.toggleMode(mode)
        try await idle(store)
        XCTAssertTrue(store.isModeActive(mode.id))
        XCTAssertTrue(controller.microphones.values(.mute, device: 1).values.allSatisfy { $0 == 0 })
        controller.microphones.defaultInput = 2
        store.toggleMode(mode)
        try await idle(store)
        XCTAssertFalse(store.hasModeSession(mode.id))
        XCTAssertNil(store.lastError)
        XCTAssertTrue(controller.microphones.values(.mute, device: 1).values.allSatisfy { $0 == 1 })
        XCTAssertTrue(controller.microphones.values(.mute, device: 2).values.allSatisfy { $0 == 0 })
    }

    func testDisconnectedDeviceKeepsJournalAcrossRelaunchUntilReconnect() async throws {
        let controller = RecoveryController(), defaults = InMemoryUserDefaults()
        controller.microphones.add(1, uid: "A", channels: 2, mute: true)
        controller.microphones.add(2, uid: "B", channels: 2, mute: true)
        let store = SwitchStore(controller: controller, defaults: defaults, enableRuntimeServices: false)
        let mode = try makeMode(store, [.init(kind: .muteMicrophone, targetIsOn: true)])
        store.toggleMode(mode)
        try await idle(store)
        controller.microphones.disconnect(1)
        controller.microphones.defaultInput = 2
        store.toggleMode(mode)
        try await idle(store)
        XCTAssertNotNil(store.lastError)
        XCTAssertTrue(store.hasModeSession(mode.id))
        XCTAssertFalse(store.isModeActive(mode.id))
        XCTAssertEqual(try sessions(defaults).first?.phase, .restoring)
        let restarted = SwitchStore(controller: controller, defaults: defaults, enableRuntimeServices: false)
        controller.microphones.add(9, uid: "A", channels: 2, mute: true)
        _ = controller.microphones.write(.mute, device: 9, element: 1, value: 1)
        restarted.recoverInterruptedMode()
        try await idle(restarted)
        XCTAssertFalse(restarted.hasModeSession(mode.id))
        XCTAssertTrue(controller.microphones.values(.mute, device: 9).values.allSatisfy { $0 == 0 })
        XCTAssertFalse(controller.microphones.writes.contains { $0.device == 2 })
    }

    func testInterruptedActivationIsJournaledBeforeMutationAndRecoveredOnRelaunch() async throws {
        let controller = RecoveryController(), defaults = InMemoryUserDefaults()
        controller.blockedKind = .stageManager
        let store = SwitchStore(controller: controller, defaults: defaults, enableRuntimeServices: false)
        let mode = try makeMode(store, [.init(kind: .darkMode, targetIsOn: true), .init(kind: .stageManager, targetIsOn: true)])
        store.toggleMode(mode)
        defer { controller.gate.signal() }
        try await wait { controller.isBlocked }
        XCTAssertTrue(controller.value(.darkMode))
        let saved = try XCTUnwrap(sessions(defaults).first)
        XCTAssertEqual(saved.phase, .activating)
        XCTAssertEqual(Set(saved.attemptedKinds ?? []), [.darkMode, .stageManager], "The in-flight write must already be journaled")
        let copied = InMemoryUserDefaults()
        for (key, value) in defaults.dictionaryRepresentation() { copied.set(value, forKey: key) }
        let afterCrash = RecoveryController()
        afterCrash.change(.darkMode, true)
        // The OS could accept the second write immediately before the process died.
        afterCrash.change(.stageManager, true)
        let restarted = SwitchStore(controller: afterCrash, defaults: copied, enableRuntimeServices: false)
        XCTAssertFalse(restarted.isModeActive(mode.id))
        XCTAssertNotNil(restarted.lastError)
        restarted.recoverInterruptedMode()
        try await idle(restarted)
        XCTAssertFalse(afterCrash.value(.darkMode))
        XCTAssertFalse(afterCrash.value(.stageManager))
        XCTAssertTrue(try sessions(copied).isEmpty)
    }

    func testRetryRestoresOnlyUnfinishedSteps() async throws {
        let controller = RecoveryController(), defaults = InMemoryUserDefaults()
        let store = SwitchStore(controller: controller, defaults: defaults, enableRuntimeServices: false)
        let mode = try makeMode(store, [.init(kind: .darkMode, targetIsOn: true), .init(kind: .stageManager, targetIsOn: true)])
        store.toggleMode(mode)
        try await idle(store)
        controller.fail(.stageManager, target: false)
        store.toggleMode(mode)
        try await idle(store)
        XCTAssertFalse(controller.value(.darkMode))
        XCTAssertTrue(controller.value(.stageManager))
        XCTAssertEqual(try sessions(defaults).first?.pendingRestorationKinds, [.stageManager])
        controller.change(.darkMode, true) // An independent user change after successful restoration.
        controller.fail(.stageManager, target: nil)
        let restarted = SwitchStore(controller: controller, defaults: defaults, enableRuntimeServices: false)
        restarted.recoverInterruptedMode()
        try await idle(restarted)
        XCTAssertTrue(controller.value(.darkMode), "Do not replay an already-completed restoration")
        XCTAssertFalse(controller.value(.stageManager))
        XCTAssertTrue(try sessions(defaults).isEmpty)
    }

    func testOldDeviceSessionNeverGuessesTheCurrentDevice() async throws {
        let controller = RecoveryController(), defaults = InMemoryUserDefaults()
        controller.microphones.add(1, uid: "B", channels: 2, mute: true)
        let originalStore = SwitchStore(controller: controller, defaults: defaults, enableRuntimeServices: false)
        let mode = try makeMode(originalStore, [.init(kind: .muteMicrophone, targetIsOn: false), .init(kind: .darkMode, targetIsOn: true)])
        let legacy = "[{\"modeID\":\"\(mode.id.rawValue)\",\"rawOriginalStates\":{\"muteMicrophone\":true,\"darkMode\":false}}]"
        defaults.set(Data(legacy.utf8), forKey: "switch.modes.activeSessions")
        controller.change(.darkMode, true)
        let restarted = SwitchStore(controller: controller, defaults: defaults, enableRuntimeServices: false)
        XCTAssertTrue(restarted.modeNeedsManualRecovery(mode.id))
        restarted.recoverInterruptedMode()
        try await idle(restarted)
        XCTAssertTrue(restarted.hasModeSession(mode.id))
        XCTAssertTrue(controller.microphones.writes.isEmpty)
        XCTAssertFalse(controller.value(.darkMode))
        restarted.confirmManualModeRecovery(mode.id)
        try await idle(restarted)
        XCTAssertFalse(restarted.hasModeSession(mode.id))
        XCTAssertTrue(controller.microphones.writes.isEmpty)
    }

    func testMissingDeviceIdentityAbortsBeforeAnyModeWrite() async throws {
        let controller = RecoveryController()
        controller.microphones.add(1, uid: "", channels: 2, mute: true)
        let store = SwitchStore(controller: controller, defaults: InMemoryUserDefaults(), enableRuntimeServices: false)
        let mode = try makeMode(store, [.init(kind: .darkMode, targetIsOn: true), .init(kind: .muteMicrophone, targetIsOn: true)])
        store.toggleMode(mode)
        try await idle(store)
        XCTAssertFalse(store.hasModeSession(mode.id))
        XCTAssertNotNil(store.lastError)
        XCTAssertTrue(controller.requests.isEmpty)
        XCTAssertTrue(controller.microphones.writes.isEmpty)
    }

    func testRetiredPresetWithUnknownDeviceGetsAVisibleRecoveryEntry() async throws {
        let controller = RecoveryController(), defaults = InMemoryUserDefaults()
        controller.microphones.add(1, uid: "B", channels: 2, mute: true)
        controller.change(.darkMode, true)
        defaults.set(Data(#"[{"modeID":"focus","rawOriginalStates":{"muteMicrophone":true,"darkMode":false}}]"#.utf8), forKey: "switch.modes.activeSessions")
        let store = SwitchStore(controller: controller, defaults: defaults, enableRuntimeServices: false)
        let recovery = try XCTUnwrap(store.visibleModes.first)
        XCTAssertTrue(recovery.id.rawValue.hasPrefix("custom.recovery."))
        XCTAssertTrue(store.modeNeedsManualRecovery(recovery.id))
        // Relaunch during migration must reuse the entry and retain the complete journal.
        let restarted = SwitchStore(controller: controller, defaults: defaults, enableRuntimeServices: false)
        XCTAssertEqual(restarted.visibleModes.map(\.id), [recovery.id])
        restarted.recoverInterruptedMode()
        try await idle(restarted)
        XCTAssertFalse(controller.value(.darkMode))
        XCTAssertTrue(controller.microphones.writes.isEmpty)
        restarted.confirmManualModeRecovery(recovery.id)
        try await idle(restarted)
        XCTAssertTrue(restarted.customModes.isEmpty)
        XCTAssertTrue(try sessions(defaults).isEmpty)
    }

    func testBlockedPowerAuthorizationAllowsKeepAwakeStopAndMicButReservesOtherPowerActions() async throws {
        let controller = RecoveryController()
        controller.microphones.add(1, uid: "A", channels: 2, mute: true)
        controller.blockedKind = .energyMode
        let store = SwitchStore(controller: controller, defaults: InMemoryUserDefaults(), enableRuntimeServices: false)
        store.set(.energyMode, enabled: true)
        defer { controller.gate.signal() }
        try await wait { controller.isBlocked }
        store.set(.keepAwake, enabled: false)
        store.set(.muteMicrophone, enabled: true)
        store.set(.lowPowerMode, enabled: true)
        try await wait { controller.requests.contains(.keepAwake) && controller.microphone.snapshot().isOn }
        XCTAssertTrue(store.isActionBusy(.energyMode))
        XCTAssertFalse(controller.requests.contains(.lowPowerMode))
    }

    private func makeMode(_ store: SwitchStore, _ items: [SwitchModeItem]) throws -> SwitchModeDefinition {
        let id = store.createCustomMode()
        var mode = try XCTUnwrap(store.customModes.first { $0.id == id })
        mode.items = items
        store.updateCustomMode(mode)
        return mode
    }
    private func sessions(_ defaults: UserDefaults) throws -> [ActiveSwitchModeSession] {
        try JSONDecoder().decode([ActiveSwitchModeSession].self, from: XCTUnwrap(defaults.data(forKey: "switch.modes.activeSessions")))
    }
    private func idle(_ store: SwitchStore) async throws { try await wait { !store.hasBusyActions } }
    private func wait(_ condition: @escaping @MainActor () -> Bool) async throws {
        for _ in 0..<250 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Operation did not finish within 2.5 seconds")
    }
}

private final class RecoveryController: SystemSwitchControlling, @unchecked Sendable {
    var onExternalChange: (@Sendable (SwitchKind) -> Void)?
    private let lock = NSLock()
    let microphones: MemoryMicrophones
    let microphone: MuteMicrophoneSwitch
    init() {
        let driver = MemoryMicrophones()
        microphones = driver
        microphone = MuteMicrophoneSwitch(access: driver, defaults: InMemoryUserDefaults())
    }
    private var states: [SwitchKind: Bool] = [:]
    private var failures: [SwitchKind: Bool] = [:]
    private var recorded: [SwitchKind] = []
    private var waiting = false
    var blockedKind: SwitchKind?
    let gate = DispatchSemaphore(value: 0)
    var isBlocked: Bool { lock.withLock { waiting } }
    var requests: [SwitchKind] { lock.withLock { recorded } }
    func value(_ kind: SwitchKind) -> Bool { lock.withLock { states[kind] ?? false } }
    func change(_ kind: SwitchKind, _ enabled: Bool) { lock.withLock { states[kind] = enabled } }
    func fail(_ kind: SwitchKind, target: Bool?) { lock.withLock { failures[kind] = target } }
    func snapshot(for kind: SwitchKind, keepAwakeDuration: KeepAwakeDuration) -> SwitchSnapshot {
        if kind == .muteMicrophone { return microphone.snapshot() }
        return .init(isOn: value(kind), isAvailable: true, subtitle: nil, warning: nil)
    }
    func captureDeviceRestorePoint(for kind: SwitchKind) -> DeviceModeRestorePoint? {
        kind == .muteMicrophone ? microphone.captureRestorePoint().map { .microphone($0) } : nil
    }
    func setDevice(_ point: DeviceModeRestorePoint, kind: SwitchKind, enabled: Bool, duration: KeepAwakeDuration) -> SwitchOperationResult {
        guard case .microphone(let point) = point else { return .init(snapshot: .off, error: "Unexpected device") }
        let error = microphone.setEnabled(enabled, boundTo: point)
        return .init(snapshot: microphone.snapshot(), error: error)
    }
    func restoreDevice(_ point: DeviceModeRestorePoint, kind: SwitchKind, duration: KeepAwakeDuration) -> SwitchOperationResult {
        guard case .microphone(let point) = point else { return .init(snapshot: .off, error: "Unexpected device") }
        let error = microphone.restore(point)
        return .init(snapshot: microphone.snapshot(), error: error)
    }
    func set(_ kind: SwitchKind, enabled: Bool, keepAwakeDuration: KeepAwakeDuration) -> SwitchOperationResult {
        lock.withLock { recorded.append(kind) }
        if blockedKind == kind { lock.withLock { waiting = true }; _ = gate.wait(timeout: .now() + 5) }
        var error: String?
        if kind == .muteMicrophone { error = microphone.setEnabled(enabled) }
        else if lock.withLock({ failures[kind] == enabled }) { error = "Injected failure" }
        else { change(kind, enabled) }
        return .init(snapshot: snapshot(for: kind, keepAwakeDuration: keepAwakeDuration), error: error)
    }
    func setKeepAwake(enabled: Bool, duration: TimeInterval?, defaultDuration: KeepAwakeDuration) -> SwitchOperationResult { set(.keepAwake, enabled: enabled, keepAwakeDuration: defaultDuration) }
    func performXcodeClean(progress: @escaping @Sendable (Double) -> Void) -> SwitchOperationResult { .init(snapshot: .off, error: nil) }
    func prepareForTermination() {}
}
