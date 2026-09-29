import Foundation

/// Mirrors corebrightnessd's `BlueLightReductionAlgoOverride`.
/// A manual Night Shift change is an override of the macOS schedule, not a setting:
/// `setEnabled:` creates a transition-bound override that the daemon clears at the next
/// scheduled edge, while the session overrides are cleared after 30 minutes of display sleep.
enum NightShiftOverride: Int, Codable, Sendable {
    case none = 0
    case offForSession = 1
    case onForSession = 2
    case offUntilNextTransition = 3
    case onUntilNextTransition = 4

    var isManual: Bool {
        self != .none
    }

    var isSessionBound: Bool {
        self == .offForSession || self == .onForSession
    }
}

/// Sunrise and sunset times reported by CoreBrightness for the Sunset to Sunrise schedule.
struct NightShiftSunTimes: Equatable, Sendable {
    var sunrises: [Date]
    var sunsets: [Date]

    init(sunrises: [Date], sunsets: [Date]) {
        self.sunrises = sunrises.sorted()
        self.sunsets = sunsets.sorted()
    }

    init?(dictionary: [String: Any]) {
        let sunrises = ["previousSunrise", "sunrise", "nextSunrise"].compactMap { dictionary[$0] as? Date }
        let sunsets = ["previousSunset", "sunset", "nextSunset"].compactMap { dictionary[$0] as? Date }
        guard !sunrises.isEmpty, !sunsets.isEmpty else { return nil }
        self.init(sunrises: sunrises, sunsets: sunsets)
    }
}

enum NightShiftSchedulePreset: String, CaseIterable, Identifiable, Sendable {
    case off
    case sunsetToSunrise
    case custom
    case alwaysOn

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "Off"
        case .sunsetToSunrise: return "Sunset to Sunrise"
        case .custom: return "Custom"
        case .alwaysOn: return "Always On"
        }
    }

    static func current(mode: NightShiftScheduleMode?, schedule: NightShiftScheduleState) -> NightShiftSchedulePreset {
        switch mode {
        case .sunsetToSunrise:
            return .sunsetToSunrise
        case .custom:
            return NightShiftAlwaysOn.matches(schedule) ? .alwaysOn : .custom
        case .off, .none:
            return .off
        }
    }
}

/// Always On is the native macOS way to keep Night Shift on: a custom schedule that covers
/// the whole day except one minute. An empty gap would mean a night of zero length (always off).
enum NightShiftAlwaysOn {
    static let defaultResumeTime = TimeOfDay(hour: 5, minute: 0)

    static func schedule(resumingAt time: TimeOfDay) -> NightShiftScheduleState {
        NightShiftScheduleState(start: time, end: time.addingMinutes(-1))
    }

    static func matches(_ schedule: NightShiftScheduleState) -> Bool {
        schedule.end == schedule.start.addingMinutes(-1)
    }

    static func isActive(_ state: NightShiftState) -> Bool {
        state.scheduleMode == .custom && matches(state.schedule)
    }
}

enum NightShiftEdge: Equatable, Sendable {
    case at(Date)
    case sunrise
    case sunset
}

enum NightShiftSchedulePlanner {
    /// The next time the schedule turns Night Shift on (`turningOn`) or off.
    /// With the schedule off, macOS ends a manual "on" at the stored custom end time.
    static func nextEdge(
        turningOn: Bool,
        mode: NightShiftScheduleMode?,
        schedule: NightShiftScheduleState,
        sunTimes: NightShiftSunTimes?,
        after now: Date,
        calendar: Calendar
    ) -> NightShiftEdge? {
        switch mode {
        case .sunsetToSunrise:
            let candidates = turningOn ? sunTimes?.sunsets : sunTimes?.sunrises
            if let next = candidates?.first(where: { $0 > now }) {
                return .at(next)
            }
            return turningOn ? .sunset : .sunrise
        case .custom:
            return .at(nextOccurrence(of: turningOn ? schedule.start : schedule.end, after: now, calendar: calendar))
        case .off, .none:
            guard !turningOn else { return nil }
            return .at(nextOccurrence(of: schedule.end, after: now, calendar: calendar))
        }
    }

