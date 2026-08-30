import Foundation
import XCTest
@testable import MacSwitch

final class LocalizationResourceTests: XCTestCase {
    private let localeFolders: [String] = [
        "en", "zh-Hans", "zh-Hant", "es", "ja", "ko", "de", "fr", "it", "pt"
    ]

    func testEveryShippedLanguageHasTheCompleteSettingsCatalog() throws {
        let english = try strings(in: "en", named: "Localizable")
        XCTAssertGreaterThanOrEqual(english.count, 130)

        for locale in localeFolders {
            let localized = try strings(in: locale, named: "Localizable")
            XCTAssertEqual(
                Set(localized.keys),
                Set(english.keys),
                "\(locale) must contain every settings localization key"
            )
            XCTAssertTrue(localized.values.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
            if locale != "en" {
                XCTAssertGreaterThanOrEqual(
                    localized.filter { $0.key != $0.value }.count,
                    120,
                    "\(locale) still contains too many untranslated settings strings"
                )
            }
        }
    }

    func testEveryShippedLanguageLocalizesPermissionPrompts() throws {
        let expectedKeys: Set<String> = [
            "NSAppleEventsUsageDescription",
            "NSBluetoothAlwaysUsageDescription",
            "NSFocusStatusUsageDescription",
            "NSInputMonitoringUsageDescription",
            "NSLocationUsageDescription",
            "NSLocationWhenInUseUsageDescription"
        ]

        for locale in localeFolders {
            let localized = try strings(in: locale, named: "InfoPlist")
            XCTAssertEqual(Set(localized.keys), expectedKeys)
            XCTAssertTrue(localized.values.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        }
    }

    func testEveryShippedLanguageLocalizesTheCompleteHandoffExperience() throws {
        let expectedKeys: Set<String> = [
            "Continue supported tasks across nearby Apple devices.",
            "Turning off Handoff also affects Universal Clipboard, Universal Control, and Sidecar.",
            "Turn Off",
            "Turn On",
            "Handoff enabled",
            "Handoff disabled",
            "Handoff unavailable",
            "Handoff is managed by your organization",
            "Handoff status could not be refreshed",
            "Handoff control is unavailable on this macOS version",
            "Handoff settings are inconsistent; toggle to repair them",
            "Automatic Handoff status updates are unavailable; use Refresh",
            "Handoff settings could not be refreshed. No changes were made.",
            "Handoff is managed by your organization.",
            "Handoff control is unavailable on this macOS version. Use AirDrop & Handoff in System Settings.",
            "Handoff could not be updated. Previous settings were restored.",
            "Handoff could not be updated, and the previous settings could not be fully restored. Check AirDrop & Handoff in System Settings.",
            "Enable \"Handoff\" failed",
            "Disable \"Handoff\" failed",
            "Handoff is not available",
            "Open Handoff",
            "Updating",
            "Updating...",
            "Turning off before hiding",
            "Shown in menu",
            "Hidden",
            "Visible",
            "Record Shortcut",
            "Type shortcut..."
        ]

        for locale in localeFolders {
            let localized = try strings(in: locale, named: "Localizable")
            XCTAssertTrue(expectedKeys.isSubset(of: localized.keys), "\(locale) is missing Handoff copy")
            if locale != "en" {
                for key in expectedKeys {
                    XCTAssertNotEqual(localized[key], key, "\(locale) did not translate \(key)")
                }
            }
        }
    }

    func testCompositeHandoffErrorsLocalizeWithoutChangingTheRoutingMessage() throws {
        let source = "Enable \"Handoff\" failed: Handoff settings could not be refreshed. No changes were made."
        let catalog = try strings(in: "zh-Hans", named: "Localizable")
        let localized = L10n.localizedRuntimeMessage(source) { key in
            catalog[key] ?? key
        }

        XCTAssertEqual(localized, "开启“接力”失败: 无法刷新接力设置。未进行任何更改。")
        XCTAssertTrue(source.lowercased().contains("handoff"))
    }

    func testReleaseBuildPackagesEveryLocalization() throws {
        let infoData = try Data(contentsOf: packageRoot.appendingPathComponent("Resources/Info.plist"))
        let info = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: infoData, format: nil) as? [String: Any]
        )
        XCTAssertEqual(info["CFBundleLocalizations"] as? [String], localeFolders)

        let script = try String(contentsOf: packageRoot.appendingPathComponent("Scripts/build_release.sh"))
        XCTAssertTrue(script.contains("for localization_dir in Resources/*.lproj"))
        XCTAssertTrue(script.contains("$localization.lproj/Localizable.strings"))
        XCTAssertTrue(script.contains("$localization.lproj/InfoPlist.strings"))
    }

    func testSettingsControlsKeepSemanticLabelsForVoiceOver() throws {
        let source = try String(contentsOf: packageRoot.appendingPathComponent("Sources/MacSwitch/Views.swift"))
        XCTAssertFalse(source.contains("Toggle(\"\""))
        XCTAssertFalse(source.contains("Picker(\"\""))
        XCTAssertTrue(source.contains("if subtitle != nil {"))
        XCTAssertTrue(source.contains(".accessibilityValue(Text(isExpanded ? \"Expanded\" : \"Collapsed\"))"))
        XCTAssertTrue(source.contains("Toggle(store.text(.startAtLogin), isOn: $store.startAtLogin)"))
        XCTAssertTrue(source.contains("Picker(store.text(.language), selection: $store.appLanguage)"))
        XCTAssertTrue(source.contains("Picker(store.text(.menuBarIcon), selection: $store.menuBarIcon)"))
        XCTAssertTrue(source.contains("accessibilityLabel: store.text(.preferences)"))
        XCTAssertTrue(source.contains(".accessibilityAction(named: Text(\"Move Up\"))"))
    }

    private var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func strings(in locale: String, named name: String) throws -> [String: String] {
        let url = packageRoot
            .appendingPathComponent("Resources")
            .appendingPathComponent("\(locale).lproj")
            .appendingPathComponent("\(name).strings")
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String]
        )
    }
}
