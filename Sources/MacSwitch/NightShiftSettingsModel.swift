import Combine
import Foundation

struct NightShiftPanelState: Sendable {
    var state: NightShiftState?
    var subtitle: String?
    var keepsSwitchState: Bool
    var restoredCustomSchedule: NightShiftScheduleState
    var lastChange: NightShiftChangeRecord?
}

protocol NightShiftSettingsBackend: Sendable {
    func load() -> NightShiftPanelState
    func applySchedule(_ preset: NightShiftSchedulePreset, customSchedule: NightShiftScheduleState) -> String?
    func setKeepsSwitchState(_ keep: Bool) -> String?
}

struct SystemNightShiftSettingsBackend: NightShiftSettingsBackend {
    func load() -> NightShiftPanelState {
        let state = NightShiftPreferences.state
        return NightShiftPanelState(
            state: state,
            subtitle: state.flatMap(NightShiftPreferences.subtitle(for:)),
            keepsSwitchState: NightShiftPreferences.keepsSwitchState,
            restoredCustomSchedule: NightShiftPreferences.restoredCustomSchedule,
            lastChange: NightShiftPreferences.lastChange
        )
    }
    func applySchedule(_ preset: NightShiftSchedulePreset, customSchedule: NightShiftScheduleState) -> String? {
        NightShiftPreferences.applySchedule(preset, customSchedule: customSchedule)
    }
    func setKeepsSwitchState(_ keep: Bool) -> String? {
        NightShiftPreferences.setKeepsSwitchState(keep)
    }
}

/// One settings session shared by the dashboard and preferences, including unsaved custom times.
@MainActor
final class NightShiftSettingsModel: ObservableObject {
    @Published private(set) var preset: NightShiftSchedulePreset = .off
    @Published private(set) var customSchedule = NightShiftScheduleState.defaultSchedule
    @Published private(set) var customScheduleHasChanges = false
    @Published private(set) var keepsSwitchState = false
    @Published private(set) var currentStatus: String?
    @Published private(set) var lastChange: NightShiftChangeRecord?
    @Published private(set) var isSupported: Bool?
    @Published private(set) var isRefreshing = false
    @Published private(set) var isUpdating = false
    @Published private(set) var statusText: String?
    @Published private(set) var hasError = false
    private weak var store: SwitchStore?
    private let backend: any NightShiftSettingsBackend
    private let refreshQueue = DispatchQueue(label: "com.maxyu.macswitch.night-shift-settings", qos: .utility)
    private var pendingRefresh = false

    init(store: SwitchStore, backend: any NightShiftSettingsBackend = SystemNightShiftSettingsBackend()) {
        self.store = store
        self.backend = backend
    }

    var isBusy: Bool { isRefreshing || isUpdating || store?.isActionBusy(.nightShift) == true }

    func refresh() {
        guard !isBusy else {
            pendingRefresh = true
            return
        }
        isRefreshing = true
        let backend = backend
        refreshQueue.async { [weak self] in
            let latest = backend.load()
            DispatchQueue.main.async {
                guard let self else { return }
                self.apply(latest, resetDraft: false)
                self.isRefreshing = false
                self.refreshIfNeeded()
            }
        }
    }

    func setCustomStart(_ time: TimeOfDay) {
        customSchedule.start = time
        customScheduleHasChanges = true
    }

    func setCustomEnd(_ time: TimeOfDay) {
        customSchedule.end = time
        customScheduleHasChanges = true
    }

    func applyPreset(_ value: NightShiftSchedulePreset) {
        let schedule = customSchedule
        update(success: Self.scheduleStatusText(for: value)) { backend in
            backend.applySchedule(value, customSchedule: schedule)
        }
    }

    func updateKeepsSwitchState(_ value: Bool) {
        update(success: value ? "The switch now keeps Night Shift as set." : "The switch works like Control Center again.") {
            $0.setKeepsSwitchState(value)
        }
    }

    private func update(success: String, operation: @escaping @Sendable (any NightShiftSettingsBackend) -> String?) {
        guard !isBusy, isSupported == true, let store else { return }
        let backend = backend
        let started = store.performNightShiftSettingsUpdate({
            let error = operation(backend)
            return (backend.load(), error)
        }, completion: { [weak self] latest, error in
            guard let self else { return }
            self.apply(latest, resetDraft: error == nil)
            self.statusText = error ?? success
            self.hasError = error != nil
            self.isUpdating = false
            self.refreshIfNeeded()
        })
        if started {
            isUpdating = true
            hasError = false
            statusText = "Updating Night Shift schedule..."
        }
    }

    private func refreshIfNeeded() {
        guard pendingRefresh else { return }
        pendingRefresh = false
        refresh()
    }

    private func apply(_ latest: NightShiftPanelState, resetDraft: Bool) {
        keepsSwitchState = latest.keepsSwitchState
        lastChange = latest.lastChange
        isSupported = latest.state?.isAvailable ?? false
        currentStatus = latest.subtitle
        guard let state = latest.state else { return }
        preset = NightShiftSchedulePreset.current(mode: state.scheduleMode, schedule: state.schedule)
        if resetDraft || !customScheduleHasChanges {
            customSchedule = preset == .alwaysOn ? latest.restoredCustomSchedule : state.schedule
            customScheduleHasChanges = false
        }
    }

    private static func scheduleStatusText(for preset: NightShiftSchedulePreset) -> String {
        switch preset {
        case .off: return "Night Shift scheduling is off. You can still use the dashboard switch manually."
        case .sunsetToSunrise: return "Night Shift will follow sunset and sunrise."
        case .custom: return "Night Shift will follow your custom schedule."
        case .alwaysOn: return "Night Shift stays on around the clock."
        }
    }
}
