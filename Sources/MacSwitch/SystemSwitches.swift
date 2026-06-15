import AppKit
import ApplicationServices
import Foundation
import IOKit.pwr_mgt
import ObjectiveC.runtime
import ServiceManagement
import SwiftUI

private let unsupportedDeviceMessage = "Unavailable on this device"
private let unsupportedSystemMessage = "This control is not available on your current system."

enum DiagnosticRedactor {
    static func redact(_ value: String) -> String {
        let homeCandidates = [
            FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path,
            NSHomeDirectory()
        ]
        .filter { !$0.isEmpty && $0 != "/" }

        var redacted = value
        for home in Set(homeCandidates).sorted(by: { $0.count > $1.count }) {
            redacted = redacted.replacingOccurrences(of: home, with: "~")
        }
        return redacted
    }
}

private func waitForSystemSwitchCondition(
    timeout: TimeInterval = 0.8,
    interval: TimeInterval = 0.05,
    _ condition: () -> Bool
) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
        if condition() {
            return true
        }
        _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(interval))
    } while Date() < deadline
    return condition()
}

@discardableResult
func openWorkspaceURL(_ url: URL) -> Bool {
    let open = {
        NSWorkspace.shared.open(url)
    }
    if Thread.isMainThread {
        return open()
    }
    var opened = false
    DispatchQueue.main.sync {
        opened = open()
    }
    return opened
}

@discardableResult
func revealInFinder(_ url: URL) -> Bool {
    let target = url.standardizedFileURL
    guard FileManager.default.fileExists(atPath: target.path) else {
        return false
    }
    let reveal = {
        NSWorkspace.shared.selectFile(target.path, inFileViewerRootedAtPath: "")
    }
    if Thread.isMainThread {
        return reveal()
    }
    var revealed = false
    DispatchQueue.main.sync {
        revealed = reveal()
    }
    return revealed
}

func restartProcessOrReport(_ processName: String, failureMessage: String) -> String? {
    let result = ProcessRunner.run("/usr/bin/killall", [processName], timeout: 2)
    if result.status == 0 || processWasNotRunning(result) {
        return nil
    }
    return ProcessRunner.failureMessage(for: result, fallback: failureMessage)
}

private func processWasNotRunning(_ result: (status: Int32, output: String, error: String)) -> Bool {
    let combined = "\(result.output)\n\(result.error)".lowercased()
    return combined.contains("no matching processes")
}

@discardableResult
func openSystemSettings(primary: String, fallback: String? = nil) -> Bool {
    guard let primaryURL = URL(string: primary) else { return false }
    if openWorkspaceURL(primaryURL) {
        return true
    }
    guard let fallback, let fallbackURL = URL(string: fallback) else { return false }
    return openWorkspaceURL(fallbackURL)
}

enum SystemSettingsLinks {
    @discardableResult
    static func openAccessibility() -> Bool {
        openSystemSettings(
            primary: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            fallback: "x-apple.systempreferences:com.apple.preference.security"
        )
    }

    @discardableResult
    static func openAutomation() -> Bool {
        openSystemSettings(
            primary: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation",
            fallback: "x-apple.systempreferences:com.apple.preference.security"
        )
    }

    @discardableResult
    static func openBluetooth() -> Bool {
        openSystemSettings(
            primary: "x-apple.systempreferences:com.apple.Bluetooth",
            fallback: "x-apple.systempreferences:com.apple.preference.bluetooth"
        )
    }

    @discardableResult
    static func openDisplays() -> Bool {
        openSystemSettings(
            primary: "x-apple.systempreferences:com.apple.Displays-Settings.extension",
            fallback: "x-apple.systempreferences:com.apple.preference.displays"
        )
    }

    @discardableResult
    static func openSound() -> Bool {
        openSystemSettings(
            primary: "x-apple.systempreferences:com.apple.Sound-Settings.extension",
            fallback: "x-apple.systempreferences:com.apple.preference.sound"
        )
    }

    @discardableResult
    static func openBattery() -> Bool {
        openSystemSettings(
            primary: "x-apple.systempreferences:com.apple.Battery-Settings.extension",
            fallback: "x-apple.systempreferences:com.apple.preference.energysaver"
        )
    }

    @discardableResult
    static func openDesktopDock() -> Bool {
        openSystemSettings(
            primary: "x-apple.systempreferences:com.apple.Desktop-Settings.extension",
            fallback: "x-apple.systempreferences:com.apple.preference.dock"
        )
    }

    @discardableResult
    static func openLockScreen() -> Bool {
        openSystemSettings(
            primary: "x-apple.systempreferences:com.apple.Lock-Screen-Settings.extension",
            fallback: "x-apple.systempreferences:com.apple.preference.security"
        )
    }

    @discardableResult
    static func openLocationServices() -> Bool {
        openSystemSettings(
            primary: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices",
            fallback: "x-apple.systempreferences:com.apple.preference.security"
        )
    }

    @discardableResult
    static func openLoginItems() -> Bool {
        openSystemSettings(
            primary: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension",
            fallback: "x-apple.systempreferences:com.apple.preference.users"
        )
    }
}

struct SwitchOperationResult {
    var snapshot: SwitchSnapshot
    var error: String?
}

enum AccessibilityPermission {
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    static func requestAndOpenSettings() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        return openSettings()
    }

    @discardableResult
    static func openSettings() -> Bool {
        SystemSettingsLinks.openAccessibility()
    }
}

enum AutomationPermission {
    static func isDenied(_ result: (status: Int32, output: String, error: String)) -> Bool {
        let combined = "\(result.output)\n\(result.error)".lowercased()
        return combined.contains("-1743")
            || combined.contains("not authorized to send apple events")
            || combined.contains("not authorised to send apple events")
            || combined.contains("not permitted to send apple events")
            || combined.contains("not allowed to send apple events")
            || combined.contains("erraeeventnotpermitted")
    }

    static func deniedMessage(for result: (status: Int32, output: String, error: String), target: String) -> String? {
        guard isDenied(result) else { return nil }
        return permissionMessage(for: target)
    }

    static func permissionMessage(for target: String) -> String {
        "\"\(target)\" requires the automation feature. Grant access to Mac Switch in System Settings > Privacy & Security > Automation."
    }

    @discardableResult
    static func openSettings() -> Bool {
        SystemSettingsLinks.openAutomation()
    }
}

final class SystemSwitchController {
    var onExternalChange: ((SwitchKind) -> Void)?

