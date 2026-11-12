import OdakCore
import SwiftUI

enum SettingsKey {
    static let defaultWPM = "defaultWPM"
    static let fontSize = "fontSize"
    static let fontDesign = "fontDesign"
    static let redHighlight = "redHighlight"
    static let theme = "theme"
    static let slowStart = "slowStart"
    static let readingStats = "readingStats"
}

enum Theme: String, CaseIterable, Identifiable {
    case charcoal, midnight, sepia, paper
    var id: Self { self }
    var name: LocalizedStringKey { LocalizedStringKey(rawValue.capitalized) }
    private var hex: (background: UInt32, text: UInt32, dim: UInt32, faint: UInt32, accent: UInt32) {
        switch self {
        case .charcoal: (0x2B2B2D, 0xECE7DF, 0x8E8B86, 0x4A4947, 0xE8873A)
        case .midnight: (0x1F2430, 0xD8DEE9, 0x7D8799, 0x3B4252, 0xE5A55D)
        case .sepia: (0xF3EAD7, 0x4A3B2C, 0x9C8B74, 0xDDD0B6, 0xC8642B)
        case .paper: (0xFAF8F3, 0x2F2E2B, 0x9A968E, 0xE4E0D7, 0xD9692E)
        }
    }
    var background: Color { Color(hex: hex.background) }
    var text: Color { Color(hex: hex.text) }
    var dim: Color { Color(hex: hex.dim) }
    var faint: Color { Color(hex: hex.faint) }
    var accent: Color { Color(hex: hex.accent) }
    var scheme: ColorScheme { self == .charcoal || self == .midnight ? .dark : .light }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

enum WordFontDesign: String, CaseIterable, Identifiable {
    case `default`, serif, rounded, monospaced
    var id: Self { self }
    var design: Font.Design {
        switch self {
        case .default: .default
        case .serif: .serif
        case .rounded: .rounded
        case .monospaced: .monospaced
        }
    }
    var nsDesign: NSFontDescriptor.SystemDesign {
        switch self {
        case .default: .default
        case .serif: .serif
        case .rounded: .rounded
        case .monospaced: .monospaced
        }
    }
}

struct SettingsView: View {
    @AppStorage(SettingsKey.defaultWPM) private var defaultWPM = 300
    @AppStorage(SettingsKey.fontSize) private var fontSize = 64.0
    @AppStorage(SettingsKey.fontDesign) private var fontDesign = WordFontDesign.serif
    @AppStorage(SettingsKey.redHighlight) private var redHighlight = true
    @AppStorage(SettingsKey.theme) private var theme = Theme.charcoal
    @AppStorage(SettingsKey.slowStart) private var slowStart = true

    var body: some View {
        Form {
            Stepper("Default speed: \(defaultWPM) WPM", value: $defaultWPM, in: Timing.wpmRange, step: 25)
            Slider(value: $fontSize, in: 24...140) { Text("Font size: \(Int(fontSize)) pt") }
            Picker("Theme", selection: $theme) {
                ForEach(Theme.allCases) { Text($0.name).tag($0) }
            }
            Picker("Font", selection: $fontDesign) {
                ForEach(WordFontDesign.allCases) { Text(LocalizedStringKey($0.rawValue.capitalized)).tag($0) }
            }
            Toggle("Highlight focus letter", isOn: $redHighlight)
            Toggle("Slow start", isOn: $slowStart)
                .help("Show the first few words more slowly after pressing play")
        }
        // One speed setting: changing it here also changes the live reader (the reader saves its changes back).
        .onChange(of: defaultWPM) { AppModel.shared.engine.wpm = $1 }
        .onChange(of: slowStart) { AppModel.shared.engine.slowStart = $1 }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize()
    }
}
