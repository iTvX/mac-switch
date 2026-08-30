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
