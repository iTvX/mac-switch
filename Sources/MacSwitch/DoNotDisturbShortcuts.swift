import AppKit
import Foundation

enum DNDShortcut: String, CaseIterable, Sendable {
    case enable, disable

    // Deliberately distinct from legacy, user-created single-action shortcuts.
    var name: String { "Mac Switch DND \(self == .enable ? "Enable" : "Disable")" }
    var outputPrefix: String { "mac-switch-dnd-v1|\(rawValue)|" }
    var resourceURL: URL? {
        Bundle.main.url(forResource: name, withExtension: "shortcut", subdirectory: "Shortcuts")
    }

    func focusName(from output: String) throws -> String {
        let text = output.trimmingCharacters(in: .newlines)
        guard text.hasPrefix(outputPrefix), text.utf8.count < 4096 else {
            throw DNDShortcutError("Do Not Disturb returned an invalid status. Reinstall both shortcuts in DND Setup.")
        }
        return String(text.dropFirst(outputPrefix.count))
    }
}

struct DNDShortcutError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

protocol DNDShortcutExecuting: Sendable {
    func list() throws -> String
    func run(identifier: String, readOnly: Bool) throws -> String
}

struct SystemDNDShortcutExecutor: DNDShortcutExecuting {
    func list() throws -> String {
        let result = ProcessRunner.run("/usr/bin/shortcuts", ["list", "--show-identifiers"], timeout: 8)
        guard result.status == 0 else { throw failure(result) }
        return result.output
    }

    func run(identifier: String, readOnly: Bool) throws -> String {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("mac-switch-dnd-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appendingPathComponent("result.txt")
        var arguments = ["run", identifier, "--output-path", output.path, "--output-type", "public.plain-text"]
        if readOnly {
            let input = directory.appendingPathComponent("status.txt")
            try Data("status".utf8).write(to: input)
            arguments += ["--input-path", input.path]
        }
        let result = ProcessRunner.run("/usr/bin/shortcuts", arguments, timeout: 15, nullInput: true)
        guard result.status == 0 else { throw failure(result) }
        guard let size = try output.resourceValues(forKeys: [.fileSizeKey]).fileSize, size < 4096 else {
            throw DNDShortcutError("Do Not Disturb returned an invalid status. Reinstall both shortcuts in DND Setup.")
        }
        return try String(contentsOf: output, encoding: .utf8)
    }

    private func failure(_ result: (status: Int32, output: String, error: String)) -> DNDShortcutError {
        if result.status == 124 {
            return DNDShortcutError("Do Not Disturb shortcut timed out. Open Shortcuts to finish any pending permission request, then retry DND Setup.")
        }
        let detail = ProcessRunner.failureMessage(for: result, fallback: "Could not run Shortcuts.")
        return DNDShortcutError("Do Not Disturb shortcut failed: \(String(detail.prefix(240)))")
    }
}

struct DNDShortcutInstallation: Sendable {
    var identifiers: [DNDShortcut: String] = [:]
    var isVerified = false
    var error: String?
    var allInstalled: Bool { DNDShortcut.allCases.allSatisfy { identifiers[$0] != nil } }

    static func parse(_ listing: String) -> [DNDShortcut: String] {
        var matches: [DNDShortcut: [String]] = [:]
        for line in listing.split(whereSeparator: \.isNewline) {
            guard let separator = line.range(of: " (", options: .backwards), line.hasSuffix(")") else { continue }
            let name = String(line[..<separator.lowerBound])
            let identifier = String(line[separator.upperBound..<line.index(before: line.endIndex)])
            guard UUID(uuidString: identifier) != nil, let role = DNDShortcut.allCases.first(where: { $0.name == name }) else { continue }
            matches[role, default: []].append(identifier)
        }
        return matches.compactMapValues { $0.count == 1 ? $0[0] : nil }
    }
}

final class DoNotDisturbShortcuts: @unchecked Sendable {
    static let shared = DoNotDisturbShortcuts()
    private let queue = DispatchQueue(label: "com.maxyu.macswitch.dnd-shortcuts")
    private let executor: any DNDShortcutExecuting
    private let defaults: UserDefaults
    private var cachedInstallation: (Date, DNDShortcutInstallation)?
    private var cachedSnapshot: (Date, SwitchSnapshot)?
    private static let verificationKey = "switch.doNotDisturb.verifiedShortcuts.v1"
    private static let focusNameKey = "switch.doNotDisturb.focusName.v1"

    init(executor: any DNDShortcutExecuting = SystemDNDShortcutExecutor(), defaults: UserDefaults = .standard) {
        self.executor = executor
        self.defaults = defaults
    }

    func installation(force: Bool = true) -> DNDShortcutInstallation {
        queue.sync { loadInstallation(force: force) }
    }

    private func loadInstallation(force: Bool) -> DNDShortcutInstallation {
        if !force, let cachedInstallation, Date().timeIntervalSince(cachedInstallation.0) < 5 { return cachedInstallation.1 }
        var result = DNDShortcutInstallation()
        do {
            result.identifiers = DNDShortcutInstallation.parse(try executor.list())
            result.isVerified = result.allInstalled && defaults.string(forKey: Self.verificationKey) == pairKey(result)
                && !(defaults.string(forKey: Self.focusNameKey) ?? "").isEmpty
        } catch { result.error = error.localizedDescription }
        cachedInstallation = (Date(), result)
        return result
    }

    private func pairKey(_ installation: DNDShortcutInstallation) -> String {
        DNDShortcut.allCases.map { installation.identifiers[$0] ?? "" }.joined(separator: "|")
    }