    /// Whether the schedule alone would have Night Shift on at `now`; nil when unknown.
    static func scheduledState(
        mode: NightShiftScheduleMode?,
        schedule: NightShiftScheduleState,
        sunTimes: NightShiftSunTimes?,
        at now: Date,
        calendar: Calendar
    ) -> Bool? {
        switch mode {
        case .off:
            return false
        case .custom:
            let components = calendar.dateComponents([.hour, .minute], from: now)
            let minutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
            return schedule.start.contains(currentMinutes: minutes, until: schedule.end)
        case .sunsetToSunrise:
            guard let sunTimes else { return nil }
            let lastSunrise = sunTimes.sunrises.last { $0 <= now }
            let lastSunset = sunTimes.sunsets.last { $0 <= now }
            switch (lastSunrise, lastSunset) {
            case let (sunrise?, sunset?):
                return sunset > sunrise
            case (nil, _?):
                return true
            case (_?, nil):
                return false
            case (nil, nil):
                return nil
            }
        case .none:
            return nil
        }
    }

    /// When macOS will change the current state by itself, if it will.
    static func until(for state: NightShiftState, now: Date, calendar: Calendar) -> NightShiftEdge? {
        guard state.isAvailable, state.override?.isSessionBound != true else { return nil }
        return nextEdge(
            turningOn: !state.enabled,
            mode: state.scheduleMode,
            schedule: state.schedule,
            sunTimes: state.sunTimes,
            after: now,
            calendar: calendar
        )
    }

    static func subtitle(for state: NightShiftState, now: Date, calendar: Calendar) -> String? {
        guard state.isAvailable else { return nil }
        if state.enabled, NightShiftAlwaysOn.isActive(state) {
            return "Always on"
        }
        guard let edge = until(for: state, now: now, calendar: calendar) else { return nil }
        let prefix = state.enabled ? "On until" : "Off until"
        switch edge {
        case .sunrise:
            return "On until sunrise"
        case .sunset:
            return "Off until sunset"
        case .at(let date):
            let components = calendar.dateComponents([.hour, .minute], from: date)
            let time = TimeOfDay(hour: components.hour ?? 0, minute: components.minute ?? 0).display
            return calendar.isDate(date, inSameDayAs: now) ? "\(prefix) \(time)" : "\(prefix) tomorrow \(time)"
        }
    }

    static func nextOccurrence(of time: TimeOfDay, after now: Date, calendar: Calendar) -> Date {
        let matching = DateComponents(hour: time.hour, minute: time.minute, second: 0)
        return calendar.nextDate(after: now, matching: matching, matchingPolicy: .nextTime)
            ?? now.addingTimeInterval(24 * 60 * 60)
    }
}

/// The Night Shift state a Mode replaces, captured so it can be restored exactly.
struct NightShiftRestorePoint: Codable, Equatable, Sendable {
    var enabled: Bool
    var modeRawValue: Int32
    var schedule: NightShiftScheduleState
    var followsSchedule: Bool
    var overrideExpiry: Date?

    var mode: NightShiftScheduleMode? {
        NightShiftScheduleMode(rawValue: modeRawValue)
    }

    init(
        enabled: Bool,
        mode: NightShiftScheduleMode,
        schedule: NightShiftScheduleState,
        followsSchedule: Bool,
        overrideExpiry: Date?
    ) {
        self.enabled = enabled
        self.modeRawValue = mode.rawValue
        self.schedule = schedule
        self.followsSchedule = followsSchedule
        self.overrideExpiry = overrideExpiry
    }

    init?(state: NightShiftState, now: Date, calendar: Calendar) {
        guard state.isAvailable, let mode = state.scheduleMode else { return nil }
        let followsSchedule: Bool
        if let override = state.override {
            followsSchedule = !override.isManual
        } else {
            let scheduled = NightShiftSchedulePlanner.scheduledState(
                mode: mode,
                schedule: state.schedule,
                sunTimes: state.sunTimes,
                at: now,
                calendar: calendar
            )
            followsSchedule = scheduled == state.enabled
        }
        var expiry: Date?
        if !followsSchedule,
           state.override?.isSessionBound != true,
           case .at(let date) = NightShiftSchedulePlanner.until(for: state, now: now, calendar: calendar) {
            expiry = date
        }
        self.init(
            enabled: state.enabled,
            mode: mode,
            schedule: state.schedule,
            followsSchedule: followsSchedule,
            overrideExpiry: expiry
        )
    }

