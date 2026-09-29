import CoreAudio
import Foundation
import XCTest
@testable import MacSwitch

final class MicrophoneBehaviorTests: XCTestCase {
    func testEightInputChannelsAreAllMutedAndVerified() {
        let driver = MemoryMicrophones()
        driver.add(1, uid: "A", channels: 8, mute: true)
        let subject = MuteMicrophoneSwitch(access: driver, defaults: InMemoryUserDefaults())
        XCTAssertNil(subject.setEnabled(true))
        XCTAssertEqual(driver.values(.mute, device: 1), Dictionary(uniqueKeysWithValues: (UInt32(1)...8).map { ($0, 1.0) }))
        XCTAssertTrue(subject.snapshot().isOn)
        XCTAssertNil(subject.setEnabled(false))
        XCTAssertTrue(driver.values(.mute, device: 1).values.allSatisfy { $0 == 0 })
    }

    func testIncompleteOrReadOnlyChannelsNeverReportMuteSuccess() {
        for missing in [false, true] {
            let driver = MemoryMicrophones()
            driver.add(1, uid: "A", channels: 8, mute: true)
            if missing { driver.remove(.mute, device: 1, element: 8) }
            else { driver.makeReadOnly(.mute, device: 1, element: 8) }
            let subject = MuteMicrophoneSwitch(access: driver, defaults: InMemoryUserDefaults())
            XCTAssertFalse(subject.snapshot().isAvailable)
            XCTAssertNotNil(subject.setEnabled(true))
            XCTAssertTrue(driver.writes.isEmpty)
        }
    }

    func testFailedChannelWriteRollsBackAndDoesNotReportMuted() {
        let driver = MemoryMicrophones()
        driver.add(1, uid: "A", channels: 8, mute: true)
        driver.rejectWrites(device: 1, element: 6)
        let subject = MuteMicrophoneSwitch(access: driver, defaults: InMemoryUserDefaults())
        XCTAssertNotNil(subject.setEnabled(true))
        XCTAssertFalse(subject.snapshot().isOn)
        XCTAssertTrue(driver.values(.mute, device: 1).values.allSatisfy { $0 == 0 })
    }

    func testAcceptedButIgnoredWriteIsDetectedAndRolledBack() {
        let driver = MemoryMicrophones()
        driver.add(1, uid: "A", channels: 3, mute: true)
        driver.ignoreWrites = true
        let subject = MuteMicrophoneSwitch(access: driver, defaults: InMemoryUserDefaults())
        XCTAssertNotNil(subject.setEnabled(true))
        XCTAssertFalse(subject.snapshot().isOn)
    }

    func testVolumeFallbackRestoresEveryChannelExactlyAfterRelaunch() {
        let driver = MemoryMicrophones(), defaults = InMemoryUserDefaults()
        driver.add(1, uid: "A", channels: 8, mute: false)
        let original = driver.values(.volume, device: 1)
        let subject = MuteMicrophoneSwitch(access: driver, defaults: defaults)
        XCTAssertNil(subject.setEnabled(true))
        XCTAssertTrue(subject.snapshot().isOn)
        XCTAssertNil(subject.setEnabled(true), "Repeated mute must preserve the original backup")
        let restarted = MuteMicrophoneSwitch(access: driver, defaults: defaults)
        XCTAssertNil(restarted.setEnabled(false))
        XCTAssertEqual(driver.values(.volume, device: 1), original)
    }

    func testModeRestoresOriginalDeviceAndMixedChannelStateAfterDefaultChanges() throws {
        let driver = MemoryMicrophones()
        driver.add(1, uid: "A", channels: 4, mute: true)
        driver.add(2, uid: "B", channels: 2, mute: true)
        _ = driver.write(.mute, device: 1, element: 2, value: 1)
        let original = driver.values(.mute, device: 1)
        let subject = MuteMicrophoneSwitch(access: driver, defaults: InMemoryUserDefaults())
        let point = try XCTUnwrap(subject.captureRestorePoint())
        driver.defaultInput = 2
        XCTAssertNil(subject.setEnabled(true, boundTo: point))
        XCTAssertTrue(driver.values(.mute, device: 1).values.allSatisfy { $0 == 1 })
        XCTAssertTrue(driver.values(.mute, device: 2).values.allSatisfy { $0 == 0 })
        XCTAssertNil(subject.restore(point))
        XCTAssertEqual(driver.values(.mute, device: 1), original)
        XCTAssertTrue(driver.values(.mute, device: 2).values.allSatisfy { $0 == 0 })
    }