    private let keepAwake = KeepAwakeManager()
    private let stageManager = StageManagerSwitch()
    private let hideWidgets = HideWidgetsSwitch()
    private let muteMicrophone = MuteMicrophoneSwitch()
    private let hideDesktopIcons = HideDesktopIconsSwitch()
    private let darkMode = DarkModeSwitch()
    private let screenSaver = ScreenSaverSwitch()
    private let bluetoothAudio = BluetoothAudioSwitch()
    private let doNotDisturb = DoNotDisturbSwitch()
    private let nightShift = NightShiftSwitch()
    private let trueTone = TrueToneSwitch()
    private let playMusic = PlayMusicSwitch()
    private let showHiddenFiles = ShowHiddenFilesSwitch()
    private let displaySleep = DisplaySleepSwitch()
    private let screenResolution = ScreenResolutionSwitch()
    private let keyboardLocker = KeyboardLocker()
    private let lockScreen = LockScreenSwitch()
    private let xcodeClean = XcodeCleanSwitch()
    private let emptyTrash = EmptyTrashSwitch()
    private let ejectDisk = EjectDiskSwitch()
    private let emptyPasteboard = EmptyPasteboardSwitch()
    private let hideWindows = HideWindowsSwitch()
    private let hideDock = HideDockSwitch()
    private let lowPowerMode = LowPowerModeSwitch()
    private let energyMode = EnergyModeSwitch()
    private lazy var screenCleaner: ScreenCleaner = {
        let cleaner = ScreenCleaner()
        cleaner.onFinished = { [weak self] in
            self?.onExternalChange?(.screenClean)
        }
        return cleaner
    }()

    init() {
        keepAwake.onExpired = { [weak self] in
            self?.onExternalChange?(.keepAwake)
        }
    }

    func snapshot(for kind: SwitchKind, keepAwakeDuration: KeepAwakeDuration) -> SwitchSnapshot {
        switch kind {
        case .keepAwake:
            return SwitchSnapshot(
                isOn: keepAwake.isActive,
                isAvailable: true,
                subtitle: keepAwake.subtitle(defaultDuration: keepAwakeDuration),
                warning: nil
            )
        case .stageManager:
            return stageManager.snapshot()
        case .hideWidgets:
            return hideWidgets.snapshot()
        case .muteMicrophone:
            return muteMicrophone.snapshot()
        case .hideDesktopIcons:
            return hideDesktopIcons.snapshot()
        case .darkMode:
            return darkMode.snapshot()
        case .screenSaver:
            return screenSaver.snapshot()
        case .bluetoothAudio:
            return bluetoothAudio.snapshot()
        case .doNotDisturb:
            return doNotDisturb.snapshot()
        case .nightShift:
            return nightShift.snapshot()
        case .trueTone:
            return trueTone.snapshot()
        case .playMusic:
            return playMusic.snapshot()
        case .showHiddenFiles:
            return showHiddenFiles.snapshot()
        case .displaySleep:
            return displaySleep.snapshot()
        case .screenResolution:
            return screenResolution.snapshot()
        case .screenClean:
            return screenCleaner.snapshot()
        case .lockKeyboard:
            return keyboardLocker.snapshot()
        case .lockScreen:
            return lockScreen.snapshot()
        case .xcodeClean:
            return xcodeClean.snapshot()
        case .emptyTrash:
            return emptyTrash.snapshot()
        case .ejectDisk:
            return ejectDisk.snapshot()
        case .emptyPasteboard:
            return emptyPasteboard.snapshot()
        case .hideWindows:
            return hideWindows.snapshot()
        case .hideDock:
            return hideDock.snapshot()
        case .lowPowerMode:
            return lowPowerMode.snapshot()
        case .energyMode:
            return energyMode.snapshot()
        }
    }

    func set(_ kind: SwitchKind, enabled: Bool, keepAwakeDuration: KeepAwakeDuration) -> SwitchOperationResult {
        switch kind {
        case .keepAwake:
            let error = keepAwake.setEnabled(enabled, duration: keepAwakeDuration.seconds)
            return SwitchOperationResult(snapshot: snapshot(for: kind, keepAwakeDuration: keepAwakeDuration), error: error)
        case .stageManager:
            let error = stageManager.setEnabled(enabled)
            return SwitchOperationResult(snapshot: snapshot(for: kind, keepAwakeDuration: keepAwakeDuration), error: error)
        case .hideWidgets:
            let error = hideWidgets.setEnabled(enabled)
            return SwitchOperationResult(snapshot: snapshot(for: kind, keepAwakeDuration: keepAwakeDuration), error: error)
        case .muteMicrophone:
            let error = muteMicrophone.setEnabled(enabled)
            return SwitchOperationResult(snapshot: snapshot(for: kind, keepAwakeDuration: keepAwakeDuration), error: error)
        case .hideDesktopIcons:
            let error = hideDesktopIcons.setEnabled(enabled)
            return SwitchOperationResult(snapshot: snapshot(for: kind, keepAwakeDuration: keepAwakeDuration), error: error)
        case .darkMode:
            let error = darkMode.setEnabled(enabled)
            return SwitchOperationResult(snapshot: snapshot(for: kind, keepAwakeDuration: keepAwakeDuration), error: error)
        case .screenSaver:
            return screenSaver.perform()
        case .bluetoothAudio:
            let error = bluetoothAudio.setEnabled(enabled)
            return SwitchOperationResult(snapshot: snapshot(for: kind, keepAwakeDuration: keepAwakeDuration), error: error)
        case .doNotDisturb:
            let error = doNotDisturb.setEnabled(enabled)
            return SwitchOperationResult(snapshot: snapshot(for: kind, keepAwakeDuration: keepAwakeDuration), error: error)
        case .nightShift:
            let error = nightShift.setEnabled(enabled)
            return SwitchOperationResult(snapshot: snapshot(for: kind, keepAwakeDuration: keepAwakeDuration), error: error)
        case .trueTone:
            let error = trueTone.setEnabled(enabled)
            return SwitchOperationResult(snapshot: snapshot(for: kind, keepAwakeDuration: keepAwakeDuration), error: error)
        case .playMusic:
            let error = playMusic.setEnabled(enabled)
            return SwitchOperationResult(snapshot: snapshot(for: kind, keepAwakeDuration: keepAwakeDuration), error: error)
        case .showHiddenFiles:
            let error = showHiddenFiles.setEnabled(enabled)
            return SwitchOperationResult(snapshot: snapshot(for: kind, keepAwakeDuration: keepAwakeDuration), error: error)
        case .displaySleep:
            return displaySleep.perform()
        case .screenResolution:
            let error = screenResolution.setEnabled(enabled)
            return SwitchOperationResult(snapshot: snapshot(for: kind, keepAwakeDuration: keepAwakeDuration), error: error)
        case .screenClean:
            let error = screenCleaner.setEnabled(enabled)
            return SwitchOperationResult(snapshot: snapshot(for: kind, keepAwakeDuration: keepAwakeDuration), error: error)
        case .lockKeyboard:
            let error = keyboardLocker.setEnabled(enabled)
            return SwitchOperationResult(snapshot: snapshot(for: kind, keepAwakeDuration: keepAwakeDuration), error: error)
        case .lockScreen:
            return lockScreen.perform()
        case .xcodeClean:
            return xcodeClean.perform()
        case .emptyTrash:
            return emptyTrash.perform()
        case .ejectDisk:
            return ejectDisk.perform()
        case .emptyPasteboard:
            return emptyPasteboard.perform()
        case .hideWindows:
            return hideWindows.perform()
        case .hideDock:
            let error = hideDock.setEnabled(enabled)
            return SwitchOperationResult(snapshot: snapshot(for: kind, keepAwakeDuration: keepAwakeDuration), error: error)
        case .lowPowerMode:
            let error = lowPowerMode.setEnabled(enabled)
            return SwitchOperationResult(snapshot: snapshot(for: kind, keepAwakeDuration: keepAwakeDuration), error: error)
        case .energyMode:
            let error = energyMode.setEnabled(enabled)
            return SwitchOperationResult(snapshot: snapshot(for: kind, keepAwakeDuration: keepAwakeDuration), error: error)
        }
    }

