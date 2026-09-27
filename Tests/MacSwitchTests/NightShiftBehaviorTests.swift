import XCTest
@testable import MacSwitch

final class NightShiftBehaviorTests: XCTestCase {
    func testSnapshotUsesEnabledInsteadOfActive() {
        let disabledClient = FakeNightShiftClient(state: makeState(active: true, enabled: false))
        let disabledSwitch = makeSwitch(disabledClient)
        XCTAssertFalse(disabledSwitch.snapshot().isOn)

        let legacyClient = FakeNightShiftClient(state: makeState(active: false, enabled: true))
        let legacySwitch = makeSwitch(legacyClient)
        let legacySnapshot = legacySwitch.snapshot()
        XCTAssertTrue(legacySnapshot.isOn)
        XCTAssertEqual(legacySnapshot.warning, "Enabled, but macOS is not applying Night Shift")
    }

    func testEnableUsesSetEnabledWhenFeatureIsAlreadyActive() {
        let client = FakeNightShiftClient(state: makeState(active: true, enabled: false))
        let nightShift = makeSwitch(client)

        XCTAssertNil(nightShift.setEnabled(true))
        XCTAssertEqual(client.operations, [.setEnabled(true)])
        XCTAssertEqual(client.state?.enabled, true)
    }

    func testEnableRepairsLegacyInactiveStateBeforeSettingEnabled() {
        let client = FakeNightShiftClient(state: makeState(active: false, enabled: false))
        let nightShift = makeSwitch(client)

        XCTAssertNil(nightShift.setEnabled(true))
        XCTAssertEqual(client.operations, [.setActive(true), .setEnabled(true)])
        XCTAssertEqual(client.state?.active, true)
        XCTAssertEqual(client.state?.enabled, true)
    }

    func testDisableNeverDisablesTheNightShiftMasterState() {
        let client = FakeNightShiftClient(state: makeState(active: true, enabled: true))
        let nightShift = makeSwitch(client)

        XCTAssertNil(nightShift.setEnabled(false))
        XCTAssertEqual(client.operations, [.setEnabled(false)])
        XCTAssertEqual(client.state?.active, true)
        XCTAssertEqual(client.state?.enabled, false)
    }

    func testCustomScheduleIsPreservedAcrossModeChanges() {
        let custom = NightShiftScheduleState(
            start: TimeOfDay(hour: 21, minute: 30),
            end: TimeOfDay(hour: 7, minute: 15)
        )
        let client = FakeNightShiftClient(
            state: makeState(active: true, enabled: true, mode: .custom, schedule: custom)
        )
        let nightShift = makeSwitch(client)

        XCTAssertNil(nightShift.applySchedule(.sunsetToSunrise, customSchedule: custom))
        XCTAssertEqual(client.operations, [.setScheduleMode(.sunsetToSunrise)])
        XCTAssertEqual(client.state?.schedule, custom)

        client.operations.removeAll()
        let updated = NightShiftScheduleState(
            start: TimeOfDay(hour: 22, minute: 0),
            end: TimeOfDay(hour: 6, minute: 45)
        )
        XCTAssertNil(nightShift.applySchedule(.custom, customSchedule: updated))
        XCTAssertEqual(client.operations, [.setSchedule(updated), .setScheduleMode(.custom)])
        XCTAssertEqual(client.state?.scheduleMode, .custom)
        XCTAssertEqual(client.state?.schedule, updated)
    }

    func testSubtitleShowsWhenMacOSWillChangeACustomSchedule() {
        let calendar = utcCalendar
        var state = makeState(active: true, enabled: true, mode: .custom, schedule: .defaultSchedule)

        XCTAssertEqual(subtitle(state, at: date(hour: 23), calendar), "On until tomorrow 07:00")
        XCTAssertEqual(subtitle(state, at: date(hour: 1), calendar), "On until 07:00")

        state.enabled = false
        XCTAssertEqual(subtitle(state, at: date(hour: 15), calendar), "Off until 22:00")
        state.override = .offUntilNextTransition
        XCTAssertEqual(subtitle(state, at: date(hour: 23), calendar), "Off until tomorrow 22:00")
    }

