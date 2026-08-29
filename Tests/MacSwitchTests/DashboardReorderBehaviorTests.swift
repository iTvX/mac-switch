import CoreGraphics
import XCTest
@testable import MacSwitch

final class DashboardReorderBehaviorTests: XCTestCase {
    func testCompletedFramesFillEveryMissingRowFromTheDraggedAnchor() {
        let order: [SwitchKind] = [.keepAwake, .nightShift, .stageManager, .handoff]
        let anchor = CGRect(x: 7, y: 100, width: 312, height: 49)
        let completed = DashboardReorderGeometry.completedFrames(
            orderedKinds: order,
            measuredFrames: [.nightShift: anchor],
            rowHeights: [
                .keepAwake: 49,
                .nightShift: 49,
                .stageManager: 43,
                .handoff: 43
            ],
            anchorKind: .nightShift
        )

        XCTAssertEqual(completed.count, order.count)
        XCTAssertEqual(completed[.keepAwake], CGRect(x: 7, y: 51, width: 312, height: 49))
        XCTAssertEqual(completed[.nightShift], anchor)
        XCTAssertEqual(completed[.stageManager], CGRect(x: 7, y: 149, width: 312, height: 43))
        XCTAssertEqual(completed[.handoff], CGRect(x: 7, y: 192, width: 312, height: 43))
    }

    func testCompletedFramesPreserveMeasuredRowsWhileFillingGaps() {
        let order: [SwitchKind] = [.keepAwake, .nightShift, .stageManager, .handoff]
        let measuredHandoff = CGRect(x: 7, y: 250, width: 312, height: 43)
        let completed = DashboardReorderGeometry.completedFrames(
            orderedKinds: order,
            measuredFrames: [
                .nightShift: CGRect(x: 7, y: 100, width: 312, height: 49),
                .handoff: measuredHandoff
            ],
            rowHeights: Dictionary(uniqueKeysWithValues: order.map { ($0, 43) }),
            anchorKind: .nightShift
        )

        XCTAssertEqual(completed[.handoff], measuredHandoff)
        XCTAssertEqual(completed[.stageManager]?.minY, 149)
        XCTAssertEqual(completed[.keepAwake]?.maxY, 100)
    }

    func testCompletedFramesRejectMissingDraggedRowFrame() {
        XCTAssertTrue(
            DashboardReorderGeometry.completedFrames(
                orderedKinds: [.keepAwake, .nightShift],
                measuredFrames: [.nightShift: CGRect(x: 0, y: 40, width: 300, height: 40)],
                rowHeights: [.keepAwake: 40, .nightShift: 40],
                anchorKind: .keepAwake
            ).isEmpty
        )
    }

    func testInsertionHysteresisPreventsBoundaryJitterInBothDirections() {
        let frames = uniformFrames()
        let order: [SwitchKind] = [.keepAwake, .nightShift, .stageManager]
        let initialFrame = frames[.keepAwake]!

        let almostDown = DashboardDragState(
            kind: .keepAwake,
            initialOrder: order,
            frozenFrames: frames,
            initialFrame: initialFrame,
            translationY: 42,
            targetIndex: 0
        )
        XCTAssertEqual(DashboardReorderGeometry.insertionIndex(using: almostDown, hysteresis: 4), 0)

        let committedDown = almostDown.withTranslation(45)
        XCTAssertEqual(DashboardReorderGeometry.insertionIndex(using: committedDown, hysteresis: 4), 1)

        let almostBackUp = almostDown.withTranslation(38).withTargetIndex(1)
        XCTAssertEqual(DashboardReorderGeometry.insertionIndex(using: almostBackUp, hysteresis: 4), 1)

        let committedBackUp = almostBackUp.withTranslation(35)
        XCTAssertEqual(DashboardReorderGeometry.insertionIndex(using: committedBackUp, hysteresis: 4), 0)
    }

    func testReorderedKindsPreserveEveryItemAndClampTheTarget() {
        let order: [SwitchKind] = [.keepAwake, .nightShift, .stageManager]
        let base = DashboardDragState(
            kind: .keepAwake,
            initialOrder: order,
            frozenFrames: uniformFrames(),
            initialFrame: uniformFrames()[.keepAwake]!,
            translationY: 0,
            targetIndex: 1
        )

        XCTAssertEqual(
            DashboardReorderGeometry.reorderedKinds(using: base),
            [.nightShift, .keepAwake, .stageManager]
        )
        XCTAssertEqual(
            DashboardReorderGeometry.reorderedKinds(using: base.withTargetIndex(99)),
            [.nightShift, .stageManager, .keepAwake]
        )
        XCTAssertEqual(Set(DashboardReorderGeometry.reorderedKinds(using: base)), Set(order))
    }

    private func uniformFrames() -> [SwitchKind: CGRect] {
        [
            .keepAwake: CGRect(x: 0, y: 0, width: 300, height: 40),
            .nightShift: CGRect(x: 0, y: 40, width: 300, height: 40),
            .stageManager: CGRect(x: 0, y: 80, width: 300, height: 40)
        ]
    }
}
