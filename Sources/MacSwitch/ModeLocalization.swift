import Foundation

enum ModeL10nKey: String, CaseIterable, Sendable {
    case active
    case addMode
    case addSwitchBeforeShowing
    case addSwitchBeforeStarting
    case closeModeSettings
    case createModePrompt
    case customMode
    case customWorkflow
    case deleteActiveModeMessage
    case deleteMode
    case deleteModeIrreversible
    case deleteModeTitle
    case descriptionLabel
    case finishBeforeTurningOff
    case finishSwitchBeforeChanging
    case hidden
    case icon
    case macOSDidNotReachState
    case modeIconAwake
    case modeIconControls
    case modeIconDisplay
    case modeIconNight
    case modeIconPeople
    case modeIconStack
    case modeIconTarget
    case modeIconWindows
    case modeIconWork
    case modeLibrary
    case modeSettings
    case name
    case noModesYet
    case restoreFailed
    case restoreThenDelete
    case restoringBeforeDeletion
    case save
    case showModeInMenu
    case shownInMenu
    case skippedUnavailable
    case startFailedRestored
    case startPartialRestoreFailed
    case switchTargets
    case turnOffAndDelete
    case turnOffBeforeEditing
    case turnOffBeforeHiding
    case turnOffCurrentBeforeStarting
    case unavailableToStart
    case updating
    case waitBeforeDeleting
}

enum ModeL10n {
    static func hasExplicitTranslation(_ key: ModeL10nKey, language: AppLanguage) -> Bool {
        values[language]?[key]?.isEmpty == false
    }

    static func text(_ key: ModeL10nKey, language: AppLanguage) -> String {
        values[language]?[key] ?? values[.english]?[key] ?? key.rawValue
    }

    static func formatted(
        _ key: ModeL10nKey,
        language: AppLanguage,
        arguments: [any CVarArg]
    ) -> String {
        String(
            format: text(key, language: language),
            locale: Locale(identifier: language.localeIdentifier),
            arguments: arguments
        )
    }

    static func modesInMenu(_ count: Int, language: AppLanguage) -> String {
        switch language {
        case .simplifiedChinese: return "菜单中有 \(count) 个"
        case .traditionalChinese: return "選單中有 \(count) 個"
        case .spanish: return "\(count) en el menú"
        case .japanese: return "メニューに \(count) 個"
        case .korean: return "메뉴에 \(count)개"
        case .german: return "\(count) im Menü"
        case .french: return "\(count) dans le menu"
        case .italian: return "\(count) nel menu"
        case .portuguese: return "\(count) no menu"
        case .english, .system: return "\(count) in menu"
        }
    }

    static func modeCount(_ count: Int, language: AppLanguage) -> String {
        switch language {
        case .simplifiedChinese: return "共 \(count) 个模式"
        case .traditionalChinese: return "共 \(count) 個模式"
        case .spanish: return count == 1 ? "1 modo" : "\(count) modos"
        case .japanese: return "\(count) 個のモード"
        case .korean: return "모드 \(count)개"
        case .german: return count == 1 ? "1 Modus" : "\(count) Modi"
        case .french: return count == 1 ? "1 mode" : "\(count) modes"
        case .italian: return count == 1 ? "1 modalità" : "\(count) modalità"
        case .portuguese: return count == 1 ? "1 modo" : "\(count) modos"
        case .english, .system: return count == 1 ? "1 mode" : "\(count) modes"
        }
    }

    static func selectedCount(_ count: Int, language: AppLanguage) -> String {
        switch language {
        case .simplifiedChinese: return "已选择 \(count) 个"
        case .traditionalChinese: return "已選取 \(count) 個"
        case .spanish: return "\(count) seleccionados"
        case .japanese: return "\(count) 個を選択"
        case .korean: return "\(count)개 선택됨"
        case .german: return "\(count) ausgewählt"
        case .french: return "\(count) sélectionnés"
        case .italian: return "\(count) selezionati"
        case .portuguese: return "\(count) selecionados"
        case .english, .system: return "\(count) selected"
        }
    }