    func testReconnectResolvesUIDInsteadOfReusedAudioObjectID() throws {
        let driver = MemoryMicrophones()
        driver.add(1, uid: "A", channels: 2, mute: true)
        let subject = MuteMicrophoneSwitch(access: driver, defaults: InMemoryUserDefaults())
        let point = try XCTUnwrap(subject.captureRestorePoint())
        driver.add(1, uid: "B", channels: 2, mute: true)
        XCTAssertNotNil(subject.restore(point))
        XCTAssertTrue(driver.writes.isEmpty)
        driver.add(9, uid: "A", channels: 2, mute: true)
        XCTAssertNil(subject.setEnabled(true, boundTo: point))
        XCTAssertNil(subject.restore(point))
        XCTAssertFalse(driver.writes.contains { $0.device == 1 })
    }

    func testVolumeBackupSurvivesModeAndNewMuteControl() throws {
        let driver = MemoryMicrophones(), defaults = InMemoryUserDefaults()
        driver.add(1, uid: "A", channels: 2, mute: false)
        let original = driver.values(.volume, device: 1)
        let subject = MuteMicrophoneSwitch(access: driver, defaults: defaults)
        XCTAssertNil(subject.setEnabled(true))
        let point = try XCTUnwrap(subject.captureRestorePoint())
        XCTAssertNil(subject.setEnabled(false, boundTo: point))
        XCTAssertNil(subject.restore(point))
        XCTAssertTrue(subject.snapshot().isOn)
        driver.addMuteControls(1)
        XCTAssertNil(subject.setEnabled(false))
        XCTAssertEqual(driver.values(.volume, device: 1), original)
    }
}

/// A CoreAudio boundary fake. All channel planning, mutation and readback use production code.
final class MemoryMicrophones: MicrophoneDeviceAccess, @unchecked Sendable {
    struct Address: Hashable { let property: MicrophoneProperty; let device: UInt32; let element: UInt32 }
    private let lock = NSLock()
    private var input: UInt32? = 1
    private var uids: [UInt32: String] = [:]
    private var counts: [UInt32: UInt32] = [:]
    private var data: [Address: Double] = [:]
    private var readOnly: Set<Address> = []
    private var rejected: Set<String> = []
    private var recorded: [Address] = []
    var ignoreWrites = false
    var defaultInput: UInt32? { get { lock.withLock { input } } set { lock.withLock { input = newValue } } }
    var devices: [UInt32] { lock.withLock { Array(uids.keys) } }
    var writes: [Address] { lock.withLock { recorded } }
    func add(_ device: UInt32, uid: String, channels: UInt32, mute: Bool) {
        lock.withLock {
            uids[device] = uid; counts[device] = channels
            data = data.filter { $0.key.device != device }
            for element in 1...channels {
                data[Address(property: mute ? .mute : .volume, device: device, element: element)] = mute ? 0 : Double(element) / Double(channels + 2)
            }
        }
    }
    func addMuteControls(_ device: UInt32) { lock.withLock { for element in 1...(counts[device] ?? 1) { data[.init(property: .mute, device: device, element: element)] = 0 } } }
    func disconnect(_ device: UInt32) { _ = lock.withLock { uids.removeValue(forKey: device) } }
    func uid(_ device: UInt32) -> String? { lock.withLock { uids[device] } }
    func channelCount(_ device: UInt32) -> UInt32? { lock.withLock { counts[device] } }
    func value(_ property: MicrophoneProperty, device: UInt32, element: UInt32) -> Double? {
        lock.withLock { data[.init(property: property, device: device, element: element)] }
    }
    func values(_ property: MicrophoneProperty, device: UInt32) -> [UInt32: Double] {
        lock.withLock { Dictionary(uniqueKeysWithValues: data.filter { $0.key.device == device && $0.key.property == property }.map { ($0.key.element, $0.value) }) }
    }
    func remove(_ property: MicrophoneProperty, device: UInt32, element: UInt32) { _ = lock.withLock { data.removeValue(forKey: .init(property: property, device: device, element: element)) } }
    func makeReadOnly(_ property: MicrophoneProperty, device: UInt32, element: UInt32) { _ = lock.withLock { readOnly.insert(.init(property: property, device: device, element: element)) } }
    func rejectWrites(device: UInt32, element: UInt32) { _ = lock.withLock { rejected.insert("\(device):\(element)") } }
    func canWrite(_ property: MicrophoneProperty, device: UInt32, element: UInt32) -> Bool {
        lock.withLock { let address = Address(property: property, device: device, element: element); return data[address] != nil && !readOnly.contains(address) }
    }
    func write(_ property: MicrophoneProperty, device: UInt32, element: UInt32, value: Double) -> Bool {
        lock.withLock {
            let address = Address(property: property, device: device, element: element)
            recorded.append(address)
            guard !readOnly.contains(address), !rejected.contains("\(device):\(element)"), data[address] != nil else { return false }
            if !ignoreWrites { data[address] = value }
            return true
        }
    }
}
