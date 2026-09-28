import AVFoundation

/// What DictationController records into: Apple's `Transcriber` (the default) or, experimentally, Parakeet.
protocol SpeechInput: AnyObject {
    /// Starts transcribing. Feed microphone buffers (in `micFormat`) to the returned closure.
    func start(micFormat: AVAudioFormat) async throws -> Mic.Sink
    /// Waits for the transcript. Stop feeding buffers first.
    func stop() async throws -> String
}

extension Transcriber: SpeechInput {}

/// Experimental, for testing: Parakeet TDT on the Neural Engine (iOS 27), through `NeuralCleaner.framework`.
/// Mic audio is converted to 16 kHz mono and streamed to the model while the key is held.
final class ParakeetTranscriber: SpeechInput {
    enum Failure: LocalizedError {
        case busy, failed

        var errorDescription: String? {
            switch self {
            case .busy: "Parakeet couldn't start a transcription."
            case .failed: "Parakeet failed to transcribe."
            }
        }
    }

    private let model: NeuralTranscribing

    /// nil (and starts loading it) until Parakeet has loaded; the caller uses Apple's Transcriber meanwhile.
    @MainActor init?() {
        guard let model = NeuralEngine.transcriber.ready as? NeuralTranscribing else { return nil }
        self.model = model
    }

    func start(micFormat: AVAudioFormat) async throws -> Mic.Sink {
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: model.sampleRate, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: micFormat, to: format)
        else { throw Transcriber.Failure.noAudioFormat }
        guard model.start() else { throw Failure.busy }
        let model = model
        return { buffer in
            guard let converted = Transcriber.convert(buffer, with: converter), let samples = converted.floatChannelData else { return }
            model.append(Data(bytes: samples[0], count: Int(converted.frameLength) * MemoryLayout<Float>.size))
        }
    }

    func stop() async throws -> String {
        let text = await withCheckedContinuation { done in model.finish { done.resume(returning: $0) } }
        guard let text else { throw Failure.failed }
        return text
    }
}
