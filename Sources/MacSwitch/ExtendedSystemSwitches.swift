import AppKit
import CoreAudio
import CoreGraphics
import Foundation
import IOBluetooth

private func switchSnapshot(
    isOn: Bool = false,
    isAvailable: Bool = true,
    subtitle: String? = nil,
    warning: String? = nil
) -> SwitchSnapshot {
    SwitchSnapshot(isOn: isOn, isAvailable: isAvailable, subtitle: subtitle, warning: warning)
}

private let unsupportedSystemMessage = "This control is not available on your current system."

private func actionResult(_ subtitle: String, error: String? = nil) -> SwitchOperationResult {
    SwitchOperationResult(
        snapshot: switchSnapshot(isOn: false, isAvailable: true, subtitle: error == nil ? subtitle : nil, warning: error),
        error: error
    )
}

private func conciseOneLineFailure(_ message: String, limit: Int = 180) -> String {
    let trimmed = message
        .split(whereSeparator: \.isNewline)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first { !$0.isEmpty }
        ?? "Unknown error."
    guard trimmed.count > limit else { return trimmed }
    return String(trimmed.prefix(max(limit - 3, 0))) + "..."
}

private func unavailableActionResult(_ subtitle: String) -> SwitchOperationResult {
    SwitchOperationResult(
        snapshot: switchSnapshot(isOn: false, isAvailable: false, subtitle: subtitle),
        error: nil
    )
}

private func playActionSound(named name: String = "Glass") {
    DispatchQueue.main.async {
        NSSound(named: NSSound.Name(name))?.play()
    }
}

private func waitForCondition(
    timeout: TimeInterval = 0.8,
    interval: TimeInterval = 0.05,
    _ condition: () -> Bool
) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
        if condition() {
            return true
        }
        _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(interval))
    } while Date() < deadline
    return condition()
}

private enum DefaultsBoolSwitch {
    static func read(domain: String, key: String, default defaultValue: Bool) -> Bool {
        readStoredValue(domain: domain, key: key) ?? defaultValue
    }

    private static func readStoredValue(domain: String, key: String) -> Bool? {
        let result = ProcessRunner.run("/usr/bin/defaults", ["read", domain, key], timeout: 2)
        guard result.status == 0 else { return nil }
        let value = result.output.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return value == "1" || value == "true" || value == "yes"
    }

    static func write(_ enabled: Bool, domain: String, key: String, restart processName: String?) -> String? {
        let result = ProcessRunner.run("/usr/bin/defaults", [
            "write", domain, key, "-bool", enabled ? "true" : "false"
        ], timeout: 2)
        if result.status != 0 {
            return ProcessRunner.failureMessage(for: result, fallback: "Could not update \(key).")
        }
        guard readStoredValue(domain: domain, key: key) == enabled else {
            return "macOS accepted the request, but \(key) did not change."
        }
        if let processName {
            return restartProcessOrReport(
                processName,
                failureMessage: "Updated \(key), but could not restart \(processName) to apply it."
            )
        }
        return nil
    }
}

struct BluetoothAudioDeviceOption: Identifiable, Equatable {
    var id: String { address }
    let address: String
    let name: String
    let isConnected: Bool
}

enum BluetoothAudioPreferences {
    static let selectedAddressKey = "switch.bluetoothAudio.selectedAddress"
    private static let legacySelectedAddressKey = ["switch.", "headphones", "Connect.selectedAddress"].joined()

    static var selectedAddress: String {
        get {
            let defaults = UserDefaults.standard
            if let value = defaults.string(forKey: selectedAddressKey) {
                return normalizedAddress(value)
            }
            return normalizedAddress(defaults.string(forKey: legacySelectedAddressKey) ?? "")
        }
        set {
            let defaults = UserDefaults.standard
            defaults.set(normalizedAddress(newValue), forKey: selectedAddressKey)
            defaults.removeObject(forKey: legacySelectedAddressKey)
        }
    }

