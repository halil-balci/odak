import Testing
@testable import OdakCore

@Suite struct TokenizerTests {
    @Test func emptyAndWhitespace() {
        #expect(Tokenizer.tokenize("").isEmpty)
        #expect(Tokenizer.tokenize("   \n\t \n\n  ").isEmpty)
    }

    @Test func collapsesWhitespaceAndKeepsPunctuation() {
        let t = Tokenizer.tokenize("  Hello,   world!\tHow\u{00A0}are you?  ")
        #expect(t.map(\.text) == ["Hello,", "world!", "How", "are", "you?"])
    }

    @Test func punctuationOnly() {
        let t = Tokenizer.tokenize("... — !!")
        #expect(t.map(\.text) == ["...", "—", "!!"])
        #expect(t.allSatisfy { $0.orpIndex == 0 })
    }

    @Test func emDashJoinedWordStaysOneToken() {
        #expect(Tokenizer.tokenize("word—word").map(\.text) == ["word—word"])
    }

    @Test func turkishUnicode() {
        let t = Tokenizer.tokenize("Çığ düştü, İstanbul'da şöyle böyle.")
        #expect(t.map(\.text) == ["Çığ", "düştü,", "İstanbul'da", "şöyle", "böyle."])
        #expect(t[0].parts.orp == "ı")
        for token in t { #expect(token.orpIndex < token.text.count) }
    }

    @Test func sentencesAndParagraphs() {
        let t = Tokenizer.tokenize("One two. Three!\nfour\n\n\nFive six")
        #expect(t.map(\.text) == ["One", "two.", "Three!", "four", "Five", "six"])
        #expect(t.map(\.sentenceIndex) == [0, 0, 1, 2, 3, 3])
        #expect(t.map(\.endsParagraph) == [false, false, false, true, false, true])
    }

    @Test func quotedSentenceEnd() {
        let t = Tokenizer.tokenize("He said \"stop.\" Then left")
        #expect(t[2].sentenceIndex == 0 && t[3].sentenceIndex == 1)
    }
}

@Suite struct ORPTests {
    @Test(arguments: [
        ("a", 0), ("an", 1), ("hello", 1), ("reader", 2), ("wonderful", 2),
        ("comprehends", 3), ("understandings", 4), ("antidisestablishmentarianism", 4),
    ])
    func byLength(word: String, expected: Int) {
        #expect(ORP.index(for: word) == expected)
    }

    @Test func offsetByLeadingPunctuation() {
        #expect(ORP.index(for: "\"hello\"") == 2)
        #expect(ORP.index(for: "(a)") == 1)
        #expect(ORP.index(for: "«understandings»") == 5)
    }

    @Test(arguments: ["I'm", "O'nun", "U.S.", "e.g.", "a\u{200B}b", "don't"])
    func landsOnWordCharacter(word: String) {
        #expect(Tokenizer.isWordCharacter(Array(word)[ORP.index(for: word)]))
    }

    @Test func neverOutOfBounds() {
        let samples = ["", "a", ".", "\"", "a.", "((x", "—", "x" + String(repeating: ".", count: 20)]
            + (1...40).map { String(repeating: "x", count: $0) }
            + (1...40).map { "\"" + String(repeating: "ğ", count: $0) + "!\"" }
        for w in samples {
            let i = ORP.index(for: w)
            #expect(i >= 0)
            if !w.isEmpty { #expect(i < w.count, "\(w)") }
        }
    }

    @Test func partsSplitAroundORP() {
        let t = Tokenizer.tokenize("reading")[0]
        #expect(t.parts == ("re", "a", "ding"))
    }
}

@Suite struct TimingTests {
    @Test func multipliers() {
        #expect(Timing.multiplier(for: "word", endsParagraph: false) == 1)
        #expect(Timing.multiplier(for: "word.", endsParagraph: false) == Timing.sentenceEnd)
        #expect(Timing.multiplier(for: "word?", endsParagraph: false) == Timing.sentenceEnd)
        #expect(Timing.multiplier(for: "word…", endsParagraph: false) == Timing.sentenceEnd)
        #expect(Timing.multiplier(for: "word,", endsParagraph: false) == Timing.clause)
        #expect(Timing.multiplier(for: "word;", endsParagraph: false) == Timing.clause)
        #expect(Timing.multiplier(for: "word:", endsParagraph: false) == Timing.clause)
        #expect(Timing.multiplier(for: "word.", endsParagraph: true) == Timing.paragraphEnd)
        #expect(Timing.multiplier(for: "wonderful", endsParagraph: false) == 1 + Timing.longWordBonus)
        #expect(Timing.multiplier(for: "understandings", endsParagraph: false) == 1 + Timing.veryLongWordBonus)
        #expect(Timing.multiplier(for: "understandings.", endsParagraph: false) == Timing.sentenceEnd + Timing.veryLongWordBonus)
    }

    @Test func tokenizerAppliesParagraphMultiplier() {
        let t = Tokenizer.tokenize("a b.\n\nc")
        #expect(t.map(\.delayMultiplier) == [1, Timing.paragraphEnd, Timing.paragraphEnd])
    }
}
