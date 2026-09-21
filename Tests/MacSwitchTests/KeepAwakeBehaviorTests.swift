import Foundation
import XCTest
@testable import MacSwitch

@MainActor
final class KeepAwakeBehaviorTests: XCTestCase {
    func testChangingOptionsWhileOffPersistsWithoutStartingKeepAwake() {
        let (store, controller, defaults) = fixture()
        store.setKeepAwakeDuration(.thirtyMinutes)
        store.setKeepAwakeWhenLidClosed(true)
        XCTAssertEqual(store.keepAwakeDuration, .thirtyMinutes)
        XCTAssertTrue(store.keepAwakeWhenLidClosed)
        XCTAssertTrue(controller.requests.isEmpty)
        let reloaded = SwitchStore(controller: controller, defaults: defaults, enableRuntimeServices: false)
        XCTAssertEqual(reloaded.keepAwakeDuration, .thirtyMinutes)
        XCTAssertTrue(reloaded.keepAwakeWhenLidClosed)
    }

    func testChangingActiveDurationReschedulesExactlyOnce() async throws {
        let (store, controller, defaults) = fixture()
        store.set(.keepAwake, enabled: true)
        try await settle(store)
        let count = controller.requests.count
        store.setKeepAwakeDuration(.fiveMinutes)
        try await settle(store)
        XCTAssertEqual(controller.requests.count, count + 1)
        XCTAssertEqual(controller.requests.last?.duration, 300)
        let deadline = try XCTUnwrap(defaults.object(forKey: "switch.keepAwake.endDate") as? Date)
        XCTAssertEqual(deadline.timeIntervalSinceNow, 300, accuracy: 2)
        store.setKeepAwakeDuration(.fiveMinutes)
        XCTAssertEqual(controller.requests.count, count + 1)
    }

    func testLidChangesPreserveTheRemainingTime() async throws {
        let (store, controller, defaults) = fixture()
        store.setKeepAwakeDuration(.oneHour)
        store.set(.keepAwake, enabled: true)
        try await settle(store)
        let originalDeadline = Date().addingTimeInterval(43)
        defaults.set(originalDeadline, forKey: "switch.keepAwake.endDate")
        store.setKeepAwakeWhenLidClosed(true)
        try await settle(store)
        XCTAssertTrue(store.keepAwakeWhenLidClosed)
        XCTAssertEqual(try XCTUnwrap(controller.requests.last?.duration), 43, accuracy: 2)
        XCTAssertEqual(defaults.object(forKey: "switch.keepAwake.endDate") as? Date, originalDeadline)
        store.setKeepAwakeWhenLidClosed(false)
        try await settle(store)
        XCTAssertFalse(store.keepAwakeWhenLidClosed)
        XCTAssertEqual(defaults.object(forKey: "switch.keepAwake.endDate") as? Date, originalDeadline)
    }

    func testLidChangesPreserveAnIndefiniteSessionEvenWithFiniteDefault() async throws {
        let (store, controller, defaults) = fixture()
        store.setKeepAwakeDuration(.oneHour)
        store.set(.keepAwake, enabled: true)
        try await settle(store)
        // A Mode can restore an earlier indefinite session while retaining the default duration.
        defaults.removeObject(forKey: "switch.keepAwake.endDate")
        store.setKeepAwakeWhenLidClosed(true)
        try await settle(store)
        XCTAssertNil(controller.requests.last?.duration)
        XCTAssertNil(defaults.object(forKey: "switch.keepAwake.endDate"))
    }

    func testExpiredSessionIsStoppedInsteadOfRestartedByLidChange() async throws {
        let (store, controller, defaults) = fixture()
        store.set(.keepAwake, enabled: true)
        try await settle(store)
        defaults.set(Date().addingTimeInterval(-1), forKey: "switch.keepAwake.endDate")
        store.setKeepAwakeWhenLidClosed(true)
        try await settle(store)
        XCTAssertEqual(controller.requests.last?.enabled, false)
        XCTAssertFalse(store.snapshots[.keepAwake]?.isOn ?? true)
        XCTAssertNil(defaults.object(forKey: "switch.keepAwake.endDate"))
    }