    static var deviceOptions: [BluetoothAudioDeviceOption] {
        audioDevices.map {
            BluetoothAudioDeviceOption(
                address: $0.addressString,
                name: $0.nameOrAddress,
                isConnected: $0.isConnected()
            )
        }
        .sorted {
            if $0.isConnected != $1.isConnected {
                return $0.isConnected && !$1.isConnected
            }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    static var bluetoothPoweredOn: Bool {
        IOBluetoothHostController.default()?.powerState == kBluetoothHCIPowerStateON
    }

    fileprivate static var audioDevices: [IOBluetoothDevice] {
        let paired = (IOBluetoothDevice.pairedDevices() ?? []).compactMap { $0 as? IOBluetoothDevice }
        return paired.filter(isHeadphoneDevice)
    }

    fileprivate static var selectedDevice: IOBluetoothDevice? {
        let selected = selectedAddress
        guard !selected.isEmpty else { return nil }
        return audioDevices.first {
            $0.addressString.caseInsensitiveCompare(selected) == .orderedSame
        }
    }

    static var selectedDeviceMissing: Bool {
        !selectedAddress.isEmpty && selectedDevice == nil
    }

    fileprivate static func targetDeviceForConnect() -> IOBluetoothDevice? {
        selectedDevice
            ?? audioDevices.first(where: { !$0.isConnected() })
            ?? audioDevices.first
    }

    private static func normalizedAddress(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    fileprivate static func statusSubtitle(for device: IOBluetoothDevice, connected: Bool) -> String {
        if connected {
            return batterySubtitle(for: device) ?? "Connected"
        }
        return "Disconnected"
    }

    private static func isHeadphoneDevice(_ device: IOBluetoothDevice) -> Bool {
        if device.deviceClassMajor == kBluetoothDeviceClassMajorAudio {
            return true
        }
        let name = (device.name ?? "").lowercased()
        return ["airpods", "headphone", "headset", "earbuds", "buds", "beats", "bose", "sony", "jabra", "wh-", "wf-"]
            .contains { name.contains($0) }
    }

    private static func batterySubtitle(for device: IOBluetoothDevice) -> String? {
        let name = (device.nameOrAddress ?? "").lowercased()
        guard name.contains("airpods") else { return nil }

        let left = batteryPercent("batteryPercentLeft", for: device)
        let right = batteryPercent("batteryPercentRight", for: device)
        let single = batteryPercent("batteryPercentSingle", for: device)

        if let left, let right {
            return "Left: \(left)% - Right: \(right)%"
        }
        if let single {
            return "Battery: \(single)%"
        }
        return nil
    }

    private static func batteryPercent(_ key: String, for device: IOBluetoothDevice) -> Int? {
        let selector = NSSelectorFromString(key)
        guard device.responds(to: selector),
              let value = device.value(forKey: key) as? Int,
              value > 0
        else { return nil }
        return value
    }
}

struct DisplayModeOption: Identifiable, Equatable {
    let id: Int
    let width: Int
    let height: Int
    let pixelWidth: Int
    let pixelHeight: Int
    let refreshRate: Double
    let isHiDPI: Bool

    var title: String {
        var text = "\(width)x\(height)"
        if isHiDPI {
            text += " HiDPI"
        }
        if refreshRate > 1 {
            text += " \(Int(refreshRate.rounded()))Hz"
        }
        return text
    }
}

struct DisplayOption: Identifiable, Equatable {
    let id: Int
    let displayID: CGDirectDisplayID
    let title: String
}

struct EjectableVolumeOption: Identifiable, Equatable {
    var id: String { path }
    let url: URL
    let path: String
    let name: String
    let isExcluded: Bool
    let isBuiltInExcluded: Bool
}

enum ScreenResolutionPreferences {
    static let selectedDisplayIndexKey = "switch.screenResolution.selectedDisplayIndex"
    static let selectedDisplaySignatureKey = "switch.screenResolution.selectedDisplaySignature"
    static let legacySelectedModeIDKey = "switch.screenResolution.selectedModeID"
    static let onlyHiDPIKey = "switch.screenResolution.onlyHiDPI"
    static let legacyPreviousModeKey = "switch.screenResolution.previousMode"

    static var selectedDisplayIndex: Int {
        get {
            selectedDisplayIndex(in: displayOptions)
        }
        set {
            setSelectedDisplayIndex(newValue)
        }
    }

    static func selectedDisplayIndex(in displays: [DisplayOption]) -> Int {
        guard !displays.isEmpty else { return 0 }
        if let storedSignature = UserDefaults.standard.string(forKey: selectedDisplaySignatureKey),
           !storedSignature.isEmpty,
           let matchedIndex = displays.firstIndex(where: { displaySignature(for: $0.displayID) == storedSignature }) {
            return matchedIndex
        }
        let stored = UserDefaults.standard.integer(forKey: selectedDisplayIndexKey)
        if displays.indices.contains(stored) {
            return stored
        }
        return displays.firstIndex { CGDisplayIsMain($0.displayID) != 0 } ?? 0
    }

    static func setSelectedDisplayIndex(_ newValue: Int, in displays: [DisplayOption]? = nil) {
        let availableDisplays = displays ?? displayOptions
        let safeIndex: Int
        if availableDisplays.isEmpty {
            safeIndex = max(0, newValue)
        } else if availableDisplays.indices.contains(newValue) {
            safeIndex = newValue
        } else {
            safeIndex = availableDisplays.firstIndex { CGDisplayIsMain($0.displayID) != 0 } ?? 0
        }

        UserDefaults.standard.set(safeIndex, forKey: selectedDisplayIndexKey)
        if availableDisplays.indices.contains(safeIndex) {
            UserDefaults.standard.set(displaySignature(for: availableDisplays[safeIndex].displayID), forKey: selectedDisplaySignatureKey)
        }
    }

    static var selectedDisplayID: CGDirectDisplayID? {
        let displays = displayOptions
        guard !displays.isEmpty else { return nil }
        let index = selectedDisplayIndex(in: displays)
        return displays.indices.contains(index) ? displays[index].displayID : displays[0].displayID
    }

    static var selectedDisplayTitle: String? {
        guard let displayID = selectedDisplayID else { return nil }
        return displayTitle(for: displayID)
    }

    static var displayOptions: [DisplayOption] {
        let ids = onlineDisplayIDs
        return ids.enumerated().map { index, displayID in
            DisplayOption(
                id: index,
                displayID: displayID,
                title: displayTitle(for: displayID, index: index, total: ids.count)
            )
        }
    }

    static var selectedModeID: Int {
        get {
            selectedModeID(for: selectedDisplayID)
        }
        set {
            setSelectedModeID(newValue, for: selectedDisplayID)
        }
    }

    static func selectedModeID(for displayID: CGDirectDisplayID?) -> Int {
        guard let displayID else {
            return UserDefaults.standard.integer(forKey: legacySelectedModeIDKey)
        }
        if let stored = UserDefaults.standard.object(forKey: selectedModeKey(for: displayID)) as? Int {
            return stored
        }
        return UserDefaults.standard.integer(forKey: legacySelectedModeIDKey)
    }

    static func setSelectedModeID(_ newValue: Int, for displayID: CGDirectDisplayID?) {
        guard let displayID else {
            UserDefaults.standard.set(newValue, forKey: legacySelectedModeIDKey)
            return
        }
        UserDefaults.standard.set(newValue, forKey: selectedModeKey(for: displayID))
    }

    static var onlyHiDPI: Bool {
        get { UserDefaults.standard.object(forKey: onlyHiDPIKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: onlyHiDPIKey) }
    }

    static var modeOptions: [DisplayModeOption] {
        guard let displayID = selectedDisplayID else { return [] }
        return modeOptions(for: displayID, onlyHiDPI: onlyHiDPI)
    }

    static var allModeOptions: [DisplayModeOption] {
        guard let displayID = selectedDisplayID else { return [] }
        return displayModes(for: displayID).map(option)
            .sorted {
                if $0.width == $1.width {
                    if $0.height == $1.height { return $0.refreshRate > $1.refreshRate }
                    return $0.height > $1.height
                }
                return $0.width > $1.width
            }
    }

    static func modeOptions(for displayID: CGDirectDisplayID, onlyHiDPI: Bool) -> [DisplayModeOption] {
        displayModes(for: displayID)
            .map(option)
            .filter { !onlyHiDPI || $0.isHiDPI }
            .sorted {
                if $0.width == $1.width {
                    if $0.height == $1.height { return $0.refreshRate > $1.refreshRate }
                    return $0.height > $1.height
                }
                return $0.width > $1.width
            }
    }

    static func currentModeTitle(for displayID: CGDirectDisplayID) -> String? {
        CGDisplayCopyDisplayMode(displayID).map { option($0).title }
    }

    static var selectedModeTitle: String? {
        guard selectedModeID != 0,
              let option = modeOptions.first(where: { $0.id == selectedModeID })
        else { return nil }
        return option.title
    }

    static var currentModeID: Int? {
        guard let displayID = selectedDisplayID else { return nil }
        return CGDisplayCopyDisplayMode(displayID).map(modeID)
    }

    fileprivate static func selectedMode(for displayID: CGDirectDisplayID) -> CGDisplayMode? {
        let storedModeID = selectedModeID(for: displayID)
        guard storedModeID != 0 else { return nil }
        return displayModes(for: displayID).first { modeID($0) == storedModeID }
    }

    fileprivate static func displayModes(for displayID: CGDirectDisplayID) -> [CGDisplayMode] {
        let options = [kCGDisplayShowDuplicateLowResolutionModes as String: true] as CFDictionary
        let modes = CGDisplayCopyAllDisplayModes(displayID, options) as? [CGDisplayMode]
        return modes?.filter { $0.isUsableForDesktopGUI() } ?? []
    }

    fileprivate static func modeID(_ mode: CGDisplayMode) -> Int {
        Int(mode.ioDisplayModeID)
    }

    fileprivate static func option(_ mode: CGDisplayMode) -> DisplayModeOption {
        DisplayModeOption(
            id: modeID(mode),
            width: mode.width,
            height: mode.height,
            pixelWidth: mode.pixelWidth,
            pixelHeight: mode.pixelHeight,
            refreshRate: mode.refreshRate,
            isHiDPI: mode.pixelWidth > mode.width || mode.pixelHeight > mode.height
        )
    }

    fileprivate static func previousModeKey(for displayID: CGDirectDisplayID) -> String {
        "switch.screenResolution.previousMode.\(displaySignature(for: displayID))"
    }

    fileprivate static func previousMode(for displayID: CGDirectDisplayID) -> Int? {
        let key = previousModeKey(for: displayID)
        if let stored = UserDefaults.standard.object(forKey: key) as? Int {
            return stored
        }
        if displayOptions.count == 1,
           let legacy = UserDefaults.standard.object(forKey: legacyPreviousModeKey) as? Int {
            return legacy
        }
        return nil
    }

    fileprivate static func setPreviousMode(_ modeID: Int, for displayID: CGDirectDisplayID) {
        UserDefaults.standard.set(modeID, forKey: previousModeKey(for: displayID))
    }

    fileprivate static func clearPreviousMode(for displayID: CGDirectDisplayID) {
        UserDefaults.standard.removeObject(forKey: previousModeKey(for: displayID))
        if displayOptions.count == 1 {
            UserDefaults.standard.removeObject(forKey: legacyPreviousModeKey)
        }
    }

    fileprivate static func selectedModeKey(for displayID: CGDirectDisplayID) -> String {
        "switch.screenResolution.selectedModeID.\(displaySignature(for: displayID))"
    }

    fileprivate static func displayTitle(for displayID: CGDirectDisplayID) -> String {
        let displays = displayOptions
        if let option = displays.first(where: { $0.displayID == displayID }) {
            return option.title
        }
        return displayTitle(for: displayID, index: 0, total: displays.count)
    }

    private static var onlineDisplayIDs: [CGDirectDisplayID] {
        var count: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &count)
        guard count > 0 else { return [CGMainDisplayID()] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetOnlineDisplayList(count, &ids, &count)
        return Array(ids.prefix(Int(count)))
    }

    private static func displayTitle(for displayID: CGDirectDisplayID, index: Int, total: Int) -> String {
        let base = CGDisplayIsMain(displayID) != 0 ? "Main Display" : "Display \(index + 1)"
        let size: String
        if let mode = CGDisplayCopyDisplayMode(displayID) {
            size = "\(mode.width)x\(mode.height)"
        } else {
            size = "\(CGDisplayPixelsWide(displayID))x\(CGDisplayPixelsHigh(displayID))"
        }
        return "\(base) (\(size))"
    }

    private static func displaySignature(for displayID: CGDirectDisplayID) -> String {
        let vendor = CGDisplayVendorNumber(displayID)
        let model = CGDisplayModelNumber(displayID)
        let serial = CGDisplaySerialNumber(displayID)
        if vendor != 0 || model != 0 || serial != 0 {
            return "\(vendor)-\(model)-\(serial)"
        }
        return "\(displayID)"
    }
}

enum DoNotDisturbPreferences {
    static let onShortcut = "Mac Switch DND On"
    static let offShortcut = "Mac Switch DND Off"
    static let stateKey = "switch.doNotDisturb.lastState"
    private static let customOnShortcutKey = "switch.doNotDisturb.customOnShortcutName"
    private static let customOffShortcutKey = "switch.doNotDisturb.customOffShortcutName"
    private static let cacheTTL: TimeInterval = 5
    private static let cacheQueue = DispatchQueue(label: "com.maxyu.macswitch.dnd-shortcut-cache")
    private static var shortcutCache: (date: Date, shortcuts: Set<String>, error: String?)?

    static var customOnShortcutName: String {
        get { UserDefaults.standard.string(forKey: customOnShortcutKey) ?? "" }
        set {
            UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: customOnShortcutKey)
            invalidateInstalledShortcutsCache()
        }
    }

    static var customOffShortcutName: String {
        get { UserDefaults.standard.string(forKey: customOffShortcutKey) ?? "" }
        set {
            UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: customOffShortcutKey)
            invalidateInstalledShortcutsCache()
        }
    }

    static var onShortcutCandidates: [String] {
        shortcutCandidates(custom: customOnShortcutName, defaults: [onShortcut, "DND On", "Focus On"])
    }

    static var offShortcutCandidates: [String] {
        shortcutCandidates(custom: customOffShortcutName, defaults: [offShortcut, "DND Off", "Focus Off"])
    }

    static var shortcutConfigurationError: String? {
        let customOn = customOnShortcutName.trimmingCharacters(in: .whitespacesAndNewlines)
        let customOff = customOffShortcutName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !customOn.isEmpty, !customOff.isEmpty else { return nil }
        if customOn.compare(customOff, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame {
            return "Use different shortcut names for DND On and DND Off."
        }
        return nil
    }

    static var installedShortcuts: Set<String> {
        loadInstalledShortcuts(forceRefresh: false)
    }

    static func refreshInstalledShortcuts() -> Set<String> {
        loadInstalledShortcuts(forceRefresh: true)
    }

    static func invalidateInstalledShortcutsCache() {
        cacheQueue.sync {
            shortcutCache = nil
        }
    }

    static var installedShortcutsError: String? {
        cacheQueue.sync {
            shortcutCache?.error
        }
    }

    private static func loadInstalledShortcuts(forceRefresh: Bool) -> Set<String> {
        if !forceRefresh,
           let cached = cacheQueue.sync(execute: { shortcutCache }),
           Date().timeIntervalSince(cached.date) < cacheTTL {
            return cached.shortcuts
        }

        let result = ProcessRunner.run("/usr/bin/shortcuts", ["list"], timeout: 2)
        guard result.status == 0 else {
            let error = conciseOneLineFailure(
                ProcessRunner.failureMessage(for: result, fallback: "Could not read Shortcuts.")
            )
            cacheQueue.sync {
                shortcutCache = (Date(), [], error)
            }
            return []
        }
        let shortcuts = Set(result.output.split(separator: "\n").map { normalizedShortcutName(String($0)) }.filter { !$0.isEmpty })
        cacheQueue.sync {
            shortcutCache = (Date(), shortcuts, nil)
        }
        return shortcuts
    }

    static var onShortcutInstalled: Bool {
        installedShortcutName(matching: onShortcutCandidates, in: installedShortcuts) != nil
    }

    static var offShortcutInstalled: Bool {
        installedShortcutName(matching: offShortcutCandidates, in: installedShortcuts) != nil
    }

    static var allShortcutsInstalled: Bool {
        allShortcutsInstalled(forceRefresh: false)
    }

    static func allShortcutsInstalled(forceRefresh: Bool) -> Bool {
        guard shortcutConfigurationError == nil else { return false }
        let installed = forceRefresh ? refreshInstalledShortcuts() : installedShortcuts
        return installedShortcutPair(in: installed) != nil
    }

    static var installedOnShortcutName: String {
        installedShortcutPair(in: installedShortcuts)?.on ?? onShortcut
    }

    static var installedOffShortcutName: String {
        installedShortcutPair(in: installedShortcuts)?.off ?? offShortcut
    }

    static func installedShortcutPair(in installed: Set<String>) -> (on: String, off: String)? {
        guard let on = installedShortcutName(matching: onShortcutCandidates, in: installed),
              let off = installedShortcutName(matching: offShortcutCandidates, in: installed),
              shortcutMatchKey(on) != shortcutMatchKey(off)
        else {
            return nil
        }
        return (on, off)
    }

    static func installedShortcutName(matching candidates: [String], in installed: Set<String>) -> String? {
        let installedByKey = installedShortcutsByMatchKey(installed)
        for candidate in candidates {
            if let installedName = installedByKey[shortcutMatchKey(candidate)] {
                return installedName
            }
        }
        return nil
    }

    private static func shortcutCandidates(custom: String, defaults: [String]) -> [String] {
        var seen: Set<String> = []
        let normalizedCustom = normalizedShortcutName(custom)
        let names = normalizedCustom.isEmpty ? defaults : [normalizedCustom]
        return names
            .map(normalizedShortcutName)
            .filter { !$0.isEmpty }
            .filter { seen.insert(shortcutMatchKey($0)).inserted }
    }

    private static func normalizedShortcutName(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func shortcutMatchKey(_ value: String) -> String {
        normalizedShortcutName(value)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }

    private static func installedShortcutsByMatchKey(_ installed: Set<String>) -> [String: String] {
        var result: [String: String] = [:]
        for name in installed {
            let normalized = normalizedShortcutName(name)
            let key = shortcutMatchKey(normalized)
            if !key.isEmpty, result[key] == nil {
                result[key] = normalized
            }
        }
        return result
    }

}

enum EjectDiskPreferences {
    private static let excludedPathsKey = "switch.ejectDisk.excludedPaths"
    private static let builtInExcludedPaths: Set<String> = ["/Volumes/BOOTCAMP"]
    private static let builtInExcludedPathPrefixes: [String] = [
        "/Library/Developer/CoreSimulator/Volumes"
    ]

    static var excludedPaths: [String] {
        get { normalizedExclusionPaths(UserDefaults.standard.stringArray(forKey: excludedPathsKey) ?? []) }
        set { UserDefaults.standard.set(normalizedExclusionPaths(newValue), forKey: excludedPathsKey) }
    }

    @discardableResult
    static func add(_ urls: [URL]) -> Bool {
        let paths = urls.compactMap(exclusionPath).compactMap(normalizedExclusionPath)
        guard !paths.isEmpty else { return false }
        excludedPaths = excludedPaths + paths
        return true
    }

    static func remove(_ path: String) {
        guard let normalized = normalizedExclusionPath(path) else { return }
        excludedPaths = excludedPaths.filter { $0 != normalized }
    }

    static func isExcluded(_ url: URL) -> Bool {
        isExcluded(url, excludedPaths: excludedPaths)
    }

    static func isExcluded(_ url: URL, excludedPaths: [String]) -> Bool {
        let path = url.standardizedFileURL.path
        return isBuiltInExcluded(url) || Set(normalizedExclusionPaths(excludedPaths)).contains(path)
    }

    static func isBuiltInExcluded(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        return builtInExcludedPaths.contains(path)
            || builtInExcludedPathPrefixes.contains { prefix in
                path == prefix || path.hasPrefix(prefix + "/")
            }
    }

    static func include(_ path: String) {
        remove(path)
    }

    @discardableResult
    static func exclude(_ url: URL) -> Bool {
        add([url])
    }

    static var mountedVolumeOptions: [EjectableVolumeOption] {
        let keys: Set<URLResourceKey> = [
            .volumeIsEjectableKey,
            .volumeIsRemovableKey,
            .volumeLocalizedNameKey
        ]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: Array(keys), options: []) ?? []
        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
            let ejectable = values.volumeIsEjectable == true || values.volumeIsRemovable == true
            guard ejectable else { return nil }
            let standardized = url.standardizedFileURL
            let path = standardized.path
            let name = values.volumeLocalizedName ?? standardized.lastPathComponent
            return EjectableVolumeOption(
                url: standardized,
                path: path,
                name: name.isEmpty ? path : name,
                isExcluded: isExcluded(standardized),
                isBuiltInExcluded: isBuiltInExcluded(standardized)
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static var ejectableVolumes: [URL] {
        mountedVolumeOptions
            .filter { !$0.isExcluded }
            .map(\.url)
    }

    private static func exclusionPath(for url: URL) -> String? {
        let selectedPath = url.standardizedFileURL.path
        return mountedVolumeOptions
            .map(\.url)
            .filter { volume in
                let path = volume.path
                return selectedPath == path || selectedPath.hasPrefix(path + "/")
            }
            .max { $0.path.count < $1.path.count }?
            .path
    }

    private static func normalizedExclusionPaths(_ paths: [String]) -> [String] {
        var seen: Set<String> = []
        return paths
            .compactMap(normalizedExclusionPath)
            .filter { seen.insert($0).inserted }
            .sorted()
    }

    private static func normalizedExclusionPath(_ path: String) -> String? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = URL(fileURLWithPath: trimmed).standardizedFileURL.path
        guard !isBuiltInExcluded(URL(fileURLWithPath: normalized)) else { return nil }
        return normalized
    }
}

enum PlayMusicPlayerSelection: String, CaseIterable, Identifiable {
    case automatic
    case music
    case iTunes
    case spotify

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: return "Automatic"
        case .music: return "Music"
        case .iTunes: return "iTunes"
        case .spotify: return "Spotify"
        }
    }
}

struct PlayMusicPlayerInfo: Identifiable, Equatable {
    var id: String { selection.rawValue }
    let selection: PlayMusicPlayerSelection
    let bundleIdentifier: String
    let scriptName: String
    let displayName: String
    let isInstalled: Bool
    let isRunning: Bool
}

enum PlayMusicPreferences {
    private static let selectedPlayerKey = "switch.playMusic.selectedPlayer"
    private static let players: [(selection: PlayMusicPlayerSelection, bundleIdentifier: String, scriptName: String, displayName: String)] = [
        (.spotify, "com.spotify.client", "Spotify", "Spotify"),
        (.music, "com.apple.Music", "Music", "Music"),
        (.iTunes, "com.apple.iTunes", "iTunes", "iTunes")
    ]

