import Foundation
import XCTest
@testable import MacSwitch

@MainActor
final class ModeBehaviorTests: XCTestCase {
    func testModeActivationPersistsAndRestoresOriginalStatesAfterRelaunch() async throws {
        let defaults = InMemoryUserDefaults()

        let controller = FakeSystemSwitchController(states: [
            .darkMode: false,
            .stageManager: true
        ])
        let store = SwitchStore(
            controller: controller,
            defaults: defaults,
            enableRuntimeServices: false
        )
        let modeID = store.createCustomMode()
        var mode = try XCTUnwrap(store.customModes.first { $0.id == modeID })
        mode.items = [
            SwitchModeItem(kind: .darkMode, targetIsOn: true),
            SwitchModeItem(kind: .stageManager, targetIsOn: false)
        ]
        store.updateCustomMode(mode)
        store.toggleMode(mode)

        try await waitUntil { store.isModeActive(modeID) && store.activeModeOperationID == nil }
        XCTAssertTrue(controller.state(for: .darkMode))
        XCTAssertFalse(controller.state(for: .stageManager))

        let relaunchedStore = SwitchStore(
            controller: controller,
            defaults: defaults,
            enableRuntimeServices: false
        )
        XCTAssertTrue(relaunchedStore.isModeActive(modeID))

        let relaunchedMode = try XCTUnwrap(relaunchedStore.customModes.first { $0.id == modeID })
        relaunchedStore.toggleMode(relaunchedMode)
        try await waitUntil { !relaunchedStore.isModeActive(modeID) && relaunchedStore.activeModeOperationID == nil }

        XCTAssertFalse(controller.state(for: .darkMode))
        XCTAssertTrue(controller.state(for: .stageManager))
        let persisted = try XCTUnwrap(defaults.data(forKey: "switch.modes.activeSessions"))
        XCTAssertTrue(try JSONDecoder().decode([ActiveSwitchModeSession].self, from: persisted).isEmpty)
    }

    func testModeActivationFailureRollsBackCompletedChanges() async throws {
        let defaults = InMemoryUserDefaults()

        let controller = FakeSystemSwitchController(
            states: [.darkMode: false, .stageManager: true],
            failures: [.stageManager: false]
        )
        let store = SwitchStore(
            controller: controller,
            defaults: defaults,
            enableRuntimeServices: false
        )
        let modeID = store.createCustomMode()
        var mode = try XCTUnwrap(store.customModes.first { $0.id == modeID })
        mode.items = [
            SwitchModeItem(kind: .darkMode, targetIsOn: true),
            SwitchModeItem(kind: .stageManager, targetIsOn: false)
        ]
        store.updateCustomMode(mode)
        store.toggleMode(mode)

        try await waitUntil {
            store.activeModeOperationID == nil &&
                store.lastError?.contains("changes were restored") == true
        }

        XCTAssertFalse(store.isModeActive(modeID))
        XCTAssertFalse(controller.state(for: .darkMode))
        XCTAssertTrue(controller.state(for: .stageManager))
    }

    func testDeletingActiveCustomModeRestoresStateBeforeRemovingIt() async throws {
        let defaults = InMemoryUserDefaults()

        let controller = FakeSystemSwitchController(states: [.darkMode: false])
        let store = SwitchStore(
            controller: controller,
            defaults: defaults,
            enableRuntimeServices: false
        )
        let modeID = store.createCustomMode()
        var mode = try XCTUnwrap(store.customModes.first { $0.id == modeID })
        mode.items = [SwitchModeItem(kind: .darkMode, targetIsOn: true)]
        store.updateCustomMode(mode)
        store.toggleMode(mode)

        try await waitUntil { store.isModeActive(modeID) && store.activeModeOperationID == nil }
        XCTAssertTrue(controller.state(for: .darkMode))

        store.deleteCustomMode(modeID)
        try await waitUntil {
            store.customModes.allSatisfy { $0.id != modeID } &&
                store.activeModeOperationID == nil
        }

        XCTAssertFalse(controller.state(for: .darkMode))
        XCTAssertFalse(store.isModeActive(modeID))
        XCTAssertNil(store.pendingCustomModeDeletionID)
        XCTAssertFalse(store.enabledModeIDs.contains(modeID))
    }