    func performXcodeClean(progress: @escaping (Double) -> Void) -> SwitchOperationResult {
        xcodeClean.perform(progress: progress)
    }

    func prepareForTermination() {
        _ = keepAwake.setEnabled(false, duration: nil)
        _ = keyboardLocker.setEnabled(false)
        _ = screenCleaner.setEnabled(false)
    }
}

private final class KeepAwakeManager {
    private let stateLock = NSLock()
    private var assertionIDs: [IOPMAssertionID] = []
    private var expirationWorkItem: DispatchWorkItem?
    private var endDate: Date?
    var onExpired: (() -> Void)?

    init() {
        if KeepAwakePreferences.managedDisableSleep, !Self.isSafeSelfTest {
            DispatchQueue.global(qos: .utility).async {
                if KeepAwakePreferences.setSleepDisabled(false) == nil {
                    KeepAwakePreferences.managedDisableSleep = false
                }
            }
        }
    }

    private static var isSafeSelfTest: Bool {
        CommandLine.arguments.contains("--self-test-safe")
    }

    deinit {
        disable()
    }

    var isActive: Bool {
        stateLock.lock()
        let active = !assertionIDs.isEmpty
        stateLock.unlock()
        return active
    }

    func subtitle(defaultDuration: KeepAwakeDuration) -> String {
        let state = currentState()
        guard state.isActive else {
            return defaultDuration.dashboardSubtitle
        }
        if KeepAwakePreferences.managedDisableSleep {
            return "Disable Sleep Enabled"
        }
        guard let endDate = state.endDate else {
            return "Active indefinitely"
        }
        return "Active until \(timeDisplay(for: endDate))"
    }

    func setEnabled(_ enabled: Bool, duration: TimeInterval?) -> String? {
        if enabled {
            let restoreError = disable()
            let reason = "Mac Switch Keep Awake" as CFString
            var systemID = IOPMAssertionID(0)
            var displayID = IOPMAssertionID(0)
            let systemResult = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                reason,
                &systemID
            )
            let displayResult = IOPMAssertionCreateWithName(
                kIOPMAssertionTypeNoDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                reason,
                &displayID
            )
            var createdAssertionIDs: [IOPMAssertionID] = []
            if systemResult == kIOReturnSuccess { createdAssertionIDs.append(systemID) }
            if displayResult == kIOReturnSuccess { createdAssertionIDs.append(displayID) }

            guard systemResult == kIOReturnSuccess, displayResult == kIOReturnSuccess else {
                releaseAssertions(createdAssertionIDs)
                return powerAssertionFailureMessage(systemResult: systemResult, displayResult: displayResult)
            }
            replaceAssertions(createdAssertionIDs)

            var disableSleepError: String?
            if KeepAwakePreferences.keepAwakeWhenLidClosed,
               !KeepAwakePreferences.sleepDisabled {
                disableSleepError = KeepAwakePreferences.setSleepDisabled(true)
                if disableSleepError == nil {
                    KeepAwakePreferences.managedDisableSleep = true
                }
            }

            if let duration {
                scheduleExpiration(after: duration)
            } else {
                clearExpiration()
            }
            if let disableSleepError {
                return "Keep Awake is active, but could not disable lid-closed sleep: \(disableSleepError)"
            }
            return restoreError.map { "Keep Awake is active, but could not restore the previous disable-sleep state first: \($0)" }
        } else {
            return disable()
        }
    }

    @discardableResult
    private func disable() -> String? {
        let ids = takeAssertionsAndCancelExpiration()
        ids.forEach { IOPMAssertionRelease($0) }
        if KeepAwakePreferences.managedDisableSleep {
            if let error = KeepAwakePreferences.setSleepDisabled(false) {
                return error
            }
            KeepAwakePreferences.managedDisableSleep = false
        }
        return nil
    }

    private func currentState() -> (isActive: Bool, endDate: Date?) {
        stateLock.lock()
        let state = (!assertionIDs.isEmpty, endDate)
        stateLock.unlock()
        return state
    }

    private func replaceAssertions(_ ids: [IOPMAssertionID]) {
        stateLock.lock()
        assertionIDs = ids
        stateLock.unlock()
    }

    private func scheduleExpiration(after duration: TimeInterval) {
        let deadline = Date().addingTimeInterval(duration)
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            _ = self.disable()
            self.onExpired?()
        }
        stateLock.lock()
        expirationWorkItem?.cancel()
        expirationWorkItem = workItem
        endDate = deadline
        stateLock.unlock()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + duration, execute: workItem)
    }

    private func clearExpiration() {
        stateLock.lock()
        expirationWorkItem?.cancel()
        expirationWorkItem = nil
        endDate = nil
        stateLock.unlock()
    }

    private func takeAssertionsAndCancelExpiration() -> [IOPMAssertionID] {
        stateLock.lock()
        expirationWorkItem?.cancel()
        expirationWorkItem = nil
        endDate = nil
        let ids = assertionIDs
        assertionIDs.removeAll()
        stateLock.unlock()
        return ids
    }

    private func releaseAssertions(_ ids: [IOPMAssertionID]) {
        ids.forEach { IOPMAssertionRelease($0) }
    }

    private func powerAssertionFailureMessage(systemResult: IOReturn, displayResult: IOReturn) -> String {
        var failures: [String] = []
        if systemResult != kIOReturnSuccess {
            failures.append("system sleep")
        }
        if displayResult != kIOReturnSuccess {
            failures.append("display sleep")
        }
        let target = failures.isEmpty ? "power" : failures.joined(separator: " and ")
        return "Could not create the \(target) assertion."
    }

    private func timeDisplay(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        guard let hour = components.hour, let minute = components.minute else { return "" }
        return TimeOfDay(hour: hour, minute: minute).display
    }
}

