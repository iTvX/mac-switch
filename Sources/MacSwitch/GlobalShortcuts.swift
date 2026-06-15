import AppKit
import Carbon
import Foundation

struct HotKeyShortcut: Codable, Equatable, Hashable {
    var keyCode: UInt32
    var modifiers: UInt32
    var display: String

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var value = UInt32(0)
        if flags.contains(.command) { value |= UInt32(cmdKey) }
        if flags.contains(.option) { value |= UInt32(optionKey) }
        if flags.contains(.control) { value |= UInt32(controlKey) }
        if flags.contains(.shift) { value |= UInt32(shiftKey) }
        return value
    }

    static func displayText(for event: NSEvent, modifiers: UInt32) -> String {
        displayText(keyCode: UInt32(event.keyCode), modifiers: modifiers, fallback: event.charactersIgnoringModifiers)
    }

    var isValidGlobalShortcut: Bool {
        Self.isValidGlobalShortcut(keyCode: keyCode, modifiers: modifiers)
    }

    var validationFailureMessage: String? {
        Self.validationFailureMessage(keyCode: keyCode, modifiers: modifiers)
    }

    static func isValidGlobalShortcut(keyCode: UInt32, modifiers: UInt32) -> Bool {
        validationFailureMessage(keyCode: keyCode, modifiers: modifiers) == nil
    }

    static func validationFailureMessage(keyCode: UInt32, modifiers: UInt32) -> String? {
        if primaryModifierCount(modifiers) < 2 {
            return "Use at least two of Command, Option, or Control."
        }
        if reservedKeyCodes.contains(keyCode) {
            return "Choose a letter, number, or function key for the shortcut."
        }
        return nil
    }

    static func recordingFailureTitle(keyCode: UInt32, modifiers: UInt32) -> String {
        if primaryModifierCount(modifiers) < 2 {
            return "Use two of ⌘ ⌥ ⌃"
        }
        if reservedKeyCodes.contains(keyCode) {
            return "Reserved key"
        }
        return "Invalid shortcut"
    }

    static func displayText(keyCode: UInt32, modifiers: UInt32, fallback: String? = nil) -> String {
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }

        let keyName: String
        if let special = specialKeyNames[keyCode] {
            keyName = special
        } else if let fallback, !fallback.isEmpty {
            keyName = fallback.uppercased()
        } else {
            keyName = "Key \(keyCode)"
        }

        parts.append(keyName)
        return parts.joined()
    }

    private static let specialKeyNames: [UInt32: String] = [
        36: "↩",
        48: "⇥",
        49: "Space",
        51: "⌫",
        53: "Esc",
        64: "F17",
        71: "Clear",
        76: "⌤",
        79: "F18",
        80: "F19",
        90: "F20",
        96: "F5",
        97: "F6",
        98: "F7",
        99: "F3",
        100: "F8",
        101: "F9",
        103: "F11",
        105: "F13",
        106: "F16",
        107: "F14",
        109: "F10",
        111: "F12",
        113: "F15",
        114: "Help",
        115: "Home",
        116: "PgUp",
        117: "⌦",
        118: "F4",
        119: "End",
        120: "F2",
        121: "PgDn",
        122: "F1",
        123: "←",
        124: "→",
        125: "↓",
        126: "↑"
    ]

    private static let reservedKeyCodes = Set<UInt32>([
        36, 48, 49, 51, 53, 71, 76, 114, 115, 116, 117, 119, 121, 123, 124, 125, 126
    ])

    private static func primaryModifierCount(_ modifiers: UInt32) -> Int {
        var count = 0
        if modifiers & UInt32(cmdKey) != 0 { count += 1 }
        if modifiers & UInt32(optionKey) != 0 { count += 1 }
        if modifiers & UInt32(controlKey) != 0 { count += 1 }
        return count
    }
}

final class GlobalShortcutManager {
    private let signature = OSType(0x4D535743) // MSWC
    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var kindsByID: [UInt32: SwitchKind] = [:]
    private var nextID: UInt32 = 1
    private var eventHandler: EventHandlerRef?
    private var eventHandlerInstallStatus: OSStatus = noErr
    private var handler: ((SwitchKind) -> Void)?

    init() {
        installEventHandler()
    }

    deinit {
        unregisterAll()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    func register(shortcuts: [SwitchKind: HotKeyShortcut], handler: @escaping (SwitchKind) -> Void) -> String? {
        unregisterAll()
        self.handler = shortcuts.isEmpty ? nil : handler
        guard !shortcuts.isEmpty else { return nil }

        if eventHandler == nil {
            installEventHandler()
        }
        guard eventHandler != nil else {
            return "Could not install global shortcut handler (OSStatus \(eventHandlerInstallStatus))."
        }

        var failures: [String] = []
        for (kind, shortcut) in shortcuts.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            if let reason = shortcut.validationFailureMessage {
                failures.append("\(shortcut.display) for \(kind.title) (\(reason))")
                continue
            }

            let hotKeyID = EventHotKeyID(signature: signature, id: nextID)
            nextID += 1

            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(
                shortcut.keyCode,
                shortcut.modifiers,
                hotKeyID,
                GetApplicationEventTarget(),
                0,
                &ref
            )

            if status == noErr {
                hotKeyRefs.append(ref)
                kindsByID[hotKeyID.id] = kind
            } else {
                failures.append("\(shortcut.display) for \(kind.title) (OSStatus \(status))")
            }
        }

        return failures.isEmpty ? nil : "Could not register shortcut: \(failures.joined(separator: ", "))."
    }

    private func unregisterAll() {
        for ref in hotKeyRefs {
            if let ref {
                UnregisterEventHotKey(ref)
            }
        }
        hotKeyRefs.removeAll()
        kindsByID.removeAll()
        nextID = 1
    }

    private func installEventHandler() {
        guard eventHandler == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        eventHandlerInstallStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            globalHotKeyHandler,
            1,
            &eventType,
            refcon,
            &eventHandler
        )
        if eventHandlerInstallStatus != noErr {
            eventHandler = nil
        }
    }

    fileprivate func handle(event: EventRef?) -> OSStatus {
        guard let event else { return noErr }

        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr, hotKeyID.signature == signature, let kind = kindsByID[hotKeyID.id] else {
            return noErr
        }

        DispatchQueue.main.async { [handler] in
            handler?(kind)
        }
        return noErr
    }
}

private let globalHotKeyHandler: EventHandlerUPP = { _, event, refcon in
    guard let refcon else { return noErr }
    let manager = Unmanaged<GlobalShortcutManager>.fromOpaque(refcon).takeUnretainedValue()
    return manager.handle(event: event)
}
