import Foundation

/// How cleaned-up dictation reads, picked on Home. Standard is today's cleanup, unchanged; the others add one
/// style line to Apple Intelligence's message. Custom is the user's own description.
enum WritingStyle: String, CaseIterable, Identifiable {
    case standard, casual, relaxed, formal, custom

    static let key = "writingStyle"
    static let customKey = "customWritingStyle"

    var id: String { rawValue }

    var name: String {
        switch self {
        case .standard: "Standard"
        case .casual: "Casual"
        case .relaxed: "Relaxed"
        case .formal: "Formal"
        case .custom: "Custom…"
        }
    }

    /// One line for the menu.
    var example: String {
        switch self {
        case .standard: "I'm going to be late. There's a cute dog outside."
        case .casual: "im gonna be late. theres a cute dog outside"
        case .relaxed: "I'm gonna be late. there's a cute dog outside"
        case .formal: "I am going to be late. There is a cute dog outside."
        case .custom: "Your own description, e.g. \"British spelling\""
        }
    }

    static var current: WritingStyle {
        UserDefaults.standard.string(forKey: key).flatMap(WritingStyle.init) ?? .standard
    }

    /// The user's own description for `custom`; empty means Standard.
    static var customText: String {
        (UserDefaults.standard.string(forKey: customKey) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The style line for Apple Intelligence's message; nil for Standard, which keeps the tuned prompt exactly.
    /// Tested on an iPhone against 12 bench cases per style.
    var appleStyle: String? {
        switch self {
        case .standard: nil
        case .casual: "Style: casual. Write everything in lowercase, even I and names, drop apostrophes (im, dont, ill), keep slang like gonna, and leave off the final period."
        case .relaxed: "Style: relaxed. Keep the speaker's phrasing and slang (gonna); capitalize I and its contractions, but not the start of sentences; no final period."
        case .formal: "Style: formal. Write out contractions (I am, cannot) and slang (going to, not gonna). Keep abbreviations and names as they are."
        case .custom: Self.customText.isEmpty ? nil : "Style: \(Self.customText). Apply this style to all of it, but keep the meaning and don't add anything."
        }
    }
}
