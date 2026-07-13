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

    var requiresBetaChannel: (() -> Bool)?

    private let defaults = UserDefaults.standard
    private let bundleVersion: String
    private let channelSwitchState = ChannelSwitchState()
    private var updaterController: SPUStandardUpdaterController?
    private var updaterObservations: [NSKeyValueObservation] = []
    private lazy var versionComparator = ChannelSwitchVersionComparator(
        state: channelSwitchState,
        bundleVersion: bundleVersion
    )

    var hasPendingChannelSwitch: Bool {
        updateChannel != currentBuildChannel
    }

    private override init() {
        let bundleHasUpdateFeed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil
        let runningFromAppBundle = Bundle.main.bundleURL.pathExtension == "app"
        let detectedBuildChannel = SoftwareUpdateChannel.currentBuild
        currentBuildChannel = detectedBuildChannel
        bundleVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        isAvailable = bundleHasUpdateFeed && runningFromAppBundle
        canCheckForUpdates = false
        lastUpdateCheckDate = nil
        automaticallyChecksForUpdates = false
        automaticallyDownloadsUpdates = false
        let storedChannel = UserDefaults.standard.string(forKey: DefaultsKey.updateChannel)
        updateChannel = storedChannel.flatMap(SoftwareUpdateChannel.init(rawValue:)) ?? detectedBuildChannel

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
        if requiresBetaChannel?() == true {
            guard let item = bestItem(in: appcast.items, for: .beta), canInstall(item) else {
                return SUAppcastItem.empty()
            }
            return item
        }
        guard let target = currentChannelSwitchTarget() else { return nil }
        guard let item = bestItem(in: appcast.items, for: target) else {
            setChannelSwitchTarget(target, updateVersion: nil)
            return SUAppcastItem.empty()
        }

        // A user-requested channel switch may cross to an older or equal build.
        // The selected item still comes from Sparkle's verified official appcast.
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
        channelSwitchState.target
    }

    private func setChannelSwitchTarget(_ target: SoftwareUpdateChannel?, updateVersion: String?) {
        channelSwitchState.set(target: target, updateVersion: updateVersion)
    }

    private func clearChannelSwitch() {
        setChannelSwitchTarget(nil, updateVersion: nil)
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

private final class ChannelSwitchState: @unchecked Sendable {
    private let lock = NSLock()
    private var storedTarget: SoftwareUpdateChannel?
    private var storedUpdateVersion: String?

    var target: SoftwareUpdateChannel? {
        lock.withLock { storedTarget }
    }

    func set(target: SoftwareUpdateChannel?, updateVersion: String?) {
        lock.withLock {
            storedTarget = target
            storedUpdateVersion = updateVersion
        }
    }

    func comparisonOverride(
        versionA: String,
        versionB: String,
        bundleVersion: String
    ) -> ComparisonResult? {
        let state = lock.withLock { (storedTarget, storedUpdateVersion) }
        guard state.0 != nil, let updateVersion = state.1, !bundleVersion.isEmpty else { return nil }
        if versionA == bundleVersion, versionB == updateVersion {
            // Channel switching can intentionally install a different package with an
            // older or equal CFBundleVersion.
            return .orderedAscending
        }
        if updateVersion != bundleVersion, versionA == updateVersion, versionB == bundleVersion {
            return .orderedDescending
        }
        return nil
    }
}

private final class ChannelSwitchVersionComparator: NSObject, SUVersionComparison {
    private let state: ChannelSwitchState
    private let bundleVersion: String

    init(state: ChannelSwitchState, bundleVersion: String) {
        self.state = state
        self.bundleVersion = bundleVersion
    }

    func compareVersion(_ versionA: String, toVersion versionB: String) -> ComparisonResult {
        if let override = state.comparisonOverride(
            versionA: versionA,
            versionB: versionB,
            bundleVersion: bundleVersion
        ) {
            return override
        }
        return SUStandardVersionComparator.default.compareVersion(versionA, toVersion: versionB)
    }
}
