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

    var appcastChannel: String? {
        switch self {
        case .stable: return nil
        case .beta: return "beta"
        }
    }

    static var currentBuild: SoftwareUpdateChannel {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        return shortVersion.localizedCaseInsensitiveContains("beta") ? .beta : .stable
    }
}

final class SoftwareUpdateManager: NSObject, ObservableObject, SPUUpdaterDelegate {
    static let shared = SoftwareUpdateManager()

    let currentBuildChannel: SoftwareUpdateChannel

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
    private let bundleVersion: String
    private let channelSwitchLock = NSLock()
    private var updaterController: SPUStandardUpdaterController?
    private var updaterObservations: [NSKeyValueObservation] = []
    private var channelSwitchTarget: SoftwareUpdateChannel?
    private var channelSwitchUpdateVersion: String?
    private lazy var versionComparator = ChannelSwitchVersionComparator(manager: self)

    var hasPendingChannelSwitch: Bool {
        updateChannel != currentBuildChannel
    }

    private override init() {
        let bundleHasUpdateFeed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil
        let runningFromAppBundle = Bundle.main.bundleURL.pathExtension == "app"
        currentBuildChannel = SoftwareUpdateChannel.currentBuild
        bundleVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
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
        prepareChannelSwitchForNextCheck()
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

    func bestValidUpdate(in appcast: SUAppcast, for updater: SPUUpdater) -> SUAppcastItem? {
        guard let target = currentChannelSwitchTarget() else { return nil }
        guard let item = bestItem(in: appcast.items, for: target) else {
            setChannelSwitchTarget(target, updateVersion: nil)
            return SUAppcastItem.empty()
        }
        guard canInstall(item) else {
            setChannelSwitchTarget(target, updateVersion: nil)
            return SUAppcastItem.empty()
        }

        setChannelSwitchTarget(target, updateVersion: item.versionString)
        return item
    }

    func versionComparator(for updater: SPUUpdater) -> SUVersionComparison? {
        versionComparator
    }

    func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: Error?
    ) {
        clearChannelSwitch()
        refresh()
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        clearChannelSwitch()
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

    private func prepareChannelSwitchForNextCheck() {
        setChannelSwitchTarget(hasPendingChannelSwitch ? updateChannel : nil, updateVersion: nil)
    }

    private func currentChannelSwitchTarget() -> SoftwareUpdateChannel? {
        channelSwitchLock.lock()
        defer { channelSwitchLock.unlock() }
        return channelSwitchTarget
    }

    private func setChannelSwitchTarget(_ target: SoftwareUpdateChannel?, updateVersion: String?) {
        channelSwitchLock.lock()
        channelSwitchTarget = target
        channelSwitchUpdateVersion = updateVersion
        channelSwitchLock.unlock()
    }

    private func clearChannelSwitch() {
        setChannelSwitchTarget(nil, updateVersion: nil)
    }

    fileprivate func channelSwitchComparisonOverride(versionA: String, versionB: String) -> ComparisonResult? {
        guard versionA != versionB else { return .orderedSame }

        channelSwitchLock.lock()
        let updateVersion = channelSwitchUpdateVersion
        channelSwitchLock.unlock()

        guard let updateVersion, !bundleVersion.isEmpty else { return nil }
        if versionA == bundleVersion, versionB == updateVersion {
            return .orderedAscending
        }
        if versionA == updateVersion, versionB == bundleVersion {
            return .orderedDescending
        }
        return nil
    }

    private func bestItem(in items: [SUAppcastItem], for channel: SoftwareUpdateChannel) -> SUAppcastItem? {
        let matchingItems = items.filter { $0.channel == channel.appcastChannel }
        return matchingItems.max { lhs, rhs in
            SUStandardVersionComparator.default.compareVersion(lhs.versionString, toVersion: rhs.versionString) == .orderedAscending
        }
    }

    private func canInstall(_ item: SUAppcastItem) -> Bool {
        guard !bundleVersion.isEmpty else { return true }
        return SUStandardVersionComparator.default.compareVersion(bundleVersion, toVersion: item.versionString) != .orderedDescending
    }
}

private final class ChannelSwitchVersionComparator: NSObject, SUVersionComparison {
    private weak var manager: SoftwareUpdateManager?

    init(manager: SoftwareUpdateManager) {
        self.manager = manager
    }

    func compareVersion(_ versionA: String, toVersion versionB: String) -> ComparisonResult {
        if let override = manager?.channelSwitchComparisonOverride(versionA: versionA, versionB: versionB) {
            return override
        }
        return SUStandardVersionComparator.default.compareVersion(versionA, toVersion: versionB)
    }
}
