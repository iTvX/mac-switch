import Foundation

enum AppLanguage: String, CaseIterable, Codable, Identifiable {
    case system
    case english
    case simplifiedChinese
    case traditionalChinese
    case spanish
    case japanese
    case korean
    case german
    case french
    case italian
    case portuguese

    var id: String { rawValue }

    var effectiveLanguage: AppLanguage {
        self == .system ? Self.preferredSystemLanguage : self
    }

    var localeIdentifier: String {
        switch self {
        case .system:
            return Self.preferredSystemLanguage.localeIdentifier
        case .english:
            return "en"
        case .simplifiedChinese:
            return "zh-Hans"
        case .traditionalChinese:
            return "zh-Hant"
        case .spanish:
            return "es"
        case .japanese:
            return "ja"
        case .korean:
            return "ko"
        case .german:
            return "de"
        case .french:
            return "fr"
        case .italian:
            return "it"
        case .portuguese:
            return "pt"
        }
    }

    var pickerTitle: String {
        pickerTitle(in: effectiveLanguage)
    }

    func pickerTitle(in language: AppLanguage) -> String {
        switch self {
        case .system:
            return L10n.text(.followSystem, language: language.effectiveLanguage)
        case .english:
            return "English"
        case .simplifiedChinese:
            return "简体中文"
        case .traditionalChinese:
            return "繁體中文"
        case .spanish:
            return "Español"
        case .japanese:
            return "日本語"
        case .korean:
            return "한국어"
        case .german:
            return "Deutsch"
        case .french:
            return "Français"
        case .italian:
            return "Italiano"
        case .portuguese:
            return "Português"
        }
    }

    static var preferredSystemLanguage: AppLanguage {
        preferredLanguage(matching: Locale.preferredLanguages) ?? .english
    }

    static func preferredLanguage(matching identifiers: [String]) -> AppLanguage? {
        for identifier in identifiers {
            let normalized = identifier
                .replacingOccurrences(of: "_", with: "-")
                .lowercased()
            if normalized.hasPrefix("zh-hant") ||
                normalized.hasPrefix("zh-tw") ||
                normalized.hasPrefix("zh-hk") ||
                normalized.hasPrefix("zh-mo") {
                return .traditionalChinese
            }
            if normalized.hasPrefix("zh") {
                return .simplifiedChinese
            }
            if normalized.hasPrefix("es") { return .spanish }
            if normalized.hasPrefix("ja") { return .japanese }
            if normalized.hasPrefix("ko") { return .korean }
            if normalized.hasPrefix("de") { return .german }
            if normalized.hasPrefix("fr") { return .french }
            if normalized.hasPrefix("it") { return .italian }
            if normalized.hasPrefix("pt") { return .portuguese }
            if normalized.hasPrefix("en") { return .english }
        }
        return nil
    }
}

enum L10nKey: String, CaseIterable {
    case about
    case accessibility
    case accessibilityGrantedSubtitle
    case accessibilityRequiredSubtitle
    case activeOf
    case application
    case approve
    case automation
    case automationSubtitle
    case bluetooth
    case bluetoothSubtitle
    case cancel
    case checking
    case checkingAccessibilitySubtitle
    case controlsReady
    case customize
    case followSystem
    case general
    case generalSubtitle
    case granted
    case language
    case languageSubtitle
    case location
    case locationSubtitle
    case menuBar
    case menuBarIcon
    case menuBarUtility
    case needsAccess
    case noSwitchAdded
    case off
    case on
    case open
    case pending
    case permissions
    case preferences
    case quit
    case quitMacSwitch
    case repair
    case review
    case selectSwitchPrompt
    case startAtLogin
    case startup
}

enum L10n {
    static func text(_ key: L10nKey, language: AppLanguage) -> String {
        values[language]?[key] ?? values[.english]?[key] ?? key.rawValue
    }

    static func switchTitle(_ kind: SwitchKind, language: AppLanguage) -> String {
        switchTitles[language]?[kind] ?? switchTitles[.english]?[kind] ?? kind.title
    }

    static func menuBarIconTitle(_ icon: MenuBarIcon, language: AppLanguage) -> String {
        menuBarIconTitles[language]?[icon] ?? menuBarIconTitles[.english]?[icon] ?? icon.title
    }

    static func controlsReady(_ count: Int, language: AppLanguage) -> String {
        switch language {
        case .simplifiedChinese:
            return "\(count) 个控制项就绪"
        case .traditionalChinese:
            return "\(count) 個控制項就緒"
        case .spanish:
            return "\(count) controles listos"
        case .japanese:
            return "\(count) 個のコントロールが準備完了"
        case .korean:
            return "\(count)개 제어 항목 준비됨"
        case .german:
            return "\(count) Steuerungen bereit"
        case .french:
            return "\(count) contrôles prêts"
        case .italian:
            return "\(count) controlli pronti"
        case .portuguese:
            return "\(count) controles prontos"
        case .english, .system:
            return "\(count) controls ready"
        }
    }

