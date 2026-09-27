import Foundation
import os

/// Links the wippr keyboard and the app through small JSON files in the App Group.
/// Keyboards can't use the mic, so the app records (its mic stays on in the background); the keyboard sends
/// start/stop and types the result. Both sides poll: Darwin notifications never reached the keyboard on iOS 27.
enum KeyboardHandoff {
    enum Phase: String, Codable {
        case off, ready, recording, processing
    }

    /// What a dictation is for; sent with the stop.
    enum Mode: String, Codable {
        /// Clean up the speech and type it.
        case dictate
        /// The speech is an instruction: rewrite `Command.text` (or, if empty, write what it asks for).
        case edit
        /// Discard the recording (the key was tapped to undo).
        case cancel
    }

    struct Text: Codable {
        var id: UUID
        var text: String
        var date: Date
        /// True when `text` replaces the text sent for editing. Empty `text` with `edit` means the edit failed.
        var edit: Bool?
    }

    private struct Status: Codable {
        var phase: Phase
        var date: Date
    }

    struct Command: Codable {
        var id: UUID
        var record: Bool
        /// When the key went down; the app replays audio from here. Optional so older files still decode.
        var date: Date?
        var mode: Mode?
        /// The text to edit (the selection, or the text before the cursor).
        var text: String?
    }

    /// The keyboard ignores text older than this.
    static let maxAge: TimeInterval = 15

    // App → keyboard

    static func send(_ text: String, edit: Bool = false) { write(Text(id: UUID(), text: text, date: .now, edit: edit), to: "text") }

    static func latestText() -> Text? {
        guard let text = read(Text.self, from: "text"), Date.now.timeIntervalSince(text.date) < maxAge else { return nil }
        return text
    }

    /// The app also calls this every second as a heartbeat.
    static func setStatus(_ phase: Phase) { write(Status(phase: phase, date: .now), to: "status") }

    /// `.off` when the app hasn't reported for a few seconds (mic turned off, or the app was killed).
    static func status() -> Phase {
        guard let status = read(Status.self, from: "status"), Date.now.timeIntervalSince(status.date) < 5 else { return .off }
        return status.phase
    }

    /// Where the keyboard's button sits on iPad, where the keyboard is too wide for a full-width button.
    enum ButtonPosition: String, Codable, CaseIterable {
        case left, center, right
    }

    static func setButtonPosition(_ position: ButtonPosition) { write(position, to: "button-position") }

    static func buttonPosition() -> ButtonPosition { read(ButtonPosition.self, from: "button-position") ?? .center }

    // Keyboard → app

    static func sendCommand(record: Bool, mode: Mode = .dictate, text: String? = nil) {
        write(Command(id: UUID(), record: record, date: .now, mode: mode, text: text), to: "command")
    }

    static func command() -> Command? { read(Command.self, from: "command") }

    private static let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.satuke.noboard")
    private static let log = Logger(subsystem: "cx.immortal.wippr", category: "handoff")

    private static func write(_ value: some Encodable, to name: String) {
        guard let url = container?.appendingPathComponent("\(name).json"),
              let data = try? JSONEncoder().encode(value) else { return log.error("no App Group container") }
        do { try data.write(to: url, options: .atomic) } catch { log.error("write \(name, privacy: .public): \(error, privacy: .public)") }
    }

    private static func read<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        guard let url = container?.appendingPathComponent("\(name).json") else {
            log.error("no App Group container")
            return nil
        }
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do { return try JSONDecoder().decode(type, from: Data(contentsOf: url)) } catch {
            log.error("read \(name, privacy: .public): \(error, privacy: .public)")
            return nil
        }
    }
}
