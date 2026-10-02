import Foundation

/// The mic's life in a small file (Library/Caches/mic-events.log, the last few hundred lines), to find why it stops
/// while the app is in the background, which the system log doesn't keep long enough to show. Event names and
/// iOS's reasons only, never what was said. `xcrun devicectl device copy from` reads it without sudo.
/// Debug builds only, like `DictationHistory`: release builds record nothing.
enum MicEvents {
    private static let file = URL.cachesDirectory.appending(path: "mic-events.log")
    private static let queue = DispatchQueue(label: "cx.immortal.wippr.mic-events")

    static func record(_ event: String) {
        #if DEBUG
        let line = "\(Date.now.formatted(.iso8601)) \(event)\n"
        queue.async {
            var lines = ((try? String(contentsOf: file, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
            lines.append(String(line.dropLast()))
            try? (lines.suffix(400).joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
        }
        #endif
    }
}
