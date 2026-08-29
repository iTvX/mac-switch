import XCTest
@testable import MacSwitch

final class HandoffBehaviorTests: XCTestCase {
    func testUnsetPreferencesUseTheMacOSDefault() {
        let client = FakeHandoffPreferencesClient()
        let handoff = HandoffSwitch(client: client)

        let snapshot = handoff.snapshot()

        XCTAssertTrue(snapshot.isOn)
        XCTAssertTrue(snapshot.isAvailable)
        XCTAssertNil(snapshot.warning)
        XCTAssertEqual(client.synchronizeCallCount, 1)
    }

    func testSnapshotRequiresAdvertisingAndReceiving() {
        let client = FakeHandoffPreferencesClient(rawValues: [
            .advertising: true,
            .receiving: false
        ])
        let handoff = HandoffSwitch(client: client)

        let snapshot = handoff.snapshot()

        XCTAssertFalse(snapshot.isOn)
        XCTAssertEqual(snapshot.warning, "Handoff settings are inconsistent; toggle to repair them")
    }

    func testManagedPreferenceDisablesTheSwitchWithoutWriting() {
        let client = FakeHandoffPreferencesClient(
            rawValues: [.advertising: true, .receiving: true],
            forcedKeys: [.advertising]
        )
        let handoff = HandoffSwitch(client: client)

        let snapshot = handoff.snapshot()
        let error = handoff.setEnabled(false)

        XCTAssertFalse(snapshot.isAvailable)
        XCTAssertEqual(snapshot.warning, "Handoff is managed by your organization")
        XCTAssertEqual(error, "Handoff is managed by your organization.")
        XCTAssertTrue(client.writes.isEmpty)
        XCTAssertEqual(client.notificationCallCount, 0)
    }

    func testSuccessfulUpdateWritesBothKeysAndNotifiesTheService() {
        let client = FakeHandoffPreferencesClient(rawValues: [
            .advertising: true,
            .receiving: true
        ])
        let handoff = HandoffSwitch(client: client)

        XCTAssertNil(handoff.setEnabled(false))

        XCTAssertEqual(client.rawValue(for: .advertising), false)
        XCTAssertEqual(client.rawValue(for: .receiving), false)
        XCTAssertEqual(client.writes, [
            .init(key: .advertising, value: false),
            .init(key: .receiving, value: false)
        ])
        XCTAssertEqual(client.synchronizeCallCount, 2)
        XCTAssertEqual(client.notificationCallCount, 1)
    }

    func testInitialSynchronizationFailureMakesNoChanges() {
        let client = FakeHandoffPreferencesClient(
            rawValues: [.advertising: true, .receiving: true],
            synchronizeResults: [false]
        )
        let handoff = HandoffSwitch(client: client)

        let error = handoff.setEnabled(false)

        XCTAssertEqual(error, "Handoff settings could not be refreshed. No changes were made.")
        XCTAssertTrue(client.writes.isEmpty)
        XCTAssertEqual(client.notificationCallCount, 0)
    }

    func testPartialApplicationRestoresExactOriginalValues() {
        let client = FakeHandoffPreferencesClient(
            rawValues: [.advertising: true],
            ignoredWriteKeys: [.receiving]
        )
        let handoff = HandoffSwitch(client: client)

        let error = handoff.setEnabled(false)

        XCTAssertEqual(error, "Handoff could not be updated. Previous settings were restored.")
        XCTAssertEqual(client.rawValue(for: .advertising), true)
        XCTAssertNil(client.rawValue(for: .receiving))
        XCTAssertEqual(client.synchronizeCallCount, 3)
        XCTAssertEqual(client.notificationCallCount, 1)
    }

    func testNotificationFailureRollsBackThePersistentChange() {
        let client = FakeHandoffPreferencesClient(
            rawValues: [.advertising: true, .receiving: true],
            notificationResults: [false, true]
        )
        let handoff = HandoffSwitch(client: client)

        let error = handoff.setEnabled(false)

        XCTAssertEqual(error, "Handoff could not be updated. Previous settings were restored.")
        XCTAssertEqual(client.rawValue(for: .advertising), true)
        XCTAssertEqual(client.rawValue(for: .receiving), true)
        XCTAssertEqual(client.notificationCallCount, 2)
    }

