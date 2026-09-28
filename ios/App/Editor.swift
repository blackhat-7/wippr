import FoundationModels

/// Edit mode: applies a spoken instruction to the text in the field with Apple's on-device model,
/// or writes what the instruction asks for when there is no text. Returns nil on any failure.
@MainActor
enum Editor {
    /// Apple's on-device model has a 4096-token context; keep the text well under it.
    static let maxText = 6000

    static func edit(_ text: String, instruction: String) async -> String? {
        guard Cleaner.appleAvailable, !instruction.isEmpty else { return nil }
        let session = LanguageModelSession(instructions: instructions)
        do {
            #if compiler(>=6.4) // Xcode 27 SDK renamed it; back-deployed to iOS 26
            let options = GenerationOptions(samplingMode: .greedy)
            #else
            let options = GenerationOptions(sampling: .greedy)
            #endif
            let response = try await session.respond(
                to: "<text>\n\(text.suffix(maxText))\n</text>\n<instruction>\n\(instruction)\n</instruction>",
                options: options
            )
            let result = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return result.isEmpty ? nil : result
        } catch {
            return nil
        }
    }

    static let instructions = """
    You edit text on the user's phone by following a spoken instruction. The user message has the current text inside <text> tags (it may be empty) and the instruction inside <instruction> tags. The instruction is a raw speech-to-text transcript, so ignore fillers and misheard words.

    Rules:
    - If <text> is not empty, apply the instruction to it and output the complete new text that replaces it. Change only what the instruction asks for.
    - If <text> is empty, write what the instruction asks for.
    - If the instruction asks for a terminal, shell or command-line command, output only the command on one line: no explanation, no backticks, no leading $.
    - Output only the resulting text. No preamble, quotes, tags or notes.
    - Keep the language of the text unless the instruction asks to translate.

    Examples:
    <text>hey can u send me the report by tmrw</text> <instruction>make it more formal</instruction>
    => Hi, could you please send me the report by tomorrow?
    <text></text> <instruction>git command to undo the last commit but keep the changes</instruction>
    => git reset --soft HEAD~1
    <text>We should meet on Monday. Tuesday also works.</text> <instruction>turn this into bullet points</instruction>
    => - We should meet on Monday.
    - Tuesday also works.
    """
}