enum KeepAwakePreferences {
    private static let keepAwakeWhenLidClosedKey = "switch.keepAwake.keepAwakeWhenLidClosed"
    private static let managedDisableSleepKey = "switch.keepAwake.managedDisableSleep"

    static var keepAwakeWhenLidClosed: Bool {
        get { UserDefaults.standard.bool(forKey: keepAwakeWhenLidClosedKey) }
        set { UserDefaults.standard.set(newValue, forKey: keepAwakeWhenLidClosedKey) }
    }

    fileprivate static var managedDisableSleep: Bool {
        get { UserDefaults.standard.bool(forKey: managedDisableSleepKey) }
        set { UserDefaults.standard.set(newValue, forKey: managedDisableSleepKey) }
    }

    static var sleepDisabled: Bool {
        let result = ProcessRunner.run("/usr/bin/pmset", ["-g", "live"], timeout: 2)
        guard result.status == 0 else { return false }
        for line in result.output.split(separator: "\n") {
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            if parts.first == "SleepDisabled",
               let value = parts.dropFirst().first {
                return value == "1"
            }
        }
        return false
    }

    fileprivate static func setSleepDisabled(_ disabled: Bool) -> String? {
        let value = disabled ? 1 : 0
        let script = """
        do shell script "/usr/bin/pmset -a disablesleep \(value)" with administrator privileges
        """
        let result = ProcessRunner.run("/usr/bin/osascript", ["-e", script], timeout: 120)
        if result.status == 0 {
            return waitForSystemSwitchCondition(timeout: 1.5, { sleepDisabled == disabled })
                ? nil
                : "macOS accepted the request, but lid-closed sleep did not change."
        }
        if let automationError = AutomationPermission.deniedMessage(for: result, target: "System Events") {
            return automationError
        }
        return ProcessRunner.failureMessage(for: result, fallback: "Could not update disable sleep.")
    }
}

private struct StageManagerSwitch {
    func snapshot() -> SwitchSnapshot {
        if #unavailable(macOS 13) {
            return SwitchSnapshot(isOn: false, isAvailable: false, subtitle: nil, warning: unsupportedSystemMessage)
        }
        return SwitchSnapshot(isOn: isEnabled, isAvailable: true, subtitle: nil, warning: nil)
    }

    var isEnabled: Bool {
        readEnabled() ?? false
    }

    private func readEnabled() -> Bool? {
        let result = ProcessRunner.run("/usr/bin/defaults", ["read", "com.apple.WindowManager", "GloballyEnabled"], timeout: 2)
        guard result.status == 0 else { return nil }
        let value = result.output.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return value == "1" || value == "true" || value == "yes"
    }

    func setEnabled(_ enabled: Bool) -> String? {
        if #unavailable(macOS 13) {
            return unsupportedSystemMessage
        }
        let write = ProcessRunner.run("/usr/bin/defaults", [
            "write", "com.apple.WindowManager", "GloballyEnabled", "-bool", enabled ? "true" : "false"
        ], timeout: 2)
        if write.status != 0 {
            return ProcessRunner.failureMessage(for: write, fallback: "Could not update Stage Manager.")
        }
        guard waitForSystemSwitchCondition({ readEnabled() == enabled }) else {
            return "macOS accepted the request, but Stage Manager did not change."
        }
        return restartProcessOrReport(
            "Dock",
            failureMessage: "Stage Manager changed, but Dock could not restart to apply it."
        )
    }
}

private struct DarkModeSwitch {
    func snapshot() -> SwitchSnapshot {
        SwitchSnapshot(isOn: isEnabled, isAvailable: true, subtitle: nil, warning: nil)
    }

    var isEnabled: Bool {
        let result = ProcessRunner.run("/usr/bin/defaults", ["read", "-g", "AppleInterfaceStyle"], timeout: 2)
        return result.output.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "dark"
    }

    func setEnabled(_ enabled: Bool) -> String? {
        let script = """
        tell application "System Events"
            tell appearance preferences
                set dark mode to \(enabled ? "true" : "false")
            end tell
        end tell
        """
        let result = ProcessRunner.run("/usr/bin/osascript", ["-e", script], timeout: 15)
        if result.status != 0 {
            if let automationError = AutomationPermission.deniedMessage(for: result, target: "System Events") {
                return automationError
            }
            return ProcessRunner.failureMessage(for: result, fallback: "Could not toggle Dark Mode.")
        }
        guard waitForSystemSwitchCondition(timeout: 1.5, { isEnabled == enabled }) else {
            return "macOS accepted the request, but Dark Mode did not change."
        }
        return nil
    }
}

private struct BlueLightTimePair {
    var hour: Int32 = 0
    var minute: Int32 = 0
}

private struct BlueLightSchedule {
    var start = BlueLightTimePair()
    var end = BlueLightTimePair()
}

private struct BlueLightStatus {
    var active = ObjCBool(false)
    var enabled = ObjCBool(false)
    var sunSchedulePermitted = ObjCBool(false)
    var mode: Int32 = 0
    var schedule = BlueLightSchedule()
    var disableFlags: UInt64 = 0
    var available = ObjCBool(false)
}

private final class CoreBrightnessClient {
    static let shared = CoreBrightnessClient()

    private let handle: UnsafeMutableRawPointer?

