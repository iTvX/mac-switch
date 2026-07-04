import Foundation
import Sparkle

enum SoftwareUpdateChannel: String, CaseIterable, Identifiable {
    case stable
    case beta

    var id: String { rawValue }

    var title: String {
        switch self {
        case .stable: return "Stable"
        case .beta: return "Beta"
        }
    }

    var subtitle: String {
        switch self {
        case .stable:
            return "Use the latest notarized public release."
        case .beta:
            return "Try prerelease builds before they become stable."
        }
    }

    var allowedSparkleChannels: Set<String> {
        switch self {
        case .stable: return []
        case .beta: return ["beta"]
        }
    }
}

final class SoftwareUpdateManager: NSObject, ObservableObject, SPUUpdaterDelegate {
    static let shared = SoftwareUpdateManager()

    @Published private(set) var isAvailable: Bool
    @Published private(set) var canCheckForUpdates: Bool
    @Published private(set) var lastUpdateCheckDate: Date?
    @Published var updateChannel: SoftwareUpdateChannel {
        didSet {
            guard oldValue != updateChannel else { return }
            defaults.set(updateChannel.rawValue, forKey: DefaultsKey.updateChannel)
            refresh()
        }
    }
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

    private let defaults = UserDefaults.standard
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
        let storedChannel = UserDefaults.standard.string(forKey: DefaultsKey.updateChannel)
        updateChannel = storedChannel.flatMap(SoftwareUpdateChannel.init(rawValue:)) ?? .stable

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
        refresh()
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

    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        updateChannel.allowedSparkleChannels
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

    private enum DefaultsKey {
        static let updateChannel = "softwareUpdate.channel"
    }
}