    func testSubtitleUsesReportedSunTimesAndFallsBackToWords() {
        let calendar = utcCalendar
        let sunTimes = NightShiftSunTimes(
            sunrises: [date(hour: 7, minute: 4), date(day: 28, hour: 7, minute: 5)],
            sunsets: [date(hour: 18, minute: 55), date(day: 28, hour: 18, minute: 53)]
        )
        var state = makeState(active: true, enabled: true, mode: .sunsetToSunrise)
        state.sunTimes = sunTimes

        XCTAssertEqual(subtitle(state, at: date(hour: 23), calendar), "On until tomorrow 07:05")
        state.enabled = false
        XCTAssertEqual(subtitle(state, at: date(hour: 12), calendar), "Off until 18:55")

        state.sunTimes = nil
        XCTAssertEqual(subtitle(state, at: date(hour: 12), calendar), "Off until sunset")
        state.enabled = true
        XCTAssertEqual(subtitle(state, at: date(hour: 23), calendar), "On until sunrise")
    }

    func testManualOnWithoutScheduleEndsAtStoredEndTime() {
        let calendar = utcCalendar
        var state = makeState(active: true, enabled: true, mode: .off, schedule: .defaultSchedule)
        state.override = .onUntilNextTransition

        XCTAssertEqual(subtitle(state, at: date(hour: 20), calendar), "On until tomorrow 07:00")
        state.enabled = false
        state.override = NightShiftOverride.none
        XCTAssertNil(subtitle(state, at: date(hour: 20), calendar))
    }

    func testSessionOverridesHaveNoPredictableEnd() {
        var state = makeState(active: true, enabled: true, mode: .custom)
        state.override = .onForSession
        XCTAssertNil(subtitle(state, at: date(hour: 23), utcCalendar))
    }

    func testAlwaysOnIsRecognizedFromTheNativeSchedule() {
        let alwaysOn = NightShiftAlwaysOn.schedule(resumingAt: TimeOfDay(hour: 5, minute: 0))
        XCTAssertEqual(alwaysOn, NightShiftScheduleState(start: .init(hour: 5, minute: 0), end: .init(hour: 4, minute: 59)))
        XCTAssertEqual(NightShiftAlwaysOn.schedule(resumingAt: .init(hour: 0, minute: 0)).end, TimeOfDay(hour: 23, minute: 59))
        XCTAssertEqual(NightShiftSchedulePreset.current(mode: .custom, schedule: alwaysOn), .alwaysOn)
        XCTAssertEqual(NightShiftSchedulePreset.current(mode: .custom, schedule: .defaultSchedule), .custom)

        var state = makeState(active: true, enabled: true, mode: .custom, schedule: alwaysOn)
        XCTAssertEqual(subtitle(state, at: date(hour: 23), utcCalendar), "Always on")
        state.enabled = false
        state.override = .offUntilNextTransition
        XCTAssertEqual(subtitle(state, at: date(hour: 23), utcCalendar), "Off until tomorrow 05:00")
    }

    func testAlwaysOnSavesThePreviousScheduleAndLeavingItRestoresTheCustomTimes() {
        let clock = TestClock(date(hour: 14))
        let previous = NightShiftScheduleState(start: .init(hour: 21, minute: 0), end: .init(hour: 6, minute: 30))
        let client = FakeNightShiftClient(
            state: makeState(active: true, enabled: false, mode: .custom, schedule: previous),
            clock: clock
        )
        let nightShift = makeSwitch(client, clock: clock)

        XCTAssertNil(nightShift.applySchedule(.alwaysOn, customSchedule: previous))
        XCTAssertEqual(client.state?.schedule, NightShiftAlwaysOn.schedule(resumingAt: NightShiftAlwaysOn.defaultResumeTime))
        XCTAssertEqual(client.state?.enabled, true)
        XCTAssertEqual(nightShift.restoredCustomSchedule, previous)

        XCTAssertNil(nightShift.applySchedule(.sunsetToSunrise, customSchedule: previous))
        XCTAssertEqual(client.state?.scheduleMode, .sunsetToSunrise)
        XCTAssertEqual(client.state?.schedule, previous)
        XCTAssertNil(nightShift.scheduleBackup)
    }

    func testAlwaysOnKeepsAnExistingFullDaySchedule() {
        let existing = NightShiftAlwaysOn.schedule(resumingAt: .init(hour: 3, minute: 30))
        let client = FakeNightShiftClient(
            state: makeState(active: true, enabled: true, mode: .custom, schedule: existing),
            clock: TestClock(date(hour: 14))
        )
        let nightShift = makeSwitch(client)

        XCTAssertNil(nightShift.applySchedule(.alwaysOn, customSchedule: .defaultSchedule))
        XCTAssertFalse(client.operations.contains(.setSchedule(NightShiftAlwaysOn.schedule(resumingAt: NightShiftAlwaysOn.defaultResumeTime))))
        XCTAssertEqual(client.state?.schedule, existing)
    }

