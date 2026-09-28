import Foundation
import Observation

/// Experimental, for testing: which model cleans dictation, picked on Home. Apple Intelligence is the default
/// and the shipping path; S1-mini on the Neural Engine and Off are there to compare against it.
enum CleanupModel: String, CaseIterable, Identifiable {
    case apple, s1mini, off

    static let key = "cleanupModel"

    var id: String { rawValue }

    var name: String {
        switch self {
        case .apple: "Apple Intelligence"
        case .s1mini: "S1-mini · Neural Engine"
        case .off: "Off"
        }
    }

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

    static var current: TranscriberModel {
        UserDefaults.standard.string(forKey: key).flatMap(TranscriberModel.init) ?? .apple
    }
}