    private init() {
        handle = dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_NOW)
    }

    func makeClient(named name: String) -> NSObject? {
        guard handle != nil,
              let cls = NSClassFromString(name) as? NSObject.Type
        else { return nil }
        return cls.init()
    }
}

private struct NightShiftSwitch {
    func snapshot() -> SwitchSnapshot {
        guard let status = status else {
            return SwitchSnapshot(isOn: false, isAvailable: false, subtitle: nil, warning: unsupportedDeviceMessage)
        }
        let available = status.available.boolValue
        let autoScheduleEnabled = status.mode == 1
        return SwitchSnapshot(
            isOn: available && status.active.boolValue,
            isAvailable: available,
            subtitle: available && autoScheduleEnabled ? "Auto change from sunrise to sunset" : nil,
            warning: available ? nil : unsupportedDeviceMessage
        )
    }

    var autoScheduleEnabled: Bool? {
        guard let status, status.available.boolValue else { return nil }
        return status.mode == 1
    }

    private var client: NSObject? {
        CoreBrightnessClient.shared.makeClient(named: "CBBlueLightClient")
    }

    private var status: BlueLightStatus? {
        guard let client else { return nil }
        let selector = NSSelectorFromString("getBlueLightStatus:")
        guard client.responds(to: selector), let method = client.method(for: selector) else { return nil }
        typealias Function = @convention(c) (AnyObject, Selector, UnsafeMutableRawPointer) -> Bool
        let function = unsafeBitCast(method, to: Function.self)
        var value = BlueLightStatus()
        let ok = withUnsafeMutablePointer(to: &value) { pointer in
            function(client, selector, UnsafeMutableRawPointer(pointer))
        }
        return ok ? value : nil
    }

    func setEnabled(_ enabled: Bool) -> String? {
        guard let client else { return "Night Shift is not available on this device." }
        guard snapshot().isAvailable else { return "Night Shift is not supported by the current display." }

        let activeSelector = NSSelectorFromString("setActive:")
        if client.responds(to: activeSelector), let method = client.method(for: activeSelector) {
            typealias Function = @convention(c) (AnyObject, Selector, Bool) -> Bool
            let function = unsafeBitCast(method, to: Function.self)
            if function(client, activeSelector, enabled),
               waitForNightShiftActive(enabled) {
                return nil
            }
        }

        let enabledSelector = NSSelectorFromString("setEnabled:")
        if client.responds(to: enabledSelector), let method = client.method(for: enabledSelector) {
            typealias Function = @convention(c) (AnyObject, Selector, Bool) -> Bool
            let function = unsafeBitCast(method, to: Function.self)
            guard function(client, enabledSelector, enabled) else {
                return "Could not toggle Night Shift."
            }
            return waitForNightShiftActive(enabled)
                ? nil
                : "macOS accepted the request, but Night Shift did not change."
        }

        return "Could not toggle Night Shift."
    }

    func setAutoScheduleEnabled(_ enabled: Bool) -> String? {
        guard let client else { return "Night Shift is not available on this device." }
        guard snapshot().isAvailable else { return "Night Shift is not supported by the current display." }
        let selector = NSSelectorFromString("setMode:")
        guard client.responds(to: selector), let method = client.method(for: selector) else {
            return "Could not update Night Shift schedule."
        }
        typealias Function = @convention(c) (AnyObject, Selector, Int32) -> Bool
        let function = unsafeBitCast(method, to: Function.self)
        guard function(client, selector, enabled ? 1 : 0) else {
            return "Could not update Night Shift schedule."
        }
        return waitForSystemSwitchCondition { autoScheduleEnabled == enabled }
            ? nil
            : "macOS accepted the request, but the Night Shift schedule did not change."
    }

    private func waitForNightShiftActive(_ enabled: Bool) -> Bool {
        waitForSystemSwitchCondition {
            guard let status else { return false }
            return status.available.boolValue && status.active.boolValue == enabled
        }
    }
}

enum NightShiftPreferences {
    static var autoScheduleEnabled: Bool? {
        NightShiftSwitch().autoScheduleEnabled
    }

    static func setAutoScheduleEnabled(_ enabled: Bool) -> String? {
        NightShiftSwitch().setAutoScheduleEnabled(enabled)
    }
}

private struct TrueToneSwitch {
    func snapshot() -> SwitchSnapshot {
        guard let client else {
            return SwitchSnapshot(isOn: false, isAvailable: false, subtitle: nil, warning: unsupportedDeviceMessage)
        }
        let supported = bool(client, "supported")
        let available = bool(client, "available")
        let enabled = bool(client, "enabled")
        let canUse = supported && available
        return SwitchSnapshot(
            isOn: canUse && enabled,
            isAvailable: canUse,
            subtitle: nil,
            warning: canUse ? nil : unsupportedDeviceMessage
        )
    }

    private var client: NSObject? {
        CoreBrightnessClient.shared.makeClient(named: "CBTrueToneClient")
    }

    func setEnabled(_ enabled: Bool) -> String? {
        guard let client else { return "True Tone is not available on this device." }
        guard bool(client, "supported"), bool(client, "available") else {
            return "True Tone is not supported by the current display."
        }
        let selector = NSSelectorFromString("setEnabled:")
        guard client.responds(to: selector), let method = client.method(for: selector) else {
            return "Could not toggle True Tone."
        }
        typealias Function = @convention(c) (AnyObject, Selector, Bool) -> Bool
        let function = unsafeBitCast(method, to: Function.self)
        guard function(client, selector, enabled) else {
            return "Could not toggle True Tone."
        }
        return waitForSystemSwitchCondition { bool(client, "enabled") == enabled }
            ? nil
            : "macOS accepted the request, but True Tone did not change."
    }

    private func bool(_ object: NSObject, _ selectorName: String) -> Bool {
        let selector = NSSelectorFromString(selectorName)
        guard object.responds(to: selector), let method = object.method(for: selector) else { return false }
        typealias Function = @convention(c) (AnyObject, Selector) -> Bool
        let function = unsafeBitCast(method, to: Function.self)
        return function(object, selector)
    }
}

private final class KeyboardLocker {
    private let eventTap = EventBlocker(mode: .keyboardOnly)

    deinit {
        eventTap.stop()
    }

