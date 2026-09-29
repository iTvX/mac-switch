import CoreGraphics
import XCTest
@testable import MacSwitch

final class DisplayRecoveryBehaviorTests: XCTestCase {
    private let point = DisplayModeRestorePoint(uuid: "original-display", originalModeID: 100, previousToggleModeID: 200, selectedTargetModeID: 50)

    func testBoundDisplayActivationAndRestorationIgnoreAnotherSelectedDisplay() {
        let access = MemoryDisplays()
        let subject = ScreenResolutionSwitch(access: access)
        XCTAssertNil(subject.setEnabled(true, boundTo: point))
        XCTAssertEqual(access.modes, [1: 50, 2: 300])
        XCTAssertNil(subject.restore(point))
        XCTAssertEqual(access.modes, [1: 100, 2: 300])
        XCTAssertEqual(access.previous, [1: 200, 2: 400])
    }

    func testDisconnectedDisplayDoesNotFallBackToCurrentDisplay() {
        let access = MemoryDisplays()
        access.connectedID = nil
        let subject = ScreenResolutionSwitch(access: access)
        XCTAssertNotNil(subject.restore(point))
        XCTAssertTrue(access.writes.isEmpty)
        // The display reconnects with a different transient CoreGraphics ID.
        access.connectedID = 9
        access.modes[9] = 50
        XCTAssertNil(subject.restore(point))
        XCTAssertEqual(access.writes, [9])
        XCTAssertEqual(access.modes[2], 300)
    }

    func testFailedDisplayRestorationPreservesThePreviousToggleMarkerForRetry() {
        let access = MemoryDisplays()
        access.rejectMode = true
        let subject = ScreenResolutionSwitch(access: access)
        XCTAssertNotNil(subject.restore(point))
        XCTAssertEqual(access.previous, [1: 200, 2: 400])
        access.rejectMode = false
        XCTAssertNil(subject.restore(point))
        XCTAssertEqual(access.modes[1], 100)
    }

    func testTurningAnExistingResolutionSwitchOffThenRestoringKeepsItsOriginalMode() {
        let access = MemoryDisplays()
        let subject = ScreenResolutionSwitch(access: access)
        XCTAssertNil(subject.setEnabled(false, boundTo: point))
        XCTAssertEqual(access.modes[1], 200)
        XCTAssertNil(access.previous[1])
        XCTAssertNil(subject.restore(point))
        XCTAssertEqual(access.modes[1], 100)
        XCTAssertEqual(access.previous[1], 200)
    }
}

private final class MemoryDisplays: DisplayModeAccess, @unchecked Sendable {
    var connectedID: UInt32? = 1
    var modes: [UInt32: Int] = [1: 100, 2: 300]
    var previous: [UInt32: Int] = [1: 200, 2: 400]
    var writes: [UInt32] = []
    var rejectMode = false
    func display(matching uuid: String) -> UInt32? { uuid == "original-display" ? connectedID : nil }
    func applyMode(_ id: Int, display: UInt32) -> String? {
        writes.append(display)
        if rejectMode { return "Injected display failure" }
        modes[display] = id
        return nil
    }
    func savePreviousMode(_ id: Int?, display: UInt32) { previous[display] = id }
}
