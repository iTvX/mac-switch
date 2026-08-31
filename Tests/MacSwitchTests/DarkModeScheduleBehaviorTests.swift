import XCTest
@testable import MacSwitch

final class DarkModeScheduleBehaviorTests: XCTestCase {
    func testManualAndAllDaySchedulesDoNotCreateIdleTimers() {
        let calendar = makeCalendar()
        let now = date(2026, 1, 15, 12, 0, calendar: calendar)

        XCTAssertNil(
            DarkModeSchedulePlanner.nextTransition(
                mode: .manual,
                start: .defaultDarkStart,
                end: .defaultDarkEnd,
                after: now,
                calendar: calendar
            )
        )
        XCTAssertNil(
            DarkModeSchedulePlanner.nextTransition(
                mode: .custom,
                start: TimeOfDay(hour: 8, minute: 0),
                end: TimeOfDay(hour: 8, minute: 0),
                after: now,
                calendar: calendar
            )
        )
    }

    func testCustomScheduleChoosesTheNextBoundaryAcrossMidnight() {
        let calendar = makeCalendar()
        let start = TimeOfDay(hour: 22, minute: 0)
        let end = TimeOfDay(hour: 7, minute: 0)

        XCTAssertEqual(
            DarkModeSchedulePlanner.nextTransition(
                mode: .custom,
                start: start,
                end: end,
                after: date(2026, 1, 15, 21, 30, calendar: calendar),
                calendar: calendar
            ),
            date(2026, 1, 15, 22, 0, calendar: calendar)
        )
        XCTAssertEqual(
            DarkModeSchedulePlanner.nextTransition(
                mode: .custom,
                start: start,
                end: end,
                after: date(2026, 1, 15, 23, 0, calendar: calendar),
                calendar: calendar
            ),
            date(2026, 1, 16, 7, 0, calendar: calendar)
        )
    }

    func testSunScheduleChoosesAFutureEventFromCurrentAndNextDay() {
        let calendar = makeCalendar()
        let today = SunWindow(
            sunrise: date(2026, 1, 15, 7, 10, calendar: calendar),
            sunset: date(2026, 1, 15, 17, 5, calendar: calendar)
        )
        let tomorrow = SunWindow(
            sunrise: date(2026, 1, 16, 7, 9, calendar: calendar),
            sunset: date(2026, 1, 16, 17, 6, calendar: calendar)
        )

        XCTAssertEqual(
            DarkModeSchedulePlanner.nextTransition(
                mode: .sunriseSunset,
                start: .defaultDarkStart,
                end: .defaultDarkEnd,
                sunWindows: [today, tomorrow],
                after: date(2026, 1, 15, 12, 0, calendar: calendar),
                calendar: calendar
            ),
            today.sunset
        )
        XCTAssertEqual(
            DarkModeSchedulePlanner.nextTransition(
                mode: .sunriseSunset,
                start: .defaultDarkStart,
                end: .defaultDarkEnd,
                sunWindows: [today, tomorrow],
                after: date(2026, 1, 15, 23, 0, calendar: calendar),
                calendar: calendar
            ),
            tomorrow.sunrise
        )
    }

    func testCustomScheduleHandlesANonexistentDaylightSavingTime() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let now = date(2026, 3, 8, 1, 50, calendar: calendar)

        let transition = try XCTUnwrap(
            DarkModeSchedulePlanner.nextTransition(
                mode: .custom,
                start: TimeOfDay(hour: 2, minute: 30),
                end: TimeOfDay(hour: 7, minute: 0),
                after: now,
                calendar: calendar
            )
        )
        let components = calendar.dateComponents([.year, .month, .day, .hour], from: transition)

        XCTAssertGreaterThan(transition, now)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 3)
        XCTAssertEqual(components.day, 8)
        XCTAssertEqual(components.hour, 3)
    }

    private func makeCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        _ minute: Int,
        calendar: Calendar
    ) -> Date {
        calendar.date(
            from: DateComponents(
                calendar: calendar,
                timeZone: calendar.timeZone,
                year: year,
                month: month,
                day: day,
                hour: hour,
                minute: minute,
                second: 0
            )
        )!
    }
}
