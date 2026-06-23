import AppKit
import Foundation
import SwiftUI

extension Notification.Name {
    static let openMacSwitchPreferences = Notification.Name("openMacSwitchPreferences")
    static let setMacSwitchPreferencesLayout = Notification.Name("setMacSwitchPreferencesLayout")
    static let quitMacSwitch = Notification.Name("quitMacSwitch")
}

enum SwitchKind: String, CaseIterable, Codable, Identifiable {
    case stageManager
    case hideWidgets
    case muteMicrophone
    case hideDesktopIcons
    case darkMode
    case keepAwake
    case screenSaver
    case bluetoothAudio
    case doNotDisturb
    case nightShift
    case trueTone
    case playMusic
    case showHiddenFiles
    case displaySleep
    case screenResolution
    case screenClean
    case lockKeyboard
    case lockScreen
    case xcodeClean
    case emptyTrash
    case ejectDisk
    case emptyPasteboard
    case hideWindows
    case hideDock
    case lowPowerMode
    case energyMode

    var id: String { rawValue }

    var title: String {
        switch self {
        case .stageManager: return "Stage Manager"
        case .hideWidgets: return "Hide Widgets"
        case .muteMicrophone: return "Mute Microphone"
        case .hideDesktopIcons: return "Hide Desktop Icons"
        case .darkMode: return "Dark Mode"
        case .keepAwake: return "Keep Awake"
        case .screenSaver: return "Screen Saver"
        case .bluetoothAudio: return "Bluetooth Audio"
        case .doNotDisturb: return "Do Not Disturb"
        case .nightShift: return "Night Shift"
        case .trueTone: return "True Tone"
        case .playMusic: return "Play Music"
        case .showHiddenFiles: return "Show Hidden Files"
        case .displaySleep: return "Display Sleep"
        case .screenResolution: return "Screen Resolution"
        case .screenClean: return "Screen Cleaning"
        case .lockKeyboard: return "Lock Keyboard"
        case .lockScreen: return "Lock Screen"
        case .xcodeClean: return "Xcode Cache Clean"
        case .emptyTrash: return "Empty Trash"
        case .ejectDisk: return "Eject Disk"
        case .emptyPasteboard: return "Empty Pasteboard"
        case .hideWindows: return "Hide Windows"
        case .hideDock: return "Hide Dock"
        case .lowPowerMode: return "Low Power Mode"
        case .energyMode: return "Energy Mode"
        }
    }

    var symbolName: String {
        switch self {
        case .stageManager: return "rectangle.3.group.fill"
        case .hideWidgets: return "rectangle.grid.2x2"
        case .muteMicrophone: return "mic.slash.fill"
        case .hideDesktopIcons: return "square.grid.3x3.square"
        case .darkMode: return "sun.max.fill"
        case .keepAwake: return "cup.and.saucer.fill"
        case .screenSaver: return "display"
        case .bluetoothAudio: return "headphones"
        case .doNotDisturb: return "moon.fill"
        case .nightShift: return "sun.max.fill"
        case .trueTone: return "sun.max.circle.fill"
        case .playMusic: return "music.note"
        case .showHiddenFiles: return "eye.fill"
        case .displaySleep: return "display.trianglebadge.exclamationmark"
        case .screenResolution: return "rectangle.inset.filled"
        case .screenClean: return "paintbrush.pointed.fill"
        case .lockKeyboard: return "keyboard.fill"
        case .lockScreen: return "lock.display"
        case .xcodeClean: return "hammer.fill"
        case .emptyTrash: return "trash.fill"
        case .ejectDisk: return "eject.fill"
        case .emptyPasteboard: return "doc.on.clipboard"
        case .hideWindows: return "macwindow.on.rectangle"
        case .hideDock: return "dock.rectangle"
        case .lowPowerMode: return "battery.25percent"
        case .energyMode: return "bolt.circle.fill"
        }
    }

    var isMomentaryAction: Bool {
        switch self {
        case .screenSaver, .displaySleep, .lockScreen, .xcodeClean, .emptyTrash, .ejectDisk, .emptyPasteboard, .hideWindows:
            return true
        default:
            return false
        }
    }

    var defaultEnabled: Bool {
        switch self {
        case .stageManager, .hideDesktopIcons, .darkMode, .keepAwake,
             .screenSaver, .nightShift, .screenClean, .lockKeyboard:
            return true
        default:
            return false
        }
    }
}

enum KeepAwakeDuration: String, CaseIterable, Codable, Identifiable {
    case indefinitely
    case fiveMinutes
    case fifteenMinutes
    case twentyFiveMinutes
    case thirtyMinutes
    case oneHour
    case twoHours
    case fiveHours
    case eightHours

    var id: String { rawValue }

    static var allCases: [KeepAwakeDuration] {
        [
            .indefinitely,
            .fiveMinutes,
            .fifteenMinutes,
            .twentyFiveMinutes,
            .thirtyMinutes,
            .oneHour,
            .twoHours,
            .fiveHours,
            .eightHours
        ]
    }

    var menuTitle: String {
        switch self {
        case .indefinitely: return "Indefinitely"
        case .fiveMinutes: return "5 Minutes"
        case .fifteenMinutes: return "15 Minutes"
        case .twentyFiveMinutes: return "25 Minutes"
        case .thirtyMinutes: return "30 Minutes"
        case .oneHour: return "1 Hour"
        case .twoHours: return "2 Hours"
        case .fiveHours: return "5 Hours"
        case .eightHours: return "8 Hours"
        }
    }

    var dashboardSubtitle: String {
        switch self {
        case .indefinitely: return "Activate indefinitely"
        default: return "Activate for \(menuTitle.lowercased())"
        }
    }

    var seconds: TimeInterval? {
        switch self {
        case .indefinitely: return nil
        case .fiveMinutes: return 5 * 60
        case .fifteenMinutes: return 15 * 60
        case .twentyFiveMinutes: return 25 * 60
        case .thirtyMinutes: return 30 * 60
        case .oneHour: return 60 * 60
        case .twoHours: return 2 * 60 * 60
        case .fiveHours: return 5 * 60 * 60
        case .eightHours: return 8 * 60 * 60
        }
    }
}

enum DoNotDisturbDuration: String, CaseIterable, Codable, Identifiable {
    case indefinitely
    case fiveMinutes
    case fifteenMinutes
    case twentyFiveMinutes
    case thirtyMinutes
    case oneHour
    case twoHours
    case fiveHours
    case eightHours
    case tomorrow

    var id: String { rawValue }

    static var allCases: [DoNotDisturbDuration] {
        [
            .indefinitely,
            .fiveMinutes,
            .fifteenMinutes,
            .twentyFiveMinutes,
            .thirtyMinutes,
            .oneHour,
            .twoHours,
            .fiveHours,
            .eightHours,
            .tomorrow
        ]
    }

    var menuTitle: String {
        switch self {
        case .indefinitely: return "Indefinitely"
        case .fiveMinutes: return "5 Minutes"
        case .fifteenMinutes: return "15 Minutes"
        case .twentyFiveMinutes: return "25 Minutes"
        case .thirtyMinutes: return "30 Minutes"
        case .oneHour: return "1 Hour"
        case .twoHours: return "2 Hours"
        case .fiveHours: return "5 Hours"
        case .eightHours: return "8 Hours"
        case .tomorrow: return "Tomorrow"
        }
    }

    var dashboardSubtitle: String {
        switch self {
        case .indefinitely: return "Activate indefinitely"
        case .tomorrow: return "Activate until tomorrow"
        default: return "Activate for \(menuTitle.lowercased())"
        }
    }

    func endDate(from date: Date = Date(), calendar: Calendar = .current) -> Date? {
        switch self {
        case .indefinitely:
            return nil
        case .fiveMinutes:
            return date.addingTimeInterval(5 * 60)
        case .fifteenMinutes:
            return date.addingTimeInterval(15 * 60)
        case .twentyFiveMinutes:
            return date.addingTimeInterval(25 * 60)
        case .thirtyMinutes:
            return date.addingTimeInterval(30 * 60)
        case .oneHour:
            return date.addingTimeInterval(60 * 60)
        case .twoHours:
            return date.addingTimeInterval(2 * 60 * 60)
        case .fiveHours:
            return date.addingTimeInterval(5 * 60 * 60)
        case .eightHours:
            return date.addingTimeInterval(8 * 60 * 60)
        case .tomorrow:
            let startOfToday = calendar.startOfDay(for: date)
            return calendar.date(byAdding: .day, value: 1, to: startOfToday)
        }
    }
}

