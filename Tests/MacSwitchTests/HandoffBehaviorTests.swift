import XCTest
@testable import MacSwitch

final class HandoffBehaviorTests: XCTestCase {
    func testUnsetPreferencesUseTheMacOSDefault() {
        let client = FakeHandoffPreferencesClient()
        let handoff = makeHandoff(client)

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
        let handoff = makeHandoff(client)

        let snapshot = handoff.snapshot()

        XCTAssertFalse(snapshot.isOn)
        XCTAssertEqual(snapshot.warning, "Handoff settings are inconsistent; toggle to repair them")
    }

    func testManagedPreferenceDisablesTheSwitchWithoutWriting() {
        let client = FakeHandoffPreferencesClient(
            rawValues: [.advertising: true, .receiving: true],
            forcedKeys: [.advertising]
        )
        let handoff = makeHandoff(client)

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
        let handoff = makeHandoff(client)

        XCTAssertNil(handoff.setEnabled(false))

        XCTAssertEqual(client.rawValue(for: .advertising), false)
        XCTAssertEqual(client.rawValue(for: .receiving), false)
        XCTAssertEqual(client.writes, [
            .init(key: .advertising, value: false),
            .init(key: .receiving, value: false)
        ])
        XCTAssertEqual(client.batchWriteCallCount, 1)
        XCTAssertEqual(client.synchronizeCallCount, 3)
        XCTAssertEqual(client.notificationCallCount, 1)
    }

    func testSnapshotSynchronizationFailureDisablesTheSwitch() {
        let client = FakeHandoffPreferencesClient(
            rawValues: [.advertising: true, .receiving: true],
            synchronizeResults: [false]
        )
        let snapshot = makeHandoff(client).snapshot()

        XCTAssertTrue(snapshot.isOn)
        XCTAssertFalse(snapshot.isAvailable)
        XCTAssertEqual(snapshot.warning, "Handoff status could not be refreshed")
    }

    func testUnsupportedNotificationContractFailsClosedWithoutWriting() {
        let client = FakeHandoffPreferencesClient(
            rawValues: [.advertising: true, .receiving: true],
            supportsChangeNotification: false
        )
        let handoff = makeHandoff(client)

        let snapshot = handoff.snapshot()
        let error = handoff.setEnabled(false)

        XCTAssertFalse(snapshot.isAvailable)
        XCTAssertEqual(snapshot.warning, "Handoff control is unavailable on this macOS version")
        XCTAssertEqual(
            error,
            "Handoff control is unavailable on this macOS version. Use AirDrop & Handoff in System Settings."
        )
        XCTAssertTrue(client.writes.isEmpty)
        XCTAssertEqual(client.notificationCallCount, 0)
    }

    func testObserverRegistrationFailureKeepsManualControlAvailable() {
        let client = FakeHandoffPreferencesClient(
            rawValues: [.advertising: true, .receiving: true],
            supportsObservation: false
        )
        let handoff = makeHandoff(client)

        XCTAssertFalse(handoff.observeStatusChanges {})
        let snapshot = handoff.snapshot()

        XCTAssertTrue(snapshot.isOn)
        XCTAssertTrue(snapshot.isAvailable)
        XCTAssertEqual(snapshot.warning, "Automatic Handoff status updates are unavailable; use Refresh")
    }

    func testInitialSynchronizationFailureMakesNoChanges() {
        let client = FakeHandoffPreferencesClient(
            rawValues: [.advertising: true, .receiving: true],
            synchronizeResults: [false]
        )
        let handoff = makeHandoff(client)

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
        let handoff = makeHandoff(client)

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
        let handoff = makeHandoff(client)

        let error = handoff.setEnabled(false)

        XCTAssertEqual(error, "Handoff could not be updated. Previous settings were restored.")
        XCTAssertEqual(client.rawValue(for: .advertising), true)
        XCTAssertEqual(client.rawValue(for: .receiving), true)
        XCTAssertEqual(client.notificationCallCount, 2)
    }