    static func activeOf(_ active: Int, total: Int, language: AppLanguage) -> String {
        switch language {
        case .simplifiedChinese:
            return "\(active) 个已开启，共 \(total) 个"
        case .traditionalChinese:
            return "\(active) 個已開啟，共 \(total) 個"
        case .spanish:
            return "\(active) activos de \(total)"
        case .japanese:
            return "\(total) 個中 \(active) 個がオン"
        case .korean:
            return "\(total)개 중 \(active)개 켜짐"
        case .german:
            return "\(active) aktiv von \(total)"
        case .french:
            return "\(active) actifs sur \(total)"
        case .italian:
            return "\(active) attivi su \(total)"
        case .portuguese:
            return "\(active) ativos de \(total)"
        case .english, .system:
            return "\(active) active of \(total)"
        }
    }

    static func onBadge(_ count: Int, language: AppLanguage) -> String {
        switch language {
        case .simplifiedChinese:
            return "\(count) 开启"
        case .traditionalChinese:
            return "\(count) 開啟"
        case .spanish:
            return "\(count) activo\(count == 1 ? "" : "s")"
        case .japanese:
            return "\(count) オン"
        case .korean:
            return "\(count) 켜짐"
        case .german:
            return "\(count) an"
        case .french:
            return "\(count) activé\(count == 1 ? "" : "s")"
        case .italian:
            return "\(count) attiv\(count == 1 ? "o" : "i")"
        case .portuguese:
            return "\(count) ligado\(count == 1 ? "" : "s")"
        case .english, .system:
            return count == 1 ? "1 On" : "\(count) On"
        }
    }