enum DarkModeScheduleMode: String, CaseIterable, Codable, Identifiable {
    case manual
    case custom
    case sunriseSunset

    var id: String { rawValue }

    var title: String {
        switch self {
        case .manual: return "Switch Manually"
        case .custom: return "Schedule From/To"
        case .sunriseSunset: return "Auto change from sunrise to sunset"
        }
    }
}

struct TimeOfDay: Codable, Equatable, Hashable {
    var hour: Int
    var minute: Int

    static let defaultDarkStart = TimeOfDay(hour: 22, minute: 0)
    static let defaultDarkEnd = TimeOfDay(hour: 7, minute: 0)

    var minutesSinceMidnight: Int {
        hour * 60 + minute
    }

    var display: String {
        String(format: "%02d:%02d", hour, minute)
    }

    func contains(currentMinutes: Int, until end: TimeOfDay) -> Bool {
        let start = minutesSinceMidnight
        let finish = end.minutesSinceMidnight
        if start == finish {
            return true
        }
        if start < finish {
            return currentMinutes >= start && currentMinutes < finish
        }
        return currentMinutes >= start || currentMinutes < finish
    }
}

enum MenuBarIcon: String, CaseIterable, Codable, Identifiable {
    case switches
    case sliders
    case grid
    case power
    case command
    case sparkles

    var id: String { rawValue }

    var title: String {
        switch self {
        case .switches: return "Switches"
        case .sliders: return "Balance"
        case .grid: return "Tiles"
        case .power: return "Pulse"
        case .command: return "Orbit"
        case .sparkles: return "Spark"
        }
    }

    func templateImage(size: NSSize = NSSize(width: 18, height: 18)) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        defer {
            image.unlockFocus()
            image.isTemplate = true
            image.accessibilityDescription = "Mac Switch \(title)"
        }

        NSGraphicsContext.current?.shouldAntialias = true
        NSColor.black.setStroke()
        NSColor.black.setFill()

        let side = min(size.width, size.height)
        let offsetX = (size.width - side) / 2
        let offsetY = (size.height - side) / 2
        let strokeWidth = max(1.45, side * 0.095)

        func x(_ value: CGFloat) -> CGFloat { offsetX + value / 18 * side }
        func y(_ value: CGFloat) -> CGFloat { offsetY + value / 18 * side }
        func point(_ xValue: CGFloat, _ yValue: CGFloat) -> NSPoint {
            NSPoint(x: x(xValue), y: y(yValue))
        }
        func rect(_ xValue: CGFloat, _ yValue: CGFloat, _ width: CGFloat, _ height: CGFloat) -> NSRect {
            NSRect(x: x(xValue), y: y(yValue), width: width / 18 * side, height: height / 18 * side)
        }
        func path(_ configure: (NSBezierPath) -> Void) -> NSBezierPath {
            let path = NSBezierPath()
            path.lineWidth = strokeWidth
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            configure(path)
            return path
        }
        func stroke(_ path: NSBezierPath) {
            path.lineWidth = strokeWidth
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.stroke()
        }
        func roundedRect(_ rect: NSRect, radius: CGFloat, filled: Bool = false) {
            let path = NSBezierPath(roundedRect: rect, xRadius: radius / 18 * side, yRadius: radius / 18 * side)
            filled ? path.fill() : stroke(path)
        }
        func oval(_ rect: NSRect, filled: Bool = false) {
            let path = NSBezierPath(ovalIn: rect)
            filled ? path.fill() : stroke(path)
        }
        func line(from start: NSPoint, to end: NSPoint) {
            stroke(path {
                $0.move(to: start)
                $0.line(to: end)
            })
        }
        func diamond(centerX: CGFloat, centerY: CGFloat, radius: CGFloat, filled: Bool = false) {
            let path = path {
                $0.move(to: point(centerX, centerY + radius))
                $0.line(to: point(centerX + radius, centerY))
                $0.line(to: point(centerX, centerY - radius))
                $0.line(to: point(centerX - radius, centerY))
                $0.close()
            }
            filled ? path.fill() : stroke(path)
        }

        switch self {
        case .switches:
            roundedRect(rect(8.0, 3.2, 2.0, 11.6), radius: 1.0, filled: true)
            roundedRect(rect(3.0, 4.1, 7.4, 3.6), radius: 1.8)
            roundedRect(rect(7.6, 10.3, 7.4, 3.6), radius: 1.8)
            oval(rect(4.0, 5.0, 1.8, 1.8), filled: true)
            oval(rect(12.2, 11.2, 1.8, 1.8), filled: true)
        case .sliders:
            roundedRect(rect(4.9, 3.1, 2.4, 11.8), radius: 1.2)
            roundedRect(rect(10.7, 3.1, 2.4, 11.8), radius: 1.2)
            oval(rect(3.6, 9.7, 5.0, 5.0), filled: true)
            oval(rect(9.4, 4.2, 5.0, 5.0), filled: true)
        case .grid:
            roundedRect(rect(3.1, 3.1, 4.5, 4.5), radius: 1.0)
            roundedRect(rect(10.4, 3.1, 4.5, 4.5), radius: 1.0)
            roundedRect(rect(3.1, 10.4, 4.5, 4.5), radius: 1.0)
            roundedRect(rect(10.4, 10.4, 4.5, 4.5), radius: 1.0, filled: true)
        case .power:
            oval(rect(4.7, 4.7, 8.6, 8.6))
            line(from: point(2.8, 9.0), to: point(5.1, 9.0))
            line(from: point(12.9, 9.0), to: point(15.2, 9.0))
            line(from: point(9.0, 12.9), to: point(9.0, 15.2))
            oval(rect(8.0, 8.0, 2.0, 2.0), filled: true)
        case .command:
            oval(rect(7.2, 7.2, 3.6, 3.6), filled: true)
            let arcA = path {
                $0.appendArc(
                    withCenter: point(9.0, 9.0),
                    radius: 6.1 / 18 * side,
                    startAngle: 18,
                    endAngle: 158
                )
            }
            stroke(arcA)
            let arcB = path {
                $0.appendArc(
                    withCenter: point(9.0, 9.0),
                    radius: 6.1 / 18 * side,
                    startAngle: 198,
                    endAngle: 338
                )
            }
            stroke(arcB)
            oval(rect(12.5, 12.0, 2.2, 2.2), filled: true)
            oval(rect(3.3, 3.8, 2.2, 2.2), filled: true)
        case .sparkles:
            diamond(centerX: 8.2, centerY: 10.4, radius: 4.1)
            diamond(centerX: 13.7, centerY: 5.1, radius: 1.8, filled: true)
            diamond(centerX: 4.0, centerY: 4.9, radius: 1.3, filled: true)
            line(from: point(12.8, 12.9), to: point(14.4, 14.5))
        }

        return image
    }
}

struct SwitchSnapshot: Equatable {
    var isOn: Bool
    var isAvailable: Bool
    var subtitle: String?
    var warning: String?

    static let off = SwitchSnapshot(isOn: false, isAvailable: true, subtitle: nil, warning: nil)
}

enum ActionSafetyPreferences {
    private static let confirmationKeys: [SwitchKind: String] = [
        .emptyTrash: "switch.safety.confirmEmptyTrash",
        .emptyPasteboard: "switch.safety.confirmEmptyPasteboard",
        .xcodeClean: "switch.safety.confirmXcodeClean",
        .ejectDisk: "switch.safety.confirmEjectDisk"
    ]

    static let protectedKinds: Set<SwitchKind> = Set(confirmationKeys.keys)

    static func confirmationRequired(for kind: SwitchKind, defaults: UserDefaults = .standard) -> Bool {
        guard let key = confirmationKeys[kind] else { return false }
        return defaults.object(forKey: key) as? Bool ?? true
    }

