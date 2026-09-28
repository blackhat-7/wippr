import Foundation
import Observation

/// Experimental, for testing: models on the Neural Engine (iOS 27+), through the separately built
/// `NeuralCleaner.framework`. Each is only loaded when its Home → Experimental setting picks it; with the
/// defaults (Apple's models) the framework is never loaded.
enum NeuralEngine {
    /// S1-mini, 8-bit (cleanup).
    @MainActor static let cleaner = NeuralSlot(folder: "s1-mini-ios", className: "WipprNeuralLanguageModel")
    /// Qwen3-1.7B, 6-bit (edit mode).
    @MainActor static let editor = NeuralSlot(folder: "qwen3-1.7b-ios", className: "WipprNeuralLanguageModel")
    /// Parakeet TDT v2, streaming float16 (speech recognition).
    @MainActor static let transcriber = NeuralSlot(folder: "parakeet-ios", className: "WipprNeuralTranscriber")

    /// S1-mini's trained system prompt and control line; its model card says not to change them.
    static let s1System = "You are a text normalizer for speech-to-text transcripts. The input begins with a control line specifying the styling, structure, and context settings; clean the transcript to match those settings and output only the cleaned text."
    static let s1Control = "[Styling: semi-formal] [Structure: lists] [Context: general]\n"

    /// S1-mini's cleanup (after the list rules); nil until the model has loaded, or if it fails.
    @MainActor static func clean(_ raw: String) async -> String? {
        guard !raw.isEmpty, let model = cleaner.ready as? NeuralLanguageModel else { return nil }
        let text = Prepass.lists(raw)
        // About twice the input's tokens (~4 bytes each) + 64, so a repetition loop stops early.
        return await respond(model, to: s1Control + text, instructions: s1System,
                             maxTokens: min(1024, text.utf8.count / 2 + 64), bundle: cleaner.bundleURL)
    }

    /// Qwen3-1.7B edit, with the same instructions and prompt format as Apple's (`Editor`);
    /// nil until the model has loaded, or if it fails.
    @MainActor static func edit(_ text: String, instruction: String) async -> String? {
        guard !instruction.isEmpty, let model = editor.ready as? NeuralLanguageModel else { return nil }
        let text = String(text.suffix(Editor.maxText))
        // The same user message as Apple's path in `Editor.edit`.
        let prompt = "<text>\n\(text)\n</text>\n<instruction>\n\(instruction)\n</instruction>"
        return await respond(model, to: prompt, instructions: Editor.instructions,
                             maxTokens: min(2048, text.utf8.count / 2 + 512), bundle: editor.bundleURL)
    }

    private static func respond(_ model: NeuralLanguageModel, to prompt: String, instructions: String,
                                maxTokens: Int, bundle: URL) async -> String? {
        await withCheckedContinuation { done in
            model.respond(to: prompt, instructions: instructions, maxTokens: maxTokens, bundle: bundle) { done.resume(returning: $0) }
        }
    }

    /// Loads the framework once; nil below iOS 27 or if it won't load.
    @MainActor fileprivate static let framework: Bool = {
        guard #available(iOS 27, *),
              let url = Bundle.main.privateFrameworksURL?.appending(path: "NeuralCleaner.framework"),
              let bundle = Bundle(url: url)
        else { return false }
        return bundle.load()
    }()
}

/// One experimental model: where its files are, and its load state for the UI.
@MainActor @Observable
final class NeuralSlot {
    enum State: Equatable {
        case idle, loading, ready
        case failed(String)
    }

    /// Only `ready` models are used; until then Apple's model does the work.
    private(set) var state = State.idle
    let bundleURL: URL
    @ObservationIgnored private let className: String
    @ObservationIgnored private var object: NeuralModel?

    init(folder: String, className: String) {
        bundleURL = URL.applicationSupportDirectory.appending(path: folder)
        self.className = className
    }

    /// Why this model can't be used on this device, or nil if it can.
    var unavailableReason: String? {
        guard #available(iOS 27, *) else { return "Needs iOS 27" }
        guard FileManager.default.fileExists(atPath: bundleURL.path) else { return "Model not installed" }
        return nil
    }

    /// The loaded model; nil (and starts loading if nothing has) until it's ready.
    var ready: NeuralModel? {
        if state == .idle { load() } // e.g. freed after a memory warning
        return state == .ready ? object : nil
    }

    /// Loads the model in the background. The first load compiles it for the Neural Engine and can take minutes.
    func load() {
        switch state {
        case .loading, .ready: return
        case .idle, .failed: break
        }
        if let reason = unavailableReason { return state = .failed(reason) }
        if object == nil, NeuralEngine.framework, let type = NSClassFromString(className) as? NSObject.Type {
            object = type.init() as? NeuralModel
        }
        guard let object else { return state = .failed("NeuralCleaner.framework didn't load") }
        state = .loading
        object.prewarm(bundleURL) { error in
            Task { @MainActor in self.state = error.map { .failed($0) } ?? .ready }
        }
    }

    /// Frees the model's memory. Does nothing if it was never used.
    func unload() {
        guard let object else { return }
        object.unload()
        state = .idle
    }
}
