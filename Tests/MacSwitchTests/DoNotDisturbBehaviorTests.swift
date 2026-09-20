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

        let native = FakeDoNotDisturbController(isAvailable: false)
        XCTAssertNil(DoNotDisturbSwitch(focusStatusProvider: provider, controlCenter: native).setEnabled(true))
        XCTAssertEqual(provider.readCount, 1)
        XCTAssertTrue(native.requests.isEmpty)
    }

    func testBuiltInControlIsReadyWithoutShortcuts() {
        for isOn in [false, true] {
            let native = FakeDoNotDisturbController()
            let subject = makeSwitch(isFocused: isOn, native: native)

            let snapshot = subject.snapshot()

            XCTAssertTrue(snapshot.isAvailable)
            XCTAssertEqual(snapshot.isOn, isOn)
            XCTAssertNil(snapshot.warning)
            XCTAssertTrue(native.requests.isEmpty, "Refreshing state must not open Control Center")
        }
    }

    func testBuiltInToggleUsesRequestedStateAndSurfacesFailure() {
        let native = FakeDoNotDisturbController()
        let subject = makeSwitch(isFocused: false, native: native)
        XCTAssertNil(subject.setEnabled(true))
        XCTAssertEqual(native.requests, [true])

        native.error = "macOS did not confirm the Do Not Disturb change."
        XCTAssertEqual(subject.setEnabled(false), native.error)
        XCTAssertEqual(native.requests, [true, false], "The system checkbox must validate the target even when shared Focus status is stale")
    }

    func testExplicitShortcutsDoNotSilentlyUseControlCenter() {
        let native = FakeDoNotDisturbController()
        let subject = makeSwitch(isFocused: true, native: native, customShortcuts: true)

        XCTAssertNil(subject.setEnabled(true))
        XCTAssertTrue(native.requests.isEmpty)
    }

    func testPermissionFailureDoesNotOpenControlCenter() {
        let native = FakeDoNotDisturbController()
        let provider = FakeFocusStatusProvider(readings: [
            FocusStatusReading(authorization: .denied, isFocused: nil)
        ])
        let subject = DoNotDisturbSwitch(focusStatusProvider: provider, controlCenter: native, hasCustomShortcuts: { false })

        XCTAssertFalse(subject.snapshot().isAvailable)
        XCTAssertNotNil(subject.setEnabled(true))
        XCTAssertTrue(native.requests.isEmpty)
    }

    private func makeSwitch(
        isFocused: Bool,
        native: FakeDoNotDisturbController,
        customShortcuts: Bool = false
    ) -> DoNotDisturbSwitch {
        DoNotDisturbSwitch(
            focusStatusProvider: FakeFocusStatusProvider(readings: [
                FocusStatusReading(authorization: .authorized, isFocused: isFocused)
            ]),
            controlCenter: native,
            hasCustomShortcuts: { customShortcuts }
        )
    }
}

private final class FakeDoNotDisturbController: DoNotDisturbControlling, @unchecked Sendable {
    let isAvailable: Bool
    var error: String?
    private(set) var requests: [Bool] = []

    init(isAvailable: Bool = true) { self.isAvailable = isAvailable }

    func setEnabled(_ enabled: Bool) -> String? {
        requests.append(enabled)
        return error
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
