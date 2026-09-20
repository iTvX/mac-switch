import XCTest
@testable import MacSwitch

final class DoNotDisturbBehaviorTests: XCTestCase {
    func testBundledWorkflowsHaveReadOnlyBranchAndExplicitOutputs() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for role in DNDShortcut.allCases {
            let path = root.appendingPathComponent("Resources/Shortcuts/\(role.name).wflow")
            let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(contentsOf: path), format: nil) as? [String: Any])
            let actions = try XCTUnwrap(plist["WFWorkflowActions"] as? [[String: Any]])
            let parameters = actions.compactMap { $0["WFWorkflowActionParameters"] as? [String: Any] }
            XCTAssertEqual(actions.count, 11)
            let input = try XCTUnwrap(parameters[0]["WFInput"] as? [String: Any])
            let variable = try XCTUnwrap(input["Variable"] as? [String: Any])
            XCTAssertEqual((variable["Value"] as? [String: String])?["Type"], "ExtensionInput")
            XCTAssertEqual(parameters[1]["WFControlFlowMode"] as? Int, 1, "Only the no-input branch can change DND")
            XCTAssertEqual(actions[2]["WFWorkflowActionIdentifier"] as? String, "is.workflow.actions.dnd.set")
            XCTAssertEqual(parameters[2]["Enabled"] as? Int, role == .enable ? 1 : 0)
            XCTAssertEqual(actions[4]["WFWorkflowActionIdentifier"] as? String, "is.workflow.actions.dnd.getfocus")
            for index in [7, 9] {
                XCTAssertEqual(actions[index]["WFWorkflowActionIdentifier"] as? String, "is.workflow.actions.output")
            }
            XCTAssertEqual(parameters[9]["WFOutput"] as? String, role.outputPrefix)
            let output = try XCTUnwrap(parameters[7]["WFOutput"] as? [String: Any])
            XCTAssertEqual(output["WFSerializationType"] as? String, "WFTextTokenString")
            XCTAssertEqual((output["Value"] as? [String: Any])?["string"] as? String, role.outputPrefix + "\u{fffc}")
        }
    }

    func testInstallationRejectsLegacyAmbiguousAndInvalidIdentifiers() {
        let fake = FakeDNDExecutor()
        let listing = fake.listing
        XCTAssertEqual(DNDShortcutInstallation.parse(listing).count, 2)
        XCTAssertEqual(DNDShortcutInstallation.parse(listing + "\n" + listing).count, 0)
        XCTAssertTrue(DNDShortcutInstallation.parse("Mac Switch DND On (\(fake.onID))").isEmpty)
        XCTAssertTrue(DNDShortcutInstallation.parse("Mac Switch DND Enable (bad-id)").isEmpty)
    }

    func testOutputMustBeExplicitVersionedAndRoleMatched() throws {
        XCTAssertEqual(try DNDShortcut.enable.focusName(from: "mac-switch-dnd-v1|enable|勿扰模式\n"), "勿扰模式")
        XCTAssertEqual(try DNDShortcut.disable.focusName(from: "mac-switch-dnd-v1|disable|"), "")
        for text in ["", "Do Not Disturb", "mac-switch-dnd-v1|disable|", "mac-switch-dnd-v2|enable|"] {
            XCTAssertThrowsError(try DNDShortcut.enable.focusName(from: text))
        }
    }

    func testFirstVerificationCalibratesLocalizedNameAndRestoresOff() {
        let fake = FakeDNDExecutor()
        fake.dndName = "勿扰模式"
        let subject = DoNotDisturbShortcuts(executor: fake, defaults: InMemoryUserDefaults())
        XCTAssertFalse(subject.snapshot().isAvailable)
        XCTAssertTrue(fake.writes.isEmpty)
        XCTAssertNil(subject.verifySetup())
        XCTAssertEqual(fake.writes, [true, false])
        XCTAssertEqual(fake.focus, "")
        XCTAssertTrue(subject.installation().isVerified)
        XCTAssertNil(subject.set(true).error)
        XCTAssertEqual(fake.focus, "勿扰模式")
        XCTAssertTrue(subject.snapshot(force: true).isOn)
    }

    func testVerificationDoesNotDisturbAnExistingFocus() {
        let fake = FakeDNDExecutor()
        fake.focus = "Work"
        let subject = DoNotDisturbShortcuts(executor: fake, defaults: InMemoryUserDefaults())
        XCTAssertNotNil(subject.verifySetup())
        XCTAssertTrue(fake.writes.isEmpty)
        XCTAssertEqual(fake.focus, "Work")
    }

    func testFailedVerificationStillAttemptsRestoration() {
        let fake = FakeDNDExecutor()
        fake.invalidEnableOutput = true
        let subject = DoNotDisturbShortcuts(executor: fake, defaults: InMemoryUserDefaults())
        XCTAssertNotNil(subject.verifySetup())
        XCTAssertEqual(fake.writes, [true, false])
        XCTAssertEqual(fake.focus, "")
        XCTAssertFalse(subject.installation().isVerified)
    }

    func testReadFailureDoesNotReuseAConfirmedStateForAnAction() {
        let (subject, fake) = verified()
        XCTAssertNil(subject.set(true).error)
        fake.failRead = true
        XCTAssertFalse(subject.snapshot(force: true).isAvailable)
        fake.writes = []
        XCTAssertNotNil(subject.set(false).error)
        XCTAssertTrue(fake.writes.isEmpty)
    }

    func testSetupReportsFailedRestorationAndStaysUnverified() {
        let fake = FakeDNDExecutor()
        fake.failDisable = true
        let backend = DoNotDisturbShortcuts(executor: fake, defaults: InMemoryUserDefaults())
        XCTAssertTrue(backend.verifySetup()?.contains("Could not restore") == true)
        XCTAssertFalse(backend.installation().isVerified)
        XCTAssertEqual(fake.writes, [true, false])
    }

    func testMissingOrReinstalledHelpersRequireSetupAgain() {
        let (subject, fake) = verified()
        fake.listing = ""
        XCTAssertFalse(subject.snapshot(force: true).isAvailable)
        XCTAssertNotNil(subject.set(true).error)
        XCTAssertTrue(fake.writes.isEmpty)
        fake.listing = "\(DNDShortcut.enable.name) (\(UUID()))\n\(DNDShortcut.disable.name) (\(fake.offID))"
        XCTAssertFalse(subject.installation().isVerified)
    }

    func testFreshPreflightObservesExternalChangesAndOtherFocusIsProtected() {
        let (subject, fake) = verified()
        XCTAssertNil(subject.set(true).error)
        fake.focus = ""
        XCTAssertTrue(subject.snapshot().isOn)
        XCTAssertFalse(subject.snapshot(force: true).isOn)
        fake.focus = "Sleep"
        fake.writes = []
        XCTAssertFalse(subject.snapshot(force: true).isAvailable)
        XCTAssertNotNil(subject.set(true).error)
        XCTAssertNotNil(subject.set(false).error)
        XCTAssertEqual(fake.focus, "Sleep")
        XCTAssertTrue(fake.writes.isEmpty)
    }

    func testFailedOrUnconfirmedWritesNeverReportSuccess() {
        for failure in 0...2 {
            let (subject, fake) = verified()
            fake.invalidEnableOutput = failure == 0
            fake.failEnable = failure == 1
            fake.ignoreEnable = failure == 2
            let result = subject.set(true)
            XCTAssertNotNil(result.error)
            XCTAssertFalse(result.snapshot.isAvailable)
        }
    }

    @MainActor
    func testModeRoundTripRestoresBothInitialStates() async throws {
        for initial in [false, true] {
            let (backend, fake) = verified()
            fake.focus = initial ? fake.dndName : ""
            let store = SwitchStore(controller: SystemSwitchController(doNotDisturb: DoNotDisturbSwitch(shortcuts: backend)), defaults: InMemoryUserDefaults(), enableRuntimeServices: false)
            let mode = try makeMode(store)
            store.toggleMode(mode)
            try await waitUntil { store.activeModeOperationID == nil }
            XCTAssertNil(store.lastError)
            XCTAssertTrue(store.isModeActive(mode.id))
            XCTAssertEqual(store.activeModeSessions[mode.id]?.originalState(for: .doNotDisturb), initial)
            XCTAssertEqual(fake.focus, fake.dndName)
            store.toggleMode(mode)
            try await waitUntil { store.activeModeOperationID == nil }
            XCTAssertNil(store.lastError)
            XCTAssertFalse(store.isModeActive(mode.id))
            XCTAssertEqual(fake.focus, initial ? fake.dndName : "")
            XCTAssertEqual(fake.writes, initial ? [] : [true, false])
        }
    }

    @MainActor
    func testModeRestorationRechecksExternalChanges() async throws {
        let (backend, fake) = verified()
        let store = SwitchStore(controller: SystemSwitchController(doNotDisturb: DoNotDisturbSwitch(shortcuts: backend)), defaults: InMemoryUserDefaults(), enableRuntimeServices: false)
        let mode = try makeMode(store)
        store.toggleMode(mode)
        try await waitUntil { store.activeModeOperationID == nil }
        fake.focus = ""
        store.toggleMode(mode)
        try await waitUntil { store.activeModeOperationID == nil }
        XCTAssertNil(store.lastError)
        XCTAssertEqual(fake.writes, [true])
        XCTAssertEqual(fake.focus, "")
    }

    @MainActor
    func testLiveModeActivationAndRestoration() async throws {
        guard ProcessInfo.processInfo.environment["MAC_SWITCH_LIVE_DND_TEST"] == "1" else {
            throw XCTSkip("Opt in on an interactive Mac with the bundled helpers installed and Focus off")
        }
        let backend = DoNotDisturbShortcuts(defaults: InMemoryUserDefaults())
        XCTAssertNil(backend.verifySetup())
        guard backend.installation().isVerified else { return XCTFail("Live setup verification failed") }
        defer { XCTAssertNil(backend.set(false).error) }
        for initial in [false, true] {
            XCTAssertNil(backend.set(initial).error)
            let store = SwitchStore(controller: SystemSwitchController(doNotDisturb: DoNotDisturbSwitch(shortcuts: backend)), defaults: InMemoryUserDefaults(), enableRuntimeServices: false)
            let mode = try makeMode(store)
            store.toggleMode(mode)
            try await waitUntil(timeout: 45) { store.activeModeOperationID == nil }
            XCTAssertNil(store.lastError)
            XCTAssertTrue(store.isModeActive(mode.id))
            XCTAssertTrue(backend.snapshot(force: true).isOn)
            store.toggleMode(mode)
            try await waitUntil(timeout: 45) { store.activeModeOperationID == nil }
            XCTAssertNil(store.lastError)
            XCTAssertFalse(store.isModeActive(mode.id))
            XCTAssertEqual(backend.snapshot(force: true).isOn, initial)
            print("LIVE DND MODE: initial=\(initial), active=true, restored=\(initial)")
        }
    }

    private func verified() -> (DoNotDisturbShortcuts, FakeDNDExecutor) {
        let fake = FakeDNDExecutor()
        let backend = DoNotDisturbShortcuts(executor: fake, defaults: InMemoryUserDefaults())
        XCTAssertNil(backend.verifySetup())
        fake.writes = []
        return (backend, fake)
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
    private func waitUntil(timeout: TimeInterval = 5, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(condition(), "Mode operation did not finish")
    }
}

