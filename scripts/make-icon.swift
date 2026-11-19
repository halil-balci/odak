// Generates Resources/AppIcon.icns and the browser extension icons. Run: swift scripts/make-icon.swift
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
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = s * 0.025
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.012)
    shadow.set()
    NSColor.black.setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: NSColor(red: 0.08, green: 0.09, blue: 0.15, alpha: 1),
               ending: NSColor(red: 0.22, green: 0.25, blue: 0.40, alpha: 1))!.draw(in: shape, angle: 90)
    NSGraphicsContext.saveGraphicsState()
    shape.addClip()  // soft light at the top
    NSGradient(starting: NSColor.white.withAlphaComponent(0.10), ending: NSColor.white.withAlphaComponent(0))!
        .draw(in: NSRect(x: 0, y: s * 0.5, width: s, height: s * 0.4), angle: 270)
    NSGraphicsContext.restoreGraphicsState()

    // Word mark "odak" with the ORP letter in the reader's accent orange (Charcoal theme), plus focus guides.
    let accent = NSColor(red: 0xE8 / 255.0, green: 0x87 / 255.0, blue: 0x3A / 255.0, alpha: 1)
    var font = NSFont.systemFont(ofSize: s * 0.25, weight: .heavy)
    if let d = font.fontDescriptor.withDesign(.rounded), let f = NSFont(descriptor: d, size: s * 0.25) { font = f }
    let kern = -s * 0.005
    let word = NSMutableAttributedString(string: "odak", attributes: [.font: font, .foregroundColor: NSColor.white, .kern: kern])
    word.addAttribute(.foregroundColor, value: accent, range: NSRange(location: 1, length: 1))
    let size = word.size()
    let x0 = (s - size.width) / 2
    word.draw(at: NSPoint(x: x0, y: (s - size.height) / 2))
    let guideX = x0 + NSAttributedString(string: "o", attributes: [.font: font, .kern: kern]).size().width
        + NSAttributedString(string: "d", attributes: [.font: font]).size().width / 2
    let w = s * 0.03, l = s * 0.07
    NSColor.white.withAlphaComponent(0.85).setFill()
    for y in [s * 0.66, s * 0.34 - l] {
        NSBezierPath(roundedRect: NSRect(x: guideX - w / 2, y: y, width: w, height: l), xRadius: w / 2, yRadius: w / 2).fill()
    }
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
for px in [16, 48, 128] {
    try render(px).write(to: root.appendingPathComponent("chrome-extension/icons/icon\(px).png"))
}
print("Wrote chrome-extension/icons")
