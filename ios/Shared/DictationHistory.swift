#if DEBUG
import Foundation

/// Debug builds only: release builds (TestFlight, App Store) don't contain this at all, so nobody else's dictation is
/// ever kept. For tuning on the developer's own devices: each dictation (what the recognizers heard, what was typed,
/// which cleanup model) and each correction (tap to undo, "delete that"), as JSON lines in the App Group, so the app
/// and the keyboard can both add to it. About 2 MB, weeks of dictation; the oldest half goes when it's full. It never
/// leaves the device unless copied off with `xcrun devicectl device copy from`.
enum DictationHistory {
    private static let file = FileManager.default
        .containerURL(forSecurityApplicationGroupIdentifier: Bundle.main.object(forInfoDictionaryKey: "AppGroup") as! String)?
        .appending(path: "Library/dictation-history.jsonl") // devicectl can only read Library, Documents and tmp
    private static let queue = DispatchQueue(label: "cx.immortal.wippr.dictation-history")
    private static let maxBytes = 2 << 20

    static func dictation(id: UUID?, mode: String, heard: String, whisper: String? = nil, typed: String, cleanup: String? = nil) {
        append(["event": "dictation", "id": id?.uuidString, "mode": mode, "heard": heard, "whisper": whisper,
                "typed": typed, "cleanup": cleanup])
    }

    /// The user took dictation `id` back: "undo" (a quick tap) or "delete that".
    static func correction(_ kind: String, id: UUID?) {
        append(["event": kind, "id": id?.uuidString])
    }

    /// Why a recognizer's result is missing from the next dictation ("whisper skipped: no speech detected").
    static func note(_ text: String) {
        append(["event": "note", "note": text])
    }

    private static func append(_ fields: [String: String?]) {
        var fields = fields.compactMapValues { $0 }
        fields["date"] = Date.now.formatted(.iso8601)
        guard let file, let json = try? JSONSerialization.data(withJSONObject: fields, options: .sortedKeys) else { return }
        queue.async {
            let line = json + Data("\n".utf8)
            if let handle = try? FileHandle(forWritingTo: file) {
                handle.seekToEndOfFile()
                handle.write(line)
                let size = handle.offsetInFile
                try? handle.close()
                if size > maxBytes, let data = try? Data(contentsOf: file) { // keep the newer half, from a line start
                    let half = data.suffix(maxBytes / 2)
                    let start = half.firstIndex(of: UInt8(ascii: "\n")).map { half.index(after: $0) } ?? half.startIndex
                    try? Data(half[start...]).write(to: file, options: .atomic)
                }
            } else {
                try? line.write(to: file)
            }
        }
    }
}
#endif
