/// One word as shown by the reader.
public struct Token: Equatable, Sendable {
    public let text: String
    /// Index (in `Character`s) of the letter to highlight. Always a valid index into `text`.
    public let orpIndex: Int
    public let delayMultiplier: Double
    public let sentenceIndex: Int
    public let endsParagraph: Bool

    public init(text: String, orpIndex: Int, delayMultiplier: Double, sentenceIndex: Int, endsParagraph: Bool) {
        self.text = text
        self.orpIndex = orpIndex
        self.delayMultiplier = delayMultiplier
        self.sentenceIndex = sentenceIndex
        self.endsParagraph = endsParagraph
    }

    /// Text before, at and after the ORP character.
    public var parts: (left: String, orp: String, right: String) {
        let chars = Array(text)
        guard !chars.isEmpty else { return ("", "", "") }
        return (String(chars[..<orpIndex]), String(chars[orpIndex]), String(chars[(orpIndex + 1)...]))
    }
}
