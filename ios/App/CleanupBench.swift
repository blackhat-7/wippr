#if DEBUG
import Foundation
import UIKit

/// Debug builds only: runs the cleanup bench on the device. Copy `bench-in.json` ({"id": "raw ASR text"}) into
/// Documents, then launch with `-cleanupBench s1mini` or `-cleanupBench apple` (add `background` to wait until the
/// app is in the background first). Results go to `Documents/bench-out-<model>-<foreground or background>.jsonl`.
@MainActor
enum CleanupBench {
    static func runIfRequested() {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-cleanupBench") else { return }
        let rest = args.dropFirst(i + 1)
        let model = rest.first.flatMap(CleanupModel.init) ?? .s1mini
        let background = rest.contains("background")
        setvbuf(stdout, nil, _IONBF, 0) // print straight to the devicectl console
        let previous = UserDefaults.standard.string(forKey: CleanupModel.key)
        UserDefaults.standard.set(model.rawValue, forKey: CleanupModel.key)
        Task {
            defer { UserDefaults.standard.set(previous, forKey: CleanupModel.key) } // leave Home's choice as it was
            if model == .s1mini {
                let start = Date.now
                NeuralEngine.shared.load()
                while NeuralEngine.shared.state == .loading { try? await Task.sleep(for: .milliseconds(100)) }
                print("bench: S1-mini \(NeuralEngine.shared.state) after \(Int(Date.now.timeIntervalSince(start) * 1000)) ms")
            }
            if background {
                print("bench: waiting for background")
                for await _ in NotificationCenter.default.notifications(named: UIApplication.didEnterBackgroundNotification) { break }
            }
            await run(model, label: background ? "background" : "foreground")
        }
    }

    private static func run(_ model: CleanupModel, label: String) async {
        let docs = URL.documentsDirectory
        let task = UIApplication.shared.beginBackgroundTask(withName: "cleanupBench")
        defer { UIApplication.shared.endBackgroundTask(task) }
        guard let data = try? Data(contentsOf: docs.appending(path: "bench-in.json")),
              let cases = try? JSONDecoder().decode([String: String].self, from: data)
        else { return print("bench: no bench-in.json") }
        print("bench: \(cases.count) cases, \(model.name), \(label)")
        let cleaner = Cleaner()
        let out = docs.appending(path: "bench-out-\(model.rawValue)-\(label).jsonl")
        var lines = ""
        for id in cases.keys.sorted() {
            print("bench: start \(id)")
            let text = await cleaner.clean(cases[id]!)
            let (by, ms) = CleanupModel.last ?? (model, 0)
            let row: [String: Any] = ["id": id, "output": text, "ms": ms, "model": by.rawValue, "mode": label]
            lines += String(decoding: try! JSONSerialization.data(withJSONObject: row), as: UTF8.self) + "\n"
            print("bench: \(id) \(ms) ms by \(by.rawValue)")
            try? lines.write(to: out, atomically: true, encoding: .utf8) // saved as it goes, in case it stalls
        }
        print("bench: done")
    }
}
#endif