    static var selectedPlayer: PlayMusicPlayerSelection {
        get {
            let rawValue = UserDefaults.standard.string(forKey: selectedPlayerKey)
            return rawValue.flatMap(PlayMusicPlayerSelection.init(rawValue:)) ?? .automatic
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: selectedPlayerKey) }
    }

    static var playerInfos: [PlayMusicPlayerInfo] {
        players.map { player in
            PlayMusicPlayerInfo(
                selection: player.selection,
                bundleIdentifier: player.bundleIdentifier,
                scriptName: player.scriptName,
                displayName: player.displayName,
                isInstalled: NSWorkspace.shared.urlForApplication(withBundleIdentifier: player.bundleIdentifier) != nil,
                isRunning: !NSRunningApplication.runningApplications(withBundleIdentifier: player.bundleIdentifier).isEmpty
            )
        }
    }

    static var launchTarget: PlayMusicPlayerInfo? {
        let selected = selectedPlayer
        if selected != .automatic {
            return playerInfos.first { $0.selection == selected && $0.isInstalled }
        }
        if let music = playerInfos.first(where: { $0.selection == .music && $0.isInstalled }) {
            return music
        }
        return playerInfos.first { $0.isInstalled }
    }

    @discardableResult
    static func open(_ info: PlayMusicPlayerInfo) -> Bool {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: info.bundleIdentifier) else {
            return false
        }
        guard openWorkspaceURL(url) else { return false }
        return waitForAppToRun(bundleIdentifier: info.bundleIdentifier)
    }

    private static func waitForAppToRun(bundleIdentifier: String, timeout: TimeInterval = 3) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty {
                return true
            }
            _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
        } while Date() < deadline
        return !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }
}

