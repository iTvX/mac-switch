import XCTest
@testable import MacSwitch

final class DoNotDisturbBehaviorTests: XCTestCase {
    func testShortcutPathStillRequiresSharedFocusPermission() {
        for authorization in [FocusStatusAuthorization.notDetermined, .restricted, .denied] {
            let provider = FakeFocusStatusProvider(authorization: authorization, isFocused: nil)
            let subject = DoNotDisturbSwitch(focusStatusProvider: provider, controlCenter: FakeDoNotDisturbController(isAvailable: false))
            XCTAssertFalse(subject.snapshot().isAvailable)
            XCTAssertEqual(subject.snapshot().subtitle, "Focus status permission required")
        }
    }

    func testShortcutPathDoesNotPretendUnknownFocusStateIsOff() {
        let subject = DoNotDisturbSwitch(
            focusStatusProvider: FakeFocusStatusProvider(isFocused: nil),
            controlCenter: FakeDoNotDisturbController(isAvailable: false)
        )
        XCTAssertFalse(subject.snapshot().isAvailable)
        XCTAssertEqual(subject.snapshot().subtitle, "Focus status unavailable")
    }

    func testNativePathDoesNotRequireSharedFocusPermission() {
        let provider = FakeFocusStatusProvider(authorization: .denied, isFocused: nil)
        let native = FakeDoNotDisturbController()
        let subject = DoNotDisturbSwitch(focusStatusProvider: provider, controlCenter: native, hasCustomShortcuts: { false })
        XCTAssertTrue(subject.snapshot().isAvailable)
        XCTAssertEqual(subject.snapshot().subtitle, "Checked when used")
        XCTAssertFalse(subject.snapshotForAction().isOn)
        let result = subject.set(true)
        XCTAssertNil(result.error)
        XCTAssertTrue(result.snapshot.isOn)
        XCTAssertEqual(provider.readCount, 0)
    }

    func testVerifiedResultSurvivesFalseSharedFocusStatusAndPassiveRefresh() {
        let native = FakeDoNotDisturbController()
        let provider = FakeFocusStatusProvider(isFocused: false)
        let subject = DoNotDisturbSwitch(focusStatusProvider: provider, controlCenter: native, hasCustomShortcuts: { false })
        let controller = SystemSwitchController(doNotDisturb: subject)

        let result = controller.set(.doNotDisturb, enabled: true, keepAwakeDuration: .indefinitely)

        XCTAssertNil(result.error)
        XCTAssertTrue(result.snapshot.isOn, "The controller must return the actual checkbox observation, not re-read shared Focus status")
        XCTAssertTrue(controller.snapshot(for: .doNotDisturb, keepAwakeDuration: .indefinitely).isOn)
        XCTAssertEqual(provider.readCount, 0)
        XCTAssertEqual(native.readCount, 0, "Passive refreshes must not open Control Center")
    }

    func testActionPreflightRechecksExternalChangesInsteadOfUsingLastObservation() {
        let native = FakeDoNotDisturbController()
        let subject = nativeSwitch(native)
        XCTAssertNil(subject.set(true).error)
        native.actualState = false // Changed outside Mac Switch.
        XCTAssertTrue(subject.snapshot().isOn)
        XCTAssertFalse(subject.snapshotForAction().isOn)
        XCTAssertFalse(subject.snapshot().isOn)
        XCTAssertEqual(native.readCount, 1)
    }

    func testUnconfirmedWriteCannotReportRequestedStateAsSuccess() {
        let native = FakeDoNotDisturbController()
        native.error = "macOS did not confirm the Do Not Disturb change."
        let result = nativeSwitch(native).set(true)
        XCTAssertEqual(result.error, native.error)
        XCTAssertFalse(result.snapshot.isAvailable)
        XCTAssertFalse(result.snapshot.isOn)
    }

    func testMissingWriteObservationIsAnErrorEvenWithoutBackendError() {
        let native = FakeDoNotDisturbController()
        native.omitObservation = true
        let result = nativeSwitch(native).set(true)
        XCTAssertNotNil(result.error)
        XCTAssertFalse(result.snapshot.isAvailable)
    }

