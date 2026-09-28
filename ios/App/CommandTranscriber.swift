import AVFoundation
import Observation
import os
import UIKit
import whisper

/// Command mode's recognizer: whisper.cpp small.en, primed with `ShellVocabulary.whisperPrompt`, hears commands far
/// better than Apple's. An optional download; without it command mode uses Apple's transcript.
/// CPU only: in the background iOS blocks the GPU (Metal) and the Neural Engine.
final class CommandTranscriber: @unchecked Sendable {
    static let shared = CommandTranscriber()

    static let modelName = "ggml-small.en-q8_0.bin"
    /// Pinned to a revision of the official whisper.cpp model repo (MIT), so the file can't change under the app.
    static let modelURL = URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/5359861c739e955e79d9a303bcbc70fb988958b1/\(modelName)")!
    static var modelFile: URL { .applicationSupportDirectory.appending(path: modelName) }
    static var isDownloaded: Bool { FileManager.default.fileExists(atPath: modelFile.path) }

    /// Whisper's input: 16 kHz mono.
    static let sampleRate = 16_000.0

    /// Owns `context`: loading, transcribing and freeing all run here, one at a time.
    private let queue = DispatchQueue(label: "cx.immortal.wippr.whisper", qos: .userInitiated)
    private var context: OpaquePointer?
    private let log = Logger(subsystem: "cx.immortal.wippr", category: "whisper")

    /// Loaded, the model and its buffers take ~650 MB. With 4 GB (iPad 10th gen) that plus an experimental model got
    /// the app killed, and the mic with it, so there it loads for each dictation (~0.6 s) and is freed after.
    private static let staysLoaded = ProcessInfo.processInfo.physicalMemory > 5 << 30

    private init() {
        // Give the memory back when iOS asks. The next command reloads it.
        NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: nil) { [self] _ in
            queue.async { [self] in free("on memory warning") }
        }
    }

    /// Loads the model now, off the main thread, so the first command doesn't wait for it (25 s on an iPad 10th gen
    /// the first time). Not where it doesn't stay loaded.
    func preload() {
        guard Self.isDownloaded, Self.staysLoaded, TerminalTranscriber.current == .whisper else { return }
        queue.async { _ = self.loadedContext() }
    }

    /// Frees the model when terminals stop using it (Terminal transcriber → Off).
    func unload() { queue.async { self.free("when turned off") } }

    /// On `queue` only.
    private func free(_ reason: StaticString) {
        guard let context else { return }
        whisper_free(context)
        self.context = nil
        log.notice("freed \(reason)")
    }

    /// Downloads the model into Application Support (not backed up). `progress` gets 0…1 on the main thread.
    static func download(progress: @escaping @MainActor (Double) -> Void) async throws {
        let file = modelFile
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        var observation: NSKeyValueObservation?
        defer { observation?.invalidate() }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let task = URLSession.shared.downloadTask(with: modelURL) { temp, response, error in
                continuation.resume(with: Result {
                    if let error { throw error }
                    guard let temp, (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                    // A move on the same volume is atomic, so a partial model never sits at `file`.
                    try FileManager.default.moveItem(at: temp, to: file)
                    var values = URLResourceValues()
                    values.isExcludedFromBackup = true
                    var file = file
                    try file.setResourceValues(values)
                })
            }
            observation = task.progress.observe(\.fractionCompleted) { task, _ in
                let fraction = task.fractionCompleted
                DispatchQueue.main.async { progress(fraction) }
            }
            task.resume()
        }
    }

    /// Transcribes 16 kHz mono `samples` off the main thread. Nil if the model is missing or nothing was heard.
    func transcribe(_ samples: [Float]) async -> String? {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.run(samples))
                if !Self.staysLoaded { self.free("after use") }
            }
        }
    }

    private func run(_ samples: [Float]) -> String? {
        // Whisper makes up words ("Thank you.") on silence, so skip audio that never gets louder than room noise.
        guard Self.hasSpeech(samples), let context = loadedContext() else { return nil }
        let start = ContinuousClock.now
        let seconds = Double(samples.count) / Self.sampleRate
        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.n_threads = 4
        // The encoder's window, 50 per second of audio (1500 = 30 s). Encoding only the clip plus a margin is ~3× faster.
        // Below ~10 s (512) Whisper returns lone letters ("p", "s"); 512 is also what bench/command measured.
        params.audio_ctx = Int32(min(max(Int(seconds * 50) + 64, 512), 1500))
        params.no_timestamps = true
        params.single_segment = true
        params.suppress_blank = true
        params.suppress_nst = true
        // Whisper can get stuck repeating a word ("mic mic mic…"). Commands are short, so stop early; its temperature
        // fallback (on by default) re-decodes such loops.
        params.max_tokens = 48
        params.print_progress = false
        params.print_realtime = false
        params.print_timestamps = false
        let status = "en".withCString { language in
            ShellVocabulary.whisperPrompt.withCString { prompt in
                params.language = language
                params.initial_prompt = prompt
                return whisper_full(context, params, samples, Int32(samples.count))
            }
        }
        guard status == 0 else {
            log.error("whisper_full failed: \(status)")
            return nil
        }
        let text = Self.collapseRepeats((0..<whisper_full_n_segments(context))
            .compactMap { whisper_full_get_segment_text(context, $0).map { String(cString: $0) } }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines))
        log.notice("\(seconds, format: .fixed(precision: 1)) s audio, ctx \(params.audio_ctx): \((ContinuousClock.now - start) / .milliseconds(1), format: .fixed(precision: 0)) ms")
        // A lone letter is Whisper failing, not a command (it heard "exit" as "s").
        return text.filter(\.isLetter).count <= 1 ? nil : text
    }

    /// True if some 20 ms of `samples` is louder than -40 dBFS (quiet speech; a quiet room is around -60).
    static func hasSpeech(_ samples: [Float]) -> Bool {
        let window = Int(sampleRate / 50)
        return stride(from: 0, to: samples.count - window + 1, by: window).contains { start in
            let power = samples[start..<start + window].reduce(0) { $0 + $1 * $1 } / Float(window)
            return 10 * log10(max(power, 1e-10)) > -40
        }
    }

    /// Keeps one of a word or phrase (up to 4 words) repeated 3+ times in a row: "mic mic mic mic" → "mic".
    static func collapseRepeats(_ text: String) -> String {
        var words = text.split(separator: " ").map(String.init)
        for size in 1...4 {
            var i = 0
            while i + size * 3 <= words.count {
                let phrase = words[i..<i + size]
                var end = i + size
                while end + size <= words.count, words[end..<end + size] == phrase { end += size }
                if (end - i) / size >= 3 { words.removeSubrange(i + size..<end) }
                i += 1
            }
        }
        return words.joined(separator: " ")
    }

    /// Loads the model the first time (and after a memory warning). On `queue` only.
    private func loadedContext() -> OpaquePointer? {
        if let context { return context }
        guard Self.isDownloaded else { return nil }
        let start = ContinuousClock.now
        var params = whisper_context_default_params()
        params.use_gpu = false
        context = whisper_init_from_file_with_params(Self.modelFile.path, params)
        if context == nil { log.error("could not load \(Self.modelName, privacy: .public)") }
        else { log.notice("loaded in \((ContinuousClock.now - start) / .milliseconds(1), format: .fixed(precision: 0)) ms") }
        return context
    }
}

