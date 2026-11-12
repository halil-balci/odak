public enum Tokenizer {
    /// Splits text into words. A blank line ends a paragraph; single line breaks are treated as spaces
    /// (PDFs and e-mails hard-wrap lines).
    public static func tokenize(_ text: String) -> [Token] {
        var tokens: [Token] = []
        var sentence = 0
        var startNewSentence = false

        func markParagraphEnd() {
            guard let last = tokens.last, !last.endsParagraph else { return }
            tokens[tokens.count - 1] = Token(text: last.text, orpIndex: last.orpIndex,
                                delayMultiplier: Timing.multiplier(for: last.text, endsParagraph: true),
                                sentenceIndex: last.sentenceIndex, endsParagraph: true)
            startNewSentence = true
        }

        for line in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let words = line.split(whereSeparator: \.isWhitespace)
            if words.isEmpty {
                if !tokens.isEmpty { markParagraphEnd() }
                continue
            }
            for word in words.map(String.init) {
                if startNewSentence { sentence += 1; startNewSentence = false }
                tokens.append(Token(text: word, orpIndex: ORP.index(for: word),
                                    delayMultiplier: Timing.multiplier(for: word, endsParagraph: false),
                                    sentenceIndex: sentence, endsParagraph: false))
                if Timing.endsSentence(word) { startNewSentence = true }
            }
        }
        if !tokens.isEmpty { markParagraphEnd() }
        return tokens
    }

    static func isWordCharacter(_ c: Character) -> Bool { c.isLetter || c.isNumber }
}

public enum ORP {
    /// Optimal recognition point: index of the character to highlight.
    public static func index(for word: String) -> Int {
        let chars = Array(word)
        guard let first = chars.firstIndex(where: Tokenizer.isWordCharacter),
              let last = chars.lastIndex(where: Tokenizer.isWordCharacter) else { return 0 }
        let letters = chars[first...last].filter(Tokenizer.isWordCharacter).count
        let offset: Int
        switch letters {
        case ...1: offset = 0
        case 2...5: offset = 1
        case 6...9: offset = 2
        case 10...13: offset = 3
        default: offset = 4
        }
        // Count word characters, not positions, so the highlight never lands on "'" or "." inside a word.
        return chars.indices[first...last].filter { Tokenizer.isWordCharacter(chars[$0]) }.dropFirst(offset).first ?? last
    }
}
