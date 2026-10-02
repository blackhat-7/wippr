import Foundation

/// A spoken phrase that types keys instead of text, e.g. "next" → `<C-b>n` for tmux.
struct Shortcut: Codable, Identifiable, Hashable {
    var id = UUID()
    var phrase: String
    /// Text with key names in angle brackets: `<C-a>`…`<C-z>`, `<Esc>`, `<Tab>`, `<Enter>`, `<Up>`, `<Down>`, `<Left>`, `<Right>`.
    var keys: String
}

enum Shortcuts {
    /// The key names the editor offers, in the order shown.
    static let keyNames = ["Esc", "Tab", "Enter", "Up", "Down", "Left", "Right"]

    static var all: [Shortcut] {
        get {
            guard let data = UserDefaults.standard.data(forKey: "shortcuts") else { return [] }
            return (try? JSONDecoder().decode([Shortcut].self, from: data)) ?? []
        }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: "shortcuts") }
    }

    /// The shortcut whose phrase is the whole transcript, ignoring case, spaces and punctuation
    /// (speech writes "tmux attach" as "T-Mux attach.", which matches).
    static func match(_ transcript: String) -> Shortcut? {
        let spoken = normalize(transcript)
        guard !spoken.isEmpty else { return nil }
        return all.first { normalize($0.phrase) == spoken }
    }

    /// The shortcut whose phrase sounds like the transcript, at most one sound off, if no other phrase is as close:
    /// in noise "teamworks attach" is "tmux attach". On noisy test speech it took shortcuts caught from 56% to 76%, with
    /// no wrong or false triggers (learnings/bench-command.md).
    static func soundAlike(_ transcript: String) -> Shortcut? {
        let spoken = soundKeys(transcript)
        let ranked = all.map { (distance: ShellVocabulary.editDistance(soundKeys($0.phrase), spoken), shortcut: $0) }
            .sorted { $0.distance < $1.distance }
        guard let best = ranked.first, best.distance <= 1, ranked.count < 2 || ranked[1].distance > best.distance else { return nil }
        return best.shortcut
    }

    /// How each word sounds (`ShellVocabulary.soundKey`): "tmux attach" → "tmks atk". An r after a vowel is dropped,
    /// as many accents do: "Teamworks" and "T-Marks" are then one sound from "tmux".
    private static func soundKeys(_ text: String) -> String {
        text.lowercased().split { !$0.isLetter && !$0.isNumber }
            .map { ShellVocabulary.soundKey(String($0).replacing(#/([aeiouy])r/#) { String($0.1) }) }
            .joined(separator: " ")
    }

    /// A key named alone, "enter", "press tab" or "down arrow": a built-in shortcut (commands are typed without pressing a key).
    /// The key's name must be heard exactly; "arrow" only has to sound like it (speech writes "Down, Aru").
    static func key(_ transcript: String) -> Shortcut? {
        var words = transcript.lowercased().split { !$0.isLetter }.map(String.init)
        if words.first == "press" { words.removeFirst() }
        if words.count == 2, ShellVocabulary.editDistance(ShellVocabulary.soundKey(words[1]), ShellVocabulary.soundKey("arrow")) <= 1 {
            words.removeLast()
        }
        guard words.count == 1, let name = keyNames.first(where: { $0.lowercased() == words[0] }) else { return nil }
        return Shortcut(phrase: name, keys: "<\(name)>")
    }

    /// One shortcut per line, `next window = <C-b>n`: for copying shortcuts to another install of noboard.
    static func text(_ shortcuts: [Shortcut]) -> String {
        shortcuts.map { "\($0.phrase) = \($0.keys)" }.joined(separator: "\n")
    }

    /// Reads `text(_:)`'s lines into `shortcuts`: a new phrase is added, a known one gets the pasted keys.
    /// Lines that aren't `phrase = keys` are skipped. Returns how many were added and how many changed.
    static func paste(_ text: String, into shortcuts: inout [Shortcut]) -> (added: Int, updated: Int) {
        var added = 0, updated = 0
        for line in text.split(whereSeparator: \.isNewline) {
            guard let separator = line.range(of: " = ") else { continue }
            let phrase = line[..<separator.lowerBound].trimmingCharacters(in: .whitespaces)
            let keys = String(line[separator.upperBound...]) // spaces in keys are typed, so keep them
            guard !normalize(phrase).isEmpty, !keys.isEmpty else { continue }
            if let index = shortcuts.firstIndex(where: { normalize($0.phrase) == normalize(phrase) }) {
                guard shortcuts[index].keys != keys else { continue }
                shortcuts[index].keys = keys
                updated += 1
            } else {
                shortcuts.append(Shortcut(phrase: phrase, keys: keys))
                added += 1
            }
        }
        return (added, updated)
    }

    /// `keys` split into keys and plain text: `<C-b>n` → [.ctrl("b"), .text("n")]. Unknown names stay text.
    enum Part: Hashable {
        case ctrl(Character)
        /// One of `keyNames`.
        case key(String)
        case text(String)
    }

    static func parts(_ keys: String) -> [Part] {
        var parts: [Part] = []
        var rest = keys[...]
        while let match = rest.firstMatch(of: #/<([^<>\s]+)>/#) {
            if match.range.lowerBound > rest.startIndex { parts.append(.text(String(rest[..<match.range.lowerBound]))) }
            let name = match.1.lowercased()
            if name.count == 3, name.hasPrefix("c-"), let letter = name.last, ("a"..."z").contains(letter) {
                parts.append(.ctrl(letter))
            } else if let known = keyNames.first(where: { $0.lowercased() == name }) {
                parts.append(.key(known))
            } else {
                parts.append(.text(String(match.0)))
            }
            rest = rest[match.range.upperBound...]
        }
        if !rest.isEmpty { parts.append(.text(String(rest))) }
        return parts
    }

    /// The characters a terminal receives for `keys`: `<C-b>n` → "\u{02}n".
    static func expand(_ keys: String) -> String {
        parts(keys).map { part in
            switch part {
            case .ctrl(let letter): String(UnicodeScalar(letter.asciiValue! - 96)) // Ctrl+A is 0x01 … Ctrl+Z is 0x1A
            case .key(let name): codes[name]!
            case .text(let text): text.replacing(#/[\u{201C}\u{201D}]/#, with: "\"").replacing(#/[\u{2018}\u{2019}]/#, with: "'") // iOS types smart quotes
            }
        }.joined()
    }

    private static let codes = [
        "Esc": "\u{1B}", "Tab": "\t",
        "Enter": "\n", // what the keyboard's return key types
        "Up": "\u{1B}[A", "Down": "\u{1B}[B", "Right": "\u{1B}[C", "Left": "\u{1B}[D",
    ]

    /// Only the letters and digits, lowercased: how phrases are compared. "T-Mux attach." → "tmuxattach".
    static func normalize(_ text: String) -> String {
        String(text.lowercased().unicodeScalars.filter(CharacterSet.alphanumerics.contains))
    }
}