/// Whisper's download for Home's Terminal transcriber menu (`DownloadableModel`).
@MainActor @Observable
final class WhisperModel: DownloadableModel {
    static let shared = WhisperModel()

    private(set) var isInstalled = CommandTranscriber.isDownloaded
    private(set) var downloadProgress: Double?
    private(set) var downloadError: String?
    let downloadSize: Int64 = 264_477_561

    func startDownload() {
        guard !isInstalled, downloadProgress == nil else { return }
        downloadError = nil
        downloadProgress = 0
        Task {
            do {
                // A progress update can arrive after the download ended; only a running one shows.
                try await CommandTranscriber.download { if self.downloadProgress != nil { self.downloadProgress = $0 } }
                isInstalled = true
                CommandTranscriber.shared.preload()
            } catch {
                downloadError = error.localizedDescription
            }
            downloadProgress = nil
        }
    }
}

/// Collects a dictation's audio as whisper's 16 kHz mono samples, up to 30 s (whisper's window).
/// `append` runs on the mic's audio thread.
final class CommandAudio: @unchecked Sendable {
    private let maxSamples = Int(CommandTranscriber.sampleRate * 30)
    private let converter: AVAudioConverter?
    private let collected = OSAllocatedUnfairLock<[Float]>(initialState: [])

    init(micFormat: AVAudioFormat) {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: CommandTranscriber.sampleRate, channels: 1, interleaved: false)!
        converter = AVAudioConverter(from: micFormat, to: format)
    }

    var samples: [Float] { collected.withLockUnchecked { $0 } }

    func append(_ buffer: AVAudioPCMBuffer) {
        guard let converter, let converted = Transcriber.convert(buffer, with: converter),
              let channel = converted.floatChannelData?[0] else { return }
        let new = UnsafeBufferPointer(start: channel, count: Int(converted.frameLength))
        collected.withLockUnchecked { samples in
            samples.append(contentsOf: new.prefix(maxSamples - samples.count))
        }
    }
}
