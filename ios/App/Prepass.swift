import Foundation

/// Rules that run on the transcript before S1-mini: spoken lists become real lists.
/// S1-mini turns "number one passport number two charger" into items called "Number 1", and ignores "bullet point".
/// Port of the list rules in `bench/e2e/prepass.py` (`prepass(text, commands=False)`); keep the two in sync.
/// On Parakeet output they lift the list score from 3.8 to 4.2 (`bench/e2e/results/summary.md`).
enum Prepass {
    private static let edge = "[ \\t,.;:!?]*"
    private static let numbers = (["one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"]
        + (1...10).map(String.init)).joined(separator: "|")

    static func lists(_ text: String) -> String {
        var text = text
        if matches(text, "\\bbullet(?:\\s+point)?\\b") >= 2 {
            text = list(split(text, "\(edge)\\bbullet(?:\\s+point)?\\b\(edge)"), numbered: false)
        }
        if matches(text, "\\bnumber\\s+(one|1)\\b") > 0, matches(text, "\\bnumber\\s+(two|2)\\b") > 0 {
            text = list(split(text, "\(edge)\\bnumber\\s+(?:\(numbers))\\b\(edge)"), numbered: true)
        }
        return text
    }

    /// "Grocery list" + items → "Grocery list:\n- Apples\n- Oat milk".
    private static func list(_ parts: [String], numbered: Bool) -> String {
        var head = parts[0].trimmingCharacters(in: .whitespaces)
        while head.last == "," || head.last == "." { head.removeLast() }
        if !head.isEmpty, !head.hasSuffix(":") { head += ":" }
        let items = parts.dropFirst()
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " ,.;")) }
            .filter { !$0.isEmpty }
            .enumerated()
            .map { i, item in (numbered ? "\(i + 1). " : "- ") + item.prefix(1).uppercased() + item.dropFirst() }
        return ([head] + items).filter { !$0.isEmpty }.joined(separator: "\n")
    }

    private static func regex(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: .caseInsensitive)
    }

    private static func matches(_ text: String, _ pattern: String) -> Int {
        regex(pattern).numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
    }

    private static func split(_ text: String, _ pattern: String) -> [String] {
        var parts: [String] = []
        var from = text.startIndex
        for m in regex(pattern).matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let r = Range(m.range, in: text) else { continue }
            parts.append(String(text[from..<r.lowerBound]))
            from = r.upperBound
        }
        parts.append(String(text[from...]))
        return parts
    }
}