    func testRollbackFailureReportsThatManualVerificationIsRequired() {
        let client = FakeHandoffPreferencesClient(
            rawValues: [.advertising: true, .receiving: true],
            synchronizeResults: [true, false, false]
        )
        let handoff = HandoffSwitch(client: client)

        let error = handoff.setEnabled(false)

        XCTAssertEqual(
            error,
            "Handoff could not be updated, and the previous settings could not be fully restored. Check AirDrop & Handoff in System Settings."
        )
    }

    func testHandoffTitleIsAvailableInEverySupportedLanguage() {
        for language in AppLanguage.allCases where language != .system {
            XCTAssertFalse(
                L10n.switchTitle(.handoff, language: language).isEmpty,
                "Missing Handoff title for \(language.rawValue)"
            )
        }
        XCTAssertEqual(L10n.switchTitle(.handoff, language: .simplifiedChinese), "接力")
        XCTAssertEqual(L10n.switchTitle(.handoff, language: .traditionalChinese), "接力")
    }

    func testRealSystemRoundTripWhenExplicitlyRequested() throws {
        guard ProcessInfo.processInfo.environment["MAC_SWITCH_HANDOFF_INTEGRATION"] == "1" else {
            throw XCTSkip("Set MAC_SWITCH_HANDOFF_INTEGRATION=1 to exercise the real macOS setting.")
        }

        let handoff = HandoffSwitch()
        let original = handoff.currentState()
        guard original.didSynchronize,
              !original.isManaged,
              original.isConsistent,
              original.rawAdvertising != nil,
              original.rawReceiving != nil
        else {
            throw XCTSkip("The real Handoff preferences are not safe for a reversible round trip.")
        }

        addTeardownBlock {
            XCTAssertNil(handoff.setEnabled(original.isEnabled))
        }

        let target = !original.isEnabled
        XCTAssertNil(handoff.setEnabled(target))
        let changed = handoff.currentState()
        XCTAssertEqual(changed.isEnabled, target)
        XCTAssertTrue(changed.isConsistent)

        XCTAssertNil(handoff.setEnabled(original.isEnabled))
        XCTAssertEqual(handoff.currentState().isEnabled, original.isEnabled)
    }
}

private final class FakeHandoffPreferencesClient: HandoffPreferencesClientProtocol, @unchecked Sendable {
    struct Write: Equatable {
        let key: HandoffPreferenceKey
        let value: Bool?
    }

    private let lock = NSLock()
    private var rawValues: [HandoffPreferenceKey: Bool]
    private let effectiveValues: [HandoffPreferenceKey: Bool]
    private let forcedKeys: Set<HandoffPreferenceKey>
    private let ignoredWriteKeys: Set<HandoffPreferenceKey>
    private var synchronizeResults: [Bool]
    private var notificationResults: [Bool]
    private(set) var writes: [Write] = []
    private(set) var synchronizeCallCount = 0
    private(set) var notificationCallCount = 0

    init(
        rawValues: [HandoffPreferenceKey: Bool] = [:],
        effectiveValues: [HandoffPreferenceKey: Bool] = [:],
        forcedKeys: Set<HandoffPreferenceKey> = [],
        ignoredWriteKeys: Set<HandoffPreferenceKey> = [],
        synchronizeResults: [Bool] = [],
        notificationResults: [Bool] = []
    ) {
        self.rawValues = rawValues
        self.effectiveValues = effectiveValues
        self.forcedKeys = forcedKeys
        self.ignoredWriteKeys = ignoredWriteKeys
        self.synchronizeResults = synchronizeResults
        self.notificationResults = notificationResults
    }

    func synchronize() -> Bool {
        lock.withLock {
            synchronizeCallCount += 1
            return synchronizeResults.isEmpty ? true : synchronizeResults.removeFirst()
        }
    }

    func rawValue(for key: HandoffPreferenceKey) -> Bool? {
        lock.withLock { rawValues[key] }
    }

    func effectiveValue(for key: HandoffPreferenceKey) -> Bool? {
        lock.withLock { effectiveValues[key] ?? rawValues[key] }
    }

    func isForced(_ key: HandoffPreferenceKey) -> Bool {
        forcedKeys.contains(key)
    }

    func setRawValue(_ value: Bool?, for key: HandoffPreferenceKey) {
        lock.withLock {
            writes.append(Write(key: key, value: value))
            guard !ignoredWriteKeys.contains(key) else { return }
            rawValues[key] = value
        }
    }

    func postChangeNotification() -> Bool {
        lock.withLock {
            notificationCallCount += 1
            return notificationResults.isEmpty ? true : notificationResults.removeFirst()
        }
    }
}
