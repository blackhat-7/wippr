import FoundationModels

/// Terminal fields: types what was said as a shell command. `SpokenSymbols` turns "dash dash", "slash", "pipe"…
/// into characters, then Apple's on-device model fixes names speech recognition heard as other words
/// ("get status" → "git status"). The model's answer is only used if it keeps the same symbols and stays
/// close to what was heard, so it can fix names but never invent a different command.
/// Terminals also get prose (a prompt for Claude Code, a question): that's typed as normal text instead.
@MainActor
enum CommandWriter {
    /// The command to type, or nil when the speech is prose rather than a command.
    /// `heard`: the transcript, then the recognizer's alternatives. `screen`: text before the cursor, often the prompt.
    static func write(heard: [String], screen: String = "") async -> String? {
        let typed = SpokenSymbols.apply(heard.first ?? "")
        guard !typed.isEmpty, !isProse(typed) else { return nil }
        guard Cleaner.isAvailable, let fixed = await fixNames(typed, alternatives: heard.dropFirst().map(SpokenSymbols.apply), screen: screen),
              symbols(fixed) == symbols(typed), similarity(fixed.lowercased(), typed) >= 0.5
        else { return typed }
        return fixed
    }

    @Generable
    struct Fixed {
        @Guide(description: "The command with misheard names replaced, on one line")
        var command: String
    }

    /// Sentences are full of small English words and commands aren't: "make sure the tests pass before you commit"
    /// is prose, `git commit -m "fix the bug"` isn't (it has symbols).
    static func isProse(_ typed: String) -> Bool {
        let words = typed.split(separator: " ")
        let small = words.filter { functionWords.contains(String($0)) }.count
        return words.count >= 4 && small >= 2 && symbols(typed).isEmpty
    }

    private static let functionWords: Set = [
        "the", "a", "an", "to", "of", "in", "on", "for", "with", "and", "or", "but", "is", "are", "was", "be", "it", "this",
        "that", "these", "what", "why", "how", "where", "when", "which", "who", "can", "could", "would", "should", "please",
        "you", "your", "we", "our", "i", "me", "my", "do", "does", "did", "not", "if", "so", "there", "then", "before", "after",
    ]

    private static func fixNames(_ typed: String, alternatives: [String], screen: String) async -> String? {
        let session = LanguageModelSession(instructions: instructions)
        var prompt = "Command: \(typed)"
        let others = alternatives.filter { $0 != typed }
        if !others.isEmpty { prompt += "\nOther hearings: \(others.joined(separator: " | "))" }
        if !screen.isEmpty { prompt += "\nScreen before the cursor: \(screen.suffix(300))" }
        #if compiler(>=6.4) // Xcode 27 SDK renamed it; back-deployed to iOS 26
        let options = GenerationOptions(samplingMode: .greedy)
        #else
        let options = GenerationOptions(sampling: .greedy)
        #endif
        // The model has been seen to never answer (and to ignore cancellation), so give up after `timeout`.
        let command: String? = await withCheckedContinuation { continuation in
            var done = false
            func finish(_ command: String?) {
                guard !done else { return }
                done = true
                continuation.resume(returning: command)
            }
            Task { finish(try? await session.respond(to: prompt, generating: Fixed.self, options: options).content.command) }
            Task { try? await Task.sleep(for: timeout); finish(nil) }
        }
        // One line only: a command must never carry a newline, which would run it.
        let line = command?.split(whereSeparator: \.isNewline).first?.trimmingCharacters(in: .whitespaces) ?? ""
        return line.isEmpty ? nil : line
    }

    /// Typical answers take under a second.
    static let timeout = Duration.seconds(3)

    /// The command's symbols in order: a fix may change words, not these.
    private static func symbols(_ command: String) -> [Character] {
        command.filter { !$0.isLetter && !$0.isNumber && !$0.isWhitespace }.map { $0 }
    }

    /// 1 for equal strings, 0 for nothing in common (Levenshtein distance over the longer length).
    private static func similarity(_ a: String, _ b: String) -> Double {
        let a = Array(a), b = Array(b)
        guard !a.isEmpty, !b.isEmpty else { return a.count == b.count ? 1 : 0 }
        var row = Array(0...b.count)
        for i in 1...a.count {
            var previous = row[0]
            row[0] = i
            for j in 1...b.count {
                let saved = row[j]
                row[j] = min(row[j] + 1, row[j - 1] + 1, previous + (a[i - 1] == b[j - 1] ? 0 : 1))
                previous = saved
            }
        }
        return 1 - Double(row[b.count]) / Double(max(a.count, b.count))
    }

    static let instructions = """
    You fix a shell command that speech recognition typed. Its symbols are already right, but names were often heard as other English words that sound alike: commands, subcommands, flags, file and folder names, environment variables.

    Replace each misheard name with the real name it sounds like. Two heard words can be one name, and a name can be heard glued to the next word. Change nothing else: keep every symbol, argument and the word order, and don't add or remove anything. A word that already makes sense stays as it is. Other hearings and the screen, when given, show which names are meant.

    Examples:
    Command: yawn add react => yarn add react
    Command: terror form plan -out plan.bin => terraform plan -out plan.bin
    Command: hell m list --all-namespaces => helm list --all-namespaces
    Command: go lang ci-lint run => golangci-lint run
    Command: pnpminstall => pnpm install
    Command: echo $home => echo $HOME
    Command: cd ~/projects/wiper => cd ~/projects/wiper
    """
}