    static func setConfirmationRequired(_ required: Bool, for kind: SwitchKind, defaults: UserDefaults = .standard) {
        guard let key = confirmationKeys[kind] else { return }
        defaults.set(required, forKey: key)
    }

    static func confirmationTitle(for kind: SwitchKind) -> String {
        switch kind {
        case .emptyTrash:
            return "Empty Trash?"
        case .emptyPasteboard:
            return "Clear Pasteboard?"
        case .xcodeClean:
            return "Clean Xcode DerivedData?"
        case .ejectDisk:
            return "Eject Disks?"
        default:
            return "Run \(kind.title)?"
        }
    }

    static func confirmationMessage(for kind: SwitchKind, snapshot: SwitchSnapshot? = nil) -> String {
        switch kind {
        case .emptyTrash:
            return snapshot?.isAvailable == false
                ? "Trash is already empty."
                : "This will permanently empty \(snapshot?.subtitle ?? "the current contents") from Trash using Finder."
        case .emptyPasteboard:
            return snapshot?.isAvailable == false
                ? "The pasteboard is already empty."
                : "This will clear \(snapshot?.subtitle ?? "the current pasteboard contents"). Clipboard contents cannot be restored by Mac Switch."
        case .xcodeClean:
            return "This removes Xcode DerivedData build caches. Xcode will recreate needed files, but the next build can take longer."
        case .ejectDisk:
            return snapshot?.isAvailable == false
                ? "No ejectable disks are currently included."
                : "This will eject \(snapshot?.subtitle ?? "the included removable disks") that are not excluded in settings."
        default:
            return "\(kind.title) will run now."
        }
    }

    static func confirmationButtonTitle(for kind: SwitchKind) -> String {
        switch kind {
        case .emptyTrash:
            return "Empty Trash"
        case .emptyPasteboard:
            return "Clear Pasteboard"
        case .xcodeClean:
            return "Clean"
        case .ejectDisk:
            return "Eject"
        default:
            return "Run"
        }
    }
}

final class SwitchStore: ObservableObject {
    private static let customizationDefaultsVersion = 2
    private static let legacyDefaultEnabledKinds: Set<SwitchKind> = [
        .hideDesktopIcons,
        .darkMode,
        .keepAwake,
        .screenSaver,
        .bluetoothAudio,
        .doNotDisturb,
        .nightShift,
        .trueTone,
        .screenClean
    ]

    @Published var orderedKinds: [SwitchKind] {
        didSet { saveOrder() }
    }

    @Published var enabledKinds: Set<SwitchKind> {
        didSet { saveEnabledKinds() }
    }

    @Published var shortcuts: [SwitchKind: HotKeyShortcut] {
        didSet {
            saveShortcuts()
            registerShortcuts()
        }
    }

    @Published var snapshots: [SwitchKind: SwitchSnapshot] = [:]

    @Published var keepAwakeDuration: KeepAwakeDuration {
        didSet {
            defaults.set(keepAwakeDuration.rawValue, forKey: DefaultsKey.keepAwakeDuration)
            refresh(.keepAwake)
            if snapshots[.keepAwake]?.isOn == true {
                set(.keepAwake, enabled: true)
            }
        }
    }

    @Published var doNotDisturbDuration: DoNotDisturbDuration {
        didSet {
            defaults.set(doNotDisturbDuration.rawValue, forKey: DefaultsKey.doNotDisturbDuration)
            if snapshots[.doNotDisturb]?.isOn == true {
                updateDoNotDisturbExpiration(enabled: true)
            }
            refresh(.doNotDisturb)
        }
    }

    @Published var darkModeScheduleMode: DarkModeScheduleMode {
        didSet {
            defaults.set(darkModeScheduleMode.rawValue, forKey: DefaultsKey.darkModeScheduleMode)
            if darkModeScheduleMode == .sunriseSunset {
                requestDarkModeLocation()
            }
            enforceDarkModeScheduleAsync()
            refresh(.darkMode)
        }
    }

    @Published var darkModeScheduleStart: TimeOfDay {
        didSet {
            saveTimeOfDay(darkModeScheduleStart, forKey: DefaultsKey.darkModeScheduleStart)
            enforceDarkModeScheduleAsync()
            refresh(.darkMode)
        }
    }

    @Published var darkModeScheduleEnd: TimeOfDay {
        didSet {
            saveTimeOfDay(darkModeScheduleEnd, forKey: DefaultsKey.darkModeScheduleEnd)
            enforceDarkModeScheduleAsync()
            refresh(.darkMode)
        }
    }

    @Published var menuBarIcon: MenuBarIcon {
        didSet { defaults.set(menuBarIcon.rawValue, forKey: DefaultsKey.menuBarIcon) }
    }

    @Published var appLanguage: AppLanguage {
        didSet { defaults.set(appLanguage.rawValue, forKey: DefaultsKey.appLanguage) }
    }

    @Published var startAtLogin: Bool {
        didSet {
            updateStartAtLoginIfNeeded(startAtLogin)
        }
    }

    @Published var lastError: String?
    @Published var darkModeLocationStatus: String = "Location is not available"
    @Published var preferredPreferencesTab: String = "general"
    @Published var preferredCustomizeKind: SwitchKind?
    @Published private(set) var actionsInProgress: Set<SwitchKind> = []
    @Published private(set) var actionsPreparing: Set<SwitchKind> = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var isUpdatingStartAtLogin = false
    @Published private(set) var startAtLoginNeedsRepair = false
    @Published private(set) var startAtLoginNeedsApproval = false

    private let defaults = UserDefaults.standard
    private let controller: SystemSwitchController
    private let sunScheduleProvider: SunScheduleProvider
    private let shortcutManager = GlobalShortcutManager()
    private let refreshQueue = DispatchQueue(label: "com.maxyu.macswitch.snapshot-refresh", qos: .utility)
    private let actionQueue = DispatchQueue(label: "com.maxyu.macswitch.switch-actions", qos: .userInitiated)
    private var timer: Timer?
    private var snapshotVersions: [SwitchKind: Int] = [:]
    private var actionVersions: [SwitchKind: Int] = [:]
    private var refreshInFlight = false
    private var pendingRefreshKinds: Set<SwitchKind> = []
    private var isApplyingStartAtLoginState = false
    private var startAtLoginStatusRefreshInFlight = false
    private var darkModeScheduleEnforcementInFlight = false
    private var doNotDisturbExpirationEnforcementInFlight = false
    private var doNotDisturbExpirationWorkItem: DispatchWorkItem?
    private var scheduledFollowUpRefreshes: Set<SwitchKind> = []
    private var pendingHideAfterDeactivation: Set<SwitchKind> = []

    private enum HidePreparationResult {
        case readyToHide
        case waitingForDeactivation
        case blocked
    }

    var visibleKinds: [SwitchKind] {
        Self.normalizedOrder(orderedKinds).filter { enabledKinds.contains($0) }
    }

    var effectiveLanguage: AppLanguage {
        appLanguage.effectiveLanguage
    }

