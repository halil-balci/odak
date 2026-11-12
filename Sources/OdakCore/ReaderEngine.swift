import Foundation
import Observation

@MainActor @Observable
public final class ReaderEngine {
    public private(set) var tokens: [Token] = []
    public private(set) var currentIndex = 0
    public private(set) var isPlaying = false
    /// Words advanced automatically by the play loop; never reset (callers take deltas).
    public private(set) var wordsRead = 0
    /// Slows the first few words after each `play()` (see `Timing.slowStartMultiplier`).
    public var slowStart = true
    /// Words shown since the last `play()`; seeking while playing does not reset it.
    @ObservationIgnored private(set) var wordsSincePlay = 0

    private var storedWPM = 300
    /// Words per minute, clamped to `Timing.wpmRange`.
    public var wpm: Int {
        get { storedWPM }
        set { storedWPM = min(max(newValue, Timing.wpmRange.lowerBound), Timing.wpmRange.upperBound) }
    }

    /// suffixMultipliers[i] = sum of delay multipliers from token i to the end.
    @ObservationIgnored private var suffixMultipliers: [Double] = [0]
    @ObservationIgnored private var playTask: Task<Void, Never>?

    public init(wpm: Int = 300) { self.wpm = wpm }

    public var currentToken: Token? { tokens.indices.contains(currentIndex) ? tokens[currentIndex] : nil }
    public var progress: Double { tokens.isEmpty ? 0 : Double(currentIndex + 1) / Double(tokens.count) }
    public var secondsPerWord: TimeInterval { 60 / Double(wpm) }
    public var remainingTime: TimeInterval {
        tokens.isEmpty ? 0 : suffixMultipliers[currentIndex] * secondsPerWord
    }
    public var isAtEnd: Bool { currentIndex >= tokens.count - 1 }

    public func load(text: String) {
        pause()
        tokens = Tokenizer.tokenize(text)
        var sums = [Double](repeating: 0, count: tokens.count + 1)
        for i in tokens.indices.reversed() { sums[i] = sums[i + 1] + tokens[i].delayMultiplier }
        suffixMultipliers = sums
        currentIndex = 0
    }

    public func play() {
        guard !isPlaying, !tokens.isEmpty else { return }
        if isAtEnd { currentIndex = 0 }
        isPlaying = true
        wordsSincePlay = 0
        // Weak capture so a dropped engine ends the loop after the current sleep; no deinit needed.
        playTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let delay = self?.currentDelay else { return }
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled, let self else { return }
                self.advance()
            }
        }
    }

    public func pause() {
        playTask?.cancel()
        playTask = nil
        isPlaying = false
    }

    public func toggle() { isPlaying ? pause() : play() }

    public func seek(to index: Int) {
        guard !tokens.isEmpty else { return }
        currentIndex = min(max(index, 0), tokens.count - 1)
    }

    public func stepWord(by delta: Int) { seek(to: currentIndex + delta) }

    /// Forward: start of next sentence (or last word). Backward: start of the current sentence,
    /// or of the previous one when already at a sentence start.
    public func jumpSentence(forward: Bool) {
        guard let current = currentToken else { return }
        if forward {
            seek(to: tokens[currentIndex...].firstIndex { $0.sentenceIndex > current.sentenceIndex } ?? tokens.count - 1)
        } else {
            let start = sentenceStart(of: currentIndex)
            seek(to: start == currentIndex && start > 0 ? sentenceStart(of: start - 1) : start)
        }
    }

    public func restart() {
        let wasPlaying = isPlaying
        pause()
        currentIndex = 0
        if wasPlaying { play() }
    }

    private var currentDelay: TimeInterval? {
        let ramp = slowStart ? Timing.slowStartMultiplier(wordsSincePlay: wordsSincePlay) : 1
        return currentToken.map { $0.delayMultiplier * secondsPerWord * ramp }
    }

    private func advance() {
        if isAtEnd { pause() } else {
            currentIndex += 1
            wordsRead += 1
            wordsSincePlay += 1
        }
    }

    private func sentenceStart(of index: Int) -> Int {
        let s = tokens[index].sentenceIndex
        var i = index
        while i > 0, tokens[i - 1].sentenceIndex == s { i -= 1 }
        return i
    }
}