    /// Calibrate the localized DND name once, starting with no Focus active.
    /// The name identifies the mode; it is never used as a cached on/off value.
    func verifySetup() -> String? {
        queue.sync {
            cachedSnapshot = nil
            let installation = loadInstallation(force: true)
            guard installation.allInstalled else { return installation.error ?? "Install both Do Not Disturb shortcuts first." }
            do {
                let initial = try readFocus(installation)
                if installation.isVerified {
                    _ = try state(for: initial)
                    return nil
                }
                guard initial.isEmpty else {
                    return "Turn off the current Focus once before verifying Do Not Disturb setup."
                }
                var name: String?
                var activationError: Error?
                do {
                    let observed = try run(.enable, installation: installation)
                    guard !observed.isEmpty else { throw DNDShortcutError("The Do Not Disturb shortcut did not turn on Focus.") }
                    name = observed
                } catch { activationError = error }
                // Always restore, even if enabling changed Focus but failed to return output.
                do {
                    guard try run(.disable, installation: installation).isEmpty else {
                        throw DNDShortcutError("Do Not Disturb stayed on after setup. Run the Disable shortcut and retry.")
                    }
                } catch {
                    return "Could not restore Do Not Disturb after setup. Run the Disable shortcut. \(error.localizedDescription)"
                }
                if let activationError { throw activationError }
                guard let name else { throw DNDShortcutError("Do Not Disturb setup did not return a Focus name.") }
                defaults.set(name, forKey: Self.focusNameKey)
                defaults.set(pairKey(installation), forKey: Self.verificationKey)
                cachedInstallation = nil
                return nil
            } catch { return error.localizedDescription }
        }
    }

    func snapshot(force: Bool = false) -> SwitchSnapshot {
        queue.sync {
            if !force {
                do { _ = try readyInstallation(force: false) }
                catch { return Self.unavailable(error.localizedDescription) }
                // Opening the dashboard must not run a shortcut (or show its system activity UI).
                // Toggle/Mode preflight always uses a fresh observation before acting.
                var snapshot = cachedSnapshot?.1 ?? Self.observed(false)
                if snapshot.isAvailable { snapshot.subtitle = "Checked when used" }
                return snapshot
            }
            let snapshot: SwitchSnapshot
            do {
                let installation = try readyInstallation(force: force)
                snapshot = Self.observed(try state(for: readFocus(installation)))
            } catch { snapshot = Self.unavailable(error.localizedDescription) }
            cachedSnapshot = (Date(), snapshot)
            return snapshot
        }
    }

    func set(_ enabled: Bool) -> SwitchOperationResult {
        queue.sync {
            do {
                let installation = try readyInstallation(force: true)
                let current = try state(for: readFocus(installation))
                if current != enabled {
                    let observed = try state(for: run(enabled ? .enable : .disable, installation: installation))
                    guard observed == enabled else {
                        throw DNDShortcutError("Do Not Disturb did not reach the requested state. Check its shortcuts in DND Setup.")
                    }
                }
                let snapshot = Self.observed(enabled)
                cachedSnapshot = (Date(), snapshot)
                return SwitchOperationResult(snapshot: snapshot, error: nil)
            } catch {
                let snapshot = Self.unavailable(error.localizedDescription)
                cachedSnapshot = (Date(), snapshot)
                return SwitchOperationResult(snapshot: snapshot, error: error.localizedDescription)
            }
        }
    }

    private func readyInstallation(force: Bool) throws -> DNDShortcutInstallation {
        let installation = loadInstallation(force: force)
        if let error = installation.error { throw DNDShortcutError(error) }
        guard installation.allInstalled else { throw DNDShortcutError("Install both shortcuts in Customize > Do Not Disturb.") }
        guard installation.isVerified else { throw DNDShortcutError("Verify the shortcuts in Customize > Do Not Disturb.") }
        return installation
    }

    private func readFocus(_ installation: DNDShortcutInstallation) throws -> String {
        try run(.enable, installation: installation, readOnly: true)
    }

    private func run(_ role: DNDShortcut, installation: DNDShortcutInstallation, readOnly: Bool = false) throws -> String {
        guard let identifier = installation.identifiers[role] else { throw DNDShortcutError("Install both Do Not Disturb shortcuts first.") }
        return try role.focusName(from: executor.run(identifier: identifier, readOnly: readOnly))
    }

    private func state(for focusName: String) throws -> Bool {
        if focusName.isEmpty { return false }
        if focusName == defaults.string(forKey: Self.focusNameKey) { return true }
        throw DNDShortcutError("Another Focus is active. Turn it off before using Do Not Disturb; Mac Switch will leave it unchanged.")
    }

    private static func observed(_ state: Bool) -> SwitchSnapshot {
        SwitchSnapshot(isOn: state, isAvailable: true, subtitle: nil, warning: nil)
    }

    private static func unavailable(_ error: String) -> SwitchSnapshot {
        SwitchSnapshot(isOn: false, isAvailable: false, subtitle: "Open DND Setup", warning: error)
    }
}

struct DoNotDisturbSwitch {
    private let shortcuts: DoNotDisturbShortcuts
    init(shortcuts: DoNotDisturbShortcuts = .shared) { self.shortcuts = shortcuts }
    func snapshot() -> SwitchSnapshot { shortcuts.snapshot() }
    func snapshotForAction() -> SwitchSnapshot { shortcuts.snapshot(force: true) }
    func set(_ enabled: Bool) -> SwitchOperationResult { shortcuts.set(enabled) }
    func setEnabled(_ enabled: Bool) -> String? { set(enabled).error }
}