    init(controller: SystemSwitchController = SystemSwitchController()) {
        self.controller = controller
        self.sunScheduleProvider = SunScheduleProvider(defaults: defaults)

        let storedOrder = defaults.stringArray(forKey: DefaultsKey.order)?
            .compactMap(SwitchKind.init(rawValue:))
        let fullDefaultOrder = SwitchKind.allCases
        let missingKinds: [SwitchKind]
        if let storedOrder, !storedOrder.isEmpty {
            let storedUnique = Self.deduplicatedKinds(storedOrder)
            let storedSet = Set(storedUnique)
            let missing = fullDefaultOrder.filter { !storedSet.contains($0) }
            orderedKinds = storedUnique + missing
            missingKinds = missing
        } else {
            orderedKinds = fullDefaultOrder
            missingKinds = []
        }

        let storedEnabled = defaults.stringArray(forKey: DefaultsKey.enabledKinds)?
            .compactMap(SwitchKind.init(rawValue:))
        if let storedEnabled, !storedEnabled.isEmpty {
            var updated = Set(storedEnabled)
            for kind in missingKinds where kind.defaultEnabled {
                updated.insert(kind)
            }
            updated = Self.migratedEnabledKindsIfNeeded(updated, defaults: defaults)
            enabledKinds = updated
        } else {
            enabledKinds = Set(fullDefaultOrder.filter(\.defaultEnabled))
        }
        defaults.set(Self.customizationDefaultsVersion, forKey: DefaultsKey.customizationDefaultsVersion)

        shortcuts = Self.loadShortcuts(from: defaults)

        let durationRaw = defaults.string(forKey: DefaultsKey.keepAwakeDuration)
        keepAwakeDuration = durationRaw.flatMap(KeepAwakeDuration.init(rawValue:)) ?? .indefinitely

        let doNotDisturbDurationRaw = defaults.string(forKey: DefaultsKey.doNotDisturbDuration)
        doNotDisturbDuration = doNotDisturbDurationRaw.flatMap(DoNotDisturbDuration.init(rawValue:)) ?? .indefinitely

        let darkModeScheduleRaw = defaults.string(forKey: DefaultsKey.darkModeScheduleMode)
        darkModeScheduleMode = darkModeScheduleRaw.flatMap(DarkModeScheduleMode.init(rawValue:)) ?? .manual
        darkModeScheduleStart = Self.loadTimeOfDay(
            from: defaults,
            key: DefaultsKey.darkModeScheduleStart,
            defaultValue: .defaultDarkStart
        )
        darkModeScheduleEnd = Self.loadTimeOfDay(
            from: defaults,
            key: DefaultsKey.darkModeScheduleEnd,
            defaultValue: .defaultDarkEnd
        )

        let iconRaw = defaults.string(forKey: DefaultsKey.menuBarIcon)
        menuBarIcon = iconRaw.flatMap(MenuBarIcon.init(rawValue:)) ?? .switches

        let languageRaw = defaults.string(forKey: DefaultsKey.appLanguage)
        appLanguage = languageRaw.flatMap(AppLanguage.init(rawValue:)) ?? .system

        startAtLogin = LoginItemManager.initialIsEnabled
        saveOrder()
        saveEnabledKinds()
        refreshStartAtLoginStatusAsync()

        for kind in SwitchKind.allCases {
            snapshots[kind] = .off
        }

        controller.onExternalChange = { [weak self] kind in
            DispatchQueue.main.async {
                self?.refresh(kind)
            }
        }

        darkModeLocationStatus = sunScheduleProvider.statusText
        sunScheduleProvider.onUpdate = { [weak self] in
            guard let self else { return }
            darkModeLocationStatus = sunScheduleProvider.statusText
            enforceDarkModeScheduleAsync()
            refresh(.darkMode)
        }

        refreshVisibleAsync()
        enforceDarkModeScheduleAsync()
        scheduleDoNotDisturbExpirationMonitorFromDefaults()
        enforceDoNotDisturbExpirationAsync()
        if darkModeScheduleMode == .sunriseSunset {
            requestDarkModeLocation()
        }
        registerShortcuts()
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.enforceDarkModeScheduleAsync()
            self?.enforceDoNotDisturbExpirationAsync()
            self?.refreshVisibleAsync()
        }
    }

    func setEnabled(_ kind: SwitchKind, _ enabled: Bool) {
        if enabled {
            pendingHideAfterDeactivation.remove(kind)
            enabledKinds.insert(kind)
            clearLastErrorIfCustomizationOwned()
            refreshAsync(kind)
        } else {
            guard enabledKinds.contains(kind) else { return }
            guard canHideKindFromDashboard(kind) else {
                lastError = "Please select at least one switch to start Mac Switch."
                return
            }
            switch prepareToHideKind(kind) {
            case .waitingForDeactivation:
                pendingHideAfterDeactivation.insert(kind)
                return
            case .blocked:
                return
            case .readyToHide:
                hideKindFromDashboard(kind)
            }
        }
    }

    func move(_ source: SwitchKind, before target: SwitchKind) {
        guard source != target,
              let from = orderedKinds.firstIndex(of: source),
              let to = orderedKinds.firstIndex(of: target)
        else { return }

        var updated = orderedKinds
        let item = updated.remove(at: from)
        let adjustedIndex = from < to ? to - 1 : to
        updated.insert(item, at: adjustedIndex)
        orderedKinds = Self.normalizedOrder(updated)
    }

    func move(_ source: SwitchKind, after target: SwitchKind) {
        guard source != target,
              let from = orderedKinds.firstIndex(of: source),
              let to = orderedKinds.firstIndex(of: target)
        else { return }

        var updated = orderedKinds
        let item = updated.remove(at: from)
        let adjustedIndex = min(from < to ? to : to + 1, updated.count)
        updated.insert(item, at: adjustedIndex)
        orderedKinds = Self.normalizedOrder(updated)
    }

    func resetCustomization() {
        guard !hasBusyActions else {
            lastError = "Finish the current switch update before restoring defaults."
            return
        }
        let defaultEnabledKinds = Set(SwitchKind.allCases.filter(\.defaultEnabled))
        pendingHideAfterDeactivation.subtract(defaultEnabledKinds)
        for kind in enabledKinds.subtracting(defaultEnabledKinds) {
            switch prepareToHideKind(kind) {
            case .waitingForDeactivation:
                pendingHideAfterDeactivation.insert(kind)
            case .readyToHide:
                enabledKinds.remove(kind)
            case .blocked:
                break
            }
        }
        orderedKinds = SwitchKind.allCases
        enabledKinds.formUnion(defaultEnabledKinds)
        defaults.set(Self.customizationDefaultsVersion, forKey: DefaultsKey.customizationDefaultsVersion)
        clearLastErrorIfCustomizationOwned()
        refreshVisibleAsync()
    }

    func clearLastError() {
        lastError = nil
    }

    func refreshStartAtLoginStatus() {
        isApplyingStartAtLoginState = true
        startAtLogin = LoginItemManager.isEnabled
        startAtLoginNeedsRepair = LoginItemManager.needsRepair
        startAtLoginNeedsApproval = LoginItemManager.needsUserApproval
        isApplyingStartAtLoginState = false
    }

    func refreshStartAtLoginStatusAsync() {
        guard !isUpdatingStartAtLogin, !startAtLoginStatusRefreshInFlight else { return }
        startAtLoginStatusRefreshInFlight = true
        actionQueue.async { [weak self] in
            let enabled = LoginItemManager.isEnabled
            let needsRepair = LoginItemManager.needsRepair
            let needsApproval = LoginItemManager.needsUserApproval
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if self.isUpdatingStartAtLogin {
                    self.startAtLoginStatusRefreshInFlight = false
                    return
                }
                self.isApplyingStartAtLoginState = true
                self.startAtLogin = enabled
                self.startAtLoginNeedsRepair = needsRepair
                self.startAtLoginNeedsApproval = needsApproval
                self.isApplyingStartAtLoginState = false
                self.startAtLoginStatusRefreshInFlight = false
            }
        }
    }

    func repairStartAtLogin() {
        updateStartAtLoginIfNeeded(true)
    }

    func cancelStartAtLoginApproval() {
        updateStartAtLoginIfNeeded(false)
    }

    func isActionBusy(_ kind: SwitchKind) -> Bool {
        isDirectActionBusy(kind)
            || conflictingActionKinds(for: kind).contains { isDirectActionBusy($0) }
    }

    var hasBusyActions: Bool {
        !actionsInProgress.isEmpty || !actionsPreparing.isEmpty
    }

    private func isDirectActionBusy(_ kind: SwitchKind) -> Bool {
        actionsInProgress.contains(kind) || actionsPreparing.contains(kind)
    }

    private func conflictingActionKinds(for kind: SwitchKind) -> Set<SwitchKind> {
        switch kind {
        case .lowPowerMode:
            return [.energyMode]
        case .energyMode:
            return [.lowPowerMode]
        default:
            return []
        }
    }

    func isCustomizationBusy(_ kind: SwitchKind) -> Bool {
        pendingHideAfterDeactivation.contains(kind) || isActionBusy(kind)
    }

    func customizationStatusText(for kind: SwitchKind) -> String {
        if pendingHideAfterDeactivation.contains(kind) {
            return "Turning off before hiding"
        }
        if isActionBusy(kind) {
            return "Updating..."
        }
        return enabledKinds.contains(kind) ? "Shown in menu" : "Hidden"
    }

    func toggle(_ kind: SwitchKind) {
        guard !pendingHideAfterDeactivation.contains(kind) else { return }
        guard !isActionBusy(kind) else { return }
        guard ensureSwitchAvailable(kind) else { return }
        let target = !(snapshots[kind]?.isOn ?? false)
        if kind == .bluetoothAudio {
            snapshots[kind] = SwitchSnapshot(
                isOn: !target,
                isAvailable: true,
                subtitle: target ? "Connecting..." : "Disconnecting...",
                warning: nil
            )
            set(kind, enabled: target)
            return
        }
        set(kind, enabled: target)
    }

    func trigger(_ kind: SwitchKind) {
        guard !isActionBusy(kind) else { return }
        if kind.requiresFreshAvailabilityBeforeAction {
            preflightTrigger(kind)
            return
        }

        guard ensureSwitchAvailable(kind, forceFreshSnapshot: kind.requiresFreshAvailabilityBeforeAction) else { return }
        if ActionSafetyPreferences.confirmationRequired(for: kind) {
            actionsPreparing.insert(kind)
            let confirmed = confirmActionIfNeeded(kind)
            actionsPreparing.remove(kind)
            guard confirmed else { return }
        } else {
            guard confirmActionIfNeeded(kind) else { return }
        }
        runConfirmedTrigger(kind)
    }

    private func runConfirmedTrigger(_ kind: SwitchKind) {
        if kind == .xcodeClean {
            runXcodeClean()
            return
        }
        if let subtitle = kind.executingSubtitle {
            snapshots[kind] = SwitchSnapshot(isOn: false, isAvailable: true, subtitle: subtitle, warning: nil)
            set(kind, enabled: true)
            return
        }
        set(kind, enabled: true)
    }

    private func preflightTrigger(_ kind: SwitchKind) {
        actionsPreparing.insert(kind)
        let duration = keepAwakeDuration
        let controller = self.controller

        if kind.snapshotRequiresMainThread {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let snapshot = self.controller.snapshot(for: kind, keepAwakeDuration: duration)
                self.finishPreflightTrigger(kind, snapshot: snapshot)
            }
            return
        }

        actionQueue.async { [weak self] in
            let snapshot = controller.snapshot(for: kind, keepAwakeDuration: duration)
            DispatchQueue.main.async { [weak self] in
                self?.finishPreflightTrigger(kind, snapshot: snapshot)
            }
        }
    }

    private func finishPreflightTrigger(_ kind: SwitchKind, snapshot: SwitchSnapshot) {
        guard actionsPreparing.contains(kind) else { return }
        let decorated = decoratedSnapshot(snapshot, for: kind)
        snapshots[kind] = decorated
        guard ensurePreparedSnapshotAvailable(kind, snapshot: decorated) else {
            actionsPreparing.remove(kind)
            return
        }
        guard confirmActionIfNeeded(kind) else {
            actionsPreparing.remove(kind)
            return
        }
        actionsPreparing.remove(kind)
        runConfirmedTrigger(kind)
    }

    private func confirmActionIfNeeded(_ kind: SwitchKind) -> Bool {
        guard ActionSafetyPreferences.confirmationRequired(for: kind) else { return true }

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.icon = NSImage(systemSymbolName: kind.symbolName, accessibilityDescription: kind.title)
        alert.messageText = ActionSafetyPreferences.confirmationTitle(for: kind)
        alert.informativeText = ActionSafetyPreferences.confirmationMessage(for: kind, snapshot: snapshots[kind])
        alert.addButton(withTitle: ActionSafetyPreferences.confirmationButtonTitle(for: kind))
        alert.addButton(withTitle: "Cancel")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Do not ask again for this action"

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return false }

        if alert.suppressionButton?.state == .on {
            ActionSafetyPreferences.setConfirmationRequired(false, for: kind)
        }
        return true
    }

    func setShortcut(_ kind: SwitchKind, shortcut: HotKeyShortcut?) {
        if let reason = shortcut?.validationFailureMessage {
            lastError = reason
            return
        }
        if let shortcut, let owner = shortcutOwner(for: shortcut, excluding: kind) {
            lastError = "This shortcut is already used by \"\(owner.title)\"."
            return
        }
        clearLastErrorIfShortcutOwned()
        shortcuts[kind] = shortcut
    }

    func clearAllShortcuts() {
        shortcuts.removeAll()
        clearLastErrorIfShortcutOwned()
    }

    func shortcutOwner(for shortcut: HotKeyShortcut, excluding ignoredKind: SwitchKind? = nil) -> SwitchKind? {
        shortcuts.first { kind, value in
            kind != ignoredKind && value.keyCode == shortcut.keyCode && value.modifiers == shortcut.modifiers
        }?.key
    }

    func set(_ kind: SwitchKind, enabled: Bool) {
        guard !isActionBusy(kind) else { return }
        guard ensureSwitchAvailable(kind) else { return }
        invalidatePendingSnapshot(for: kind)
        let actionVersion = nextActionVersion(for: kind)
        actionsInProgress.insert(kind)
        let duration = keepAwakeDuration

        if kind.operationRequiresMainThread {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self] in
                guard let self, self.isCurrentAction(kind, version: actionVersion) else { return }
                let result = self.controller.set(kind, enabled: enabled, keepAwakeDuration: duration)
                self.applySetResult(result, for: kind, enabled: enabled, actionVersion: actionVersion)
            }
            return
        }

        let controller = self.controller
        actionQueue.async { [weak self] in
            let result = controller.set(kind, enabled: enabled, keepAwakeDuration: duration)
            DispatchQueue.main.async {
                self?.applySetResult(result, for: kind, enabled: enabled, actionVersion: actionVersion)
            }
        }
    }

    private func applySetResult(_ result: SwitchOperationResult, for kind: SwitchKind, enabled: Bool, actionVersion: Int) {
        guard isCurrentAction(kind, version: actionVersion) else { return }
        actionsInProgress.remove(kind)
        if result.error == nil, kind == .doNotDisturb {
            updateDoNotDisturbExpiration(enabled: enabled)
        }
        var snapshot = decoratedSnapshot(result.snapshot, for: kind)
        let failureTitle = Self.operationFailureTitle(for: kind, enabled: enabled)
        if let error = result.error {
            snapshot.warning = failureTitle
            lastError = "\(failureTitle): \(error)"
        } else {
            clearLastErrorIfOwned(by: kind, failureTitle: failureTitle)
        }
        snapshots[kind] = snapshot
        completePendingHideAfterDeactivation(for: kind, enabled: enabled, error: result.error)
        schedulePostActionRefresh(for: kind)
    }

    @discardableResult
    private func ensureSwitchAvailable(_ kind: SwitchKind, forceFreshSnapshot: Bool = false) -> Bool {
        var snapshot = snapshots[kind] ?? .off
        if forceFreshSnapshot || (snapshot == .off && kind.snapshotRequiresMainThread) {
            snapshot = decoratedSnapshot(
                controller.snapshot(for: kind, keepAwakeDuration: keepAwakeDuration),
                for: kind
            )
            snapshots[kind] = snapshot
        }

        return ensurePreparedSnapshotAvailable(kind, snapshot: snapshot)
    }

    private func ensurePreparedSnapshotAvailable(_ kind: SwitchKind, snapshot: SwitchSnapshot) -> Bool {
        guard !snapshot.isAvailable else { return true }
        let updated = decoratedSnapshot(snapshot, for: kind)
        snapshots[kind] = updated
        let detail = updated.warning ?? updated.subtitle ?? "This switch is not available on this Mac."
        lastError = "\(kind.title) is not available: \(detail)"
        return false
    }

    private func clearLastErrorIfOwned(by kind: SwitchKind, failureTitle: String) {
        guard let lastError else { return }
        let ownedPrefixes = [
            "\(failureTitle):",
            "\(kind.title) is not available:"
        ]
        if ownedPrefixes.contains(where: { lastError.hasPrefix($0) }) {
            self.lastError = nil
        }
    }

    func refresh(_ kind: SwitchKind) {
        refreshAsync(kind)
    }

    func refreshAll() {
        refreshAllAsync()
    }

    func refreshVisibleAsync() {
        refreshAsync(kinds: visibleKinds)
    }

    func refreshAllAsync() {
        refreshAsync(kinds: SwitchKind.allCases)
    }

    func refreshAsync(_ kind: SwitchKind) {
        refreshAsync(kinds: [kind])
    }

    private func refreshAsync(kinds: [SwitchKind]) {
        let requestedKinds = Set(kinds.filter { !isActionBusy($0) })
        guard !requestedKinds.isEmpty else { return }

        if refreshInFlight {
            pendingRefreshKinds.formUnion(requestedKinds)
            return
        }

        refreshInFlight = true
        isRefreshing = true

        let duration = keepAwakeDuration
        let controller = self.controller
        let requestedVersions = Dictionary(uniqueKeysWithValues: requestedKinds.map { ($0, snapshotVersions[$0, default: 0]) })
        let mainKinds = requestedKinds.filter(\.snapshotRequiresMainThread)
        let backgroundKinds = requestedKinds.filter { !$0.snapshotRequiresMainThread }

        if !mainKinds.isEmpty {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                for kind in mainKinds
                    where !self.isActionBusy(kind)
                    && self.snapshotVersions[kind, default: 0] == requestedVersions[kind, default: 0] {
                    let snapshot = self.controller.snapshot(for: kind, keepAwakeDuration: duration)
                    let decorated = self.decoratedSnapshot(snapshot, for: kind)
                    self.snapshots[kind] = decorated
                    self.clearAvailabilityErrorIfResolved(for: kind, snapshot: decorated)
                    self.scheduleFollowUpRefreshIfNeeded(for: kind, snapshot: decorated)
                }
            }
        }

        guard !backgroundKinds.isEmpty else {
            DispatchQueue.main.async { [weak self] in
                self?.finishRefreshCycle()
            }
            return
        }

        refreshQueue.async { [weak self] in
            let snapshots = backgroundKinds.map { kind in
                (kind, controller.snapshot(for: kind, keepAwakeDuration: duration))
            }
            DispatchQueue.main.async {
                guard let self else { return }
                for (kind, snapshot) in snapshots
                    where !self.isActionBusy(kind)
                    && self.snapshotVersions[kind, default: 0] == requestedVersions[kind, default: 0] {
                    let decorated = self.decoratedSnapshot(snapshot, for: kind)
                    self.snapshots[kind] = decorated
                    self.clearAvailabilityErrorIfResolved(for: kind, snapshot: decorated)
                    self.scheduleFollowUpRefreshIfNeeded(for: kind, snapshot: decorated)
                }
                self.finishRefreshCycle()
            }
        }
    }

    private func finishRefreshCycle() {
        refreshInFlight = false
        isRefreshing = false

        let pending = pendingRefreshKinds.filter { !isActionBusy($0) }
        pendingRefreshKinds.removeAll()
        if !pending.isEmpty {
            refreshAsync(kinds: Array(pending))
        }
    }

    private func invalidatePendingSnapshot(for kind: SwitchKind) {
        snapshotVersions[kind, default: 0] += 1
    }

    private func nextActionVersion(for kind: SwitchKind) -> Int {
        actionVersions[kind, default: 0] += 1
        return actionVersions[kind, default: 0]
    }

    private func isCurrentAction(_ kind: SwitchKind, version: Int) -> Bool {
        actionsInProgress.contains(kind) && actionVersions[kind, default: 0] == version
    }

    private func clearAvailabilityErrorIfResolved(for kind: SwitchKind, snapshot: SwitchSnapshot) {
        guard snapshot.isAvailable,
              lastError?.hasPrefix("\(kind.title) is not available:") == true
        else { return }
        lastError = nil
    }

    private func scheduleFollowUpRefreshIfNeeded(for kind: SwitchKind, snapshot: SwitchSnapshot) {
        guard kind == .xcodeClean,
              snapshot.subtitle?.contains("Calculating") == true,
              !scheduledFollowUpRefreshes.contains(kind)
        else { return }

        scheduledFollowUpRefreshes.insert(kind)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self else { return }
            self.scheduledFollowUpRefreshes.remove(kind)
            self.refreshAsync(kind)
        }
    }

    private func prepareToHideKind(_ kind: SwitchKind) -> HidePreparationResult {
        guard !kind.isMomentaryAction else {
            return .readyToHide
        }
        guard !isActionBusy(kind) else {
            return .waitingForDeactivation
        }
        guard snapshots[kind]?.isOn == true else {
            return .readyToHide
        }
        set(kind, enabled: false)
        if actionsInProgress.contains(kind) {
            return .waitingForDeactivation
        }
        return snapshots[kind]?.isOn == true ? .blocked : .readyToHide
    }

    private func completePendingHideAfterDeactivation(for kind: SwitchKind, enabled: Bool, error: String?) {
        guard pendingHideAfterDeactivation.remove(kind) != nil else { return }
        guard error == nil else { return }
        if !enabled {
            hideKindFromDashboard(kind)
        } else {
            switch prepareToHideKind(kind) {
            case .waitingForDeactivation:
                pendingHideAfterDeactivation.insert(kind)
            case .readyToHide:
                hideKindFromDashboard(kind)
            case .blocked:
                break
            }
        }
    }

    private func hideKindFromDashboard(_ kind: SwitchKind) {
        guard enabledKinds.contains(kind) else { return }
        guard canHideKindFromDashboard(kind) else {
            lastError = "Please select at least one switch to start Mac Switch."
            return
        }
        enabledKinds.remove(kind)
        clearLastErrorIfCustomizationOwned()
    }

    private func canHideKindFromDashboard(_ kind: SwitchKind) -> Bool {
        let effectiveVisible = enabledKinds.subtracting(pendingHideAfterDeactivation)
        return !effectiveVisible.subtracting([kind]).isEmpty
    }

    func requestDarkModeLocation() {
        sunScheduleProvider.requestLocation()
        darkModeLocationStatus = sunScheduleProvider.statusText
    }

    func prepareForTermination() {
        timer?.invalidate()
        timer = nil
        cancelDoNotDisturbExpirationMonitor()
        controller.prepareForTermination()
    }

    private func runXcodeClean() {
        guard !actionsInProgress.contains(.xcodeClean) else { return }
        let actionVersion = nextActionVersion(for: .xcodeClean)
        actionsInProgress.insert(.xcodeClean)
        snapshots[.xcodeClean] = SwitchSnapshot(
            isOn: false,
            isAvailable: true,
            subtitle: Self.xcodeCleaningSubtitle(percent: 0),
            warning: nil
        )

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let result = self.controller.performXcodeClean { [weak self] percent in
                DispatchQueue.main.async {
                    guard let self, self.isCurrentAction(.xcodeClean, version: actionVersion) else { return }
                    self.snapshots[.xcodeClean] = SwitchSnapshot(
                        isOn: false,
                        isAvailable: true,
                        subtitle: Self.xcodeCleaningSubtitle(percent: percent),
                        warning: nil
                    )
                }
            }

            DispatchQueue.main.async { [weak self] in
                guard let self, self.isCurrentAction(.xcodeClean, version: actionVersion) else { return }
                self.actionsInProgress.remove(.xcodeClean)
                var snapshot = self.decoratedSnapshot(result.snapshot, for: .xcodeClean)
                if let error = result.error {
                    let failureTitle = Self.operationFailureTitle(for: .xcodeClean, enabled: true)
                    snapshot.warning = failureTitle
                    self.lastError = "\(failureTitle): \(error)"
                } else {
                    self.clearLastErrorIfOwned(
                        by: .xcodeClean,
                        failureTitle: Self.operationFailureTitle(for: .xcodeClean, enabled: true)
                    )
                }
                self.snapshots[.xcodeClean] = snapshot
                self.schedulePostActionRefresh(for: .xcodeClean)
            }
        }
    }

    private func schedulePostActionRefresh(for kind: SwitchKind) {
        var kinds: Set<SwitchKind> = [kind]
        kinds.formUnion(conflictingActionKinds(for: kind))
        guard kind.isMomentaryAction || kinds.count > 1 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.refreshAsync(kinds: Array(kinds))
        }
    }

    private static func xcodeCleaningSubtitle(percent: Double) -> String {
        "Cleaning DerivedData...\(Int(percent.rounded()))%"
    }

    private static func operationFailureTitle(for kind: SwitchKind, enabled: Bool) -> String {
        if kind.isMomentaryAction {
            return "\(kind.title) failed"
        }
        return "\(enabled ? "Enable" : "Disable") \"\(kind.title)\" failed"
    }

    var darkModeSunScheduleDescription: String {
        guard let window = sunScheduleProvider.sunWindow() else {
            return darkModeLocationStatus
        }
        return "Sunrise \(window.sunriseDisplay), sunset \(window.sunsetDisplay)"
    }

    func quit() {
        NSApplication.shared.terminate(nil)
    }

    func text(_ key: L10nKey) -> String {
        L10n.text(key, language: effectiveLanguage)
    }

    func switchTitle(_ kind: SwitchKind) -> String {
        L10n.switchTitle(kind, language: effectiveLanguage)
    }

    func menuBarIconTitle(_ icon: MenuBarIcon) -> String {
        L10n.menuBarIconTitle(icon, language: effectiveLanguage)
    }

    private func updateStartAtLoginIfNeeded(_ enabled: Bool) {
        guard !isApplyingStartAtLoginState else { return }
        guard !isUpdatingStartAtLogin else { return }
        isUpdatingStartAtLogin = true
        actionQueue.async { [weak self] in
            let failure: String?
            do {
                try LoginItemManager.setEnabled(enabled)
                failure = nil
            } catch {
                failure = error.localizedDescription
            }
            let refreshedEnabled = LoginItemManager.isEnabled
            let refreshedNeedsRepair = LoginItemManager.needsRepair
            let refreshedNeedsApproval = LoginItemManager.needsUserApproval

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isUpdatingStartAtLogin = false
                self.isApplyingStartAtLoginState = true
                self.startAtLogin = refreshedEnabled
                self.startAtLoginNeedsRepair = refreshedNeedsRepair
                self.startAtLoginNeedsApproval = refreshedNeedsApproval
                self.isApplyingStartAtLoginState = false
                if let failure {
                    self.lastError = "Start at Login failed: \(failure)"
                } else {
                    self.clearLastErrorIfPrefixed("Start at Login failed:")
                }
            }
        }
    }

    private func saveOrder() {
        defaults.set(Self.normalizedOrder(orderedKinds).map(\.rawValue), forKey: DefaultsKey.order)
    }

    private func saveEnabledKinds() {
        let orderedEnabled = Self.normalizedOrder(orderedKinds).filter { enabledKinds.contains($0) }
        defaults.set(orderedEnabled.map(\.rawValue), forKey: DefaultsKey.enabledKinds)
    }

    private func updateDoNotDisturbExpiration(enabled: Bool) {
        if enabled, let endDate = doNotDisturbDuration.endDate() {
            defaults.set(endDate, forKey: DefaultsKey.doNotDisturbEndDate)
            scheduleDoNotDisturbExpirationMonitor(for: endDate)
        } else {
            defaults.removeObject(forKey: DefaultsKey.doNotDisturbEndDate)
            cancelDoNotDisturbExpirationMonitor()
        }
    }

    private func enforceDarkModeScheduleAsync() {
        guard darkModeScheduleMode != .manual else { return }
        guard !darkModeScheduleEnforcementInFlight else { return }

        darkModeScheduleEnforcementInFlight = true
        let mode = darkModeScheduleMode
        let start = darkModeScheduleStart
        let end = darkModeScheduleEnd
        let sunWindow = mode == .sunriseSunset ? sunScheduleProvider.sunWindow() : nil
        let duration = keepAwakeDuration
        let controller = self.controller

        refreshQueue.async { [weak self] in
            let snapshot = controller.snapshot(for: .darkMode, keepAwakeDuration: duration)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.darkModeScheduleEnforcementInFlight = false
                guard self.darkModeScheduleMode == mode,
                      self.darkModeScheduleStart == start,
                      self.darkModeScheduleEnd == end
                else {
                    self.enforceDarkModeScheduleAsync()
                    return
                }

                guard let shouldEnable = self.darkModeScheduleTarget(mode: mode, start: start, end: end, sunWindow: sunWindow) else {
                    self.snapshots[.darkMode] = self.decoratedSnapshot(snapshot, for: .darkMode)
                    return
                }

                if snapshot.isOn != shouldEnable {
                    self.set(.darkMode, enabled: shouldEnable)
                } else {
                    self.snapshots[.darkMode] = self.decoratedSnapshot(snapshot, for: .darkMode)
                }
            }
        }
    }

    private func darkModeScheduleTarget(
        mode: DarkModeScheduleMode,
        start: TimeOfDay,
        end: TimeOfDay,
        sunWindow: SunWindow?
    ) -> Bool? {
        switch mode {
        case .manual:
            return nil
        case .custom:
            let components = Calendar.current.dateComponents([.hour, .minute], from: Date())
            guard let hour = components.hour, let minute = components.minute else { return nil }
            return start.contains(currentMinutes: hour * 60 + minute, until: end)
        case .sunriseSunset:
            return sunWindow?.shouldEnableDarkMode()
        }
    }

    private func enforceDoNotDisturbExpirationAsync() {
        guard let endDate = defaults.object(forKey: DefaultsKey.doNotDisturbEndDate) as? Date else {
            cancelDoNotDisturbExpirationMonitor()
            return
        }
        guard Date() >= endDate else {
            scheduleDoNotDisturbExpirationMonitor(for: endDate)
            if let snapshot = snapshots[.doNotDisturb] {
                snapshots[.doNotDisturb] = decoratedDoNotDisturbSnapshot(snapshot)
            }
            return
        }

        guard !doNotDisturbExpirationEnforcementInFlight else { return }
        doNotDisturbExpirationEnforcementInFlight = true
        let duration = keepAwakeDuration
        let controller = self.controller

        refreshQueue.async { [weak self] in
            let snapshot = controller.snapshot(for: .doNotDisturb, keepAwakeDuration: duration)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.doNotDisturbExpirationEnforcementInFlight = false
                guard let currentEndDate = self.defaults.object(forKey: DefaultsKey.doNotDisturbEndDate) as? Date,
                      currentEndDate == endDate,
                      Date() >= currentEndDate
                else { return }

                let decorated = self.decoratedSnapshot(snapshot, for: .doNotDisturb)
                self.snapshots[.doNotDisturb] = decorated

                guard snapshot.isAvailable else {
                    self.scheduleDoNotDisturbExpirationMonitor(for: currentEndDate, minimumDelay: 30)
                    return
                }

                if snapshot.isOn {
                    self.set(.doNotDisturb, enabled: false)
                    self.scheduleDoNotDisturbExpirationMonitor(for: currentEndDate, minimumDelay: 30)
                } else {
                    self.defaults.removeObject(forKey: DefaultsKey.doNotDisturbEndDate)
                    self.cancelDoNotDisturbExpirationMonitor()
                }
            }
        }
    }

    private func scheduleDoNotDisturbExpirationMonitorFromDefaults() {
        if let endDate = defaults.object(forKey: DefaultsKey.doNotDisturbEndDate) as? Date {
            scheduleDoNotDisturbExpirationMonitor(for: endDate)
        } else {
            cancelDoNotDisturbExpirationMonitor()
        }
    }

    private func scheduleDoNotDisturbExpirationMonitor(for endDate: Date, minimumDelay: TimeInterval = 0) {
        doNotDisturbExpirationWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.enforceDoNotDisturbExpirationAsync()
        }
        doNotDisturbExpirationWorkItem = workItem
        let delay = max(endDate.timeIntervalSinceNow, minimumDelay)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func cancelDoNotDisturbExpirationMonitor() {
        doNotDisturbExpirationWorkItem?.cancel()
        doNotDisturbExpirationWorkItem = nil
    }

    private func decoratedSnapshot(_ snapshot: SwitchSnapshot, for kind: SwitchKind) -> SwitchSnapshot {
        if kind == .doNotDisturb {
            return decoratedDoNotDisturbSnapshot(snapshot)
        }
        guard kind == .darkMode else { return snapshot }
        var updated = snapshot
        switch darkModeScheduleMode {
        case .manual:
            break
        case .custom:
            updated.subtitle = "From \(darkModeScheduleStart.display) to \(darkModeScheduleEnd.display)"
        case .sunriseSunset:
            if let window = sunScheduleProvider.sunWindow() {
                updated.subtitle = updated.isOn
                    ? "Will turn off at \(window.sunriseDisplay)"
                    : "Will turn on at \(window.sunsetDisplay)"
            } else {
                updated.warning = darkModeLocationStatus
            }
        }
        return updated
    }

    private func decoratedDoNotDisturbSnapshot(_ snapshot: SwitchSnapshot) -> SwitchSnapshot {
        guard snapshot.warning == nil else {
            return snapshot
        }

        var updated = snapshot
        if updated.isOn {
            if let endDate = defaults.object(forKey: DefaultsKey.doNotDisturbEndDate) as? Date {
                updated.subtitle = doNotDisturbDuration == .tomorrow
                    ? "Will turn off tomorrow"
                    : "Will turn off at \(timeDisplay(for: endDate))"
            } else {
                updated.subtitle = DoNotDisturbDuration.indefinitely.dashboardSubtitle
            }
        } else {
            updated.subtitle = doNotDisturbDuration.dashboardSubtitle
        }
        return updated
    }

    private func timeDisplay(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        guard let hour = components.hour, let minute = components.minute else { return "" }
        return TimeOfDay(hour: hour, minute: minute).display
    }

    private func saveShortcuts() {
        let encoded = Dictionary(uniqueKeysWithValues: shortcuts.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(encoded) {
            defaults.set(data, forKey: DefaultsKey.shortcuts)
        }
    }

    private func saveTimeOfDay(_ value: TimeOfDay, forKey key: String) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        }
    }

    private func registerShortcuts() {
        let error = shortcutManager.register(shortcuts: shortcuts) { [weak self] kind in
            guard let self else { return }
            if kind.isMomentaryAction {
                trigger(kind)
            } else {
                toggle(kind)
            }
        }
        if let error {
            lastError = error
        } else if lastError?.hasPrefix("Could not register shortcut:") == true ||
                    lastError?.hasPrefix("Could not install global shortcut handler") == true {
            lastError = nil
        }
    }

    private func clearLastErrorIfCustomizationOwned() {
        guard let lastError else { return }
        if lastError == "Please select at least one switch to start Mac Switch." ||
            lastError.hasPrefix("This shortcut is already used by") ||
            lastError == "Use at least two of Command, Option, or Control." ||
            lastError == "Choose a letter, number, or function key for the shortcut." {
            self.lastError = nil
        }
    }

    private func clearLastErrorIfShortcutOwned() {
        guard let lastError else { return }
        if lastError.hasPrefix("Could not register shortcut:") ||
            lastError.hasPrefix("This shortcut is already used by") ||
            lastError == "Use at least two of Command, Option, or Control." ||
            lastError == "Choose a letter, number, or function key for the shortcut." {
            self.lastError = nil
        }
    }

    private func clearLastErrorIfPrefixed(_ prefix: String) {
        if lastError?.hasPrefix(prefix) == true {
            lastError = nil
        }
    }

    private static func loadShortcuts(from defaults: UserDefaults) -> [SwitchKind: HotKeyShortcut] {
        guard let data = defaults.data(forKey: DefaultsKey.shortcuts),
              let raw = try? JSONDecoder().decode([String: HotKeyShortcut].self, from: data)
        else { return [:] }

        var loaded: [SwitchKind: HotKeyShortcut] = [:]
        var seenShortcuts: Set<String> = []
        for kind in SwitchKind.allCases {
            guard let value = raw[kind.rawValue],
                  value.isValidGlobalShortcut
            else { continue }

            let shortcutKey = "\(value.keyCode)-\(value.modifiers)"
            guard seenShortcuts.insert(shortcutKey).inserted else { continue }
            loaded[kind] = value
        }
        return loaded
    }

    private static func deduplicatedKinds(_ kinds: [SwitchKind]) -> [SwitchKind] {
        var seen: Set<SwitchKind> = []
        return kinds.filter { seen.insert($0).inserted }
    }

    private static func normalizedOrder(
        _ kinds: [SwitchKind],
        appendingMissingFrom defaultOrder: [SwitchKind] = SwitchKind.allCases
    ) -> [SwitchKind] {
        let unique = deduplicatedKinds(kinds)
        guard !unique.isEmpty else { return defaultOrder }
        let present = Set(unique)
        return unique + defaultOrder.filter { !present.contains($0) }
    }

    private static func migratedEnabledKindsIfNeeded(_ kinds: Set<SwitchKind>, defaults: UserDefaults) -> Set<SwitchKind> {
        let storedVersion = defaults.integer(forKey: DefaultsKey.customizationDefaultsVersion)
        guard storedVersion < customizationDefaultsVersion,
              kinds == legacyDefaultEnabledKinds
        else { return kinds }
        return Set(SwitchKind.allCases.filter(\.defaultEnabled))
    }

    private static func loadTimeOfDay(from defaults: UserDefaults, key: String, defaultValue: TimeOfDay) -> TimeOfDay {
        guard let data = defaults.data(forKey: key),
              let value = try? JSONDecoder().decode(TimeOfDay.self, from: data),
              (0...23).contains(value.hour),
              (0...59).contains(value.minute)
        else { return defaultValue }
        return value
    }
}

