import Foundation

struct DisplayModeRestorePoint: Codable, Equatable, Sendable {
    let uuid: String
    let originalModeID: Int
    let previousToggleModeID: Int?
    let selectedTargetModeID: Int?
}

enum DeviceModeRestorePoint: Codable, Equatable, Sendable {
    case microphone(MicrophoneRestorePoint)
    case display(DisplayModeRestorePoint)
}

enum ModeSessionPhase: String, Codable, Sendable { case activating, active, restoring }
