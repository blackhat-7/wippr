import AVFoundation
import Foundation
import Speech

setvbuf(stdout, nil, _IOLBF, 0) // line by line, so a log file shows progress

// Command-mode benchmark: macOS voices say each case, Apple's SpeechTranscriber (as the app configures it) hears it,
// and CommandWriter (compiled from ios/App) writes the command. Scores exact matches against `expect`.
// Run with ./run.sh; needs Apple Intelligence on. No GPU: everything is Apple's on-device stack.

struct Case: Decodable {
    var id: Int
    var say: String
    var expect: [String]
}

struct Row: Encodable {
    var id: Int, voice: String, say: String, heard: [String], raw: Bool, symbols: Bool, command: String, ok: Bool, alternativesOK: Bool, seconds: Double
}

let here = URL(fileURLWithPath: CommandLine.arguments[1])
let audioDir = here.appendingPathComponent("audio")
try FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)
// --cases=cases.local.jsonl for a private set (e.g. from your own shell history; gitignored).
let cases = try String(contentsOf: here.appendingPathComponent(CommandLine.arguments.first { $0.hasPrefix("--cases=") }.map { String($0.dropFirst(8)) } ?? "cases.jsonl"), encoding: .utf8)
    .split(separator: "\n").map { try JSONDecoder().decode(Case.self, from: Data($0.utf8)) }
// Arguments after the directory: case ids and/or voice names to run only those, and options:
// --asr=speech|dictation|legacy|whisper-small|whisper-turbo (default speech, what the app uses) and, for Whisper,
// --prompt=names (just command names) or --prompt (ShellVocabulary.whisperPrompt).
// Apple's custom language models (SFCustomLanguageModelData) were tried and dropped: learnings/bench-command.md.
let options = Dictionary(CommandLine.arguments.filter { $0.hasPrefix("--") }.map {
    let parts = $0.dropFirst(2).split(separator: "=", maxSplits: 1)
    return (String(parts[0]), parts.count > 1 ? String(parts[1]) : "")
}, uniquingKeysWith: { $1 })
let arguments = CommandLine.arguments.dropFirst(2).filter { !$0.hasPrefix("--") }
let asr = options["asr"] ?? "speech"
let only = arguments.compactMap(Int.init)
// --locale=en-US hears every voice with that locale instead of the voice's own (Apple recognizers only).
let voices = [("Samantha", "en-US"), ("Reed", "en-US"), ("Aman", "en-IN"), ("Tara", "en-IN")]
    .filter { voice in !arguments.contains { Int($0) == nil } || arguments.contains(voice.0) }
    .map { ($0.0, options["locale"] ?? $0.1) }

func audio(_ c: Case, voice: String) throws -> URL {
    let url = audioDir.appendingPathComponent("\(voice)-\(c.id).aiff")
    if !FileManager.default.fileExists(atPath: url.path) {
        let say = Process()
        say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        say.arguments = ["-v", voice, "-o", url.path, c.say]
        try say.run()
        say.waitUntilExit()
    }
    return url
}

func hear(_ url: URL, locale: Locale) async throws -> [String] {
    switch asr {
    case "parakeet": // transcribed beforehand by parakeet.py (Parakeet TDT 0.6B v2 on MLX)
        return [try String(contentsOf: here.appendingPathComponent(".build/heard/parakeet/\(url.deletingPathExtension().lastPathComponent).txt"), encoding: .utf8)]
    case "speech": return try await speech(url, locale: locale)
    case "dictation": return try await dictation(url, locale: locale)
    case "legacy": return [try await legacy(url, locale: locale)]
    case "whisper-small": return [try whisper(url, model: "ggml-small.en.bin")]
    case "whisper-small-q5": return [try whisper(url, model: "ggml-small.en-q5_1.bin")]
    case "whisper-small-q8": return [try whisper(url, model: "ggml-small.en-q8_0.bin")]
    case "whisper-turbo": return [try whisper(url, model: "ggml-large-v3-turbo-q5_0.bin")]
    default: fatalError("unknown --asr \(asr)")
    }
}

