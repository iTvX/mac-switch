import AppKit
import Carbon
import CoreGraphics
import CoreLocation
import Foundation

enum RegressionDiagnostics {
    static func runSafe() -> Int32 {
        var reporter = SelfTestReporter()

        reporter.section("Bundle")
        checkBundleMetadata(&reporter)
        checkAppIcon(&reporter)

        reporter.section("System dependencies")
        checkExecutableDependencies(&reporter)
        checkLockScreenSupport(&reporter)
        checkDisplays(&reporter)

        reporter.section("Runtime safeguards")
        checkProcessTimeout(&reporter)
        checkLargeProcessOutput(&reporter)
        checkScreenCleanExitEvents(&reporter)
        checkSystemSettingsURLs(&reporter)
        checkSunScheduleDateAlignment(&reporter)
        checkShortcutValidation(&reporter)
        checkDoNotDisturbShortcutStatus(&reporter)
        checkActionSafetyPreferences(&reporter)
        checkEjectDiskExclusions(&reporter)

        reporter.section("Default layout")
        checkDefaultVisibility(&reporter)

        reporter.section("Login item")
        checkLoginItem(&reporter)

        reporter.section("Switch snapshots")
        checkSnapshots(&reporter)

        reporter.finish()
        return reporter.hasFailures ? 1 : 0
    }

    private static func checkBundleMetadata(_ reporter: inout SelfTestReporter) {
        let info = bundledInfoDictionary()
        let requiredInfoKeys = [
            "CFBundleIdentifier",
            "CFBundleIconFile",
            "CFBundleName",
            "NSAppleEventsUsageDescription",
            "NSBluetoothAlwaysUsageDescription",
            "NSInputMonitoringUsageDescription",
            "NSLocationWhenInUseUsageDescription"
        ]

        for key in requiredInfoKeys {
            let value = info[key] as? String
            reporter.check(value?.isEmpty == false, "\(key) present")
        }

        reporter.check(info["CFBundleExecutable"] as? String == "MacSwitch", "CFBundleExecutable matches binary name")
        reporter.check(info["CFBundlePackageType"] as? String == "APPL", "CFBundlePackageType is APPL")
        reporter.check(info["LSApplicationCategoryType"] as? String == "public.app-category.utilities", "app category is Utilities")
        reporter.check(info["LSMinimumSystemVersion"] as? String == "14.0", "minimum macOS version is explicit")
        reporter.check(info["LSUIElement"] as? Bool == true, "app is configured as a menu bar accessory")
    }

    private static func checkAppIcon(_ reporter: inout SelfTestReporter) {
        let info = bundledInfoDictionary()
        guard let rawName = info["CFBundleIconFile"] as? String,
              !rawName.isEmpty
        else {
            reporter.fail("app icon declared")
            return
        }

        let iconFileName = rawName.hasSuffix(".icns") ? rawName : "\(rawName).icns"
        let fileManager = FileManager.default
        let cwd = URL(fileURLWithPath: fileManager.currentDirectoryPath)
        let candidateDirectories = [
            Bundle.main.resourceURL,
            cwd.appendingPathComponent("Resources", isDirectory: true),
            cwd.appendingPathComponent("Build/Mac Switch.app/Contents/Resources", isDirectory: true)
        ].compactMap { $0 }

        let exists = candidateDirectories.contains {
            fileManager.fileExists(atPath: $0.appendingPathComponent(iconFileName).path)
        }
        reporter.check(exists, "\(iconFileName) bundled")
    }

    private static func checkLoginItem(_ reporter: inout SelfTestReporter) {
        let summary = LoginItemManager.diagnosticSummary
        reporter.check(summary.contains("backend="), "Start at Login diagnostic includes backend")
        reporter.check(summary.contains("status="), "Start at Login diagnostic includes registration status")
        reporter.check(summary.contains("schema="), "Start at Login diagnostic includes launch agent schema")
        reporter.check(summary.contains("service="), "Start at Login diagnostic includes service load state")
        reporter.check(summary.contains("current="), "Start at Login diagnostic includes current app match")
        if LoginItemManager.needsUserApproval {
            reporter.pass("Start at Login pending approval: \(summary)")
        } else if LoginItemManager.isEnabled {
            let state = LoginItemManager.needsRepair ? "enabled, needs repair" : "enabled"
            reporter.pass("Start at Login \(state): \(summary)")
        } else {
            reporter.pass("Start at Login disabled: \(summary)")
        }
    }

