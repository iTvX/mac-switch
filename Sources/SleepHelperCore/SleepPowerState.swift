import Foundation

public enum SleepPowerState {
    /// pmset prints this optional key in its system-wide section. An unset key is the default off state.
    /// The later live-settings section can contain process names and must not be parsed as system policy.
    public static func parse(_ output: String) -> Bool? {
        var inSystemSettings = false
        for line in output.split(separator: "\n") {
            let text = line.trimmingCharacters(in: .whitespaces)
            if text == "System-wide power settings:" { inSystemSettings = true; continue }
            if text == "Currently in use:" { return false }
            guard inSystemSettings else { continue }
            let fields = text.split(whereSeparator: \.isWhitespace)
            if fields.first == "SleepDisabled" {
                guard fields.count == 2 else { return nil }
                switch fields[1] {
                case "0": return false
                case "1": return true
                default: return nil
                }
            }
        }
        return nil
    }
}
