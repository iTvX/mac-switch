import Foundation
import Security

@objc public protocol SleepHelperProtocol {
    func setLidSleepDisabled(_ disabled: Bool, until deadline: Date?, reply: @escaping (String?) -> Void)
    func restoreLegacySleepSetting(reply: @escaping (String?) -> Void)
}

public enum SleepHelperIdentity {
    public static let appIdentifier = "com.maxyu.macswitch"
    public static let serviceIdentifier = "com.maxyu.macswitch.sleep-helper"
    public static let plistName = serviceIdentifier + ".plist"

    public static func requirement(identifier: String, team: String) -> String? {
        guard [appIdentifier, serviceIdentifier].contains(identifier),
              team.count == 10, team.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) }) else { return nil }
        return "anchor apple generic and identifier \"\(identifier)\" and certificate leaf[subject.OU] = \"\(team)\" and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and ! entitlement[\"com.apple.security.get-task-allow\"] exists"
    }

    public static func ownTeam() -> String? {
        var code: SecCode?
        var info: CFDictionary?
        var staticCode: SecStaticCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dictionary = info as? [String: Any] else { return nil }
        return dictionary[kSecCodeInfoTeamIdentifier as String] as? String
    }
}
