import Testing
@testable import OdakCore

@MainActor @Suite struct ReaderEngineTests {
    let text = "One two three. Four five six. Seven eight."

    @Test func emptyEngine() {
        let e = ReaderEngine()
        #expect(e.currentToken == nil && e.progress == 0 && e.remainingTime == 0)
        e.play(); e.stepWord(by: 1); e.jumpSentence(forward: true); e.seek(to: 5)
        #expect(!e.isPlaying && e.currentIndex == 0)
    }

    @Test func wpmClamped() {
        let e = ReaderEngine()
        e.wpm = 10; #expect(e.wpm == 100)
        e.wpm = 99999; #expect(e.wpm == 1500)
        #expect(ReaderEngine(wpm: 0).wpm == 100)
    }

    @Test func seekAndStepClamp() {
        let e = ReaderEngine(); e.load(text: text)
        e.seek(to: -5); #expect(e.currentIndex == 0)
        e.seek(to: 100); #expect(e.currentIndex == 7)
        e.stepWord(by: 1); #expect(e.currentIndex == 7)
        e.stepWord(by: -3); #expect(e.currentIndex == 4)
        #expect(e.currentToken?.text == "five")
    }

    @Test func jumpSentence() {
        let e = ReaderEngine(); e.load(text: text)
        e.jumpSentence(forward: true); #expect(e.currentIndex == 3)
        e.jumpSentence(forward: true); #expect(e.currentIndex == 6)
        e.jumpSentence(forward: true); #expect(e.currentIndex == 7)
        e.jumpSentence(forward: false); #expect(e.currentIndex == 6)
        e.jumpSentence(forward: false); #expect(e.currentIndex == 3)
        e.seek(to: 4)
        e.jumpSentence(forward: false); #expect(e.currentIndex == 3)
        e.seek(to: 0)
        e.jumpSentence(forward: false); #expect(e.currentIndex == 0)
    }

    @Test func progressAndRemainingTime() {
        let e = ReaderEngine(wpm: 600); e.load(text: text)
        #expect(e.progress == 1.0 / 8)
        let total = e.tokens.map(\.delayMultiplier).reduce(0, +) * 0.1
        #expect(abs(e.remainingTime - total) < 1e-9)
        e.seek(to: 7)
        #expect(e.progress == 1)
        #expect(abs(e.remainingTime - e.tokens[7].delayMultiplier * 0.1) < 1e-9)
    }

    @Test func playsToEndAndStops() async throws {
        let e = ReaderEngine(wpm: 1500); e.load(text: "a b c")
        e.play()
        #expect(e.isPlaying)
        for _ in 0..<100 where e.isPlaying { try await Task.sleep(for: .milliseconds(20)) }
        #expect(!e.isPlaying && e.currentIndex == 2)
        e.play() // at end: restarts from the beginning
        #expect(e.isPlaying && e.currentIndex == 0)
        e.pause()
    }

    @Test func pauseStopsAdvancing() async throws {
        let e = ReaderEngine(wpm: 1500); e.load(text: text)
        e.toggle(); e.toggle()
        let index = e.currentIndex
        try await Task.sleep(for: .milliseconds(150))
        #expect(!e.isPlaying && e.currentIndex == index)
    }

    @Test func loadAndRestartReset() {
        let e = ReaderEngine(); e.load(text: text)
        e.seek(to: 5); e.restart(); #expect(e.currentIndex == 0)
        e.seek(to: 5); e.play(); e.load(text: "x y")
        #expect(!e.isPlaying && e.currentIndex == 0 && e.tokens.count == 2)
    }

    @Test func slowStartTable() {
        let expected = [2.0, 1.7, 1.45, 1.25, 1.1, 1.0, 1.0]
        #expect((0..<7).map { Timing.slowStartMultiplier(wordsSincePlay: $0) } == expected)
        #expect(Timing.slowStartMultiplier(wordsSincePlay: 100) == 1.0)
        #expect(ReaderEngine().slowStart)
    }

    @Test func wordsReadCountsOnlyAutomaticAdvances() async throws {
        let e = ReaderEngine(wpm: 1500); e.slowStart = false; e.load(text: "a b c")
        e.seek(to: 2); e.stepWord(by: -1); e.jumpSentence(forward: false)
        #expect(e.wordsRead == 0)
        e.play()
        for _ in 0..<100 where e.isPlaying { try await Task.sleep(for: .milliseconds(20)) }
        #expect(e.wordsRead == 2)
        e.load(text: "x y"); e.restart()
        #expect(e.wordsRead == 2) // never reset by the engine
    }

    @Test func rampResetsOnPlayButNotOnSeek() async throws {
        let e = ReaderEngine(wpm: 1500); e.load(text: text)
        e.play()
        for _ in 0..<100 where e.wordsSincePlay < 2 { try await Task.sleep(for: .milliseconds(10)) }
        let shown = e.wordsSincePlay
        e.seek(to: 0)
        #expect(e.wordsSincePlay == shown && shown >= 2)
        e.pause(); e.play()
        #expect(e.wordsSincePlay == 0)
        e.pause()
    }
}