    func testAlwaysOnUsesASessionOverrideSoTheDailyWrapIsInvisible() {
        let clock = TestClock(date(hour: 14))
        let client = FakeNightShiftClient(
            state: makeState(active: true, enabled: false, mode: .sunsetToSunrise),
            clock: clock
        )
        let nightShift = makeSwitch(client, clock: clock)

        XCTAssertNil(nightShift.applySchedule(.alwaysOn, customSchedule: .defaultSchedule))
        XCTAssertEqual(client.operations.last, .setEnabledForSession(true))
        XCTAssertEqual(client.state?.override, .onForSession)
        XCTAssertEqual(nightShift.snapshot().subtitle, "Always on")

        // macOS drops the session override after a long display sleep; Mac Switch reapplies it.
        client.state?.override = NightShiftOverride.none
        nightShift.reconcileAlwaysOn()
        XCTAssertEqual(client.state?.override, .onForSession)
    }

    func testAlwaysOnNeverTurnsNightShiftBackOnAfterTheUserTurnsItOff() {
        var state = makeState(active: true, enabled: false, mode: .custom, schedule: NightShiftAlwaysOn.schedule(resumingAt: NightShiftAlwaysOn.defaultResumeTime))
        state.override = .offUntilNextTransition
        let client = FakeNightShiftClient(state: state, clock: TestClock(date(hour: 14)))
        let nightShift = makeSwitch(client)

        nightShift.reconcileAlwaysOn()
        XCTAssertEqual(client.operations, [])

        client.state?.enabled = true
        client.state?.override = nil
        nightShift.reconcileAlwaysOn()
        XCTAssertEqual(client.operations, [], "An unreadable override must not be overwritten")
    }

    func testLeavingAlwaysOnHandsControlBackToTheSchedule() {
        let clock = TestClock(date(hour: 14))
        let client = FakeNightShiftClient(
            state: makeState(active: true, enabled: false, mode: .custom, schedule: .defaultSchedule),
            clock: clock
        )
        let nightShift = makeSwitch(client, clock: clock)
        XCTAssertNil(nightShift.applySchedule(.alwaysOn, customSchedule: .defaultSchedule))
        XCTAssertEqual(client.state?.override, .onForSession)

        // Same custom mode, so only releasing the session override lets 22:00-07:00 turn it off at 14:00.
        XCTAssertNil(nightShift.applySchedule(.custom, customSchedule: .defaultSchedule))
        XCTAssertEqual(client.state?.schedule, .defaultSchedule)
        XCTAssertEqual(client.state?.enabled, false)
        XCTAssertEqual(client.state?.override, .offUntilNextTransition)
    }

    func testASessionOverrideSetElsewhereIsLeftAlone() {
        var state = makeState(active: true, enabled: true, mode: .custom, schedule: .defaultSchedule)
        state.override = .onForSession
        let client = FakeNightShiftClient(state: state, clock: TestClock(date(hour: 14)))
        let nightShift = makeSwitch(client)

        nightShift.reconcileAlwaysOn()
        XCTAssertEqual(client.operations, [])
        XCTAssertEqual(client.state?.enabled, true)
    }

    func testKeepingTheSwitchStateHoldsItThroughTheScheduleAndRestoresTheSchedule() {
        let clock = TestClock(date(hour: 23))
        let client = FakeNightShiftClient(
            state: makeState(active: true, enabled: true, mode: .custom, schedule: .defaultSchedule),
            clock: clock
        )
        let nightShift = makeSwitch(client, clock: clock)

        XCTAssertNil(nightShift.setKeepsSwitchState(true))
        XCTAssertTrue(nightShift.keepsSwitchState)
        XCTAssertTrue(NightShiftAlwaysOn.isActive(try XCTUnwrap(client.state)))
        XCTAssertEqual(nightShift.scheduleBackup, NightShiftScheduleBackup(mode: .custom, schedule: .defaultSchedule))

        XCTAssertNil(nightShift.setEnabled(false))
        XCTAssertEqual(client.state?.scheduleMode, .off)
        XCTAssertEqual(client.state?.enabled, false)
        XCTAssertEqual(client.state?.override, NightShiftOverride.none)

        XCTAssertNil(nightShift.setEnabled(true))
        XCTAssertTrue(NightShiftAlwaysOn.isActive(try XCTUnwrap(client.state)))
        XCTAssertEqual(client.state?.enabled, true)

        XCTAssertNil(nightShift.setKeepsSwitchState(false))
        XCTAssertEqual(client.state?.scheduleMode, .custom)
        XCTAssertEqual(client.state?.schedule, .defaultSchedule)
        XCTAssertNil(nightShift.scheduleBackup)
    }

