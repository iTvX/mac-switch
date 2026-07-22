import Foundation
import Sparkle

enum SoftwareUpdateChannel: String, CaseIterable, Identifiable {
    case stable
    case beta

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        switch (self, language) {
        case (.stable, .simplifiedChinese): return "正式版"
        case (.beta, .simplifiedChinese): return "测试版"
        case (.stable, .traditionalChinese): return "正式版"
        case (.beta, .traditionalChinese): return "測試版"
        case (.stable, .spanish): return "Estable"
        case (.beta, .spanish): return "Beta"
        case (.stable, .japanese): return "安定版"
        case (.beta, .japanese): return "ベータ版"
        case (.stable, .korean): return "안정화"
        case (.beta, .korean): return "베타"
        case (.stable, .german): return "Stabil"
        case (.beta, .german): return "Beta"
        case (.stable, .french): return "Stable"
        case (.beta, .french): return "Bêta"
        case (.stable, .italian): return "Stabile"
        case (.beta, .italian): return "Beta"
        case (.stable, .portuguese): return "Estável"
        case (.beta, .portuguese): return "Beta"
        case (.stable, .english), (.stable, .system): return "Stable"
        case (.beta, .english), (.beta, .system): return "Beta"
        }
    }

    func subtitle(language: AppLanguage) -> String {
        switch (self, language) {
        case (.stable, .simplifiedChinese): return "使用最新的已公证正式版本。"
        case (.beta, .simplifiedChinese): return "在功能正式发布前体验测试版本。"
        case (.stable, .traditionalChinese): return "使用最新的已公證正式版本。"
        case (.beta, .traditionalChinese): return "在功能正式發布前體驗測試版本。"
        case (.stable, .spanish): return "Usa la versión pública notarizada más reciente."
        case (.beta, .spanish): return "Prueba versiones preliminares antes de su publicación."
        case (.stable, .japanese): return "最新の公証済み正式版を使用します。"
        case (.beta, .japanese): return "正式公開前のベータ版を試します。"
        case (.stable, .korean): return "공증된 최신 정식 버전을 사용합니다."
        case (.beta, .korean): return "정식 출시 전 베타 버전을 사용합니다."
        case (.stable, .german): return "Verwendet die neueste notarisierte öffentliche Version."
        case (.beta, .german): return "Testet Vorabversionen vor ihrer stabilen Veröffentlichung."
        case (.stable, .french): return "Utilise la dernière version publique notariée."
        case (.beta, .french): return "Teste les préversions avant leur publication stable."
        case (.stable, .italian): return "Usa l’ultima versione pubblica autenticata da Apple."
        case (.beta, .italian): return "Prova le versioni preliminari prima del rilascio stabile."
        case (.stable, .portuguese): return "Usa a versão pública notarizada mais recente."
        case (.beta, .portuguese): return "Testa versões preliminares antes do lançamento estável."
        case (.stable, .english), (.stable, .system): return "Use the latest notarized public release."
        case (.beta, .english), (.beta, .system): return "Try prerelease builds before they become stable."
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
        let detectedBuildChannel = SoftwareUpdateChannel.currentBuild
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