    private static let values: [AppLanguage: [L10nKey: String]] = [
        .english: [
            .about: "About",
            .accessibility: "Accessibility",
            .accessibilityGrantedSubtitle: "Granted for Lock Keyboard and Screen Cleaning.",
            .accessibilityRequiredSubtitle: "Required for Lock Keyboard and Screen Cleaning.",
            .activeOf: "active of",
            .application: "Application",
            .approve: "Approve",
            .automation: "Automation",
            .automationSubtitle: "Needed when macOS asks Mac Switch to control System Events, Finder, Music, or Spotify.",
            .bluetooth: "Bluetooth",
            .bluetoothSubtitle: "Used to find and connect paired Bluetooth audio devices.",
            .cancel: "Cancel",
            .checking: "Checking",
            .checkingAccessibilitySubtitle: "Checking permission for Lock Keyboard and Screen Cleaning.",
            .controlsReady: "controls ready",
            .customize: "Customize",
            .followSystem: "Follow System",
            .general: "General",
            .generalSubtitle: "Launch behavior, menu bar appearance, language, and system permissions.",
            .granted: "Granted",
            .language: "Language",
            .languageSubtitle: "Follow macOS, or choose an app language without restarting Mac Switch.",
            .location: "Location",
            .locationSubtitle: "Used only for sunrise/sunset Dark Mode scheduling.",
            .menuBar: "Menu Bar",
            .menuBarIcon: "Menu Bar Icon",
            .menuBarUtility: "Menu bar utility",
            .needsAccess: "Needs Access",
            .noSwitchAdded: "No Switch Added",
            .off: "Off",
            .on: "On",
            .open: "Open",
            .pending: "Pending",
            .permissions: "Permissions",
            .preferences: "Preferences",
            .quit: "Quit",
            .quitMacSwitch: "Quit Mac Switch",
            .repair: "Repair",
            .review: "Review",
            .selectSwitchPrompt: "Please select at least one switch to start Mac Switch.",
            .startAtLogin: "Start at Login",
            .startup: "Startup"
        ],
        .simplifiedChinese: [
            .about: "关于",
            .accessibility: "辅助功能",
            .accessibilityGrantedSubtitle: "已允许锁定键盘和屏幕清洁使用辅助功能。",
            .accessibilityRequiredSubtitle: "锁定键盘和屏幕清洁需要辅助功能权限。",
            .activeOf: "已开启，共",
            .application: "应用",
            .approve: "批准",
            .automation: "自动化",
            .automationSubtitle: "当 macOS 要求 Mac Switch 控制系统事件、访达、音乐或 Spotify 时需要。",
            .bluetooth: "蓝牙",
            .bluetoothSubtitle: "用于查找并连接已配对的蓝牙音频设备。",
            .cancel: "取消",
            .checking: "检查中",
            .checkingAccessibilitySubtitle: "正在检查锁定键盘和屏幕清洁的辅助功能权限。",
            .controlsReady: "控制项就绪",
            .customize: "自定义",
            .followSystem: "跟随系统",
            .general: "通用",
            .generalSubtitle: "启动行为、菜单栏外观、语言和系统权限。",
            .granted: "已允许",
            .language: "语言",
            .languageSubtitle: "跟随 macOS，或无需重启 Mac Switch 直接选择应用语言。",
            .location: "位置",
            .locationSubtitle: "仅用于日出/日落深色模式计划。",
            .menuBar: "菜单栏",
            .menuBarIcon: "菜单栏图标",
            .menuBarUtility: "菜单栏工具",
            .needsAccess: "需要权限",
            .noSwitchAdded: "未添加开关",
            .off: "关",
            .on: "开",
            .open: "打开",
            .pending: "待处理",
            .permissions: "权限",
            .preferences: "设置",
            .quit: "退出",
            .quitMacSwitch: "退出 Mac Switch",
            .repair: "修复",
            .review: "查看",
            .selectSwitchPrompt: "请至少选择一个开关来启动 Mac Switch。",
            .startAtLogin: "登录时启动",
            .startup: "启动"
        ],
        .traditionalChinese: [
            .about: "關於",
            .accessibility: "輔助使用",
            .accessibilityGrantedSubtitle: "已允許鎖定鍵盤和螢幕清潔使用輔助使用。",
            .accessibilityRequiredSubtitle: "鎖定鍵盤和螢幕清潔需要輔助使用權限。",
            .activeOf: "已開啟，共",
            .application: "應用程式",
            .approve: "核准",
            .automation: "自動化",
            .automationSubtitle: "當 macOS 要求 Mac Switch 控制系統事件、Finder、音樂或 Spotify 時需要。",
            .bluetooth: "藍牙",
            .bluetoothSubtitle: "用於尋找並連接已配對的藍牙音訊裝置。",
            .cancel: "取消",
            .checking: "檢查中",
            .checkingAccessibilitySubtitle: "正在檢查鎖定鍵盤和螢幕清潔的輔助使用權限。",
            .controlsReady: "控制項就緒",
            .customize: "自訂",
            .followSystem: "跟隨系統",
            .general: "一般",
            .generalSubtitle: "啟動行為、選單列外觀、語言和系統權限。",
            .granted: "已允許",
            .language: "語言",
            .languageSubtitle: "跟隨 macOS，或無需重新啟動 Mac Switch 直接選擇應用程式語言。",
            .location: "位置",
            .locationSubtitle: "僅用於日出/日落深色模式排程。",
            .menuBar: "選單列",
            .menuBarIcon: "選單列圖示",
            .menuBarUtility: "選單列工具",
            .needsAccess: "需要權限",
            .noSwitchAdded: "尚未加入開關",
            .off: "關",
            .on: "開",
            .open: "開啟",
            .pending: "待處理",
            .permissions: "權限",
            .preferences: "設定",
            .quit: "結束",
            .quitMacSwitch: "結束 Mac Switch",
            .repair: "修復",
            .review: "查看",
            .selectSwitchPrompt: "請至少選擇一個開關來啟動 Mac Switch。",
            .startAtLogin: "登入時啟動",
            .startup: "啟動"
        ],
        .spanish: [
            .about: "Acerca de",
            .accessibility: "Accesibilidad",
            .accessibilityGrantedSubtitle: "Concedido para Bloquear teclado y Limpieza de pantalla.",
            .accessibilityRequiredSubtitle: "Requerido para Bloquear teclado y Limpieza de pantalla.",
            .application: "Aplicación",
            .approve: "Aprobar",
            .automation: "Automatización",
            .automationSubtitle: "Necesario cuando macOS pide a Mac Switch controlar Eventos del Sistema, Finder, Música o Spotify.",
            .bluetooth: "Bluetooth",
            .bluetoothSubtitle: "Se usa para buscar y conectar dispositivos de audio Bluetooth emparejados.",
            .cancel: "Cancelar",
            .checking: "Comprobando",
            .checkingAccessibilitySubtitle: "Comprobando permisos para Bloquear teclado y Limpieza de pantalla.",
            .customize: "Personalizar",
            .followSystem: "Seguir el sistema",
            .general: "General",
            .generalSubtitle: "Inicio, apariencia de la barra de menús, idioma y permisos del sistema.",
            .granted: "Concedido",
            .language: "Idioma",
            .languageSubtitle: "Sigue macOS o elige un idioma de la app sin reiniciar Mac Switch.",
            .location: "Ubicación",
            .locationSubtitle: "Solo se usa para programar Modo oscuro con amanecer/atardecer.",
            .menuBar: "Barra de menús",
            .menuBarIcon: "Icono de la barra",
            .menuBarUtility: "Utilidad de barra de menús",
            .needsAccess: "Necesita acceso",
            .noSwitchAdded: "No hay interruptores",
            .off: "Desactivado",
            .on: "Activado",
            .open: "Abrir",
            .pending: "Pendiente",
            .permissions: "Permisos",
            .preferences: "Preferencias",
            .quit: "Salir",
            .quitMacSwitch: "Salir de Mac Switch",
            .repair: "Reparar",
            .review: "Revisar",
            .selectSwitchPrompt: "Selecciona al menos un interruptor para iniciar Mac Switch.",
            .startAtLogin: "Abrir al iniciar sesión",
            .startup: "Inicio"
        ],
        .japanese: [
            .about: "情報",
            .accessibility: "アクセシビリティ",
            .accessibilityGrantedSubtitle: "キーボードロックと画面クリーニングに許可されています。",
            .accessibilityRequiredSubtitle: "キーボードロックと画面クリーニングに必要です。",
            .application: "アプリ",
            .approve: "承認",
            .automation: "オートメーション",
            .automationSubtitle: "macOS が Mac Switch にシステムイベント、Finder、ミュージック、Spotify の制御を求める場合に必要です。",
            .bluetooth: "Bluetooth",
            .bluetoothSubtitle: "ペアリング済みの Bluetooth オーディオ機器の検索と接続に使用します。",
            .cancel: "キャンセル",
            .checking: "確認中",
            .checkingAccessibilitySubtitle: "キーボードロックと画面クリーニングの権限を確認中です。",
            .customize: "カスタマイズ",
            .followSystem: "システムに合わせる",
            .general: "一般",
            .generalSubtitle: "起動、メニューバー表示、言語、システム権限。",
            .granted: "許可済み",
            .language: "言語",
            .languageSubtitle: "macOS に合わせるか、Mac Switch を再起動せずにアプリの言語を選べます。",
            .location: "位置情報",
            .locationSubtitle: "日の出/日の入りによるダークモードのスケジュールにのみ使用します。",
            .menuBar: "メニューバー",
            .menuBarIcon: "メニューバーアイコン",
            .menuBarUtility: "メニューバーユーティリティ",
            .needsAccess: "アクセスが必要",
            .noSwitchAdded: "スイッチがありません",
            .off: "オフ",
            .on: "オン",
            .open: "開く",
            .pending: "保留中",
            .permissions: "権限",
            .preferences: "設定",
            .quit: "終了",
            .quitMacSwitch: "Mac Switch を終了",
            .repair: "修復",
            .review: "確認",
            .selectSwitchPrompt: "Mac Switch を開始するには、少なくとも 1 つのスイッチを選択してください。",
            .startAtLogin: "ログイン時に起動",
            .startup: "起動"
        ],
        .korean: [
            .about: "정보",
            .accessibility: "손쉬운 사용",
            .accessibilityGrantedSubtitle: "키보드 잠금 및 화면 청소에 허용되었습니다.",
            .accessibilityRequiredSubtitle: "키보드 잠금 및 화면 청소에 필요합니다.",
            .application: "앱",
            .approve: "승인",
            .automation: "자동화",
            .automationSubtitle: "macOS가 Mac Switch에 시스템 이벤트, Finder, 음악 또는 Spotify 제어를 요청할 때 필요합니다.",
            .bluetooth: "Bluetooth",
            .bluetoothSubtitle: "페어링된 Bluetooth 오디오 기기를 찾고 연결하는 데 사용합니다.",
            .cancel: "취소",
            .checking: "확인 중",
            .checkingAccessibilitySubtitle: "키보드 잠금 및 화면 청소 권한을 확인 중입니다.",
            .customize: "사용자화",
            .followSystem: "시스템 따르기",
            .general: "일반",
            .generalSubtitle: "실행 동작, 메뉴 막대 모양, 언어 및 시스템 권한.",
            .granted: "허용됨",
            .language: "언어",
            .languageSubtitle: "macOS를 따르거나 Mac Switch를 재시작하지 않고 앱 언어를 선택합니다.",
            .location: "위치",
            .locationSubtitle: "일출/일몰 다크 모드 예약에만 사용합니다.",
            .menuBar: "메뉴 막대",
            .menuBarIcon: "메뉴 막대 아이콘",
            .menuBarUtility: "메뉴 막대 유틸리티",
            .needsAccess: "권한 필요",
            .noSwitchAdded: "스위치 없음",
            .off: "끔",
            .on: "켬",
            .open: "열기",
            .pending: "대기 중",
            .permissions: "권한",
            .preferences: "설정",
            .quit: "종료",
            .quitMacSwitch: "Mac Switch 종료",
            .repair: "복구",
            .review: "검토",
            .selectSwitchPrompt: "Mac Switch를 시작하려면 하나 이상의 스위치를 선택하세요.",
            .startAtLogin: "로그인 시 시작",
            .startup: "시작"
        ],
        .german: [
            .about: "Info",
            .accessibility: "Bedienungshilfen",
            .accessibilityGrantedSubtitle: "Für Tastatur sperren und Bildschirmreinigung erlaubt.",
            .accessibilityRequiredSubtitle: "Für Tastatur sperren und Bildschirmreinigung erforderlich.",
            .application: "App",
            .approve: "Genehmigen",
            .automation: "Automation",
            .automationSubtitle: "Erforderlich, wenn macOS Mac Switch die Steuerung von System Events, Finder, Musik oder Spotify erlaubt.",
            .bluetooth: "Bluetooth",
            .bluetoothSubtitle: "Wird verwendet, um gekoppelte Bluetooth-Audiogeräte zu finden und zu verbinden.",
            .cancel: "Abbrechen",
            .checking: "Prüfen",
            .checkingAccessibilitySubtitle: "Berechtigung für Tastatur sperren und Bildschirmreinigung wird geprüft.",
            .customize: "Anpassen",
            .followSystem: "System folgen",
            .general: "Allgemein",
            .generalSubtitle: "Startverhalten, Menüleistenoptik, Sprache und Systemberechtigungen.",
            .granted: "Erlaubt",
            .language: "Sprache",
            .languageSubtitle: "macOS folgen oder eine App-Sprache ohne Neustart von Mac Switch wählen.",
            .location: "Standort",
            .locationSubtitle: "Nur für Dunkelmodus-Zeitpläne nach Sonnenaufgang/Sonnenuntergang.",
            .menuBar: "Menüleiste",
            .menuBarIcon: "Menüleistensymbol",
            .menuBarUtility: "Menüleisten-Tool",
            .needsAccess: "Zugriff nötig",
            .noSwitchAdded: "Kein Schalter hinzugefügt",
            .off: "Aus",
            .on: "Ein",
            .open: "Öffnen",
            .pending: "Ausstehend",
            .permissions: "Berechtigungen",
            .preferences: "Einstellungen",
            .quit: "Beenden",
            .quitMacSwitch: "Mac Switch beenden",
            .repair: "Reparieren",
            .review: "Prüfen",
            .selectSwitchPrompt: "Bitte wähle mindestens einen Schalter, um Mac Switch zu starten.",
            .startAtLogin: "Beim Anmelden starten",
            .startup: "Start"
        ],
        .french: [
            .about: "À propos",
            .accessibility: "Accessibilité",
            .accessibilityGrantedSubtitle: "Autorisé pour Verrouiller le clavier et Nettoyage de l’écran.",
            .accessibilityRequiredSubtitle: "Requis pour Verrouiller le clavier et Nettoyage de l’écran.",
            .application: "Application",
            .approve: "Approuver",
            .automation: "Automatisation",
            .automationSubtitle: "Nécessaire lorsque macOS demande à Mac Switch de contrôler Événements système, Finder, Musique ou Spotify.",
            .bluetooth: "Bluetooth",
            .bluetoothSubtitle: "Utilisé pour trouver et connecter des appareils audio Bluetooth jumelés.",
            .cancel: "Annuler",
            .checking: "Vérification",
            .customize: "Personnaliser",
            .checkingAccessibilitySubtitle: "Vérification de l’autorisation pour Verrouiller le clavier et Nettoyage de l’écran.",
            .followSystem: "Suivre le système",
            .general: "Général",
            .generalSubtitle: "Démarrage, apparence de la barre de menus, langue et autorisations système.",
            .granted: "Autorisé",
            .language: "Langue",
            .languageSubtitle: "Suivre macOS ou choisir une langue d’app sans redémarrer Mac Switch.",
            .location: "Localisation",
            .locationSubtitle: "Utilisé uniquement pour la programmation du mode sombre au lever/coucher du soleil.",
            .menuBar: "Barre de menus",
            .menuBarIcon: "Icône de la barre",
            .menuBarUtility: "Utilitaire de barre de menus",
            .needsAccess: "Accès requis",
            .noSwitchAdded: "Aucun interrupteur ajouté",
            .off: "Désactivé",
            .on: "Activé",
            .open: "Ouvrir",
            .pending: "En attente",
            .permissions: "Autorisations",
            .preferences: "Préférences",
            .quit: "Quitter",
            .quitMacSwitch: "Quitter Mac Switch",
            .repair: "Réparer",
            .review: "Vérifier",
            .selectSwitchPrompt: "Sélectionnez au moins un interrupteur pour démarrer Mac Switch.",
            .startAtLogin: "Ouvrir à la connexion",
            .startup: "Démarrage"
        ],
        .italian: [
            .about: "Info",
            .accessibility: "Accessibilità",
            .accessibilityGrantedSubtitle: "Consentito per Blocca tastiera e Pulizia schermo.",
            .accessibilityRequiredSubtitle: "Richiesto per Blocca tastiera e Pulizia schermo.",
            .application: "App",
            .approve: "Approva",
            .automation: "Automazione",
            .automationSubtitle: "Necessario quando macOS chiede a Mac Switch di controllare Eventi di Sistema, Finder, Musica o Spotify.",
            .bluetooth: "Bluetooth",
            .bluetoothSubtitle: "Usato per trovare e connettere dispositivi audio Bluetooth abbinati.",
            .cancel: "Annulla",
            .checking: "Controllo",
            .checkingAccessibilitySubtitle: "Controllo dei permessi per Blocca tastiera e Pulizia schermo.",
            .customize: "Personalizza",
            .followSystem: "Segui il sistema",
            .general: "Generali",
            .generalSubtitle: "Avvio, aspetto della barra dei menu, lingua e permessi di sistema.",
            .granted: "Consentito",
            .language: "Lingua",
            .languageSubtitle: "Segui macOS o scegli una lingua dell’app senza riavviare Mac Switch.",
            .location: "Posizione",
            .locationSubtitle: "Usata solo per programmare la modalità scura con alba/tramonto.",
            .menuBar: "Barra dei menu",
            .menuBarIcon: "Icona nella barra menu",
            .menuBarUtility: "Utility barra dei menu",
            .needsAccess: "Accesso richiesto",
            .noSwitchAdded: "Nessun interruttore aggiunto",
            .off: "Disattivo",
            .on: "Attivo",
            .open: "Apri",
            .pending: "In sospeso",
            .permissions: "Permessi",
            .preferences: "Preferenze",
            .quit: "Esci",
            .quitMacSwitch: "Esci da Mac Switch",
            .repair: "Ripara",
            .review: "Rivedi",
            .selectSwitchPrompt: "Seleziona almeno un interruttore per avviare Mac Switch.",
            .startAtLogin: "Apri al login",
            .startup: "Avvio"
        ],
        .portuguese: [
            .about: "Sobre",
            .accessibility: "Acessibilidade",
            .accessibilityGrantedSubtitle: "Concedido para Bloquear teclado e Limpeza de tela.",
            .accessibilityRequiredSubtitle: "Necessário para Bloquear teclado e Limpeza de tela.",
            .application: "Aplicativo",
            .approve: "Aprovar",
            .automation: "Automação",
            .automationSubtitle: "Necessário quando o macOS pede ao Mac Switch para controlar Eventos do Sistema, Finder, Música ou Spotify.",
            .bluetooth: "Bluetooth",
            .bluetoothSubtitle: "Usado para encontrar e conectar dispositivos de áudio Bluetooth emparelhados.",
            .cancel: "Cancelar",
            .checking: "Verificando",
            .checkingAccessibilitySubtitle: "Verificando permissão para Bloquear teclado e Limpeza de tela.",
            .customize: "Personalizar",
            .followSystem: "Seguir o sistema",
            .general: "Geral",
            .generalSubtitle: "Inicialização, aparência da barra de menus, idioma e permissões do sistema.",
            .granted: "Concedido",
            .language: "Idioma",
            .languageSubtitle: "Siga o macOS ou escolha um idioma do app sem reiniciar o Mac Switch.",
            .location: "Localização",
            .locationSubtitle: "Usado apenas para programar Modo Escuro por nascer/pôr do sol.",
            .menuBar: "Barra de menus",
            .menuBarIcon: "Ícone da barra de menus",
            .menuBarUtility: "Utilitário da barra de menus",
            .needsAccess: "Acesso necessário",
            .noSwitchAdded: "Nenhum controle adicionado",
            .off: "Desligado",
            .on: "Ligado",
            .open: "Abrir",
            .pending: "Pendente",
            .permissions: "Permissões",
            .preferences: "Preferências",
            .quit: "Sair",
            .quitMacSwitch: "Sair do Mac Switch",
            .repair: "Reparar",
            .review: "Revisar",
            .selectSwitchPrompt: "Selecione pelo menos um controle para iniciar o Mac Switch.",
            .startAtLogin: "Abrir ao iniciar sessão",
            .startup: "Inicialização"
        ]
    ]

