import AVFoundation
import Speech

/// Transcribes one dictation with Apple's on-device `SpeechTranscriber` (iOS 26).
/// The model is system-managed, so wippr ships no ASR weights.
final class Transcriber {
    enum Failure: LocalizedError {
        case unsupportedDevice, unsupportedLocale, noAudioFormat

        var errorDescription: String? {
            switch self {
            case .unsupportedDevice: "This iPhone does not support on-device transcription."
            case .unsupportedLocale: "On-device transcription does not support this device's language."
            case .noAudioFormat: "No audio format is compatible with the speech model."
            }
        }
    }

    private let module: SpeechTranscriber
    private let analyzer: SpeechAnalyzer
    private var input: AsyncStream<AnalyzerInput>.Continuation?
    private var results: Task<String, Error>?
    /// Voice mode: gets each phrase as the model finishes it, with where it is in the audio (seconds from the first
    /// buffer); `stop()` then returns nothing.
    private let onPhrase: (@MainActor (String, ClosedRange<TimeInterval>) -> Void)?

    /// With `onPhrase`, the model reports fast: it finishes each phrase at a pause (even a 1 s one) instead of when it
    /// sees fit, which can be after the next sentence.
    init(onPhrase: (@MainActor (String, ClosedRange<TimeInterval>) -> Void)? = nil) async throws {
        module = try await Self.makeModule(fast: onPhrase != nil)
        analyzer = SpeechAnalyzer(modules: [module])
        self.onPhrase = onPhrase
    }

    /// Downloads the speech model for the current language if needed. Run in the foreground.
    static func installAssets() async throws {
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [try await makeModule()]) {
            try await request.downloadAndInstall()
        }
    }

    /// Starts transcribing. Feed microphone buffers (in `micFormat`) to the returned closure.
    func start(micFormat: AVAudioFormat) async throws -> Mic.Sink {
        try await Self.installAssets()
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module]),
              let converter = AVAudioConverter(from: micFormat, to: format)
        else { throw Failure.noAudioFormat }

        let module = module, onPhrase = onPhrase
        results = Task {
            var final = ""
            for try await result in module.results where result.isFinal {
                let text = String(result.text.characters)
                if let onPhrase {
                    let phrase = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    // The words' times: the result's own range also covers the silence before them.
                    let words = result.text.runs.compactMap(\.audioTimeRange)
                    let start = (words.first ?? result.range).start.seconds, end = (words.last ?? result.range).end.seconds
                    if !phrase.isEmpty { await onPhrase(phrase, start...max(start, end)) }
                } else {
                    final += text
                }
            }
            return final.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let (stream, input) = AsyncStream.makeStream(of: AnalyzerInput.self)
        self.input = input
        try await analyzer.start(inputSequence: stream)
        return { buffer in
            if let converted = Self.convert(buffer, with: converter) {
                input.yield(AnalyzerInput(buffer: converted))
            }
        }
    }

    /// Waits for the model to finalize and returns the full transcript. Stop feeding buffers first.
    func stop() async throws -> String {
        input?.finish()
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        return try await results?.value ?? ""
    }

    private static func makeModule(fast: Bool = false) async throws -> SpeechTranscriber {
        guard SpeechTranscriber.isAvailable else { throw Failure.unsupportedDevice }
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: .current) else {
            throw Failure.unsupportedLocale
        }
        return SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: fast ? [.fastResults] : [],
                                 attributeOptions: fast ? [.audioTimeRange] : [])
    }

    static func convert(_ buffer: AVAudioPCMBuffer, with converter: AVAudioConverter) -> AVAudioPCMBuffer? {
        let format = converter.outputFormat
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * format.sampleRate / buffer.format.sampleRate) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        var consumed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        return error == nil && output.frameLength > 0 ? output : nil
    }
}
