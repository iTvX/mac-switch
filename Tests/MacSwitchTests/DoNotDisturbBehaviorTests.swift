import XCTest
@testable import MacSwitch

final class DoNotDisturbBehaviorTests: XCTestCase {
    func testSnapshotRequiresFocusStatusPermission() {
        for authorization in [
            FocusStatusAuthorization.notDetermined,
            .restricted,
            .denied
        ] {
            let provider = FakeFocusStatusProvider(
                readings: [FocusStatusReading(authorization: authorization, isFocused: nil)]
            )

            let snapshot = DoNotDisturbSwitch(focusStatusProvider: provider).snapshot()

            XCTAssertFalse(snapshot.isAvailable)
            XCTAssertEqual(snapshot.subtitle, "Focus status permission required")
        }
    }

    func testSnapshotUsesCurrentMacOSFocusStateBeforeShortcutValidation() {
        let provider = FakeFocusStatusProvider(readings: [
            FocusStatusReading(authorization: .authorized, isFocused: true)
        ])

        let snapshot = DoNotDisturbSwitch(focusStatusProvider: provider).snapshot()

        XCTAssertTrue(snapshot.isOn)
        XCTAssertEqual(provider.readCount, 1)
    }

    func testMissingFocusStateIsUnavailableInsteadOfPretendingToBeOff() {
        let provider = FakeFocusStatusProvider(readings: [
            FocusStatusReading(authorization: .authorized, isFocused: nil)
        ])

        let snapshot = DoNotDisturbSwitch(focusStatusProvider: provider).snapshot()

        XCTAssertFalse(snapshot.isAvailable)
        XCTAssertFalse(snapshot.isOn)
        XCTAssertEqual(snapshot.subtitle, "Focus status unavailable")
    }

    func testNoOpToggleDoesNotRunShortcuts() {
        let provider = FakeFocusStatusProvider(readings: [
            FocusStatusReading(authorization: .authorized, isFocused: true)
        ])

        XCTAssertNil(DoNotDisturbSwitch(focusStatusProvider: provider).setEnabled(true))
        XCTAssertEqual(provider.readCount, 1)
    }
}

private final class FakeFocusStatusProvider: FocusStatusProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var readings: [FocusStatusReading]
    private(set) var readCount = 0

    init(readings: [FocusStatusReading]) {
        precondition(!readings.isEmpty)
        self.readings = readings
    }

    func read() -> FocusStatusReading {
        lock.lock()
        defer { lock.unlock() }
        readCount += 1
        if readings.count > 1 {
            return readings.removeFirst()
        }
        return readings[0]
    }
}
