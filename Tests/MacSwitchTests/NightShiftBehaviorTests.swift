import XCTest
@testable import MacSwitch

final class NightShiftBehaviorTests: XCTestCase {
    func testSnapshotUsesEnabledInsteadOfActive() {
        let disabledClient = FakeNightShiftClient(state: makeState(active: true, enabled: false))
        let disabledSwitch = NightShiftSwitch(client: disabledClient)
        XCTAssertFalse(disabledSwitch.snapshot().isOn)

        let legacyClient = FakeNightShiftClient(state: makeState(active: false, enabled: true))
        let legacySwitch = NightShiftSwitch(client: legacyClient)
        let legacySnapshot = legacySwitch.snapshot()
        XCTAssertTrue(legacySnapshot.isOn)
        XCTAssertEqual(legacySnapshot.warning, "Enabled, but macOS is not applying Night Shift")
    }

    func testEnableUsesSetEnabledWhenFeatureIsAlreadyActive() {
        let client = FakeNightShiftClient(state: makeState(active: true, enabled: false))
        let nightShift = NightShiftSwitch(client: client)

        XCTAssertNil(nightShift.setEnabled(true))
        XCTAssertEqual(client.operations, [.setEnabled(true)])
        XCTAssertEqual(client.state?.enabled, true)
    }

    func testEnableRepairsLegacyInactiveStateBeforeSettingEnabled() {
        let client = FakeNightShiftClient(state: makeState(active: false, enabled: false))
        let nightShift = NightShiftSwitch(client: client)

        XCTAssertNil(nightShift.setEnabled(true))
        XCTAssertEqual(client.operations, [.setActive(true), .setEnabled(true)])
        XCTAssertEqual(client.state?.active, true)
        XCTAssertEqual(client.state?.enabled, true)
    }

    func testDisableNeverDisablesTheNightShiftMasterState() {
        let client = FakeNightShiftClient(state: makeState(active: true, enabled: true))
        let nightShift = NightShiftSwitch(client: client)

        XCTAssertNil(nightShift.setEnabled(false))
        XCTAssertEqual(client.operations, [.setEnabled(false)])
        XCTAssertEqual(client.state?.active, true)
        XCTAssertEqual(client.state?.enabled, false)
    }

    func testCustomScheduleIsVisibleAndPreservedAcrossModeChanges() {
        let custom = NightShiftScheduleState(
            start: TimeOfDay(hour: 5, minute: 0),
            end: TimeOfDay(hour: 4, minute: 59)
        )
        let client = FakeNightShiftClient(
            state: makeState(active: true, enabled: true, mode: .custom, schedule: custom)
        )
        let nightShift = NightShiftSwitch(client: client)

        XCTAssertEqual(nightShift.snapshot().subtitle, "Custom 05:00-04:59")
        XCTAssertNil(nightShift.setScheduleMode(.sunsetToSunrise, customSchedule: custom))
        XCTAssertEqual(client.operations, [.setScheduleMode(.sunsetToSunrise)])
        XCTAssertEqual(client.state?.schedule, custom)

        client.operations.removeAll()
        let updated = NightShiftScheduleState(
            start: TimeOfDay(hour: 21, minute: 30),
            end: TimeOfDay(hour: 7, minute: 15)
        )
        XCTAssertNil(nightShift.setScheduleMode(.custom, customSchedule: updated))
        XCTAssertEqual(client.operations, [.setSchedule(updated), .setScheduleMode(.custom)])
        XCTAssertEqual(client.state?.scheduleMode, .custom)
        XCTAssertEqual(client.state?.schedule, updated)
    }

    func testMutationPolicyCoversEveryActiveEnabledCombination() {
        XCTAssertEqual(
            NightShiftStatePolicy.mutations(toReach: true, from: makeState(active: true, enabled: true)),
            []
        )
        XCTAssertEqual(
            NightShiftStatePolicy.mutations(toReach: true, from: makeState(active: true, enabled: false)),
            [.setEnabled(true)]
        )
        XCTAssertEqual(
            NightShiftStatePolicy.mutations(toReach: true, from: makeState(active: false, enabled: true)),
            [.setActive(true), .setEnabled(true)]
        )
        XCTAssertEqual(
            NightShiftStatePolicy.mutations(toReach: true, from: makeState(active: false, enabled: false)),
            [.setActive(true), .setEnabled(true)]
        )
        XCTAssertEqual(
            NightShiftStatePolicy.mutations(toReach: false, from: makeState(active: true, enabled: true)),
            [.setEnabled(false)]
        )
        XCTAssertEqual(
            NightShiftStatePolicy.mutations(toReach: false, from: makeState(active: false, enabled: false)),
            []
        )
    }

    private func makeState(
        active: Bool,
        enabled: Bool,
        mode: NightShiftScheduleMode = .off,
        schedule: NightShiftScheduleState = .defaultSchedule
    ) -> NightShiftState {
        NightShiftState(
            active: active,
            enabled: enabled,
            sunSchedulePermitted: true,
            scheduleMode: mode,
            schedule: schedule,
            disableFlags: 0,
            available: true,
            supported: true,
            strength: 0.5,
            correlatedColorTemperature: 4_100
        )
    }
}

private final class FakeNightShiftClient: NightShiftClientProtocol, @unchecked Sendable {
    enum Operation: Equatable {
        case setActive(Bool)
        case setEnabled(Bool)
        case setScheduleMode(NightShiftScheduleMode)
        case setSchedule(NightShiftScheduleState)
    }

    var onStatusChange: (@Sendable () -> Void)?
    var state: NightShiftState?
    var operations: [Operation] = []

    init(state: NightShiftState?) {
        self.state = state
    }

    func readState() -> NightShiftState? {
        state
    }

    func setActive(_ active: Bool) -> Bool {
        operations.append(.setActive(active))
        state?.active = active
        onStatusChange?()
        return true
    }

    func setEnabled(_ enabled: Bool) -> Bool {
        operations.append(.setEnabled(enabled))
        state?.enabled = enabled
        onStatusChange?()
        return true
    }

    func setScheduleMode(_ mode: NightShiftScheduleMode) -> Bool {
        operations.append(.setScheduleMode(mode))
        state?.scheduleMode = mode
        onStatusChange?()
        return true
    }

    func setSchedule(_ schedule: NightShiftScheduleState) -> Bool {
        operations.append(.setSchedule(schedule))
        state?.schedule = schedule
        onStatusChange?()
        return true
    }
}
