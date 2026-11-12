import AppKit
import OdakCore
import Observation

/// Single shared state so the window, Services and file-open handlers drive the same reader.
@MainActor @Observable
final class AppModel {
    static let shared = AppModel()

    let engine: ReaderEngine
    var text = ""
    var isReading = false
    /// False until the loaded text is played for the first time; drives the "click to start" hint.
    var hasStarted = false
    /// Index the reader opened at (> 0 when resuming); the hint shows while still there.
    var startIndex = 0
    var isImporterPresented = false
    var isStatsPresented = false
    var errorMessage: String?

    /// Last unfinished reading, persisted in `sessionURL`.
    private(set) var savedSession: Session?
    /// Word count of `savedSession.text`, for the "Continue reading" percentage.
    private(set) var savedTotal = 0
    private(set) var stats: [String: DayStats]

    @ObservationIgnored private var playStartedAt: Date?
    @ObservationIgnored private var wordsFlushed = 0
    @ObservationIgnored private var lastSessionSave = Date.distantPast

    init() {
        let defaults = UserDefaults.standard
        let saved = defaults.integer(forKey: SettingsKey.defaultWPM)
        engine = ReaderEngine(wpm: saved == 0 ? 300 : saved)
        engine.slowStart = defaults.object(forKey: SettingsKey.slowStart) as? Bool ?? true
        stats = defaults.data(forKey: SettingsKey.readingStats).flatMap { try? JSONDecoder().decode([String: DayStats].self, from: $0) } ?? [:]
        if let data = try? Data(contentsOf: Self.sessionURL), let session = try? JSONDecoder().decode(Session.self, from: data) {
            savedSession = session
            savedTotal = Tokenizer.tokenize(session.text).count
        }
    }

    func read(_ newText: String) {
        guard !newText.allSatisfy(\.isWhitespace) else { return }
        if isReading { saveProgress() }
        text = newText
        engine.load(text: newText)
        if let s = savedSession, s.text == newText, s.index < engine.tokens.count - 1 { engine.seek(to: s.index) }
        startIndex = engine.currentIndex
        hasStarted = false
        isReading = true
    }

    func open(_ url: URL) {
        Task {
            do { read(try await TextExtractor.text(from: url)) } catch { errorMessage = error.localizedDescription }
        }
    }

    func pasteAndRead() {
        if let s = NSPasteboard.general.string(forType: .string) { read(s) }
    }

    func close() {
        engine.pause()
        saveProgress()
        isReading = false
    }

    // MARK: Session + stats

    struct Session: Codable { var text: String, index: Int, savedAt: Date }
    struct DayStats: Codable { var words = 0, seconds = 0.0 }

    private static let sessionURL = URL.applicationSupportDirectory.appending(path: "Odak/last-session.json")

    /// Called by the reader whenever play state changes.
    func playStateChanged(playing: Bool) {
        if playing { hasStarted = true }
        flushStats()
        if !playing { saveSession() }
    }

    /// Called by the reader on every index change; saves at most every ~5 s while playing.
    func indexChanged() {
        guard engine.isPlaying, Date.now.timeIntervalSince(lastSessionSave) > 5 else { return }
        saveSession()
    }

    /// Flushes stats and the session; used on pause, close and terminate.
    func saveProgress() {
        guard isReading else { return }
        flushStats()
        saveSession()
    }

    private func saveSession() {
        lastSessionSave = .now
        guard !engine.tokens.isEmpty else { return }
        // At 0 or at the end there is nothing to continue. Drop this text's session, but never let a
        // just-opened or finished text clobber another text's unfinished one.
        guard engine.currentIndex > 0, !engine.isAtEnd else {
            if savedSession?.text == text { forgetSession() }
            return
        }
        let session = Session(text: text, index: engine.currentIndex, savedAt: .now)
        savedSession = session
        savedTotal = engine.tokens.count
        // Failures are ignored: persistence must never block reading.
        try? FileManager.default.createDirectory(at: Self.sessionURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(session).write(to: Self.sessionURL, options: .atomic)
    }

    func forgetSession() {
        savedSession = nil
        try? FileManager.default.removeItem(at: Self.sessionURL)
    }

    /// Adds words read and play time since the last flush to today's entry.
    private func flushStats() {
        let now = Date.now
        let seconds = playStartedAt.map { now.timeIntervalSince($0) } ?? 0
        let words = engine.wordsRead - wordsFlushed
        wordsFlushed = engine.wordsRead
        playStartedAt = engine.isPlaying ? now : nil
        guard words > 0 || seconds > 0 else { return }
        // shortcut: a session spanning midnight is credited to the day it is flushed on; fine for daily totals.
        stats[Self.dayKey(now), default: DayStats()].words += words
        stats[Self.dayKey(now), default: DayStats()].seconds += seconds
        saveStats()
    }

    func resetStats() {
        stats = [:]
        saveStats()
    }

    private func saveStats() {
        let cutoff = Self.dayKey(Calendar.current.date(byAdding: .day, value: -365, to: .now)!)
        stats = stats.filter { $0.key >= cutoff }  // yyyy-MM-dd sorts chronologically
        if let data = try? JSONEncoder().encode(stats) { UserDefaults.standard.set(data, forKey: SettingsKey.readingStats) }
    }

    static func dayKey(_ date: Date) -> String { dayFormatter.string(from: date) }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}
