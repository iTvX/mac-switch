import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let resources = root.appendingPathComponent("Resources", isDirectory: true)
let iconset = resources.appendingPathComponent("MacSwitchIcon.iconset", isDirectory: true)
let icns = resources.appendingPathComponent("MacSwitchIcon.icns")

try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let outputs: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for output in outputs {
    let image = makeIcon(size: output.pixels)
    try writePNG(image, to: iconset.appendingPathComponent(output.name))
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else {
    throw NSError(domain: "MacSwitchIcon", code: Int(process.terminationStatus), userInfo: [
        NSLocalizedDescriptionKey: "iconutil failed with status \(process.terminationStatus)"
    ])
}

try? FileManager.default.removeItem(at: iconset)
print("Generated \(icns.path)")

private func makeIcon(size pixels: Int) -> NSImage {
    let size = NSSize(width: pixels, height: pixels)
    let image = NSImage(size: size)
    image.lockFocus()

    let rect = NSRect(origin: .zero, size: size)
    let corner = CGFloat(pixels) * 0.215
    let body = NSBezierPath(roundedRect: rect.insetBy(dx: CGFloat(pixels) * 0.045, dy: CGFloat(pixels) * 0.045), xRadius: corner, yRadius: corner)
    NSGradient(colors: [
        NSColor(calibratedRed: 0.08, green: 0.56, blue: 0.92, alpha: 1),
        NSColor(calibratedRed: 0.12, green: 0.82, blue: 0.72, alpha: 1)
    ])?.draw(in: body, angle: -35)

    NSColor.white.withAlphaComponent(0.16).setStroke()
    body.lineWidth = max(1, CGFloat(pixels) * 0.018)
    body.stroke()

    let scale = CGFloat(pixels) / 1024
    drawSlider(y: 678 * scale, knobX: 660 * scale, in: rect, scale: scale)
    drawSlider(y: 512 * scale, knobX: 404 * scale, in: rect, scale: scale)
    drawSlider(y: 346 * scale, knobX: 606 * scale, in: rect, scale: scale)

    image.unlockFocus()
    return image
}

private func drawSlider(y: CGFloat, knobX: CGFloat, in rect: NSRect, scale: CGFloat) {
    let trackHeight = max(3, 52 * scale)
    let track = NSRect(
        x: 230 * scale,
        y: y - trackHeight / 2,
        width: rect.width - 460 * scale,
        height: trackHeight
    )
    let trackPath = NSBezierPath(roundedRect: track, xRadius: trackHeight / 2, yRadius: trackHeight / 2)
    NSColor.white.withAlphaComponent(0.92).setFill()
    trackPath.fill()

    let knobDiameter = max(8, 118 * scale)
    let knobRect = NSRect(
        x: knobX - knobDiameter / 2,
        y: y - knobDiameter / 2,
        width: knobDiameter,
        height: knobDiameter
    )
    let knob = NSBezierPath(ovalIn: knobRect)
    NSColor(calibratedRed: 0.04, green: 0.18, blue: 0.30, alpha: 1).setFill()
    knob.fill()
    NSColor.white.withAlphaComponent(0.92).setStroke()
    knob.lineWidth = max(1, 16 * scale)
    knob.stroke()
}

private func writePNG(_ image: NSImage, to url: URL) throws {
    guard let data = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: data),
          let png = bitmap.representation(using: .png, properties: [:])
    else {
        throw NSError(domain: "MacSwitchIcon", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Could not render PNG for \(url.lastPathComponent)"
        ])
    }
    try png.write(to: url, options: .atomic)
}