    func testPostNotificationVerificationRollsBackARevertedSetting() {
        let client = FakeHandoffPreferencesClient(
            rawValues: [.advertising: true, .receiving: true],
            rawValuesAfterFirstNotification: [.advertising: true, .receiving: true]
        )
        let handoff = makeHandoff(client)

        let error = handoff.setEnabled(false)

        XCTAssertEqual(error, "Handoff could not be updated. Previous settings were restored.")
        XCTAssertEqual(client.rawValue(for: .advertising), true)
        XCTAssertEqual(client.rawValue(for: .receiving), true)
        XCTAssertEqual(client.batchWriteCallCount, 2)
        XCTAssertEqual(client.notificationCallCount, 2)
    }

    func testManagedRestrictionWithForcedDisabledValueCannotBeOverridden() {
        let client = FakeHandoffPreferencesClient(
            rawValues: [.advertising: true, .receiving: true],
            effectiveValues: [.advertising: false, .receiving: false],
            forcedKeys: [.advertising, .receiving]
        )
        let handoff = makeHandoff(client)

        let snapshot = handoff.snapshot()
        let error = handoff.setEnabled(true)

        XCTAssertFalse(snapshot.isOn)
        XCTAssertFalse(snapshot.isAvailable)
        XCTAssertEqual(snapshot.warning, "Handoff is managed by your organization")
        XCTAssertEqual(error, "Handoff is managed by your organization.")
        XCTAssertTrue(client.writes.isEmpty)
    }

    func testCurrentMacOSResolvesAndDeliversTheHandoffNotification() throws {
        let notificationName = try XCTUnwrap(HandoffDarwinNotification.resolvedName)
        XCTAssertTrue(notificationName.hasSuffix("ActivityContinuationIsEnabledChangedNotification"))

        let delivered = expectation(description: "Darwin Handoff notification delivered")
        delivered.assertForOverFulfill = false
        let handoff = HandoffSwitch(waitForPropagation: {})
        XCTAssertTrue(handoff.observeStatusChanges {
            delivered.fulfill()
        })
        XCTAssertTrue(HandoffDarwinNotification.post())
        wait(for: [delivered], timeout: 2)
    }

    func testCurrentMacOSReadDoesNotMutateHandoffPreferences() {
        let handoff = HandoffSwitch(waitForPropagation: {})
        let before = handoff.currentState()
        let after = handoff.currentState()

        XCTAssertTrue(before.didSynchronize)
        XCTAssertTrue(before.notificationContractAvailable)
        XCTAssertEqual(after.rawAdvertising, before.rawAdvertising)
        XCTAssertEqual(after.rawReceiving, before.rawReceiving)
        XCTAssertEqual(after.isEnabled, before.isEnabled)
    }

    func testPeriodicRefreshPolicyUsesNotificationsAndFiveMinuteFallback() {
        let now = Date(timeIntervalSince1970: 10_000)

        XCTAssertTrue(HandoffRefreshPolicy.shouldPerformPeriodicRefresh(lastRefresh: nil, now: now))
        XCTAssertFalse(
            HandoffRefreshPolicy.shouldPerformPeriodicRefresh(
                lastRefresh: now.addingTimeInterval(-(5 * 60 - 1)),
                now: now
            )
        )
        XCTAssertTrue(
            HandoffRefreshPolicy.shouldPerformPeriodicRefresh(
                lastRefresh: now.addingTimeInterval(-(5 * 60)),
                now: now
            )
        )
    }