private enum DefaultsKey {
    static let order = "switch.order"
    static let enabledKinds = "switch.enabledKinds"
    static let keepAwakeDuration = "switch.keepAwakeDuration"
    static let doNotDisturbDuration = "switch.doNotDisturb.duration"
    static let doNotDisturbEndDate = "switch.doNotDisturb.endDate"
    static let darkModeScheduleMode = "switch.darkMode.scheduleMode"
    static let darkModeScheduleStart = "switch.darkMode.scheduleStart"
    static let darkModeScheduleEnd = "switch.darkMode.scheduleEnd"
    static let menuBarIcon = "app.menuBarIcon"
    static let appLanguage = "app.language"
    static let shortcuts = "switch.shortcuts"
    static let customizationDefaultsVersion = "switch.customizationDefaultsVersion"
}

private extension SwitchKind {
    var operationRequiresMainThread: Bool {
        switch self {
        case .screenSaver, .nightShift, .trueTone,
             .screenResolution, .screenClean, .lockKeyboard, .ejectDisk,
             .emptyPasteboard, .hideWindows:
            return true
        default:
            return false
        }
    }

    var snapshotRequiresMainThread: Bool {
        switch self {
        case .bluetoothAudio, .nightShift, .trueTone,
             .screenResolution, .screenClean, .lockKeyboard, .emptyPasteboard, .hideWindows:
            return true
        default:
            return false
        }
    }

    var requiresFreshAvailabilityBeforeAction: Bool {
        switch self {
        case .displaySleep, .emptyTrash, .ejectDisk, .emptyPasteboard, .hideWindows:
            return true
        default:
            return false
        }
    }

    var executingSubtitle: String? {
        switch self {
        case .screenSaver:
            return "Starting screen saver..."
        case .displaySleep:
            return "Sleeping display..."
        case .lockScreen:
            return "Locking screen..."
        case .xcodeClean:
            return "Cleaning DerivedData..."
        case .emptyTrash:
            return "Emptying the Trash..."
        case .ejectDisk:
            return "Ejecting the disks..."
        case .emptyPasteboard:
            return "Emptying the Pasteboard..."
        case .hideWindows:
            return "Hiding windows..."
        default:
            return nil
        }
    }
}