    func snapshot() -> SwitchSnapshot {
        guard eventTap.isActive || AccessibilityPermission.isTrusted else {
            return SwitchSnapshot(
                isOn: false,
                isAvailable: true,
                subtitle: "Accessibility permission required",
                warning: "Open System Settings"
            )
        }
        return SwitchSnapshot(
            isOn: eventTap.isActive,
            isAvailable: true,
            subtitle: eventTap.isActive ? "Keyboard is locked - click the switch to unlock" : nil,
            warning: nil
        )
    }

    func setEnabled(_ enabled: Bool) -> String? {
        if enabled {
            return eventTap.start()
        }
        eventTap.stop()
        return eventTap.isActive ? "Could not stop the keyboard lock event tap." : nil
    }
}

private final class ScreenCleaner {
    var onFinished: (() -> Void)?

    private let maximumSessionDuration: TimeInterval = 10 * 60
    private let eventTap = EventBlocker(mode: .screenClean)
    private var windows: [NSWindow] = []
    private var exitMonitors: [Any] = []
    private var failSafeExitWorkItem: DispatchWorkItem?

    deinit {
        finish()
    }

    var isActive: Bool { !windows.isEmpty || eventTap.isActive }

    func snapshot() -> SwitchSnapshot {
        guard isActive || AccessibilityPermission.isTrusted else {
            return SwitchSnapshot(
                isOn: false,
                isAvailable: true,
                subtitle: "Accessibility permission required",
                warning: "Open System Settings"
            )
        }
        return SwitchSnapshot(isOn: isActive, isAvailable: true, subtitle: isActive ? "Click or press Esc to exit" : nil, warning: nil)
    }

    func setEnabled(_ enabled: Bool) -> String? {
        if enabled {
            if isActive { return nil }
            if let error = eventTap.start(onEscape: { [weak self] in self?.finish() }) {
                return error
            }
            guard startOverlay() else {
                eventTap.stop()
                return "No display is available for cleaning mode."
            }
            installExitMonitors()
            scheduleFailSafeExit()
            guard windows.allSatisfy(\.isVisible), eventTap.isActive else {
                finish()
                return "Could not present screen cleaning mode on every display."
            }
            return nil
        }
        finish()
        return isActive ? "Could not exit screen cleaning mode." : nil
    }

    @discardableResult
    private func startOverlay() -> Bool {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return false }

        windows = screens.map { screen in
            let window = ScreenCleanWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.onExit = { [weak self] in self?.finish() }
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.isOpaque = true
            window.backgroundColor = .black
            window.acceptsMouseMovedEvents = true
            window.contentView = NSHostingView(rootView: ScreenCleanOverlayView())
            window.makeKeyAndOrderFront(nil)
            return window
        }
        if windows.isEmpty || !windows.allSatisfy(\.isVisible) {
            windows.forEach { $0.orderOut(nil) }
            windows.removeAll()
            return false
        }
        return true
    }

    private func finish() {
        let wasActive = isActive
        cancelFailSafeExit()
        removeExitMonitors()
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        eventTap.stop()
        if wasActive {
            onFinished?()
        }
    }

    private func installExitMonitors() {
        guard exitMonitors.isEmpty else { return }

        let local = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]) { [weak self] event in
            if event.type == .keyDown, event.keyCode != 53 {
                return nil
            }
            DispatchQueue.main.async { self?.finish() }
            return nil
        }
        if let local {
            exitMonitors.append(local)
        }

        let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            DispatchQueue.main.async { self?.finish() }
        }
        if let global {
            exitMonitors.append(global)
        }
    }

    private func removeExitMonitors() {
        exitMonitors.forEach { NSEvent.removeMonitor($0) }
        exitMonitors.removeAll()
    }

    private func scheduleFailSafeExit() {
        cancelFailSafeExit()
        let workItem = DispatchWorkItem { [weak self] in
            self?.finish()
        }
        failSafeExitWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + maximumSessionDuration, execute: workItem)
    }

    private func cancelFailSafeExit() {
        failSafeExitWorkItem?.cancel()
        failSafeExitWorkItem = nil
    }
}

private final class ScreenCleanWindow: NSWindow {
    var onExit: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            onExit?()
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            onExit?()
        case .keyDown where event.keyCode == 53:
            onExit?()
        default:
            super.sendEvent(event)
        }
    }
}

private enum EventBlockMode {
    case keyboardOnly
    case screenClean
}

enum ScreenCleanExitEvent {
    static func shouldExit(type: CGEventType, keyCode: Int64? = nil) -> Bool {
        switch type {
        case .keyDown:
            return keyCode == 53
        case .leftMouseDown, .rightMouseDown, .otherMouseDown,
             .leftMouseUp, .rightMouseUp, .otherMouseUp:
            return true
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            return true
        default:
            return false
        }
    }
}

private final class EventBlocker {
    private let mode: EventBlockMode
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var onEscape: (() -> Void)?

    var isActive: Bool { eventTap != nil }

    init(mode: EventBlockMode) {
        self.mode = mode
    }

    deinit {
        stop()
    }

    func start(onEscape: (() -> Void)? = nil) -> String? {
        if isActive { return nil }
        self.onEscape = onEscape

        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else {
            return "Accessibility permission is required."
        }

        let mask = mode == .keyboardOnly ? keyboardMask : cleaningMask
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: eventTapCallback,
            userInfo: refcon
        ) else {
            return "Could not create the input event tap."
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        guard let runLoopSource else {
            CFMachPortInvalidate(tap)
            eventTap = nil
            self.onEscape = nil
            return "Could not attach the input event tap."
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        guard CGEvent.tapIsEnabled(tap: tap) else {
            stop()
            return "Could not enable the input event tap."
        }
        return nil
    }

    func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        runLoopSource = nil
        eventTap = nil
        onEscape = nil
    }

    fileprivate func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if mode == .screenClean {
                DispatchQueue.main.async { [weak self] in self?.onEscape?() }
            }
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        if mode == .screenClean {
            let keyCode = type == .keyDown ? event.getIntegerValueField(.keyboardEventKeycode) : nil
            if ScreenCleanExitEvent.shouldExit(type: type, keyCode: keyCode) {
                DispatchQueue.main.async { [weak self] in self?.onEscape?() }
                return nil
            }
        }

