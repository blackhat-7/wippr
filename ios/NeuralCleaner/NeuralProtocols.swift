import Foundation

// The bridge between the app and `NeuralCleaner.framework`. Compiled into both.
// The framework needs iOS 27 (Core AI), the app supports iOS 26, so the app never links it:
// it loads the framework at runtime on iOS 27 and talks to it through these Objective-C protocols.
// Everything behind them is experimental, for testing; Apple's models stay the default.

@objc(WipprNeuralModel)
public protocol NeuralModel: NSObjectProtocol {
    /// Loads the model (compiles it for the Neural Engine the first time, which can take minutes).
    /// Calls back with nil once it's loaded, or the error.
    func prewarm(_ bundle: URL, completion: @escaping (String?) -> Void)
    /// Frees the model's memory; the next use reloads it.
    func unload()
}

/// A chat LLM (S1-mini for cleanup, Qwen3-1.7B for edit mode).
@objc(WipprNeuralLanguageModel)
public protocol NeuralLanguageModel: NeuralModel {
    /// Greedy reply to `prompt` under `instructions`, at most `maxTokens` long; nil on any failure.
    func respond(to prompt: String, instructions: String, maxTokens: Int, bundle: URL,
                 completion: @escaping (String?) -> Void)
}

/// Streaming speech recognition (Parakeet TDT).
@objc(WipprNeuralTranscribing)
public protocol NeuralTranscribing: NeuralModel {
    /// The sample rate `append` expects (mono Float32).
    var sampleRate: Double { get }
    /// Starts a stream; false if the model isn't loaded or a stream is already running.
    func start() -> Bool
    /// Mono Float32 samples at `sampleRate`. Cheap and safe from any thread, including the audio thread.
    func append(_ samples: Data)
    /// Ends the stream; calls back with the transcript, or nil on failure.
    func finish(completion: @escaping (String?) -> Void)
}