struct HideWidgetsSwitch {
    func snapshot() -> SwitchSnapshot {
        if #unavailable(macOS 14) {
            return switchSnapshot(isAvailable: false, warning: unsupportedSystemMessage)
        }
        let standardHidden = DefaultsBoolSwitch.read(domain: "com.apple.WindowManager", key: "StandardHideWidgets", default: false)
        let stageManagerHidden = DefaultsBoolSwitch.read(domain: "com.apple.WindowManager", key: "StageManagerHideWidgets", default: false)
        return switchSnapshot(
            isOn: standardHidden && stageManagerHidden,
            subtitle: standardHidden == stageManagerHidden ? nil : "Partially hidden"
        )
    }

    func setEnabled(_ enabled: Bool) -> String? {
        if #unavailable(macOS 14) {
            return unsupportedSystemMessage
        }
        let errors = [
            DefaultsBoolSwitch.write(enabled, domain: "com.apple.WindowManager", key: "StandardHideWidgets", restart: nil),
            DefaultsBoolSwitch.write(enabled, domain: "com.apple.WindowManager", key: "StageManagerHideWidgets", restart: nil)
        ].compactMap { $0 }
        guard errors.isEmpty else {
            return errors.joined(separator: "\n")
        }
        if let restartError = restartProcessOrReport(
            "Dock",
            failureMessage: "Hide Widgets changed, but Dock could not restart to apply it."
        ) {
            return restartError
        }
        return nil
    }
}

struct HideDesktopIconsSwitch {
    func snapshot() -> SwitchSnapshot {
        let createDesktop = DefaultsBoolSwitch.read(domain: "com.apple.finder", key: "CreateDesktop", default: true)
        return switchSnapshot(isOn: !createDesktop)
    }

    func setEnabled(_ enabled: Bool) -> String? {
        DefaultsBoolSwitch.write(!enabled, domain: "com.apple.finder", key: "CreateDesktop", restart: "Finder")
    }
}

struct HideDockSwitch {
    func snapshot() -> SwitchSnapshot {
        let hidden = DefaultsBoolSwitch.read(domain: "com.apple.dock", key: "autohide", default: false)
        return switchSnapshot(isOn: hidden)
    }

    func setEnabled(_ enabled: Bool) -> String? {
        DefaultsBoolSwitch.write(enabled, domain: "com.apple.dock", key: "autohide", restart: "Dock")
    }
}

struct ShowHiddenFilesSwitch {
    func snapshot() -> SwitchSnapshot {
        let enabled = DefaultsBoolSwitch.read(domain: "com.apple.finder", key: "AppleShowAllFiles", default: false)
        return switchSnapshot(isOn: enabled)
    }

    func setEnabled(_ enabled: Bool) -> String? {
        DefaultsBoolSwitch.write(enabled, domain: "com.apple.finder", key: "AppleShowAllFiles", restart: "Finder")
    }
}

struct MuteMicrophoneSwitch {
    private let previousVolumeKey = "switch.muteMicrophone.previousVolume"

    func snapshot() -> SwitchSnapshot {
        guard let device = defaultInputDevice else {
            return switchSnapshot(isAvailable: false, warning: "No input device")
        }
        let canSetMute = canSetInputProperty(kAudioDevicePropertyMute, device: device)
        let canSetVolume = canSetInputProperty(kAudioDevicePropertyVolumeScalar, device: device)

        if let muted = readMute(device: device), canSetMute {
            return switchSnapshot(isOn: muted, subtitle: muted ? "The microphone has been muted" : nil)
        }
        if let volume = readVolume(device: device) {
            let muted = volume <= 0.001
            if canSetVolume {
                return switchSnapshot(isOn: muted, subtitle: muted ? "The microphone has been muted" : "Volume fallback")
            }
            return switchSnapshot(
                isAvailable: false,
                warning: "The default input device reports volume but does not allow Mac Switch to change it."
            )
        }
        return switchSnapshot(
            isAvailable: false,
            warning: "The default input device does not expose macOS mute or input volume control."
        )
    }

    func setEnabled(_ enabled: Bool) -> String? {
        guard let device = defaultInputDevice else { return "No default input device." }
        if setMute(enabled, device: device) {
            guard waitForMute(device: device, equals: enabled) else {
                return "macOS accepted the microphone mute request, but input mute did not change."
            }
            if !enabled {
                UserDefaults.standard.removeObject(forKey: previousVolumeKey)
            }
            return nil
        }

        guard let currentVolume = readVolume(device: device) else {
            return "The current microphone does not expose mute or input volume control."
        }
        if enabled {
            UserDefaults.standard.set(Double(currentVolume), forKey: previousVolumeKey)
            guard setVolume(0, device: device) else {
                return "Could not mute microphone input volume."
            }
            return waitForVolume(device: device) { $0 <= 0.001 }
                ? nil
                : "macOS accepted the request, but microphone input volume did not mute."
        }

        let previous = UserDefaults.standard.object(forKey: previousVolumeKey) as? Double
        let restored = Float32(previous ?? 0.65)
        let target = max(restored, 0.25)
        if setVolume(target, device: device),
           waitForVolume(device: device, matches: target) {
            UserDefaults.standard.removeObject(forKey: previousVolumeKey)
            return nil
        }
        return "Could not restore microphone input volume."
    }

    private var defaultInputDevice: AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return status == noErr && device != 0 ? device : nil
    }

    private func readMute(device: AudioDeviceID) -> Bool? {
        var values: [Bool] = []
        for var address in preferredReadableInputAddresses(kAudioDevicePropertyMute, device: device) {
            var value = UInt32(0)
            var size = UInt32(MemoryLayout<UInt32>.size)
            let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
            if status == noErr {
                values.append(value != 0)
            }
        }
        guard !values.isEmpty else { return nil }
        if values.allSatisfy({ $0 }) { return true }
        if values.allSatisfy({ !$0 }) { return false }
        return nil
    }

    private func setMute(_ enabled: Bool, device: AudioDeviceID) -> Bool {
        var didSet = false
        for var address in settableInputAddresses(kAudioDevicePropertyMute, device: device) {
            var value = UInt32(enabled ? 1 : 0)
            let size = UInt32(MemoryLayout<UInt32>.size)
            didSet = AudioObjectSetPropertyData(device, &address, 0, nil, size, &value) == noErr || didSet
        }
        return didSet
    }

    private func waitForMute(device: AudioDeviceID, equals enabled: Bool) -> Bool {
        waitForCondition {
            readMute(device: device) == enabled
        }
    }

    private func readVolume(device: AudioDeviceID) -> Float32? {
        var values: [Float32] = []
        for var address in preferredReadableInputAddresses(kAudioDevicePropertyVolumeScalar, device: device) {
            var value = Float32(0)
            var size = UInt32(MemoryLayout<Float32>.size)
            let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
            if status == noErr {
                values.append(value)
            }
        }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Float32(values.count)
    }

    private func setVolume(_ volume: Float32, device: AudioDeviceID) -> Bool {
        var didSet = false
        for var address in settableInputAddresses(kAudioDevicePropertyVolumeScalar, device: device) {
            var value = min(max(volume, 0), 1)
            let size = UInt32(MemoryLayout<Float32>.size)
            didSet = AudioObjectSetPropertyData(device, &address, 0, nil, size, &value) == noErr || didSet
        }
        return didSet
    }

    private func waitForVolume(device: AudioDeviceID, matches target: Float32) -> Bool {
        waitForVolume(device: device) { abs($0 - target) <= 0.03 }
    }

    private func waitForVolume(device: AudioDeviceID, predicate: @escaping (Float32) -> Bool) -> Bool {
        waitForCondition {
            guard let volume = readVolume(device: device) else { return false }
            return predicate(volume)
        }
    }

    private func canSetInputProperty(_ selector: AudioObjectPropertySelector, device: AudioDeviceID) -> Bool {
        !settableInputAddresses(selector, device: device).isEmpty
    }

    private func isSettable(device: AudioDeviceID, address: inout AudioObjectPropertyAddress) -> Bool {
        var settable = DarwinBoolean(false)
        return AudioObjectIsPropertySettable(device, &address, &settable) == noErr && settable.boolValue
    }

    private func preferredReadableInputAddresses(
        _ selector: AudioObjectPropertySelector,
        device: AudioDeviceID
    ) -> [AudioObjectPropertyAddress] {
        let readable = readableInputAddresses(selector, device: device)
        let settable = settableInputAddresses(selector, device: device, readable: readable)
        return settable.isEmpty ? readable : settable
    }

    private func readableInputAddresses(
        _ selector: AudioObjectPropertySelector,
        device: AudioDeviceID
    ) -> [AudioObjectPropertyAddress] {
        inputAddresses(selector).filter { candidate in
            var address = candidate
            return AudioObjectHasProperty(device, &address)
        }
    }

    private func settableInputAddresses(
        _ selector: AudioObjectPropertySelector,
        device: AudioDeviceID,
        readable: [AudioObjectPropertyAddress]? = nil
    ) -> [AudioObjectPropertyAddress] {
        (readable ?? readableInputAddresses(selector, device: device)).filter { candidate in
            var address = candidate
            return isSettable(device: device, address: &address)
        }
    }

    private func inputAddresses(_ selector: AudioObjectPropertySelector) -> [AudioObjectPropertyAddress] {
        [kAudioObjectPropertyElementMain, 1, 2].map {
            AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: $0
            )
        }
    }
}