    private static func bundledInfoDictionary() -> [String: Any] {
        if let info = Bundle.main.infoDictionary, info["CFBundleIdentifier"] != nil {
            return info
        }

        let fileManager = FileManager.default
        let candidates = [
            URL(fileURLWithPath: fileManager.currentDirectoryPath)
                .appendingPathComponent("Resources/Info.plist"),
            URL(fileURLWithPath: fileManager.currentDirectoryPath)
                .appendingPathComponent("Build/Mac Switch.app/Contents/Info.plist")
        ]

        for url in candidates where fileManager.fileExists(atPath: url.path) {
            if let data = try? Data(contentsOf: url),
               let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
                return plist
            }
        }

        return Bundle.main.infoDictionary ?? [:]
    }

    private static func checkExecutableDependencies(_ reporter: inout SelfTestReporter) {
        let paths = [
            "/usr/bin/defaults",
            "/usr/bin/killall",
            "/usr/bin/osascript",
            "/usr/bin/pgrep",
            "/usr/bin/pmset",
            "/usr/bin/shortcuts",
            "/bin/sh",
            "/bin/sleep",
            "/bin/launchctl"
        ]

        for path in paths {
            reporter.check(FileManager.default.isExecutableFile(atPath: path), "\(path) executable")
        }
    }

    private static func checkLockScreenSupport(_ reporter: inout SelfTestReporter) {
        let path = "/System/Library/PrivateFrameworks/login.framework/login"
        let symbolAvailable: Bool
        if let handle = dlopen(path, RTLD_LAZY) {
            symbolAvailable = dlsym(handle, "SACLockScreenImmediate") != nil
        } else {
            symbolAvailable = false
        }
        if symbolAvailable {
            reporter.pass("lock screen immediate framework available")
        } else {
            reporter.pass("lock screen will use System Events fallback")
        }
    }

    private static func checkDisplays(_ reporter: inout SelfTestReporter) {
        var count: UInt32 = 0
        let countResult = CGGetOnlineDisplayList(0, nil, &count)
        reporter.check(countResult == .success && count > 0, "online display list available")
        guard countResult == .success && count > 0 else { return }

        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        let listResult = CGGetOnlineDisplayList(count, &ids, &count)
        reporter.check(listResult == .success, "online displays enumerated")

        let displays = ids.prefix(Int(count))
        reporter.check(displays.contains { CGDisplayIsMain($0) != 0 }, "main display detected")

        for displayID in displays {
            let options = [kCGDisplayShowDuplicateLowResolutionModes as String: true] as CFDictionary
            let modes = CGDisplayCopyAllDisplayModes(displayID, options) as? [CGDisplayMode]
            reporter.check(modes?.isEmpty == false, "display \(displayID) modes available")
        }
    }

    private static func checkProcessTimeout(_ reporter: inout SelfTestReporter) {
        let started = Date()
        let result = ProcessRunner.run("/bin/sleep", ["2"], timeout: 0.1)
        let elapsed = Date().timeIntervalSince(started)
        reporter.check(result.status == 124 && elapsed < 1.5, "external command timeout terminates stalled commands")
    }

    private static func checkLargeProcessOutput(_ reporter: inout SelfTestReporter) {
        let script = """
        i=0
        while [ "$i" -lt 3000 ]; do
            printf '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789\\n'
            i=$((i + 1))
        done
        """
        let started = Date()
        let result = ProcessRunner.run("/bin/sh", ["-c", script], timeout: 3)
        let elapsed = Date().timeIntervalSince(started)
        reporter.check(
            result.status == 0 && result.output.count > 150_000 && elapsed < 3,
            "external command output is drained while running"
        )
    }

    private static func checkScreenCleanExitEvents(_ reporter: inout SelfTestReporter) {
        reporter.check(
            ScreenCleanExitEvent.shouldExit(type: .leftMouseDown),
            "Screen Cleaning exits on mouse down"
        )
        reporter.check(
            ScreenCleanExitEvent.shouldExit(type: .leftMouseUp),
            "Screen Cleaning exits on mouse up"
        )
        reporter.check(
            ScreenCleanExitEvent.shouldExit(type: .keyDown, keyCode: 53),
            "Screen Cleaning exits on Escape"
        )
        reporter.check(
            ScreenCleanExitEvent.shouldExit(type: .tapDisabledByTimeout),
            "Screen Cleaning exits if the event tap is disabled"
        )
        reporter.check(
            !ScreenCleanExitEvent.shouldExit(type: .mouseMoved),
            "Screen Cleaning ignores pointer movement"
        )
        reporter.check(
            !ScreenCleanExitEvent.shouldExit(type: .keyDown, keyCode: 0),
            "Screen Cleaning blocks non-Escape keys without exiting"
        )
    }

    private static func checkShortcutValidation(_ reporter: inout SelfTestReporter) {
        reporter.check(
            HotKeyShortcut.isValidGlobalShortcut(keyCode: 40, modifiers: UInt32(cmdKey | optionKey)),
            "shortcut validation accepts Command-Option shortcuts"
        )
        reporter.check(
            !HotKeyShortcut.isValidGlobalShortcut(keyCode: 40, modifiers: UInt32(cmdKey)),
            "shortcut validation rejects single-modifier shortcuts"
        )
        reporter.check(
            !HotKeyShortcut.isValidGlobalShortcut(keyCode: 0, modifiers: UInt32(cmdKey)),
            "shortcut validation rejects Command-A"
        )
        reporter.check(
            !HotKeyShortcut.isValidGlobalShortcut(keyCode: 1, modifiers: UInt32(shiftKey)),
            "shortcut validation rejects Shift-only shortcuts"
        )
        reporter.check(
            !HotKeyShortcut.isValidGlobalShortcut(keyCode: 53, modifiers: UInt32(cmdKey | optionKey)),
            "shortcut validation rejects reserved keys"
        )
    }

    private static func checkDoNotDisturbShortcutStatus(_ reporter: inout SelfTestReporter) {
        _ = DoNotDisturbPreferences.refreshInstalledShortcuts()
        if let error = DoNotDisturbPreferences.installedShortcutsError {
            reporter.pass("Shortcuts list failure is captured: \(error)")
        } else {
            reporter.pass("Shortcuts list status available")
        }
    }

    private static func checkActionSafetyPreferences(_ reporter: inout SelfTestReporter) {
        let suiteName = "com.maxyu.macswitch.selftest.safety.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            reporter.fail("safety preferences test defaults available")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        for kind in ActionSafetyPreferences.protectedKinds.sorted(by: { $0.title < $1.title }) {
            reporter.check(
                ActionSafetyPreferences.confirmationRequired(for: kind, defaults: defaults),
                "\(kind.title) asks for confirmation by default"
            )
            ActionSafetyPreferences.setConfirmationRequired(false, for: kind, defaults: defaults)
            reporter.check(
                !ActionSafetyPreferences.confirmationRequired(for: kind, defaults: defaults),
                "\(kind.title) confirmation preference can be disabled"
            )
        }
    }

    private static func checkEjectDiskExclusions(_ reporter: inout SelfTestReporter) {
        let path = "/Volumes/MacSwitchSelfTest"
        let url = URL(fileURLWithPath: path)
        reporter.check(
            EjectDiskPreferences.isExcluded(url, excludedPaths: [path]),
            "Eject Disk exclusion matching works without writing preferences"
        )
        let simulatorRuntimeURL = URL(fileURLWithPath: "/Library/Developer/CoreSimulator/Volumes/iOS_SelfTest")
        reporter.check(
            EjectDiskPreferences.isExcluded(simulatorRuntimeURL, excludedPaths: []),
            "Eject Disk protects CoreSimulator runtime volumes by default"
        )
    }

    private static func checkSystemSettingsURLs(_ reporter: inout SelfTestReporter) {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation",
            "x-apple.systempreferences:com.apple.Bluetooth",
            "x-apple.systempreferences:com.apple.Displays-Settings.extension",
            "x-apple.systempreferences:com.apple.Sound-Settings.extension",
            "x-apple.systempreferences:com.apple.Battery-Settings.extension",
            "x-apple.systempreferences:com.apple.Desktop-Settings.extension",
            "x-apple.systempreferences:com.apple.Lock-Screen-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices",
            "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
        ]

        for url in urls {
            reporter.check(URL(string: url) != nil, "system settings URL is valid: \(url)")
        }
    }

    private static func checkSunScheduleDateAlignment(_ reporter: inout SelfTestReporter) {
        var losAngeles = Calendar(identifier: .gregorian)
        losAngeles.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .current
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current

        let cases: [(String, Calendar, CLLocationCoordinate2D)] = [
            ("Los Angeles", losAngeles, CLLocationCoordinate2D(latitude: 34.0522, longitude: -118.2437)),
            ("Tokyo", tokyo, CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503))
        ]

        for testCase in cases {
            guard let date = testCase.1.date(from: DateComponents(year: 2026, month: 6, day: 21)),
                  let window = SolarCalculator.sunWindow(on: date, coordinate: testCase.2, calendar: testCase.1)
            else {
                reporter.fail("sun schedule calculates for \(testCase.0)")
                continue
            }
            let targetDay = testCase.1.startOfDay(for: date)
            reporter.check(
                testCase.1.startOfDay(for: window.sunrise) == targetDay
                    && testCase.1.startOfDay(for: window.sunset) == targetDay,
                "sun schedule aligns events to the requested local day for \(testCase.0)"
            )
        }
    }

    private static func checkDefaultVisibility(_ reporter: inout SelfTestReporter) {
        let defaults = Set(SwitchKind.allCases.filter(\.defaultEnabled))
        reporter.check(defaults.contains(.keepAwake), "default layout includes Keep Awake")
        reporter.check(defaults.contains(.stageManager), "default layout includes Stage Manager")
        reporter.check(defaults.contains(.darkMode), "default layout includes Dark Mode")
        reporter.check(!defaults.contains(.bluetoothAudio), "default layout hides Bluetooth Audio until configured")
        reporter.check(!defaults.contains(.doNotDisturb), "default layout hides Do Not Disturb until shortcuts are configured")
        reporter.check(!defaults.contains(.trueTone), "default layout hides device-dependent True Tone")
    }

    private static func checkSnapshots(_ reporter: inout SelfTestReporter) {
        let controller = SystemSwitchController()
        for kind in SwitchKind.allCases {
            if kind == .playMusic {
                reporter.pass("Play Music: skipped in safe self-test to avoid Automation prompts")
                continue
            }
            let snapshot = controller.snapshot(for: kind, keepAwakeDuration: .indefinitely)
            let state = snapshot.isAvailable ? "available" : "unavailable"
            let enabled = snapshot.isOn ? "on" : "off"
            var details = "\(kind.title): \(state), \(enabled)"
            if let subtitle = snapshot.subtitle, !subtitle.isEmpty {
                details += ", subtitle=present"
            }
            if let warning = snapshot.warning, !warning.isEmpty {
                details += ", warning=present"
            }
            reporter.pass(details)
        }
    }
}

private struct SelfTestReporter {
    private(set) var hasFailures = false

    mutating func section(_ title: String) {
        print("\n## \(title)")
    }

    mutating func check(_ condition: Bool, _ message: String) {
        if condition {
            pass(message)
        } else {
            fail(message)
        }
    }

    mutating func pass(_ message: String) {
        print("PASS \(message)")
    }

    mutating func fail(_ message: String) {
        hasFailures = true
        print("FAIL \(message)")
    }

    func finish() {
        print("\nResult: \(hasFailures ? "FAIL" : "PASS")")
    }
}
