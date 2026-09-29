import CoreAudio
import Foundation

enum MicrophoneProperty: Sendable { case mute, volume }

protocol MicrophoneDeviceAccess: Sendable {
    var defaultInput: AudioDeviceID? { get }
    var devices: [AudioDeviceID] { get }
    func uid(_ device: AudioDeviceID) -> String?
    func channelCount(_ device: AudioDeviceID) -> UInt32?
    func value(_ property: MicrophoneProperty, device: AudioDeviceID, element: UInt32) -> Double?
    func canWrite(_ property: MicrophoneProperty, device: AudioDeviceID, element: UInt32) -> Bool
    func write(_ property: MicrophoneProperty, device: AudioDeviceID, element: UInt32, value: Double) -> Bool
}

struct MicrophoneRestorePoint: Codable, Equatable, Sendable {
    let uid: String
    let mute: [UInt32: Double]?
    let volume: [UInt32: Double]?
    let volumeBackup: [UInt32: Double]?
}

struct MuteMicrophoneSwitch: @unchecked Sendable {
    private let access: any MicrophoneDeviceAccess
    private let defaults: UserDefaults
    init(access: any MicrophoneDeviceAccess = CoreAudioMicrophoneAccess(), defaults: UserDefaults = .standard) {
        self.access = access
        self.defaults = defaults
    }
    private let channelsKey = "switch.muteMicrophone.previousChannelVolumes.v1"
    private let unavailable = "The microphone does not expose control for every input channel."

    func snapshot() -> SwitchSnapshot {
        guard let device = access.defaultInput else { return .init(isOn: false, isAvailable: false, subtitle: nil, warning: "No input device") }
        guard let plan = controlPlan(device) else { return .init(isOn: false, isAvailable: false, subtitle: nil, warning: unavailable) }
        let muted = plan.values.values.allSatisfy { plan.property == .mute ? $0 != 0 : $0 <= 0.001 }
        return .init(isOn: muted, isAvailable: true, subtitle: muted ? "The microphone has been muted" : nil, warning: nil)
    }

    func setEnabled(_ enabled: Bool) -> String? {
        guard let device = access.defaultInput else { return "No default input device." }
        return setEnabled(enabled, device: device)
    }

    func captureRestorePoint() -> MicrophoneRestorePoint? {
        guard let device = access.defaultInput, let uid = access.uid(device), !uid.isEmpty, controlPlan(device) != nil else { return nil }
        return MicrophoneRestorePoint(uid: uid, mute: readPlan(.mute, device: device), volume: readPlan(.volume, device: device),
                                      volumeBackup: savedVolumes(uid: uid))
    }

    func setEnabled(_ enabled: Bool, boundTo point: MicrophoneRestorePoint) -> String? {
        guard let device = resolve(point.uid) else { return "The original microphone is disconnected. Reconnect it and retry." }
        return setEnabled(enabled, device: device)
    }

    func restore(_ point: MicrophoneRestorePoint) -> String? {
        guard let device = resolve(point.uid) else { return "The original microphone is disconnected. Reconnect it and retry." }
        // Restore the captured channels, not the current default input or a volume average.
        if let volume = point.volume, !writeValues(volume, property: .volume, device: device) { return "Could not restore microphone input volume." }
        if let mute = point.mute, !writeValues(mute, property: .mute, device: device) { return "Could not restore microphone mute state." }
        saveVolumes(point.volumeBackup, uid: point.uid)
        return nil
    }

    private func resolve(_ uid: String) -> AudioDeviceID? {
        let matches = access.devices.filter { access.uid($0) == uid }
        return matches.count == 1 ? matches[0] : nil
    }

    private func setEnabled(_ enabled: Bool, device: AudioDeviceID) -> String? {
        guard let plan = controlPlan(device) else { return unavailable }
        let uid = access.uid(device)
        if plan.property == .mute {
            // A reconnected driver may expose mute after we previously used its volume controls.
            if !enabled, let uid, let saved = savedVolumes(uid: uid),
               !writeValues(saved, property: .volume, device: device) {
                return "Could not restore microphone input volume."
            }
            guard writeValues(plan.values.mapValues { _ in enabled ? 1 : 0 }, property: .mute, device: device) else {
                return "Could not change mute on every microphone input channel."
            }
            if !enabled, let uid { saveVolumes(nil, uid: uid) }
            return nil
        }
        guard let uid, !uid.isEmpty else { return "Could not identify the microphone for volume restoration." }
        if enabled {
            if plan.values.values.allSatisfy({ $0 <= 0.001 }) { return nil }
            saveVolumes(plan.values, uid: uid)
            return writeValues(plan.values.mapValues { _ in 0 }, property: .volume, device: device)
                ? nil : "Could not mute microphone input volume."
        }
        let saved = savedVolumes(uid: uid)
        let legacy = MicrophoneVolumeRestoreStore.volume(for: "uid:" + uid, defaults: defaults)
        let target = plan.values.mapValues { _ in legacy ?? 0.65 }.merging(saved ?? [:]) { _, original in original }
        guard Set(target.keys) == Set(plan.values.keys), writeValues(target, property: .volume, device: device) else {
            return "Could not restore microphone input volume."
        }
        saveVolumes(nil, uid: uid)
        MicrophoneVolumeRestoreStore.clear(for: "uid:" + uid, defaults: defaults)
        return nil
    }

