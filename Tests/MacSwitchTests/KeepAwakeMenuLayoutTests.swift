import AppKit
import SwiftUI
import XCTest
@testable import MacSwitch

@MainActor
final class KeepAwakeMenuLayoutTests: XCTestCase {
    func testMenuSizeDoesNotChangeWhenSelectingDurationOrBecomingBusy() async throws {
        _ = NSApplication.shared
        let controller = MenuLayoutController()
        let store = SwitchStore(controller: controller, defaults: InMemoryUserDefaults(), enableRuntimeServices: false)
        store.snapshots[.keepAwake] = SwitchSnapshot(isOn: true, isAvailable: true, subtitle: "Active indefinitely", warning: nil)
        let host = NSHostingView(rootView: MenuLayoutFixture(store: store))
        host.frame = NSRect(x: 0, y: 0, width: 268, height: 266)
        try await Task.sleep(for: .milliseconds(30))
        host.layoutSubtreeIfNeeded()
        let initial = host.fittingSize
        store.setKeepAwakeDuration(.fiveMinutes)
        XCTAssertTrue(store.isActionBusy(.keepAwake))
        try await Task.sleep(for: .milliseconds(30))
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(host.fittingSize.height, initial.height, accuracy: 0.5)
        XCTAssertEqual(host.fittingSize.width, initial.width, accuracy: 0.5)
        controller.gate.signal()
        for _ in 0..<100 where store.isActionBusy(.keepAwake) { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(store.isActionBusy(.keepAwake))
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(host.fittingSize.height, initial.height, accuracy: 0.5)
        XCTAssertLessThanOrEqual(initial.height, DashboardLayout.minHeight - 12)
    }
}

private struct MenuLayoutFixture: View {
    @ObservedObject var store: SwitchStore
    var body: some View {
        DashboardRowQuickMenu(kind: .keepAwake, store: store,
            hideDisabledReason: store.isActionBusy(.keepAwake) ? "Finish current action first" : nil,
            configure: {}, hideFromMenu: {})
    }
}

private final class MenuLayoutController: SystemSwitchControlling, @unchecked Sendable {
    let gate = DispatchSemaphore(value: 0)
    var onExternalChange: (@Sendable (SwitchKind) -> Void)?
    func snapshot(for kind: SwitchKind, keepAwakeDuration: KeepAwakeDuration) -> SwitchSnapshot {
        SwitchSnapshot(isOn: kind == .keepAwake, isAvailable: true, subtitle: "Active", warning: nil)
    }
    func set(_ kind: SwitchKind, enabled: Bool, keepAwakeDuration: KeepAwakeDuration) -> SwitchOperationResult {
        _ = gate.wait(timeout: .now() + 3)
        return SwitchOperationResult(snapshot: snapshot(for: kind, keepAwakeDuration: keepAwakeDuration), error: nil)
    }
    func setKeepAwake(enabled: Bool, duration: TimeInterval?, defaultDuration: KeepAwakeDuration) -> SwitchOperationResult {
        set(.keepAwake, enabled: enabled, keepAwakeDuration: defaultDuration)
    }
    func performXcodeClean(progress: @escaping @Sendable (Double) -> Void) -> SwitchOperationResult { SwitchOperationResult(snapshot: .off, error: nil) }
    func prepareForTermination() {}
}
