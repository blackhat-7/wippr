import Foundation
import os

/// Links the wippr keyboard and the app through small JSON files in the App Group.
/// Keyboards can't use the mic, so the app records (its mic stays on in the background); the keyboard sends
/// start/stop and types the result. Both sides poll: Darwin notifications never reached the keyboard on iOS 27.
enum KeyboardHandoff {
    enum Phase: String, Codable {
        case off, ready, recording, processing
    }

    struct Text: Codable {
        var id: UUID
        var text: String
        var date: Date
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
    }

    /// The keyboard ignores text older than this.
    static let maxAge: TimeInterval = 15

    // App → keyboard

    static func send(_ text: String) { write(Text(id: UUID(), text: text, date: .now), to: "text") }

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

    // Keyboard → app

    static func sendCommand(record: Bool) { write(Command(id: UUID(), record: record, date: .now), to: "command") }

    static func command() -> Command? { read(Command.self, from: "command") }

    private static let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.cx.immortal.wippr")
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
