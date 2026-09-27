import AVFoundation
import Observation

/// What's set up, re-read whenever the app becomes active (e.g. back from Settings).
@MainActor @Observable
final class SetupStatus {
    static let shared = SetupStatus()

    private(set) var keyboardAdded = DictationController.keyboardAdded
    /// Only known once the keyboard has appeared with Full Access (it can't write the App Group otherwise).
    private(set) var fullAccess = KeyboardHandoff.keyboardHasFullAccess
    private(set) var micPermission = AVAudioApplication.shared.recordPermission
    private(set) var cleanupAvailable = Cleaner.isAvailable
    /// Problems from the last `recheck()`; nil until it has run.
    private(set) var problems: [String]?
    private(set) var checking = false

    func refresh() {
        keyboardAdded = DictationController.keyboardAdded
        fullAccess = KeyboardHandoff.keyboardHasFullAccess
        micPermission = AVAudioApplication.shared.recordPermission
        cleanupAvailable = Cleaner.isAvailable
    }

    /// Runs the full setup check: mic permission, speech model download, Apple Intelligence.
    func recheck() async -> [String] {
        checking = true
        let found = await DictationController.shared.setUp()
        problems = found
        checking = false
        refresh()
        return found
    }
}
