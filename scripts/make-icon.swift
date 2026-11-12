// Generates Resources/AppIcon.icns. Run: swift scripts/make-icon.swift
import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    let rect = NSRect(x: s * 0.1, y: s * 0.1, width: s * 0.8, height: s * 0.8)
    let shape = NSBezierPath(roundedRect: rect, xRadius: s * 0.18, yRadius: s * 0.18)
    NSGradient(starting: NSColor(red: 0.13, green: 0.15, blue: 0.22, alpha: 1),
               ending: NSColor(red: 0.27, green: 0.31, blue: 0.45, alpha: 1))!.draw(in: shape, angle: 90)

    // Word mark "read" with the ORP letter in red, plus focus guides.
    let font = NSFont.systemFont(ofSize: s * 0.22, weight: .bold)
    let word = NSMutableAttributedString(string: "read", attributes: [.font: font, .foregroundColor: NSColor.white])
    word.addAttribute(.foregroundColor, value: NSColor.systemRed, range: NSRange(location: 1, length: 1))
    let size = word.size()
    word.draw(at: NSPoint(x: (s - size.width) / 2, y: (s - size.height) / 2))
    NSColor.white.withAlphaComponent(0.6).setFill()
    let guideX = (s - size.width) / 2 + NSAttributedString(string: "r", attributes: [.font: font]).size().width
        + NSAttributedString(string: "e", attributes: [.font: font]).size().width / 2 - s * 0.006
    NSRect(x: guideX, y: s * 0.66, width: s * 0.012, height: s * 0.07).fill()
    NSRect(x: guideX, y: s * 0.27, width: s * 0.012, height: s * 0.07).fill()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try render(base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("Resources/AppIcon.icns").path]
try p.run()
p.waitUntilExit()
print(p.terminationStatus == 0 ? "Wrote Resources/AppIcon.icns" : "iconutil failed")