private final class FakeDNDExecutor: DNDShortcutExecuting, @unchecked Sendable {
    let onID = "00000000-0000-0000-0000-000000000001"
    let offID = "00000000-0000-0000-0000-000000000002"
    private let lock = NSLock()
    private var storedFocus = ""
    private var storedWrites: [Bool] = []
    var focus: String { get { lock.withLock { storedFocus } } set { lock.withLock { storedFocus = newValue } } }
    var writes: [Bool] { get { lock.withLock { storedWrites } } set { lock.withLock { storedWrites = newValue } } }
    // Test configuration is set before starting concurrent operations.
    var dndName = "Do Not Disturb"
    var listing: String
    var invalidEnableOutput = false
    var failRead = false
    var failDisable = false
    var failEnable = false
    var ignoreEnable = false
    init() { listing = "Mac Switch DND Enable (\(onID))\nMac Switch DND Disable (\(offID))" }
    func list() throws -> String { listing }
    func run(identifier: String, readOnly: Bool) throws -> String {
        try lock.withLock {
            let role: DNDShortcut = identifier == onID ? .enable : .disable
            if readOnly && failRead { throw DNDShortcutError("Do Not Disturb status unavailable.") }
            if !readOnly {
                storedWrites.append(role == .enable)
                if role == .disable && failDisable { throw DNDShortcutError("Do Not Disturb restoration failed.") }
                if role == .enable && failEnable { throw DNDShortcutError("Do Not Disturb shortcut timed out.") }
                if !(role == .enable && ignoreEnable) { storedFocus = role == .enable ? dndName : "" }
                if role == .enable && invalidEnableOutput { return "" }
            }
            return role.outputPrefix + storedFocus
        }
    }
}
