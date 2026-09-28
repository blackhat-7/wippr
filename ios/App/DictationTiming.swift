import Foundation
import Observation
import os

/// Where the time goes in a dictation, from letting go of the key to the text being typed:
/// pickup (the app noticing the stop), ASR (finalizing the transcript), cleanup, and insert (the keyboard
/// noticing the text and typing it). Shown under Home's Experimental section and logged.
struct DictationTiming {
    var id: UUID?
    var released: Date
    var pickup: TimeInterval
    var asr: TimeInterval
    var cleanup: TimeInterval
    var sent: Date

    private static let log = Logger(subsystem: "cx.immortal.wippr", category: "timing")

    @MainActor static func record(released: Date, picked: Date, transcribed: Date, cleaned: Date, id: UUID?) {
        let timing = DictationTiming(id: id, released: released, pickup: picked.timeIntervalSince(released),
                                     asr: transcribed.timeIntervalSince(picked), cleanup: cleaned.timeIntervalSince(transcribed),
                                     sent: cleaned)
        DictationTimings.shared.last = timing
        log.notice("pickup \(ms(timing.pickup)) ms, asr \(ms(timing.asr)) ms, cleanup \(ms(timing.cleanup)) ms")
    }

    /// Insert and total, once the keyboard has typed this text (nil for in-app dictation, or before it's typed).
    func typed(_ typed: KeyboardHandoff.Typed?) -> (insert: TimeInterval, total: TimeInterval)? {
        guard let id, let typed, typed.id == id else { return nil }
        return (typed.date.timeIntervalSince(sent), typed.date.timeIntervalSince(released))
    }

    private static func ms(_ t: TimeInterval) -> Int { Int(t * 1000) }
}

@MainActor @Observable
final class DictationTimings {
    static let shared = DictationTimings()
    var last: DictationTiming?
}
