import Foundation
import XCTest

final class PackageSmokeTests: XCTestCase {
    func testSafeSelfTestExecutablePasses() throws {
        let executable = try macSwitchExecutable()
        let result = try run(executable.path, ["--self-test-safe"], timeout: 20)

        XCTAssertEqual(result.status, 0, result.combinedOutput)
        XCTAssertTrue(result.output.contains("Result: PASS"), result.combinedOutput)
        XCTAssertTrue(result.output.contains("Start at Login diagnostic includes backend"), result.combinedOutput)
        XCTAssertTrue(result.output.contains("Start at Login diagnostic includes registration status"), result.combinedOutput)
        XCTAssertTrue(result.output.contains("Start at Login diagnostic includes launch agent schema"), result.combinedOutput)
        XCTAssertTrue(result.output.contains("Start at Login diagnostic includes current app match"), result.combinedOutput)
        XCTAssertTrue(result.output.contains("Screen Cleaning exits on mouse down"), result.combinedOutput)
        XCTAssertTrue(result.output.contains("Screen Cleaning exits if the event tap is disabled"), result.combinedOutput)
        XCTAssertTrue(result.output.contains("shortcut validation accepts Command-Option shortcuts"), result.combinedOutput)
        XCTAssertTrue(result.output.contains("shortcut validation rejects Command-A"), result.combinedOutput)
        XCTAssertTrue(result.output.contains("shortcut validation rejects reserved keys"), result.combinedOutput)
        XCTAssertTrue(result.output.contains("Eject Disk asks for confirmation by default"), result.combinedOutput)
        XCTAssertTrue(result.output.contains("Eject Disk exclusion matching works without writing preferences"), result.combinedOutput)
        XCTAssertTrue(result.output.contains("Play Music: skipped in safe self-test to avoid Automation prompts"), result.combinedOutput)
        XCTAssertFalse(result.combinedOutput.contains(NSHomeDirectory()), "safe self-test output should redact the current user's home path")
    }

    func testUISmokeModeOpensPreferencesWindow() throws {
        let executable = try macSwitchExecutable()
        let result = try run(executable.path, ["--ui-smoke-test"], timeout: 12)

        XCTAssertEqual(result.status, 0, result.combinedOutput)
        XCTAssertTrue(result.output.contains("Preferences window exists"), result.combinedOutput)
        XCTAssertTrue(result.output.contains("Preferences window is onscreen"), result.combinedOutput)
        XCTAssertTrue(result.output.contains("Result: PASS"), result.combinedOutput)
    }

    func testDashboardSmokeModeOpensDashboardWindow() throws {
        let executable = try macSwitchExecutable()
        let result = try run(executable.path, ["--dashboard-smoke-test"], timeout: 12)

        XCTAssertEqual(result.status, 0, result.combinedOutput)
        XCTAssertTrue(result.output.contains("Dashboard window exists"), result.combinedOutput)
        XCTAssertTrue(result.output.contains("Dashboard window is onscreen"), result.combinedOutput)
        XCTAssertTrue(result.output.contains("Dashboard window size is"), result.combinedOutput)
        XCTAssertTrue(result.output.contains("Result: PASS"), result.combinedOutput)
    }

    func testDashboardUsesAdaptiveNativePopoverLayout() throws {
        let appDelegate = try String(contentsOf: packageRoot.appendingPathComponent("Sources/MacSwitch/AppDelegate.swift"))
        let views = try String(contentsOf: packageRoot.appendingPathComponent("Sources/MacSwitch/Views.swift"))
        let dashboardSource = try extract(
            views,
            from: "struct DashboardView",
            to: "private struct EmptyDashboardView"
        )
        let footerSource = try extract(
            views,
            from: "private struct FooterBar",
            to: "private struct CompactIconButton"
        )
        let backdropSource = try extract(
            views,
            from: "private struct DashboardBackdrop",
            to: "private struct DashboardBandBackground"
        )
        let headerSource = try extract(
            views,
            from: "private struct DashboardHeader",
            to: "private struct ControlRow"
        )
        let controlRowSource = try extract(
            views,
            from: "private struct ControlRow",
            to: "private struct SwitchGlyph"
        )
        let reorderRowSource = try extract(
            views,
            from: "private struct DashboardReorderRow",
            to: "private struct DashboardDropPlacement"
        )
        let dragModifierSource = try extract(
            views,
            from: "private struct ConditionalDragModifier",
            to: "private struct SwitchGlyph"
        )

        XCTAssertTrue(views.contains("enum DashboardLayout"))
        XCTAssertTrue(views.contains("static let minHeight: CGFloat = 278"))
        XCTAssertTrue(views.contains("static let maxHeight: CGFloat = 438"))
        XCTAssertTrue(views.contains("static let cornerRadius: CGFloat = 18"))
        XCTAssertTrue(views.contains("private struct DashboardBackdrop"))
        XCTAssertTrue(backdropSource.contains(".fill(.ultraThinMaterial)"))
        XCTAssertTrue(backdropSource.contains("RoundedRectangle(cornerRadius: DashboardLayout.cornerRadius"))
        XCTAssertTrue(dashboardSource.contains(".compositingGroup()"))
        XCTAssertTrue(dashboardSource.contains(".clipShape(RoundedRectangle(cornerRadius: DashboardLayout.cornerRadius"))
        XCTAssertFalse(backdropSource.contains("VisualEffectView("))
        XCTAssertTrue(views.contains("private struct DashboardBandBackground"))
        XCTAssertTrue(views.contains("DashboardColors.windowVeil"))
        XCTAssertTrue(views.contains("DashboardColors.glassGlow"))
        XCTAssertTrue(views.contains("DashboardColors.highlight"))
        XCTAssertTrue(views.contains(".toggleStyle(.switch)"))
        XCTAssertTrue(footerSource.contains("DashboardFooterButton"))
        XCTAssertTrue(footerSource.contains("DashboardBandBackground(placement: .footer)"))
        XCTAssertFalse(footerSource.contains(".background(DashboardColors.footerFill)"))
        XCTAssertFalse(footerSource.contains("CompactIconButton(symbol: \"gearshape\")"))
        XCTAssertFalse(footerSource.contains(".frame(maxWidth: .infinity)"))
        XCTAssertFalse(footerSource.contains(".buttonStyle(.bordered)"))
        XCTAssertTrue(headerSource.contains("CompactIconButton(symbol: \"gearshape\")"))
        XCTAssertFalse(headerSource.contains("CompactIconButton(symbol: \"arrow.clockwise\""))
        XCTAssertFalse(headerSource.contains("store.refreshVisibleAsync()"))
        XCTAssertTrue(dashboardSource.contains("@State private var dashboardDragging: SwitchKind?"))
        XCTAssertTrue(dashboardSource.contains("@State private var dashboardDropPlacement: DashboardDropPlacement?"))
        XCTAssertTrue(dashboardSource.contains("dragProvider: {"))
        XCTAssertTrue(dashboardSource.contains("dragging = kind"))
        XCTAssertTrue(dashboardSource.contains("DashboardDropSlot(isVisible: showsDropBefore)"))
        XCTAssertTrue(dashboardSource.contains("DashboardDropSlot(isVisible: showsDropAfter)"))
        XCTAssertTrue(dashboardSource.contains(".onDrop("))
        XCTAssertTrue(dashboardSource.contains("delegate: DashboardDropDelegate("))
        XCTAssertTrue(dashboardSource.contains("rowHeight: ControlRow.rowHeight(for: snapshot)"))
        XCTAssertTrue(dashboardSource.contains("topInset: showsDropBefore ? DashboardDropSlot.height : 0"))
        XCTAssertTrue(views.contains("private struct DashboardDropPlacement: Equatable"))
        XCTAssertTrue(views.contains("private struct DashboardDropSlot: View"))
        XCTAssertTrue(views.contains("private struct RowIdentityContent: View"))
        XCTAssertTrue(views.contains("private struct ConditionalDragModifier: ViewModifier"))
        XCTAssertFalse(reorderRowSource.contains(".onDrag"))
        XCTAssertTrue(dragModifierSource.contains("content.onDrag(dragProvider)"))
        XCTAssertTrue(controlRowSource.contains("RowIdentityContent("))
        XCTAssertTrue(controlRowSource.contains("let isDragging: Bool"))
        XCTAssertTrue(controlRowSource.contains("let dragProvider: (() -> NSItemProvider)?"))
        XCTAssertTrue(controlRowSource.contains("DashboardColors.rowDragFill"))
        XCTAssertTrue(controlRowSource.contains("fileprivate static func rowHeight(for snapshot: SwitchSnapshot)"))
        XCTAssertFalse(views.contains("RowOrderMenu"))
        XCTAssertFalse(views.contains("Move Up"))
        XCTAssertFalse(views.contains("Move Down"))
        XCTAssertTrue(appDelegate.contains("private var currentDashboardSize: NSSize"))
        XCTAssertTrue(appDelegate.contains("DashboardLayout.size(visibleCount: store.visibleKinds.count, showsError: store.lastError != nil)"))
        XCTAssertTrue(appDelegate.contains("window.setContentSize(size)"))
        XCTAssertTrue(appDelegate.contains("resizeVisibleDashboardKeepingTopEdge()"))
        XCTAssertFalse(appDelegate.contains("private let dashboardSize = NSSize(width: 326, height: 438)"))
        XCTAssertFalse(views.contains("PaletteToggleStyle"))
        XCTAssertTrue(views.contains("private struct DashboardBandBackground"))
        XCTAssertTrue(views.contains("LinearGradient("))
    }

    func testPreferencesWindowIsResizableAndScreenClamped() throws {
        let appDelegate = try String(contentsOf: packageRoot.appendingPathComponent("Sources/MacSwitch/AppDelegate.swift"))
        let views = try String(contentsOf: packageRoot.appendingPathComponent("Sources/MacSwitch/Views.swift"))

        XCTAssertTrue(appDelegate.contains("styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView]"))
        XCTAssertFalse(appDelegate.contains(".miniaturizable, .resizable"))
        XCTAssertTrue(appDelegate.contains("window.titleVisibility = .hidden"))
        XCTAssertTrue(appDelegate.contains("window.titlebarAppearsTransparent = true"))
        XCTAssertTrue(appDelegate.contains("window.toolbarStyle = .unified"))
        XCTAssertTrue(appDelegate.contains("window.isMovableByWindowBackground = true"))
        XCTAssertTrue(appDelegate.contains("window.isOpaque = false"))
        XCTAssertTrue(appDelegate.contains("window.backgroundColor = .clear"))
        XCTAssertTrue(appDelegate.contains("private static var openCustomizeOnLaunch"))
        XCTAssertTrue(appDelegate.contains("CommandLine.arguments.contains(\"--open-customize\")"))
        XCTAssertTrue(appDelegate.contains("store.preferredPreferencesTab = \"customize\""))
        XCTAssertTrue(appDelegate.contains("uiRegressionMode || preferencesSmokeMode || dashboardSmokeMode || openPreferencesOnLaunch || openCustomizeOnLaunch"))
        XCTAssertTrue(appDelegate.contains("private let preferencesCompactContentSize = NSSize(width: 580, height: 440)"))
        XCTAssertTrue(appDelegate.contains("private let preferencesExpandedContentSize = NSSize(width: 980, height: 460)"))
        XCTAssertTrue(appDelegate.contains("name: .setMacSwitchPreferencesLayout"))
        XCTAssertTrue(appDelegate.contains("private func resizePreferencesWindow(layoutMode: PreferencesLayoutMode, animate: Bool)"))
        XCTAssertTrue(appDelegate.contains("private func preferencesContentSize(for layoutMode: PreferencesLayoutMode) -> NSSize"))
        XCTAssertTrue(appDelegate.contains("return store.preferredCustomizeKind == nil ? .compact : .detail"))
        XCTAssertFalse(appDelegate.contains("preferencesCustomizeContentSize"))
        XCTAssertTrue(appDelegate.contains("window.setFrame(frame, display: true, animate: animate)"))
        XCTAssertTrue(appDelegate.contains("window.minSize = NSSize(width: 540, height: 390)"))
        XCTAssertTrue(appDelegate.contains("frame.size.width = min(frame.width, visibleFrame.width)"))
        XCTAssertTrue(appDelegate.contains("frame.size.height = min(frame.height, visibleFrame.height)"))
        XCTAssertTrue(appDelegate.contains("window.setFrame(frame, display: true)"))
        XCTAssertTrue(views.contains(".frame(minWidth: 540, minHeight: 390)"))
        XCTAssertTrue(views.contains(".frame(width: 132)"))
        XCTAssertTrue(views.contains(".frame(maxWidth: .infinity, maxHeight: .infinity)"))
        XCTAssertTrue(views.contains("VisualEffectView(material: .hudWindow"))
        XCTAssertTrue(views.contains("VisualEffectView(material: .sidebar"))
        XCTAssertTrue(views.contains("static let titlebarInset: CGFloat = 14"))
        XCTAssertTrue(views.contains("private struct GlassCardModifier"))
        XCTAssertTrue(views.contains("@State private var isExpanded = false"))
        XCTAssertTrue(views.contains("@State private var isExpanded = true"))
        XCTAssertTrue(views.contains("init(_ title: String, defaultExpanded: Bool = true"))
        XCTAssertTrue(views.contains("SettingsGroup(store.text(.permissions), defaultExpanded: true)"))
        XCTAssertTrue(views.contains("withAnimation(.snappy(duration: 0.18))"))
        XCTAssertFalse(appDelegate.contains("window.minSize = NSSize(width: 900, height: 560)"))
        XCTAssertFalse(views.contains(".frame(minWidth: 900, minHeight: 560)"))
        XCTAssertFalse(views.contains(".frame(minWidth: 600, minHeight: 390)"))
        XCTAssertFalse(views.contains(".frame(width: 940, height: 640)"))
    }

    func testMenuBarIconSelectionUsesPublishedValueImmediately() throws {
        let appDelegate = try String(contentsOf: packageRoot.appendingPathComponent("Sources/MacSwitch/AppDelegate.swift"))
        let model = try String(contentsOf: packageRoot.appendingPathComponent("Sources/MacSwitch/Model.swift"))
        let views = try String(contentsOf: packageRoot.appendingPathComponent("Sources/MacSwitch/Views.swift"))
        let menuBarIconSource = try extract(model, from: "enum MenuBarIcon", to: "struct SwitchSnapshot")

        XCTAssertTrue(appDelegate.contains(".sink { [weak self] icon in self?.updateStatusIcon(icon) }"))
        XCTAssertTrue(appDelegate.contains("private func updateStatusIcon(_ icon: MenuBarIcon)"))
        XCTAssertTrue(appDelegate.contains("let image = icon.templateImage()"))
        XCTAssertTrue(menuBarIconSource.contains("func templateImage(size: NSSize = NSSize(width: 18, height: 18)) -> NSImage"))
        XCTAssertTrue(menuBarIconSource.contains("image.isTemplate = true"))
        XCTAssertTrue(views.contains("Image(nsImage: icon.templateImage(size: NSSize(width: 17, height: 17)))"))
        XCTAssertTrue(menuBarIconSource.contains("case .power: return \"Pulse\""))
        XCTAssertTrue(menuBarIconSource.contains("case .command: return \"Orbit\""))
        XCTAssertTrue(menuBarIconSource.contains("case .sliders: return \"Balance\""))
        XCTAssertFalse(menuBarIconSource.contains("return \"Power\""))
        XCTAssertFalse(menuBarIconSource.contains("return \"Command\""))
        XCTAssertFalse(menuBarIconSource.contains("return \"Sliders\""))
        XCTAssertFalse(menuBarIconSource.contains("var symbolName: String"))
        XCTAssertFalse(views.contains("Label(icon.title, systemImage: icon.symbolName)"))
        XCTAssertFalse(appDelegate.contains("NSImage(systemSymbolName: icon.symbolName"))
        XCTAssertFalse(appDelegate.contains(".sink { [weak self] _ in self?.updateStatusIcon() }"))
        XCTAssertFalse(appDelegate.contains("NSImage(systemSymbolName: store.menuBarIcon.symbolName"))
    }

    func testLanguageSelectionSupportsCommonLanguages() throws {
        let localization = try String(contentsOf: packageRoot.appendingPathComponent("Sources/MacSwitch/Localization.swift"))
        let model = try String(contentsOf: packageRoot.appendingPathComponent("Sources/MacSwitch/Model.swift"))
        let views = try String(contentsOf: packageRoot.appendingPathComponent("Sources/MacSwitch/Views.swift"))
        let generalPreferencesSource = try extract(
            views,
            from: "private struct GeneralPreferencesView",
            to: "private struct AboutPreferencesView"
        )

        XCTAssertTrue(localization.contains("case system"))
        XCTAssertTrue(localization.contains("case simplifiedChinese"))
        XCTAssertTrue(localization.contains("case traditionalChinese"))
        XCTAssertTrue(localization.contains("case spanish"))
        XCTAssertTrue(localization.contains("case japanese"))
        XCTAssertTrue(localization.contains("case korean"))
        XCTAssertTrue(localization.contains("case german"))
        XCTAssertTrue(localization.contains("case french"))
        XCTAssertTrue(localization.contains("case italian"))
        XCTAssertTrue(localization.contains("case portuguese"))
        XCTAssertTrue(localization.contains("static var preferredSystemLanguage"))
        XCTAssertTrue(localization.contains("Locale.preferredLanguages"))
        XCTAssertTrue(localization.contains("return .traditionalChinese"))
        XCTAssertTrue(localization.contains("return .simplifiedChinese"))
        XCTAssertTrue(localization.contains(".followSystem: \"跟随系统\""))
        XCTAssertTrue(localization.contains(".followSystem: \"システムに合わせる\""))
        XCTAssertTrue(localization.contains(".followSystem: \"시스템 따르기\""))
        XCTAssertTrue(localization.contains(".followSystem: \"System folgen\""))

        XCTAssertTrue(model.contains("@Published var appLanguage: AppLanguage"))
        XCTAssertTrue(model.contains("DefaultsKey.appLanguage"))
        XCTAssertTrue(model.contains("appLanguage = languageRaw.flatMap(AppLanguage.init(rawValue:)) ?? .system"))
        XCTAssertTrue(model.contains("func text(_ key: L10nKey) -> String"))
        XCTAssertTrue(model.contains("func switchTitle(_ kind: SwitchKind) -> String"))

        XCTAssertTrue(generalPreferencesSource.contains("SettingsGroup(store.text(.language))"))
        XCTAssertTrue(generalPreferencesSource.contains("Picker(\"\", selection: $store.appLanguage)"))
        XCTAssertTrue(generalPreferencesSource.contains("ForEach(AppLanguage.allCases)"))
        XCTAssertTrue(generalPreferencesSource.contains("Text(language.pickerTitle(in: store.effectiveLanguage)).tag(language)"))
        XCTAssertTrue(generalPreferencesSource.contains("Text(store.menuBarIconTitle(icon))"))
        XCTAssertTrue(views.contains(".environment(\\.locale, Locale(identifier: store.effectiveLanguage.localeIdentifier))"))
        XCTAssertTrue(views.contains("L10n.controlsReady(store.visibleKinds.count, language: store.effectiveLanguage)"))
        XCTAssertTrue(views.contains("store.switchTitle(lhs).localizedStandardCompare(store.switchTitle(rhs))"))
        XCTAssertTrue(views.contains("Text(store.switchTitle(kind))"))
    }

    func testInfoPlistHasShippingMetadataAndPermissions() throws {
        let plistURL = packageRoot.appendingPathComponent("Resources/Info.plist")
        let data = try Data(contentsOf: plistURL)
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )

        XCTAssertEqual(plist["CFBundleIdentifier"] as? String, "com.maxyu.macswitch")
        XCTAssertEqual(plist["CFBundleExecutable"] as? String, "MacSwitch")
        XCTAssertEqual(plist["LSUIElement"] as? Bool, true)
        XCTAssertEqual(plist["LSApplicationCategoryType"] as? String, "public.app-category.utilities")
        XCTAssertEqual(plist["LSMinimumSystemVersion"] as? String, "14.0")
        XCTAssertEqual(plist["NSHumanReadableCopyright"] as? String, "Copyright © 2026 Mac Switch contributors")
        XCTAssertNil(plist["SUFeedURL"], "release feed URL should be injected at build time")
        XCTAssertNil(plist["SUPublicEDKey"], "Sparkle public key should be injected at build time")
        XCTAssertNil(plist["MacSwitchFeedbackURL"], "feedback URL should be injected at build time")

