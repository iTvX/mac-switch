import Foundation
import Sparkle

final class SoftwareUpdateManager: NSObject, ObservableObject, SPUUpdaterDelegate {
    static let shared = SoftwareUpdateManager()

    @Published private(set) var isAvailable: Bool
    @Published private(set) var canCheckForUpdates: Bool
    @Published private(set) var lastUpdateCheckDate: Date?
    @Published var automaticallyChecksForUpdates: Bool {
        didSet {
            guard oldValue != automaticallyChecksForUpdates else { return }
            updaterController?.updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
            refresh()
        }
    }
    @Published var automaticallyDownloadsUpdates: Bool {
        didSet {
            guard oldValue != automaticallyDownloadsUpdates else { return }
            updaterController?.updater.automaticallyDownloadsUpdates = automaticallyDownloadsUpdates
            refresh()
        }
    }

    private var updaterController: SPUStandardUpdaterController?
    private var updaterObservations: [NSKeyValueObservation] = []

    private override init() {
        let bundleHasUpdateFeed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil
        let runningFromAppBundle = Bundle.main.bundleURL.pathExtension == "app"
        isAvailable = bundleHasUpdateFeed && runningFromAppBundle
        canCheckForUpdates = false
        lastUpdateCheckDate = nil
        automaticallyChecksForUpdates = false
        automaticallyDownloadsUpdates = false

        super.init()

        guard isAvailable else { return }

        let controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        updaterController = controller
        observe(updater: controller.updater)
        refresh()
    }

    func start() {
        guard let updaterController else { return }
        updaterController.startUpdater()
        refresh()
    }

    func checkForUpdates() {
        guard let updaterController else { return }
        updaterController.checkForUpdates(nil)
        refresh()
    }

    func refresh() {
        guard let updater = updaterController?.updater else {
            canCheckForUpdates = false
            lastUpdateCheckDate = nil
            return
        }

        canCheckForUpdates = updater.canCheckForUpdates
        lastUpdateCheckDate = updater.lastUpdateCheckDate
        automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
        automaticallyDownloadsUpdates = updater.automaticallyDownloadsUpdates
    }

    func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: Error?
    ) {
        refresh()
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        refresh()
    }

    private func observe(updater: SPUUpdater) {
        updaterObservations = [
            updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] _, _ in
                DispatchQueue.main.async { self?.refresh() }
            },
            updater.observe(\.automaticallyChecksForUpdates, options: [.initial, .new]) { [weak self] _, _ in
                DispatchQueue.main.async { self?.refresh() }
            },
            updater.observe(\.automaticallyDownloadsUpdates, options: [.initial, .new]) { [weak self] _, _ in
                DispatchQueue.main.async { self?.refresh() }
            }
        ]
    }
}