    func testRuntimeCompatibilityFailsClosedOutsideVerifiedMacOSVersions() {
        func version(_ major: Int) -> OperatingSystemVersion {
            OperatingSystemVersion(majorVersion: major, minorVersion: 0, patchVersion: 0)
        }

        XCTAssertFalse(
            HandoffRuntimeCompatibility.supports(osVersion: version(13), notificationContractAvailable: true)
        )
        XCTAssertTrue(
            HandoffRuntimeCompatibility.supports(osVersion: version(14), notificationContractAvailable: true)
        )
        XCTAssertFalse(
            HandoffRuntimeCompatibility.supports(osVersion: version(16), notificationContractAvailable: true)
        )
        XCTAssertTrue(
            HandoffRuntimeCompatibility.supports(osVersion: version(26), notificationContractAvailable: true)
        )
        XCTAssertFalse(
            HandoffRuntimeCompatibility.supports(osVersion: version(27), notificationContractAvailable: true)
        )
        XCTAssertFalse(
            HandoffRuntimeCompatibility.supports(osVersion: version(26), notificationContractAvailable: false)
        )
    }

    func testRollbackFailureReportsThatManualVerificationIsRequired() {
        let client = FakeHandoffPreferencesClient(
            rawValues: [.advertising: true, .receiving: true],
            synchronizeResults: [true, false, false]
        )
        let handoff = makeHandoff(client)

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
              original.notificationContractAvailable,
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

    private func makeHandoff(_ client: FakeHandoffPreferencesClient) -> HandoffSwitch {
        HandoffSwitch(client: client, waitForPropagation: {})
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
    let supportsChangeNotification: Bool
    private let supportsObservation: Bool
    private let forcedKeys: Set<HandoffPreferenceKey>
    private let ignoredWriteKeys: Set<HandoffPreferenceKey>
    private let rawValuesAfterFirstNotification: [HandoffPreferenceKey: Bool]?
    private var synchronizeResults: [Bool]
    private var notificationResults: [Bool]
    private(set) var writes: [Write] = []
    private(set) var batchWriteCallCount = 0
    private(set) var synchronizeCallCount = 0
    private(set) var notificationCallCount = 0

    init(
        rawValues: [HandoffPreferenceKey: Bool] = [:],
        effectiveValues: [HandoffPreferenceKey: Bool] = [:],
        supportsChangeNotification: Bool = true,
        supportsObservation: Bool = true,
        forcedKeys: Set<HandoffPreferenceKey> = [],
        ignoredWriteKeys: Set<HandoffPreferenceKey> = [],
        rawValuesAfterFirstNotification: [HandoffPreferenceKey: Bool]? = nil,
        synchronizeResults: [Bool] = [],
        notificationResults: [Bool] = []
    ) {
        self.rawValues = rawValues
        self.effectiveValues = effectiveValues
        self.supportsChangeNotification = supportsChangeNotification
        self.supportsObservation = supportsObservation
        self.forcedKeys = forcedKeys
        self.ignoredWriteKeys = ignoredWriteKeys
        self.rawValuesAfterFirstNotification = rawValuesAfterFirstNotification
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

    func setRawValues(advertising: Bool?, receiving: Bool?) {
        lock.withLock {
            batchWriteCallCount += 1
            for (key, value) in [
                (HandoffPreferenceKey.advertising, advertising),
                (HandoffPreferenceKey.receiving, receiving)
            ] {
                writes.append(Write(key: key, value: value))
                guard !ignoredWriteKeys.contains(key) else { continue }
                rawValues[key] = value
            }
        }
    }

    func postChangeNotification() -> Bool {
        lock.withLock {
            notificationCallCount += 1
            if notificationCallCount == 1, let rawValuesAfterFirstNotification {
                rawValues = rawValuesAfterFirstNotification
            }
            return notificationResults.isEmpty ? true : notificationResults.removeFirst()
        }
    }

    func observeChanges(_ handler: @escaping @Sendable () -> Void) -> (any HandoffChangeObservation)? {
        supportsObservation ? FakeHandoffChangeObservation() : nil
    }
}

private final class FakeHandoffChangeObservation: HandoffChangeObservation, @unchecked Sendable {}