struct ScreenSaverSwitch {
    func snapshot() -> SwitchSnapshot {
        switchSnapshot(isOn: ProcessRunner.run("/usr/bin/pgrep", ["-x", "ScreenSaverEngine"], timeout: 1).status == 0)
    }

    func perform() -> SwitchOperationResult {
        let url = URL(fileURLWithPath: "/System/Library/CoreServices/ScreenSaverEngine.app")
        let opened = openWorkspaceURL(url)
        guard opened else {
            return actionResult("Could not start screen saver", error: "Could not start screen saver.")
        }
        return waitForCondition(timeout: 1.5, { ProcessRunner.run("/usr/bin/pgrep", ["-x", "ScreenSaverEngine"], timeout: 1).status == 0 })
            ? actionResult("Started screen saver")
            : actionResult("Could not start screen saver", error: "macOS accepted the request, but the screen saver did not start.")
    }
}

struct BluetoothAudioSwitch {
    func snapshot() -> SwitchSnapshot {
        guard BluetoothAudioPreferences.bluetoothPoweredOn else {
            return switchSnapshot(isAvailable: false, warning: "Please turn on Bluetooth")
        }
        let devices = BluetoothAudioPreferences.audioDevices
        guard !devices.isEmpty else {
            return switchSnapshot(isAvailable: false, warning: "Device not found.")
        }
        if !BluetoothAudioPreferences.selectedAddress.isEmpty,
           BluetoothAudioPreferences.selectedDevice == nil {
            return switchSnapshot(isOn: false, isAvailable: false, subtitle: "Choose another device", warning: "Selected device not found.")
        }
        let selected = BluetoothAudioPreferences.selectedDevice
        let connected = selected.map { $0.isConnected() ? $0 : nil }
            ?? devices.first(where: { $0.isConnected() })
        let target = selected ?? connected ?? devices.first
        let subtitle = target.map {
            BluetoothAudioPreferences.statusSubtitle(for: $0, connected: $0.isConnected())
        }
        return switchSnapshot(
            isOn: connected != nil,
            subtitle: subtitle,
            warning: nil
        )
    }

    func setEnabled(_ enabled: Bool) -> String? {
        guard BluetoothAudioPreferences.bluetoothPoweredOn else {
            return "Please turn on Bluetooth"
        }
        let devices = BluetoothAudioPreferences.audioDevices
        guard !devices.isEmpty else { return "Device not found." }
        if BluetoothAudioPreferences.selectedDeviceMissing {
            return "Selected device not found. Choose another device in Customize > Bluetooth Audio."
        }

        if enabled {
            guard let target = BluetoothAudioPreferences.targetDeviceForConnect() else {
                return "Device not found."
            }
            let targetName = displayName(for: target)
            let result = target.openConnection()
            guard result == kIOReturnSuccess || waitForDevice(target, connected: true, timeout: 1.5) else {
                return "\(targetName) is not responding."
            }
            return waitForDevice(target, connected: true) ? nil : "\(targetName) did not connect."
        }

        var failed: [String] = []
        let targets = BluetoothAudioPreferences.selectedDevice.map { [$0] } ?? devices
        for device in targets where device.isConnected() {
            let result = device.closeConnection()
            if result != kIOReturnSuccess || !waitForDevice(device, connected: false) {
                failed.append(displayName(for: device))
            }
        }
        return failed.isEmpty ? nil : "Could not disconnect \(joinedDeviceNames(failed))."
    }

    private func waitForDevice(_ device: IOBluetoothDevice, connected: Bool, timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if device.isConnected() == connected {
                return true
            }
            _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.15))
        } while Date() < deadline
        return device.isConnected() == connected
    }

    private func joinedDeviceNames(_ names: [String], limit: Int = 2) -> String {
        let visible = names.prefix(limit).joined(separator: ", ")
        let remaining = names.count - min(names.count, limit)
        return remaining > 0 ? "\(visible), and \(remaining) more" : visible
    }

    private func displayName(for device: IOBluetoothDevice) -> String {
        device.nameOrAddress ?? device.addressString ?? "Bluetooth Device"
    }
}

struct DoNotDisturbSwitch {
    func snapshot() -> SwitchSnapshot {
        if let configurationError = DoNotDisturbPreferences.shortcutConfigurationError {
            UserDefaults.standard.removeObject(forKey: DoNotDisturbPreferences.stateKey)
            return switchSnapshot(
                isAvailable: false,
                subtitle: "Check shortcut names",
                warning: configurationError
            )
        }
        let installed = DoNotDisturbPreferences.allShortcutsInstalled
        let shortcutError = DoNotDisturbPreferences.installedShortcutsError
        if !installed {
            UserDefaults.standard.removeObject(forKey: DoNotDisturbPreferences.stateKey)
        }
        return switchSnapshot(
            isOn: installed && UserDefaults.standard.bool(forKey: DoNotDisturbPreferences.stateKey),
            isAvailable: installed,
            subtitle: installed ? nil : (shortcutError == nil ? "Install shortcuts" : "Shortcuts unavailable"),
            warning: installed ? nil : (shortcutError ?? "Install shortcuts first")
        )
    }

    func setEnabled(_ enabled: Bool) -> String? {
        if let configurationError = DoNotDisturbPreferences.shortcutConfigurationError {
            return configurationError
        }
        guard DoNotDisturbPreferences.allShortcutsInstalled(forceRefresh: true) else {
            if let error = DoNotDisturbPreferences.installedShortcutsError {
                return "Could not read Shortcuts: \(error)"
            }
            return "Install or choose Focus shortcuts in Customize > Do Not Disturb, then try again."
        }
        let shortcut = enabled ? DoNotDisturbPreferences.installedOnShortcutName : DoNotDisturbPreferences.installedOffShortcutName
        let result = ProcessRunner.run("/usr/bin/shortcuts", ["run", shortcut], timeout: 12)
        if result.status == 0 {
            DoNotDisturbPreferences.invalidateInstalledShortcutsCache()
            UserDefaults.standard.set(enabled, forKey: DoNotDisturbPreferences.stateKey)
            return nil
        }
        return ProcessRunner.failureMessage(for: result, fallback: "Could not run \(shortcut).")
    }
}

struct PlayMusicSwitch {
    func snapshot() -> SwitchSnapshot {
        guard let app = activeApp else {
            if launchTarget != nil {
                return switchSnapshot(subtitle: unavailableMessage)
            }
            return switchSnapshot(isAvailable: false, warning: unavailableMessage)
        }

        let stateResult = playerStateResult(for: app)
        if AutomationPermission.isDenied(stateResult) {
            return switchSnapshot(
                isAvailable: false,
                subtitle: "Review Automation",
                warning: AutomationPermission.permissionMessage(for: app.scriptName)
            )
        }
        guard stateResult.status == 0 else {
            let detail = conciseOneLineFailure(
                ProcessRunner.failureMessage(for: stateResult, fallback: "Could not read \(app.displayName) playback state.")
            )
            return switchSnapshot(
                isAvailable: false,
                subtitle: "Open \(app.displayName)",
                warning: "Could not read \(app.displayName) playback state: \(detail)"
            )
        }

        let state = normalizedPlayerState(from: stateResult)
        let subtitle = state == "playing" ? (currentTrack(for: app) ?? app.displayName) : app.displayName
        return switchSnapshot(
            isOn: state == "playing",
            subtitle: subtitle
        )
    }

    func setEnabled(_ enabled: Bool) -> String? {
        let app: PlayMusicPlayerInfo
        if let active = activeApp {
            app = active
        } else if enabled, let target = launchTarget {
            app = target
            if let error = launch(app) {
                return error
            }
        } else {
            return enabled ? "\(unavailableMessage)." : nil
        }

        let command = enabled ? "play" : "pause"
        let result = ProcessRunner.run("/usr/bin/osascript", [
            "-e", "tell application \"\(app.scriptName)\" to \(command)"
        ], timeout: 8)
        if let automationError = AutomationPermission.deniedMessage(for: result, target: app.scriptName) {
            return automationError
        }
        guard result.status == 0 else {
            return ProcessRunner.failureMessage(for: result, fallback: "Could not control \(app.displayName).")
        }
        let expectedState = enabled ? "playing" : "paused"
        return waitForPlayerState(app, expectedState: expectedState)
            ? nil
            : "macOS accepted the request, but \(app.displayName) did not \(enabled ? "start playing" : "pause")."
    }

    private var activeApp: PlayMusicPlayerInfo? {
        let running = PlayMusicPreferences.playerInfos.filter(\.isRunning)
        let selected = PlayMusicPreferences.selectedPlayer
        if selected != .automatic {
            return running.first { $0.selection == selected }
        }
        return running.first(where: { normalizedPlayerState(from: playerStateResult(for: $0)) == "playing" }) ?? running.first
    }