    func testTurningOffKeepSwitchStateLeavesAScheduleChangedElsewhere() {
        let clock = TestClock(date(hour: 12))
        let client = FakeNightShiftClient(
            state: makeState(active: true, enabled: false, mode: .sunsetToSunrise),
            clock: clock
        )
        let nightShift = makeSwitch(client, clock: clock)
        XCTAssertNil(nightShift.setKeepsSwitchState(true))
        XCTAssertEqual(client.state?.scheduleMode, .off)

        let changedElsewhere = NightShiftScheduleState(start: .init(hour: 20, minute: 0), end: .init(hour: 6, minute: 0))
        client.state?.scheduleMode = .custom
        client.state?.schedule = changedElsewhere
        client.operations.removeAll()

        XCTAssertNil(nightShift.setKeepsSwitchState(false))
        XCTAssertEqual(client.operations, [])
        XCTAssertEqual(client.state?.schedule, changedElsewhere)
        XCTAssertNil(nightShift.scheduleBackup)
    }

    func testTheDefaultSwitchUsesTemporarySystemChanges() {
        let client = FakeNightShiftClient(state: makeState(active: true, enabled: true, mode: .sunsetToSunrise))
        let nightShift = makeSwitch(client)

        XCTAssertNil(nightShift.setEnabled(false))
        XCTAssertEqual(client.operations, [.setEnabled(false)])
        XCTAssertEqual(client.state?.scheduleMode, .sunsetToSunrise)
        XCTAssertNil(nightShift.scheduleBackup)
    }

    func testModeRestoreReturnsToTheScheduleInsteadOfAStaleState() throws {
        let clock = TestClock(date(hour: 22))
        let client = FakeNightShiftClient(
            state: makeState(active: true, enabled: true, mode: .custom, schedule: .defaultSchedule),
            clock: clock
        )
        client.state?.override = NightShiftOverride.none
        let nightShift = makeSwitch(client, clock: clock)
        let point = try XCTUnwrap(nightShift.captureRestorePoint())
        XCTAssertTrue(point.followsSchedule)

        XCTAssertNil(nightShift.hold(false))
        XCTAssertEqual(client.state?.scheduleMode, .off)

        clock.date = date(day: 28, hour: 9)
        XCTAssertNil(nightShift.restore(point))
        XCTAssertEqual(client.state?.scheduleMode, .custom)
        XCTAssertEqual(client.state?.schedule, .defaultSchedule)
        XCTAssertEqual(client.state?.enabled, false, "Daytime restore must follow the schedule, not the captured on state")
    }

    func testModeRestoreKeepsAManualChangeUntilItWouldHaveEnded() throws {
        let clock = TestClock(date(hour: 15))
        var captured = makeState(active: true, enabled: true, mode: .custom, schedule: .defaultSchedule)
        captured.override = .onUntilNextTransition
        let point = try XCTUnwrap(NightShiftRestorePoint(state: captured, now: clock.date, calendar: utcCalendar))
        XCTAssertFalse(point.followsSchedule)
        XCTAssertEqual(point.overrideExpiry, date(day: 28, hour: 7))

        XCTAssertTrue(point.desiredState(sunTimes: nil, at: date(hour: 16), calendar: utcCalendar))
        XCTAssertFalse(point.desiredState(sunTimes: nil, at: date(day: 28, hour: 8), calendar: utcCalendar))
    }

    func testRestorePointsDecodeAndRoundTrip() throws {
        let point = NightShiftRestorePoint(
            enabled: true,
            mode: .sunsetToSunrise,
            schedule: .defaultSchedule,
            followsSchedule: false,
            overrideExpiry: date(hour: 7)
        )
        let decoded = try JSONDecoder().decode(NightShiftRestorePoint.self, from: JSONEncoder().encode(point))
        XCTAssertEqual(decoded, point)
    }

