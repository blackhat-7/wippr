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
                glue = false; push("--"); glue = true; i += 1 // a flag starts a new word, even after "dot"
            case "dash" where joinsWords(out, next), "-" where joinsWords(out, next):
                push("-", attach: true); glue = true // "remote dash control" → "remote-control"
            case "dash", "-":
                glue = false; push("-"); glue = true
                // Spelled letters after a dash are one flag: "dash l a" → "-la".
                var letters = ""
                while i + 1 < words.count, words[i + 1].count == 1, words[i + 1].first!.isLetter {
                    letters += words[i + 1]; i += 1
                }
                if !letters.isEmpty { push(letters) }
            case "backslash", "back" where next == "slash", "backward" where next == "slash":
                if word != "backslash" { i += 1 }
                push("\\", attach: !startsFresh()); glue = true
            case "forward" where next == "slash":
                i += 1
                fallthrough
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
            case "control" where isControlKey(words, i), "ctrl" where isControlKey(words, i):
                // "control b" → Ctrl+B, the byte a terminal gets (0x02), e.g. tmux's prefix.
                push(String(UnicodeScalar(next!.first!.asciiValue! - 96))); glue = true; i += 1
            case "escape":
                push("\u{1B}"); glue = true
            case "per" where next == "cent":
                i += 1
                fallthrough
            case "percent", "percentage":
                push("%", attach: glue)
            case "colon":
                push(":", attach: glue); glue = true
            case "open" where isBracket(next), "left" where isBracket(next):
                push(brackets[next!]!.open); glue = true; i += 1 // "open paren": glued to what follows
            case "close" where isBracket(next), "right" where isBracket(next):
                push(brackets[next!]!.close, attach: true); i += 1
            case "space":
                push(" ", attach: true); glue = true // a real space: "dot space close paren" → ". )"
            case "star", "asterisk":
                push("*")
            case "at" where next.map(isHost) ?? false:
                push("@", attach: true); glue = true // "root at 10.0.0.2" → "root@10.0.0.2"
            case "pipe":
                push("|")
            case "and" where next == "and", "ampersand" where next == "ampersand", "double" where next == "and" || next == "ampersand":
                push("&&"); i += 1
            case "ampersand":
                push("&")
            case "or" where next == "or":
                push("||"); i += 1
            case "greater" where next == "than":
                push(">"); i += 1
            case "less" where next == "than":
                push("<"); i += 1
            case "semicolon":
                push(";", attach: true)
            case "double" where next == "quote":
                i += 1
                fallthrough
            case "quote":
                if inQuote { push("\"", attach: true) } else { push("\""); glue = true }
                inQuote.toggle()
            default:
                // Spelled letters are one word: "l s" → "ls".
                if word.count == 1, word.first!.isLetter, let last = out.last, endsInSpelledLetter(last), !glue {
                    push(word, attach: true)
                } else {
                    push(word)
                }
            }
            i += 1
        }
        return out.joined(separator: " ")
    }

    /// A dash between two words, not after a command or before a letter: "pre dash commit", "tmux kill dash session",
    /// but "ls dash la" and "checkout dash b" are flags.
    private static func joinsWords(_ out: [String], _ next: String?) -> Bool {
        guard let previous = out.last, let next, next.count > 1, next.allSatisfy(\.isLetter), previous.allSatisfy(\.isLetter) else { return false }
        let commandPosition = out.count == 1 || ["sudo", "|", "&&", "||", ";"].contains(out[out.count - 2])
        return !(commandPosition && ShellVocabulary.commands.contains(previous))
    }

    /// "control b" followed by nothing, a spelled key or a symbol word. Anything else ("control b percentage" before
    /// "percentage" was known) is typed as words: sent as keys, tmux would run "p" and the rest would be typed.
    private static func isControlKey(_ words: [String], _ i: Int) -> Bool {
        guard i + 1 < words.count, words[i + 1].count == 1, words[i + 1].first!.isLetter else { return false }
        guard i + 2 < words.count else { return true }
        let after = words[i + 2]
        return after.count == 1 || symbolWords.contains(after) || after.allSatisfy { !$0.isLetter }
    }

    private static let symbolWords: Set = [
        "dash", "slash", "backslash", "dot", "space", "tilde", "tilda", "tilder", "pipe", "star", "asterisk", "quote", "double", "colon",
        "percent", "percentage", "per", "escape", "underscore", "equals", "dollar", "plus", "semicolon", "ampersand",
        "and", "or", "greater", "less", "control", "ctrl",
    ]

    /// "l", ":w": a lone letter at the end, so the next spelled letter joins it ("l s" → "ls", ": w q" → ":wq").
    private static func endsInSpelledLetter(_ word: String) -> Bool {
        guard let last = word.last, last.isLetter else { return false }
        return word.dropLast().last.map { !$0.isLetter && !$0.isNumber } ?? true
    }

    /// An IP address or domain: "192.168.1.10", "github.com".
    private static func isHost(_ word: String) -> Bool {
        word.contains(".") && word.allSatisfy { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" }
    }

    private static func isBracket(_ word: String?) -> Bool { word.map(brackets.keys.contains) ?? false }

    /// "paren", "bracket", "curly"… → their characters. "square" is [ ] ("square bracket", shortened in `tokens`).
    private static let brackets: [String: (open: String, close: String)] = [
        "paren": ("(", ")"), "parenthesis": ("(", ")"), "parentheses": ("(", ")"), "parens": ("(", ")"), "bracket": ("(", ")"),
        "parent": ("(", ")"), "parents": ("(", ")"), // how speech recognition writes "paren"
        "square": ("[", "]"), "brace": ("{", "}"), "curly": ("{", "}"),
    ]

    private static let operators: Set = ["|", "&&", "||", ">", "<", ";"]

    /// Lowercased words, with the recognizer's punctuation dropped (it adds commas and a final full stop).
    private static func tokens(_ transcript: String) -> [String] {
        transcript.lowercased()
            .replacing(#/\b(?:ctrl|control)[-+]([a-z])\b/#) { "control \($0.1)" } // Whisper writes "Ctrl+B", "control-B"
            // …and glues bracket words: "openparent", "close-paren".
            .replacing(#/\b(open|close|left|right)-?(parenthesis|parentheses|parents|parent|parens|paren|bracket|brace|curly|square)/#) { "\($0.1) \($0.2)" }
            .replacing("square bracket", with: "square").replacing("curly brace", with: "curly")
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
