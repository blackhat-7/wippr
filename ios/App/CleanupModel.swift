import Foundation
import Observation

/// Experimental, for testing: which model cleans dictation, picked on Home. Apple Intelligence is the default
/// and the shipping path; S1-mini on the Neural Engine and Off are there to compare against it.
enum CleanupModel: String, CaseIterable, Identifiable {
    case apple, s1mini, s1miniCPU, off

    static let key = "cleanupModel"

    var id: String { rawValue }

    var name: String {
        switch self {
        case .apple: "Apple Intelligence"
        case .s1mini: "S1-mini · Neural Engine"
        case .s1miniCPU: "S1-mini · CPU"
        case .off: "Off"
        }
    }

    /// Either copy of S1-mini: same model, same trained styles.
    var isS1mini: Bool { self == .s1mini || self == .s1miniCPU }

    static var current: CleanupModel {
        UserDefaults.standard.string(forKey: key).flatMap(CleanupModel.init) ?? .apple
    }

    /// The last cleanup, for comparing models on Home: which one did it, and how long it took.
    @MainActor static var last: (model: CleanupModel, ms: Int)? {
        get { CleanupStats.shared.last }
        set { CleanupStats.shared.last = newValue }
    }
}

@MainActor @Observable
final class CleanupStats {
    static let shared = CleanupStats()
    var last: (model: CleanupModel, ms: Int)?
}

/// Experimental, for testing: which model transcribes dictation. Apple's SpeechTranscriber is the default.
enum TranscriberModel: String, CaseIterable, Identifiable {
    case apple, parakeet

    static let key = "transcriberModel"

    var id: String { rawValue }

    var name: String {
        switch self {
        case .apple: "Apple SpeechTranscriber"
        case .parakeet: "Parakeet · Neural Engine"
        }
    }

    /// Which one a dictation actually used (a picked model that isn't ready falls back to Apple's).
    static func of(_ transcriber: any SpeechInput) -> TranscriberModel {
        transcriber is ParakeetTranscriber ? .parakeet : .apple
    }

    static var current: TranscriberModel {
        UserDefaults.standard.string(forKey: key).flatMap(TranscriberModel.init) ?? .apple
    }
}

/// Command mode's recognizer. Off (Apple's transcript, nothing to download) unless Whisper is downloaded, which
/// hears commands far better; a choice made on Home wins. Apple's also stands in for speech too long for a command.
enum TerminalTranscriber: String, CaseIterable, Identifiable {
    case off, whisper

    static let key = "terminalTranscriber"

    var id: String { rawValue }

    var name: String {
        switch self {
        case .off: "Off"
        case .whisper: CommandTranscriber.isDownloaded ? "Whisper small.en · CPU" : "Download Whisper (264 MB)"
        }
    }

    static var current: TerminalTranscriber {
        UserDefaults.standard.string(forKey: key).flatMap(TerminalTranscriber.init)
            ?? (CommandTranscriber.isDownloaded ? .whisper : .off)
    }
}
