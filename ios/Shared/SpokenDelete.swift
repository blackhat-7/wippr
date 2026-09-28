/// Spoken deletes, in any app and without Apple Intelligence: "delete that", "delete word", "delete sentence",
/// "delete line". The app matches the whole transcript; the keyboard, which can see the text, works out how much to delete.
enum SpokenDelete: String, Codable {
    case that, word, sentence, line

    private static let phrases: [String: SpokenDelete] = [
        "delete that": .that, "scratch that": .that, "undo that": .that,
        "delete word": .word, "delete last word": .word, "delete the last word": .word, "delete previous word": .word,
        "delete sentence": .sentence, "delete last sentence": .sentence, "delete the last sentence": .sentence,
        "delete previous sentence": .sentence,
        "delete line": .line, "delete the line": .line, "clear line": .line,
    ]

    /// The delete the whole transcript asks for, ignoring case and punctuation ("Delete that." matches).
    static func match(_ transcript: String) -> SpokenDelete? {
        let words = transcript.lowercased().split { !$0.isLetter }.joined(separator: " ")
        return phrases[words]
    }

    /// How many characters to delete from the end of `before` (the text before the cursor). `lastTyped` is noboard's
    /// last insertion, for "delete that": deleted only if the text still ends with it.
    func count(before: String, lastTyped: String?) -> Int {
        let text = Array(before)
        var end = text.count
        switch self {
        case .that:
            guard let lastTyped, !lastTyped.isEmpty, before.hasSuffix(lastTyped) else { return 0 }
            return lastTyped.count
        case .word: // trailing spaces, then the word
            while end > 0, text[end - 1].isWhitespace { end -= 1 }
            while end > 0, !text[end - 1].isWhitespace { end -= 1 }
        case .sentence: // back to the previous sentence's end or a line break, keeping them
            while end > 0, text[end - 1].isWhitespace { end -= 1 }
            if end > 0, ".!?".contains(text[end - 1]) { end -= 1 }
            while end > 0, !".!?\n".contains(text[end - 1]) { end -= 1 }
        case .line: // back to the line break, keeping it
            while end > 0, text[end - 1] != "\n" { end -= 1 }
        }
        return text.count - end
    }
}
