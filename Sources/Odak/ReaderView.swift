import OdakCore
import SwiftUI

struct ReaderView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(SettingsKey.fontSize) private var fontSize = 64.0
    @AppStorage(SettingsKey.fontDesign) private var fontDesign = WordFontDesign.serif
    @AppStorage(SettingsKey.redHighlight) private var redHighlight = true
    @AppStorage(SettingsKey.theme) private var theme = Theme.charcoal
    @State private var keyMonitor: Any?
    @State private var scrollRemainder: CGFloat = 0
    @State private var pointerMoves = 0
    @State private var overToolbar = false
    @State private var toolbarsVisible = true

    private var engine: ReaderEngine { model.engine }
    private var showContext: Bool { !engine.isPlaying }
    private var weight: Font.Weight { fontDesign == .serif ? .regular : .medium }
    private var bodySize: CGFloat { min(max(fontSize * 0.3, 15), 26) }
    private static let neighbours = 3, contextTokens = 150

    var body: some View {
        VStack(spacing: 0) {
            toolbar(topBar)
            VStack(spacing: 0) {
                contextText(range: max(0, engine.currentIndex - Self.neighbours - Self.contextTokens)..<max(0, engine.currentIndex - Self.neighbours),
                            alignment: .bottom)
                wordLine
                VStack(spacing: 12) {
                    // Always laid out (opacity only) so the word line doesn't jump when the hint goes away.
                    let showHint = !model.hasStarted && engine.currentIndex == model.startIndex && !engine.isPlaying
                    Text(model.startIndex > 0 ? "Click or press Space to continue" : "Click or press Space to start")
                        .font(.callout).foregroundStyle(theme.dim)
                        .opacity(showHint ? 1 : 0)
                        .accessibilityHidden(!showHint)
                    let start = min(engine.currentIndex + 1 + Self.neighbours, engine.tokens.count)
                    contextText(range: start..<min(start + Self.contextTokens, engine.tokens.count), alignment: .top)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { engine.toggle() }
            toolbar(bottomBar)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
        // A window-level key monitor instead of .focusable/.onKeyPress: SwiftUI focus never reliably landed on
        // this view (e.g. when opened from Services/Finder), which left Space, arrows and Esc dead.
        .onAppear {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .scrollWheel]) { event in
                // Only the reader window (title "Odak", not Settings) and not while a sheet such as statistics is open.
                guard let window = event.window, window.title == "Odak", window.attachedSheet == nil,
                      !(window.firstResponder is NSText) else { return event }
                if event.type == .scrollWheel { return handleScroll(event) ? nil : event }
                return handleKey(event) ? nil : event
            }
        }
        .onDisappear { keyMonitor.map(NSEvent.removeMonitor); keyMonitor = nil }
        .onChange(of: engine.wpm) { UserDefaults.standard.set($1, forKey: SettingsKey.defaultWPM) }
        .onChange(of: engine.isPlaying) { model.playStateChanged(playing: $1) }
        .onChange(of: engine.currentIndex) { model.indexChanged() }
        .onContinuousHover { if case .active = $0 { pointerMoves += 1 } }
        // Restarts on every pointer move or play/pause; hides the toolbars after 1.5 s of stillness while playing.
        .task(id: [pointerMoves, engine.isPlaying ? 1 : 0, overToolbar ? 1 : 0]) {
            toolbarsVisible = true
            guard engine.isPlaying, !overToolbar else { return }
            try? await Task.sleep(for: .seconds(1.5))
            if !Task.isCancelled { toolbarsVisible = false }
        }
    }

    // MARK: Word line

    private var wordLine: some View {
        let parts = engine.currentToken?.parts ?? (left: "", orp: "", right: "")
        let i = engine.currentIndex, tokens = engine.tokens
        let before = tokens.isEmpty ? "" : tokens[max(0, i - Self.neighbours)..<i].map(\.text).joined(separator: " ")
        let after = tokens.isEmpty ? "" : tokens[min(i + 1, tokens.count)..<min(i + 1 + Self.neighbours, tokens.count)].map(\.text).joined(separator: " ")
        return GeometryReader { geo in
            let size = fittedSize(parts, width: geo.size.width)
            let font = Font.system(size: size, weight: weight, design: fontDesign.design)
            // Two flexible halves of equal width keep the ORP letter centered at a fixed x.
            // Neighbours truncate at the outer edges; the current word is fixed-size and never cut.
            HStack(spacing: 0) {
                HStack(spacing: size * 0.3) {
                    Text(before).foregroundStyle(theme.dim).truncationMode(.head).opacity(showContext ? 1 : 0)
                    Text(parts.left).fixedSize()
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                Text(parts.orp).foregroundStyle(redHighlight ? theme.accent : theme.text).fixedSize()
                HStack(spacing: size * 0.3) {
                    Text(parts.right).fixedSize()
                    Text(after).foregroundStyle(theme.dim).truncationMode(.tail).opacity(showContext ? 1 : 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(font)
            .lineLimit(1)
            .foregroundStyle(theme.text)
            .padding(.vertical, 24)
            .overlay {
                VStack {
                    Rectangle().frame(width: 2, height: 14)
                    Spacer()
                    Rectangle().frame(width: 2, height: 14)
                }
                .foregroundStyle(theme.faint)
                .opacity(showContext ? 0 : 1)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .frame(height: fontSize * 1.4 + 48)
        .animation(contextAnimation, value: showContext)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(engine.currentToken?.text ?? "")
        .accessibilityAddTraits(.updatesFrequently)
    }

    /// Font size at which the longer half still fits its half of the width, so words are never cut off with "…".
    private func fittedSize(_ parts: (left: String, orp: String, right: String), width: CGFloat) -> CGFloat {
        let base = NSFont.systemFont(ofSize: fontSize, weight: weight == .regular ? .regular : .medium)
        let nsFont = base.fontDescriptor.withDesign(fontDesign.nsDesign).flatMap { NSFont(descriptor: $0, size: fontSize) } ?? base
        func w(_ s: String) -> CGFloat { (s as NSString).size(withAttributes: [.font: nsFont]).width }
        let needed = 2 * max(w(parts.left), w(parts.right)) + w(parts.orp)
        // Text width scales linearly with point size; 0.97 leaves room for rounding.
        return needed > width ? fontSize * width * 0.97 / needed : fontSize
    }

    // MARK: Context

    private var contextAnimation: Animation { showContext ? .easeIn(duration: 0.25) : .easeOut(duration: 0.6) }

    /// Surrounding text, shown while paused. Overflow is clipped away from the word line with a soft fade.
    private func contextText(range: Range<Int>, alignment: Alignment) -> some View {
        let text = engine.tokens[range].map { $0.endsParagraph ? $0.text + "\n\n" : $0.text + " " }.joined()
        let fade = alignment == .bottom ? [Color.clear, .black, .black] : [.black, .black, .clear]
        // The text lives in an overlay so its full height never pushes the toolbars out of the window.
        return Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: alignment) {
                Text(text.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(.system(size: bodySize, design: fontDesign.design))
                    .lineSpacing(bodySize * 0.5)
                    .foregroundStyle(theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 900, alignment: .leading)
            }
            .clipped()
            .mask(LinearGradient(colors: fade, startPoint: .top, endPoint: .bottom))
            .opacity(showContext ? 1 : 0)
            .animation(contextAnimation, value: showContext)
            .accessibilityHidden(true)
    }

    // MARK: Toolbars

    private func toolbar(_ content: some View) -> some View {
        content
            .opacity(toolbarsVisible || !engine.isPlaying ? 1 : 0)
            .animation(.easeInOut(duration: 0.3), value: toolbarsVisible || !engine.isPlaying)
            .onHover { overToolbar = $0 }
    }

    private var topBar: some View {
        HStack(spacing: 18) {
            IconButton("Back to Text", systemImage: "chevron.left", help: "Back to text (Esc)") { model.close() }
            Text(remainingLabel)
                .italic()
                .foregroundStyle(theme.dim)
                .help(String(localized: "\(Duration.seconds(engine.remainingTime).formatted(.time(pattern: .minuteSecond))) left · Word \(engine.tokens.isEmpty ? 0 : engine.currentIndex + 1) of \(engine.tokens.count)"))
            ValueStepper(label: "WPM", value: engine.wpm, help: "Words per minute (↑/↓)") { engine.wpm += 25 * $0 }
            ValueStepper(label: "Font size", value: Int(fontSize), help: "Font size") { fontSize = min(max(fontSize + 4 * Double($0), 24), 140) }
            Spacer()
            Menu {
                Picker("Theme", selection: $theme) {
                    ForEach(Theme.allCases) { Text($0.name).tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                Image(systemName: "circle.lefthalf.filled")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Theme")
            .accessibilityLabel("Theme")
            IconButton("Reading Statistics", systemImage: "chart.bar.xaxis", help: "Reading statistics (⌘Y)") {
                model.isStatsPresented = true
            }
            SettingsLink { IconLabel(systemImage: "gearshape") }
                .buttonStyle(.plain)
                .help("Settings (⌘,)")
                .accessibilityLabel("Settings")
        }
        .font(.callout)
        .padding(.vertical, 6)
    }

    private var remainingLabel: String {
        let t = engine.remainingTime
        return t < 60 ? String(localized: "< 1 min") : String(localized: "\(Int((t / 60).rounded(.up))) min")
    }

    private var bottomBar: some View {
        VStack(spacing: 8) {
            ProgressBar(engine: engine)
            HStack(spacing: 6) {
                Spacer()
                IconButton(engine.isPlaying ? "Pause" : "Play", systemImage: engine.isPlaying ? "pause.fill" : "play.fill",
                           help: "Play/Pause (Space)") { engine.toggle() }
                IconButton("Previous Sentence", systemImage: "chevron.left.2", help: "Previous sentence (⌥←)") { engine.jumpSentence(forward: false) }
                IconButton("Next Sentence", systemImage: "chevron.right.2", help: "Next sentence (⌥→)") { engine.jumpSentence(forward: true) }
                IconButton("Restart", systemImage: "arrow.counterclockwise", help: "Restart (R)") { engine.restart() }
                IconButton("Full Screen", systemImage: "arrow.up.left.and.arrow.down.right", help: "Toggle full screen (⌃⌘F)") {
                    NSApp.keyWindow?.toggleFullScreen(nil)
                }
            }
        }
        .padding(.top, 6)
    }

    /// Returns true when the key was handled (and must not reach other views).
    private func handleKey(_ event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard mods.isDisjoint(with: [.command, .control]) else { return false }
        let sentence = mods.contains(.option)
        let arrows: Set<UInt16> = [123, 124, 125, 126]
        // Only arrows auto-repeat; holding Space/Esc/R must not keep firing.
        if event.isARepeat, !arrows.contains(event.keyCode) { return true }
        switch event.keyCode {
        case 49: engine.toggle()                                   // Space
        case 123: sentence ? engine.jumpSentence(forward: false) : engine.stepWord(by: -1)
        case 124: sentence ? engine.jumpSentence(forward: true) : engine.stepWord(by: 1)
        case 126: engine.wpm += 25
        case 125: engine.wpm -= 25
        case 53: model.close()                                     // Esc
        default:
            guard event.charactersIgnoringModifiers?.lowercased() == "r" else { return false }
            engine.restart()
        }
        return true
    }

    /// Vertical scrolling scrubs through the words like a document: down (or swipe up) = forward. Pauses playback.
    private func handleScroll(_ event: NSEvent) -> Bool {
        let dy = event.scrollingDeltaY
        guard abs(dy) > abs(event.scrollingDeltaX) else { return false }
        // Trackpads send pixel deltas (many small events), mouse wheels about one line per notch.
        scrollRemainder -= event.hasPreciseScrollingDeltas ? dy / 12 : dy
        let steps = Int(scrollRemainder)
        guard steps != 0 else { return true }
        scrollRemainder -= CGFloat(steps)
        if engine.isPlaying { engine.pause() }
        engine.stepWord(by: steps)
        return true
    }
}

/// Borderless toolbar icon: dim, brightening on a subtle rounded background while hovered.
private struct IconLabel: View {
    @AppStorage(SettingsKey.theme) private var theme = Theme.charcoal
    @State private var hovering = false
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 14, weight: .medium))
            .frame(width: 30, height: 30)
            .foregroundStyle(hovering ? theme.text : theme.dim)
            .background(hovering ? theme.text.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
    }
}

private struct IconButton: View {
    let title: LocalizedStringKey, systemImage: String, help: LocalizedStringKey, action: () -> Void

    init(_ title: LocalizedStringKey, systemImage: String, help: LocalizedStringKey, action: @escaping () -> Void) {
        (self.title, self.systemImage, self.help, self.action) = (title, systemImage, help, action)
    }

    var body: some View {
        Button(action: action) { IconLabel(systemImage: systemImage) }
            .buttonStyle(.plain)
            .help(help)
            .accessibilityLabel(title)
    }
}

/// "WPM 350" with small up/down chevrons; `step` is called with +1 or -1.
private struct ValueStepper: View {
    @AppStorage(SettingsKey.theme) private var theme = Theme.charcoal
    let label: LocalizedStringKey, value: Int, help: LocalizedStringKey, step: (Int) -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(label).foregroundStyle(theme.dim)
            VStack(spacing: 0) {
                chevron("chevron.up", 1)
                Text("\(value)").monospacedDigit()
                chevron("chevron.down", -1)
            }
        }
        .help(help)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(value)")
        .accessibilityAdjustableAction { step($0 == .increment ? 1 : -1) }
    }

    private func chevron(_ name: String, _ delta: Int) -> some View {
        Button { step(delta) } label: {
            Image(systemName: name)
                .font(.system(size: 8, weight: .bold))
                .frame(width: 16, height: 11)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(theme.dim)
    }
}

private struct ProgressBar: View {
    @AppStorage(SettingsKey.theme) private var theme = Theme.charcoal
    let engine: ReaderEngine

    var body: some View {
        GeometryReader { geo in
            let x = geo.size.width * engine.progress
            ZStack(alignment: .leading) {
                Capsule().fill(theme.faint).frame(height: 3)
                Capsule().fill(theme.dim).frame(width: x, height: 3)
                Circle().fill(theme.text).frame(width: 12, height: 12).offset(x: min(max(x - 6, 0), geo.size.width - 12))
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                let fraction = min(max(value.location.x / max(geo.size.width, 1), 0), 1)
                engine.seek(to: Int(fraction * Double(engine.tokens.count)))
            })
        }
        .frame(height: 14)
        .accessibilityElement()
        .accessibilityLabel("Reading progress")
        .accessibilityValue("\(Int(engine.progress * 100)) percent")
        .accessibilityAdjustableAction { direction in
            engine.jumpSentence(forward: direction == .increment)
        }
    }
}