    /// The on/off state to restore: what the schedule dictates now, unless the replaced
    /// manual change would still be in effect.
    func desiredState(sunTimes: NightShiftSunTimes?, at now: Date, calendar: Calendar) -> Bool {
        let followsNow = followsSchedule || overrideExpiry.map { $0 <= now } == true
        guard followsNow else { return enabled }
        return NightShiftSchedulePlanner.scheduledState(
            mode: mode,
            schedule: schedule,
            sunTimes: sunTimes,
            at: now,
            calendar: calendar
        ) ?? enabled
    }
}

/// The user's own schedule, saved while Mac Switch keeps the switch as set.
struct NightShiftScheduleBackup: Codable, Equatable, Sendable {
    var modeRawValue: Int32
    var schedule: NightShiftScheduleState

    var mode: NightShiftScheduleMode {
        NightShiftScheduleMode(rawValue: modeRawValue) ?? .off
    }

    init(mode: NightShiftScheduleMode, schedule: NightShiftScheduleState) {
        self.modeRawValue = mode.rawValue
        self.schedule = schedule
    }
}

enum NightShiftChangeCause: String, Codable, Sendable {
    case macSwitch
    case schedule
    case overrideEnded
    case manualElsewhere
    case scheduleSettings
    case sunSchedulePermission
    case availability

    func description(enabled: Bool) -> String {
        switch self {
        case .macSwitch:
            return "Changed by Mac Switch."
        case .schedule:
            return enabled
                ? "The macOS schedule turned Night Shift on."
                : "The macOS schedule turned Night Shift off."
        case .overrideEnded:
            return "A temporary change ended and the macOS schedule resumed."
        case .manualElsewhere:
            return "Changed in Control Center or System Settings."
        case .scheduleSettings:
            return "The Night Shift schedule was changed outside Mac Switch."
        case .sunSchedulePermission:
            return "Location access for Sunset to Sunrise changed."
        case .availability:
            return "The current display or display preset changed Night Shift availability."
        }
    }
}

struct NightShiftChangeRecord: Codable, Equatable, Sendable {
    var date: Date
    var cause: NightShiftChangeCause
    var enabled: Bool
    var modeRawValue: Int32?
}

enum NightShiftChangeClassifier {
    static func hasRelevantChange(from before: NightShiftState, to after: NightShiftState) -> Bool {
        before.enabled != after.enabled ||
            before.scheduleMode != after.scheduleMode ||
            before.schedule != after.schedule ||
            before.isAvailable != after.isAvailable ||
            before.disableFlags != after.disableFlags ||
            before.sunSchedulePermitted != after.sunSchedulePermitted
    }

    static func cause(
        from before: NightShiftState,
        to after: NightShiftState,
        initiatedByMacSwitch: Bool
    ) -> NightShiftChangeCause? {
        guard hasRelevantChange(from: before, to: after) else { return nil }
        if initiatedByMacSwitch {
            return .macSwitch
        }
        if before.isAvailable != after.isAvailable || before.disableFlags != after.disableFlags {
            return .availability
        }
        if before.sunSchedulePermitted != after.sunSchedulePermitted {
            return .sunSchedulePermission
        }
        if before.scheduleMode != after.scheduleMode || before.schedule != after.schedule {
            return .scheduleSettings
        }
        if after.override?.isManual == true {
            return .manualElsewhere
        }
        if before.override?.isManual == true {
            return .overrideEnded
        }
        return .schedule
    }
}

struct NightShiftTransactionRecovery: Codable, Sendable {
    let point: NightShiftRestorePoint
    let active: Bool
    let override: NightShiftOverride?
    let backup: NightShiftScheduleBackup?
    let keepsSwitchState: Bool
}

enum NightShiftPreferenceKey {
    static let pendingRecovery = "nightShift.pendingRecovery.v1"
    static let keepsSwitchState = "nightShift.keepsSwitchState"
    static let scheduleBackup = "nightShift.scheduleBackup"
    static let lastChange = "nightShift.lastChange"
}

extension TimeOfDay {
    func addingMinutes(_ minutes: Int) -> TimeOfDay {
        let total = ((minutesSinceMidnight + minutes) % 1440 + 1440) % 1440
        return TimeOfDay(hour: total / 60, minute: total % 60)
    }
}