    private var launchTarget: PlayMusicPlayerInfo? {
        PlayMusicPreferences.launchTarget
    }

    private var unavailableMessage: String {
        let selected = PlayMusicPreferences.selectedPlayer
        if selected == .automatic {
            return "Open Music or Spotify"
        }
        return launchTarget == nil ? "\(selected.title) is not installed" : "Open \(selected.title)"
    }

    private func launch(_ app: PlayMusicPlayerInfo) -> String? {
        guard app.isInstalled else {
            return "\(app.displayName) is not installed."
        }
        let result = ProcessRunner.run("/usr/bin/open", ["-b", app.bundleIdentifier], timeout: 4)
        if result.status != 0 {
            return ProcessRunner.failureMessage(for: result, fallback: "Could not open \(app.displayName).")
        }

        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if Self.isRunning(app), playerControlsReady(for: app) {
                return nil
            }
            _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.15))
        }
        return Self.isRunning(app)
            ? "\(app.displayName) opened, but playback controls are not ready."
            : "\(app.displayName) did not finish opening."
    }

    private static func isRunning(_ app: PlayMusicPlayerInfo) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleIdentifier).isEmpty
    }

    private func playerStateResult(for app: PlayMusicPlayerInfo) -> (status: Int32, output: String, error: String) {
        ProcessRunner.run("/usr/bin/osascript", [
            "-e", "tell application \"\(app.scriptName)\" to player state as string"
        ], timeout: 2)
    }

    private func normalizedPlayerState(from result: (status: Int32, output: String, error: String)) -> String? {
        guard result.status == 0 else { return nil }
        return result.output.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func waitForPlayerState(_ app: PlayMusicPlayerInfo, expectedState: String) -> Bool {
        waitForCondition(timeout: 2) {
            normalizedPlayerState(from: playerStateResult(for: app)) == expectedState
        }
    }

    private func playerControlsReady(for app: PlayMusicPlayerInfo) -> Bool {
        let result = playerStateResult(for: app)
        return result.status == 0 || AutomationPermission.isDenied(result)
    }

    private func currentTrack(for app: PlayMusicPlayerInfo) -> String? {
        let script = """
        tell application "\(app.scriptName)"
            if player state is stopped then return ""
            try
                set trackArtist to artist of current track
            on error
                set trackArtist to ""
            end try
            try
                set trackName to name of current track
            on error
                set trackName to ""
            end try
            if trackArtist is "" and trackName is "" then return ""
            if trackArtist is "" then return trackName
            if trackName is "" then return trackArtist
            return trackArtist & " - " & trackName
        end tell
        """
        let result = ProcessRunner.run("/usr/bin/osascript", ["-e", script], timeout: 2)
        guard result.status == 0 else { return nil }
        let text = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}

struct DisplaySleepSwitch {
    func snapshot() -> SwitchSnapshot {
        Self.hasOnlineDisplay
            ? switchSnapshot()
            : switchSnapshot(isAvailable: false, warning: "No active display found.")
    }

    func perform() -> SwitchOperationResult {
        guard Self.hasOnlineDisplay else {
            return actionResult("No active display", error: "No active display found.")
        }
        let result = ProcessRunner.run("/usr/bin/pmset", ["displaysleepnow"], timeout: 5)
        return actionResult("Display sleeping", error: result.status == 0 ? nil : ProcessRunner.failureMessage(for: result, fallback: "Could not sleep the display."))
    }

    private static var hasOnlineDisplay: Bool {
        var count: UInt32 = 0
        return CGGetOnlineDisplayList(0, nil, &count) == .success && count > 0
    }
}

struct ScreenResolutionSwitch {
    func snapshot() -> SwitchSnapshot {
        guard let displayID = ScreenResolutionPreferences.selectedDisplayID else {
            return switchSnapshot(isAvailable: false, warning: "No active display")
        }
        guard let current = CGDisplayCopyDisplayMode(displayID) else {
            return switchSnapshot(isAvailable: false, warning: "No active display")
        }
        let previous = ScreenResolutionPreferences.previousMode(for: displayID)
        let size = ScreenResolutionPreferences.option(current).title
        let subtitle = ScreenResolutionPreferences.displayOptions.count > 1
            ? "\(ScreenResolutionPreferences.displayTitle(for: displayID)): \(size)"
            : size
        return switchSnapshot(isOn: previous != nil && previous != modeID(current), subtitle: subtitle)
    }

    func setEnabled(_ enabled: Bool) -> String? {
        guard let display = ScreenResolutionPreferences.selectedDisplayID else {
            return "No active display found."
        }
        guard let current = CGDisplayCopyDisplayMode(display) else {
            return "No active display found."
        }
        let modes = ScreenResolutionPreferences.displayModes(for: display)
        guard !modes.isEmpty else {
            return "No display modes are available."
        }

        if enabled {
            guard let target = ScreenResolutionPreferences.selectedMode(for: display)
                    ?? lowerResolutionMode(from: current, modes: modes) else {
                ScreenResolutionPreferences.clearPreviousMode(for: display)
                return "No lower resolution mode is available."
            }
            guard modeID(target) != modeID(current) else {
                ScreenResolutionPreferences.clearPreviousMode(for: display)
                return nil
            }

            if ScreenResolutionPreferences.previousMode(for: display) == nil {
                ScreenResolutionPreferences.setPreviousMode(modeID(current), for: display)
            }

            let result = CGDisplaySetDisplayMode(display, target, nil)
            if result == .success, verifyCurrentMode(display, matches: target) {
                return nil
            }
            ScreenResolutionPreferences.clearPreviousMode(for: display)
            if result == .success {
                return "macOS accepted the request, but the display did not switch to the selected resolution."
            }
            return "Could not switch display resolution."
        }

        guard let previous = ScreenResolutionPreferences.previousMode(for: display) else {
            return nil
        }
        guard let mode = modes.first(where: { modeID($0) == previous }) else {
            ScreenResolutionPreferences.clearPreviousMode(for: display)
            return "Original display mode is no longer available."
        }
        let result = CGDisplaySetDisplayMode(display, mode, nil)
        if result == .success, verifyCurrentMode(display, matches: mode) {
            ScreenResolutionPreferences.clearPreviousMode(for: display)
            return nil
        }
        return result == .success
            ? "macOS accepted the request, but the display did not restore its original resolution."
            : "Could not restore display resolution."
    }

    private func lowerResolutionMode(from current: CGDisplayMode, modes: [CGDisplayMode]) -> CGDisplayMode? {
        let currentArea = current.width * current.height
        return modes
            .filter { modeID($0) != modeID(current) && ($0.width * $0.height) < currentArea }
            .sorted {
                if $0.width == $1.width { return $0.height > $1.height }
                return $0.width > $1.width
            }
            .first
    }

    private func modeID(_ mode: CGDisplayMode) -> Int {
        ScreenResolutionPreferences.modeID(mode)
    }

    private func verifyCurrentMode(_ display: CGDirectDisplayID, matches expected: CGDisplayMode, timeout: TimeInterval = 0.45) -> Bool {
        let expectedID = modeID(expected)
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let current = CGDisplayCopyDisplayMode(display), modeID(current) == expectedID {
                return true
            }
            _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        } while Date() < deadline
        return CGDisplayCopyDisplayMode(display).map { modeID($0) == expectedID } ?? false
    }
}

struct LockScreenSwitch {
    func snapshot() -> SwitchSnapshot {
        let locked = Self.isScreenLocked
        return switchSnapshot(isOn: locked, subtitle: locked ? "Screen locked" : nil)
    }

    func perform() -> SwitchOperationResult {
        if Self.lockWithLoginFramework() {
            return Self.waitForScreenLock()
                ? actionResult("Locked screen")
                : Self.unconfirmedLockResult()
        }

        let script = """
        tell application "System Events" to keystroke "q" using {control down, command down}
        """
        let result = ProcessRunner.run("/usr/bin/osascript", ["-e", script], timeout: 5)
        let error = AutomationPermission.deniedMessage(for: result, target: "System Events")
            ?? (result.status == 0 ? nil : ProcessRunner.failureMessage(for: result, fallback: "Could not lock screen."))
        if error == nil, !Self.waitForScreenLock() {
            return Self.unconfirmedLockResult()
        }
        return actionResult("Locked screen", error: error)
    }

    private static var isScreenLocked: Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return session["CGSSessionScreenIsLocked"] as? Bool == true
    }

    private static func waitForScreenLock(timeout: TimeInterval = 2.0) -> Bool {
        waitForCondition(timeout: timeout) {
            isScreenLocked
        }
    }

    private static func unconfirmedLockResult() -> SwitchOperationResult {
        actionResult(
            "Lock screen not confirmed",
            error: "macOS accepted the lock request, but the screen did not report locked."
        )
    }

    private static func lockWithLoginFramework() -> Bool {
        let path = "/System/Library/PrivateFrameworks/login.framework/login"
        guard let handle = dlopen(path, RTLD_LAZY),
              let symbol = dlsym(handle, "SACLockScreenImmediate")
        else { return false }
        typealias Function = @convention(c) () -> Void
        let function = unsafeBitCast(symbol, to: Function.self)
        function()
        return true
    }
}

struct XcodeCleanSwitch {
    private static var cachedSize: (date: Date, bytes: UInt64)?
    private static var isCalculating = false
    private static let cacheTTL: TimeInterval = 120
    private static let emptyCacheTTL: TimeInterval = 6
    private static let cacheQueue = DispatchQueue(label: "com.maxyu.macswitch.xcode-clean-size-cache")

