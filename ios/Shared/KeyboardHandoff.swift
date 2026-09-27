import Foundation

/// Hands dictated text from the app to the wippr keyboard, which types it into the focused field.
/// A file in the App Group plus a Darwin notification. The keyboard ignores text older than `maxAge`.
enum KeyboardHandoff {
    static let notification = "cx.immortal.wippr.text" as CFString
    static let maxAge: TimeInterval = 15

    private struct Message: Codable {
        var id: UUID
        var text: String
        var date: Date
    }

    private static var url: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.cx.immortal.wippr")?
            .appendingPathComponent("handoff.json")
    }

    static func send(_ text: String) {
        guard let url, let data = try? JSONEncoder().encode(Message(id: UUID(), text: text, date: .now)) else { return }
        try? data.write(to: url, options: .atomic)
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName(notification), nil, nil, true
        )
    }

    /// The last text sent, if it is recent.
    static func latest() -> (id: String, text: String)? {
        guard let url, let data = try? Data(contentsOf: url),
              let message = try? JSONDecoder().decode(Message.self, from: data),
              Date.now.timeIntervalSince(message.date) < maxAge
        else { return nil }
        return (message.id.uuidString, message.text)
    }
}