    private static let switchTitles: [AppLanguage: [SwitchKind: String]] = [
        .english: SwitchKind.allCases.reduce(into: [:]) { result, kind in result[kind] = kind.title },
        .simplifiedChinese: [
            .stageManager: "台前调度", .hideWidgets: "隐藏小组件", .muteMicrophone: "静音麦克风",
            .hideDesktopIcons: "隐藏桌面图标", .darkMode: "深色模式", .keepAwake: "保持唤醒",
            .screenSaver: "屏幕保护程序", .bluetoothAudio: "蓝牙音频", .doNotDisturb: "勿扰模式",
            .nightShift: "夜览", .trueTone: "原彩显示", .playMusic: "播放音乐",
            .showHiddenFiles: "显示隐藏文件", .displaySleep: "显示器睡眠", .screenResolution: "屏幕分辨率",
            .screenClean: "屏幕清洁", .lockKeyboard: "锁定键盘", .lockScreen: "锁定屏幕",
            .xcodeClean: "清理 Xcode 缓存", .emptyTrash: "清空废纸篓", .ejectDisk: "推出磁盘",
            .emptyPasteboard: "清空剪贴板", .hideWindows: "隐藏窗口", .hideDock: "隐藏 Dock",
            .lowPowerMode: "低电量模式", .energyMode: "能耗模式"
        ],
        .traditionalChinese: [
            .stageManager: "幕前調度", .hideWidgets: "隱藏小工具", .muteMicrophone: "麥克風靜音",
            .hideDesktopIcons: "隱藏桌面圖示", .darkMode: "深色模式", .keepAwake: "保持喚醒",
            .screenSaver: "螢幕保護程式", .bluetoothAudio: "藍牙音訊", .doNotDisturb: "勿擾模式",
            .nightShift: "Night Shift", .trueTone: "原彩顯示", .playMusic: "播放音樂",
            .showHiddenFiles: "顯示隱藏檔案", .displaySleep: "顯示器睡眠", .screenResolution: "螢幕解析度",
            .screenClean: "螢幕清潔", .lockKeyboard: "鎖定鍵盤", .lockScreen: "鎖定螢幕",
            .xcodeClean: "清理 Xcode 快取", .emptyTrash: "清空垃圾桶", .ejectDisk: "退出磁碟",
            .emptyPasteboard: "清空剪貼板", .hideWindows: "隱藏視窗", .hideDock: "隱藏 Dock",
            .lowPowerMode: "低耗電模式", .energyMode: "能源模式"
        ],
        .spanish: [
            .stageManager: "Organizador visual", .hideWidgets: "Ocultar widgets", .muteMicrophone: "Silenciar micrófono",
            .hideDesktopIcons: "Ocultar iconos del escritorio", .darkMode: "Modo oscuro", .keepAwake: "Mantener despierto",
            .screenSaver: "Salvapantallas", .bluetoothAudio: "Audio Bluetooth", .doNotDisturb: "No molestar",
            .nightShift: "Night Shift", .trueTone: "True Tone", .playMusic: "Reproducir música",
            .showHiddenFiles: "Mostrar archivos ocultos", .displaySleep: "Reposo de pantalla", .screenResolution: "Resolución",
            .screenClean: "Limpieza de pantalla", .lockKeyboard: "Bloquear teclado", .lockScreen: "Bloquear pantalla",
            .xcodeClean: "Limpiar caché de Xcode", .emptyTrash: "Vaciar papelera", .ejectDisk: "Expulsar disco",
            .emptyPasteboard: "Vaciar portapapeles", .hideWindows: "Ocultar ventanas", .hideDock: "Ocultar Dock",
            .lowPowerMode: "Modo de bajo consumo", .energyMode: "Modo de energía"
        ],
        .japanese: [
            .stageManager: "ステージマネージャ", .hideWidgets: "ウィジェットを隠す", .muteMicrophone: "マイクをミュート",
            .hideDesktopIcons: "デスクトップアイコンを隠す", .darkMode: "ダークモード", .keepAwake: "スリープ防止",
            .screenSaver: "スクリーンセーバ", .bluetoothAudio: "Bluetooth オーディオ", .doNotDisturb: "集中モード",
            .nightShift: "Night Shift", .trueTone: "True Tone", .playMusic: "音楽を再生",
            .showHiddenFiles: "隠しファイルを表示", .displaySleep: "ディスプレイスリープ", .screenResolution: "画面解像度",
            .screenClean: "画面クリーニング", .lockKeyboard: "キーボードロック", .lockScreen: "画面をロック",
            .xcodeClean: "Xcode キャッシュ削除", .emptyTrash: "ゴミ箱を空にする", .ejectDisk: "ディスクを取り出す",
            .emptyPasteboard: "ペーストボードを消去", .hideWindows: "ウインドウを隠す", .hideDock: "Dock を隠す",
            .lowPowerMode: "低電力モード", .energyMode: "エネルギーモード"
        ],
        .korean: [
            .stageManager: "스테이지 매니저", .hideWidgets: "위젯 숨기기", .muteMicrophone: "마이크 음소거",
            .hideDesktopIcons: "데스크탑 아이콘 숨기기", .darkMode: "다크 모드", .keepAwake: "잠자기 방지",
            .screenSaver: "화면 보호기", .bluetoothAudio: "Bluetooth 오디오", .doNotDisturb: "방해금지 모드",
            .nightShift: "Night Shift", .trueTone: "True Tone", .playMusic: "음악 재생",
            .showHiddenFiles: "숨김 파일 표시", .displaySleep: "디스플레이 잠자기", .screenResolution: "화면 해상도",
            .screenClean: "화면 청소", .lockKeyboard: "키보드 잠금", .lockScreen: "화면 잠금",
            .xcodeClean: "Xcode 캐시 정리", .emptyTrash: "휴지통 비우기", .ejectDisk: "디스크 추출",
            .emptyPasteboard: "클립보드 비우기", .hideWindows: "윈도우 숨기기", .hideDock: "Dock 숨기기",
            .lowPowerMode: "저전력 모드", .energyMode: "에너지 모드"
        ],
        .german: [
            .stageManager: "Stage Manager", .hideWidgets: "Widgets ausblenden", .muteMicrophone: "Mikrofon stummschalten",
            .hideDesktopIcons: "Schreibtischsymbole ausblenden", .darkMode: "Dunkelmodus", .keepAwake: "Wach halten",
            .screenSaver: "Bildschirmschoner", .bluetoothAudio: "Bluetooth-Audio", .doNotDisturb: "Nicht stören",
            .nightShift: "Night Shift", .trueTone: "True Tone", .playMusic: "Musik abspielen",
            .showHiddenFiles: "Versteckte Dateien anzeigen", .displaySleep: "Display-Ruhezustand", .screenResolution: "Bildschirmauflösung",
            .screenClean: "Bildschirmreinigung", .lockKeyboard: "Tastatur sperren", .lockScreen: "Bildschirm sperren",
            .xcodeClean: "Xcode-Cache bereinigen", .emptyTrash: "Papierkorb leeren", .ejectDisk: "Medium auswerfen",
            .emptyPasteboard: "Zwischenablage leeren", .hideWindows: "Fenster ausblenden", .hideDock: "Dock ausblenden",
            .lowPowerMode: "Stromsparmodus", .energyMode: "Energiemodus"
        ],
        .french: [
            .stageManager: "Stage Manager", .hideWidgets: "Masquer les widgets", .muteMicrophone: "Couper le micro",
            .hideDesktopIcons: "Masquer les icônes du bureau", .darkMode: "Mode sombre", .keepAwake: "Garder éveillé",
            .screenSaver: "Économiseur d’écran", .bluetoothAudio: "Audio Bluetooth", .doNotDisturb: "Ne pas déranger",
            .nightShift: "Night Shift", .trueTone: "True Tone", .playMusic: "Lire la musique",
            .showHiddenFiles: "Afficher les fichiers cachés", .displaySleep: "Veille de l’écran", .screenResolution: "Résolution d’écran",
            .screenClean: "Nettoyage de l’écran", .lockKeyboard: "Verrouiller le clavier", .lockScreen: "Verrouiller l’écran",
            .xcodeClean: "Nettoyer le cache Xcode", .emptyTrash: "Vider la corbeille", .ejectDisk: "Éjecter le disque",
            .emptyPasteboard: "Vider le presse-papiers", .hideWindows: "Masquer les fenêtres", .hideDock: "Masquer le Dock",
            .lowPowerMode: "Mode économie d’énergie", .energyMode: "Mode énergie"
        ],
        .italian: [
            .stageManager: "Stage Manager", .hideWidgets: "Nascondi widget", .muteMicrophone: "Disattiva microfono",
            .hideDesktopIcons: "Nascondi icone scrivania", .darkMode: "Modalità scura", .keepAwake: "Tieni attivo",
            .screenSaver: "Salvaschermo", .bluetoothAudio: "Audio Bluetooth", .doNotDisturb: "Non disturbare",
            .nightShift: "Night Shift", .trueTone: "True Tone", .playMusic: "Riproduci musica",
            .showHiddenFiles: "Mostra file nascosti", .displaySleep: "Stop schermo", .screenResolution: "Risoluzione schermo",
            .screenClean: "Pulizia schermo", .lockKeyboard: "Blocca tastiera", .lockScreen: "Blocca schermo",
            .xcodeClean: "Pulisci cache Xcode", .emptyTrash: "Svuota cestino", .ejectDisk: "Espelli disco",
            .emptyPasteboard: "Svuota appunti", .hideWindows: "Nascondi finestre", .hideDock: "Nascondi Dock",
            .lowPowerMode: "Risparmio energetico", .energyMode: "Modalità energia"
        ],
        .portuguese: [
            .stageManager: "Organizador Visual", .hideWidgets: "Ocultar widgets", .muteMicrophone: "Silenciar microfone",
            .hideDesktopIcons: "Ocultar ícones da mesa", .darkMode: "Modo Escuro", .keepAwake: "Manter acordado",
            .screenSaver: "Protetor de tela", .bluetoothAudio: "Áudio Bluetooth", .doNotDisturb: "Não Perturbe",
            .nightShift: "Night Shift", .trueTone: "True Tone", .playMusic: "Reproduzir música",
            .showHiddenFiles: "Mostrar arquivos ocultos", .displaySleep: "Repouso da tela", .screenResolution: "Resolução da tela",
            .screenClean: "Limpeza de tela", .lockKeyboard: "Bloquear teclado", .lockScreen: "Bloquear tela",
            .xcodeClean: "Limpar cache do Xcode", .emptyTrash: "Esvaziar lixo", .ejectDisk: "Ejetar disco",
            .emptyPasteboard: "Limpar área de transferência", .hideWindows: "Ocultar janelas", .hideDock: "Ocultar Dock",
            .lowPowerMode: "Modo Pouca Energia", .energyMode: "Modo de energia"
        ]
    ]

