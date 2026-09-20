import AppKit
import ApplicationServices

struct DoNotDisturbControlResult: Sendable {
    let state: Bool?
    let error: String?
}

protocol DoNotDisturbControlling: Sendable {
    var isAvailable: Bool { get }
    var lastConfirmedState: Bool? { get }
    func readState() -> DoNotDisturbControlResult
    func setEnabled(_ enabled: Bool) -> DoNotDisturbControlResult
}

/// Controls the system's DND checkbox without requiring user-created Shortcuts.
/// Only action preflight and writes open Control Center; passive refreshes never open UI.
final class ControlCenterFocusController: DoNotDisturbControlling, @unchecked Sendable {
    static let permissionMessage = "Allow Accessibility access to control Do Not Disturb without shortcuts."
    private static let queue = DispatchQueue(label: "com.maxyu.macswitch.control-center-focus")
    private static let dndIdentifier = "focus-mode-activity-com.apple.donotdisturb.mode.default"

    var isAvailable: Bool { AccessibilityPermission.isTrusted }

    // Accessed only on queue. This is an observed system value, never a requested
    // value or a persisted preference. Passive refreshes must not open system UI.
    private var confirmedState: Bool?

    var lastConfirmedState: Bool? {
        Self.queue.sync { confirmedState }
    }

    func readState() -> DoNotDisturbControlResult {
        Self.queue.sync { update(nil) }
    }

    func setEnabled(_ enabled: Bool) -> DoNotDisturbControlResult {
        Self.queue.sync { update(enabled) }
    }

    private func update(_ enabled: Bool?) -> DoNotDisturbControlResult {
        func failed(_ message: String) -> DoNotDisturbControlResult {
            // An unverified result must not be mistaken for a successful change.
            confirmedState = nil
            return DoNotDisturbControlResult(state: nil, error: message)
        }
        func observed(_ state: Bool) -> DoNotDisturbControlResult {
            confirmedState = state
            return DoNotDisturbControlResult(state: state, error: nil)
        }
        guard isAvailable else { return failed(Self.permissionMessage) }
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.controlcenter").first else {
            return failed("Could not open Control Center for Do Not Disturb.")
        }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.5)
        guard let menuItem = find("com.apple.menuextra.controlcenter", in: root) else {
            return failed("Could not open Control Center for Do Not Disturb.")
        }

        // Do not close a Control Center panel the user had already opened.
        let openedHere = windows(in: root).isEmpty
        if openedHere, AXUIElementPerformAction(menuItem, kAXPressAction as CFString) != .success {
            return failed("Could not open Control Center for Do Not Disturb.")
        }
        defer {
            if openedHere {
                dismiss(root: root, menuItem: menuItem)
            }
        }

        if findInWindows(Self.dndIdentifier, root: root) == nil {
            guard let focus = waitForElement("controlcenter-focus-modes", root: root) else {
                return failed("Could not find Do Not Disturb in Control Center. Open Focus settings or configure Focus shortcuts.")
            }
            var actionNames: CFArray?
            AXUIElementCopyActionNames(focus, &actionNames)
            let actions = actionNames as? [String] ?? []
            // Opening details is distinct from AXPress, which toggles the last
            // used Focus and could enable a different mode such as Sleep.
            let detailsAction = actions.first { $0.hasPrefix("Name:show details\n") }
                ?? (actions.contains(kAXShowMenuAction) ? kAXShowMenuAction : nil)
            guard let detailsAction,
                  AXUIElementPerformAction(focus, detailsAction as CFString) == .success else {
                return failed("Could not find Do Not Disturb in Control Center. Open Focus settings or configure Focus shortcuts.")
            }
        }

        guard let checkbox = waitForElement(Self.dndIdentifier, root: root),
              let current = checked(checkbox) else {
            return failed("Could not read Do Not Disturb in Control Center.")
        }
        guard let enabled, current != enabled else { return observed(current) }
        guard AXUIElementPerformAction(checkbox, kAXPressAction as CFString) == .success else {
            return failed("Could not change Do Not Disturb in Control Center.")
        }
        let deadline = Date().addingTimeInterval(3)
        repeat {
            if let updated = findInWindows(Self.dndIdentifier, root: root), checked(updated) == enabled {
                return observed(enabled)
            }
            Thread.sleep(forTimeInterval: 0.1)
        } while Date() < deadline
        return failed("macOS did not confirm the Do Not Disturb change.")
    }

    private func waitForElement(_ identifier: String, root: AXUIElement) -> AXUIElement? {
        let deadline = Date().addingTimeInterval(3)
        repeat {
            if let element = findInWindows(identifier, root: root) { return element }
            Thread.sleep(forTimeInterval: 0.1)
        } while Date() < deadline
        return nil
    }

    private func dismiss(root: AXUIElement, menuItem: AXUIElement) {
        // On newer macOS, pressing the menu item from Focus details returns
        // to the main panel first. Wait for each transition before pressing again.
        for _ in 0..<2 {
            guard !windows(in: root).isEmpty else { return }
            _ = AXUIElementPerformAction(menuItem, kAXPressAction as CFString)
            let deadline = Date().addingTimeInterval(0.7)
            repeat {
                if windows(in: root).isEmpty { return }
                Thread.sleep(forTimeInterval: 0.1)
            } while Date() < deadline
        }
    }

    private func findInWindows(_ identifier: String, root: AXUIElement) -> AXUIElement? {
        for window in windows(in: root) {
            if let element = find(identifier, in: window) { return element }
        }
        return nil
    }

    private func windows(in root: AXUIElement) -> [AXUIElement] {
        attribute(kAXWindowsAttribute, of: root) as? [AXUIElement] ?? []
    }

    private func find(_ identifier: String, in element: AXUIElement, depth: Int = 0) -> AXUIElement? {
        guard depth < 12 else { return nil }
        if attribute(kAXIdentifierAttribute, of: element) as? String == identifier { return element }
        for child in attribute(kAXChildrenAttribute, of: element) as? [AXUIElement] ?? [] {
            if let match = find(identifier, in: child, depth: depth + 1) { return match }
        }
        return nil
    }

    private func checked(_ element: AXUIElement) -> Bool? {
        (attribute(kAXValueAttribute, of: element) as? NSNumber)?.boolValue
    }

    private func attribute(_ name: String, of element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
}