    func snapshot() -> SwitchSnapshot {
        if let bytes = Self.cachedDerivedDataSize() {
            let size = bytes == 0 ? "Zero" : Self.byteFormatter.string(fromByteCount: Int64(bytes))
            return switchSnapshot(isAvailable: bytes > 0, subtitle: "DerivedData: \(size)")
        }
        return switchSnapshot(subtitle: "DerivedData: Calculating...")
    }

    func perform(progress: ((Double) -> Void)? = nil) -> SwitchOperationResult {
        let directory = XcodeCleanPreferences.derivedDataURL
        guard FileManager.default.fileExists(atPath: directory.path) else {
            Self.setCachedSize(0)
            progress?(100)
            return unavailableActionResult("DerivedData: Zero")
        }
        do {
            let items = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            guard !items.isEmpty else {
                Self.setCachedSize(0)
                progress?(100)
                return unavailableActionResult("DerivedData: Zero")
            }

            progress?(0)
            var removedCount = 0
            var failures: [String] = []
            for (index, item) in items.enumerated() {
                do {
                    try FileManager.default.removeItem(at: item)
                    removedCount += 1
                } catch {
                    failures.append("\(item.lastPathComponent): \(error.localizedDescription)")
                }
                let percent = (Double(index + 1) / Double(items.count)) * 100
                progress?(percent)
            }
            if failures.isEmpty {
                Self.setCachedSize(0)
                playActionSound()
                return actionResult("Cleaned Successfully!")
            }

            Self.invalidateCachedSize()
            let visibleFailures = failures.prefix(3).joined(separator: "\n")
            let omitted = failures.count > 3 ? "\n...and \(failures.count - 3) more." : ""
            let error = "Removed \(removedCount) of \(items.count) items. Could not remove \(failures.count):\n\(visibleFailures)\(omitted)"
            return actionResult("Partially cleaned DerivedData", error: error)
        } catch {
            Self.invalidateCachedSize()
            return actionResult("Could not clean DerivedData", error: error.localizedDescription)
        }
    }

    private static var byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter
    }()

    private static func cachedDerivedDataSize() -> UInt64? {
        let cached = cacheQueue.sync { cachedSize }
        if let cached,
           Date().timeIntervalSince(cached.date) < (cached.bytes == 0 ? emptyCacheTTL : cacheTTL) {
            return cached.bytes
        }
        startSizeCalculationIfNeeded()
        return cached?.bytes
    }

    private static func setCachedSize(_ bytes: UInt64) {
        cacheQueue.sync {
            cachedSize = (Date(), bytes)
            isCalculating = false
        }
    }

    static func invalidateCachedSize() {
        cacheQueue.sync {
            cachedSize = nil
            isCalculating = false
        }
    }

    private static func startSizeCalculationIfNeeded() {
        let shouldStart = cacheQueue.sync { () -> Bool in
            guard !isCalculating else { return false }
            isCalculating = true
            return true
        }
        guard shouldStart else { return }

        DispatchQueue.global(qos: .utility).async {
            let bytes = directorySize(at: XcodeCleanPreferences.derivedDataURL)
            setCachedSize(bytes)
        }
    }

    private static func directorySize(at url: URL) -> UInt64 {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: []
        ) else { return 0 }

        var total: UInt64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: keys),
                  values.isRegularFile == true
            else { continue }
            total += UInt64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        return total
    }
}

enum XcodeCleanPreferences {
    static var derivedDataURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Developer/Xcode/DerivedData")
    }

    @discardableResult
    static func revealDerivedData() -> Bool {
        let url = derivedDataURL
        if FileManager.default.fileExists(atPath: url.path) {
            return revealInFinder(url)
        } else {
            return openWorkspaceURL(url.deletingLastPathComponent())
        }
    }

    static func refreshSizeEstimate() {
        XcodeCleanSwitch.invalidateCachedSize()
    }
}

enum TrashPreferences {
    private static let ignoredMetadataNames: Set<String> = [".DS_Store", ".localized", "Icon\r"]

    static var itemCount: Int {
        trashDirectories.reduce(0) { total, url in
            total + countedItems(in: url)
        }
    }

    @discardableResult
    static func openTrash() -> Bool {
        let userTrash = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash", isDirectory: true)
        return openWorkspaceURL(userTrash)
    }

    private static var trashDirectories: [URL] {
        let fileManager = FileManager.default
        let userTrash = fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".Trash", isDirectory: true)
        let uid = getuid()
        let volumeTrashes = (fileManager.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: []) ?? [])
            .map { $0.appendingPathComponent(".Trashes/\(uid)", isDirectory: true) }
        return ([userTrash] + volumeTrashes).filter { fileManager.fileExists(atPath: $0.path) }
    }

    private static func countedItems(in directory: URL) -> Int {
        let items = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        )) ?? []
        return items.filter { !ignoredMetadataNames.contains($0.lastPathComponent) }.count
    }
}

struct EmptyTrashSwitch {
    func snapshot() -> SwitchSnapshot {
        let count = TrashPreferences.itemCount
        return switchSnapshot(
            isAvailable: count > 0,
            subtitle: count == 0 ? "Trash empty" : "\(count) item\(count == 1 ? "" : "s")"
        )
    }

    func perform() -> SwitchOperationResult {
        guard TrashPreferences.itemCount > 0 else {
            return unavailableActionResult("Trash empty")
        }
        let script = "tell application \"Finder\" to empty trash"
        let result = ProcessRunner.run("/usr/bin/osascript", ["-e", script], timeout: 60)
        let error = AutomationPermission.deniedMessage(for: result, target: "Finder")
            ?? (result.status == 0 ? nil : ProcessRunner.failureMessage(for: result, fallback: "Could not empty the Trash."))
        if error == nil {
            let remaining = TrashPreferences.itemCount
            if remaining > 0 {
                return actionResult(
                    "Trash still has \(remaining) item\(remaining == 1 ? "" : "s")",
                    error: "Finder finished, but \(remaining) item\(remaining == 1 ? "" : "s") remain in Trash."
                )
            }
            playActionSound(named: "Pop")
        }
        return actionResult("Trash emptied", error: error)
    }
}

struct EjectDiskSwitch {
    func snapshot() -> SwitchSnapshot {
        let count = EjectDiskPreferences.ejectableVolumes.count
        return switchSnapshot(
            isAvailable: count > 0,
            subtitle: count == 0 ? "No ejectable disks" : "\(count) disk\(count == 1 ? "" : "s")"
        )
    }

    func perform() -> SwitchOperationResult {
        let volumes = EjectDiskPreferences.ejectableVolumes
        guard !volumes.isEmpty else {
            return unavailableActionResult("No ejectable disks")
        }

        var failed: [String] = []
        for volume in volumes {
            if !NSWorkspace.shared.unmountAndEjectDevice(atPath: volume.path) || !waitForVolumeToUnmount(volume) {
                failed.append(volume.lastPathComponent)
            }
        }
        if failed.isEmpty {
            playActionSound(named: "Pop")
        }
        return failed.isEmpty
            ? actionResult("Ejected \(volumes.count) disk\(volumes.count == 1 ? "" : "s")")
            : actionResult(
                "Could not eject \(joinedVolumeNames(failed))",
                error: "Could not eject \(joinedVolumeNames(failed))."
            )
    }

    private func waitForVolumeToUnmount(_ volume: URL, timeout: TimeInterval = 3) -> Bool {
        let path = volume.path
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if !FileManager.default.fileExists(atPath: path) {
                return true
            }
            _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
        } while Date() < deadline
        return !FileManager.default.fileExists(atPath: path)
    }

    private func joinedVolumeNames(_ names: [String], limit: Int = 3) -> String {
        let visible = names.prefix(limit).joined(separator: ", ")
        let remaining = names.count - min(names.count, limit)
        return remaining > 0 ? "\(visible), and \(remaining) more" : visible
    }
}

struct EmptyPasteboardSwitch {
    func snapshot() -> SwitchSnapshot {
        let count = PasteboardPreferences.itemCount
        return switchSnapshot(
            isAvailable: count > 0,
            subtitle: count == 0 ? "Pasteboard empty" : "\(count) item\(count == 1 ? "" : "s")"
        )
    }

    func perform() -> SwitchOperationResult {
        guard PasteboardPreferences.itemCount > 0 else {
            return unavailableActionResult("Pasteboard empty")
        }
        PasteboardPreferences.clear()
        let remaining = PasteboardPreferences.itemCount
        guard remaining == 0 else {
            return actionResult(
                "Pasteboard still has \(remaining) item\(remaining == 1 ? "" : "s")",
                error: "macOS reported \(remaining) pasteboard item\(remaining == 1 ? "" : "s") after clearing."
            )
        }
        return actionResult("Pasteboard emptied")
    }
}

enum PasteboardPreferences {
    static var itemCount: Int {
        NSPasteboard.general.pasteboardItems?.count ?? 0
    }

    static func clear() {
        NSPasteboard.general.clearContents()
    }
}

struct HideWindowsSwitch {
    func snapshot() -> SwitchSnapshot {
        let count = HideWindowsPreferences.hidableApps.count
        return switchSnapshot(
            isAvailable: count > 0,
            subtitle: count == 0 ? "No apps to hide" : "\(count) app\(count == 1 ? "" : "s")"
        )
    }