    func testModeLocalizationCoversEverySupportedLanguage() {
        let languages = AppLanguage.allCases.filter { $0 != .system }

        for language in languages {
            for key in ModeL10nKey.allCases {
                XCTAssertTrue(
                    ModeL10n.hasExplicitTranslation(key, language: language),
                    "Missing \(key.rawValue) translation for \(language.rawValue)."
                )
            }

            let formattedSamples = [
                ModeL10n.formatted(.addSwitchBeforeShowing, language: language, arguments: ["Mode"]),
                ModeL10n.formatted(.addSwitchBeforeStarting, language: language, arguments: ["Mode"]),
                ModeL10n.formatted(.deleteModeTitle, language: language, arguments: ["Mode"]),
                ModeL10n.formatted(.restoreFailed, language: language, arguments: ["Mode", "Failure"]),
                ModeL10n.formatted(.skippedUnavailable, language: language, arguments: ["Mode", "Switch"]),
                ModeL10n.formatted(.startFailedRestored, language: language, arguments: ["Mode", "Failure"]),
                ModeL10n.formatted(.startPartialRestoreFailed, language: language, arguments: ["Mode", "Failure"]),
                ModeL10n.formatted(.unavailableToStart, language: language, arguments: ["Mode"])
            ]
            for sample in formattedSamples {
                XCTAssertFalse(sample.contains("%@"), "Unexpanded placeholder for \(language.rawValue): \(sample)")
                XCTAssertFalse(sample.contains("%1$@"), "Unexpanded placeholder for \(language.rawValue): \(sample)")
                XCTAssertFalse(sample.contains("%2$@"), "Unexpanded placeholder for \(language.rawValue): \(sample)")
            }
        }
    }

    private func waitUntil(
        timeout: TimeInterval = 3,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() >= deadline {
                XCTFail("Timed out waiting for the mode operation to finish.")
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}

private final class FakeSystemSwitchController: SystemSwitchControlling, @unchecked Sendable {
    var onExternalChange: (@Sendable (SwitchKind) -> Void)?

    private let lock = NSLock()
    private var states: [SwitchKind: Bool]
    private let failures: [SwitchKind: Bool]

    init(states: [SwitchKind: Bool], failures: [SwitchKind: Bool] = [:]) {
        self.states = states
        self.failures = failures
    }

    func state(for kind: SwitchKind) -> Bool {
        lock.withLock { states[kind] ?? false }
    }

    func snapshot(for kind: SwitchKind, keepAwakeDuration: KeepAwakeDuration) -> SwitchSnapshot {
        SwitchSnapshot(
            isOn: state(for: kind),
            isAvailable: true,
            subtitle: nil,
            warning: nil
        )
    }

    func set(
        _ kind: SwitchKind,
        enabled: Bool,
        keepAwakeDuration: KeepAwakeDuration
    ) -> SwitchOperationResult {
        if failures[kind] == enabled {
            return SwitchOperationResult(
                snapshot: snapshot(for: kind, keepAwakeDuration: keepAwakeDuration),
                error: "Simulated failure"
            )
        }
        lock.withLock { states[kind] = enabled }
        return SwitchOperationResult(
            snapshot: snapshot(for: kind, keepAwakeDuration: keepAwakeDuration),
            error: nil
        )
    }

    func setKeepAwake(
        enabled: Bool,
        duration: TimeInterval?,
        defaultDuration: KeepAwakeDuration
    ) -> SwitchOperationResult {
        set(.keepAwake, enabled: enabled, keepAwakeDuration: defaultDuration)
    }

    func performXcodeClean(progress: @escaping @Sendable (Double) -> Void) -> SwitchOperationResult {
        progress(1)
        return SwitchOperationResult(snapshot: .off, error: nil)
    }

    func prepareForTermination() {}
}