    func testChangeClassifierExplainsWhoChangedNightShift() {
        let before = makeState(active: true, enabled: true, mode: .sunsetToSunrise)
        var after = before
        after.enabled = false

        XCTAssertEqual(NightShiftChangeClassifier.cause(from: before, to: after, initiatedByMacSwitch: true), .macSwitch)
        XCTAssertEqual(NightShiftChangeClassifier.cause(from: before, to: after, initiatedByMacSwitch: false), .schedule)

        var manual = after
        manual.override = .offUntilNextTransition
        XCTAssertEqual(NightShiftChangeClassifier.cause(from: before, to: manual, initiatedByMacSwitch: false), .manualElsewhere)

        var overridden = before
        overridden.override = .onUntilNextTransition
        var resumed = after
        resumed.override = NightShiftOverride.none
        XCTAssertEqual(NightShiftChangeClassifier.cause(from: overridden, to: resumed, initiatedByMacSwitch: false), .overrideEnded)

        var modeChanged = before
        modeChanged.scheduleMode = .off
        XCTAssertEqual(NightShiftChangeClassifier.cause(from: before, to: modeChanged, initiatedByMacSwitch: false), .scheduleSettings)

        var locationChanged = modeChanged
        locationChanged.sunSchedulePermitted = false
        XCTAssertEqual(NightShiftChangeClassifier.cause(from: before, to: locationChanged, initiatedByMacSwitch: false), .sunSchedulePermission)

        var unavailable = before
        unavailable.available = false
        XCTAssertEqual(NightShiftChangeClassifier.cause(from: before, to: unavailable, initiatedByMacSwitch: false), .availability)

        var strengthOnly = before
        strengthOnly.strength = 0.9
        XCTAssertNil(NightShiftChangeClassifier.cause(from: before, to: strengthOnly, initiatedByMacSwitch: false))
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

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(day: Int = 27, hour: Int, minute: Int = 0) -> Date {
        utcCalendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }

    private func subtitle(_ state: NightShiftState, at now: Date, _ calendar: Calendar) -> String? {
        NightShiftSchedulePlanner.subtitle(for: state, now: now, calendar: calendar)
    }

    private func makeSwitch(_ client: FakeNightShiftClient, clock: TestClock? = nil) -> NightShiftSwitch {
        let calendar = utcCalendar
        let clock = clock ?? TestClock(date(hour: 12))
        return NightShiftSwitch(
            client: client,
            defaults: InMemoryUserDefaults(),
            now: { clock.date },
            calendar: { calendar }
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

private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ date: Date) {
        current = date
    }

    var date: Date {
        get { lock.withLock { current } }
        set { lock.withLock { current = newValue } }
    }
}

private final class FakeNightShiftClient: NightShiftClientProtocol, @unchecked Sendable {
    enum Operation: Equatable {
        case setActive(Bool)
        case setEnabled(Bool)
        case setEnabledForSession(Bool)
        case setScheduleMode(NightShiftScheduleMode)
        case setSchedule(NightShiftScheduleState)
    }

    var onStatusChange: (@Sendable () -> Void)?
    var state: NightShiftState?
    var operations: [Operation] = []
    // With a clock, the fake follows corebrightnessd: a manual change is an override,
    // and changing the mode clears it so the schedule decides again.
    private let clock: TestClock?
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    init(state: NightShiftState?, clock: TestClock? = nil) {
        self.state = state
        self.clock = clock
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
        if clock != nil, let mode = state?.scheduleMode {
            state?.override = mode == .off && !enabled
                ? NightShiftOverride.none
                : (enabled ? .onUntilNextTransition : .offUntilNextTransition)
        }
        onStatusChange?()
        return true
    }

    func setEnabledForSession(_ enabled: Bool) -> Bool {
        operations.append(.setEnabledForSession(enabled))
        state?.enabled = enabled
        state?.override = enabled ? .onForSession : .offForSession
        onStatusChange?()
        return true
    }

    func setScheduleMode(_ mode: NightShiftScheduleMode) -> Bool {
        operations.append(.setScheduleMode(mode))
        let changed = state?.scheduleMode != mode
        state?.scheduleMode = mode
        if changed {
            followSchedule()
        }
        onStatusChange?()
        return true
    }

    func setSchedule(_ schedule: NightShiftScheduleState) -> Bool {
        operations.append(.setSchedule(schedule))
        state?.schedule = schedule
        if state?.override == NightShiftOverride.none {
            followSchedule()
        }
        onStatusChange?()
        return true
    }

    private func followSchedule() {
        guard let clock, let current = state else { return }
        state?.override = NightShiftOverride.none
        state?.enabled = NightShiftSchedulePlanner.scheduledState(
            mode: current.scheduleMode,
            schedule: current.schedule,
            sunTimes: current.sunTimes,
            at: clock.date,
            calendar: calendar
        ) ?? current.enabled
    }
}
