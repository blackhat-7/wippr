#if DEBUG
import AVFoundation
import Foundation
import FoundationModels
import UIKit

/// Debug builds only: benches on the device, reading inputs from Documents and writing results next to them.
///
/// - `-cleanupBench apple|s1mini [background]`: `bench-in.json` ({"id": "raw ASR text"}) through `Cleaner`.
/// - `-asrBench apple|parakeet [realtime]`: every `asr/<id>.wav` through the transcriber, as if spoken into the mic.
/// - `-editBench apple`: `edit-in.json` ([{"id", "text", "instruction"}]) through `Editor`.
/// - `-editBench neural:<folder>`: the same cases through a Core AI model in `Application Support/<folder>`, with
///   Apple's edit instructions and message format (or `edit-prompt.json` if present), for picking an editor.
/// - `-cleanupBench applecustom` / `-editBench applecustom`: Apple's model with the prompt in `cleanup-prompt.json` /
///   `edit-prompt.json` ({"instructions", "template"}; the template's `{text}` and `{instruction}` are filled in),
///   for trying prompts without changing the app's.
///
/// `background` waits until the app is in the background first. Results go to
/// `Documents/bench-out-<model>-<foreground or background>.jsonl` (cleanup), `asr-out-<model>.jsonl`,
/// `edit-out-<model>.jsonl`. The model settings are put back as they were afterwards.
@MainActor
enum CleanupBench {
    static func runIfRequested() {
        let args = ProcessInfo.processInfo.arguments
        // `-downloadModel s1mini|parakeet`: delete the model, download it from Hugging Face as a fresh install would, load it.
        if let i = args.firstIndex(of: "-downloadModel") {
            setvbuf(stdout, nil, _IONBF, 0)
            let slot = args.dropFirst(i + 1).first == "parakeet" ? NeuralEngine.transcriber : NeuralEngine.cleaner
            Task {
                slot.deleteModel()
                let start = Date.now
                slot.startDownload()
                var shown = -1
                while true {
                    switch slot.download {
                    case .running(let f) where Int(f * 10) > shown:
                        shown = Int(f * 10)
                        print("bench: download \(shown * 10)% after \(Int(Date.now.timeIntervalSince(start))) s")
                    case .failed(let error): return print("bench: download failed: \(error)")
                    case .none where slot.isInstalled:
                        print("bench: downloaded in \(Int(Date.now.timeIntervalSince(start))) s")
                        let load = Date.now
                        await ready(slot)
                        return print("bench: \(slot.state) after \(Int(Date.now.timeIntervalSince(load) * 1000)) ms; bench: done")
                    default: break
                    }
                    try? await Task.sleep(for: .milliseconds(200))
                }
            }
            return
        }
        for (flag, key) in [("-cleanupBench", CleanupModel.key), ("-asrBench", TranscriberModel.key), ("-editBench", "editBench")] {
            guard let i = args.firstIndex(of: flag) else { continue }
            let rest = args.dropFirst(i + 1)
            let model = rest.first ?? ""
            let background = rest.contains("background")
            setvbuf(stdout, nil, _IONBF, 0) // print straight to the devicectl console
            // Only the model under test: the other settings are Apple's for the run, so no other experimental model
            // loads next to it (two big ones together can exceed the app's memory limit).
            let keys = [CleanupModel.key, TranscriberModel.key]
            let previous = keys.map { UserDefaults.standard.string(forKey: $0) }
            for other in keys { UserDefaults.standard.set(other == key ? model : "apple", forKey: other) }
            Task {
                defer { for (k, v) in zip(keys, previous) { UserDefaults.standard.set(v, forKey: k) } } // leave Home's choices as they were
                if let slot = slot(flag, model) {
                    let start = Date.now
                    await ready(slot)
                    print("bench: \(model) \(slot.state) after \(Int(Date.now.timeIntervalSince(start) * 1000)) ms")
                    benchSlot = slot
                }
                if background {
                    print("bench: waiting for background")
                    for await _ in NotificationCenter.default.notifications(named: UIApplication.didEnterBackgroundNotification) { break }
                }
                let task = UIApplication.shared.beginBackgroundTask(withName: "bench")
                defer { UIApplication.shared.endBackgroundTask(task) }
                switch flag {
                case "-cleanupBench": await cleanup(model, label: background ? "background" : "foreground")
                case "-asrBench": await asr(model, realtime: rest.contains("realtime"))
                default: await edit(model)
                }
                print("bench: done")
            }
            return
        }
    }