    func perform() -> SwitchOperationResult {
        let apps = HideWindowsPreferences.hidableApps
        guard !apps.isEmpty else {
            return unavailableActionResult("No apps to hide")
        }
        var hiddenApps: [NSRunningApplication] = []
        var hiddenNames: [String] = []
        var failedNames: [String] = []

        for app in apps {
            if app.hide(), waitForAppToHide(app) {
                hiddenApps.append(app)
                hiddenNames.append(HideWindowsPreferences.displayName(for: app))
            } else {
                failedNames.append(HideWindowsPreferences.displayName(for: app))
            }
        }

        guard !hiddenNames.isEmpty else {
            return actionResult("Could not hide windows", error: "No running app accepted the hide request.")
        }
        HideWindowsPreferences.recordHidden(hiddenApps)
        if !failedNames.isEmpty {
            return actionResult(
                "Hidden \(hiddenNames.count) of \(apps.count) apps",
                error: "Could not hide \(HideWindowsPreferences.joinedAppNames(failedNames))."
            )
        }
        return actionResult("Hidden \(hiddenNames.count) apps")
    }

    private func waitForAppToHide(_ app: NSRunningApplication, timeout: TimeInterval = 0.6) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if app.isHidden {
                return true
            }
            _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        } while Date() < deadline
        return app.isHidden
    }
}

struct HideWindowsRestoreResult {
    let restored: Int
    let failed: [String]
}

enum HideWindowsPreferences {
    private static let hiddenAppTokensKey = "switch.hideWindows.hiddenAppTokens"

    static var hidableApps: [NSRunningApplication] {
        let bundleID = Bundle.main.bundleIdentifier
        return NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular &&
            $0.bundleIdentifier != bundleID &&
            !$0.isHidden
        }
    }

    static var hiddenApps: [NSRunningApplication] {
        pruneTrackedHiddenApps()
        let tokens = hiddenAppTokens
        let bundleID = Bundle.main.bundleIdentifier
        return NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular &&
            $0.bundleIdentifier != bundleID &&
            $0.isHidden &&
            tokens.contains(token(for: $0))
        }
    }

    static func recordHidden(_ apps: [NSRunningApplication]) {
        guard !apps.isEmpty else { return }
        hiddenAppTokens.formUnion(apps.map(token(for:)))
    }

    @discardableResult
    static func unhideAll() -> HideWindowsRestoreResult {
        var restored = 0
        var failed: [String] = []
        for app in hiddenApps {
            if app.unhide(), waitForApp(app, hidden: false) {
                restored += 1
                forgetHidden(app)
            } else {
                failed.append(displayName(for: app))
            }
        }
        pruneTrackedHiddenApps()
        return HideWindowsRestoreResult(restored: restored, failed: failed)
    }

    static func displayName(for app: NSRunningApplication) -> String {
        app.localizedName ?? app.bundleIdentifier ?? "an app"
    }

    static func joinedAppNames(_ names: [String], limit: Int = 3) -> String {
        let visible = names.prefix(limit).joined(separator: ", ")
        let remaining = names.count - min(names.count, limit)
        return remaining > 0 ? "\(visible), and \(remaining) more" : visible
    }

    private static var hiddenAppTokens: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: hiddenAppTokensKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue).sorted(), forKey: hiddenAppTokensKey) }
    }

    private static func token(for app: NSRunningApplication) -> String {
        if let bundleIdentifier = app.bundleIdentifier, !bundleIdentifier.isEmpty {
            return "bundle:\(bundleIdentifier)"
        }
        return "pid:\(app.processIdentifier)"
    }

    private static func forgetHidden(_ app: NSRunningApplication) {
        hiddenAppTokens.remove(token(for: app))
    }

    private static func pruneTrackedHiddenApps() {
        let bundleID = Bundle.main.bundleIdentifier
        let liveHiddenTokens = Set(NSWorkspace.shared.runningApplications.compactMap { app -> String? in
            guard app.activationPolicy == .regular,
                  app.bundleIdentifier != bundleID,
                  app.isHidden
            else { return nil }
            return token(for: app)
        })
        let pruned = hiddenAppTokens.intersection(liveHiddenTokens)
        if pruned != hiddenAppTokens {
            hiddenAppTokens = pruned
        }
    }

    private static func waitForApp(_ app: NSRunningApplication, hidden: Bool, timeout: TimeInterval = 0.6) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if app.isHidden == hidden {
                return true
            }
            _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        } while Date() < deadline
        return app.isHidden == hidden
    }
}

struct LowPowerModeSwitch {
    func snapshot() -> SwitchSnapshot {
        guard let mode = PowerMode.current else {
            return switchSnapshot(
                isAvailable: false,
                warning: "Could not read the current power mode."
            )
        }
        let canUseLowPower = PowerMode.availableModes(current: mode).contains(1)
        return switchSnapshot(
            isOn: mode == 1,
            isAvailable: canUseLowPower,
            warning: canUseLowPower ? nil : unsupportedSystemMessage
        )
    }

    func setEnabled(_ enabled: Bool) -> String? {
        guard enabled else {
            return PowerMode.set(0)
        }
        guard PowerMode.availableModes.contains(1) else {
            return unsupportedSystemMessage
        }
        return PowerMode.set(1)
    }
}

enum EnergyModeSelection: Int, CaseIterable, Identifiable {
    case lowPower = 1
    case highPower = 2

    var id: Int { rawValue }

    static var supportedCases: [EnergyModeSelection] {
        let supportedRawValues = PowerMode.availableModes
        return allCases.filter { supportedRawValues.contains($0.rawValue) }
    }

    var title: String {
        switch self {
        case .lowPower: return "Low Power"
        case .highPower: return "High Power"
        }
    }
}

enum EnergyModePreferences {
    private static let selectedModeKey = "switch.energyMode.selectedMode"

    static var storedSelection: EnergyModeSelection {
        get {
            let rawValue = UserDefaults.standard.integer(forKey: selectedModeKey)
            return EnergyModeSelection(rawValue: rawValue) ?? .highPower
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: selectedModeKey) }
    }

    static var selectedMode: EnergyModeSelection {
        get { selectedMode(among: EnergyModeSelection.supportedCases) }
        set { storedSelection = newValue }
    }

    static func selectedMode(among supported: [EnergyModeSelection]) -> EnergyModeSelection {
        let stored = storedSelection
        if supported.isEmpty || supported.contains(stored) {
            return stored
        }
        return supported.first ?? stored
    }
}

struct EnergyModeSwitch {
    func snapshot() -> SwitchSnapshot {
        guard let mode = PowerMode.current else {
            return switchSnapshot(
                isAvailable: false,
                warning: "Could not read the current power mode."
            )
        }
        let supportedRawValues = PowerMode.availableModes(current: mode)
        let supportedSelections = EnergyModeSelection.allCases.filter { supportedRawValues.contains($0.rawValue) }
        let selected = EnergyModePreferences.selectedMode(among: supportedSelections)
        let isSupported = supportedSelections.contains(selected)
        return switchSnapshot(
            isOn: isSupported && mode == selected.rawValue,
            isAvailable: isSupported,
            subtitle: isSupported ? (mode == selected.rawValue ? selected.title : "Automatic") : nil,
            warning: isSupported ? nil : unsupportedSystemMessage
        )
    }

    func setEnabled(_ enabled: Bool) -> String? {
        guard enabled else {
            return PowerMode.set(0)
        }
        let supportedSelections = EnergyModeSelection.supportedCases
        let selected = EnergyModePreferences.selectedMode(among: supportedSelections)
        guard supportedSelections.contains(selected) else {
            return unsupportedSystemMessage
        }
        return PowerMode.set(selected.rawValue)
    }
}

private enum PowerMode {
    static var availableModes: Set<Int> {
        availableModes(current: current)
    }

    static func availableModes(current: Int?) -> Set<Int> {
        var modes: Set<Int> = [0]
        let result = ProcessRunner.run("/usr/bin/pmset", ["-g", "cap"], timeout: 2)
        if result.status == 0 {
            let output = result.output.lowercased()
            if output.contains("lowpowermode") {
                modes.insert(1)
            }
            if output.contains("highpowermode") {
                modes.insert(2)
            }
        }
        if let current {
            modes.insert(current)
        }
        return modes
    }

    static var current: Int? {
        let result = ProcessRunner.run("/usr/bin/pmset", ["-g", "live"], timeout: 2)
        guard result.status == 0 else { return nil }
        for line in result.output.split(separator: "\n") {
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            if parts.first == "powermode", let value = parts.dropFirst().first, let mode = Int(value) {
                return mode
            }
        }
        return nil
    }

    static func set(_ mode: Int) -> String? {
        let currentMode = current
        if currentMode == mode {
            return nil
        }
        guard mode == 0 || availableModes(current: currentMode).contains(mode) else {
            return unsupportedSystemMessage
        }
        let script = """
        do shell script "/usr/bin/pmset -a powermode \(mode)" with administrator privileges
        """
        let result = ProcessRunner.run("/usr/bin/osascript", ["-e", script], timeout: 120)
        if result.status == 0 {
            return waitForCondition(timeout: 1.5, { current == mode })
                ? nil
                : "macOS accepted the request, but power mode did not change."
        }
        if let automationError = AutomationPermission.deniedMessage(for: result, target: "System Events") {
            return automationError
        }
        return ProcessRunner.failureMessage(for: result, fallback: "Could not update power mode.")
    }
}