    private static let menuBarIconTitles: [AppLanguage: [MenuBarIcon: String]] = [
        .english: MenuBarIcon.allCases.reduce(into: [:]) { result, icon in result[icon] = icon.title },
        .simplifiedChinese: [.switches: "开关", .sliders: "平衡", .grid: "网格", .power: "脉冲", .command: "轨道", .sparkles: "星光"],
        .traditionalChinese: [.switches: "開關", .sliders: "平衡", .grid: "格狀", .power: "脈衝", .command: "軌道", .sparkles: "星光"],
        .spanish: [.switches: "Interruptores", .sliders: "Balance", .grid: "Mosaico", .power: "Pulso", .command: "Órbita", .sparkles: "Brillo"],
        .japanese: [.switches: "スイッチ", .sliders: "バランス", .grid: "タイル", .power: "パルス", .command: "軌道", .sparkles: "きらめき"],
        .korean: [.switches: "스위치", .sliders: "밸런스", .grid: "타일", .power: "펄스", .command: "궤도", .sparkles: "스파크"],
        .german: [.switches: "Schalter", .sliders: "Balance", .grid: "Kacheln", .power: "Impuls", .command: "Orbit", .sparkles: "Funkeln"],
        .french: [.switches: "Interrupteurs", .sliders: "Balance", .grid: "Tuiles", .power: "Impulsion", .command: "Orbite", .sparkles: "Éclat"],
        .italian: [.switches: "Interruttori", .sliders: "Bilancia", .grid: "Riquadri", .power: "Impulso", .command: "Orbita", .sparkles: "Scintilla"],
        .portuguese: [.switches: "Controles", .sliders: "Equilíbrio", .grid: "Blocos", .power: "Pulso", .command: "Órbita", .sparkles: "Brilho"]
    ]
}