/// The best transcript, then up to 4 alternatives: Transcriber.swift's module plus alternatives.
func speech(_ url: URL, locale: Locale) async throws -> [String] {
    let module = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [.alternativeTranscriptions], attributeOptions: [])
    if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) { try await request.downloadAndInstall() }
    let results = Task {
        var best = "", alternatives: [String] = []
        for try await result in module.results where result.isFinal {
            best += String(result.text.characters)
            alternatives = result.alternatives.map { String($0.characters) }
        }
        return [best.trimmingCharacters(in: .whitespaces)] + alternatives.prefix(4).map { $0.trimmingCharacters(in: .whitespaces) }
    }
    _ = try await SpeechAnalyzer(inputAudioFile: AVAudioFile(forReading: url), modules: [module], finishAfterFile: true)
    return try await results.value
}

func dictation(_ url: URL, locale: Locale) async throws -> [String] {
    let module = DictationTranscriber(locale: locale, contentHints: [.shortForm], transcriptionOptions: [], reportingOptions: [.alternativeTranscriptions], attributeOptions: [])
    if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) { try await request.downloadAndInstall() }
    let results = Task {
        var best = "", alternatives: [String] = []
        for try await result in module.results where result.isFinal {
            alternatives = result.alternatives.map { best + String($0.characters) }
            best += String(result.text.characters)
        }
        return [best.trimmingCharacters(in: .whitespaces)] + alternatives.prefix(4).map { $0.trimmingCharacters(in: .whitespaces) }
    }
    _ = try await SpeechAnalyzer(inputAudioFile: AVAudioFile(forReading: url), modules: [module], finishAfterFile: true)
    return try await results.value
}

/// SFSpeechRecognizer, on device.
func legacy(_ url: URL, locale: Locale) async throws -> String {
    let recognizer = SFSpeechRecognizer(locale: locale)!
    let request = SFSpeechURLRecognitionRequest(url: url)
    request.requiresOnDeviceRecognition = true
    request.addsPunctuation = false
    return try await withCheckedThrowingContinuation { continuation in
        var done = false
        recognizer.recognitionTask(with: request) { result, error in
            guard !done else { return }
            if let error { done = true; continuation.resume(throwing: error) }
            else if let result, result.isFinal { done = true; continuation.resume(returning: result.bestTranscription.formattedString) }
        }
    }
}

/// whisper.cpp (brew install whisper-cpp; models in ~/.cache/whisper), optionally primed with command names.
func whisper(_ url: URL, model: String) throws -> String {
    let wav = url.deletingPathExtension().appendingPathExtension("wav")
    if !FileManager.default.fileExists(atPath: wav.path) {
        try run("/usr/bin/afconvert", ["-f", "WAVE", "-d", "LEI16@16000", url.path, wav.path])
    }
    var arguments = ["-m", NSString(string: "~/.cache/whisper/\(model)").expandingTildeInPath, "-f", wav.path, "-l", "en", "-nt", "-np"]
    // --ac=512: a ~10 s audio window instead of 30 s, ~3× faster on CPU (what the app would use).
    if let ac = options["ac"] { arguments += ["-ac", ac] }
    switch options["prompt"] {
    case "names": arguments += ["--prompt", "Shell commands: " + ShellVocabulary.commands.prefix(80).joined(separator: ", ") + "."]
    case .some: arguments += ["--prompt", ShellVocabulary.whisperPrompt]
    case nil: break
    }
    return try run("/opt/homebrew/bin/whisper-cli", arguments).trimmingCharacters(in: .whitespacesAndNewlines)
}

@discardableResult
func run(_ tool: String, _ arguments: [String]) throws -> String {
    let process = Process(), out = Pipe()
    process.executableURL = URL(fileURLWithPath: tool)
    process.arguments = arguments
    process.standardOutput = out
    process.standardError = FileHandle.nullDevice
    try process.run()
    let data = out.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return String(decoding: data, as: UTF8.self)
}

