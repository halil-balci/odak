/// All pacing constants live here.
public enum Timing {
    public static let sentenceEnd = 2.2
    public static let clause = 1.5
    public static let paragraphEnd = 2.5
    public static let longWordBonus = 0.3       // > longWordLetters
    public static let veryLongWordBonus = 0.6   // > veryLongWordLetters
    public static let longWordLetters = 8
    public static let veryLongWordLetters = 12
    public static let wpmRange = 100...1500

    static let sentenceEnders: Set<Character> = [".", "!", "?", "…"]
    static let clauseEnders: Set<Character> = [",", ";", ":"]
    static let closers: Set<Character> = ["\"", "'", ")", "]", "}", "”", "’", "»"]

    public static func multiplier(for word: String, endsParagraph: Bool) -> Double {
        var base = 1.0
        if endsParagraph { base = paragraphEnd }
        else if endsSentence(word) { base = sentenceEnd }
        else if let c = lastMeaningful(word), clauseEnders.contains(c) { base = clause }

        let letters = word.filter(Tokenizer.isWordCharacter).count
        if letters > veryLongWordLetters { base += veryLongWordBonus }
        else if letters > longWordLetters { base += longWordBonus }
        return base
    }

    static let slowStartRamp = [2.0, 1.7, 1.45, 1.25, 1.1]

    /// Extra delay factor for the first words after play starts, so the eye can settle in.
    public static func slowStartMultiplier(wordsSincePlay: Int) -> Double {
        slowStartRamp.indices.contains(wordsSincePlay) ? slowStartRamp[wordsSincePlay] : 1.0
    }

    public static func endsSentence(_ word: String) -> Bool {
        guard let c = lastMeaningful(word) else { return false }
        return sentenceEnders.contains(c)
    }

    /// Last character ignoring closing quotes/brackets, e.g. `end."` -> `.`
    private static func lastMeaningful(_ word: String) -> Character? {
        word.last(where: { !closers.contains($0) })
    }
}
