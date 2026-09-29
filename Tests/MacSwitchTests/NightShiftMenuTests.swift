import AppKit
import SwiftUI
import XCTest
@testable import MacSwitch

@MainActor
final class NightShiftMenuTests: XCTestCase {
    func testOpeningAndRefreshingOptionsDoesNotChangeNightShift() async throws {
        let (store, model, backend) = fixture()
        model.refresh()
        try await settle(model)
        XCTAssertTrue(store.nightShiftSettings === model)
        XCTAssertEqual(model.preset, .custom)
        XCTAssertEqual(model.isSupported, true)
        model.refresh()
        try await settle(model)
        XCTAssertEqual(backend.operations, [])
        XCTAssertFalse(backend.wasReadOnMain)
    }

    func testSettingsReserveTheSwitchUntilTheUpdateFinishes() async throws {
        let controller = NightMenuController()
        let (store, model, backend) = fixture(controller: controller)
        model.refresh()
        try await settle(model)
        backend.gate = DispatchSemaphore(value: 0)
        defer { backend.gate?.signal() }
        model.applyPreset(.alwaysOn)
        XCTAssertTrue(store.isActionBusy(.nightShift))
        store.toggle(.nightShift)
        model.updateKeepsSwitchState(true)
        XCTAssertEqual(controller.toggleCount, 0)
        backend.gate?.signal()
        try await settle(model)
        XCTAssertEqual(backend.operations, ["alwaysOn"])
        XCTAssertEqual(model.preset, .alwaysOn)
        XCTAssertFalse(store.isActionBusy(.nightShift))
    }

    func testRefreshPreservesCustomDraftAndApplyUsesThoseTimes() async throws {
        let (store, model, backend) = fixture()
        model.refresh()
        try await settle(model)
        let start = TimeOfDay(hour: 21, minute: 15)
        let end = TimeOfDay(hour: 6, minute: 30)
        model.setCustomStart(start)
        model.setCustomEnd(end)
        model.refresh()
        try await settle(model)
        XCTAssertEqual(model.customSchedule, NightShiftScheduleState(start: start, end: end))
        XCTAssertTrue(model.customScheduleHasChanges)
        model.applyPreset(.custom)
        try await settle(model)
        XCTAssertEqual(backend.load().state?.schedule, NightShiftScheduleState(start: start, end: end))
        XCTAssertFalse(model.customScheduleHasChanges)
        XCTAssertFalse(store.isActionBusy(.nightShift))
    }

    func testFailureKeepsConfirmedSelectionAndCustomDraft() async throws {
        let (store, model, backend) = fixture()
        model.refresh()
        try await settle(model)
        model.setCustomStart(TimeOfDay(hour: 20, minute: 45))
        backend.error = "Could not change Night Shift schedule."
        model.applyPreset(.alwaysOn)
        try await settle(model)
        XCTAssertEqual(model.preset, .custom)
        XCTAssertTrue(model.hasError)
        XCTAssertTrue(model.customScheduleHasChanges)
        XCTAssertEqual(model.customSchedule.start, TimeOfDay(hour: 20, minute: 45))
        XCTAssertFalse(store.isActionBusy(.nightShift))
        backend.error = nil
        model.updateKeepsSwitchState(true)
        try await settle(model)
        XCTAssertTrue(model.keepsSwitchState)
        XCTAssertFalse(model.hasError)
    }

    func testUnavailableDisplayDoesNotAcceptSettingsChanges() async throws {
        let (store, model, backend) = fixture()
        backend.available = false
        model.refresh()
        try await settle(model)
        model.applyPreset(.alwaysOn)
        model.updateKeepsSwitchState(true)
        XCTAssertEqual(model.isSupported, false)
        XCTAssertEqual(backend.operations, [])
        XCTAssertFalse(store.isActionBusy(.nightShift))
    }

