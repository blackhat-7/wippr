import ActivityKit

/// The single Live Activity wippr keeps in the Dynamic Island.
/// It stays in `ready` between dictations so the island button is always one long-press away.
struct DictationAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        enum Phase: String, Codable, Hashable {
            case ready, recording, processing
            /// Always-on: waiting for "wipper".
            case listening
        }

        var phase: Phase
        /// Live transcript while recording; the last result when ready.
        var text: String
        /// False when iOS refused the background clipboard write; opening the app retries it.
        var copied: Bool
    }
}
