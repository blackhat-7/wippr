#if DEBUG
import Foundation
import UIKit

/// Debug builds only: runs the cleanup bench on the device. Launch with `-cleanupBench` after copying
/// `bench-in.json` ({"id": "raw ASR text"}) into Documents; results go to `Documents/bench-out-<foreground or background>.jsonl`.
/// `-cleanupBench background` waits until the app is in the background first (to test the Neural Engine there).
@MainActor
enum CleanupBench {
    static func runIfRequested() {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-cleanupBench") else { return }
        let background = args.dropFirst(i + 1).first == "background"
        setvbuf(stdout, nil, _IONBF, 0) // print straight to the devicectl console
        Task {
            if background {
                print("bench: waiting for background")
                await waitForBackground()
            }
            await run(label: background ? "background" : "foreground")
        }
    }

    private static func waitForBackground() async {
        for await _ in NotificationCenter.default.notifications(named: UIApplication.didEnterBackgroundNotification) {
            return
        }
    }

    private static func run(label: String) async {
        let docs = URL.documentsDirectory
        let task = UIApplication.shared.beginBackgroundTask(withName: "cleanupBench")
        defer { UIApplication.shared.endBackgroundTask(task) }
        guard let data = try? Data(contentsOf: docs.appending(path: "bench-in.json")),
              let cases = try? JSONDecoder().decode([String: String].self, from: data)
        else { return print("bench: no bench-in.json") }
        print("bench: \(cases.count) cases, engine installed: \(NeuralEngine.isInstalled), available: \(NeuralEngine.isAvailable)")
        let out = docs.appending(path: "bench-out-\(label).jsonl")
        var lines = ""
        for (n, id) in cases.keys.sorted().enumerated() {
            print("bench: start \(id)")
            let start = Date.now
            let text = await NeuralEngine.clean(cases[id]!)
            let ms = Int(Date.now.timeIntervalSince(start) * 1000)
            let row: [String: Any] = ["id": id, "output": text ?? NSNull(), "ms": ms, "first": n == 0, "mode": label]
            lines += String(decoding: try! JSONSerialization.data(withJSONObject: row), as: UTF8.self) + "\n"
            print("bench: \(id) \(ms) ms \(text == nil ? "FAILED" : "ok")")
            try? lines.write(to: out, atomically: true, encoding: .utf8) // saved as it goes, in case it stalls
        }
        print("bench: done")
    }
}
#endif
