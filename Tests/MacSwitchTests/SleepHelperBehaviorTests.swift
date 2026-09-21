import Foundation
import Security
import XCTest
import SleepHelperCore
@testable import MacSwitch

final class SleepHelperBehaviorTests: XCTestCase {
    func testLeaseUpdatesDoNotTogglePowerAndDisconnectRestoresIt() throws {
        let power = FakeSleepPower()
        let journal = FakeSleepRecovery()
        let service = try SleepLeaseCoordinator(power: power, recovery: journal)
        let owner = UUID()
        try service.set(true, owner: owner, deadline: nil)
        try service.set(true, owner: owner, deadline: Date().addingTimeInterval(600))
        XCTAssertEqual(power.writes, [true])
        XCTAssertTrue(journal.pending)
        try service.disconnect(owner)
        XCTAssertEqual(power.writes, [true, false])
        XCTAssertFalse(journal.pending)
        try service.set(true, owner: owner, deadline: nil)
        try service.set(false, owner: owner, deadline: nil)
        XCTAssertEqual(power.writes, [true, false, true, false])
    }

    func testMultipleConnectionsDoNotUndoEachOthersLeases() throws {
        let power = FakeSleepPower()
        let service = try SleepLeaseCoordinator(power: power, recovery: FakeSleepRecovery())
        let first = UUID(), second = UUID()
        try service.set(true, owner: first, deadline: nil)
        try service.set(true, owner: second, deadline: nil)
        try service.disconnect(first)
        XCTAssertTrue(power.disabled)
        try service.disconnect(second)
        XCTAssertFalse(power.disabled)
    }

    func testExternalDisabledSettingIsPreserved() throws {
        let power = FakeSleepPower()
        power.disabled = true
        let service = try SleepLeaseCoordinator(power: power, recovery: FakeSleepRecovery())
        try service.set(true, owner: UUID(), deadline: nil)
        try service.shutdown()
        XCTAssertTrue(power.disabled)
        XCTAssertTrue(power.writes.isEmpty)
    }

    func testDeadlineAndReschedulingExpireWithoutTheApp() throws {
        let power = FakeSleepPower()
        let service = try SleepLeaseCoordinator(power: power, recovery: FakeSleepRecovery())
        let owner = UUID(), now = Date()
        try service.set(true, owner: owner, deadline: now.addingTimeInterval(5), now: now)
        try service.set(true, owner: owner, deadline: now.addingTimeInterval(10), now: now)
        try service.expire(now: now.addingTimeInterval(6))
        XCTAssertTrue(power.disabled)
        try service.expire(now: now.addingTimeInterval(11))
        XCTAssertFalse(power.disabled)
        XCTAssertNil(service.nextDeadline)
    }

    func testDaemonRestartRestoresOnlyJournaledChanges() throws {
        let power = FakeSleepPower()
        let journal = FakeSleepRecovery()
        let first = try SleepLeaseCoordinator(power: power, recovery: journal)
        try first.set(true, owner: UUID(), deadline: nil)
        let restarted = try SleepLeaseCoordinator(power: power, recovery: journal)
        try restarted.expire()
        XCTAssertFalse(power.disabled)
        XCTAssertFalse(journal.pending)
    }

    func testFailedRestorationRetainsRecoveryForRetry() throws {
        let power = FakeSleepPower(), journal = FakeSleepRecovery()
        let service = try SleepLeaseCoordinator(power: power, recovery: journal)
        let owner = UUID()
        try service.set(true, owner: owner, deadline: nil)
        power.failDisable = true
        XCTAssertThrowsError(try service.disconnect(owner))
        XCTAssertTrue(service.needsRestoreRetry)
        XCTAssertTrue(journal.pending)
        power.failDisable = false
        try service.expire()
        XCTAssertFalse(power.disabled)
        XCTAssertFalse(service.needsRestoreRetry)
    }

    func testFailedEnableRestoresAnUncertainMutation() throws {
        let power = FakeSleepPower(), journal = FakeSleepRecovery()
        let service = try SleepLeaseCoordinator(power: power, recovery: journal)
        power.failEnableAfterMutation = true
        XCTAssertThrowsError(try service.set(true, owner: UUID(), deadline: nil))
        XCTAssertFalse(power.disabled)
        XCTAssertFalse(journal.pending)
    }

    func testCannotChangeSystemWithoutWritingRecoveryFirst() throws {
        let power = FakeSleepPower(), journal = FakeSleepRecovery()
        let service = try SleepLeaseCoordinator(power: power, recovery: journal)
        journal.failWrite = true
        XCTAssertThrowsError(try service.set(true, owner: UUID(), deadline: nil))
        XCTAssertTrue(power.writes.isEmpty)
    }

    func testLegacyMigrationWaitsForOtherLeasesBeforeRestoring() throws {
        let power = FakeSleepPower(), journal = FakeSleepRecovery()
        power.disabled = true
        let service = try SleepLeaseCoordinator(power: power, recovery: journal)
        let owner = UUID()
        try service.set(true, owner: owner, deadline: nil)
        try service.restoreLegacySetting()
        XCTAssertTrue(power.disabled)
        try service.disconnect(owner)
        XCTAssertFalse(power.disabled)
    }