        return nil
    }

    private var keyboardMask: CGEventMask {
        (1 << CGEventType.keyDown.rawValue) |
        (1 << CGEventType.keyUp.rawValue) |
        (1 << CGEventType.flagsChanged.rawValue)
    }

    private var cleaningMask: CGEventMask {
        keyboardMask |
        (1 << CGEventType.leftMouseDown.rawValue) |
        (1 << CGEventType.leftMouseUp.rawValue) |
        (1 << CGEventType.rightMouseDown.rawValue) |
        (1 << CGEventType.rightMouseUp.rawValue) |
        (1 << CGEventType.otherMouseDown.rawValue) |
        (1 << CGEventType.otherMouseUp.rawValue) |
        (1 << CGEventType.mouseMoved.rawValue) |
        (1 << CGEventType.leftMouseDragged.rawValue) |
        (1 << CGEventType.rightMouseDragged.rawValue) |
        (1 << CGEventType.otherMouseDragged.rawValue) |
        (1 << CGEventType.scrollWheel.rawValue)
    }

}

private let eventTapCallback: CGEventTapCallBack = { proxy, type, event, refcon in
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let blocker = Unmanaged<EventBlocker>.fromOpaque(refcon).takeUnretainedValue()
    return blocker.handle(proxy: proxy, type: type, event: event)
}

private final class ProcessOutputBuffer {
    private let lock = NSLock()
    private var data = Data()

    func replace(with newData: Data) {
        lock.lock()
        data = newData
        lock.unlock()
    }

    func string() -> String {
        lock.lock()
        let value = data
        lock.unlock()
        return String(data: value, encoding: .utf8) ?? ""
    }
}

enum ProcessRunner {
    static func run(
        _ executable: String,
        _ arguments: [String],
        timeout: TimeInterval? = nil
    ) -> (status: Int32, output: String, error: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        let terminationSemaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            terminationSemaphore.signal()
        }

        do {
            try process.run()
        } catch {
            return (1, "", error.localizedDescription)
        }

        let readGroup = DispatchGroup()
        let outputBuffer = ProcessOutputBuffer()
        let errorBuffer = ProcessOutputBuffer()

        readGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            outputBuffer.replace(with: outputPipe.fileHandleForReading.readDataToEndOfFile())
            readGroup.leave()
        }

        readGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            errorBuffer.replace(with: errorPipe.fileHandleForReading.readDataToEndOfFile())
            readGroup.leave()
        }

        let didTimeOut: Bool
        if let timeout {
            didTimeOut = terminationSemaphore.wait(timeout: .now() + timeout) != .success
            if didTimeOut {
                process.terminate()
                if terminationSemaphore.wait(timeout: .now() + 0.75) != .success {
                    Darwin.kill(process.processIdentifier, SIGKILL)
                    _ = terminationSemaphore.wait(timeout: .now() + 0.75)
                }
            }
        } else {
            process.waitUntilExit()
            didTimeOut = false
        }

        _ = readGroup.wait(timeout: .now() + 2)
        let output = outputBuffer.string()
        let error = errorBuffer.string()
        if didTimeOut {
            let seconds = timeout.map { String(format: "%.1f", $0) } ?? ""
            let timeoutError = "Command timed out after \(seconds) seconds: \(executable) \(arguments.joined(separator: " "))"
            return (124, output, [error, timeoutError].filter { !$0.isEmpty }.joined(separator: "\n"))
        }
        return (process.terminationStatus, output, error)
    }

    static func failureMessage(
        for result: (status: Int32, output: String, error: String),
        fallback: String
    ) -> String {
        let text = [result.error, result.output]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        return text.isEmpty ? fallback : text
    }
}

enum LoginItemManager {
    static let label = "com.maxyu.macswitch.login"

    static var initialIsEnabled: Bool {
        if usesServiceManagement {
            if serviceManagementStatusIsEnabled {
                return true
            }
            return configuredProgramArguments != nil
        }
        return configuredProgramArguments != nil
    }

    static var isEnabled: Bool {
        if usesServiceManagement {
            if serviceManagementStatusIsEnabled {
                return true
            }
            return configuredProgramArguments != nil || launchAgentServiceLoaded
        }
        return configuredProgramArguments != nil || launchAgentServiceLoaded
    }

    static var isConfiguredForCurrentApp: Bool {
        if usesServiceManagement {
            guard configuredProgramArguments == nil else { return false }
            return serviceManagementStatusIsEnabled
        }
        return configuredProgramArguments == expectedProgramArguments && launchAgentPlistIsCurrent
    }

    static var isServiceLoaded: Bool {
        if usesServiceManagement {
            return serviceManagementStatusIsEnabled
        }
        return launchAgentServiceLoaded
    }

    static var needsRepair: Bool {
        if usesServiceManagement {
            return configuredProgramArguments != nil
                || launchAgentServiceLoaded
        }
        guard configuredProgramArguments != nil || launchAgentServiceLoaded else { return false }
        return !isConfiguredForCurrentApp || !isServiceLoaded
    }

    static var needsUserApproval: Bool {
        usesServiceManagement && serviceManagementStatusRequiresApproval
    }

    static func setEnabled(_ enabled: Bool) throws {
        if usesServiceManagement {
            try setServiceManagementEnabled(enabled)
            return
        }
        try setLaunchAgentEnabled(enabled)
    }

    static var diagnosticSummary: String {
        let configured = DiagnosticRedactor.redact(configuredProgramArguments?.joined(separator: " ") ?? "none")
        let expected = DiagnosticRedactor.redact(expectedProgramArguments.joined(separator: " "))
        let loaded = isServiceLoaded ? "loaded" : "not loaded"
        let current = isConfiguredForCurrentApp ? "yes" : "no"
        let backend = usesServiceManagement ? "serviceManagement" : "launchAgent"
        let serviceStatus = Bundle.main.bundleURL.pathExtension == "app" ? serviceManagementStatusText : "unavailable"
        let schema = launchAgentPlistIsCurrent ? "current" : "stale"
        let launchAgentPath = DiagnosticRedactor.redact(launchAgentURL.path)
        return "backend=\(backend), status=\(serviceStatus), plist=\(FileManager.default.fileExists(atPath: launchAgentURL.path) ? "present" : "missing"), schema=\(schema), service=\(loaded), current=\(current), configured=\(configured), expected=\(expected), path=\(launchAgentPath)"
    }

    private static var usesServiceManagement: Bool {
        Bundle.main.bundleURL.pathExtension == "app" && !serviceManagementStatusIsNotFound
    }

    private static var serviceManagementStatusIsEnabled: Bool {
        switch SMAppService.mainApp.status {
        case .enabled:
            return true
        default:
            return false
        }
    }

    private static var serviceManagementStatusRequiresApproval: Bool {
        switch SMAppService.mainApp.status {
        case .requiresApproval:
            return true
        default:
            return false
        }
    }

