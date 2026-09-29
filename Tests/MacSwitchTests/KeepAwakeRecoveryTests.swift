import Foundation
import IOKit.pwr_mgt
import XCTest
@testable import MacSwitch

final class KeepAwakeRecoveryTests: XCTestCase, @unchecked Sendable {
    func testLeaseLossImmediatelyClearsClaimThenRecoversTheOriginalDeadline() async throws {
        let lid = RecoveringLid()
        let subject = makeManager(lid)
        let deadline = Date().addingTimeInterval(1800)
        XCTAssertNil(subject.setEnabled(true, duration: nil, endingAt: deadline))
        XCTAssertEqual(subject.subtitle(defaultDuration: .indefinitely), "Disable Sleep Enabled")
        lid.loseLease()
        XCTAssertTrue(subject.isActive)
        XCTAssertNotEqual(subject.subtitle(defaultDuration: .indefinitely), "Disable Sleep Enabled")
        XCTAssertNotNil(subject.warning)
        try await wait { lid.requests.count == 2 && subject.warning == nil }
        XCTAssertEqual(lid.requests.map(\.deadline), [deadline, deadline])
        XCTAssertNil(subject.warning)
        XCTAssertEqual(subject.subtitle(defaultDuration: .indefinitely), "Disable Sleep Enabled")
        XCTAssertNil(subject.setEnabled(false, duration: nil))
    }

    func testStopBeforeRecoveryPreventsAStaleLeaseFromBeingRecreated() async throws {
        let lid = RecoveringLid()
        let manager = makeManager(lid)
        XCTAssertNil(manager.setEnabled(true, duration: 60))
        lid.loseLease()
        XCTAssertNil(manager.setEnabled(false, duration: nil))
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertEqual(lid.requests.count, 1)
        XCTAssertFalse(manager.isActive)
    }

    func testExpiryBeforeRecoveryDoesNotExtendTheSession() async throws {
        let lid = RecoveringLid(), manager = makeManager(lid)
        XCTAssertNil(manager.setEnabled(true, duration: 0.07))
        lid.loseLease()
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertEqual(lid.requests.count, 1)
        XCTAssertFalse(manager.isActive)
    }

    func testDisconnectDuringSuccessfulReplyCannotLeaveFalseProtectionClaim() async throws {
        let lid = RecoveringLid(), manager = makeManager(lid)
        lid.dropDuringNextRequest = true
        XCTAssertNotNil(manager.setEnabled(true, duration: 60))
        XCTAssertNotNil(manager.warning)
        XCTAssertNotEqual(manager.subtitle(defaultDuration: .indefinitely), "Disable Sleep Enabled")
        try await wait { lid.requests.count >= 2 && manager.warning == nil }
        XCTAssertNil(manager.warning)
        XCTAssertNil(manager.setEnabled(false, duration: nil))
    }

    func testFailedAutomaticRecoveryKeepsWarningAndOrdinaryAssertions() async throws {
        let lid = RecoveringLid(), manager = makeManager(lid)
        XCTAssertNil(manager.setEnabled(true, duration: 60))
        lid.failRequests = true
        lid.loseLease()
        try await wait { lid.requests.count >= 2 }
        XCTAssertTrue(manager.isActive)
        XCTAssertNotNil(manager.warning)
        XCTAssertNotEqual(manager.subtitle(defaultDuration: .indefinitely), "Disable Sleep Enabled")
        lid.failRequests = false
        XCTAssertNil(manager.setEnabled(true, duration: 60))
        XCTAssertNil(manager.warning)
        XCTAssertNil(manager.setEnabled(false, duration: nil))
    }

    private func makeManager(_ lid: RecoveringLid) -> KeepAwakeManager {
        KeepAwakeManager(assertions: RecoveryAssertions(), lidController: lid, lidPreference: { true }, legacyRecoveryPending: false, didRestoreLegacy: {})
    }
    private func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<100 { if condition() { return }; try await Task.sleep(for: .milliseconds(10)) }
        XCTFail("Helper recovery did not finish")
    }
}

private struct RecoveryAssertions: KeepAwakeAsserting {
    func create() -> (ids: [IOPMAssertionID], error: String?) { ([1, 2], nil) }
    func release(_ ids: [IOPMAssertionID]) {}
}
private final class RecoveringLid: LidSleepControlling, @unchecked Sendable {
    struct Request { let disabled: Bool; let deadline: Date? }
    private let lock = NSLock()
    private var observers: [UUID: @Sendable () -> Void] = [:]
    private var recorded: [Request] = []
    private var failing = false
    private var dropsNext = false
    var failRequests: Bool { get { lock.withLock { failing } } set { lock.withLock { failing = newValue } } }
    var dropDuringNextRequest: Bool { get { lock.withLock { dropsNext } } set { lock.withLock { dropsNext = newValue } } }
    var requests: [Request] { lock.withLock { recorded } }
    func setDisabled(_ disabled: Bool, until deadline: Date?) -> String? {
        let drops = lock.withLock { () -> Bool in
            recorded.append(.init(disabled: disabled, deadline: deadline))
            let result = dropsNext; dropsNext = false; return result
        }
        if drops { loseLease() }
        return failRequests ? "Injected connection failure" : nil
    }
    func restoreLegacySetting() -> String? { nil }
    func observeLeaseLoss(_ handler: @escaping @Sendable () -> Void) -> UUID? {
        let id = UUID(); lock.withLock { observers[id] = handler }; return id
    }
    func removeLeaseObserver(_ id: UUID) { _ = lock.withLock { observers.removeValue(forKey: id) } }
    func loseLease() { lock.withLock { Array(observers.values) }.forEach { $0() } }
}