    func testExplicitShortcutConfigurationDoesNotSilentlyUseNativeBackend() {
        let native = FakeDoNotDisturbController()
        let subject = DoNotDisturbSwitch(
            focusStatusProvider: FakeFocusStatusProvider(isFocused: true),
            controlCenter: native,
            hasCustomShortcuts: { true }
        )
        XCTAssertNil(subject.setEnabled(true))
        XCTAssertTrue(native.requests.isEmpty)
        XCTAssertEqual(native.readCount, 0)
    }

    @MainActor
    func testModeStartsAndRestoresThroughRealSystemControllerWithUnsharedFocus() async throws {
        let native = FakeDoNotDisturbController()
        let controller = SystemSwitchController(doNotDisturb: nativeSwitch(native))
        let store = SwitchStore(controller: controller, defaults: InMemoryUserDefaults(), enableRuntimeServices: false)
        let mode = try makeMode(store)

        store.toggleMode(mode)
        try await waitUntil { store.activeModeOperationID == nil }
        XCTAssertNil(store.lastError)
        XCTAssertTrue(store.isModeActive(mode.id))
        XCTAssertTrue(native.actualState)
        XCTAssertEqual(store.snapshots[.doNotDisturb]?.isOn, true)
        XCTAssertEqual(store.activeModeSessions[mode.id]?.originalState(for: .doNotDisturb), false)

        store.toggleMode(mode)
        try await waitUntil { store.activeModeOperationID == nil }
        XCTAssertNil(store.lastError)
        XCTAssertFalse(store.isModeActive(mode.id))
        XCTAssertFalse(native.actualState)
        XCTAssertEqual(native.requests, [true, false])
        XCTAssertEqual(native.readCount, 2)
    }

    @MainActor
    func testModePreservesDNDThatWasAlreadyOnDespiteFalseSharedStatus() async throws {
        let native = FakeDoNotDisturbController()
        native.actualState = true
        let store = SwitchStore(controller: SystemSwitchController(doNotDisturb: nativeSwitch(native)), defaults: InMemoryUserDefaults(), enableRuntimeServices: false)
        let mode = try makeMode(store)
        store.toggleMode(mode)
        try await waitUntil { store.activeModeOperationID == nil }
        XCTAssertTrue(store.isModeActive(mode.id))
        XCTAssertEqual(store.activeModeSessions[mode.id]?.originalState(for: .doNotDisturb), true)
        store.toggleMode(mode)
        try await waitUntil { store.activeModeOperationID == nil }
        XCTAssertNil(store.lastError)
        XCTAssertTrue(native.actualState)
        XCTAssertTrue(native.requests.isEmpty)
    }

    @MainActor
    func testModeRestorationRechecksExternalDNDChanges() async throws {
        let native = FakeDoNotDisturbController()
        let store = SwitchStore(controller: SystemSwitchController(doNotDisturb: nativeSwitch(native)), defaults: InMemoryUserDefaults(), enableRuntimeServices: false)
        let mode = try makeMode(store)
        store.toggleMode(mode)
        try await waitUntil { store.activeModeOperationID == nil }
        native.actualState = false
        store.toggleMode(mode)
        try await waitUntil { store.activeModeOperationID == nil }
        XCTAssertNil(store.lastError)
        XCTAssertFalse(native.actualState)
        XCTAssertEqual(native.requests, [true], "Restoration should not toggle DND back on after an external change")
    }