/// What the transcript alone would type: lowercased, without the final full stop.
func rawCommand(_ heard: String) -> String {
    var text = heard.lowercased()
    while let last = text.last, ".!?".contains(last) { text.removeLast() }
    return text
}

var rows: [Row] = []
for (voice, locale) in voices {
    for c in cases where only.isEmpty || only.contains(c.id) {
        let url = try audio(c, voice: voice)
        // Transcripts are cached per recognizer setup, so a CommandWriter change re-scores in seconds.
        let cache = here.appendingPathComponent(".build/heard/\(asr)-\(options["prompt"] ?? "none")\(options["ac"].map { "-ac\($0)" } ?? "")\(options["locale"].map { "-\($0)" } ?? "")-\(ShellVocabulary.whisperPrompt.utf8.reduce(0) { ($0 &* 31) &+ Int($1) } & 0xFFFF)-\(url.deletingPathExtension().lastPathComponent).json")
        // A recognizer error ("no speech") or hang counts as hearing nothing.
        let heard: [String] = await withCheckedContinuation { continuation in
            var done = false
            func finish(_ heard: [String]) { if !done { done = true; continuation.resume(returning: heard) } }
            if let data = try? Data(contentsOf: cache), let heard = try? JSONDecoder().decode([String].self, from: data) { return finish(heard) }
            Task {
                let heard = (try? await hear(url, locale: Locale(identifier: locale))) ?? [""]
                try? FileManager.default.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? JSONEncoder().encode(heard).write(to: cache)
                finish(heard)
            }
            Task { try? await Task.sleep(for: .seconds(20)); finish([""]) }
        }
        let start = Date()
        let command = await CommandWriter.write(heard: [heard[0]]) ?? "<prose>" // prose is typed as normal dictation
        let seconds = Date().timeIntervalSince(start)
        let withAlternatives = heard.count > 1 ? await CommandWriter.write(heard: heard) ?? "<prose>" : command
        let row = Row(id: c.id, voice: voice, say: c.say, heard: heard, raw: c.expect.contains(rawCommand(heard[0])),
                      symbols: c.expect.contains(SpokenSymbols.apply(heard[0])), command: command, ok: c.expect.contains(command),
                      alternativesOK: c.expect.contains(withAlternatives), seconds: seconds)
        rows.append(row)
        let mark = row.ok ? "✓" : "✗"
        print("\(mark) [\(voice)] \(c.say)\n    heard: \(heard[0])\n    wrote: \(command)   expect: \(c.expect[0])")
    }
}

func percent(_ f: (Row) -> Bool) -> String { String(format: "%3.0f%%", 100 * Double(rows.filter(f).count) / Double(max(rows.count, 1))) }
print("\n== \(rows.count) runs ==")
print("transcript alone     \(percent(\.raw))")
print("+ spoken symbols     \(percent(\.symbols))")
print("CommandWriter        \(percent(\.ok))")
print("  + alternatives     \(percent(\.alternativesOK))")
for (voice, _) in voices {
    let mine = rows.filter { $0.voice == voice }
    guard !mine.isEmpty else { continue }
    print("  \(voice.padding(toLength: 9, withPad: " ", startingAt: 0)) \(mine.filter(\.ok).count)/\(mine.count)")
}
let sorted = rows.map(\.seconds).sorted()
print(String(format: "CommandWriter latency  median %.2f s, p90 %.2f s", sorted[sorted.count / 2], sorted[Int(Double(sorted.count) * 0.9)]))

let out = here.appendingPathComponent("results/\(ISO8601DateFormatter().string(from: .now))-\(asr)\(options["prompt"].map { "-prompt\($0)" } ?? "")-\(voices.map(\.0).joined(separator: "+")).json")
try FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
try encoder.encode(rows).write(to: out)
print("results: \(out.path)")
