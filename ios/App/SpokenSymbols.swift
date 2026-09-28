import Foundation

/// Turns spoken shell symbols into characters: "cd tilde slash nix and and just update" → "cd ~/nix && just update".
/// Symbols are a small closed set, so this is exact; CommandWriter's model then only fixes misheard names.
enum SpokenSymbols {
    static func apply(_ transcript: String) -> String {
        let words = tokens(transcript)
        var out: [String] = []
        /// Glue the next word onto the last one ("readme" + ".", then + "md").
        var glue = false
        var inQuote = false
        var i = 0
        func push(_ text: String, attach: Bool = false) {
            if (glue || attach), let last = out.popLast() { out.append(last + text) } else { out.append(text) }
            glue = false
        }
        /// True when the previous word is the command itself, a flag or an operator: a path then starts fresh.
        func startsFresh() -> Bool {
            guard let last = out.last else { return true }
            let command = out.count == 1 && last.allSatisfy(\.isLetter) // "cd", not "./run"
            return command || last.hasPrefix("-") || operators.contains(last) || last == "sudo"
        }
        while i < words.count {
            let word = words[i], next = i + 1 < words.count ? words[i + 1] : nil
            switch word {
            case "dash" where next == "dash":
                push("--"); glue = true; i += 1
            case "dash", "-":
                push("-"); glue = true
                // Spelled letters after a dash are one flag: "dash l a" → "-la".
                var letters = ""
                while i + 1 < words.count, words[i + 1].count == 1, words[i + 1].first!.isLetter {
                    letters += words[i + 1]; i += 1
                }
                if !letters.isEmpty { push(letters) }
            case "slash", "/":
                push("/", attach: !startsFresh()); glue = true
            case "dot", ".":
                push(".", attach: !startsFresh() && !(out.last?.hasSuffix("\"") ?? false)); glue = true
            case "tilde", "tilda", "tilder", "~":
                push("~", attach: out.last.map { $0.uppercased() == "HEAD" || $0.hasSuffix("/") } ?? false); glue = true
            case "underscore", "equals":
                push(word == "underscore" ? "_" : "=", attach: true); glue = true
            case "dollar", "plus":
                push(word == "dollar" ? "$" : "+"); glue = true
            case "star", "asterisk":
                push("*")
            case "at" where next.map(isHost) ?? false:
                push("@", attach: true); glue = true // "root at 10.0.0.2" → "root@10.0.0.2"
            case "pipe":
                push("|")
            case "and" where next == "and":
                push("&&"); i += 1
            case "or" where next == "or":
                push("||"); i += 1
            case "greater" where next == "than":
                push(">"); i += 1
            case "less" where next == "than":
                push("<"); i += 1
            case "semicolon":
                push(";", attach: true)
            case "quote":
                if inQuote { push("\"", attach: true) } else { push("\""); glue = true }
                inQuote.toggle()
            default:
                // Spelled letters are one word: "l s" → "ls".
                if word.count == 1, word.first!.isLetter, let last = out.last, last.count == 1, last.first!.isLetter, !glue {
                    push(word, attach: true)
                } else {
                    push(word)
                }
            }
            i += 1
        }
        return out.joined(separator: " ")
    }

    /// An IP address or domain: "192.168.1.10", "github.com".
    private static func isHost(_ word: String) -> Bool {
        word.contains(".") && word.allSatisfy { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" }
    }

    private static let operators: Set = ["|", "&&", "||", ">", "<", ";"]

    /// Lowercased words, with the recognizer's punctuation dropped (it adds commas and a final full stop).
    private static func tokens(_ transcript: String) -> [String] {
        transcript.lowercased()
            .replacingOccurrences(of: ",", with: " ")
            .split(separator: " ")
            .map { word in
                var word = String(word)
                while word.count > 1, let last = word.last, ".!?".contains(last) { word.removeLast() }
                return word
            }
            .filter { !$0.isEmpty && $0 != "." }
    }
}