    func testFailedLidChangeRestoresSelectionAndReportsError() async throws {
        let (store, controller, defaults) = fixture()
        store.set(.keepAwake, enabled: true)
        try await settle(store)
        controller.failure = "Administrator authorization was cancelled."
        store.setKeepAwakeWhenLidClosed(true)
        try await settle(store)
        XCTAssertFalse(store.keepAwakeWhenLidClosed)
        XCTAssertFalse(defaults.bool(forKey: KeepAwakePreferences.keepAwakeWhenLidClosedKey))
        XCTAssertTrue(store.lastError?.contains("authorization was cancelled") == true)
    }

    func testBusyOptionsDoNotChangePreferencesOrEnqueueAnotherAction() async throws {
        let (store, controller, defaults) = fixture()
        controller.delay = 0.08
        store.set(.keepAwake, enabled: true)
        XCTAssertTrue(store.isActionBusy(.keepAwake))
        store.setKeepAwakeDuration(.fiveMinutes)
        store.setKeepAwakeWhenLidClosed(true)
        XCTAssertEqual(store.keepAwakeDuration, .indefinitely)
        XCTAssertFalse(store.keepAwakeWhenLidClosed)
        XCTAssertFalse(defaults.bool(forKey: KeepAwakePreferences.keepAwakeWhenLidClosedKey))
        try await settle(store)
        XCTAssertEqual(controller.requests.count, 1)
    }

    private func fixture() -> (SwitchStore, KeepAwakeTestController, InMemoryUserDefaults) {
        let controller = KeepAwakeTestController()
        let defaults = InMemoryUserDefaults()
        let store = SwitchStore(controller: controller, defaults: defaults, enableRuntimeServices: false)
        return (store, controller, defaults)
    }

    private func settle(_ store: SwitchStore) async throws {
        let deadline = Date().addingTimeInterval(3)
        while store.isActionBusy(.keepAwake), Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(store.isActionBusy(.keepAwake))
    }
}

private final class KeepAwakeTestController: SystemSwitchControlling, @unchecked Sendable {
    struct Request { let enabled: Bool; let duration: TimeInterval? }
    private let lock = NSLock()
    private var state = false
    private var recorded: [Request] = []
    var requests: [Request] { lock.withLock { recorded } }
    var onExternalChange: (@Sendable (SwitchKind) -> Void)?
    // Configured before the next asynchronous operation starts.
    var failure: String?
    var delay: TimeInterval = 0

    func snapshot(for kind: SwitchKind, keepAwakeDuration: KeepAwakeDuration) -> SwitchSnapshot {
        lock.withLock { SwitchSnapshot(isOn: kind == .keepAwake && state, isAvailable: true, subtitle: nil, warning: nil) }
    }
    func set(_ kind: SwitchKind, enabled: Bool, keepAwakeDuration: KeepAwakeDuration) -> SwitchOperationResult {
        setKeepAwake(enabled: enabled, duration: keepAwakeDuration.seconds, defaultDuration: keepAwakeDuration)
    }
    func setKeepAwake(enabled: Bool, duration: TimeInterval?, defaultDuration: KeepAwakeDuration) -> SwitchOperationResult {
        if delay > 0 { Thread.sleep(forTimeInterval: delay) }
        lock.withLock {
            recorded.append(Request(enabled: enabled, duration: duration))
            if failure == nil { state = enabled }
        }
        return SwitchOperationResult(snapshot: snapshot(for: .keepAwake, keepAwakeDuration: defaultDuration), error: failure)
    }
    func performXcodeClean(progress: @escaping @Sendable (Double) -> Void) -> SwitchOperationResult {
        SwitchOperationResult(snapshot: .off, error: nil)
    }
    func prepareForTermination() {}
}