    private static var serviceManagementStatusIsNotFound: Bool {
        switch SMAppService.mainApp.status {
        case .notFound:
            return true
        default:
            return false
        }
    }

    private static var serviceManagementStatusText: String {
        switch SMAppService.mainApp.status {
        case .notRegistered:
            return "notRegistered"
        case .enabled:
            return "enabled"
        case .requiresApproval:
            return "requiresApproval"
        case .notFound:
            return "notFound"
        @unknown default:
            return "unknown"
        }
    }

    private static func setServiceManagementEnabled(_ enabled: Bool) throws {
        if enabled {
            switch SMAppService.mainApp.status {
            case .enabled, .requiresApproval:
                break
            default:
                try SMAppService.mainApp.register()
            }
            try removeLegacyLaunchAgentIfPresent()
            return
        }

        switch SMAppService.mainApp.status {
        case .enabled, .requiresApproval:
            try SMAppService.mainApp.unregister()
        default:
            break
        }
        try removeLegacyLaunchAgentIfPresent()
    }

    private static func setLaunchAgentEnabled(_ enabled: Bool) throws {
        if enabled {
            guard !expectedProgramArguments.isEmpty else {
                throw NSError(domain: "MacSwitchLoginItem", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "Could not determine the Mac Switch executable path."
                ])
            }
            try FileManager.default.createDirectory(at: launchAgentURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try makePlistData().write(to: launchAgentURL, options: .atomic)
            _ = bootout()

            let result = bootstrapWithLoadedServiceRecovery()
            if result.status != 0 {
                try? removeLaunchAgentIfPresent()
                throw NSError(domain: "MacSwitchLoginItem", code: Int(result.status), userInfo: [
                    NSLocalizedDescriptionKey: combinedOutput(result).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? "Could not enable Start at Login."
                        : combinedOutput(result).trimmingCharacters(in: .whitespacesAndNewlines)
                ])
            }

            guard isConfiguredForCurrentApp, isServiceLoaded else {
                try? removeLaunchAgentIfPresent()
                throw NSError(domain: "MacSwitchLoginItem", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "Could not verify the Start at Login launch agent."
                ])
            }
        } else {
            _ = bootout()
            try removeLaunchAgentIfPresent()
            guard configuredProgramArguments == nil else {
                throw NSError(domain: "MacSwitchLoginItem", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "Could not remove the Start at Login launch agent."
                ])
            }
            guard !launchAgentServiceLoaded else {
                throw NSError(domain: "MacSwitchLoginItem", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "Could not unload the Start at Login launch service."
                ])
            }
        }
    }

    private static var launchAgentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    private static var launchctlDomain: String {
        "gui/\(getuid())"
    }

    private static var launchAgentServiceLoaded: Bool {
        launchctlPrint().status == 0
    }

    private static var expectedProgramArguments: [String] {
        if Bundle.main.bundleURL.pathExtension == "app" {
            return ["/usr/bin/open", Bundle.main.bundleURL.path]
        }
        if let executable = Bundle.main.executablePath, !executable.isEmpty {
            return [executable]
        }
        return []
    }

    private static var configuredProgramArguments: [String]? {
        guard let plist = launchAgentPlist,
              let arguments = plist["ProgramArguments"] as? [String],
              !arguments.isEmpty
        else { return nil }
        return arguments
    }

    private static var launchAgentPlist: [String: Any]? {
        guard let data = try? Data(contentsOf: launchAgentURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              plist["Label"] as? String == label
        else { return nil }
        return plist
    }

    private static var launchAgentPlistIsCurrent: Bool {
        guard let plist = launchAgentPlist else { return false }
        return plist["ProgramArguments"] as? [String] == expectedProgramArguments
            && plist["RunAtLoad"] as? Bool == true
            && plist["KeepAlive"] as? Bool == false
            && plist["LimitLoadToSessionType"] as? String == "Aqua"
    }

    private static func makePlistData() throws -> Data {
        let dict: [String: Any] = [
            "Label": label,
            "ProgramArguments": expectedProgramArguments,
            "LimitLoadToSessionType": "Aqua",
            "RunAtLoad": true,
            "KeepAlive": false
        ]
        return try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
    }

    private static func launchctlPrint() -> (status: Int32, output: String, error: String) {
        ProcessRunner.run("/bin/launchctl", ["print", "\(launchctlDomain)/\(label)"], timeout: 5)
    }

    private static func bootstrap() -> (status: Int32, output: String, error: String) {
        ProcessRunner.run("/bin/launchctl", ["bootstrap", launchctlDomain, launchAgentURL.path], timeout: 5)
    }

    private static func bootstrapWithLoadedServiceRecovery() -> (status: Int32, output: String, error: String) {
        var result = bootstrap()
        if result.status != 0 && isAlreadyLoaded(result) {
            _ = bootout()
            result = bootstrap()
        }
        return result
    }

    private static func isAlreadyLoaded(_ result: (status: Int32, output: String, error: String)) -> Bool {
        combinedOutput(result).localizedCaseInsensitiveContains("service already loaded")
            || combinedOutput(result).localizedCaseInsensitiveContains("already bootstrapped")
    }

    private static func combinedOutput(_ result: (status: Int32, output: String, error: String)) -> String {
        "\(result.output)\n\(result.error)"
    }

    @discardableResult
    private static func bootout() -> (status: Int32, output: String, error: String) {
        let serviceResult = ProcessRunner.run("/bin/launchctl", ["bootout", "\(launchctlDomain)/\(label)"], timeout: 5)
        if serviceResult.status == 0 {
            return serviceResult
        }
        return ProcessRunner.run("/bin/launchctl", ["bootout", launchctlDomain, launchAgentURL.path], timeout: 5)
    }

    private static func removeLaunchAgentIfPresent() throws {
        if FileManager.default.fileExists(atPath: launchAgentURL.path) {
            try FileManager.default.removeItem(at: launchAgentURL)
        }
    }

    private static func removeLegacyLaunchAgentIfPresent() throws {
        guard FileManager.default.fileExists(atPath: launchAgentURL.path) || launchAgentServiceLoaded else {
            return
        }
        _ = bootout()
        try removeLaunchAgentIfPresent()
        guard !launchAgentServiceLoaded else {
            throw NSError(domain: "MacSwitchLoginItem", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Could not unload the legacy Start at Login launch service."
            ])
        }
    }
}
