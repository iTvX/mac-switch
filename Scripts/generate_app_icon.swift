import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let resources = root.appendingPathComponent("Resources", isDirectory: true)
let sourceIconset = resources.appendingPathComponent("AppIcon.appiconset", isDirectory: true)
let temporaryIconset = resources.appendingPathComponent("MacSwitchIcon.iconset", isDirectory: true)
let icns = resources.appendingPathComponent("MacSwitchIcon.icns")
let fileManager = FileManager.default

let iconFiles: [(source: String, destination: String)] = [
    ("MacSwitchIcon-16x16@1x.png", "icon_16x16.png"),
    ("MacSwitchIcon-16x16@2x.png", "icon_16x16@2x.png"),
    ("MacSwitchIcon-32x32@1x.png", "icon_32x32.png"),
    ("MacSwitchIcon-32x32@2x.png", "icon_32x32@2x.png"),
    ("MacSwitchIcon-128x128@1x.png", "icon_128x128.png"),
    ("MacSwitchIcon-128x128@2x.png", "icon_128x128@2x.png"),
    ("MacSwitchIcon-256x256@1x.png", "icon_256x256.png"),
    ("MacSwitchIcon-256x256@2x.png", "icon_256x256@2x.png"),
    ("MacSwitchIcon-512x512@1x.png", "icon_512x512.png"),
    ("MacSwitchIcon-512x512@2x.png", "icon_512x512@2x.png")
]

guard fileManager.fileExists(atPath: sourceIconset.path) else {
    throw NSError(domain: "MacSwitchIcon", code: 1, userInfo: [
        NSLocalizedDescriptionKey: "Missing \(sourceIconset.path)"
    ])
}

try? fileManager.removeItem(at: temporaryIconset)
try fileManager.createDirectory(at: temporaryIconset, withIntermediateDirectories: true)
defer { try? fileManager.removeItem(at: temporaryIconset) }

for file in iconFiles {
    let source = sourceIconset.appendingPathComponent(file.source)
    let destination = temporaryIconset.appendingPathComponent(file.destination)
    guard fileManager.fileExists(atPath: source.path) else {
        throw NSError(domain: "MacSwitchIcon", code: 2, userInfo: [
            NSLocalizedDescriptionKey: "Missing app icon source: \(source.path)"
        ])
    }
    try validatePNGHasAlpha(source)
    try fileManager.copyItem(at: source, to: destination)
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", temporaryIconset.path, "-o", icns.path]
try process.run()
process.waitUntilExit()

guard process.terminationStatus == 0 else {
    throw NSError(domain: "MacSwitchIcon", code: Int(process.terminationStatus), userInfo: [
        NSLocalizedDescriptionKey: "iconutil failed with status \(process.terminationStatus)"
    ])
}

print("Generated \(icns.path) from \(sourceIconset.path)")

private func validatePNGHasAlpha(_ url: URL) throws {
    let data = try Data(contentsOf: url)
    let pngSignature = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    guard data.count > 25, data.prefix(8) == pngSignature else {
        throw NSError(domain: "MacSwitchIcon", code: 3, userInfo: [
            NSLocalizedDescriptionKey: "\(url.lastPathComponent) is not a valid PNG file"
        ])
    }

    let colorType = data[25]
    guard colorType == 6 else {
        throw NSError(domain: "MacSwitchIcon", code: 4, userInfo: [
            NSLocalizedDescriptionKey: "\(url.lastPathComponent) must be an RGBA PNG with alpha to avoid an opaque app-icon halo"
        ])
    }
}
