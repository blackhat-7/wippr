import Foundation

/// How cleaned-up dictation reads, picked on Home. Standard is today's cleanup, unchanged. The others map onto
/// S1-mini's trained control-line values (`Styling`, `Context`; see its model card) and, for Apple Intelligence,
/// add one style line to the message. Custom is free text, which only Apple Intelligence can follow.
enum WritingStyle: String, CaseIterable, Identifiable {
    case standard, casual, relaxed, formal, email, custom

    static let key = "writingStyle"
    static let customKey = "customWritingStyle"

    var id: String { rawValue }

    var name: String {
        switch self {
        case .standard: "Standard"
        case .casual: "Casual"
        case .relaxed: "Relaxed"
        case .formal: "Formal"
        case .email: "Email"
        case .custom: "Custom…"
        }
    }

    /// One line for the menu, from S1-mini's model card.
    var example: String {
        switch self {
        case .standard: "I'm going to be late. There's a cute dog outside."
        case .casual: "im gonna be late. theres a cute dog outside"
        case .relaxed: "I'm gonna be late. there's a cute dog outside"
        case .formal: "I am going to be late. There is a cute dog outside."
        case .email: "Hi Sarah,\n\n…\n\nThanks,\nJohn"
        case .custom: "Your own description, e.g. \"British spelling\""
        }
    }

    /// Email layout only works well with S1-mini (Apple Intelligence adds a subject line and a sign-off nobody said).
    static var offered: [WritingStyle] {
        allCases.filter { $0 != .email || CleanupModel.current.isS1mini }
    }

    static var current: WritingStyle {
        UserDefaults.standard.string(forKey: key).flatMap(WritingStyle.init) ?? .standard
    }

    /// The user's own description for `custom`; empty means Standard.
    static var customText: String {
        (UserDefaults.standard.string(forKey: customKey) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// S1-mini's control line. It only knows its trained values, so a custom style gets Standard's.
    var s1Control: String {
        let (styling, context) = switch self {
        case .standard, .custom: ("semi-formal", "general")
        case .casual: ("casual", "general")
        case .relaxed: ("semi-casual", "general")
        case .formal: ("formal", "general")
        case .email: ("semi-formal", "email")
        }
        return "[Styling: \(styling)] [Structure: lists] [Context: \(context)]\n"
    }

    /// The style line for Apple Intelligence's message; nil for Standard, which keeps today's prompt exactly.
    var appleStyle: String? {
        switch self {
        case .standard: nil
        case .casual: "Style: casual. Write everything in lowercase, even I and names, drop apostrophes (im, dont, ill), keep slang like gonna, and leave off the final period."
        case .relaxed: "Style: relaxed. Keep the speaker's phrasing and slang (gonna); capitalize I and its contractions, but not the start of sentences; no final period."
        case .formal: "Style: formal. Write out contractions (I am, cannot) and slang (going to, not gonna). Keep abbreviations and names as they are."
        case .email: nil // Apple Intelligence invents subjects and sign-offs here; only offered with S1-mini

        case .custom: Self.customText.isEmpty ? nil : "Style: \(Self.customText). Apply this style to all of it, but keep the meaning and don't add anything."
        }
    }
}
