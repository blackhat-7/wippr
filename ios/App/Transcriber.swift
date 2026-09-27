import AVFoundation
import Speech

/// Streams microphone audio into Apple's on-device `SpeechTranscriber` (iOS 26).
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

    private let engine = AVAudioEngine()
    private let module: SpeechTranscriber
    private let analyzer: SpeechAnalyzer
    private let onText: @Sendable (String) -> Void
    private var input: AsyncStream<AnalyzerInput>.Continuation?
    private var results: Task<String, Error>?

    /// `onText` receives the whole transcript so far, including not-yet-final words.
    init(onText: @escaping @Sendable (String) -> Void) async throws {
        module = try await Self.makeModule()
        analyzer = SpeechAnalyzer(modules: [module])
        self.onText = onText
    }

    /// Downloads the speech model for the current language if needed. Run in the foreground.
    static func installAssets() async throws {
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [try await makeModule()]) {
            try await request.downloadAndInstall()
        }
    }

    func start() async throws {
        try await Self.installAssets()
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module]) else {
            throw Failure.noAudioFormat
        }

        let module = module, onText = onText
        results = Task {
            var final = ""
            for try await result in module.results {
                let text = String(result.text.characters)
                if result.isFinal { final += text }
                onText(result.isFinal ? final : final + text)
            }
            return final.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let (stream, input) = AsyncStream.makeStream(of: AnalyzerInput.self)
        self.input = input
        try await analyzer.start(inputSequence: stream)

        let mic = engine.inputNode
        let micFormat = mic.outputFormat(forBus: 0)
        guard let converter = AVAudioConverter(from: micFormat, to: format) else { throw Failure.noAudioFormat }
        mic.installTap(onBus: 0, bufferSize: 4096, format: micFormat) { buffer, _ in
            if let converted = Self.convert(buffer, with: converter) {
                input.yield(AnalyzerInput(buffer: converted))
            }
        }
        engine.prepare()
        try engine.start()
    }

    /// Stops the mic, waits for the model to finalize, and returns the full transcript.
    func stop() async throws -> String {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        input?.finish()
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        return try await results?.value ?? ""
    }

    private static func makeModule() async throws -> SpeechTranscriber {
        guard SpeechTranscriber.isAvailable else { throw Failure.unsupportedDevice }
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: .current) else {
            throw Failure.unsupportedLocale
        }
        return SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [.volatileResults], attributeOptions: [])
    }

    private static func convert(_ buffer: AVAudioPCMBuffer, with converter: AVAudioConverter) -> AVAudioPCMBuffer? {
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
