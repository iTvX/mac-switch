import Foundation

enum DiagnosticExport {
    static func switchLine(_ kind: SwitchKind, snapshot: SwitchSnapshot) -> String {
        let status = snapshot.isAvailable ? (snapshot.isOn ? "on" : "off") : "unavailable"
        // These values can contain device names, media metadata, volume names,
        // or arbitrary subprocess output. Path redaction cannot anonymize them.
        let subtitle = snapshot.subtitle?.isEmpty == false ? "present" : "none"
        let warning = snapshot.warning?.isEmpty == false ? "present" : "none"
        return "- \(kind.title): \(status) (subtitle=\(subtitle), warning=\(warning))"
    }

    static func errorSummary(_ error: String?) -> String {
        error == nil ? "none" : "present (details omitted for privacy)"
    }
}