        let requiredUsageKeys = [
            "NSAppleEventsUsageDescription",
            "NSBluetoothAlwaysUsageDescription",
            "NSInputMonitoringUsageDescription",
            "NSLocationWhenInUseUsageDescription"
        ]
        for key in requiredUsageKeys {
            let value = plist[key] as? String
            XCTAssertFalse(value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true, "\(key) should be present")
        }
    }

    func testSourceAvailableLicenseRestrictsCommercialUseAndForkDistribution() throws {
        let license = try String(contentsOf: packageRoot.appendingPathComponent("LICENSE"))
        let readme = try String(contentsOf: packageRoot.appendingPathComponent("README.md"))

        XCTAssertTrue(license.contains("Mac Switch Source Available License 1.0"))
        XCTAssertTrue(license.contains("not an\nOpen Source Initiative approved open source license"))
        XCTAssertTrue(license.contains("Use the Software for Commercial Use."))
        XCTAssertTrue(license.contains("prior written permission from the Copyright Holder"))
        XCTAssertTrue(license.contains("Publish, release, maintain, promote, or distribute a fork"))
        XCTAssertTrue(license.contains("app store submission"))
        XCTAssertTrue(license.contains("binary release"))
        XCTAssertTrue(license.contains("update feed"))
        XCTAssertTrue(license.contains("this license does not grant permission to publish, release, promote, distribute,\nor commercialize any fork or derivative version"))

        XCTAssertTrue(readme.contains("source-available under the Mac Switch Source Available License"))
        XCTAssertTrue(readme.contains("published for transparency and review"))
        XCTAssertTrue(readme.contains("Commercial use, redistribution, binary releases"))
        XCTAssertTrue(readme.contains("publishing forked or rebranded versions"))
        XCTAssertTrue(readme.contains("operating an update feed require prior written permission"))

        let permissiveLicenseName = ascii([77, 73, 84, 32, 76, 105, 99, 101, 110, 115, 101])
        let permissiveGrantPhrase = ascii([80, 101, 114, 109, 105, 115, 115, 105, 111, 110, 32, 105, 115, 32, 104, 101, 114, 101, 98, 121, 32, 103, 114, 97, 110, 116, 101, 100])
        XCTAssertFalse(license.contains(permissiveLicenseName))
        XCTAssertFalse(readme.contains(permissiveLicenseName))
        XCTAssertFalse(license.contains(permissiveGrantPhrase))
    }

    func testReleaseScriptKeepsSigningNotaryAndArchiveGuards() throws {
        let script = try String(contentsOf: packageRoot.appendingPathComponent("Scripts/build_release.sh"))
        let readinessScriptURL = packageRoot.appendingPathComponent("Scripts/check_release_ready.sh")
        let readinessScript = try String(contentsOf: readinessScriptURL)
        let readme = try String(contentsOf: packageRoot.appendingPathComponent("README.md"))
        let releaseWorkflow = try String(contentsOf: packageRoot.appendingPathComponent(".github/workflows/release.yml"))
        let privateCiPrefix = ascii([83, 65, 89, 76, 69, 84, 95])
        let privateCiName = ascii([115, 97, 121, 108, 101, 116])
        let oldNotaryProfile = ascii([109, 97, 99, 45, 115, 119, 105, 116, 99, 104, 45, 99, 108, 101, 97, 110, 45, 110, 111, 116, 97, 114, 121])

        XCTAssertTrue(releaseWorkflow.contains("branches:\n      - main"), "release workflow should run automatically after PR merges to main")
        XCTAssertFalse(releaseWorkflow.contains("environment: release"), "release workflow should not wait for manual environment approval")
        XCTAssertTrue(releaseWorkflow.contains("CFBundleShortVersionString"), "automatic release tags should use the app short version")
        XCTAssertTrue(releaseWorkflow.contains("echo \"create_tag=$create_tag\" >> \"$GITHUB_OUTPUT\""), "automatic releases should record whether the tag is generated")
        XCTAssertTrue(releaseWorkflow.contains("Publish generated release tag"), "automatic release tags should only be published after the app bundle is verified")
        XCTAssertTrue(releaseWorkflow.contains("if: steps.release_tag.outputs.create_tag == 'true'"), "manual releases should not recreate existing tags")
        XCTAssertTrue(releaseWorkflow.contains("git tag \"$RELEASE_TAG\" \"$GITHUB_SHA\""), "automatic release should tag the merged main commit")
        XCTAssertTrue(releaseWorkflow.contains("git push origin \"refs/tags/$RELEASE_TAG\""), "automatic release should publish the generated tag")
        XCTAssertTrue(releaseWorkflow.contains("default_branch=\"${GITHUB_DEFAULT_BRANCH:-main}\""))
        XCTAssertTrue(releaseWorkflow.contains("Release tag $tag must point to a commit reachable from $default_branch"))
        XCTAssertTrue(script.contains("Developer ID Application:"), "release script should auto-detect Developer ID identities")
        XCTAssertTrue(script.contains("SIGN_IDENTITY"), "release script should support explicit signing identity overrides")
        XCTAssertFalse(script.contains(privateCiPrefix), "release script should not expose project-specific private CI variables")
        XCTAssertTrue(script.contains("security unlock-keychain"), "release script should unlock the login keychain when a password is supplied")
        XCTAssertTrue(script.contains("NOTARY_KEYCHAIN=\"${NOTARY_KEYCHAIN:-}\""), "release script should use notarytool's default keychain unless explicitly overridden")
        XCTAssertTrue(script.contains("set-key-partition-list"), "release script should allow codesign to use the unlocked key")
        XCTAssertTrue(script.contains("--options runtime"), "release signing should use hardened runtime")
        XCTAssertTrue(script.contains("--entitlements"), "release signing should apply entitlements")
        XCTAssertTrue(script.contains("--self-test-safe"), "release build should run safe diagnostics")
        XCTAssertTrue(script.contains("--ui-smoke-test"), "release build should expose optional UI smoke diagnostics")
        XCTAssertTrue(script.contains("--dashboard-smoke-test"), "release build should expose optional dashboard smoke diagnostics")
        XCTAssertTrue(script.contains("notarytool submit"), "release script should support notarization")
        XCTAssertTrue(script.contains("NOTARY_APPLE_ID"), "release script should detect direct Apple ID notarization credentials")
        XCTAssertTrue(script.contains("NOTARY_TEAM_ID"), "release script should detect direct team ID notarization credentials")
        XCTAssertTrue(script.contains("NOTARY_PASSWORD"), "release script should detect app-specific notarization passwords")
        XCTAssertTrue(script.contains("Direct Apple ID notarization environment variables are no longer supported"), "release script should reject direct Apple ID notarization credentials")
        XCTAssertFalse(script.contains("--apple-id"), "release script should not pass direct Apple ID credentials to notarytool")
        XCTAssertTrue(script.contains("--output-format json"), "release script should save structured notarization results")
        XCTAssertTrue(script.contains("\"Accepted\""), "release script should require an accepted notarization result")
        XCTAssertTrue(script.contains("stapler staple"), "release script should staple notarized apps")
        XCTAssertTrue(script.contains("SKIP_NOTARIZATION=\"${SKIP_NOTARIZATION:-0}\""))
        XCTAssertTrue(script.contains("REQUIRE_NOTARIZATION=\"${REQUIRE_NOTARIZATION:-1}\""))
        XCTAssertTrue(script.contains("Notarization is required for release builds"))
        XCTAssertTrue(script.contains("For local non-distribution builds only, rerun with SKIP_NOTARIZATION=1."))
        XCTAssertTrue(script.contains("Notary submission skipped because SKIP_NOTARIZATION=1. This build is for local testing only."))
        XCTAssertTrue(script.contains("DEFAULT_NOTARY_PROFILE=\"${DEFAULT_NOTARY_PROFILE:-mac-switch-notary}\""))
        XCTAssertTrue(script.contains("--keychain \"$NOTARY_KEYCHAIN\""), "release script should support explicit notary keychain overrides")
        XCTAssertTrue(script.contains("notary_profile_setup_hint"), "release script should show the matching store-credentials command")
        XCTAssertTrue(script.contains("SU_FEED_URL"))
        XCTAssertTrue(script.contains("SPARKLE_PUBLIC_KEY"))
        XCTAssertTrue(script.contains("MacSwitchFeedbackURL"))
        XCTAssertTrue(script.contains("ditto -c -k --sequesterRsrc --keepParent"), "release script should create notarization-safe archives")
        XCTAssertTrue(script.contains("ditto -x -k"), "release script should verify the zip archive contents")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: readinessScriptURL.path), "release readiness script should be executable")
        XCTAssertTrue(readinessScript.contains("codesign --verify"), "release readiness should verify the signature")
        XCTAssertTrue(readinessScript.contains("spctl --assess"), "release readiness should fail if Gatekeeper rejects the app")
        XCTAssertTrue(readinessScript.contains("stapler validate"), "release readiness should require a notarization staple")
        XCTAssertTrue(readinessScript.contains("DEFAULT_NOTARY_PROFILE=\"${DEFAULT_NOTARY_PROFILE:-mac-switch-notary}\""))
        XCTAssertTrue(readinessScript.contains("NOTARY_KEYCHAIN=\"${NOTARY_KEYCHAIN:-}\""), "release readiness should use notarytool's default keychain unless explicitly overridden")
        XCTAssertFalse(readinessScript.contains(privateCiPrefix), "release readiness should not expose project-specific private CI variables")
        XCTAssertTrue(readinessScript.contains("notarytool history"), "release readiness should verify notary credentials")
        XCTAssertTrue(readinessScript.contains("ditto -x -k"), "release readiness should verify the archive contents")
        XCTAssertTrue(readme.contains("not as a public build or redistribution guide"))
        XCTAssertTrue(readme.contains("Official downloads are published through the repository's GitHub Releases"))
        XCTAssertFalse(readme.contains("./Scripts/build_release.sh"))
        XCTAssertFalse(readme.contains("./Scripts/check_release_ready.sh"))
        XCTAssertFalse(readme.contains("Notarization is required by default"))
        XCTAssertFalse(readme.contains("SKIP_NOTARIZATION=1"))
        XCTAssertFalse(script.contains(oldNotaryProfile))
        XCTAssertFalse(readinessScript.contains(oldNotaryProfile))
        XCTAssertFalse(readme.contains(oldNotaryProfile))
        XCTAssertTrue(readme.contains("Trademark Notice"))
        XCTAssertTrue(readme.contains("not affiliated with or endorsed by Apple Inc."))
        XCTAssertFalse(readme.contains(privateCiPrefix))
        XCTAssertFalse(readme.localizedCaseInsensitiveContains(privateCiName))
    }

    func testSparkleUpdateFlowIsBundledSignedAndPublished() throws {
        let package = try String(contentsOf: packageRoot.appendingPathComponent("Package.swift"))
        let appDelegate = try String(contentsOf: packageRoot.appendingPathComponent("Sources/MacSwitch/AppDelegate.swift"))
        let manager = try String(contentsOf: packageRoot.appendingPathComponent("Sources/MacSwitch/SoftwareUpdateManager.swift"))
        let views = try String(contentsOf: packageRoot.appendingPathComponent("Sources/MacSwitch/Views.swift"))
        let generalPreferencesSource = try extract(
            views,
            from: "private struct GeneralPreferencesView",
            to: "private enum AppLinks"
        )
        let aboutPreferencesSource = try extract(
            views,
            from: "private struct AboutPreferencesView",
            to: "private struct CustomizePreferencesView"
        )
        let buildScript = try String(contentsOf: packageRoot.appendingPathComponent("Scripts/build_release.sh"))
        let appcastScriptURL = packageRoot.appendingPathComponent("Scripts/generate_appcast.sh")
        let appcastScript = try String(contentsOf: appcastScriptURL)
        let publishScriptURL = packageRoot.appendingPathComponent("Scripts/publish_appcast.sh")
        let publishScript = try String(contentsOf: publishScriptURL)

        XCTAssertTrue(package.contains("https://github.com/sparkle-project/Sparkle"))
        XCTAssertTrue(package.contains(".product(name: \"Sparkle\", package: \"Sparkle\")"))
        XCTAssertTrue(manager.contains("import Sparkle"))
        XCTAssertTrue(manager.contains("SPUStandardUpdaterController"))
        XCTAssertTrue(manager.contains("SPUUpdaterDelegate"))
        XCTAssertTrue(manager.contains("Bundle.main.object(forInfoDictionaryKey: \"SUFeedURL\")"))
        XCTAssertTrue(manager.contains("updaterDelegate: self"))
        XCTAssertTrue(manager.contains("didFinishUpdateCycleFor"))
        XCTAssertTrue(manager.contains("didAbortWithError"))
        XCTAssertTrue(manager.contains("observe(updater: controller.updater)"))
        XCTAssertTrue(manager.contains("updater.observe(\\.canCheckForUpdates"))
        XCTAssertTrue(manager.contains("updater.observe(\\.automaticallyChecksForUpdates"))
        XCTAssertTrue(appDelegate.contains("SoftwareUpdateManager.shared"))
        XCTAssertTrue(appDelegate.contains("softwareUpdates.start()"))
        XCTAssertFalse(generalPreferencesSource.contains("SettingsGroup(\"Updates\")"))
        XCTAssertFalse(generalPreferencesSource.contains("softwareUpdates"))
        XCTAssertTrue(aboutPreferencesSource.contains("SettingsGroup(\"Updates\")"))
        XCTAssertTrue(aboutPreferencesSource.contains("subtitle: updateCheckSubtitle"))
        XCTAssertTrue(aboutPreferencesSource.contains("softwareUpdates.checkForUpdates()"))
        XCTAssertTrue(aboutPreferencesSource.contains("automaticallyChecksForUpdates"))
        XCTAssertTrue(aboutPreferencesSource.contains("automaticallyDownloadsUpdates"))
        XCTAssertFalse(aboutPreferencesSource.contains("Periodically check the official release feed for new versions."))
        XCTAssertFalse(aboutPreferencesSource.contains("Download available updates automatically after a scheduled check."))

        XCTAssertTrue(buildScript.contains("Contents/Frameworks"))
        XCTAssertTrue(buildScript.contains("Sparkle.framework"))
        XCTAssertTrue(buildScript.contains("install_name_tool -add_rpath \"@executable_path/../Frameworks\""))
        XCTAssertTrue(buildScript.contains("XPCServices/Downloader.xpc"))
        XCTAssertTrue(buildScript.contains("XPCServices/Installer.xpc"))
        XCTAssertTrue(buildScript.contains("Updater.app"))
        XCTAssertTrue(buildScript.contains("Autoupdate"))
        XCTAssertTrue(buildScript.contains("BUILD_NUMBER=\"${BUILD_NUMBER:-$(date -u +%Y%m%d%H%M%S)}\""))
        XCTAssertTrue(buildScript.contains("Set :CFBundleVersion $BUILD_NUMBER"))
        XCTAssertTrue(buildScript.contains("test -d \"$VERIFY_DIR/$APP_NAME.app/Contents/Frameworks/Sparkle.framework\""))

        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: appcastScriptURL.path))
        XCTAssertTrue(appcastScript.contains("SPARKLE_ACCOUNT=\"${SPARKLE_ACCOUNT:-com.maxyu.macswitch.sparkle}\""))
        XCTAssertTrue(appcastScript.contains("SPARKLE_PRIVATE_KEY"))
        XCTAssertTrue(appcastScript.contains("SPARKLE_PRIVATE_KEY environment signing is no longer supported"))
        XCTAssertFalse(appcastScript.contains("--ed-key-file -"))
        XCTAssertTrue(appcastScript.contains("--account \"$SPARKLE_ACCOUNT\""))
        XCTAssertTrue(appcastScript.contains("generate_appcast"))
        XCTAssertTrue(appcastScript.contains("GITHUB_REPOSITORY"))
        XCTAssertTrue(appcastScript.contains("https://github.com/$GITHUB_REPOSITORY/releases/download/$RELEASE_TAG/"))
        XCTAssertTrue(appcastScript.contains("Mac.Switch.zip"))

        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: publishScriptURL.path))
        XCTAssertTrue(publishScript.contains("APPCAST_RELEASE_TAG=\"${APPCAST_RELEASE_TAG:-appcast}\""))
        XCTAssertTrue(publishScript.contains("APPCAST_PUBLIC_URL"))
        XCTAssertTrue(publishScript.contains("GITHUB_REPOSITORY"))
        XCTAssertTrue(publishScript.contains("APPCAST_VERIFY_ATTEMPTS"))
        XCTAssertTrue(publishScript.contains("expected_appcast_version"))
        XCTAssertTrue(publishScript.contains("expected_enclosure_url"))
        XCTAssertTrue(publishScript.contains("gh release upload \"$APPCAST_RELEASE_TAG\" \"$APPCAST_PATH\" --clobber"))
        XCTAssertTrue(publishScript.contains("curl -fsSL"))
        XCTAssertTrue(publishScript.contains("Public appcast did not match generated appcast"))
    }

    func testSourceAvailableTreeDoesNotExposePrivateOrCompetitorReferences() throws {
        let binaryAssetExtensions = [".gif", ".icns", ".jpg", ".jpeg", ".pdf", ".png"]
        let gitFilesResult = try run("/usr/bin/git", ["ls-files"], timeout: 5)
        let listedFiles = gitFilesResult.status == 0
            ? gitFilesResult.output.split(separator: "\n").map(String.init)
            : []
        let trackedFiles = try (listedFiles.isEmpty ? sourceAvailableFilesForAudit() : listedFiles)
            .filter { path in
                !binaryAssetExtensions.contains(where: path.hasSuffix)
                    && FileManager.default.fileExists(atPath: packageRoot.appendingPathComponent(path).path)
            }
        XCTAssertFalse(trackedFiles.isEmpty, "source availability audit should scan local files even before git is initialized")
        let forbiddenProductName = ascii([79, 110, 101, 32, 83, 119, 105, 116, 99, 104])
        let forbiddenProductNameJoined = ascii([79, 110, 101, 83, 119, 105, 116, 99, 104])
        let caseSensitiveForbiddenPatterns = [
            forbiddenProductName,
            forbiddenProductNameJoined,
            ascii([79, 78, 69, 95, 83, 87, 73, 84, 67, 72]),
            ascii([111, 110, 101, 115, 119, 105, 116, 99, 104]),
            ascii([72, 101, 97, 100, 112, 104, 111, 110, 101, 115, 32, 67, 111, 110, 110, 101, 99, 116])
        ]
        let caseSensitiveForbiddenRegexes = [
            "\\b" + ascii([83, 99, 114, 101, 101, 110, 32, 67, 108, 101, 97, 110]) + "\\b"
        ]
        let caseInsensitiveForbiddenPatterns = [
            ascii([102, 105, 114, 101, 98, 97, 108, 108]),
            ascii([83, 65, 89, 76, 69, 84, 95]),
            ascii([115, 97, 121, 108, 101, 116]),
            ascii([105, 84, 118, 88]),
            ascii([109, 97, 99, 45, 115, 119, 105, 116, 99, 104, 45, 99, 108, 101, 97, 110]),
            ascii([97, 112, 112, 46, 109, 97, 99, 115, 119, 105, 116, 99, 104])
        ]
        let caseInsensitiveForbiddenRegexes = [
            ["/Users", "[^\\s\"']+"].joined(separator: "/")
        ]

        for path in trackedFiles {
            let source = try String(contentsOf: packageRoot.appendingPathComponent(path))
            for pattern in caseSensitiveForbiddenPatterns {
                XCTAssertFalse(
                    source.contains(pattern),
                    "\(path) should not contain private or competitor reference: \(pattern)"
                )
            }
            for pattern in caseSensitiveForbiddenRegexes {
                XCTAssertNil(
                    source.range(of: pattern, options: .regularExpression),
                    "\(path) should not contain private or competitor reference matching regex: \(pattern)"
                )
            }
            for pattern in caseInsensitiveForbiddenPatterns {
                XCTAssertFalse(
                    source.localizedCaseInsensitiveContains(pattern),
                    "\(path) should not contain private or competitor reference: \(pattern)"
                )
            }
            for pattern in caseInsensitiveForbiddenRegexes {
                XCTAssertNil(
                    source.range(of: pattern, options: [.regularExpression, .caseInsensitive]),
                    "\(path) should not contain private or competitor reference matching regex: \(pattern)"
                )
            }
        }

        XCTAssertFalse(trackedFiles.contains("Docs/\(ascii([79, 78, 69, 95, 83, 87, 73, 84, 67, 72]))_FEATURE_MATRIX.md"))
        XCTAssertFalse(trackedFiles.contains("Sources/MacSwitch/\(forbiddenProductNameJoined)ParitySwitches.swift"))
    }

    func testStartupPathsAvoidBlockingLoginAndPowerDiagnostics() throws {
        let model = try String(contentsOf: packageRoot.appendingPathComponent("Sources/MacSwitch/Model.swift"))
        let switches = try String(contentsOf: packageRoot.appendingPathComponent("Sources/MacSwitch/SystemSwitches.swift"))
        let modelInitSource = try extract(
            model,
            from: "init(controller: SystemSwitchController = SystemSwitchController())",
            to: "controller.onExternalChange ="
        )

        XCTAssertTrue(model.contains("@Published private(set) var startAtLoginNeedsRepair = false"))
        XCTAssertTrue(model.contains("@Published private(set) var startAtLoginNeedsApproval = false"))
        XCTAssertFalse(
            model.contains("@Published private(set) var startAtLoginNeedsRepair = LoginItemManager.needsRepair"),
            "SwitchStore initialization should not synchronously run launchctl diagnostics"
        )
        XCTAssertTrue(model.contains("refreshStartAtLoginStatusAsync()"))
        XCTAssertTrue(
            modelInitSource.contains("startAtLogin = LoginItemManager.initialIsEnabled"),
            "SwitchStore initialization should use a non-blocking Start at Login estimate before async verification"
        )
        XCTAssertFalse(
            modelInitSource.contains("startAtLogin = LoginItemManager.isEnabled"),
            "SwitchStore initialization should not synchronously run launchctl through LoginItemManager.isEnabled"
        )
        XCTAssertTrue(switches.contains("static var initialIsEnabled: Bool"))
        XCTAssertTrue(
            switches.contains("DispatchQueue.global(qos: .utility).async"),
            "managed disable-sleep restoration should not block app startup"
        )
        XCTAssertTrue(
            switches.contains("guard isConfiguredForCurrentApp, isServiceLoaded else"),
            "Start at Login enable should verify both the plist and loaded launch service"
        )
        XCTAssertTrue(
            switches.contains("return configuredProgramArguments == expectedProgramArguments && launchAgentPlistIsCurrent"),
            "Start at Login should not treat stale launch agent plist schemas as fully repaired"
        )
    }

    func testStartAtLoginApprovalAndRepairAreShownAsDifferentStates() throws {
        let model = try String(contentsOf: packageRoot.appendingPathComponent("Sources/MacSwitch/Model.swift"))
        let switches = try String(contentsOf: packageRoot.appendingPathComponent("Sources/MacSwitch/SystemSwitches.swift"))
        let views = try String(contentsOf: packageRoot.appendingPathComponent("Sources/MacSwitch/Views.swift"))
        let generalPreferencesSource = try extract(
            views,
            from: "private struct GeneralPreferencesView",
            to: "private enum AppLinks"
        )
        let errorRouterSource = try extract(
            views,
            from: "private enum ErrorFixRouter",
            to: "private extension SwitchKind"
        )

        XCTAssertTrue(switches.contains("static var needsUserApproval: Bool"))
        XCTAssertTrue(switches.contains("usesServiceManagement && serviceManagementStatusRequiresApproval"))
        XCTAssertTrue(model.contains("startAtLoginNeedsApproval = LoginItemManager.needsUserApproval"))
        XCTAssertTrue(model.contains("Start at Login failed: \\(failure)"))
        XCTAssertTrue(generalPreferencesSource.contains("store.startAtLoginNeedsApproval"))
        XCTAssertTrue(generalPreferencesSource.contains("store.isUpdatingStartAtLogin || store.startAtLoginNeedsApproval"))
        XCTAssertTrue(generalPreferencesSource.contains("startAtLoginPillText"))
        XCTAssertTrue(generalPreferencesSource.contains("startAtLoginPillColor"))
        XCTAssertTrue(generalPreferencesSource.contains("store.text(.approve)"))
        XCTAssertFalse(generalPreferencesSource.contains("Pending approval in Login Items"))
        XCTAssertTrue(generalPreferencesSource.contains("return store.text(.pending)"))
        XCTAssertFalse(generalPreferencesSource.contains("The login item points at another copy or an old service"))
        XCTAssertFalse(generalPreferencesSource.contains("Enabled for this copy of Mac Switch."))
        XCTAssertFalse(generalPreferencesSource.contains("Off. Enable it to open Mac Switch automatically after you sign in."))
        XCTAssertFalse(generalPreferencesSource.contains("Choose the symbol shown in the macOS menu bar."))
        XCTAssertFalse(generalPreferencesSource.contains("Stop the app and remove the menu bar icon until you open it again."))
        XCTAssertTrue(errorRouterSource.contains("Open Login Items"))
        XCTAssertTrue(errorRouterSource.contains("SystemSettingsLinks.openLoginItems()"))
        XCTAssertTrue(errorRouterSource.contains("store.refreshStartAtLoginStatusAsync()"))
    }

    func testStartAtLoginUsesModernServiceAndMigratesLegacyAgent() throws {
        let package = try String(contentsOf: packageRoot.appendingPathComponent("Package.swift"))
        let switches = try String(contentsOf: packageRoot.appendingPathComponent("Sources/MacSwitch/SystemSwitches.swift"))
        let loginItemSource = try extract(
            switches,
            from: "enum LoginItemManager",
            to: "}\n}\n"
        )
        let serviceManagementSetSource = try extract(
            switches,
            from: "private static func setServiceManagementEnabled",
            to: "private static func setLaunchAgentEnabled"
        )

        XCTAssertTrue(package.contains(".linkedFramework(\"ServiceManagement\")"))
        XCTAssertTrue(switches.contains("import ServiceManagement"))
        XCTAssertTrue(loginItemSource.contains("Bundle.main.bundleURL.pathExtension == \"app\" && !serviceManagementStatusIsNotFound"))
        XCTAssertTrue(loginItemSource.contains("static var initialIsEnabled: Bool"))
        XCTAssertTrue(loginItemSource.contains("private static var serviceManagementStatusIsNotFound"))
        XCTAssertTrue(loginItemSource.contains("if serviceManagementStatusIsEnabled"))
        XCTAssertFalse(loginItemSource.contains("case .enabled, .requiresApproval:\n            return true"))
        XCTAssertTrue(loginItemSource.contains("SMAppService.mainApp.register()"))
        XCTAssertTrue(loginItemSource.contains("SMAppService.mainApp.unregister()"))
        XCTAssertTrue(loginItemSource.contains("removeLegacyLaunchAgentIfPresent()"))
        XCTAssertTrue(loginItemSource.contains("bootstrapWithLoadedServiceRecovery()"))
        XCTAssertTrue(loginItemSource.contains("isAlreadyLoaded(result)"))
        XCTAssertTrue(loginItemSource.contains("launchAgentPlistIsCurrent"))
        XCTAssertTrue(loginItemSource.contains("plist[\"LimitLoadToSessionType\"] as? String == \"Aqua\""))
        XCTAssertTrue(loginItemSource.contains("configuredProgramArguments != nil || launchAgentServiceLoaded"))
        XCTAssertTrue(loginItemSource.contains("backend="))
        XCTAssertTrue(loginItemSource.contains("status="))
        XCTAssertTrue(loginItemSource.contains("schema="))
        XCTAssertTrue(serviceManagementSetSource.range(of: "try SMAppService.mainApp.register()")!.lowerBound < serviceManagementSetSource.range(of: "try removeLegacyLaunchAgentIfPresent()")!.lowerBound)
    }

    func testFeedbackLinksOpenGitHubIssues() throws {
        let views = try String(contentsOf: packageRoot.appendingPathComponent("Sources/MacSwitch/Views.swift"))
        let generalPreferencesSource = try extract(
            views,
            from: "private struct GeneralPreferencesView",
            to: "private enum AppLinks"
        )
        let appLinksSource = try extract(
            views,
            from: "private enum AppLinks",
            to: "private enum AppDiagnostics"
        )
        let aboutPreferencesSource = try extract(
            views,
            from: "private struct AboutPreferencesView",
            to: "private struct CustomizePreferencesView"
        )

        XCTAssertTrue(appLinksSource.contains("MacSwitchFeedbackURL"))
        XCTAssertFalse(appLinksSource.contains("mailto:"))
        XCTAssertFalse(appLinksSource.contains("https://github.com/"))
        XCTAssertFalse(generalPreferencesSource.contains("SettingsGroup(\"Support\")"))
        XCTAssertFalse(generalPreferencesSource.contains("AppLinks.feedback"))
        XCTAssertFalse(generalPreferencesSource.contains("Copy Diagnostics"))
        XCTAssertTrue(aboutPreferencesSource.contains("File a bug report or feature request on GitHub."))
        XCTAssertTrue(aboutPreferencesSource.contains("Could not open GitHub issues."))
        XCTAssertTrue(aboutPreferencesSource.contains("Feedback URL is not configured for this build."))
        XCTAssertTrue(aboutPreferencesSource.contains("Label(\"Issue\", systemImage: \"exclamationmark.bubble\")"))
        XCTAssertFalse(views.contains("Could not open your default email app."))
    }

    func testDurationStatusCopyIsReadable() throws {
        let model = try String(contentsOf: packageRoot.appendingPathComponent("Sources/MacSwitch/Model.swift"))
        let switches = try String(contentsOf: packageRoot.appendingPathComponent("Sources/MacSwitch/SystemSwitches.swift"))

        XCTAssertTrue(model.contains("case .indefinitely: return \"Activate indefinitely\""))
        XCTAssertTrue(model.contains("case .tomorrow: return \"Activate until tomorrow\""))
        XCTAssertTrue(switches.contains("return \"Active indefinitely\""))
        XCTAssertTrue(switches.contains("return \"Active until \\(timeDisplay(for: endDate))\""))
        XCTAssertFalse(model.contains("Activate for indefinitely"))
        XCTAssertFalse(switches.contains("Activate for indefinitely"))
        XCTAssertFalse(switches.contains("Activate till"))
    }

    func testTerminationCleansPersistentSystemState() throws {
        let appDelegate = try String(contentsOf: packageRoot.appendingPathComponent("Sources/MacSwitch/AppDelegate.swift"))
        let model = try String(contentsOf: packageRoot.appendingPathComponent("Sources/MacSwitch/Model.swift"))
        let switches = try String(contentsOf: packageRoot.appendingPathComponent("Sources/MacSwitch/SystemSwitches.swift"))
        let terminateSource = try extract(
            appDelegate,
            from: "func applicationWillTerminate",
            to: "func windowWillClose"
        )
        let storeTerminationSource = try extract(
            model,
            from: "func prepareForTermination()",
            to: "private func runXcodeClean()"
        )
        let controllerTerminationSource = try extract(
            switches,
            from: "func prepareForTermination()",
            to: "}\n\nprivate final class KeepAwakeManager"
        )

        XCTAssertTrue(terminateSource.contains("store.prepareForTermination()"))
        XCTAssertTrue(storeTerminationSource.contains("timer?.invalidate()"))
        XCTAssertTrue(storeTerminationSource.contains("controller.prepareForTermination()"))
        XCTAssertTrue(controllerTerminationSource.contains("keepAwake.setEnabled(false"))
        XCTAssertTrue(controllerTerminationSource.contains("keyboardLocker.setEnabled(false)"))
        XCTAssertTrue(controllerTerminationSource.contains("screenCleaner.setEnabled(false)"))
    }

    func testHiddenStatefulSwitchesAreRemovedOnlyAfterSuccessfulDeactivation() throws {
        let model = try String(contentsOf: packageRoot.appendingPathComponent("Sources/MacSwitch/Model.swift"))
        let views = try String(contentsOf: packageRoot.appendingPathComponent("Sources/MacSwitch/Views.swift"))
        let customizeToggleSource = try extract(
            model,
            from: "func setEnabled(_ kind: SwitchKind, _ enabled: Bool)",
            to: "func move(_ source: SwitchKind, before target: SwitchKind)"
        )
        let resetSource = try extract(
            model,
            from: "func resetCustomization()",
            to: "func clearLastError()"
        )
        let deactivateSource = try extract(
            model,
            from: "private func prepareToHideKind",
            to: "func requestDarkModeLocation()"
        )
        let applySetSource = try extract(
            model,
            from: "private func applySetResult",
            to: "@discardableResult\n    private func ensureSwitchAvailable"
        )
        let toggleSource = try extract(
            model,
            from: "func toggle(_ kind: SwitchKind)",
            to: "func trigger(_ kind: SwitchKind)"
        )
        let customizeRowSource = try extract(
            views,
            from: "private struct CustomizeRow",
            to: "private struct SwitchPreferencePanel"
        )
        let switchPanelSource = try extract(
            views,
            from: "private struct SwitchPreferencePanel",
            to: "private struct BluetoothAudioPreferencesPanel"
        )

        XCTAssertTrue(model.contains("private var pendingHideAfterDeactivation: Set<SwitchKind> = []"))
        XCTAssertTrue(model.contains("func isCustomizationBusy(_ kind: SwitchKind) -> Bool"))
        XCTAssertTrue(model.contains("var hasBusyActions: Bool"))
        XCTAssertTrue(model.contains("func customizationStatusText(for kind: SwitchKind) -> String"))
        XCTAssertTrue(model.contains("Turning off before hiding"))
        XCTAssertTrue(model.contains("private enum HidePreparationResult"))
        XCTAssertTrue(model.contains("case readyToHide"))
        XCTAssertTrue(model.contains("case waitingForDeactivation"))
        XCTAssertTrue(model.contains("case blocked"))
        XCTAssertTrue(customizeToggleSource.contains("pendingHideAfterDeactivation.remove(kind)"))
        XCTAssertTrue(customizeToggleSource.range(of: "pendingHideAfterDeactivation.remove(kind)")!.lowerBound < customizeToggleSource.range(of: "enabledKinds.insert(kind)")!.lowerBound)
        XCTAssertTrue(customizeToggleSource.contains("prepareToHideKind(kind)"))
        XCTAssertTrue(customizeToggleSource.contains("pendingHideAfterDeactivation.insert(kind)"))
        XCTAssertTrue(customizeToggleSource.contains("case .blocked"))
        XCTAssertTrue(customizeToggleSource.contains("case .readyToHide"))
        XCTAssertTrue(resetSource.contains("prepareToHideKind(kind)"))
        XCTAssertTrue(resetSource.contains("guard !hasBusyActions else"))
        XCTAssertTrue(resetSource.contains("Finish the current switch update before restoring defaults."))
        XCTAssertTrue(resetSource.contains("pendingHideAfterDeactivation.subtract(defaultEnabledKinds)"))
        XCTAssertTrue(resetSource.range(of: "pendingHideAfterDeactivation.subtract(defaultEnabledKinds)")!.lowerBound < resetSource.range(of: "for kind in enabledKinds.subtracting(defaultEnabledKinds)")!.lowerBound)
        XCTAssertTrue(resetSource.contains("enabledKinds.formUnion(defaultEnabledKinds)"))
        XCTAssertTrue(resetSource.contains("clearLastErrorIfCustomizationOwned()"))
        XCTAssertFalse(customizeToggleSource.contains("lastError = nil"))
        XCTAssertFalse(resetSource.contains("lastError = nil"))
        XCTAssertTrue(deactivateSource.contains("!kind.isMomentaryAction"))
        XCTAssertTrue(deactivateSource.contains("guard !isActionBusy(kind) else"))
        XCTAssertTrue(views.contains(".disabled(store.hasBusyActions)"))
        XCTAssertTrue(deactivateSource.contains("snapshots[kind]?.isOn == true"))
        XCTAssertTrue(deactivateSource.contains("set(kind, enabled: false)"))
        XCTAssertTrue(deactivateSource.contains("return snapshots[kind]?.isOn == true ? .blocked : .readyToHide"))
        XCTAssertTrue(applySetSource.contains("completePendingHideAfterDeactivation(for: kind, enabled: enabled, error: result.error)"))
        XCTAssertTrue(toggleSource.contains("guard !pendingHideAfterDeactivation.contains(kind) else { return }"))
        XCTAssertTrue(deactivateSource.contains("guard error == nil else { return }"))
        XCTAssertTrue(deactivateSource.contains("if !enabled"))
        XCTAssertTrue(deactivateSource.contains("prepareToHideKind(kind)"))
        XCTAssertTrue(deactivateSource.contains("pendingHideAfterDeactivation.insert(kind)"))
        XCTAssertTrue(deactivateSource.contains("hideKindFromDashboard(kind)"))
        XCTAssertTrue(model.contains("private func canHideKindFromDashboard(_ kind: SwitchKind) -> Bool"))
        XCTAssertTrue(model.contains("let effectiveVisible = enabledKinds.subtracting(pendingHideAfterDeactivation)"))
        XCTAssertTrue(customizeToggleSource.contains("canHideKindFromDashboard(kind)"))
        XCTAssertTrue(customizeRowSource.contains("let isEnabled: Bool"))
        XCTAssertTrue(customizeRowSource.contains("let isBusy: Bool"))
        XCTAssertTrue(customizeRowSource.contains("let statusText: String"))
        XCTAssertTrue(customizeRowSource.contains(".disabled(isBusy)"))
        XCTAssertTrue(customizeRowSource.contains("Text(statusText)"))
        XCTAssertFalse(customizeRowSource.contains("@ObservedObject var store"))
        XCTAssertFalse(customizeRowSource.contains(".onHover"))
        XCTAssertTrue(switchPanelSource.contains("store.isCustomizationBusy(kind)"))
        XCTAssertTrue(switchPanelSource.contains("? \"Updating\""))
    }

    func testCustomizationOrderIsDeduplicatedAndPersistedStably() throws {
        let model = try String(contentsOf: packageRoot.appendingPathComponent("Sources/MacSwitch/Model.swift"))
        let visibleSource = try extract(
            model,
            from: "var visibleKinds: [SwitchKind]",
            to: "init(controller:"
        )
        let initSource = try extract(
            model,
            from: "init(controller:",
            to: "for kind in SwitchKind.allCases"
        )
        let moveSource = try extract(
            model,
            from: "func move(_ source: SwitchKind, before target: SwitchKind)",
            to: "func resetCustomization()"
        )
        let saveSource = try extract(
            model,
            from: "private func saveOrder()",
            to: "private func updateDoNotDisturbExpiration"
        )
        let helpersSource = try extract(
            model,
            from: "private static func loadShortcuts",
            to: "private static func migratedEnabledKindsIfNeeded"
        )

        XCTAssertTrue(visibleSource.contains("Self.normalizedOrder(orderedKinds).filter { enabledKinds.contains($0) }"))
        XCTAssertTrue(initSource.contains("let storedUnique = Self.deduplicatedKinds(storedOrder)"))
        XCTAssertTrue(initSource.contains("let storedSet = Set(storedUnique)"))
        XCTAssertTrue(initSource.contains("orderedKinds = storedUnique + missing"))
        XCTAssertTrue(initSource.contains("saveOrder()"))
        XCTAssertTrue(initSource.contains("saveEnabledKinds()"))
        XCTAssertTrue(moveSource.contains("orderedKinds = Self.normalizedOrder(updated)"))
        XCTAssertTrue(model.contains("func move(_ source: SwitchKind, after target: SwitchKind)"))
        XCTAssertTrue(model.contains("let adjustedIndex = min(from < to ? to : to + 1, updated.count)"))
        XCTAssertFalse(model.contains("func moveVisible(_ kind: SwitchKind, up: Bool)"))
        XCTAssertTrue(saveSource.contains("Self.normalizedOrder(orderedKinds).map(\\.rawValue)"))
        XCTAssertTrue(saveSource.contains("let orderedEnabled = Self.normalizedOrder(orderedKinds).filter { enabledKinds.contains($0) }"))
        XCTAssertTrue(saveSource.contains("orderedEnabled.map(\\.rawValue)"))
        XCTAssertTrue(helpersSource.contains("private static func deduplicatedKinds(_ kinds: [SwitchKind]) -> [SwitchKind]"))
        XCTAssertTrue(helpersSource.contains("private static func normalizedOrder("))
        XCTAssertTrue(helpersSource.contains("return unique + defaultOrder.filter { !present.contains($0) }"))
    }

    func testCustomizeListIsSortedAndDoesNotSupportPreferenceDrag() throws {
        let views = try String(contentsOf: packageRoot.appendingPathComponent("Sources/MacSwitch/Views.swift"))
        let customizeSource = try extract(
            views,
            from: "private struct CustomizePreferencesView",
            to: "private struct CustomizeRow"
        )
        let rowSource = try extract(
            views,
            from: "private struct CustomizeRow",
            to: "private struct SwitchPreferencePanel"
        )

        XCTAssertTrue(views.contains("fileprivate static let rowHeight: CGFloat = 46"))
        XCTAssertTrue(customizeSource.contains("private var sortedKinds: [SwitchKind]"))
        XCTAssertTrue(customizeSource.contains("let lhsEnabled = store.enabledKinds.contains(lhs)"))
        XCTAssertTrue(customizeSource.contains("if lhsEnabled != rhsEnabled"))
        XCTAssertTrue(customizeSource.contains("store.switchTitle(lhs).localizedStandardCompare(store.switchTitle(rhs))"))
        XCTAssertTrue(customizeSource.contains("ForEach(sortedKinds)"))
        XCTAssertTrue(customizeSource.contains("Drag items in the menu bar menu to change order."))
        XCTAssertFalse(customizeSource.contains("This list is sorted A-Z"))
        XCTAssertFalse(customizeSource.contains(".onDrag"))
        XCTAssertFalse(customizeSource.contains(".onDrop"))
        XCTAssertFalse(views.contains("private struct SwitchDropDelegate"))
        XCTAssertFalse(rowSource.contains("line.3.horizontal"))
        XCTAssertTrue(rowSource.contains("chevron.right"))
    }

    func testDashboardDragDropPreviewsLandingSlotBeforeMoving() throws {
        let views = try String(contentsOf: packageRoot.appendingPathComponent("Sources/MacSwitch/Views.swift"))
        let dashboardDropDelegateSource = try extract(
            views,
            from: "private struct DashboardDropDelegate",
            to: "struct ScreenCleanOverlayView"
        )
        let placementUpdateSource = try extract(
            dashboardDropDelegateSource,
            from: "private func updatePlacement",
            to: "private func position"
        )

        XCTAssertTrue(views.contains("static let height: CGFloat = 18"))
        XCTAssertTrue(dashboardDropDelegateSource.contains("@Binding var placement: DashboardDropPlacement?"))
        XCTAssertTrue(dashboardDropDelegateSource.contains("return DropProposal(operation: .move)"))
        XCTAssertTrue(dashboardDropDelegateSource.contains("placement = next"))
        XCTAssertTrue(dashboardDropDelegateSource.contains("return rowY > rowHeight / 2 ? .after : .before"))
        XCTAssertTrue(dashboardDropDelegateSource.contains("store.move(source, before: target.item)"))
        XCTAssertTrue(dashboardDropDelegateSource.contains("store.move(source, after: target.item)"))
        XCTAssertTrue(dashboardDropDelegateSource.contains("withAnimation(.spring(response: 0.24, dampingFraction: 0.86))"))
        XCTAssertFalse(placementUpdateSource.contains("store.move("))
    }

    func testPublicRefreshAPIsDoNotSynchronouslySnapshotSystemState() throws {
        let model = try String(contentsOf: packageRoot.appendingPathComponent("Sources/MacSwitch/Model.swift"))
        let refreshSource = try extract(
            model,
            from: "func refresh(_ kind: SwitchKind)",
            to: "func refreshVisibleAsync()"
        )

        XCTAssertTrue(refreshSource.contains("refreshAsync(kind)"))
        XCTAssertTrue(refreshSource.contains("refreshAllAsync()"))
        XCTAssertFalse(
            refreshSource.contains("controller.snapshot"),
            "public refresh entry points should not synchronously poll system state"
        )
    }

    func testRefreshInvalidationIsScopedPerSwitch() throws {
        let model = try String(contentsOf: packageRoot.appendingPathComponent("Sources/MacSwitch/Model.swift"))
        let refreshSource = try extract(
            model,
            from: "private func refreshAsync(kinds: [SwitchKind])",
            to: "func requestDarkModeLocation()"
        )

        XCTAssertTrue(model.contains("private var snapshotVersions: [SwitchKind: Int] = [:]"))
        XCTAssertTrue(model.contains("private var scheduledFollowUpRefreshes: Set<SwitchKind> = []"))
        XCTAssertTrue(model.contains("invalidatePendingSnapshot(for: kind)"))
        XCTAssertTrue(refreshSource.contains("let requestedVersions = Dictionary"))
        XCTAssertTrue(refreshSource.contains("snapshotVersions[kind, default: 0] == requestedVersions[kind, default: 0]"))
        XCTAssertTrue(refreshSource.contains("clearAvailabilityErrorIfResolved(for: kind, snapshot: decorated)"))
        XCTAssertTrue(model.contains("private func clearAvailabilityErrorIfResolved(for kind: SwitchKind, snapshot: SwitchSnapshot)"))
        XCTAssertTrue(model.contains("lastError?.hasPrefix(\"\\(kind.title) is not available:\") == true"))
        XCTAssertTrue(refreshSource.contains("scheduleFollowUpRefreshIfNeeded(for: kind, snapshot: decorated)"))
        XCTAssertTrue(refreshSource.contains("snapshot.subtitle?.contains(\"Calculating\") == true"))
        XCTAssertTrue(refreshSource.contains("DispatchQueue.main.asyncAfter(deadline: .now() + 1.5"))
        XCTAssertFalse(
            model.contains("refreshGeneration"),
            "refresh invalidation should not discard unrelated switch snapshots"
        )
    }

    func testResourceActionsRefreshAvailabilityBeforeConfirmation() throws {
        let model = try String(contentsOf: packageRoot.appendingPathComponent("Sources/MacSwitch/Model.swift"))
        let actionSafetySource = try extract(
            model,
            from: "enum ActionSafetyPreferences",
            to: "final class SwitchStore"
        )
        let triggerSource = try extract(
            model,
            from: "func trigger(_ kind: SwitchKind)",
            to: "private func confirmActionIfNeeded"
        )
        let preflightSource = try extract(
            model,
            from: "private func preflightTrigger",
            to: "private func confirmActionIfNeeded"
        )
        let refreshSource = try extract(
            model,
            from: "private func refreshAsync(kinds: [SwitchKind])",
            to: "private func finishRefreshCycle"
        )
        let confirmationSource = try extract(
            model,
            from: "private func confirmActionIfNeeded",
            to: "func setShortcut"
        )
        let freshAvailabilitySource = try extract(
            model,
            from: "var requiresFreshAvailabilityBeforeAction: Bool",
            to: "var executingSubtitle: String?"
        )

        XCTAssertTrue(model.contains("@Published private(set) var actionsPreparing: Set<SwitchKind> = []"))
        XCTAssertTrue(model.contains("func isActionBusy(_ kind: SwitchKind) -> Bool"))
        XCTAssertTrue(triggerSource.contains("guard !isActionBusy(kind) else { return }"))
        XCTAssertTrue(triggerSource.contains("ActionSafetyPreferences.confirmationRequired(for: kind)"))
        XCTAssertTrue(triggerSource.contains("actionsPreparing.insert(kind)\n            let confirmed = confirmActionIfNeeded(kind)"))
        XCTAssertTrue(triggerSource.contains("actionsPreparing.remove(kind)\n            guard confirmed else { return }"))
        XCTAssertTrue(triggerSource.contains("kind.requiresFreshAvailabilityBeforeAction"))
        XCTAssertFalse(triggerSource.contains("kind.requiresFreshAvailabilityBeforeAction && !kind.snapshotRequiresMainThread"))
        XCTAssertTrue(triggerSource.contains("preflightTrigger(kind)"))
        XCTAssertTrue(preflightSource.contains("actionsPreparing.insert(kind)"))
        XCTAssertTrue(preflightSource.contains("if kind.snapshotRequiresMainThread"))
        XCTAssertTrue(preflightSource.contains("DispatchQueue.main.async"))
        XCTAssertTrue(preflightSource.contains("actionQueue.async"))
        XCTAssertTrue(preflightSource.contains("controller.snapshot(for: kind"))
        XCTAssertTrue(preflightSource.contains("finishPreflightTrigger(kind, snapshot: snapshot)"))
        XCTAssertTrue(preflightSource.contains("private func finishPreflightTrigger"))
        XCTAssertTrue(preflightSource.contains("actionsPreparing.remove(kind)"))
        XCTAssertTrue(preflightSource.contains("runConfirmedTrigger(kind)"))
        XCTAssertTrue(preflightSource.contains("guard confirmActionIfNeeded(kind) else"))
        XCTAssertTrue(preflightSource.range(of: "guard confirmActionIfNeeded(kind) else")!.lowerBound < preflightSource.range(of: "actionsPreparing.remove(kind)\n        runConfirmedTrigger(kind)")!.lowerBound)
        XCTAssertTrue(confirmationSource.contains("NSApp.activate(ignoringOtherApps: true)"))
        XCTAssertTrue(confirmationSource.contains("NSImage(systemSymbolName: kind.symbolName"))
        XCTAssertTrue(refreshSource.contains("!isActionBusy($0)"))
        XCTAssertTrue(actionSafetySource.contains("confirmationMessage(for kind: SwitchKind, snapshot: SwitchSnapshot? = nil)"))
        XCTAssertTrue(confirmationSource.contains("confirmationMessage(for: kind, snapshot: snapshots[kind])"))
        XCTAssertFalse(actionSafetySource.contains("TrashPreferences.itemCount"))
        XCTAssertFalse(actionSafetySource.contains("PasteboardPreferences.itemCount"))
        XCTAssertFalse(actionSafetySource.contains("EjectDiskPreferences.ejectableVolumes.count"))
        for raw in [".displaySleep", ".emptyTrash", ".ejectDisk", ".emptyPasteboard", ".hideWindows"] {
            XCTAssertTrue(freshAvailabilitySource.contains(raw), "\(raw) should refresh current availability before confirmation")
        }
    }

    func testPowerModeActionsAreSerializedAndRefreshTogether() throws {
        let model = try String(contentsOf: packageRoot.appendingPathComponent("Sources/MacSwitch/Model.swift"))
        let busySource = try extract(
            model,
            from: "func isActionBusy(_ kind: SwitchKind)",
            to: "func isCustomizationBusy"
        )
        let setSource = try extract(
            model,
            from: "func set(_ kind: SwitchKind, enabled: Bool)",
            to: "private func applySetResult"
        )
        let refreshSource = try extract(
            model,
            from: "private func refreshAsync(kinds: [SwitchKind])",
            to: "private func invalidatePendingSnapshot"
        )
        let postActionRefreshSource = try extract(
            model,
            from: "private func schedulePostActionRefresh",
            to: "private static func xcodeCleaningSubtitle"
        )

        XCTAssertTrue(model.contains("private func conflictingActionKinds(for kind: SwitchKind) -> Set<SwitchKind>"))
        XCTAssertTrue(model.contains("case .lowPowerMode:\n            return [.energyMode]"))
        XCTAssertTrue(model.contains("case .energyMode:\n            return [.lowPowerMode]"))
        XCTAssertTrue(busySource.contains("conflictingActionKinds(for: kind).contains"))
        XCTAssertTrue(setSource.contains("guard !isActionBusy(kind) else { return }"))
        XCTAssertTrue(refreshSource.contains("Set(kinds.filter { !isActionBusy($0) })"))
        XCTAssertTrue(refreshSource.contains("where !self.isActionBusy(kind)"))
        XCTAssertTrue(postActionRefreshSource.contains("var kinds: Set<SwitchKind> = [kind]"))
        XCTAssertTrue(postActionRefreshSource.contains("kinds.formUnion(conflictingActionKinds(for: kind))"))
        XCTAssertTrue(postActionRefreshSource.contains("refreshAsync(kinds: Array(kinds))"))
    }

    func testKeepAwakeDoesNotRunSlowPowerOperationsOnMainThread() throws {
        let model = try String(contentsOf: packageRoot.appendingPathComponent("Sources/MacSwitch/Model.swift"))
        let switches = try String(contentsOf: packageRoot.appendingPathComponent("Sources/MacSwitch/SystemSwitches.swift"))
        let views = try String(contentsOf: packageRoot.appendingPathComponent("Sources/MacSwitch/Views.swift"))
        let operationPolicy = try extract(
            model,
            from: "var operationRequiresMainThread: Bool",
            to: "var snapshotRequiresMainThread: Bool"
        )
        let snapshotPolicy = try extract(
            model,
            from: "var snapshotRequiresMainThread: Bool",
            to: "var requiresFreshAvailabilityBeforeAction"
        )
        let keepAwakeSource = try extract(
            switches,
            from: "private final class KeepAwakeManager",
            to: "enum KeepAwakePreferences"
        )

        XCTAssertFalse(
            operationPolicy.contains(".keepAwake"),
            "Keep Awake can invoke administrator pmset prompts and must not block the main thread"
        )
        XCTAssertTrue(snapshotPolicy.contains(".hideWindows"))
        XCTAssertTrue(keepAwakeSource.contains("DispatchWorkItem"))
        XCTAssertTrue(keepAwakeSource.contains("DispatchQueue.global(qos: .utility).asyncAfter"))
        XCTAssertTrue(keepAwakeSource.contains("!Self.isSafeSelfTest"))
        XCTAssertTrue(keepAwakeSource.contains("CommandLine.arguments.contains(\"--self-test-safe\")"))
        XCTAssertTrue(keepAwakeSource.contains("guard systemResult == kIOReturnSuccess, displayResult == kIOReturnSuccess else"))
        XCTAssertTrue(keepAwakeSource.contains("releaseAssertions(createdAssertionIDs)"))
        XCTAssertTrue(keepAwakeSource.contains("powerAssertionFailureMessage(systemResult: systemResult, displayResult: displayResult)"))
        XCTAssertTrue(switches.contains("lid-closed sleep did not change"))
        XCTAssertTrue(switches.contains("AutomationPermission.deniedMessage(for: result, target: \"System Events\")"))
        XCTAssertFalse(
            keepAwakeSource.contains("Timer.scheduledTimer"),
            "Keep Awake expiration should not depend on a run loop when actions run off the main thread"
        )

        let keepAwakePreferencesPanel = try extract(
            views,
            from: "private struct KeepAwakePreferencesPanel",
            to: "private struct DarkModePreferencesPanel"
        )
        XCTAssertTrue(keepAwakePreferencesPanel.contains("sleepStatusLoading"))
        XCTAssertTrue(keepAwakePreferencesPanel.contains("pendingSleepStatusRefresh"))
        XCTAssertTrue(keepAwakePreferencesPanel.contains("DispatchQueue.global(qos: .utility).async"))
        XCTAssertTrue(keepAwakePreferencesPanel.contains("store.refreshAsync(.keepAwake)"))
        XCTAssertFalse(
            keepAwakePreferencesPanel.contains("Timer.publish(every: 3"),
            "Keep Awake preferences should not keep polling pmset while the settings window is open"
        )
        XCTAssertFalse(
            keepAwakePreferencesPanel.contains("@State private var sleepDisabled = KeepAwakePreferences.sleepDisabled"),
            "Keep Awake preferences should not run pmset synchronously while constructing the view"
        )
        XCTAssertFalse(
            keepAwakePreferencesPanel.contains("store.refresh(.keepAwake)"),
            "Keep Awake preferences should not synchronously snapshot after preference changes"
        )
    }

    func testPreferencePanelsDoNotSynchronouslyPollPermissionsMediaOrNightShift() throws {
        let source = try String(contentsOf: packageRoot.appendingPathComponent("Sources/MacSwitch/Views.swift"))
        let generalSource = try extract(
            source,
            from: "private struct GeneralPreferencesView",
            to: "private enum AppLinks"
        )
        let nightShiftSource = try extract(
            source,
            from: "private struct NightShiftPreferencesPanel",
            to: "private struct TimeOfDayPickerRow"
        )
        let playMusicSource = try extract(
            source,
            from: "private struct PlayMusicPreferencesPanel",
            to: "private struct EjectDiskPreferencesPanel"
        )
        let accessibilitySource = try extract(
            source,
            from: "private struct AccessibilityPreferencesPanel",
            to: "private extension SwitchKind"
        )
        let energyModeSource = try extract(
            source,
            from: "private struct EnergyModePreferencesPanel",
            to: "private struct AccessibilityPreferencesPanel"
        )
        let extendedSwitches = try String(contentsOf: packageRoot.appendingPathComponent("Sources/MacSwitch/ExtendedSystemSwitches.swift"))
        let energyModePreferencesSource = try extract(
            extendedSwitches,
            from: "enum EnergyModePreferences",
            to: "struct EnergyModeSwitch"
        )
        let lowPowerSwitchSource = try extract(
            extendedSwitches,
            from: "struct LowPowerModeSwitch",
            to: "enum EnergyModeSelection"
        )
        let energyModeSwitchSource = try extract(
            extendedSwitches,
            from: "struct EnergyModeSwitch",
            to: "private enum PowerMode"
        )

        XCTAssertTrue(generalSource.contains("@State private var accessibilityTrusted = false"))
        XCTAssertTrue(generalSource.contains("isCheckingAccessibility"))
        XCTAssertTrue(generalSource.contains("pendingAccessibilityCheck"))
        XCTAssertTrue(generalSource.contains("DispatchQueue.global(qos: .utility).async"))
        XCTAssertTrue(generalSource.contains("store.refreshAsync(.screenClean)"))
        XCTAssertTrue(generalSource.contains("store.refreshAsync(.lockKeyboard)"))
        XCTAssertFalse(
            generalSource.contains("Timer.publish(every: 3"),
            "General preferences should refresh after open/user actions instead of polling while navigating settings"
        )
        XCTAssertFalse(generalSource.contains("accessibilityTrusted = AccessibilityPermission.isTrusted"))
        XCTAssertFalse(generalSource.contains("store.refresh(.screenClean)"))
        XCTAssertFalse(generalSource.contains("store.refresh(.lockKeyboard)"))

        XCTAssertTrue(nightShiftSource.contains("@State private var nightShiftSupported: Bool?"))
        XCTAssertTrue(nightShiftSource.contains("isRefreshingNightShift"))
        XCTAssertTrue(nightShiftSource.contains("pendingNightShiftRefresh"))
        XCTAssertTrue(nightShiftSource.contains("isUpdatingNightShiftSchedule"))
        XCTAssertTrue(nightShiftSource.contains("updateNightShiftAutoSchedule(value)"))
        XCTAssertTrue(nightShiftSource.contains("DispatchQueue.global(qos: .utility).async"))
        XCTAssertTrue(nightShiftSource.contains("DispatchQueue.global(qos: .userInitiated).async"))
        XCTAssertTrue(nightShiftSource.contains("store.refreshAsync(.nightShift)"))
        XCTAssertTrue(nightShiftSource.contains("store.isActionBusy(.nightShift)"))
        XCTAssertTrue(nightShiftSource.contains("guard !isUpdatingNightShiftSchedule, !store.isActionBusy(.nightShift) else { return }"))
        XCTAssertFalse(nightShiftSource.contains("@State private var autoScheduleEnabled = NightShiftPreferences.autoScheduleEnabled"))
        XCTAssertFalse(nightShiftSource.contains("if NightShiftPreferences.autoScheduleEnabled == nil"))
        XCTAssertFalse(nightShiftSource.contains("store.refresh(.nightShift)"))

        XCTAssertTrue(playMusicSource.contains("@State private var playerInfos: [PlayMusicPlayerInfo] = []"))
        XCTAssertTrue(playMusicSource.contains("isRefreshingPlayers"))
        XCTAssertTrue(playMusicSource.contains("pendingPlayersRefresh"))
        XCTAssertTrue(playMusicSource.contains("DispatchQueue.global(qos: .utility).async"))
        XCTAssertTrue(playMusicSource.contains("Timer.publish(every: 6"))
        XCTAssertFalse(playMusicSource.contains("@State private var playerInfos = PlayMusicPreferences.playerInfos"))
        XCTAssertFalse(playMusicSource.contains("return PlayMusicPreferences.launchTarget"))

        XCTAssertTrue(accessibilitySource.contains("@State private var isTrusted = false"))
        XCTAssertTrue(accessibilitySource.contains("isCheckingTrust"))
        XCTAssertTrue(accessibilitySource.contains("pendingTrustCheck"))
        XCTAssertTrue(accessibilitySource.contains("DispatchQueue.global(qos: .utility).async"))
        XCTAssertTrue(accessibilitySource.contains("store.refreshAsync(kind)"))
        XCTAssertFalse(accessibilitySource.contains("@State private var isTrusted = AccessibilityPermission.isTrusted"))
        XCTAssertFalse(accessibilitySource.contains("store.refresh(kind)"))

        XCTAssertTrue(energyModeSource.contains("@State private var selectedMode = EnergyModePreferences.storedSelection"))
        XCTAssertTrue(energyModeSource.contains("DispatchQueue.global(qos: .utility).async"))
        XCTAssertTrue(energyModeSource.contains("EnergyModePreferences.selectedMode(among: supported)"))
        XCTAssertFalse(energyModeSource.contains("@State private var selectedMode = EnergyModePreferences.selectedMode"))
        XCTAssertTrue(energyModePreferencesSource.contains("static var storedSelection: EnergyModeSelection"))
        XCTAssertTrue(energyModePreferencesSource.contains("static func selectedMode(among supported: [EnergyModeSelection])"))
        XCTAssertTrue(extendedSwitches.contains("let supportedRawValues = PowerMode.availableModes"))
        XCTAssertTrue(extendedSwitches.contains("return allCases.filter { supportedRawValues.contains($0.rawValue) }"))
        XCTAssertFalse(extendedSwitches.contains("PowerMode.availableModes.compactMap(EnergyModeSelection.init(rawValue:))"))
        XCTAssertTrue(lowPowerSwitchSource.contains("PowerMode.availableModes(current: mode).contains(1)"))
        XCTAssertTrue(energyModeSwitchSource.contains("PowerMode.availableModes(current: mode)"))
        XCTAssertTrue(lowPowerSwitchSource.contains("guard let mode = PowerMode.current else"))
        XCTAssertTrue(energyModeSwitchSource.contains("guard let mode = PowerMode.current else"))
        XCTAssertTrue(lowPowerSwitchSource.contains("guard enabled else {\n            return PowerMode.set(0)\n        }"))
        XCTAssertTrue(energyModeSwitchSource.contains("guard enabled else {\n            return PowerMode.set(0)\n        }"))
        XCTAssertFalse(lowPowerSwitchSource.contains("return PowerMode.set(enabled ? 1 : 0)"))
        XCTAssertFalse(energyModeSwitchSource.contains("return PowerMode.set(enabled ? selected.rawValue : 0)"))
        XCTAssertTrue(extendedSwitches.contains("Could not read the current power mode."))
        XCTAssertTrue(energyModeSwitchSource.contains("EnergyModePreferences.selectedMode(among: supportedSelections)"))
        let energyModeSwitchLines = energyModeSwitchSource.split(separator: "\n").map(String.init)
        XCTAssertFalse(energyModeSwitchLines.contains { line in
            line.contains("EnergyModePreferences.selectedMode") && !line.contains("selectedMode(among:")
        })
        XCTAssertTrue(extendedSwitches.contains("static func availableModes(current: Int?) -> Set<Int>"))
    }

    func testPeriodicScheduleEnforcementDoesNotPollSystemStateOnMainThread() throws {
        let model = try String(contentsOf: packageRoot.appendingPathComponent("Sources/MacSwitch/Model.swift"))
        let timerSource = try extract(
            model,
            from: "timer = Timer.scheduledTimer",
            to: "func setEnabled(_ kind: SwitchKind, _ enabled: Bool)"
        )
        let darkModeSource = try extract(
            model,
            from: "private func enforceDarkModeScheduleAsync()",
            to: "private func darkModeScheduleTarget"
        )
        let doNotDisturbSource = try extract(
            model,
            from: "private func enforceDoNotDisturbExpirationAsync()",
            to: "private func decoratedSnapshot"
        )

        XCTAssertTrue(model.contains("private var darkModeScheduleEnforcementInFlight = false"))
        XCTAssertTrue(model.contains("private var doNotDisturbExpirationEnforcementInFlight = false"))
        XCTAssertTrue(model.contains("private var doNotDisturbExpirationWorkItem: DispatchWorkItem?"))
        XCTAssertTrue(model.contains("scheduleDoNotDisturbExpirationMonitorFromDefaults()"))
        XCTAssertTrue(timerSource.contains("enforceDarkModeScheduleAsync()"))
        XCTAssertTrue(timerSource.contains("enforceDoNotDisturbExpirationAsync()"))
        XCTAssertFalse(timerSource.contains("controller.snapshot"), "periodic timer should not synchronously snapshot system state")
        XCTAssertTrue(darkModeSource.contains("refreshQueue.async"))
        XCTAssertTrue(darkModeSource.contains("controller.snapshot(for: .darkMode"))
        XCTAssertTrue(doNotDisturbSource.contains("refreshQueue.async"))
        XCTAssertTrue(doNotDisturbSource.contains("controller.snapshot(for: .doNotDisturb"))
        XCTAssertTrue(doNotDisturbSource.contains("scheduleDoNotDisturbExpirationMonitor(for: endDate)"))
        XCTAssertTrue(doNotDisturbSource.contains("scheduleDoNotDisturbExpirationMonitor(for: currentEndDate, minimumDelay: 30)"))
        XCTAssertTrue(doNotDisturbSource.contains("private func cancelDoNotDisturbExpirationMonitor()"))
        XCTAssertTrue(model.contains("defaults.removeObject(forKey: DefaultsKey.doNotDisturbEndDate)"))
        XCTAssertTrue(model.contains("cancelDoNotDisturbExpirationMonitor()"))
        XCTAssertFalse(
            doNotDisturbSource.contains("self.defaults.removeObject(forKey: DefaultsKey.doNotDisturbEndDate)\n                if snapshot.isOn"),
            "DND expiration should not be removed before a successful off shortcut run"
        )
    }

    func testDoNotDisturbExpirationRetriesThroughTemporaryShortcutFailures() throws {
        let model = try String(contentsOf: packageRoot.appendingPathComponent("Sources/MacSwitch/Model.swift"))
        let enforcementSource = try extract(
            model,
            from: "private func enforceDoNotDisturbExpirationAsync()",
            to: "private func scheduleDoNotDisturbExpirationMonitorFromDefaults"
        )
        let decorationSource = try extract(
            model,
            from: "private func decoratedDoNotDisturbSnapshot",
            to: "private func timeDisplay"
        )

        let freshSnapshotAssignment = "let decorated = self.decoratedSnapshot(snapshot, for: .doNotDisturb)\n                self.snapshots[.doNotDisturb] = decorated"
        let unavailableRetry = "guard snapshot.isAvailable else {\n                    self.scheduleDoNotDisturbExpirationMonitor(for: currentEndDate, minimumDelay: 30)\n                    return\n                }"
        XCTAssertTrue(enforcementSource.contains(freshSnapshotAssignment))
        XCTAssertTrue(enforcementSource.contains(unavailableRetry))

        guard let assignmentRange = enforcementSource.range(of: freshSnapshotAssignment),
              let retryRange = enforcementSource.range(of: unavailableRetry),
              let setRange = enforcementSource.range(of: "self.set(.doNotDisturb, enabled: false)")
        else {
            XCTFail("DND expiration enforcement should publish the fresh snapshot, retry unavailable Shortcuts, then run the off shortcut.")
            return
        }
        XCTAssertTrue(assignmentRange.lowerBound < retryRange.lowerBound)
        XCTAssertTrue(retryRange.lowerBound < setRange.lowerBound)
        XCTAssertFalse(decorationSource.contains("defaults.removeObject(forKey: DefaultsKey.doNotDisturbEndDate)"))
        XCTAssertFalse(decorationSource.contains("cancelDoNotDisturbExpirationMonitor()"))
    }

    func testResourcePreferencePanelsAvoidRepeatedSynchronousSystemReads() throws {
        let source = try String(contentsOf: packageRoot.appendingPathComponent("Sources/MacSwitch/Views.swift"))
        let extendedSwitches = try String(contentsOf: packageRoot.appendingPathComponent("Sources/MacSwitch/ExtendedSystemSwitches.swift"))
        let diagnostics = try String(contentsOf: packageRoot.appendingPathComponent("Sources/MacSwitch/RegressionDiagnostics.swift"))
        let audioSource = try extract(
            source,
            from: "private struct BluetoothAudioPreferencesPanel",
            to: "private struct RecoveryNotice"
        )
        let screenResolutionSource = try extract(
            source,
            from: "private struct ScreenResolutionPreferencesPanel",
            to: "private struct DoNotDisturbPreferencesPanel"
        )
        let playMusicSource = try extract(
            source,
            from: "private struct PlayMusicPreferencesPanel",
            to: "private struct EjectDiskPreferencesPanel"
        )
        let ejectDiskSource = try extract(
            source,
            from: "private struct EjectDiskPreferencesPanel",
            to: "private struct XcodeCleanPreferencesPanel"
        )
        let trashSource = try extract(
            source,
            from: "private struct TrashPreferencesPanel",
            to: "private struct PasteboardPreferencesPanel"
        )
        let pasteboardSource = try extract(
            source,
            from: "private struct PasteboardPreferencesPanel",
            to: "private struct HideWindowsPreferencesPanel"
        )
        let hideWindowsSource = try extract(
            source,
            from: "private struct HideWindowsPreferencesPanel",
            to: "private struct LockScreenPreferencesPanel"
        )
        let energyModeSource = try extract(
            source,
            from: "private struct EnergyModePreferencesPanel",
            to: "private struct AccessibilityPreferencesPanel"
        )
        let ejectPreferencesSource = try extract(
            extendedSwitches,
            from: "enum EjectDiskPreferences",
            to: "enum PlayMusicPlayerSelection"
        )

        XCTAssertTrue(source.contains("private func scheduleAfterSwitchActionSettles("))
        XCTAssertTrue(source.contains("store.isActionBusy(kind), remainingAttempts > 0"))

        XCTAssertTrue(audioSource.contains("@State private var devices: [BluetoothAudioDeviceOption] = []"))
        XCTAssertTrue(audioSource.contains("isRefreshingDevices"))
        XCTAssertTrue(audioSource.contains("pendingDeviceRefresh"))
        XCTAssertTrue(audioSource.contains("DispatchQueue.global(qos: .utility).async"))
        XCTAssertTrue(audioSource.contains("let latestAddress = BluetoothAudioPreferences.selectedAddress"))
        XCTAssertTrue(audioSource.contains("$0.address.caseInsensitiveCompare(normalized) == .orderedSame"))
        XCTAssertTrue(audioSource.contains("$0.address.caseInsensitiveCompare(latestAddress) == .orderedSame"))
        XCTAssertTrue(audioSource.contains(".disabled(isRefreshingDevices || store.isActionBusy(.bluetoothAudio))"))
        XCTAssertFalse(audioSource.contains("let storedAddress = BluetoothAudioPreferences.selectedAddress"))
        XCTAssertTrue(audioSource.contains("store.refreshAsync(.bluetoothAudio)"))
        XCTAssertFalse(audioSource.contains("@State private var devices = BluetoothAudioPreferences.deviceOptions"))
        XCTAssertFalse(audioSource.contains("store.refresh(.bluetoothAudio)"))
        XCTAssertTrue(extendedSwitches.contains("private static func normalizedAddress"))
        XCTAssertTrue(extendedSwitches.contains("$0.addressString.caseInsensitiveCompare(selected) == .orderedSame"))

        XCTAssertTrue(screenResolutionSource.contains("@State private var displays: [DisplayOption] = []"))
        XCTAssertTrue(screenResolutionSource.contains("@State private var currentResolutionText = \"Checking...\""))
        XCTAssertTrue(screenResolutionSource.contains("isRefreshingDisplays"))
        XCTAssertTrue(screenResolutionSource.contains("pendingDisplayRefresh"))
        XCTAssertTrue(screenResolutionSource.contains("DispatchQueue.global(qos: .utility).async"))
        XCTAssertTrue(screenResolutionSource.contains("Label(\"Display Settings\", systemImage: \"display\")"))
        XCTAssertTrue(screenResolutionSource.contains("Could not open Displays settings."))
        XCTAssertTrue(screenResolutionSource.contains("ScreenResolutionPreferences.setSelectedDisplayIndex(value, in: displays)"))
        XCTAssertTrue(screenResolutionSource.contains(".disabled(isRefreshingDisplays || store.isActionBusy(.screenResolution))"))
        XCTAssertFalse(screenResolutionSource.contains("@State private var displays = ScreenResolutionPreferences.displayOptions"))
        XCTAssertFalse(screenResolutionSource.contains("ScreenResolutionPreferences.selectedDisplayIndex = value"))
        XCTAssertFalse(screenResolutionSource.contains("private var currentResolutionText: String"))
        XCTAssertFalse(screenResolutionSource.contains("ScreenResolutionPreferences.currentModeID"))

        XCTAssertTrue(playMusicSource.contains(".disabled(isRefreshingPlayers || store.isActionBusy(.playMusic))"))
        XCTAssertTrue(playMusicSource.contains("Label(isRefreshingPlayers ? \"Checking...\" : \"Refresh Players\", systemImage: \"arrow.clockwise\")"))

        XCTAssertTrue(ejectDiskSource.contains("@State private var mountedVolumes: [EjectableVolumeOption] = []"))
        XCTAssertTrue(ejectDiskSource.contains("isRefreshingVolumes"))
        XCTAssertTrue(ejectDiskSource.contains("pendingVolumesRefresh"))
        XCTAssertTrue(ejectDiskSource.contains("DispatchQueue.global(qos: .utility).async"))
        XCTAssertTrue(ejectDiskSource.contains("Choose a removable or ejectable volume to exclude."))
        XCTAssertTrue(ejectDiskSource.contains("clearExclusionSelectionError()"))
        XCTAssertTrue(ejectDiskSource.contains("volume.isBuiltInExcluded ? \"Protected\""))
        XCTAssertTrue(ejectDiskSource.contains(".disabled(volume.isBuiltInExcluded || isRefreshingVolumes || store.isActionBusy(.ejectDisk))"))
        XCTAssertTrue(ejectDiskSource.contains(".disabled(!snapshot.isAvailable || isRefreshingVolumes || store.isActionBusy(.ejectDisk))"))
        XCTAssertTrue(ejectDiskSource.contains(".disabled(isRefreshingVolumes || store.isActionBusy(.ejectDisk))"))
        XCTAssertTrue(ejectDiskSource.contains("scheduleAfterSwitchActionSettles(store: store, kind: .ejectDisk)"))
        XCTAssertTrue(ejectDiskSource.contains("This volume is excluded by default"))
        XCTAssertFalse(ejectDiskSource.contains("private func refreshSoon()"))
        XCTAssertFalse(ejectDiskSource.contains("@State private var mountedVolumes = EjectDiskPreferences.mountedVolumeOptions"))
        XCTAssertTrue(ejectPreferencesSource.contains("@discardableResult\n    static func add(_ urls: [URL]) -> Bool"))
        XCTAssertTrue(ejectPreferencesSource.contains("normalizedExclusionPaths"))
        XCTAssertTrue(ejectPreferencesSource.contains("normalizedExclusionPath"))
        XCTAssertTrue(ejectPreferencesSource.contains("trimmingCharacters(in: .whitespacesAndNewlines)"))
        XCTAssertTrue(ejectPreferencesSource.contains("private static let builtInExcludedPathPrefixes"))
        XCTAssertTrue(ejectPreferencesSource.contains("/Library/Developer/CoreSimulator/Volumes"))
        XCTAssertTrue(ejectPreferencesSource.contains("path == prefix || path.hasPrefix(prefix + \"/\")"))
        XCTAssertTrue(ejectPreferencesSource.contains("guard !isBuiltInExcluded(URL(fileURLWithPath: normalized)) else { return nil }"))
        XCTAssertTrue(ejectPreferencesSource.contains("static func isBuiltInExcluded(_ url: URL) -> Bool"))
        XCTAssertTrue(ejectPreferencesSource.contains("static func isExcluded(_ url: URL, excludedPaths: [String]) -> Bool"))
        XCTAssertTrue(diagnostics.contains("CoreSimulator/Volumes/iOS_SelfTest"))
        XCTAssertTrue(diagnostics.contains("Eject Disk protects CoreSimulator runtime volumes by default"))
        XCTAssertTrue(ejectPreferencesSource.contains("Set(normalizedExclusionPaths(excludedPaths)).contains(path)"))
        XCTAssertTrue(ejectPreferencesSource.contains("isBuiltInExcluded: isBuiltInExcluded(standardized)"))
        XCTAssertTrue(ejectPreferencesSource.contains("urls.compactMap(exclusionPath)"))
        XCTAssertTrue(ejectPreferencesSource.contains("return mountedVolumeOptions"))
        XCTAssertTrue(ejectPreferencesSource.contains("selectedPath == path || selectedPath.hasPrefix(path + \"/\")"))
        XCTAssertFalse(ejectPreferencesSource.contains("urls.map { $0.standardizedFileURL.path }"))

        XCTAssertTrue(trashSource.contains("@State private var itemCount = 0"))
        XCTAssertTrue(trashSource.contains("isRefreshingCount"))
        XCTAssertTrue(trashSource.contains("pendingCountRefresh"))
        XCTAssertTrue(trashSource.contains("DispatchQueue.global(qos: .utility).async"))
        XCTAssertTrue(trashSource.contains("scheduleAfterSwitchActionSettles(store: store, kind: .emptyTrash)"))
        XCTAssertFalse(trashSource.contains("private func refreshCountSoon()"))
        XCTAssertFalse(trashSource.contains("private var itemCount: Int"))

        XCTAssertTrue(pasteboardSource.contains("@State private var itemCount = 0"))
        XCTAssertTrue(pasteboardSource.contains("isRefreshingCount"))
        XCTAssertTrue(pasteboardSource.contains("pendingCountRefresh"))
        XCTAssertTrue(pasteboardSource.contains("DispatchQueue.main.async"))
        XCTAssertTrue(pasteboardSource.contains("pasteboardActionTitle"))
        XCTAssertTrue(pasteboardSource.contains("store.actionsPreparing.contains(.emptyPasteboard)"))
        XCTAssertTrue(pasteboardSource.contains("scheduleAfterSwitchActionSettles(store: store, kind: .emptyPasteboard)"))
        XCTAssertFalse(pasteboardSource.contains("private func refreshCountSoon()"))
        XCTAssertFalse(pasteboardSource.contains("DispatchQueue.global(qos: .utility).async"))
        XCTAssertFalse(pasteboardSource.contains("private var itemCount: Int"))

        XCTAssertTrue(hideWindowsSource.contains("@State private var hiddenCount = 0"))
        XCTAssertTrue(hideWindowsSource.contains("@State private var hidableCount = 0"))
        XCTAssertTrue(hideWindowsSource.contains("isRefreshingCounts"))
        XCTAssertTrue(hideWindowsSource.contains("@State private var isShowingHidden = false"))
        XCTAssertTrue(hideWindowsSource.contains("pendingCountsRefresh"))
        XCTAssertTrue(hideWindowsSource.contains("DispatchQueue.main.async"))
        XCTAssertTrue(hideWindowsSource.contains("scheduleAfterSwitchActionSettles(store: store, kind: .hideWindows)"))
        XCTAssertTrue(hideWindowsSource.contains("store.refreshAsync(.hideWindows)"))
        XCTAssertTrue(hideWindowsSource.contains("private func showHiddenApps()"))
        XCTAssertFalse(hideWindowsSource.contains("DispatchQueue.global(qos: .utility).async"))
        XCTAssertFalse(hideWindowsSource.contains("DispatchQueue.global(qos: .userInitiated).async"))
        XCTAssertTrue(hideWindowsSource.contains("let result = HideWindowsPreferences.unhideAll()"))
        XCTAssertTrue(hideWindowsSource.contains("if !result.failed.isEmpty"))
        XCTAssertTrue(hideWindowsSource.contains("store.lastError = \"Could not show \\(HideWindowsPreferences.joinedAppNames(result.failed)).\""))
        XCTAssertTrue(hideWindowsSource.contains("else if store.lastError?.hasPrefix(\"Could not show \") == true"))
        XCTAssertTrue(hideWindowsSource.contains("store.clearLastError()"))
        XCTAssertFalse(hideWindowsSource.contains("private var hidableCount: Int"))

        XCTAssertTrue(energyModeSource.contains("guard !isLoadingModes else {"))
        XCTAssertTrue(energyModeSource.contains("@State private var pendingModesRefresh = false"))
        XCTAssertTrue(energyModeSource.contains("pendingModesRefresh = pendingModesRefresh || force"))
        XCTAssertTrue(energyModeSource.contains("let shouldRefreshAgain = pendingModesRefresh"))
        XCTAssertTrue(energyModeSource.contains("loadSupportedModes(force: true)"))
        XCTAssertFalse(energyModeSource.contains("guard force || !isLoadingModes else { return }"))
    }

    func testPreferenceControlsDisableConflictingActionsWhileBusy() throws {
        let source = try String(contentsOf: packageRoot.appendingPathComponent("Sources/MacSwitch/Views.swift"))
        let keepAwakeSource = try extract(
            source,
            from: "private struct KeepAwakePreferencesPanel",
            to: "private struct DarkModePreferencesPanel"
        )
        let darkModeSource = try extract(
            source,
            from: "private struct DarkModePreferencesPanel",
            to: "private struct NightShiftPreferencesPanel"
        )
        let nightShiftSource = try extract(
            source,
            from: "private struct NightShiftPreferencesPanel",
            to: "private struct TimeOfDayPickerRow"
        )
        let audioSource = try extract(
            source,
            from: "private struct BluetoothAudioPreferencesPanel",
            to: "private struct RecoveryNotice"
        )
        let screenResolutionSource = try extract(
            source,
            from: "private struct ScreenResolutionPreferencesPanel",
            to: "private struct DoNotDisturbPreferencesPanel"
        )
        let doNotDisturbSource = try extract(
            source,
            from: "private struct DoNotDisturbPreferencesPanel",
            to: "private struct ShortcutInstallRow"
        )
        let playMusicSource = try extract(
            source,
            from: "private struct PlayMusicPreferencesPanel",
            to: "private struct EjectDiskPreferencesPanel"
        )
        let ejectDiskSource = try extract(
            source,
            from: "private struct EjectDiskPreferencesPanel",
            to: "private struct XcodeCleanPreferencesPanel"
        )
        let xcodeSource = try extract(
            source,
            from: "private struct XcodeCleanPreferencesPanel",
            to: "private struct MicrophonePreferencesPanel"
        )
        let microphoneSource = try extract(
            source,
            from: "private struct MicrophonePreferencesPanel",
            to: "private struct DesktopDockPreferencesPanel"
        )
        let desktopDockSource = try extract(
            source,
            from: "private struct DesktopDockPreferencesPanel",
            to: "private struct TrashPreferencesPanel"
        )
        let trashSource = try extract(
            source,
            from: "private struct TrashPreferencesPanel",
            to: "private struct PasteboardPreferencesPanel"
        )
        let pasteboardSource = try extract(
            source,
            from: "private struct PasteboardPreferencesPanel",
            to: "private struct HideWindowsPreferencesPanel"
        )
        let hideWindowsSource = try extract(
            source,
            from: "private struct HideWindowsPreferencesPanel",
            to: "private struct LockScreenPreferencesPanel"
        )
        let lockScreenSource = try extract(
            source,
            from: "private struct LockScreenPreferencesPanel",
            to: "private struct DisplayUtilityPreferencesPanel"
        )
        let displayUtilitySource = try extract(
            source,
            from: "private struct DisplayUtilityPreferencesPanel",
            to: "private struct LowPowerModePreferencesPanel"
        )
        let lowPowerSource = try extract(
            source,
            from: "private struct LowPowerModePreferencesPanel",
            to: "private struct EnergyModePreferencesPanel"
        )
        let energyModeSource = try extract(
            source,
            from: "private struct EnergyModePreferencesPanel",
            to: "private struct AccessibilityPreferencesPanel"
        )

        XCTAssertTrue(keepAwakeSource.contains(".disabled(store.isActionBusy(.keepAwake))"))
        XCTAssertTrue(keepAwakeSource.contains(".disabled(sleepStatusLoading || store.isActionBusy(.keepAwake))"))
        XCTAssertTrue(darkModeSource.contains(".disabled(store.isActionBusy(.darkMode))"))
        XCTAssertTrue(nightShiftSource.contains(".disabled(isRefreshingNightShift || isUpdatingNightShiftSchedule || store.isActionBusy(.nightShift))"))
        XCTAssertTrue(doNotDisturbSource.contains(".disabled(store.isActionBusy(.doNotDisturb))"))
        XCTAssertTrue(doNotDisturbSource.contains(".disabled(isRefreshing || store.isActionBusy(.doNotDisturb))"))
        XCTAssertTrue(doNotDisturbSource.contains(".disabled(!allInstalled || isRefreshing || store.isActionBusy(.doNotDisturb))"))
        XCTAssertTrue(audioSource.contains(".disabled(isRefreshingDevices || store.isActionBusy(.bluetoothAudio))"))
        XCTAssertTrue(screenResolutionSource.contains(".disabled(isRefreshingDisplays || store.isActionBusy(.screenResolution))"))
        XCTAssertTrue(playMusicSource.contains(".disabled(isRefreshingPlayers || store.isActionBusy(.playMusic))"))
        XCTAssertTrue(ejectDiskSource.contains(".disabled(volume.isBuiltInExcluded || isRefreshingVolumes || store.isActionBusy(.ejectDisk))"))
        XCTAssertTrue(ejectDiskSource.contains(".disabled(!snapshot.isAvailable || isRefreshingVolumes || store.isActionBusy(.ejectDisk))"))
        XCTAssertTrue(ejectDiskSource.contains(".disabled(isRefreshingVolumes || store.isActionBusy(.ejectDisk))"))
        XCTAssertTrue(xcodeSource.contains(".disabled(store.isRefreshing || store.isActionBusy(.xcodeClean))"))
        XCTAssertTrue(microphoneSource.contains(".disabled(store.isActionBusy(.muteMicrophone))"))
        XCTAssertTrue(desktopDockSource.contains(".disabled(store.isActionBusy(kind))"))
        XCTAssertTrue(trashSource.contains(".disabled(itemCount == 0 || isRefreshingCount || store.isActionBusy(.emptyTrash))"))
        XCTAssertTrue(trashSource.contains(".disabled(isRefreshingCount || store.isActionBusy(.emptyTrash))"))
        XCTAssertTrue(pasteboardSource.contains(".disabled(itemCount == 0 || isRefreshingCount || store.isActionBusy(.emptyPasteboard))"))
        XCTAssertTrue(pasteboardSource.contains(".disabled(isRefreshingCount || store.isActionBusy(.emptyPasteboard))"))
        XCTAssertTrue(hideWindowsSource.contains(".disabled(hidableCount == 0 || isRefreshingCounts || isShowingHidden || store.isActionBusy(.hideWindows))"))
        XCTAssertTrue(hideWindowsSource.contains(".disabled(hiddenCount == 0 || isRefreshingCounts || isShowingHidden || store.isActionBusy(.hideWindows))"))
        XCTAssertTrue(hideWindowsSource.contains(".disabled(isRefreshingCounts || isShowingHidden || store.isActionBusy(.hideWindows))"))
        XCTAssertTrue(lockScreenSource.contains(".disabled(store.isActionBusy(kind))"))
        XCTAssertTrue(displayUtilitySource.contains(".disabled(store.isActionBusy(kind))"))
        XCTAssertTrue(lowPowerSource.contains(".disabled(store.isActionBusy(.lowPowerMode))"))
        XCTAssertTrue(energyModeSource.contains(".disabled(store.isActionBusy(.energyMode))"))
        XCTAssertTrue(energyModeSource.contains(".disabled(isLoadingModes || store.isActionBusy(.energyMode))"))
    }

    func testDoNotDisturbShortcutNameEditingIsDebounced() throws {
        let source = try String(contentsOf: packageRoot.appendingPathComponent("Sources/MacSwitch/Views.swift"))
        let switches = try String(contentsOf: packageRoot.appendingPathComponent("Sources/MacSwitch/ExtendedSystemSwitches.swift"))
        let doNotDisturbSource = try extract(
            source,
            from: "private struct DoNotDisturbPreferencesPanel",
            to: "private struct ShortcutInstallRow"
        )
        let preferencesSource = try extract(
            switches,
            from: "enum DoNotDisturbPreferences",
            to: "struct DoNotDisturbSwitch"
        )
        let switchSource = try extract(
            switches,
            from: "struct DoNotDisturbSwitch",
            to: "struct PlayMusicSwitch"
        )

        XCTAssertTrue(doNotDisturbSource.contains("@State private var shortcutNameRefreshWorkItem: DispatchWorkItem?"))
        XCTAssertTrue(doNotDisturbSource.contains("scheduleShortcutNameRefresh()"))
        XCTAssertTrue(doNotDisturbSource.contains("DispatchQueue.main.asyncAfter(deadline: .now() + 0.35"))
        XCTAssertTrue(doNotDisturbSource.contains("refreshStatus(force: true)"))
        XCTAssertTrue(doNotDisturbSource.contains(".onDisappear"))
        XCTAssertFalse(doNotDisturbSource.contains("guard !allInstalled else { return }"))
        XCTAssertTrue(doNotDisturbSource.contains("@State private var hasDistinctShortcutPair = false"))
        XCTAssertTrue(doNotDisturbSource.contains("DoNotDisturbPreferences.shortcutConfigurationError"))
        XCTAssertTrue(doNotDisturbSource.contains("let shortcutPair = DoNotDisturbPreferences.installedShortcutPair(in: installed)"))
        XCTAssertTrue(doNotDisturbSource.contains("DoNotDisturbPreferences.installedShortcutName("))
        XCTAssertTrue(doNotDisturbSource.contains(".disabled(isRefreshing || store.isActionBusy(.doNotDisturb))"))
        XCTAssertTrue(doNotDisturbSource.contains("isDisabled: store.isActionBusy(.doNotDisturb)"))
        XCTAssertTrue(doNotDisturbSource.contains("Ready. Using \\(shortcutPair.on) and \\(shortcutPair.off)."))
        XCTAssertTrue(doNotDisturbSource.contains("DND On and DND Off must resolve to two different shortcuts."))
        XCTAssertTrue(preferencesSource.contains("invalidateInstalledShortcutsCache()"))
        XCTAssertTrue(preferencesSource.contains("shortcutCache = nil"))
        XCTAssertTrue(preferencesSource.contains("static var shortcutConfigurationError: String?"))
        XCTAssertTrue(preferencesSource.contains("Use different shortcut names for DND On and DND Off."))
        XCTAssertTrue(preferencesSource.contains("static func installedShortcutPair(in installed: Set<String>)"))
        XCTAssertTrue(preferencesSource.contains("static func installedShortcutName(matching candidates: [String], in installed: Set<String>) -> String?"))
        XCTAssertTrue(preferencesSource.contains("private static func normalizedShortcutName(_ value: String) -> String"))
        XCTAssertTrue(preferencesSource.contains("private static func shortcutMatchKey(_ value: String) -> String"))
        XCTAssertTrue(preferencesSource.contains("private static func installedShortcutsByMatchKey(_ installed: Set<String>) -> [String: String]"))
        XCTAssertTrue(preferencesSource.contains(".folding(options: [.caseInsensitive, .diacriticInsensitive]"))
        XCTAssertTrue(preferencesSource.contains("let normalizedCustom = normalizedShortcutName(custom)"))
        XCTAssertTrue(preferencesSource.contains("let names = normalizedCustom.isEmpty ? defaults : [normalizedCustom]"))
        XCTAssertTrue(preferencesSource.contains("result.output.split(separator: \"\\n\").map { normalizedShortcutName(String($0)) }.filter { !$0.isEmpty }"))
        XCTAssertFalse(preferencesSource.contains("([custom] + defaults)\n            .map(normalizedShortcutName)"))
        XCTAssertFalse(preferencesSource.contains("let normalizedInstalled = Set(installed.map(normalizedShortcutName).filter { !$0.isEmpty })"))
        XCTAssertTrue(preferencesSource.contains("guard shortcutConfigurationError == nil else { return false }"))
        XCTAssertTrue(switches.contains("private func conciseOneLineFailure"))
        XCTAssertTrue(preferencesSource.contains("conciseOneLineFailure("))
        XCTAssertFalse(preferencesSource.contains("private static func conciseFailureMessage"))
        XCTAssertTrue(switchSource.contains("UserDefaults.standard.removeObject(forKey: DoNotDisturbPreferences.stateKey)"))
        XCTAssertTrue(switchSource.contains("subtitle: \"Check shortcut names\""))
        XCTAssertTrue(switchSource.contains("DoNotDisturbPreferences.invalidateInstalledShortcutsCache()"))
        XCTAssertFalse(
            doNotDisturbSource.contains("DoNotDisturbPreferences.customOnShortcutName = value\n                        refreshStatus()"),
            "typing shortcut names should not run shortcuts list on every keypress"
        )
    }

    func testScreenCleanHasExitFailSafes() throws {
        let switches = try String(contentsOf: packageRoot.appendingPathComponent("Sources/MacSwitch/SystemSwitches.swift"))
        let diagnostics = try String(contentsOf: packageRoot.appendingPathComponent("Sources/MacSwitch/RegressionDiagnostics.swift"))
        let views = try String(contentsOf: packageRoot.appendingPathComponent("Sources/MacSwitch/Views.swift"))
        let cleanerSource = try extract(
            switches,
            from: "private final class ScreenCleaner",
            to: "private final class ScreenCleanWindow"
        )
        let exitEventSource = try extract(
            switches,
            from: "enum ScreenCleanExitEvent",
            to: "private final class EventBlocker"
        )
        let eventBlockerSource = try extract(
            switches,
            from: "fileprivate func handle",
            to: "private var keyboardMask"
        )
        let overlaySource = try extract(
            views,
            from: "struct ScreenCleanOverlayView",
            to: "struct VisualEffectView"
        )

        XCTAssertTrue(cleanerSource.contains("private let maximumSessionDuration: TimeInterval = 10 * 60"))
        XCTAssertTrue(cleanerSource.contains("scheduleFailSafeExit()"))
        XCTAssertTrue(cleanerSource.contains("cancelFailSafeExit()"))
        XCTAssertTrue(cleanerSource.contains("windows.allSatisfy(\\.isVisible)"))
        XCTAssertTrue(cleanerSource.contains("Could not present screen cleaning mode on every display."))
        XCTAssertTrue(cleanerSource.contains("Could not exit screen cleaning mode."))
        XCTAssertTrue(cleanerSource.contains("DispatchQueue.main.asyncAfter(deadline: .now() + maximumSessionDuration"))
        XCTAssertFalse(
            cleanerSource.contains("AccessibilityPermission.openSettings()"),
            "screen cleaning should not open System Settings without an explicit user action"
        )
        XCTAssertTrue(exitEventSource.contains(".tapDisabledByTimeout"))
        XCTAssertTrue(exitEventSource.contains(".tapDisabledByUserInput"))
        XCTAssertTrue(eventBlockerSource.contains("mode == .screenClean"))
        XCTAssertTrue(eventBlockerSource.contains("self?.onEscape?()"))
        XCTAssertTrue(switches.contains("CGEvent.tapIsEnabled(tap: tap)"))
        XCTAssertTrue(switches.contains("Could not attach the input event tap."))
        XCTAssertTrue(switches.contains("Could not enable the input event tap."))
        XCTAssertTrue(diagnostics.contains("Screen Cleaning exits if the event tap is disabled"))
        XCTAssertTrue(overlaySource.contains("Failsafe exits automatically after 10 minutes"))
    }

    func testCleanupActionsVerifyResultsAndReportPartialFailures() throws {
        let source = try String(contentsOf: packageRoot.appendingPathComponent("Sources/MacSwitch/ExtendedSystemSwitches.swift"))
        let xcodeSource = try extract(
            source,
            from: "struct XcodeCleanSwitch",
            to: "enum XcodeCleanPreferences"
        )
        let trashSource = try extract(
            source,
            from: "struct EmptyTrashSwitch",
            to: "struct EjectDiskSwitch"
        )
        let pasteboardSource = try extract(
            source,
            from: "struct EmptyPasteboardSwitch",
            to: "enum PasteboardPreferences"
        )

        XCTAssertTrue(xcodeSource.contains("var failures: [String] = []"))
        XCTAssertTrue(xcodeSource.contains("removedCount += 1"))
        XCTAssertTrue(xcodeSource.contains("Partially cleaned DerivedData"))
        XCTAssertTrue(xcodeSource.contains("Removed \\(removedCount) of \\(items.count) items"))
        XCTAssertTrue(trashSource.contains("let remaining = TrashPreferences.itemCount"))
        XCTAssertTrue(trashSource.contains("Finder finished, but \\(remaining) item"))
        XCTAssertTrue(trashSource.contains("playActionSound(named: \"Pop\")"))
        XCTAssertTrue(pasteboardSource.contains("let remaining = PasteboardPreferences.itemCount"))
        XCTAssertTrue(pasteboardSource.contains("macOS reported \\(remaining) pasteboard item"))
    }

    func testSystemActionsVerifyPostconditionsBeforeReportingSuccess() throws {
        let source = try String(contentsOf: packageRoot.appendingPathComponent("Sources/MacSwitch/ExtendedSystemSwitches.swift"))
        let defaultsSource = try extract(
            source,
            from: "private enum DefaultsBoolSwitch",
            to: "struct BluetoothAudioDeviceOption"
        )
        let resolutionSource = try extract(
            source,
            from: "struct ScreenResolutionSwitch",
            to: "struct LockScreenSwitch"
        )
        let displaySleepSource = try extract(
            source,
            from: "struct DisplaySleepSwitch",
            to: "struct ScreenResolutionSwitch"
        )
        let lockScreenSource = try extract(
            source,
            from: "struct LockScreenSwitch",
            to: "struct XcodeCleanSwitch"
        )
        let resolutionPreferencesSource = try extract(
            source,
            from: "enum ScreenResolutionPreferences",
            to: "enum DoNotDisturbPreferences"
        )
        let ejectSource = try extract(
            source,
            from: "struct EjectDiskSwitch",
            to: "struct EmptyPasteboardSwitch"
        )
        let hideWindowsSource = try extract(
            source,
            from: "struct HideWindowsSwitch",
            to: "struct LowPowerModeSwitch"
        )

        XCTAssertTrue(defaultsSource.contains("readStoredValue(domain: domain, key: key) == enabled"))
        XCTAssertTrue(defaultsSource.contains("macOS accepted the request, but \\(key) did not change."))
        XCTAssertTrue(defaultsSource.contains("restartProcessOrReport("))
        XCTAssertTrue(defaultsSource.contains("Updated \\(key), but could not restart \\(processName) to apply it."))
        XCTAssertFalse(defaultsSource.contains("_ = ProcessRunner.run(\"/usr/bin/killall\", [processName]"))
        XCTAssertTrue(resolutionSource.contains("verifyCurrentMode(display, matches: target)"))
        XCTAssertTrue(resolutionSource.contains("verifyCurrentMode(display, matches: mode)"))
        XCTAssertTrue(resolutionSource.contains("the display did not switch to the selected resolution"))
        XCTAssertTrue(displaySleepSource.contains("Self.hasOnlineDisplay"))
        XCTAssertTrue(displaySleepSource.contains("CGGetOnlineDisplayList(0, nil, &count)"))
        XCTAssertTrue(displaySleepSource.contains("No active display found."))
        XCTAssertTrue(resolutionSource.contains("ScreenResolutionPreferences.clearPreviousMode(for: display)\n            if result == .success"))
        XCTAssertTrue(resolutionSource.contains("if result == .success {\n                return \"macOS accepted the request, but the display did not switch to the selected resolution.\""))
        XCTAssertTrue(resolutionPreferencesSource.contains("let index = selectedDisplayIndex(in: displays)"))
        XCTAssertTrue(resolutionPreferencesSource.contains("static let selectedDisplaySignatureKey = \"switch.screenResolution.selectedDisplaySignature\""))
        XCTAssertTrue(resolutionPreferencesSource.contains("UserDefaults.standard.string(forKey: selectedDisplaySignatureKey)"))
        XCTAssertTrue(resolutionPreferencesSource.contains("displaySignature(for: $0.displayID) == storedSignature"))
        XCTAssertTrue(resolutionPreferencesSource.contains("static func setSelectedDisplayIndex(_ newValue: Int, in displays: [DisplayOption]? = nil)"))
        XCTAssertTrue(resolutionPreferencesSource.contains("UserDefaults.standard.set(displaySignature(for: availableDisplays[safeIndex].displayID), forKey: selectedDisplaySignatureKey)"))
        XCTAssertTrue(resolutionPreferencesSource.contains("let storedModeID = selectedModeID(for: displayID)"))
        XCTAssertTrue(resolutionPreferencesSource.contains("guard storedModeID != 0 else { return nil }"))
        XCTAssertFalse(resolutionPreferencesSource.contains("guard selectedModeID != 0 else { return nil }"))
        XCTAssertFalse(resolutionPreferencesSource.contains("modeID($0) == selectedModeID"))
        XCTAssertTrue(ejectSource.contains("waitForVolumeToUnmount(volume)"))
        XCTAssertTrue(ejectSource.contains("FileManager.default.fileExists(atPath: path)"))
        XCTAssertTrue(lockScreenSource.contains("CGSessionCopyCurrentDictionary()"))
        XCTAssertTrue(lockScreenSource.contains("waitForScreenLock()"))
        XCTAssertTrue(lockScreenSource.contains("macOS accepted the lock request, but the screen did not report locked."))
        XCTAssertTrue(hideWindowsSource.contains("waitForAppToHide(app)"))
        XCTAssertTrue(hideWindowsSource.contains("HideWindowsPreferences.recordHidden(hiddenApps)"))
        XCTAssertTrue(hideWindowsSource.contains("private static let hiddenAppTokensKey = \"switch.hideWindows.hiddenAppTokens\""))
        XCTAssertTrue(hideWindowsSource.contains("tokens.contains(token(for: $0))"))
        XCTAssertTrue(hideWindowsSource.contains("pruneTrackedHiddenApps()"))
        XCTAssertTrue(hideWindowsSource.contains("forgetHidden(app)"))
        XCTAssertTrue(hideWindowsSource.contains("Hidden \\(hiddenNames.count) of \\(apps.count) apps"))
        XCTAssertTrue(hideWindowsSource.contains("Could not hide \\(HideWindowsPreferences.joinedAppNames(failedNames))."))
        XCTAssertTrue(hideWindowsSource.contains("struct HideWindowsRestoreResult"))
        XCTAssertTrue(hideWindowsSource.contains("static func unhideAll() -> HideWindowsRestoreResult"))
        XCTAssertTrue(hideWindowsSource.contains("waitForApp(app, hidden: false)"))
        XCTAssertTrue(hideWindowsSource.contains("return HideWindowsRestoreResult(restored: restored, failed: failed)"))
        XCTAssertTrue(source.contains("Hide Widgets changed, but Dock could not restart to apply it."))
        XCTAssertTrue(source.contains("guard errors.isEmpty else"))
        XCTAssertTrue(ejectSource.contains("joinedVolumeNames(failed)"))
        XCTAssertTrue(ejectSource.contains("and \\(remaining) more"))
    }

    func testStatefulSwitchesReadBackSystemStateAfterMutatingCalls() throws {
        let systemSwitches = try String(contentsOf: packageRoot.appendingPathComponent("Sources/MacSwitch/SystemSwitches.swift"))
        let extendedSwitches = try String(contentsOf: packageRoot.appendingPathComponent("Sources/MacSwitch/ExtendedSystemSwitches.swift"))
        let stageSource = try extract(
            systemSwitches,
            from: "private struct StageManagerSwitch",
            to: "private struct DarkModeSwitch"
        )
        let darkModeSource = try extract(
            systemSwitches,
            from: "private struct DarkModeSwitch",
            to: "private struct BlueLightTimePair"
        )
        let nightShiftSource = try extract(
            systemSwitches,
            from: "private struct NightShiftSwitch",
            to: "enum NightShiftPreferences"
        )
        let trueToneSource = try extract(
            systemSwitches,
            from: "private struct TrueToneSwitch",
            to: "private final class KeyboardLocker"
        )
        let microphoneSource = try extract(
            extendedSwitches,
            from: "struct MuteMicrophoneSwitch",
            to: "struct ScreenSaverSwitch"
        )
        let screenSaverSource = try extract(
            extendedSwitches,
            from: "struct ScreenSaverSwitch",
            to: "struct BluetoothAudioSwitch"
        )
        let audioSource = try extract(
            extendedSwitches,
            from: "struct BluetoothAudioSwitch",
            to: "struct DoNotDisturbSwitch"
        )
        let playMusicSource = try extract(
            extendedSwitches,
            from: "struct PlayMusicSwitch",
            to: "struct DisplaySleepSwitch"
        )
        let energyModeSwitchSource = try extract(
            extendedSwitches,
            from: "struct EnergyModeSwitch",
            to: "private enum PowerMode"
        )
        let powerModeSource = extendedSwitches

        XCTAssertTrue(systemSwitches.contains("waitForSystemSwitchCondition"))
        XCTAssertTrue(stageSource.contains("readEnabled() == enabled"))
        XCTAssertTrue(stageSource.contains("Stage Manager did not change"))
        XCTAssertTrue(darkModeSource.contains("isEnabled == enabled"))
        XCTAssertTrue(darkModeSource.contains("Dark Mode did not change"))
        XCTAssertTrue(systemSwitches.contains("func restartProcessOrReport(_ processName: String, failureMessage: String) -> String?"))
        XCTAssertTrue(systemSwitches.contains("processWasNotRunning(result)"))
        XCTAssertTrue(stageSource.contains("restartProcessOrReport(\n            \"Dock\""))
        XCTAssertTrue(stageSource.contains("Stage Manager changed, but Dock could not restart to apply it."))
        XCTAssertFalse(stageSource.contains("_ = ProcessRunner.run(\"/usr/bin/killall\", [\"Dock\"]"))
        XCTAssertTrue(nightShiftSource.contains("waitForNightShiftActive(enabled)"))
        XCTAssertTrue(nightShiftSource.contains("status.active.boolValue"))
        XCTAssertFalse(nightShiftSource.contains("status.enabled.boolValue"))
        XCTAssertTrue(nightShiftSource.contains("Night Shift did not change"))
        XCTAssertTrue(nightShiftSource.contains("Night Shift schedule did not change"))
        XCTAssertTrue(trueToneSource.contains("bool(client, \"enabled\") == enabled"))
        XCTAssertTrue(trueToneSource.contains("True Tone did not change"))

        XCTAssertTrue(extendedSwitches.contains("waitForCondition"))
        XCTAssertTrue(microphoneSource.contains("waitForMute(device: device, equals: enabled)"))
        XCTAssertTrue(microphoneSource.contains("waitForVolume(device: device)"))
        XCTAssertTrue(microphoneSource.contains("microphone input volume did not mute"))
        XCTAssertTrue(microphoneSource.contains("preferredReadableInputAddresses"))
        XCTAssertTrue(microphoneSource.contains("let settable = settableInputAddresses"))
        XCTAssertTrue(microphoneSource.contains("return settable.isEmpty ? readable : settable"))
        XCTAssertTrue(microphoneSource.contains("if values.allSatisfy({ $0 }) { return true }"))
        XCTAssertTrue(microphoneSource.contains("if values.allSatisfy({ !$0 }) { return false }"))
        XCTAssertTrue(microphoneSource.contains("for var address in settableInputAddresses(kAudioDevicePropertyMute"))
        XCTAssertTrue(microphoneSource.contains("for var address in settableInputAddresses(kAudioDevicePropertyVolumeScalar"))
        XCTAssertTrue(screenSaverSource.contains("let opened = openWorkspaceURL(url)"))
        XCTAssertTrue(screenSaverSource.contains("pgrep\", [\"-x\", \"ScreenSaverEngine\"]"))
        XCTAssertTrue(screenSaverSource.contains("the screen saver did not start"))
        XCTAssertFalse(screenSaverSource.contains("NSWorkspace.shared.open(url)"))
        XCTAssertFalse(audioSource.contains("Thread.sleep"))
        XCTAssertTrue(audioSource.contains("let targetName = displayName(for: target)"))
        XCTAssertTrue(audioSource.contains("\\(targetName) is not responding."))
        XCTAssertTrue(audioSource.contains("\\(targetName) did not connect."))
        XCTAssertTrue(audioSource.contains("Could not disconnect \\(joinedDeviceNames(failed))."))
        XCTAssertTrue(audioSource.contains("private func joinedDeviceNames"))
        XCTAssertTrue(audioSource.contains("private func displayName(for device: IOBluetoothDevice) -> String"))
        XCTAssertTrue(playMusicSource.contains("waitForPlayerState"))
        XCTAssertTrue(playMusicSource.contains("did not \\(enabled ? \"start playing\" : \"pause\")"))
        XCTAssertFalse(playMusicSource.contains("Thread.sleep"))
        XCTAssertTrue(energyModeSwitchSource.contains("let supportedRawValues = PowerMode.availableModes(current: mode)"))
        XCTAssertTrue(energyModeSwitchSource.contains("EnergyModeSelection.allCases.filter { supportedRawValues.contains($0.rawValue) }"))
        XCTAssertFalse(energyModeSwitchSource.contains("PowerMode.availableModes(current: mode).compactMap(EnergyModeSelection.init(rawValue:))"))
        XCTAssertTrue(powerModeSource.contains("let currentMode = current"))
        XCTAssertTrue(powerModeSource.contains("if currentMode == mode"))
        XCTAssertTrue(powerModeSource.contains("guard mode == 0 || availableModes(current: currentMode).contains(mode)"))
        XCTAssertTrue(powerModeSource.contains("current == mode"))
        XCTAssertTrue(powerModeSource.contains("power mode did not change"))
    }

    func testMomentaryActionsExposeInProgressFeedback() throws {
        let model = try String(contentsOf: packageRoot.appendingPathComponent("Sources/MacSwitch/Model.swift"))
        let views = try String(contentsOf: packageRoot.appendingPathComponent("Sources/MacSwitch/Views.swift"))
        let executingSource = try extract(
            model,
            from: "var executingSubtitle: String?",
            to: "}\n}"
        )
        let rowActionSource = try extract(
            views,
            from: "private struct RowActionButton",
            to: "private struct RowFixButton"
        )
        let keepAwakeDurationMenuSource = try extract(
            views,
            from: "private struct KeepAwakeDurationMenu",
            to: "private struct DoNotDisturbDurationMenu"
        )
        let doNotDisturbDurationMenuSource = try extract(
            views,
            from: "private struct DoNotDisturbDurationMenu",
            to: "private struct DurationMenuLabel"
        )
        let xcodeSource = try extract(
            views,
            from: "private struct XcodeCleanPreferencesPanel",
            to: "private struct MicrophonePreferencesPanel"
        )
        let trashSource = try extract(
            views,
            from: "private struct TrashPreferencesPanel",
            to: "private struct PasteboardPreferencesPanel"
        )
        let pasteboardSource = try extract(
            views,
            from: "private struct PasteboardPreferencesPanel",
            to: "private struct HideWindowsPreferencesPanel"
        )
        let hideWindowsSource = try extract(
            views,
            from: "private struct HideWindowsPreferencesPanel",
            to: "private struct LockScreenPreferencesPanel"
        )
        let lockScreenSource = try extract(
            views,
            from: "private struct LockScreenPreferencesPanel",
            to: "private struct DisplayUtilityPreferencesPanel"
        )
        let displayUtilitySource = try extract(
            views,
            from: "private struct DisplayUtilityPreferencesPanel",
            to: "private struct LowPowerModePreferencesPanel"
        )

        for text in [
            "Starting screen saver...",
            "Sleeping display...",
            "Locking screen...",
            "Cleaning DerivedData...",
            "Emptying the Trash...",
            "Ejecting the disks...",
            "Emptying the Pasteboard...",
            "Hiding windows..."
        ] {
            XCTAssertTrue(executingSource.contains(text), "\(text) should be exposed during momentary actions")
        }

        XCTAssertTrue(rowActionSource.contains("let isRunning: Bool"))
        XCTAssertTrue(rowActionSource.contains("ProgressView()"))
        XCTAssertTrue(rowActionSource.contains(".disabled(!isEnabled || isRunning)"))
        XCTAssertTrue(views.contains("store.isActionBusy(kind)"))
        XCTAssertTrue(keepAwakeDurationMenuSource.contains(".disabled(store.isActionBusy(.keepAwake))"))
        XCTAssertTrue(keepAwakeDurationMenuSource.contains(".opacity(store.isActionBusy(.keepAwake) ? 0.55 : 1)"))
        XCTAssertTrue(keepAwakeDurationMenuSource.contains("Divider()"))
        XCTAssertTrue(keepAwakeDurationMenuSource.contains("Toggle(\"Keep awake when the lid is closed\""))
        XCTAssertTrue(keepAwakeDurationMenuSource.contains("KeepAwakePreferences.keepAwakeWhenLidClosed = value"))
        let allDurationRange = try XCTUnwrap(keepAwakeDurationMenuSource.range(of: "Button(KeepAwakeDuration.indefinitely.menuTitle)"))
        let lidClosedRange = try XCTUnwrap(keepAwakeDurationMenuSource.range(of: "Toggle(\"Keep awake when the lid is closed\""))
        let otherDurationsRange = try XCTUnwrap(keepAwakeDurationMenuSource.range(of: "ForEach(KeepAwakeDuration.allCases.filter { $0 != .indefinitely })"))
        XCTAssertLessThan(allDurationRange.lowerBound, lidClosedRange.lowerBound)
        XCTAssertLessThan(lidClosedRange.lowerBound, otherDurationsRange.lowerBound)
        XCTAssertTrue(doNotDisturbDurationMenuSource.contains(".disabled(store.isActionBusy(.doNotDisturb))"))
        XCTAssertTrue(doNotDisturbDurationMenuSource.contains(".opacity(store.isActionBusy(.doNotDisturb) ? 0.55 : 1)"))
        XCTAssertTrue(views.contains("store.actionsPreparing.map { \"Preparing \\($0.title)\" }"))
        XCTAssertTrue(xcodeSource.contains("Cleaning..."))
        XCTAssertTrue(trashSource.contains("emptyTrashActionTitle"))
        XCTAssertTrue(trashSource.contains("store.actionsPreparing.contains(.emptyTrash)"))
        XCTAssertTrue(trashSource.contains("Checking..."))
        XCTAssertTrue(trashSource.contains("Emptying..."))
        XCTAssertTrue(pasteboardSource.contains("pasteboardActionTitle"))
        XCTAssertTrue(pasteboardSource.contains("store.actionsPreparing.contains(.emptyPasteboard)"))
        XCTAssertTrue(pasteboardSource.contains("Checking..."))
        XCTAssertTrue(pasteboardSource.contains("Clearing..."))
        XCTAssertTrue(hideWindowsSource.contains("hideWindowsActionTitle"))
        XCTAssertTrue(hideWindowsSource.contains("store.actionsPreparing.contains(.hideWindows)"))
        XCTAssertTrue(hideWindowsSource.contains("Hiding..."))
        XCTAssertTrue(lockScreenSource.contains("Starting..."))
        XCTAssertTrue(lockScreenSource.contains("Locking..."))
        XCTAssertTrue(displayUtilitySource.contains("Sleeping..."))
    }

    func testDiagnosticsCopyDoesNotBlockMainThreadForSystemSummaries() throws {
        let source = try String(contentsOf: packageRoot.appendingPathComponent("Sources/MacSwitch/Views.swift"))
        let switches = try String(contentsOf: packageRoot.appendingPathComponent("Sources/MacSwitch/SystemSwitches.swift"))
        let diagnostics = try String(contentsOf: packageRoot.appendingPathComponent("Sources/MacSwitch/RegressionDiagnostics.swift"))
        let diagnosticsSource = try extract(
            source,
            from: "private enum AppDiagnostics",
            to: "private struct SwitchShortcutSection"
        )
        let summarySource = try extract(
            source,
            from: "static func summary(store: SwitchStore",
            to: "private struct SwitchShortcutSection"
        )

        XCTAssertTrue(diagnosticsSource.contains("DispatchQueue.global(qos: .utility).async"))
        XCTAssertTrue(diagnosticsSource.contains("let loginSummary = LoginItemManager.diagnosticSummary"))
        XCTAssertTrue(diagnosticsSource.contains("let accessibilityTrusted = AccessibilityPermission.isTrusted"))
        XCTAssertTrue(diagnosticsSource.contains("private static let refreshPollLimit = 12"))
        XCTAssertTrue(diagnosticsSource.contains("writeWhenRefreshSettled("))
        XCTAssertTrue(diagnosticsSource.contains("guard store.isRefreshing && remainingAttempts > 0 else"))
        XCTAssertTrue(diagnosticsSource.contains("DispatchQueue.main.asyncAfter(deadline: .now() + refreshPollInterval)"))
        XCTAssertTrue(diagnosticsSource.contains("summary(store: store, loginSummary: loginSummary, accessibilityTrusted: accessibilityTrusted)"))
        XCTAssertTrue(diagnosticsSource.contains("store.refreshAsync(.emptyPasteboard)"))
        XCTAssertTrue(summarySource.contains("DiagnosticRedactor.redact(snapshot.warning ?? snapshot.subtitle ?? \"\")"))
        XCTAssertTrue(summarySource.contains("let lastError = store.lastError.map(DiagnosticRedactor.redact) ?? \"none\""))
        XCTAssertTrue(summarySource.contains("let appPath = DiagnosticRedactor.redact(Bundle.main.bundleURL.path)"))
        XCTAssertTrue(summarySource.contains("let executablePath = DiagnosticRedactor.redact(Bundle.main.executablePath ?? \"-\")"))
        XCTAssertTrue(summarySource.contains("Last error: \\(lastError)"))
        XCTAssertTrue(summarySource.contains("App path: \\(appPath)"))
        XCTAssertTrue(summarySource.contains("Executable: \\(executablePath)"))
        XCTAssertTrue(switches.contains("enum DiagnosticRedactor"))
        XCTAssertTrue(switches.contains("DiagnosticRedactor.redact(configuredProgramArguments?.joined(separator: \" \") ?? \"none\")"))
        XCTAssertTrue(switches.contains("DiagnosticRedactor.redact(expectedProgramArguments.joined(separator: \" \"))"))
        XCTAssertTrue(switches.contains("DiagnosticRedactor.redact(launchAgentURL.path)"))
        XCTAssertTrue(diagnostics.contains("Play Music: skipped in safe self-test to avoid Automation prompts"))
        XCTAssertTrue(diagnostics.contains("Eject Disk exclusion matching works without writing preferences"))
        XCTAssertFalse(diagnostics.contains("EjectDiskPreferences.exclude(volume.url)"))
        XCTAssertTrue(diagnostics.contains("subtitle=present"))
        XCTAssertTrue(diagnostics.contains("warning=present"))
        XCTAssertFalse(diagnostics.contains("subtitle=\\(subtitle)"))
        XCTAssertFalse(diagnostics.contains("warning=\\(warning)"))
        XCTAssertFalse(
            summarySource.contains("LoginItemManager.diagnosticSummary"),
            "diagnostics summary formatting should use the precomputed login item summary"
        )
        XCTAssertFalse(
            summarySource.contains("AccessibilityPermission.isTrusted"),
            "diagnostics summary formatting should use the precomputed accessibility status"
        )
        XCTAssertTrue(source.contains("diagnosticsCopyInProgress"))
    }

    func testMicrophoneSwitchRequiresSettableInputControls() throws {
        let source = try String(contentsOf: packageRoot.appendingPathComponent("Sources/MacSwitch/ExtendedSystemSwitches.swift"))
        let microphoneSource = try extract(
            source,
            from: "struct MuteMicrophoneSwitch",
            to: "struct ScreenSaverSwitch"
        )

        XCTAssertTrue(microphoneSource.contains("AudioObjectIsPropertySettable"))
        XCTAssertTrue(microphoneSource.contains("does not allow Mac Switch to change it"))
        XCTAssertFalse(
            microphoneSource.contains("Microphone mute not supported"),
            "unsupported microphone state should explain whether input or controls are missing"
        )
    }

    func testPlayMusicSnapshotSurfacesAutomationDenial() throws {
        let switches = try String(contentsOf: packageRoot.appendingPathComponent("Sources/MacSwitch/SystemSwitches.swift"))
        let source = try String(contentsOf: packageRoot.appendingPathComponent("Sources/MacSwitch/ExtendedSystemSwitches.swift"))
        let automationSource = try extract(
            switches,
            from: "enum AutomationPermission",
            to: "final class SystemSwitchController"
        )
        let playMusicSource = try extract(
            source,
            from: "struct PlayMusicSwitch",
            to: "struct DisplaySleepSwitch"
        )

        XCTAssertTrue(automationSource.contains("static func isDenied"))
        XCTAssertTrue(automationSource.contains("static func permissionMessage(for target: String)"))
        XCTAssertFalse(
            automationSource.contains("guard isDenied(result) else { return nil }\n        openSettings()"),
            "automation denial handling should not open System Settings without an explicit user action"
        )
        XCTAssertTrue(playMusicSource.contains("let stateResult = playerStateResult(for: app)"))
        XCTAssertTrue(playMusicSource.contains("AutomationPermission.isDenied(stateResult)"))
        XCTAssertTrue(playMusicSource.contains("Could not read \\(app.displayName) playback state"))
        XCTAssertTrue(playMusicSource.contains("conciseOneLineFailure("))
        XCTAssertTrue(playMusicSource.contains("playerControlsReady(for: app)"))
        XCTAssertTrue(source.contains("private static func waitForAppToRun"))
        XCTAssertTrue(source.contains("return waitForAppToRun(bundleIdentifier: info.bundleIdentifier)"))
        XCTAssertTrue(playMusicSource.contains("opened, but playback controls are not ready."))
        XCTAssertTrue(playMusicSource.contains("isAvailable: false"))
        XCTAssertTrue(playMusicSource.contains("Review Automation"))
        XCTAssertTrue(playMusicSource.contains("normalizedPlayerState(from: stateResult)"))
        XCTAssertTrue(playMusicSource.contains("state == \"playing\" ? (currentTrack(for: app) ?? app.displayName) : app.displayName"))
        XCTAssertFalse(playMusicSource.contains("currentTrack(for: app) ?? app.displayName\n        )"))
    }

    func testDashboardUnavailableRowsExposeTargetedFixActions() throws {
        let source = try String(contentsOf: packageRoot.appendingPathComponent("Sources/MacSwitch/Views.swift"))
        let systemSwitches = try String(contentsOf: packageRoot.appendingPathComponent("Sources/MacSwitch/SystemSwitches.swift"))
        let extendedSwitches = try String(contentsOf: packageRoot.appendingPathComponent("Sources/MacSwitch/ExtendedSystemSwitches.swift"))
        let controlRowSource = try extract(
            source,
            from: "private struct ControlRow",
            to: "private struct SwitchGlyph"
        )
        let errorRouterSource = try extract(
            source,
            from: "private enum ErrorFixRouter",
            to: "private extension SwitchKind"
        )

        XCTAssertTrue(source.contains("private struct RowFixButton"))
        XCTAssertTrue(controlRowSource.contains("rowFixMessage"))
        XCTAssertTrue(controlRowSource.contains("let accessibilityPrompt = snapshot.warning == \"Open System Settings\""))
        XCTAssertTrue(controlRowSource.contains("kind == .screenClean || kind == .lockKeyboard"))
        XCTAssertTrue(controlRowSource.contains("snapshot.isAvailable == false || accessibilityPrompt"))
        XCTAssertTrue(controlRowSource.contains("ErrorFixRouter.route(message: rowFixMessage, store: store)"))
        XCTAssertTrue(controlRowSource.contains("does not expose"))
        XCTAssertTrue(controlRowSource.contains("does not allow"))
        XCTAssertTrue(controlRowSource.contains("not supported"))
        XCTAssertTrue(controlRowSource.contains("trash empty"))
        XCTAssertTrue(controlRowSource.contains("pasteboard empty"))
        XCTAssertTrue(controlRowSource.contains("no ejectable disks"))
        XCTAssertTrue(controlRowSource.contains("no apps to hide"))
        XCTAssertTrue(controlRowSource.contains("deriveddata: zero"))
        XCTAssertTrue(source.contains("Open Music Setup"))
        XCTAssertTrue(source.contains("openCustomize(.playMusic, store: store)"))
        XCTAssertTrue(source.contains("Open Bluetooth"))
        XCTAssertTrue(source.contains("Open Bluetooth Audio"))
        XCTAssertTrue(source.contains("openCustomize(.bluetoothAudio, store: store)"))
        XCTAssertTrue(errorRouterSource.contains("clearLastErrorIfOpened"))
        XCTAssertTrue(errorRouterSource.contains("clearLastErrorIfOpened(SystemSettingsLinks.openBluetooth(), store: store)"))
        XCTAssertTrue(errorRouterSource.contains("clearLastErrorIfOpened(XcodeCleanPreferences.revealDerivedData(), store: store)"))
        XCTAssertTrue(errorRouterSource.contains("clearLastErrorIfOpened(TrashPreferences.openTrash(), store: store)"))
        XCTAssertFalse(errorRouterSource.contains("SystemSettingsLinks.openBluetooth()\n            store.clearLastError()"))
        XCTAssertTrue(systemSwitches.contains("static func openBluetooth() -> Bool"))
        XCTAssertTrue(systemSwitches.contains("static func openLoginItems() -> Bool"))
        XCTAssertTrue(extendedSwitches.contains("static func revealDerivedData() -> Bool"))
        XCTAssertTrue(extendedSwitches.contains("static func openTrash() -> Bool"))
        XCTAssertTrue(systemSwitches.contains("func revealInFinder(_ url: URL) -> Bool"))
        XCTAssertTrue(systemSwitches.contains("NSWorkspace.shared.selectFile(target.path, inFileViewerRootedAtPath: \"\")"))
        XCTAssertTrue(extendedSwitches.contains("return revealInFinder(url)"))
        XCTAssertFalse(extendedSwitches.contains("activateFileViewerSelecting([url])"))
        XCTAssertTrue(errorRouterSource.range(of: "lowercased.contains(\"headphones\")")!.lowerBound < errorRouterSource.range(of: "lowercased.contains(\"bluetooth\")")!.lowerBound)
    }

    func testOpenFailuresStayVisibleAndErrorTextIsReadable() throws {
        let views = try String(contentsOf: packageRoot.appendingPathComponent("Sources/MacSwitch/Views.swift"))
        let switches = try String(contentsOf: packageRoot.appendingPathComponent("Sources/MacSwitch/SystemSwitches.swift"))
        let dashboardBanner = try extract(
            views,
            from: "private struct DashboardErrorBanner",
            to: "private struct ErrorRemediation"
        )
        let preferencesBanner = try extract(
            views,
            from: "private struct PreferencesErrorBanner",
            to: "private struct SidebarTabButton"
        )

        XCTAssertTrue(switches.contains("DispatchQueue.main.sync"))
        XCTAssertFalse(
            switches.contains("DispatchQueue.main.async {\n            _ = open()\n        }\n        return true"),
            "openWorkspaceURL should not report success before NSWorkspace actually opens the URL"
        )
        XCTAssertTrue(views.contains("private func reportOpenResult"))
        XCTAssertTrue(views.contains("store.lastError = failureMessage"))
        XCTAssertTrue(views.contains("else if store.lastError == failureMessage"))
        XCTAssertTrue(views.contains("store.clearLastError()"))
        XCTAssertTrue(views.contains("private func openWorkspaceURLOrReport"))
        XCTAssertTrue(views.contains("revealInFinder(Bundle.main.bundleURL)"))
        XCTAssertTrue(views.contains("Could not reveal the Mac Switch app bundle."))
        XCTAssertFalse(views.contains("activateFileViewerSelecting([Bundle.main.bundleURL])"))
        XCTAssertTrue(views.contains("Could not open Login Items settings."))
        XCTAssertTrue(views.contains("Could not open Accessibility settings."))
        XCTAssertTrue(views.contains("Could not open Disk Utility."))
        XCTAssertTrue(views.contains("Could not open Shortcuts."))
        XCTAssertFalse(views.contains("https://www." + "i" + "cloud.com/shortcuts/"))
        XCTAssertTrue(views.contains("Could not open \\(target.displayName)."))
        XCTAssertTrue(views.contains("lowercased.contains(\"disable sleep\")"))
        XCTAssertTrue(views.contains("lowercased.contains(\"lid-closed sleep\")"))
        XCTAssertTrue(views.contains("lowercased.contains(\"pmset\")"))
        XCTAssertTrue(views.contains("lowercased.contains(\"appleshowallfiles\")"))
        XCTAssertTrue(views.contains("lowercased.contains(\"createdesktop\")"))
        XCTAssertTrue(views.contains("lowercased.contains(\"autohide\")"))
        XCTAssertTrue(views.contains("lowercased.contains(\"globallyenabled\")"))
        XCTAssertTrue(views.contains("reportOpenResult(\n                            PlayMusicPreferences.open(target)"))
        XCTAssertTrue(views.contains("XcodeCleanPreferences.refreshSizeEstimate()"))
        XCTAssertTrue(views.contains("store: store,\n                isDisabled: store.isActionBusy(.doNotDisturb)"))
        XCTAssertTrue(dashboardBanner.contains(".help(message)"))
        XCTAssertTrue(preferencesBanner.contains(".help(message)"))
    }

    func testStatusItemOpensDashboardOnMouseDown() throws {
        let appDelegate = try String(contentsOf: packageRoot.appendingPathComponent("Sources/MacSwitch/AppDelegate.swift"))
        XCTAssertTrue(appDelegate.contains("NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)"))
        XCTAssertFalse(appDelegate.contains("NSStatusBar.system.statusItem(withLength: 34)"))
        XCTAssertTrue(appDelegate.contains("item.button?.sendAction(on: [.leftMouseDown])"))
    }

    func testPreferencesNoLongerExposeDisabledPlaceholderTabs() throws {
        let source = try String(contentsOf: packageRoot.appendingPathComponent("Sources/MacSwitch/Views.swift"))
        let tabSource = try extract(
            source,
            from: "private enum PreferencesTab",
            to: "private enum PreferencesColors"
        )
        let shortcutSectionSource = try extract(
            source,
            from: "private struct SwitchShortcutSection",
            to: "private struct ShortcutRecorderButton"
        )
        let customizeSource = try extract(
            source,
            from: "private struct CustomizePreferencesView",
            to: "private struct CustomizeRow"
        )
        let switchPanelSource = try extract(
            source,
            from: "private struct SwitchPreferencePanel",
            to: "private struct BluetoothAudioPreferencesPanel"
        )
        let aboutSource = try extract(
            source,
            from: "private struct AboutPreferencesView",
            to: "private struct CustomizePreferencesView"
        )

        XCTAssertFalse(source.contains("ShortcutsPreferencesView"), "Shortcuts should live inside each switch options panel")
        XCTAssertFalse(tabSource.contains("case shortcuts"))
        XCTAssertTrue(source.contains("AboutPreferencesView"), "About preferences should be implemented")
        XCTAssertTrue(tabSource.contains("var isImplemented: Bool"))
        XCTAssertTrue(shortcutSectionSource.contains("ShortcutRecorderButton(shortcut: store.shortcuts[kind])"))
        XCTAssertTrue(shortcutSectionSource.contains("store.setShortcut(kind, shortcut: shortcut)"))
        XCTAssertTrue(shortcutSectionSource.contains("store.setShortcut(kind, shortcut: nil)"))
        XCTAssertTrue(shortcutSectionSource.contains("Hidden from dashboard; shortcut still works"))
        XCTAssertTrue(switchPanelSource.contains("SwitchShortcutSection(kind: kind, store: store)"))
        let switchSpecificSettingsRange = try XCTUnwrap(switchPanelSource.range(of: "case .bluetoothAudio:"))
        let shortcutSectionRange = try XCTUnwrap(switchPanelSource.range(of: "SwitchShortcutSection(kind: kind, store: store)"))
        XCTAssertLessThan(switchSpecificSettingsRange.lowerBound, shortcutSectionRange.lowerBound)
        XCTAssertTrue(aboutSource.contains("@State private var confirmsClearingShortcuts = false"))
        XCTAssertTrue(aboutSource.contains("Clear All Shortcuts"))
        XCTAssertTrue(aboutSource.contains("store.clearAllShortcuts()"))
        XCTAssertTrue(source.contains("VisualEffectView(material: .hudWindow"))
        XCTAssertTrue(source.contains(".background(Color.clear)"))
        XCTAssertTrue(source.contains("private struct DashboardBackdrop"))
        XCTAssertTrue(source.contains("DashboardColors.windowVeil"))
        XCTAssertTrue(source.contains("DashboardColors.glassGlow"))
        XCTAssertTrue(source.contains("VisualEffectView(material: .sidebar"))
        XCTAssertTrue(source.contains(".toggleStyle(.switch)"))
        XCTAssertTrue(source.contains("Label(\"Battery\", systemImage: \"battery.50percent\")"))
        XCTAssertFalse(source.contains("Label(\"Battery Settings\", systemImage: \"battery.50percent\")"))
        XCTAssertFalse(source.contains("PaletteToggleStyle"))
        XCTAssertFalse(source.contains("badgeBackground"))
        XCTAssertTrue(source.contains("private struct DashboardBandBackground"))
        XCTAssertTrue(customizeSource.contains("init(store: SwitchStore)"))
        XCTAssertTrue(customizeSource.contains("_selectedKind = State(initialValue: Self.initialSelection(in: store))"))
        XCTAssertTrue(customizeSource.contains("private static func initialSelection(in store: SwitchStore) -> SwitchKind?"))
        XCTAssertTrue(customizeSource.contains("onClose:"))
        XCTAssertTrue(source.contains("Image(systemName: \"xmark\")"))
        XCTAssertTrue(customizeSource.contains("HStack(alignment: .top, spacing: selectedKind == nil ? 0 : 10)"))
        XCTAssertTrue(customizeSource.contains("publishCustomizeLayout(detailVisible: true)"))
        XCTAssertTrue(customizeSource.contains("publishCustomizeLayout(detailVisible: false)"))
        XCTAssertTrue(customizeSource.contains("name: .setMacSwitchPreferencesLayout"))
        XCTAssertTrue(source.contains("userInfo: [\"mode\": \"compact\"]"))
        XCTAssertFalse(source.contains("? (store.preferredCustomizeKind == nil ? \"compact\" : \"detail\")"))
        XCTAssertTrue(customizeSource.contains(".onDisappear {\n            selectedKind = nil\n            publishCustomizeLayout(detailVisible: false)\n        }"))
        XCTAssertTrue(customizeSource.contains("userInfo: [\"mode\": detailVisible ? \"detail\" : \"compact\"]"))
        XCTAssertTrue(customizeSource.contains(".transition(.move(edge: .trailing).combined(with: .opacity))"))
        XCTAssertFalse(customizeSource.contains("@State private var selectedKind: SwitchKind = .keepAwake"))
        XCTAssertFalse(tabSource.contains("return false"), "Preferences tabs should not use disabled placeholder states")
        XCTAssertFalse(source.localizedCaseInsensitiveContains("coming soon"), "Preferences should not expose coming-soon placeholder copy")
    }

    func testLocationStatusUsesActionableMessages() throws {
        let source = try String(contentsOf: packageRoot.appendingPathComponent("Sources/MacSwitch/SunSchedule.swift"))
        let views = try String(contentsOf: packageRoot.appendingPathComponent("Sources/MacSwitch/Views.swift"))
        let darkModeSource = try extract(
            views,
            from: "private struct DarkModePreferencesPanel",
            to: "private struct NightShiftPreferencesPanel"
        )

        XCTAssertTrue(source.contains("Location Services are off"))
        XCTAssertTrue(source.contains("Location access denied"))
        XCTAssertTrue(source.contains("Location access restricted"))
        XCTAssertTrue(source.contains("Location lookup failed"))
        XCTAssertTrue(darkModeSource.contains("status.contains(\"off\")"))
        XCTAssertTrue(darkModeSource.contains("status.contains(\"failed\")"))
        XCTAssertFalse(
            source.contains("case .denied, .restricted:\n            status = .unavailable(\"Location is not available\")"),
            "denied and restricted location states should tell the user what changed"
        )
    }

    func testSunScheduleAlignsEventsToRequestedLocalDay() throws {
        let source = try String(contentsOf: packageRoot.appendingPathComponent("Sources/MacSwitch/SunSchedule.swift"))
        let diagnostics = try String(contentsOf: packageRoot.appendingPathComponent("Sources/MacSwitch/RegressionDiagnostics.swift"))
        let calculatorSource = try extract(
            source,
            from: "enum SolarCalculator",
            to: "private static func degreesToRadians"
        )

        XCTAssertTrue(calculatorSource.contains("align(candidate, toLocalDayOf: date, calendar: calendar)"))
        XCTAssertTrue(calculatorSource.contains("calendar.startOfDay(for: candidate)"))
        XCTAssertTrue(calculatorSource.contains("calendar.startOfDay(for: date)"))
        XCTAssertTrue(calculatorSource.contains("candidate.addingTimeInterval(24 * 60 * 60)"))
        XCTAssertTrue(calculatorSource.contains("candidate.addingTimeInterval(-24 * 60 * 60)"))
        XCTAssertTrue(diagnostics.contains("import CoreLocation"))
        XCTAssertTrue(diagnostics.contains("checkSunScheduleDateAlignment(&reporter)"))
        XCTAssertTrue(diagnostics.contains("SolarCalculator.sunWindow"))
        XCTAssertTrue(diagnostics.contains("America/Los_Angeles"))
        XCTAssertTrue(diagnostics.contains("Asia/Tokyo"))
    }

    func testGlobalShortcutValidationAvoidsCommonSystemShortcuts() throws {
        let shortcuts = try String(contentsOf: packageRoot.appendingPathComponent("Sources/MacSwitch/GlobalShortcuts.swift"))
        let model = try String(contentsOf: packageRoot.appendingPathComponent("Sources/MacSwitch/Model.swift"))
        let views = try String(contentsOf: packageRoot.appendingPathComponent("Sources/MacSwitch/Views.swift"))
        let diagnostics = try String(contentsOf: packageRoot.appendingPathComponent("Sources/MacSwitch/RegressionDiagnostics.swift"))

        XCTAssertTrue(shortcuts.contains("primaryModifierCount(modifiers) < 2"))
        XCTAssertTrue(shortcuts.contains("reservedKeyCodes"))
        XCTAssertTrue(shortcuts.contains("Use at least two of Command, Option, or Control."))
        XCTAssertTrue(shortcuts.contains("Choose a letter, number, or function key for the shortcut."))
        XCTAssertTrue(shortcuts.contains("if let reason = shortcut.validationFailureMessage"))
        XCTAssertTrue(shortcuts.contains("Could not install global shortcut handler (OSStatus \\(eventHandlerInstallStatus))."))
        XCTAssertTrue(shortcuts.contains("(OSStatus \\(status))"))
        XCTAssertTrue(shortcuts.contains("nextID = 1"))
        XCTAssertTrue(shortcuts.contains("eventHandlerInstallStatus = InstallEventHandler"))
        XCTAssertTrue(model.contains("shortcut?.validationFailureMessage"))
        XCTAssertTrue(model.contains("clearLastErrorIfShortcutOwned()"))
        XCTAssertTrue(model.contains("lastError?.hasPrefix(\"Could not install global shortcut handler\") == true"))
        XCTAssertFalse(model.contains("lastError?.contains(\"shortcut\") == true"))
        XCTAssertFalse(model.contains("lastError = nil\n        shortcuts[kind] = shortcut"))
        XCTAssertTrue(model.contains("clearLastErrorIfPrefixed(\"Start at Login failed:\")"))
        XCTAssertTrue(model.contains("guard !isUpdatingStartAtLogin else { return }"))
        XCTAssertFalse(model.contains("self.lastError = nil\n                }\n            }\n        }\n    }\n\n    private func saveOrder"))
        XCTAssertTrue(views.contains("Two modifiers + key. Delete clears."))
        XCTAssertTrue(views.contains("HotKeyShortcut.recordingFailureTitle"))
        XCTAssertTrue(diagnostics.contains("shortcut validation rejects Command-A"))
        XCTAssertTrue(diagnostics.contains("shortcut validation rejects reserved keys"))
        XCTAssertFalse(diagnostics.contains("shortcut validation accepts Command-A"))
        XCTAssertFalse(views.contains("Use ⌘, ⌥, or ⌃"))
    }

    func testShortcutPersistenceAndRegistrationRecoverFromEmptyOrDuplicateState() throws {
        let shortcuts = try String(contentsOf: packageRoot.appendingPathComponent("Sources/MacSwitch/GlobalShortcuts.swift"))
        let model = try String(contentsOf: packageRoot.appendingPathComponent("Sources/MacSwitch/Model.swift"))
        let registerSource = try extract(
            shortcuts,
            from: "func register(shortcuts:",
            to: "private func unregisterAll()"
        )
        let loadSource = try extract(
            model,
            from: "private static func loadShortcuts",
            to: "private static func deduplicatedKinds"
        )

        XCTAssertTrue(registerSource.contains("self.handler = shortcuts.isEmpty ? nil : handler"))
        XCTAssertTrue(registerSource.contains("guard !shortcuts.isEmpty else { return nil }"))
        XCTAssertTrue(loadSource.contains("var seenShortcuts: Set<String> = []"))
        XCTAssertTrue(loadSource.contains("for kind in SwitchKind.allCases"))
        XCTAssertTrue(loadSource.contains("let shortcutKey = \"\\(value.keyCode)-\\(value.modifiers)\""))
        XCTAssertTrue(loadSource.contains("guard seenShortcuts.insert(shortcutKey).inserted else { continue }"))
        XCTAssertFalse(loadSource.contains("Dictionary(uniqueKeysWithValues: raw.compactMap"))
    }

    func testInteractionPolishAndStaleActionGuards() throws {
        let appDelegate = try String(contentsOf: packageRoot.appendingPathComponent("Sources/MacSwitch/AppDelegate.swift"))
        let model = try String(contentsOf: packageRoot.appendingPathComponent("Sources/MacSwitch/Model.swift"))
        let switches = try String(contentsOf: packageRoot.appendingPathComponent("Sources/MacSwitch/SystemSwitches.swift"))
        let feature = try String(contentsOf: packageRoot.appendingPathComponent("Sources/MacSwitch/ExtendedSystemSwitches.swift"))
        let views = try String(contentsOf: packageRoot.appendingPathComponent("Sources/MacSwitch/Views.swift"))
        let dashboardOpenSource = try extract(
            appDelegate,
            from: "private func showDashboard(relativeTo button:",
            to: "private func hideDashboard()"
        )
        let dashboardRefreshSource = try extract(
            appDelegate,
            from: "private func scheduleDashboardRefreshAfterOpen()",
            to: "private func finishUISmokeTest()"
        )
        let actionSource = try extract(
            model,
            from: "func set(_ kind: SwitchKind, enabled: Bool)",
            to: "@discardableResult\n    private func ensureSwitchAvailable"
        )
        let xcodeCleanSource = try extract(
            model,
            from: "private func runXcodeClean()",
            to: "private func schedulePostActionRefresh"
        )
        let loginSource = try extract(
            views,
            from: "private struct GeneralPreferencesView",
            to: "private enum AppLinks"
        )
        let shortcutInstallSource = try extract(
            views,
            from: "private struct ShortcutInstallRow",
            to: "private struct KeepAwakePreferencesPanel"
        )
        let trashSource = try extract(
            feature,
            from: "enum TrashPreferences",
            to: "struct EmptyTrashSwitch"
        )
        let controllerInitSource = try extract(
            switches,
            from: "final class SystemSwitchController",
            to: "func snapshot(for kind:"
        )

        XCTAssertTrue(dashboardOpenSource.contains("scheduleDashboardRefreshAfterOpen()"))
        XCTAssertFalse(dashboardOpenSource.contains("store.refreshVisibleAsync()"), "dashboard click path should draw first, then refresh")
        XCTAssertTrue(dashboardRefreshSource.contains("DispatchQueue.main.asyncAfter(deadline: .now() + 0.06)"))
        XCTAssertTrue(dashboardRefreshSource.contains("dashboardWindow?.isVisible == true"))
        XCTAssertTrue(dashboardRefreshSource.contains("store.refreshVisibleAsync()"))

        XCTAssertTrue(model.contains("private var actionVersions: [SwitchKind: Int] = [:]"))
        XCTAssertTrue(model.contains("private func nextActionVersion(for kind: SwitchKind) -> Int"))
        XCTAssertTrue(model.contains("private func isCurrentAction(_ kind: SwitchKind, version: Int) -> Bool"))
        XCTAssertTrue(actionSource.contains("let actionVersion = nextActionVersion(for: kind)"))
        XCTAssertTrue(actionSource.contains("self.isCurrentAction(kind, version: actionVersion)"))
        XCTAssertTrue(actionSource.contains("applySetResult(result, for: kind, enabled: enabled, actionVersion: actionVersion)"))
        XCTAssertTrue(xcodeCleanSource.contains("let actionVersion = nextActionVersion(for: .xcodeClean)"))
        XCTAssertTrue(xcodeCleanSource.contains("self.isCurrentAction(.xcodeClean, version: actionVersion)"))
        XCTAssertFalse(xcodeCleanSource.contains("actionsInProgress.contains(.xcodeClean) else { return }\n                    self.snapshots"))

        XCTAssertTrue(controllerInitSource.contains("keepAwake.onExpired"))
        XCTAssertTrue(controllerInitSource.contains("onExternalChange?(.keepAwake)"))
        XCTAssertTrue(switches.contains("var onExpired: (() -> Void)?"))
        XCTAssertTrue(switches.contains("_ = self.disable()\n            self.onExpired?()"))

        XCTAssertTrue(model.contains("func cancelStartAtLoginApproval()"))
        XCTAssertTrue(loginSource.contains("store.cancelStartAtLoginApproval()"))
        XCTAssertTrue(loginSource.contains("Label(store.text(.cancel), systemImage: \"xmark.circle\")"))
        XCTAssertFalse(loginSource.contains("cancel the pending login item"))

        XCTAssertTrue(shortcutInstallSource.contains("Button(\"Open Shortcuts\")"))
        XCTAssertTrue(shortcutInstallSource.contains("AppLinks.shortcutsApp"))
        XCTAssertTrue(shortcutInstallSource.contains("Create or choose in Shortcuts"))
        XCTAssertTrue(shortcutInstallSource.contains(".disabled(isDisabled)"))
        XCTAssertFalse(shortcutInstallSource.contains(".disabled(installed || isDisabled)"))

        XCTAssertTrue(trashSource.contains("private static let ignoredMetadataNames"))
        XCTAssertTrue(trashSource.contains("\".DS_Store\""))
        XCTAssertTrue(trashSource.contains("\".localized\""))
        XCTAssertTrue(trashSource.contains("private static func countedItems(in directory: URL) -> Int"))
        XCTAssertTrue(trashSource.contains("!ignoredMetadataNames.contains($0.lastPathComponent)"))
        XCTAssertFalse(trashSource.contains(".count) ?? 0)"))
    }

    private var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func macSwitchExecutable() throws -> URL {
        let candidates = [
            packageRoot.appendingPathComponent(".build/debug/MacSwitch"),
            packageRoot.appendingPathComponent(".build/arm64-apple-macosx/debug/MacSwitch"),
            packageRoot.appendingPathComponent(".build/x86_64-apple-macosx/debug/MacSwitch")
        ]

        let fileManager = FileManager.default
        if let executable = candidates.first(where: { fileManager.isExecutableFile(atPath: $0.path) }) {
            return executable
        }

        XCTFail("MacSwitch debug executable was not found. Checked: \(candidates.map(\.path).joined(separator: ", "))")
        throw CocoaError(.fileNoSuchFile)
    }

    private func run(
        _ executable: String,
        _ arguments: [String],
        timeout: TimeInterval
    ) throws -> (status: Int32, output: String, error: String, combinedOutput: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = packageRoot

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
            XCTFail("Process timed out: \(executable) \(arguments.joined(separator: " "))")
        }
        process.waitUntilExit()

        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let error = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (process.terminationStatus, output, error, [output, error].filter { !$0.isEmpty }.joined(separator: "\n"))
    }

    private func sourceAvailableFilesForAudit() throws -> [String] {
        let fileManager = FileManager.default
        let excludedDirectories: Set<String> = [
            ".build",
            ".git",
            ".swiftpm",
            "Build",
            "DerivedData"
        ]
        guard let enumerator = fileManager.enumerator(
            at: packageRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        ) else {
            return []
        }

        var files: [String] = []
        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            let resourceValues = try url.resourceValues(forKeys: [.isDirectoryKey])
            if resourceValues.isDirectory == true {
                if excludedDirectories.contains(name) {
                    enumerator.skipDescendants()
                }
                continue
            }
            let path = url.path
            guard path.hasPrefix(packageRoot.path + "/") else { continue }
            files.append(String(path.dropFirst(packageRoot.path.count + 1)))
        }
        return files.sorted()
    }

    private func extract(_ source: String, from startMarker: String, to endMarker: String) throws -> String {
        let start = try XCTUnwrap(source.range(of: startMarker)?.lowerBound)
        let end = try XCTUnwrap(source.range(of: endMarker, range: start..<source.endIndex)?.lowerBound)
        return String(source[start..<end])
    }

    private func ascii(_ bytes: [UInt8]) -> String {
        String(decoding: bytes, as: UTF8.self)
    }
}
