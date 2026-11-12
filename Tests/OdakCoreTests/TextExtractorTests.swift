import AppKit
import Foundation
import Testing
@testable import OdakCore

@MainActor @Suite struct TextExtractorTests {
    let dir: URL = {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("OdakTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    @Test func plainTextUTF8() async throws {
        let url = dir.appendingPathComponent("a.txt")
        try "Merhaba dünya — çağ".write(to: url, atomically: true, encoding: .utf8)
        #expect(try await TextExtractor.text(from: url) == "Merhaba dünya — çağ")
    }

    @Test func plainTextLegacyEncodingFallback() async throws {
        let url = dir.appendingPathComponent("b.md")
        try #require("café".data(using: .isoLatin1)).write(to: url)
        #expect(try await TextExtractor.text(from: url).hasPrefix("caf"))
    }

    @Test func plainTextLegacyEncodings() async throws {
        let tr = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.windowsLatin5.rawValue)))
        let cases: [(String, String.Encoding)] = [
            ("Merhaba dünya, çağ ışık şimdi İstanbul öğle", tr),
            ("Hello world, this is plain text", .utf16LittleEndian),
            ("Big endian ğ", .utf16BigEndian),
            ("With BOM ş", .utf16),
        ]
        for (i, (text, enc)) in cases.enumerated() {
            let url = dir.appendingPathComponent("enc\(i).txt")
            try #require(text.data(using: enc)).write(to: url)
            #expect(try await TextExtractor.text(from: url) == text)
        }
    }

    @Test func otherPlainTextTypesAndNoExtension() async throws {
        for name in ["server.log", "data.csv", "README"] {
            let url = dir.appendingPathComponent(name)
            try "plain words".write(to: url, atomically: true, encoding: .utf8)
            #expect(try await TextExtractor.text(from: url) == "plain words")
        }
    }

    @Test func rtf() async throws {
        let url = dir.appendingPathComponent("c.rtf")
        let attr = NSAttributedString(string: "Rich text here.")
        let data = try attr.data(from: NSRange(location: 0, length: attr.length),
                                 documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        try data.write(to: url)
        #expect(try await TextExtractor.text(from: url).trimmingCharacters(in: .whitespacesAndNewlines) == "Rich text here.")
    }

    @Test func embeddedImagesAreNotWords() async throws {
        let url = dir.appendingPathComponent("img.html")
        try #"<p>Hello</p><img src="missing.png"><p>world</p>"#.write(to: url, atomically: true, encoding: .utf8)
        let text = try await TextExtractor.text(from: url)
        #expect(!text.contains("\u{FFFC}"))
        #expect(Tokenizer.tokenize(text).map(\.text) == ["Hello", "world"])
    }

    @Test func binaryWithoutExtensionIsRejected() async throws {
        let url = dir.appendingPathComponent("tool")
        try Data([0xCF, 0xFA, 0xED, 0xFE, 0x07, 0x00, 0x00, 0x01, 0x00, 0x00]).write(to: url)
        await #expect(throws: TextExtractionError.unsupportedFileType("tool")) { try await TextExtractor.text(from: url) }
    }

    @Test func unsupportedAndEmpty() async throws {
        let bad = dir.appendingPathComponent("x.xyz")
        try "hi".write(to: bad, atomically: true, encoding: .utf8)
        await #expect(throws: TextExtractionError.unsupportedFileType("xyz")) { try await TextExtractor.text(from: bad) }

        let empty = dir.appendingPathComponent("e.txt")
        try "  \n ".write(to: empty, atomically: true, encoding: .utf8)
        await #expect(throws: TextExtractionError.empty) { try await TextExtractor.text(from: empty) }

        await #expect(throws: TextExtractionError.unreadable("missing.txt")) {
            try await TextExtractor.text(from: dir.appendingPathComponent("missing.txt"))
        }
    }
}