    private func controlPlan(_ device: AudioDeviceID) -> (property: MicrophoneProperty, values: [UInt32: Double])? {
        for property in [MicrophoneProperty.mute, .volume] {
            if let values = readPlan(property, device: device), values.keys.allSatisfy({ access.canWrite(property, device: device, element: $0) }) {
                return (property, values)
            }
        }
        return nil
    }

    private func readPlan(_ property: MicrophoneProperty, device: AudioDeviceID) -> [UInt32: Double]? {
        let master = access.value(property, device: device, element: 0)
        if let master, access.canWrite(property, device: device, element: 0) { return [0: master] }
        if let count = access.channelCount(device), count > 0, count <= 512 {
            var values: [UInt32: Double] = [:]
            for element in 1...count {
                guard let value = access.value(property, device: device, element: element) else { return master.map { [0: $0] } }
                values[element] = value
            }
            return values
        }
        return master.map { [0: $0] }
    }

    private func writeValues(_ values: [UInt32: Double], property: MicrophoneProperty, device: AudioDeviceID) -> Bool {
        guard !values.isEmpty, let current = readPlan(property, device: device), Set(values.keys) == Set(current.keys),
              values.values.allSatisfy({ $0.isFinite && (0...1).contains($0) && (property == .volume || $0 == 0 || $0 == 1) }) else { return false }
        let changed = values.keys.filter { abs(values[$0]! - current[$0]!) > (property == .mute ? 0 : 0.001) }
        guard changed.allSatisfy({ access.canWrite(property, device: device, element: $0) }) else { return false }
        var succeeded = true
        for element in changed.sorted() {
            if !access.write(property, device: device, element: element, value: values[element]!) { succeeded = false; break }
        }
        if succeeded, waitForValues(values, property: property, device: device) { return true }
        // Best-effort rollback. The Mode journal / normal volume backup remains available for retry.
        for element in changed { _ = access.write(property, device: device, element: element, value: current[element]!) }
        return false
    }

    private func waitForValues(_ values: [UInt32: Double], property: MicrophoneProperty, device: AudioDeviceID) -> Bool {
        let deadline = Date().addingTimeInterval(0.8)
        repeat {
            if values.allSatisfy({ element, target in
                guard let actual = access.value(property, device: device, element: element) else { return false }
                return abs(actual - target) <= (property == .mute ? 0 : 0.001)
            }) { return true }
            Thread.sleep(forTimeInterval: 0.025)
        } while Date() < deadline
        return false
    }
    private func savedVolumes(uid: String) -> [UInt32: Double]? {
        guard let values = (defaults.dictionary(forKey: channelsKey)?[uid] as? [String: Double]) else { return nil }
        return Dictionary(uniqueKeysWithValues: values.compactMap { key, value in UInt32(key).map { ($0, value) } })
    }
    private func saveVolumes(_ values: [UInt32: Double]?, uid: String) {
        var all = defaults.dictionary(forKey: channelsKey) ?? [:]
        all[uid] = values.map { Dictionary(uniqueKeysWithValues: $0.map { (String($0.key), $0.value) }) }
        defaults.set(all, forKey: channelsKey)
    }
}

struct CoreAudioMicrophoneAccess: MicrophoneDeviceAccess {
    var defaultInput: AudioDeviceID? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: 0)
        var device: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        return AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr && device != 0 ? device : nil
    }
    var devices: [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: 0)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
        var result = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        let status = result.withUnsafeMutableBytes { bytes -> OSStatus in
            guard let pointer = bytes.baseAddress else { return -1 }
            return AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, pointer)
        }
        return status == noErr ? result : []
    }
    func uid(_ device: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceUID, mScope: kAudioObjectPropertyScopeGlobal, mElement: 0)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }
    func channelCount(_ device: AudioDeviceID) -> UInt32? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration, mScope: kAudioDevicePropertyScopeInput, mElement: 0)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr,
              size >= MemoryLayout<AudioBufferList>.size else { return nil }
        let storage = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { storage.deallocate() }
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, storage) == noErr else { return nil }
        return UnsafeMutableAudioBufferListPointer(storage.assumingMemoryBound(to: AudioBufferList.self)).reduce(0) { $0 + $1.mNumberChannels }
    }
    private func address(_ property: MicrophoneProperty, _ element: UInt32) -> AudioObjectPropertyAddress {
        .init(mSelector: property == .mute ? kAudioDevicePropertyMute : kAudioDevicePropertyVolumeScalar, mScope: kAudioDevicePropertyScopeInput, mElement: element)
    }
    func value(_ property: MicrophoneProperty, device: AudioDeviceID, element: UInt32) -> Double? {
        var address = address(property, element)
        if property == .mute {
            var value: UInt32 = 0; var size = UInt32(MemoryLayout<UInt32>.size)
            return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr ? Double(value) : nil
        }
        var value: Float32 = 0; var size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr && value.isFinite ? Double(value) : nil
    }
    func canWrite(_ property: MicrophoneProperty, device: AudioDeviceID, element: UInt32) -> Bool {
        var address = address(property, element); var writable = DarwinBoolean(false)
        return AudioObjectIsPropertySettable(device, &address, &writable) == noErr && writable.boolValue
    }
    func write(_ property: MicrophoneProperty, device: AudioDeviceID, element: UInt32, value: Double) -> Bool {
        var address = address(property, element)
        if property == .mute {
            var raw: UInt32 = value != 0 ? 1 : 0
            return AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &raw) == noErr
        }
        var raw = Float32(value)
        return AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &raw) == noErr
    }
}
