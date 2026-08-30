import Foundation
import XCTest
@testable import MacSwitch

@MainActor
final class TogglePreflightBehaviorTests: XCTestCase {
    func testToggleUsesFreshSystemStateInsteadOfStaleDashboardState() async throws {
        let controller = PreflightController(snapshot: SwitchSnapshot(
            isOn: true,
            isAvailable: true,
            subtitle: nil,
            warning: nil
        ))
        let store = SwitchStore(
            controller: controller,
            defaults: InMemoryUserDefaults(),
            enableRuntimeServices: false
        )
        XCTAssertFalse(store.snapshots[.darkMode]?.isOn ?? true)

        store.toggle(.darkMode)
        try await waitUntil { controller.setTargets.count == 1 }

        XCTAssertEqual(controller.setTargets, [false])
        XCTAssertFalse(store.snapshots[.darkMode]?.isOn ?? true)
    }

    func testUnavailableFreshSnapshotStopsTheToggle() async throws {
        let controller = PreflightController(snapshot: SwitchSnapshot(
            isOn: false,
            isAvailable: false,
            subtitle: nil,
            warning: "Unavailable"
        ))
        let store = SwitchStore(
            controller: controller,
            defaults: InMemoryUserDefaults(),
            enableRuntimeServices: false
        )

        store.toggle(.darkMode)
        try await Task.sleep(for: .milliseconds(150))

        XCTAssertTrue(controller.setTargets.isEmpty)
        XCTAssertEqual(store.snapshots[.darkMode]?.warning, "Unavailable")
    }

    func testRepeatedClickDuringPreflightProducesOneMutation() async throws {
        let controller = PreflightController(
            snapshot: SwitchSnapshot(isOn: false, isAvailable: true, subtitle: nil, warning: nil),
            snapshotDelay: 0.12
        )
        let store = SwitchStore(
            controller: controller,
            defaults: InMemoryUserDefaults(),
            enableRuntimeServices: false
        )

        store.toggle(.stageManager)
        store.toggle(.stageManager)
        try await waitUntil { controller.setTargets.count == 1 }

        XCTAssertEqual(controller.setTargets, [true])
    }

    private func waitUntil(
        timeout: TimeInterval = 2,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() >= deadline {
                XCTFail("Timed out waiting for switch preflight")
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}

private final class PreflightController: SystemSwitchControlling, @unchecked Sendable {
    var onExternalChange: (@Sendable (SwitchKind) -> Void)?

    private let lock = NSLock()
    private var currentSnapshot: SwitchSnapshot
    private let snapshotDelay: TimeInterval
    private var targets: [Bool] = []

    init(snapshot: SwitchSnapshot, snapshotDelay: TimeInterval = 0) {
        currentSnapshot = snapshot
        self.snapshotDelay = snapshotDelay
    }

    var setTargets: [Bool] {
        lock.withLock { targets }
    }

    func snapshot(for kind: SwitchKind, keepAwakeDuration: KeepAwakeDuration) -> SwitchSnapshot {
        if snapshotDelay > 0 {
            Thread.sleep(forTimeInterval: snapshotDelay)
        }
        return lock.withLock { currentSnapshot }
    }

    func set(
        _ kind: SwitchKind,
        enabled: Bool,
        keepAwakeDuration: KeepAwakeDuration
    ) -> SwitchOperationResult {
        lock.withLock {
            targets.append(enabled)
            currentSnapshot.isOn = enabled
        }
        return SwitchOperationResult(
            snapshot: lock.withLock { currentSnapshot },
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