    /// The model under test; each case waits for it, so a reload (after a memory warning) can't let Apple's model
    /// answer instead. Cases it still didn't do are marked with the model that did.
    private static var benchSlot: NeuralSlot?

    private static func ready(_ slot: NeuralSlot?) async {
        guard let slot else { return }
        slot.load()
        while slot.state == .loading || slot.state == .idle {
            if slot.state == .idle { slot.load() }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    /// A model folder under test as the editor (`-editBench neural:<folder>`).
    private static var editorSlot: NeuralSlot?

    private static func slot(_ flag: String, _ model: String) -> NeuralSlot? {
        if flag == "-editBench", model.hasPrefix("neural:") {
            editorSlot = NeuralSlot(folder: String(model.dropFirst("neural:".count)), className: "WipprNeuralLanguageModel")
            return editorSlot
        }
        return switch (flag, model) {
        case ("-cleanupBench", "s1mini"): NeuralEngine.cleaner
        case ("-asrBench", "parakeet"): NeuralEngine.transcriber
        default: nil
        }
    }

    private static let docs = URL.documentsDirectory

    /// Appends one JSON line per result, saving as it goes in case the run stalls.
    private static func writer(_ name: String) -> ([String: Any]) -> Void {
        let url = docs.appending(path: name)
        var lines = ""
        return { row in
            lines += String(decoding: try! JSONSerialization.data(withJSONObject: row), as: UTF8.self) + "\n"
            try? lines.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private static func cleanup(_ model: String, label: String) async {
        guard let data = try? Data(contentsOf: docs.appending(path: "bench-in.json")),
              let cases = try? JSONDecoder().decode([String: String].self, from: data)
        else { return print("bench: no bench-in.json") }
        print("bench: \(cases.count) cases, cleanup \(model), \(label)")
        let custom = model == "applecustom" ? prompt("cleanup-prompt.json") : nil
        if model == "applecustom", custom == nil { return print("bench: no cleanup-prompt.json") }
        let write = writer("bench-out-\(model)-\(label).jsonl")
        for id in cases.keys.sorted() {
            await ready(benchSlot)
            if let custom {
                let start = Date.now
                let text = await respond(custom, ["text": cases[id]!]) ?? cases[id]!
                let ms = Int(Date.now.timeIntervalSince(start) * 1000)
                write(["id": id, "output": text, "ms": ms, "model": model, "mode": label])
                print("bench: \(id) \(ms) ms by \(model)")
                continue
            }
            // A new Cleaner (and session) per case, as the app makes one per dictation.
            let text = await Cleaner().clean(cases[id]!)
            let (by, ms) = CleanupModel.last ?? (.apple, 0)
            write(["id": id, "output": text, "ms": ms, "model": by.rawValue, "mode": label])
            print("bench: \(id) \(ms) ms by \(by.rawValue)")
        }
    }

    /// Feeds each clip to the transcriber in 100 ms buffers, as fast as it takes them (or, with `realtime`, at the
    /// pace of speech, like the mic), then times `stop()` (what the user waits for after letting go) and the whole run.
    private static func asr(_ model: String, realtime: Bool) async {
        let dir = docs.appending(path: "asr")
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter({ $0.pathExtension == "wav" }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }), !files.isEmpty
        else { return print("bench: no asr/*.wav") }
        print("bench: \(files.count) clips, transcriber \(model)")
        let write = writer("asr-out-\(model)\(realtime ? "-realtime" : "").jsonl")
        for url in files {
            let id = url.deletingPathExtension().lastPathComponent
            await ready(benchSlot)
            do {
                let file = try AVAudioFile(forReading: url)
                let format = file.processingFormat
                let transcriber: any SpeechInput
                if model == "parakeet", let parakeet = ParakeetTranscriber() { transcriber = parakeet } else { transcriber = try await Transcriber() }
                let start = Date.now
                let sink = try await transcriber.start(micFormat: format)
                let frames = AVAudioFrameCount(format.sampleRate / 10)
                while file.framePosition < file.length {
                    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { break }
                    try file.read(into: buffer, frameCount: frames)
                    sink(buffer)
                    if realtime { try? await Task.sleep(for: .milliseconds(100)) }
                }
                let fed = Date.now
                let text = try await transcriber.stop()
                let end = Date.now
                let stopMs = Int(end.timeIntervalSince(fed) * 1000), totalMs = Int(end.timeIntervalSince(start) * 1000)
                let audioMs = Int(Double(file.length) / format.sampleRate * 1000)
                let by = transcriber is ParakeetTranscriber ? "parakeet" : "apple"
                write(["id": id, "text": text, "stop_ms": stopMs, "total_ms": totalMs, "audio_ms": audioMs, "model": by])
                print("bench: \(id) stop \(stopMs) ms, total \(totalMs) ms for \(audioMs) ms audio by \(by)")
            } catch {
                write(["id": id, "error": "\(error)"])
                print("bench: \(id) error \(error)")
            }
        }
    }

    private struct EditCase: Decodable {
        var id: String
        var text: String
        var instruction: String
    }

    private static func edit(_ model: String) async {
        guard let data = try? Data(contentsOf: docs.appending(path: "edit-in.json")),
              let cases = try? JSONDecoder().decode([EditCase].self, from: data)
        else { return print("bench: no edit-in.json") }
        let custom = model == "applecustom" ? prompt("edit-prompt.json") : nil
        if model == "applecustom", custom == nil { return print("bench: no edit-prompt.json") }
        print("bench: \(cases.count) edit cases, \(model)")
        let write = writer("edit-out-\(model.replacingOccurrences(of: ":", with: "-")).jsonl")
        let neuralPrompt = prompt("neural-edit-prompt.json")
            ?? Prompt(instructions: Editor.instructions, template: "<text>\n{text}\n</text>\n<instruction>\n{instruction}\n</instruction>")
        for c in cases {
            await ready(benchSlot)
            let start = Date.now
            let text = String(c.text.suffix(Editor.maxText))
            let output = if let slot = editorSlot {
                await neural(slot, neuralPrompt, ["text": text, "instruction": c.instruction],
                             maxTokens: min(2048, text.utf8.count / 2 + 512))
            } else if let custom {
                await respond(custom, ["text": String(c.text.suffix(Editor.maxText)), "instruction": c.instruction])
            } else {
                await Editor.edit(c.text, instruction: c.instruction)
            }
            let ms = Int(Date.now.timeIntervalSince(start) * 1000)
            write(["id": c.id, "output": output ?? NSNull(), "ms": ms, "model": model])
            print("bench: \(c.id) \(ms) ms by \(model)")
        }
    }

    /// A prompt to try: the session's instructions, and the user message with `{name}` placeholders.
    private struct Prompt: Decodable {
        var instructions: String
        var template: String
    }

    private static func prompt(_ file: String) -> Prompt? {
        (try? Data(contentsOf: docs.appending(path: file))).flatMap { try? JSONDecoder().decode(Prompt.self, from: $0) }
    }

    /// A Core AI model under test, greedy, in a new session; nil on failure.
    private static func neural(_ slot: NeuralSlot, _ prompt: Prompt, _ values: [String: String], maxTokens: Int) async -> String? {
        guard let model = slot.ready as? NeuralLanguageModel else { return nil }
        var message = prompt.template
        for (name, value) in values { message = message.replacingOccurrences(of: "{\(name)}", with: value) }
        return await withCheckedContinuation { done in
            model.respond(to: message, instructions: prompt.instructions, maxTokens: maxTokens, bundle: slot.bundleURL) {
                done.resume(returning: $0)
            }
        }
    }

    /// Apple's model, greedy, in a new session, like `Cleaner` and `Editor`; nil on failure or an empty reply.
    private static func respond(_ prompt: Prompt, _ values: [String: String]) async -> String? {
        var message = prompt.template
        for (name, value) in values { message = message.replacingOccurrences(of: "{\(name)}", with: value) }
        let session = LanguageModelSession(instructions: prompt.instructions)
        do {
            let response = try await session.respond(to: message, options: GenerationOptions(samplingMode: .greedy))
            let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        } catch {
            print("bench: respond failed: \(error)")
            return nil
        }
    }
}
#endif