    private static let values: [AppLanguage: [ModeL10nKey: String]] = [
        .english: [
            .active: "Active",
            .addMode: "Add Mode",
            .addSwitchBeforeShowing: "Add at least one switch to \"%@\" before showing this mode.",
            .addSwitchBeforeStarting: "Add at least one switch to \"%@\" before starting this mode.",
            .closeModeSettings: "Close mode settings",
            .createModePrompt: "Create a mode and choose the switches that fit your workflow.",
            .customMode: "Custom Mode",
            .customWorkflow: "Custom workflow",
            .deleteActiveModeMessage: "Mac Switch will restore the switch states from before this mode was activated, then delete it.",
            .deleteMode: "Delete Mode",
            .deleteModeIrreversible: "This mode cannot be recovered.",
            .deleteModeTitle: "Delete \"%@\"?",
            .descriptionLabel: "Description",
            .finishBeforeTurningOff: "Finish the current switch update before turning off this mode.",
            .finishSwitchBeforeChanging: "Finish the current switch update before changing modes.",
            .hidden: "Hidden",
            .icon: "Icon",
            .macOSDidNotReachState: "macOS did not reach the requested state",
            .modeIconAwake: "Awake",
            .modeIconControls: "Controls",
            .modeIconDisplay: "Display",
            .modeIconNight: "Night",
            .modeIconPeople: "People",
            .modeIconStack: "Stack",
            .modeIconTarget: "Target",
            .modeIconWindows: "Windows",
            .modeIconWork: "Work",
            .modeLibrary: "Mode Library",
            .modeSettings: "Mode settings",
            .name: "Name",
            .noModesYet: "No modes yet",
            .restoreFailed: "Mode \"%1$@\" could not fully restore its previous state. Retry turning it off. %2$@",
            .restoreThenDelete: "Restore its previous states, then delete this mode",
            .restoringBeforeDeletion: "Restoring before deletion...",
            .save: "Save",
            .showModeInMenu: "Show this mode in the menu",
            .shownInMenu: "Shown in menu",
            .skippedUnavailable: "Mode \"%1$@\" skipped unavailable switches: %2$@.",
            .startFailedRestored: "Mode \"%1$@\" could not start; its changes were restored. %2$@",
            .startPartialRestoreFailed: "Mode \"%1$@\" started only partially and could not fully restore its changes. Turn it off to retry. %2$@",
            .switchTargets: "Switch targets",
            .turnOffAndDelete: "Turn Off & Delete",
            .turnOffBeforeEditing: "Turn this mode off before editing its switches.",
            .turnOffBeforeHiding: "Turn this mode off before hiding it from the menu.",
            .turnOffCurrentBeforeStarting: "Turn off the current mode before starting another mode.",
            .unavailableToStart: "Mode \"%@\" could not start because none of its switches are available.",
            .updating: "Updating...",
            .waitBeforeDeleting: "Wait for the current mode operation to finish before deleting it."
        ],
        .simplifiedChinese: [
            .active: "已启用", .addMode: "添加模式",
            .addSwitchBeforeShowing: "请先为“%@”添加至少一个开关，再将此模式显示在菜单中。",
            .addSwitchBeforeStarting: "请先为“%@”添加至少一个开关，再启动此模式。",
            .closeModeSettings: "关闭模式设置", .createModePrompt: "创建一个模式，并选择适合你工作流程的开关。",
            .customMode: "自定义模式", .customWorkflow: "自定义工作流程",
            .deleteActiveModeMessage: "Mac Switch 将先恢复此模式启用前的开关状态，然后将其删除。",
            .deleteMode: "删除模式", .deleteModeIrreversible: "此模式删除后无法恢复。", .deleteModeTitle: "删除“%@”？",
            .descriptionLabel: "描述", .finishBeforeTurningOff: "请等待当前开关更新完成后再关闭此模式。",
            .finishSwitchBeforeChanging: "请等待当前开关更新完成后再切换模式。", .hidden: "已隐藏", .icon: "图标",
            .macOSDidNotReachState: "macOS 未能切换到请求的状态",
            .modeIconAwake: "唤醒", .modeIconControls: "控制", .modeIconDisplay: "显示器", .modeIconNight: "夜间",
            .modeIconPeople: "人员", .modeIconStack: "堆叠", .modeIconTarget: "目标", .modeIconWindows: "窗口", .modeIconWork: "工作",
            .modeLibrary: "模式库", .modeSettings: "模式设置", .name: "名称", .noModesYet: "暂无模式",
            .restoreFailed: "模式“%1$@”未能完全恢复之前的状态。请再次尝试关闭。%2$@",
            .restoreThenDelete: "先恢复之前的状态，再删除此模式", .restoringBeforeDeletion: "正在恢复后删除...", .save: "保存",
            .showModeInMenu: "在菜单中显示此模式", .shownInMenu: "显示在菜单中",
            .skippedUnavailable: "模式“%1$@”已跳过不可用的开关：%2$@。",
            .startFailedRestored: "模式“%1$@”无法启动；已恢复其更改。%2$@",
            .startPartialRestoreFailed: "模式“%1$@”仅部分启动，且未能完全恢复更改。请关闭此模式后重试。%2$@",
            .switchTargets: "开关目标", .turnOffAndDelete: "关闭并删除",
            .turnOffBeforeEditing: "请先关闭此模式，再编辑其中的开关。", .turnOffBeforeHiding: "请先关闭此模式，再将其从菜单中隐藏。",
            .turnOffCurrentBeforeStarting: "请先关闭当前模式，再启动另一个模式。",
            .unavailableToStart: "模式“%@”无法启动，因为其中没有可用的开关。", .updating: "正在更新...",
            .waitBeforeDeleting: "请等待当前模式操作完成后再删除。"
        ],
        .traditionalChinese: [
            .active: "已啟用", .addMode: "加入模式",
            .addSwitchBeforeShowing: "請先為「%@」加入至少一個開關，再將此模式顯示於選單中。",
            .addSwitchBeforeStarting: "請先為「%@」加入至少一個開關，再啟動此模式。",
            .closeModeSettings: "關閉模式設定", .createModePrompt: "建立模式，並選擇適合工作流程的開關。",
            .customMode: "自訂模式", .customWorkflow: "自訂工作流程",
            .deleteActiveModeMessage: "Mac Switch 會先還原啟用此模式前的開關狀態，再將其刪除。",
            .deleteMode: "刪除模式", .deleteModeIrreversible: "此模式刪除後無法復原。", .deleteModeTitle: "刪除「%@」？",
            .descriptionLabel: "描述", .finishBeforeTurningOff: "請等待目前的開關更新完成後再關閉此模式。",
            .finishSwitchBeforeChanging: "請等待目前的開關更新完成後再切換模式。", .hidden: "已隱藏", .icon: "圖示",
            .macOSDidNotReachState: "macOS 未能切換至要求的狀態",
            .modeIconAwake: "喚醒", .modeIconControls: "控制", .modeIconDisplay: "顯示器", .modeIconNight: "夜間",
            .modeIconPeople: "人員", .modeIconStack: "堆疊", .modeIconTarget: "目標", .modeIconWindows: "視窗", .modeIconWork: "工作",
            .modeLibrary: "模式資料庫", .modeSettings: "模式設定", .name: "名稱", .noModesYet: "尚無模式",
            .restoreFailed: "模式「%1$@」未能完整還原先前狀態。請再次嘗試關閉。%2$@",
            .restoreThenDelete: "先還原先前狀態，再刪除此模式", .restoringBeforeDeletion: "正在還原後刪除...", .save: "儲存",
            .showModeInMenu: "在選單中顯示此模式", .shownInMenu: "顯示於選單中",
            .skippedUnavailable: "模式「%1$@」已略過無法使用的開關：%2$@。",
            .startFailedRestored: "模式「%1$@」無法啟動；已還原其變更。%2$@",
            .startPartialRestoreFailed: "模式「%1$@」僅部分啟動，且未能完整還原變更。請關閉後重試。%2$@",
            .switchTargets: "開關目標", .turnOffAndDelete: "關閉並刪除",
            .turnOffBeforeEditing: "請先關閉此模式，再編輯其中的開關。", .turnOffBeforeHiding: "請先關閉此模式，再從選單隱藏。",
            .turnOffCurrentBeforeStarting: "請先關閉目前模式，再啟動另一個模式。",
            .unavailableToStart: "模式「%@」無法啟動，因為其中沒有可用的開關。", .updating: "正在更新...",
            .waitBeforeDeleting: "請等待目前的模式操作完成後再刪除。"
        ],
        .spanish: [
            .active: "Activo", .addMode: "Añadir modo", .addSwitchBeforeShowing: "Añade al menos un control a «%@» antes de mostrar este modo.",
            .addSwitchBeforeStarting: "Añade al menos un control a «%@» antes de iniciar este modo.", .closeModeSettings: "Cerrar ajustes del modo",
            .createModePrompt: "Crea un modo y elige los controles adecuados para tu flujo de trabajo.", .customMode: "Modo personalizado",
            .customWorkflow: "Flujo personalizado", .deleteActiveModeMessage: "Mac Switch restaurará los estados anteriores y después eliminará este modo.",
            .deleteMode: "Eliminar modo", .deleteModeIrreversible: "Este modo no se puede recuperar.", .deleteModeTitle: "¿Eliminar «%@»?",
            .descriptionLabel: "Descripción", .finishBeforeTurningOff: "Espera a que termine la actualización antes de desactivar este modo.",
            .finishSwitchBeforeChanging: "Espera a que termine la actualización antes de cambiar de modo.", .hidden: "Oculto", .icon: "Icono",
            .macOSDidNotReachState: "macOS no alcanzó el estado solicitado", .modeIconAwake: "Activo", .modeIconControls: "Controles",
            .modeIconDisplay: "Pantalla", .modeIconNight: "Noche", .modeIconPeople: "Personas", .modeIconStack: "Pila",
            .modeIconTarget: "Objetivo", .modeIconWindows: "Ventanas", .modeIconWork: "Trabajo", .modeLibrary: "Biblioteca de modos",
            .modeSettings: "Ajustes del modo", .name: "Nombre", .noModesYet: "Aún no hay modos",
            .restoreFailed: "El modo «%1$@» no pudo restaurar por completo su estado anterior. Intenta desactivarlo de nuevo. %2$@",
            .restoreThenDelete: "Restaurar los estados anteriores y eliminar el modo", .restoringBeforeDeletion: "Restaurando antes de eliminar...",
            .save: "Guardar", .showModeInMenu: "Mostrar este modo en el menú", .shownInMenu: "Visible en el menú",
            .skippedUnavailable: "El modo «%1$@» omitió controles no disponibles: %2$@.",
            .startFailedRestored: "El modo «%1$@» no pudo iniciarse; se restauraron sus cambios. %2$@",
            .startPartialRestoreFailed: "El modo «%1$@» se inició parcialmente y no pudo restaurar todos sus cambios. Desactívalo para volver a intentarlo. %2$@",
            .switchTargets: "Estados de los controles", .turnOffAndDelete: "Desactivar y eliminar",
            .turnOffBeforeEditing: "Desactiva este modo antes de editar sus controles.", .turnOffBeforeHiding: "Desactiva este modo antes de ocultarlo del menú.",
            .turnOffCurrentBeforeStarting: "Desactiva el modo actual antes de iniciar otro.",
            .unavailableToStart: "El modo «%@» no pudo iniciarse porque ninguno de sus controles está disponible.", .updating: "Actualizando...",
            .waitBeforeDeleting: "Espera a que termine la operación actual antes de eliminar el modo."
        ],
        .japanese: [
            .active: "有効", .addMode: "モードを追加", .addSwitchBeforeShowing: "「%@」に1つ以上のスイッチを追加してからメニューに表示してください。",
            .addSwitchBeforeStarting: "「%@」に1つ以上のスイッチを追加してから開始してください。", .closeModeSettings: "モード設定を閉じる",
            .createModePrompt: "モードを作成し、ワークフローに合うスイッチを選択します。", .customMode: "カスタムモード",
            .customWorkflow: "カスタムワークフロー", .deleteActiveModeMessage: "有効化前のスイッチ状態を復元してから、このモードを削除します。",
            .deleteMode: "モードを削除", .deleteModeIrreversible: "このモードは復元できません。", .deleteModeTitle: "「%@」を削除しますか？",
            .descriptionLabel: "説明", .finishBeforeTurningOff: "現在のスイッチ更新が完了してからモードをオフにしてください。",
            .finishSwitchBeforeChanging: "現在のスイッチ更新が完了してからモードを変更してください。", .hidden: "非表示", .icon: "アイコン",
            .macOSDidNotReachState: "macOS が要求された状態になりませんでした", .modeIconAwake: "起動", .modeIconControls: "コントロール",
            .modeIconDisplay: "ディスプレイ", .modeIconNight: "夜", .modeIconPeople: "人", .modeIconStack: "スタック",
            .modeIconTarget: "ターゲット", .modeIconWindows: "ウインドウ", .modeIconWork: "仕事", .modeLibrary: "モードライブラリ",
            .modeSettings: "モード設定", .name: "名前", .noModesYet: "モードはまだありません",
            .restoreFailed: "モード「%1$@」は以前の状態を完全に復元できませんでした。もう一度オフにしてください。%2$@",
            .restoreThenDelete: "以前の状態を復元してから削除", .restoringBeforeDeletion: "復元してから削除中...", .save: "保存",
            .showModeInMenu: "このモードをメニューに表示", .shownInMenu: "メニューに表示",
            .skippedUnavailable: "モード「%1$@」は利用できないスイッチをスキップしました：%2$@。",
            .startFailedRestored: "モード「%1$@」を開始できなかったため、変更を復元しました。%2$@",
            .startPartialRestoreFailed: "モード「%1$@」は一部のみ開始され、変更を完全に復元できませんでした。オフにして再試行してください。%2$@",
            .switchTargets: "スイッチの状態", .turnOffAndDelete: "オフにして削除",
            .turnOffBeforeEditing: "スイッチを編集する前にこのモードをオフにしてください。", .turnOffBeforeHiding: "メニューから隠す前にこのモードをオフにしてください。",
            .turnOffCurrentBeforeStarting: "別のモードを開始する前に現在のモードをオフにしてください。",
            .unavailableToStart: "モード「%@」は利用可能なスイッチがないため開始できませんでした。", .updating: "更新中...",
            .waitBeforeDeleting: "現在のモード操作が完了してから削除してください。"
        ],
        .korean: [
            .active: "활성", .addMode: "모드 추가", .addSwitchBeforeShowing: "메뉴에 표시하기 전에 ‘%@’에 스위치를 하나 이상 추가하세요.",
            .addSwitchBeforeStarting: "시작하기 전에 ‘%@’에 스위치를 하나 이상 추가하세요.", .closeModeSettings: "모드 설정 닫기",
            .createModePrompt: "모드를 만들고 작업 흐름에 맞는 스위치를 선택하세요.", .customMode: "사용자 설정 모드",
            .customWorkflow: "사용자 설정 작업 흐름", .deleteActiveModeMessage: "활성화 전의 스위치 상태를 복원한 다음 이 모드를 삭제합니다.",
            .deleteMode: "모드 삭제", .deleteModeIrreversible: "이 모드는 복구할 수 없습니다.", .deleteModeTitle: "‘%@’을(를) 삭제할까요?",
            .descriptionLabel: "설명", .finishBeforeTurningOff: "현재 스위치 업데이트가 끝난 후 이 모드를 끄세요.",
            .finishSwitchBeforeChanging: "현재 스위치 업데이트가 끝난 후 모드를 변경하세요.", .hidden: "숨김", .icon: "아이콘",
            .macOSDidNotReachState: "macOS가 요청한 상태에 도달하지 못했습니다", .modeIconAwake: "깨우기", .modeIconControls: "제어",
            .modeIconDisplay: "디스플레이", .modeIconNight: "야간", .modeIconPeople: "사람", .modeIconStack: "스택",
            .modeIconTarget: "대상", .modeIconWindows: "윈도우", .modeIconWork: "업무", .modeLibrary: "모드 보관함",
            .modeSettings: "모드 설정", .name: "이름", .noModesYet: "아직 모드가 없습니다",
            .restoreFailed: "‘%1$@’ 모드가 이전 상태를 완전히 복원하지 못했습니다. 다시 꺼 보세요. %2$@",
            .restoreThenDelete: "이전 상태를 복원한 후 모드 삭제", .restoringBeforeDeletion: "복원한 후 삭제 중...", .save: "저장",
            .showModeInMenu: "메뉴에 이 모드 표시", .shownInMenu: "메뉴에 표시됨",
            .skippedUnavailable: "‘%1$@’ 모드가 사용할 수 없는 스위치를 건너뛰었습니다: %2$@.",
            .startFailedRestored: "‘%1$@’ 모드를 시작하지 못해 변경 사항을 복원했습니다. %2$@",
            .startPartialRestoreFailed: "‘%1$@’ 모드가 일부만 시작되었고 변경 사항을 완전히 복원하지 못했습니다. 모드를 끈 후 다시 시도하세요. %2$@",
            .switchTargets: "스위치 상태", .turnOffAndDelete: "끄고 삭제",
            .turnOffBeforeEditing: "스위치를 편집하기 전에 이 모드를 끄세요.", .turnOffBeforeHiding: "메뉴에서 숨기기 전에 이 모드를 끄세요.",
            .turnOffCurrentBeforeStarting: "다른 모드를 시작하기 전에 현재 모드를 끄세요.",
            .unavailableToStart: "‘%@’ 모드에 사용할 수 있는 스위치가 없어 시작하지 못했습니다.", .updating: "업데이트 중...",
            .waitBeforeDeleting: "현재 모드 작업이 끝난 후 삭제하세요."
        ],
        .german: [
            .active: "Aktiv", .addMode: "Modus hinzufügen", .addSwitchBeforeShowing: "Füge „%@“ mindestens einen Schalter hinzu, bevor der Modus angezeigt wird.",
            .addSwitchBeforeStarting: "Füge „%@“ mindestens einen Schalter hinzu, bevor der Modus gestartet wird.", .closeModeSettings: "Moduseinstellungen schließen",
            .createModePrompt: "Erstelle einen Modus und wähle die Schalter für deinen Arbeitsablauf.", .customMode: "Eigener Modus",
            .customWorkflow: "Eigener Arbeitsablauf", .deleteActiveModeMessage: "Mac Switch stellt zuerst die vorherigen Schalterzustände wieder her und löscht dann den Modus.",
            .deleteMode: "Modus löschen", .deleteModeIrreversible: "Dieser Modus kann nicht wiederhergestellt werden.", .deleteModeTitle: "„%@“ löschen?",
            .descriptionLabel: "Beschreibung", .finishBeforeTurningOff: "Warte auf die aktuelle Schalteraktualisierung, bevor du den Modus ausschaltest.",
            .finishSwitchBeforeChanging: "Warte auf die aktuelle Schalteraktualisierung, bevor du den Modus wechselst.", .hidden: "Ausgeblendet", .icon: "Symbol",
            .macOSDidNotReachState: "macOS hat den angeforderten Zustand nicht erreicht", .modeIconAwake: "Wach", .modeIconControls: "Steuerungen",
            .modeIconDisplay: "Display", .modeIconNight: "Nacht", .modeIconPeople: "Personen", .modeIconStack: "Stapel",
            .modeIconTarget: "Ziel", .modeIconWindows: "Fenster", .modeIconWork: "Arbeit", .modeLibrary: "Modusbibliothek",
            .modeSettings: "Moduseinstellungen", .name: "Name", .noModesYet: "Noch keine Modi",
            .restoreFailed: "Der Modus „%1$@“ konnte den vorherigen Zustand nicht vollständig wiederherstellen. Schalte ihn erneut aus. %2$@",
            .restoreThenDelete: "Vorherige Zustände wiederherstellen und Modus löschen", .restoringBeforeDeletion: "Wiederherstellen und löschen...", .save: "Sichern",
            .showModeInMenu: "Diesen Modus im Menü anzeigen", .shownInMenu: "Im Menü angezeigt",
            .skippedUnavailable: "Der Modus „%1$@“ hat nicht verfügbare Schalter übersprungen: %2$@.",
            .startFailedRestored: "Der Modus „%1$@“ konnte nicht gestartet werden; die Änderungen wurden rückgängig gemacht. %2$@",
            .startPartialRestoreFailed: "Der Modus „%1$@“ wurde nur teilweise gestartet und konnte seine Änderungen nicht vollständig rückgängig machen. Schalte ihn aus und versuche es erneut. %2$@",
            .switchTargets: "Schalterzustände", .turnOffAndDelete: "Ausschalten & löschen",
            .turnOffBeforeEditing: "Schalte diesen Modus aus, bevor du seine Schalter bearbeitest.", .turnOffBeforeHiding: "Schalte diesen Modus aus, bevor du ihn im Menü ausblendest.",
            .turnOffCurrentBeforeStarting: "Schalte den aktuellen Modus aus, bevor du einen anderen startest.",
            .unavailableToStart: "Der Modus „%@“ konnte nicht gestartet werden, da keiner seiner Schalter verfügbar ist.", .updating: "Aktualisieren...",
            .waitBeforeDeleting: "Warte, bis der aktuelle Modusvorgang abgeschlossen ist, bevor du ihn löschst."
        ],
        .french: [
            .active: "Actif", .addMode: "Ajouter un mode", .addSwitchBeforeShowing: "Ajoutez au moins un contrôle à « %@ » avant d’afficher ce mode.",
            .addSwitchBeforeStarting: "Ajoutez au moins un contrôle à « %@ » avant de démarrer ce mode.", .closeModeSettings: "Fermer les réglages du mode",
            .createModePrompt: "Créez un mode et choisissez les contrôles adaptés à votre flux de travail.", .customMode: "Mode personnalisé",
            .customWorkflow: "Flux personnalisé", .deleteActiveModeMessage: "Mac Switch restaurera les états précédents, puis supprimera ce mode.",
            .deleteMode: "Supprimer le mode", .deleteModeIrreversible: "Ce mode ne pourra pas être récupéré.", .deleteModeTitle: "Supprimer « %@ » ?",
            .descriptionLabel: "Description", .finishBeforeTurningOff: "Attendez la fin de la mise à jour avant de désactiver ce mode.",
            .finishSwitchBeforeChanging: "Attendez la fin de la mise à jour avant de changer de mode.", .hidden: "Masqué", .icon: "Icône",
            .macOSDidNotReachState: "macOS n’a pas atteint l’état demandé", .modeIconAwake: "Éveil", .modeIconControls: "Contrôles",
            .modeIconDisplay: "Écran", .modeIconNight: "Nuit", .modeIconPeople: "Personnes", .modeIconStack: "Pile",
            .modeIconTarget: "Cible", .modeIconWindows: "Fenêtres", .modeIconWork: "Travail", .modeLibrary: "Bibliothèque de modes",
            .modeSettings: "Réglages du mode", .name: "Nom", .noModesYet: "Aucun mode pour le moment",
            .restoreFailed: "Le mode « %1$@ » n’a pas pu restaurer complètement son état précédent. Essayez de le désactiver à nouveau. %2$@",
            .restoreThenDelete: "Restaurer les états précédents, puis supprimer le mode", .restoringBeforeDeletion: "Restauration avant suppression...", .save: "Enregistrer",
            .showModeInMenu: "Afficher ce mode dans le menu", .shownInMenu: "Affiché dans le menu",
            .skippedUnavailable: "Le mode « %1$@ » a ignoré les contrôles indisponibles : %2$@.",
            .startFailedRestored: "Le mode « %1$@ » n’a pas pu démarrer ; ses modifications ont été annulées. %2$@",
            .startPartialRestoreFailed: "Le mode « %1$@ » n’a démarré que partiellement et n’a pas pu annuler toutes ses modifications. Désactivez-le pour réessayer. %2$@",
            .switchTargets: "États des contrôles", .turnOffAndDelete: "Désactiver et supprimer",
            .turnOffBeforeEditing: "Désactivez ce mode avant de modifier ses contrôles.", .turnOffBeforeHiding: "Désactivez ce mode avant de le masquer du menu.",
            .turnOffCurrentBeforeStarting: "Désactivez le mode actuel avant d’en démarrer un autre.",
            .unavailableToStart: "Le mode « %@ » n’a pas pu démarrer car aucun de ses contrôles n’est disponible.", .updating: "Mise à jour...",
            .waitBeforeDeleting: "Attendez la fin de l’opération en cours avant de supprimer ce mode."
        ],
        .italian: [
            .active: "Attiva", .addMode: "Aggiungi modalità", .addSwitchBeforeShowing: "Aggiungi almeno un controllo a “%@” prima di mostrare questa modalità.",
            .addSwitchBeforeStarting: "Aggiungi almeno un controllo a “%@” prima di avviare questa modalità.", .closeModeSettings: "Chiudi impostazioni modalità",
            .createModePrompt: "Crea una modalità e scegli i controlli adatti al tuo flusso di lavoro.", .customMode: "Modalità personalizzata",
            .customWorkflow: "Flusso personalizzato", .deleteActiveModeMessage: "Mac Switch ripristinerà gli stati precedenti e poi eliminerà questa modalità.",
            .deleteMode: "Elimina modalità", .deleteModeIrreversible: "Questa modalità non può essere recuperata.", .deleteModeTitle: "Eliminare “%@”?",
            .descriptionLabel: "Descrizione", .finishBeforeTurningOff: "Attendi il completamento dell’aggiornamento prima di disattivare questa modalità.",
            .finishSwitchBeforeChanging: "Attendi il completamento dell’aggiornamento prima di cambiare modalità.", .hidden: "Nascosta", .icon: "Icona",
            .macOSDidNotReachState: "macOS non ha raggiunto lo stato richiesto", .modeIconAwake: "Attivo", .modeIconControls: "Controlli",
            .modeIconDisplay: "Schermo", .modeIconNight: "Notte", .modeIconPeople: "Persone", .modeIconStack: "Pila",
            .modeIconTarget: "Obiettivo", .modeIconWindows: "Finestre", .modeIconWork: "Lavoro", .modeLibrary: "Libreria modalità",
            .modeSettings: "Impostazioni modalità", .name: "Nome", .noModesYet: "Nessuna modalità",
            .restoreFailed: "La modalità “%1$@” non ha ripristinato completamente lo stato precedente. Prova a disattivarla di nuovo. %2$@",
            .restoreThenDelete: "Ripristina gli stati precedenti e poi elimina", .restoringBeforeDeletion: "Ripristino prima dell’eliminazione...", .save: "Salva",
            .showModeInMenu: "Mostra questa modalità nel menu", .shownInMenu: "Visibile nel menu",
            .skippedUnavailable: "La modalità “%1$@” ha ignorato i controlli non disponibili: %2$@.",
            .startFailedRestored: "La modalità “%1$@” non si è avviata; le modifiche sono state ripristinate. %2$@",
            .startPartialRestoreFailed: "La modalità “%1$@” si è avviata solo in parte e non ha ripristinato tutte le modifiche. Disattivala per riprovare. %2$@",
            .switchTargets: "Stati dei controlli", .turnOffAndDelete: "Disattiva ed elimina",
            .turnOffBeforeEditing: "Disattiva questa modalità prima di modificarne i controlli.", .turnOffBeforeHiding: "Disattiva questa modalità prima di nasconderla dal menu.",
            .turnOffCurrentBeforeStarting: "Disattiva la modalità attuale prima di avviarne un’altra.",
            .unavailableToStart: "La modalità “%@” non si è avviata perché nessun controllo è disponibile.", .updating: "Aggiornamento...",
            .waitBeforeDeleting: "Attendi il completamento dell’operazione corrente prima di eliminare la modalità."
        ],
        .portuguese: [
            .active: "Ativo", .addMode: "Adicionar modo", .addSwitchBeforeShowing: "Adicione pelo menos um controle a “%@” antes de mostrar este modo.",
            .addSwitchBeforeStarting: "Adicione pelo menos um controle a “%@” antes de iniciar este modo.", .closeModeSettings: "Fechar ajustes do modo",
            .createModePrompt: "Crie um modo e escolha os controles adequados ao seu fluxo de trabalho.", .customMode: "Modo personalizado",
            .customWorkflow: "Fluxo personalizado", .deleteActiveModeMessage: "O Mac Switch restaurará os estados anteriores e depois excluirá este modo.",
            .deleteMode: "Excluir modo", .deleteModeIrreversible: "Este modo não poderá ser recuperado.", .deleteModeTitle: "Excluir “%@”?",
            .descriptionLabel: "Descrição", .finishBeforeTurningOff: "Aguarde a atualização atual terminar antes de desligar este modo.",
            .finishSwitchBeforeChanging: "Aguarde a atualização atual terminar antes de mudar de modo.", .hidden: "Oculto", .icon: "Ícone",
            .macOSDidNotReachState: "O macOS não atingiu o estado solicitado", .modeIconAwake: "Ativo", .modeIconControls: "Controles",
            .modeIconDisplay: "Tela", .modeIconNight: "Noite", .modeIconPeople: "Pessoas", .modeIconStack: "Pilha",
            .modeIconTarget: "Alvo", .modeIconWindows: "Janelas", .modeIconWork: "Trabalho", .modeLibrary: "Biblioteca de modos",
            .modeSettings: "Ajustes do modo", .name: "Nome", .noModesYet: "Ainda não há modos",
            .restoreFailed: "O modo “%1$@” não restaurou completamente o estado anterior. Tente desligá-lo novamente. %2$@",
            .restoreThenDelete: "Restaurar os estados anteriores e excluir o modo", .restoringBeforeDeletion: "Restaurando antes de excluir...", .save: "Salvar",
            .showModeInMenu: "Mostrar este modo no menu", .shownInMenu: "Visível no menu",
            .skippedUnavailable: "O modo “%1$@” ignorou controles indisponíveis: %2$@.",
            .startFailedRestored: "O modo “%1$@” não iniciou; suas alterações foram restauradas. %2$@",
            .startPartialRestoreFailed: "O modo “%1$@” iniciou apenas parcialmente e não restaurou todas as alterações. Desligue-o para tentar novamente. %2$@",
            .switchTargets: "Estados dos controles", .turnOffAndDelete: "Desligar e excluir",
            .turnOffBeforeEditing: "Desligue este modo antes de editar seus controles.", .turnOffBeforeHiding: "Desligue este modo antes de ocultá-lo do menu.",
            .turnOffCurrentBeforeStarting: "Desligue o modo atual antes de iniciar outro.",
            .unavailableToStart: "O modo “%@” não iniciou porque nenhum de seus controles está disponível.", .updating: "Atualizando...",
            .waitBeforeDeleting: "Aguarde a operação atual terminar antes de excluir o modo."
        ]
    ]
}
