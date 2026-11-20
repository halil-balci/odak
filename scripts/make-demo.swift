// Renders docs/demo.gif (the reader in the Charcoal theme) and docs/social-preview.png.
// Run from the repo root: swift scripts/make-demo.swift  (needs ffmpeg for the GIF)
import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let tmp = ProcessInfo.processInfo.environment["TMPDIR"].map { URL(fileURLWithPath: $0) } ?? FileManager.default.temporaryDirectory
let frames = tmp.appendingPathComponent("odak-demo")
try? FileManager.default.removeItem(at: frames)
try FileManager.default.createDirectory(at: frames, withIntermediateDirectories: true)

func color(_ hex: UInt32) -> NSColor {
    NSColor(red: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}
// Charcoal theme, same values as Theme in SettingsView.swift.
let background = color(0x2B2B2D), text = color(0xECE7DF), dim = color(0x8E8B86), faint = color(0x4A4947), accent = color(0xE8873A)

func serif(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    return base.fontDescriptor.withDesign(.serif).flatMap { NSFont(descriptor: $0, size: size) } ?? base
}

// Same rule as ORP.index(for:) in OdakCore.
func orpIndex(_ word: String) -> Int {
    let chars = Array(word)
    let letters = chars.indices.filter { chars[$0].isLetter || chars[$0].isNumber }
    guard !letters.isEmpty else { return 0 }
    let offset: Int
    switch letters.count {
    case ...1: offset = 0
    case 2...5: offset = 1
    case 6...9: offset = 2
    case 10...13: offset = 3
    default: offset = 4
    }
    return letters[min(offset, letters.count - 1)]
}

func png(_ w: Int, _ h: Int, to url: URL, draw: (CGFloat, CGFloat) -> Void) throws {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw(CGFloat(w), CGFloat(h))
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}

/// Draws a word with its ORP letter centered on x, like the reader does.
func drawWord(_ word: String, centerX: CGFloat, baselineY: CGFloat, font: NSFont) {
    let chars = Array(word), i = orpIndex(word)
    let left = String(chars[..<i]), orp = String(chars[i]), right = String(chars[(i + 1)...])
    let attrs: (NSColor) -> [NSAttributedString.Key: Any] = { [.font: font, .foregroundColor: $0] }
    let orpWidth = (orp as NSString).size(withAttributes: attrs(accent)).width
    let leftWidth = (left as NSString).size(withAttributes: attrs(text)).width
    let x = centerX - orpWidth / 2
    let y = baselineY + font.descender  // draw(at:) takes the bottom of the line box
    (left as NSString).draw(at: NSPoint(x: x - leftWidth, y: y), withAttributes: attrs(text))
    (orp as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: attrs(accent))
    (right as NSString).draw(at: NSPoint(x: x + orpWidth, y: y), withAttributes: attrs(text))
}

func drawWindow(_ w: CGFloat, _ h: CGFloat) {
    NSColor(white: 0.12, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: w, height: h).fill()
    background.setFill()
    NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: w, height: h), xRadius: 18, yRadius: 18).fill()
    for (i, c) in [0xEE6A5F, 0xF5BF4F, 0x61C554].enumerated() {
        color(UInt32(c)).setFill()
        NSBezierPath(ovalIn: NSRect(x: 18 + CGFloat(i) * 26, y: h - 34, width: 16, height: 16)).fill()
    }
}

// Demo GIF: 300 WPM with the app's longer pauses after commas and sentences.
let sample = "Odak shows one word at a time. Your eyes stay still, and the words come to you. Read faster, with less effort."
let wordFont = serif(64)
var list = ""
for (n, word) in sample.split(separator: " ").map(String.init).enumerated() {
    let url = frames.appendingPathComponent(String(format: "%03d.png", n))
    try png(1000, 500, to: url) { w, h in
        drawWindow(w, h)
        faint.setFill()
        NSRect(x: w / 2 - 1, y: h / 2 + 52, width: 2, height: 14).fill()
        NSRect(x: w / 2 - 1, y: h / 2 - 66, width: 2, height: 14).fill()
        drawWord(word, centerX: w / 2, baselineY: h / 2 - 18, font: wordFont)
    }
    let delay = word.hasSuffix(".") ? 0.6 : word.hasSuffix(",") ? 0.4 : word.count > 7 ? 0.28 : 0.2
    list += "file '\(url.path)'\nduration \(delay)\n"
}
list += "file '\(frames.appendingPathComponent(String(format: "%03d.png", sample.split(separator: " ").count - 1)).path)'\n"
let listURL = frames.appendingPathComponent("list.txt")
try list.write(to: listURL, atomically: false, encoding: .utf8)

let ffmpeg = Process()
ffmpeg.executableURL = URL(fileURLWithPath: "/usr/bin/env")
ffmpeg.arguments = ["ffmpeg", "-y", "-loglevel", "error", "-f", "concat", "-safe", "0", "-i", listURL.path,
                    "-vf", "scale=700:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=64[p];[b][p]paletteuse",
                    "-loop", "0", root.appendingPathComponent("docs/demo.gif").path]
try ffmpeg.run()
ffmpeg.waitUntilExit()
guard ffmpeg.terminationStatus == 0 else { fatalError("ffmpeg failed") }

// Social preview for GitHub (Settings › Social preview), 1280×640.
try png(1280, 640, to: root.appendingPathComponent("docs/social-preview.png")) { w, h in
    background.setFill()
    NSRect(x: 0, y: 0, width: w, height: h).fill()
    faint.setFill()
    NSRect(x: w / 2 - 1.5, y: h / 2 + 128, width: 3, height: 22).fill()
    NSRect(x: w / 2 - 1.5, y: h / 2 - 32, width: 3, height: 22).fill()
    drawWord("odak", centerX: w / 2, baselineY: h / 2 + 22, font: serif(120))
    let center = NSMutableParagraphStyle()
    center.alignment = .center
    ("Read one word at a time. Your eyes stay still." as NSString).draw(
        in: NSRect(x: 0, y: h / 2 - 130, width: w, height: 50),
        withAttributes: [.font: serif(38), .foregroundColor: text, .paragraphStyle: center])
    ("Free, open-source speed reader for macOS and every browser" as NSString).draw(
        in: NSRect(x: 0, y: h / 2 - 190, width: w, height: 40),
        withAttributes: [.font: NSFont.systemFont(ofSize: 26), .foregroundColor: dim, .paragraphStyle: center])
}
print("Wrote docs/demo.gif and docs/social-preview.png")
