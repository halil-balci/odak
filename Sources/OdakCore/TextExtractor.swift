import AppKit
import PDFKit
import UniformTypeIdentifiers

public enum TextExtractionError: LocalizedError, Equatable {
    case unsupportedFileType(String)
    case unreadable(String)
    case empty

    public var errorDescription: String? {
        switch self {
        case .unsupportedFileType(let ext): String(localized: "Files of type “\(ext)” are not supported.")
        case .unreadable(let name): String(localized: "Could not read “\(name)”.")
        case .empty: String(localized: "The file contains no readable text.")
        }
    }
}

public enum TextExtractor {
    public static let supportedExtensions: Set<String> = ["txt", "text", "md", "markdown", "pdf", "rtf", "rtfd", "docx", "doc", "html", "htm", "odt"]

    private static let attributedTypes: [String: NSAttributedString.DocumentType] = [
        "rtf": .rtf, "rtfd": .rtfd, "docx": .officeOpenXML, "doc": .docFormat,
        "html": .html, "htm": .html, "odt": .openDocument,
    ]

    /// Runs off the main thread (big PDFs take a while); only the NSAttributedString import hops to the main
    /// thread, because its HTML importer requires it.
    public static func text(from url: URL) async throws -> String {
        let ext = url.pathExtension.lowercased()
        var text: String
        switch ext {
        case "txt", "text", "md", "markdown":
            text = try plainText(url)
        case "pdf":
            guard let doc = PDFDocument(url: url) else { throw TextExtractionError.unreadable(url.lastPathComponent) }
            text = doc.string ?? ""
        case "":
            // No extension: accept only real UTF-8 text, so binaries (e.g. Unix executables) aren't shown as garbage.
            guard let s = String(data: try readData(url), encoding: .utf8), !s.contains("\0") else {
                throw TextExtractionError.unsupportedFileType(url.lastPathComponent)
            }
            text = s
        default:
            if UTType(filenameExtension: ext)?.conforms(to: .plainText) == true {
                text = try plainText(url)
                break
            }
            guard let type = attributedTypes[ext] else { throw TextExtractionError.unsupportedFileType(ext) }
            text = try await MainActor.run {
                do {
                    return try NSAttributedString(url: url, options: [.documentType: type], documentAttributes: nil).string
                } catch {
                    throw TextExtractionError.unreadable(url.lastPathComponent)
                }
            }
            // Embedded images come through as U+FFFC (object replacement), which would show as an empty word.
            text = text.replacingOccurrences(of: "\u{FFFC}", with: " ")
        }
        guard !text.allSatisfy(\.isWhitespace) else { throw TextExtractionError.empty }
        return text
    }

    private static func readData(_ url: URL) throws -> Data {
        do { return try Data(contentsOf: url) } catch { throw TextExtractionError.unreadable(url.lastPathComponent) }
    }

    private static func plainText(_ url: URL) throws -> String {
        let data = try readData(url)
        // NUL bytes never appear in real text (yet UTF-8 decoding accepts them): treat as BOM-less UTF-16, endianness from where the zeros sit.
        if data.contains(0), ![[0xFF, 0xFE], [0xFE, 0xFF]].contains(Array(data.prefix(2))) {
            let oddZeros = data.indices.filter { $0 % 2 == 1 && data[$0] == 0 }.count
            let evenZeros = data.indices.filter { $0 % 2 == 0 && data[$0] == 0 }.count
            if let s = String(data: data, encoding: oddZeros >= evenZeros ? .utf16LittleEndian : .utf16BigEndian) { return s }
        }
        if let s = String(data: data, encoding: .utf8) { return s }
        var detected: String.Encoding = .utf8
        if let s = try? String(contentsOf: url, usedEncoding: &detected) { return s }
        // shortcut: Windows-1254 (Turkish) is the only 8-bit fallback and accepts any bytes; MacRoman etc. decode as Latin5.
        let turkish = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.windowsLatin5.rawValue)))
        return String(data: data, encoding: turkish) ?? String(decoding: data, as: UTF8.self)
    }
}