    func testPeerRequirementIsStrictAndCompiles() throws {
        XCTAssertNil(SleepHelperIdentity.requirement(identifier: "other.app", team: "ABCDEFGHIJ"))
        XCTAssertNil(SleepHelperIdentity.requirement(identifier: SleepHelperIdentity.appIdentifier, team: "invalid\" or true"))
        for identifier in [SleepHelperIdentity.appIdentifier, SleepHelperIdentity.serviceIdentifier] {
            let requirement = try XCTUnwrap(SleepHelperIdentity.requirement(identifier: identifier, team: "ABCDEFGHIJ"))
            var parsed: SecRequirement?
            XCTAssertEqual(SecRequirementCreateWithString(requirement as CFString, [], &parsed), errSecSuccess)
            XCTAssertNotNil(parsed)
            XCTAssertTrue(requirement.contains("anchor apple generic"))
            XCTAssertTrue(requirement.contains("get-task-allow"))
        }
    }

    func testDurationChangesKeepAssertionsAndTheLidLeaseAlive() {
        let assertions = FakeAwakeAssertions(), lid = FakeLidController()
        let preference = LidPreference(true)
        let manager = KeepAwakeManager(assertions: assertions, lidController: lid, lidPreference: { preference.value }, legacyRecoveryPending: false)
        XCTAssertNil(manager.setEnabled(true, duration: 300))
        XCTAssertNil(manager.setEnabled(true, duration: 900))
        XCTAssertEqual(assertions.creations, 1)
        XCTAssertTrue(assertions.released.isEmpty)
        XCTAssertEqual(lid.requests, [true, true])
        preference.value = false
        XCTAssertNil(manager.setEnabled(true, duration: 900))
        XCTAssertEqual(assertions.creations, 1)
        XCTAssertEqual(lid.requests, [true, true, false])
        XCTAssertNil(manager.setEnabled(false, duration: nil))
        XCTAssertEqual(assertions.released, [1, 2])
    }

    func testNewManagerDoesNotAttemptAuthorizationOrRecoveryUntilUsed() {
        let assertions = FakeAwakeAssertions(), lid = FakeLidController()
        let manager = KeepAwakeManager(assertions: assertions, lidController: lid, lidPreference: { false }, legacyRecoveryPending: true, didRestoreLegacy: {})
        XCTAssertFalse(manager.isActive)
        XCTAssertTrue(lid.requests.isEmpty)
        XCTAssertEqual(lid.restorations, 0)
        XCTAssertNil(manager.setEnabled(false, duration: nil))
        XCTAssertEqual(lid.restorations, 1)
    }

    func testStaleExpirationDoesNotStopARescheduledSession() throws {
        let assertions = FakeAwakeAssertions(), lid = FakeLidController()
        let manager = KeepAwakeManager(assertions: assertions, lidController: lid, lidPreference: { false }, legacyRecoveryPending: false)
        XCTAssertNil(manager.setEnabled(true, duration: 0.04))
        XCTAssertNil(manager.setEnabled(true, duration: 60))
        Thread.sleep(forTimeInterval: 0.08)
        XCTAssertTrue(manager.isActive)
        XCTAssertTrue(assertions.released.isEmpty)
        XCTAssertNil(manager.setEnabled(false, duration: nil))
    }
}

private struct FakeFailure: Error {}
private final class FakeSleepPower: SleepPowerControlling {
    var disabled = false
    var writes: [Bool] = []
    var failDisable = false
    var failEnableAfterMutation = false
    func isSleepDisabled() throws -> Bool { disabled }
    func setSleepDisabled(_ disabled: Bool) throws {
        if !disabled && failDisable { throw FakeFailure() }
        self.disabled = disabled
        writes.append(disabled)
        if disabled && failEnableAfterMutation { throw FakeFailure() }
    }
}
private final class FakeSleepRecovery: SleepRecoveryStoring {
    var pending = false
    var failWrite = false
    func needsRecovery() throws -> Bool { pending }
    func setNeedsRecovery(_ value: Bool) throws { if failWrite { throw FakeFailure() }; pending = value }
}
private final class FakeAwakeAssertions: KeepAwakeAsserting, @unchecked Sendable {
    var creations = 0
    var released: [UInt32] = []
    func create() -> (ids: [UInt32], error: String?) { creations += 1; return ([1, 2], nil) }
    func release(_ ids: [UInt32]) { released += ids }
}
private final class FakeLidController: LidSleepControlling, @unchecked Sendable {
    var requests: [Bool] = []
    var restorations = 0
    func setDisabled(_ disabled: Bool, until deadline: Date?) -> String? { requests.append(disabled); return nil }
    func restoreLegacySetting() -> String? { restorations += 1; return nil }
}
private final class LidPreference: @unchecked Sendable {
    var value: Bool
    init(_ value: Bool) { self.value = value }
}
