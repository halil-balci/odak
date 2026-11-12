import OdakCore
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(SettingsKey.theme) private var theme = Theme.charcoal

    var body: some View {
        @Bindable var model = model
        Group {
            if model.isReading { ReaderView() } else { InputView() }
        }
        // The title bar is hidden, so content runs to the top edge; 28 pt keeps clear of the traffic lights.
        .padding(.top, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.background)
        .ignoresSafeArea(edges: .top)
        .foregroundStyle(theme.text)
        .tint(theme.accent)
        .preferredColorScheme(theme.scheme)
        .onDrop(of: [.fileURL, .plainText], isTargeted: nil, perform: handleDrop)
        .fileImporter(isPresented: $model.isImporterPresented,
                      allowedContentTypes: [.plainText] + TextExtractor.supportedExtensions.compactMap { UTType(filenameExtension: $0) }) { result in
            switch result {
            case .success(let url): model.open(url)
            case .failure(let error): model.errorMessage = error.localizedDescription
            }
        }
        .sheet(isPresented: $model.isStatsPresented) { StatsView() }
        .alert("Couldn’t open file", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        let model = model
        if provider.canLoadObject(ofClass: URL.self) {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in url.isFileURL ? model.open(url) : model.read(url.absoluteString) }
            }
        } else {
            _ = provider.loadObject(ofClass: String.self) { text, _ in
                if let text { Task { @MainActor in model.read(text) } }
            }
        }
        return true
    }
}

struct InputView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(SettingsKey.theme) private var theme = Theme.charcoal

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 12) {
            if let session = model.savedSession { continueCard(session) }
            TextEditor(text: $model.text)
                .font(.system(size: 15, design: .serif))
                .lineSpacing(4)
                .scrollContentBackground(.hidden)
                .padding(12)
                .background(theme.text.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                .overlay {
                    if model.text.isEmpty {
                        Text("Paste or type text here, or drop a file (TXT, Markdown, PDF, RTF, Word, HTML, ODT) onto the window.\n\nTip: select text in any app and choose Services › Read with Odak.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(theme.dim)
                            .padding(40)
                            .allowsHitTesting(false)
                    }
                }
                .accessibilityLabel("Text to read")

            HStack {
                Button("Open File…") { model.isImporterPresented = true }
                    .help("Open a document (⌘O)")
                Button("Paste & Read") { model.pasteAndRead() }
                    .help("Read the clipboard (⇧⌘V)")
                Spacer()
                Button("Read") { model.read(model.text) }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .disabled(model.text.allSatisfy(\.isWhitespace))
                    .help("Open in the reader (⌘↩)")
            }
        }
        .padding([.horizontal, .bottom], 20)
    }

    private func continueCard(_ session: AppModel.Session) -> some View {
        let preview = session.text.split(whereSeparator: \.isWhitespace).prefix(8).joined(separator: " ")
        let percent = model.savedTotal == 0 ? 0 : session.index * 100 / model.savedTotal
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Continue reading").font(.headline)
                Text("\(preview)… · \(percent)% read").font(.callout).foregroundStyle(theme.dim).lineLimit(1)
            }
            Spacer()
            Button("Continue") { model.read(session.text) }
                .buttonStyle(.borderedProminent)
                .help("Open the reader where you left off")
            Button { model.forgetSession() } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain)
                .foregroundStyle(theme.dim)
                .help("Forget this reading")
                .accessibilityLabel("Forget this reading")
        }
        .padding(12)
        .background(theme.text.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }
}