    @MainActor
    func testLiveModeActivationAndRestoration() async throws {
        guard ProcessInfo.processInfo.environment["MAC_SWITCH_LIVE_DND_TEST"] == "1" else {
            throw XCTSkip("Opt in on an interactive Mac to verify real DND state changes")
        }
        let native = ControlCenterFocusController()
        guard native.isAvailable else { throw XCTSkip("Accessibility access is required") }
        let initial = try XCTUnwrap(native.readState().state)
        defer { XCTAssertNil(native.setEnabled(initial).error, "Restore the original system state") }
        // Hold the shared Focus reading false throughout, reproducing the report.
        let dnd = DoNotDisturbSwitch(focusStatusProvider: FakeFocusStatusProvider(isFocused: false), controlCenter: native, hasCustomShortcuts: { false })
        let store = SwitchStore(controller: SystemSwitchController(doNotDisturb: dnd), defaults: InMemoryUserDefaults(), enableRuntimeServices: false)
        var mode = try makeMode(store)
        mode.items = [SwitchModeItem(kind: .doNotDisturb, targetIsOn: !initial)]
        store.updateCustomMode(mode)

        store.toggleMode(mode)
        try await waitUntil(timeout: 15) { store.activeModeOperationID == nil }
        XCTAssertNil(store.lastError)
        XCTAssertTrue(store.isModeActive(mode.id))
        XCTAssertEqual(native.readState().state, !initial)
        XCTAssertEqual(store.snapshots[.doNotDisturb]?.isOn, !initial)
        guard store.isModeActive(mode.id) else { return }

        store.toggleMode(mode)
        try await waitUntil(timeout: 15) { store.activeModeOperationID == nil }
        XCTAssertNil(store.lastError)
        XCTAssertFalse(store.isModeActive(mode.id))
        XCTAssertEqual(native.readState().state, initial)
        print("LIVE DND MODE: initial=\(initial), active=\(!initial), restored=\(initial), sharedFocus=false")
    }

    private func nativeSwitch(_ native: FakeDoNotDisturbController) -> DoNotDisturbSwitch {
        DoNotDisturbSwitch(focusStatusProvider: FakeFocusStatusProvider(isFocused: false), controlCenter: native, hasCustomShortcuts: { false })
    }

    @MainActor
    private func makeMode(_ store: SwitchStore) throws -> SwitchModeDefinition {
        let id = store.createCustomMode()
        var mode = try XCTUnwrap(store.customModes.first { $0.id == id })
        mode.title = "Interview"
        mode.items = [SwitchModeItem(kind: .doNotDisturb, targetIsOn: true)]
        store.updateCustomMode(mode)
        return mode
    }

    @MainActor
    private func waitUntil(timeout: TimeInterval = 4, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(condition(), "Mode operation did not finish")
    }
}

private final class FakeDoNotDisturbController: DoNotDisturbControlling, @unchecked Sendable {
    let isAvailable: Bool
    private let lock = NSLock()
    private var state = false
    private var confirmed: Bool?
    private var requested: [Bool] = []
    private var reads = 0
    // Configured before concurrent test operations start.
    var error: String?
    var omitObservation = false
    var actualState: Bool {
        get { lock.withLock { state } }
        set { lock.withLock { state = newValue } }
    }
    var lastConfirmedState: Bool? { lock.withLock { confirmed } }
    var requests: [Bool] { lock.withLock { requested } }
    var readCount: Int { lock.withLock { reads } }
    init(isAvailable: Bool = true) { self.isAvailable = isAvailable }
    func readState() -> DoNotDisturbControlResult {
        lock.withLock {
            reads += 1
            confirmed = state
            return DoNotDisturbControlResult(state: state, error: nil)
        }
    }
    func setEnabled(_ enabled: Bool) -> DoNotDisturbControlResult {
        lock.withLock {
            requested.append(enabled)
            if error != nil || omitObservation { return DoNotDisturbControlResult(state: nil, error: error) }
            state = enabled
            confirmed = state
            return DoNotDisturbControlResult(state: state, error: nil)
        }
    }
}

private final class FakeFocusStatusProvider: FocusStatusProviding, @unchecked Sendable {
    private let lock = NSLock()
    private let reading: FocusStatusReading
    private var reads = 0
    var readCount: Int { lock.withLock { reads } }
    init(authorization: FocusStatusAuthorization = .authorized, isFocused: Bool?) {
        reading = FocusStatusReading(authorization: authorization, isFocused: isFocused)
    }
    func read() -> FocusStatusReading {
        lock.withLock { reads += 1; return reading }
    }
}