    func testQuickPanelFitsSmallDashboardAndOnlyExpandsForCustomTimes() async throws {
        _ = NSApplication.shared
        let (store, model, _) = fixture()
        model.refresh()
        try await settle(model)
        for height in [DashboardLayout.minHeight - 20, DashboardLayout.maxHeight - 20] {
            var renderedHeights: [CGFloat] = []
            for preset in [NightShiftSchedulePreset.alwaysOn, .custom] {
                model.applyPreset(preset)
                try await settle(model)
                XCTAssertEqual(model.preset, preset)
                let size = DashboardRowQuickMenu.size(for: .nightShift, availableHeight: height, isCustomNightShift: preset == .custom)
                // Each preset gets a fresh host: off-window NSHostingView caches its initial intrinsic size.
                let host = NSHostingView(rootView: DashboardRowQuickMenu(
                    kind: .nightShift, store: store, hideDisabledReason: nil,
                    availableHeight: height, configure: {}, hideFromMenu: {}
                ))
                host.appearance = NSAppearance(named: .aqua)
                host.frame = NSRect(origin: .zero, size: size)
                try await Task.sleep(for: .milliseconds(30))
                host.layoutSubtreeIfNeeded()
                XCTAssertEqual(host.fittingSize.height, size.height, accuracy: 0.5)
                XCTAssertEqual(host.fittingSize.width, size.width, accuracy: 0.5)
                XCTAssertLessThanOrEqual(host.fittingSize.height, height)
                renderedHeights.append(host.fittingSize.height)
                if let directory = ProcessInfo.processInfo.environment["NIGHT_MENU_SCREENSHOTS"],
                   let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    try bitmap.representation(using: .png, properties: [:])?.write(to:
                        URL(fileURLWithPath: directory).appendingPathComponent("night-menu-\(preset.rawValue)-\(Int(height)).png"))
                }
                try await settle(model)
            }
            XCTAssertLessThan(renderedHeights[0], renderedHeights[1], "Ordinary presets should not leave an empty time editor area")
        }
    }

    private func fixture(controller: NightMenuController = NightMenuController()) -> (SwitchStore, NightShiftSettingsModel, NightMenuBackend) {
        let store = SwitchStore(controller: controller, defaults: InMemoryUserDefaults(), enableRuntimeServices: false)
        let backend = NightMenuBackend()
        let model = NightShiftSettingsModel(store: store, backend: backend)
        store.nightShiftSettings = model
        return (store, model, backend)
    }

    private func settle(_ model: NightShiftSettingsModel) async throws {
        for _ in 0..<200 where model.isBusy { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(model.isBusy)
    }
}

private final class NightMenuBackend: NightShiftSettingsBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var panel = NightShiftPanelState(
        state: NightShiftState(active: true, enabled: true, sunSchedulePermitted: true,
                              scheduleMode: .custom, schedule: .defaultSchedule, disableFlags: 0,
                              available: true, supported: true, strength: 0.5, correlatedColorTemperature: 4100),
        subtitle: "On until 07:00", keepsSwitchState: false, restoredCustomSchedule: .defaultSchedule, lastChange: nil)
    private var recorded: [String] = []
    private var readOnMain = false
    var wasReadOnMain: Bool { lock.withLock { readOnMain } }
    var operations: [String] { lock.withLock { recorded } }
    var gate: DispatchSemaphore?
    var error: String?
    var available = true
    func load() -> NightShiftPanelState {
        lock.withLock {
            readOnMain = readOnMain || Thread.isMainThread
            var result = panel
            if !available { result.state = nil }
            return result
        }
    }
    func applySchedule(_ preset: NightShiftSchedulePreset, customSchedule: NightShiftScheduleState) -> String? {
        _ = gate?.wait(timeout: .now() + 3)
        return lock.withLock {
            recorded.append(preset.rawValue)
            if let error { return error }
            panel.state?.scheduleMode = preset == .off ? .off : (preset == .sunsetToSunrise ? .sunsetToSunrise : .custom)
            panel.state?.schedule = preset == .alwaysOn ? NightShiftAlwaysOn.schedule(resumingAt: .init(hour: 5, minute: 0)) : customSchedule
            return nil
        }
    }
    func setKeepsSwitchState(_ keep: Bool) -> String? {
        lock.withLock {
            recorded.append("keep:\(keep)")
            if let error { return error }
            panel.keepsSwitchState = keep
            return nil
        }
    }
}

private final class NightMenuController: SystemSwitchControlling, @unchecked Sendable {
    var onExternalChange: (@Sendable (SwitchKind) -> Void)?
    private let lock = NSLock()
    private var toggles = 0
    var toggleCount: Int { lock.withLock { toggles } }
    func snapshot(for kind: SwitchKind, keepAwakeDuration: KeepAwakeDuration) -> SwitchSnapshot {
        SwitchSnapshot(isOn: true, isAvailable: true, subtitle: nil, warning: nil)
    }
    func set(_ kind: SwitchKind, enabled: Bool, keepAwakeDuration: KeepAwakeDuration) -> SwitchOperationResult {
        lock.withLock { toggles += 1 }
        return SwitchOperationResult(snapshot: .off, error: nil)
    }
    func setKeepAwake(enabled: Bool, duration: TimeInterval?, defaultDuration: KeepAwakeDuration) -> SwitchOperationResult {
        set(.keepAwake, enabled: enabled, keepAwakeDuration: defaultDuration)
    }
    func performXcodeClean(progress: @escaping @Sendable (Double) -> Void) -> SwitchOperationResult { .init(snapshot: .off, error: nil) }
    func prepareForTermination() {}
}
