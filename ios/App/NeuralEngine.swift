import Foundation
import Observation
import os

/// Experimental, for testing: models on the Neural Engine (iOS 27+), through the separately built
/// `NeuralCleaner.framework`. Each is only loaded when its Home → Experimental setting picks it; with the
/// defaults (Apple's models) the framework is never loaded.
enum NeuralEngine {
    /// S1-mini, 8-bit (cleanup).
    @MainActor static let cleaner = NeuralSlot(folder: "s1-mini-ios", className: "WipprNeuralLanguageModel", source: .s1mini)
    /// Parakeet TDT v2, streaming float16 (speech recognition).
    @MainActor static let transcriber = NeuralSlot(folder: "parakeet-ios", className: "WipprNeuralTranscriber", source: .parakeet)

    /// S1-mini's trained system prompt; its model card says not to change it. The control line comes from the
    /// writing style (`WritingStyle.s1Control`), always one of the trained values.
    static let s1System = "You are a text normalizer for speech-to-text transcripts. The input begins with a control line specifying the styling, structure, and context settings; clean the transcript to match those settings and output only the cleaned text."

    /// S1-mini's cleanup (after the list rules); nil until the model has loaded, or if it fails.
    @MainActor static func clean(_ raw: String) async -> String? {
        guard !raw.isEmpty, let model = cleaner.ready as? NeuralLanguageModel else { return nil }
        let text = Prepass.lists(raw)
        // About twice the input's tokens (~4 bytes each) + 64, so a repetition loop stops early.
        return await respond(model, to: WritingStyle.current.s1Control + text, instructions: s1System,
                             maxTokens: min(1024, text.utf8.count / 2 + 64), bundle: cleaner.bundleURL)
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
    /// Loading one took ~2.9 GB, and a 4 GB iPad (10th gen) killed the app for it, turning the mic off. Home hides
    /// these models there, and one picked before this check won't load.
    static let fitsThisDevice = ProcessInfo.processInfo.physicalMemory > 5 << 30

    enum State: Equatable {
        case idle, loading, ready
        case failed(String)
    }

    enum Download: Equatable {
        case none
        case running(Double)
        case failed(String)
    }

    /// Only `ready` models are used; until then Apple's model does the work.
    private(set) var state = State.idle
    /// Fetching the model from Hugging Face (Home → Experimental).
    private(set) var download = Download.none
    let bundleURL: URL
    /// Where to download it from; nil for a model that's only ever copied in by hand (bench candidates).
    let source: ModelSource?
    @ObservationIgnored private let className: String
    @ObservationIgnored private var object: NeuralModel?

    init(folder: String, className: String, source: ModelSource? = nil) {
        bundleURL = URL.applicationSupportDirectory.appending(path: folder)
        self.className = className
        self.source = source
    }

    var isInstalled: Bool { FileManager.default.fileExists(atPath: bundleURL.path) }

    /// Downloads the model (iOS 27 only; the app has to stay open until it's done).
    func startDownload() {
        guard let source, !isInstalled, #available(iOS 27, *) else { return }
        if case .running = download { return }
        download = .running(0)
        let folder = bundleURL
        Task {
            do {
                let last = OSAllocatedUnfairLock(initialState: 0.0)
                try await source.download(to: folder) { fraction in
                    // Redraw every 0.5%.
                    guard last.withLock({ l in fraction - l >= 0.005 || fraction >= 1 ? { l = fraction; return true }() : false }) else { return }
                    Task { @MainActor in if case .running = self.download { self.download = .running(fraction) } }
                }
                download = .none
                if state != .idle { state = .idle } // a failed "not installed" load can be retried now
            } catch {
                download = .failed(error.localizedDescription)
            }
        }
    }

    /// Frees the disk space; the model can be downloaded again.
    func deleteModel() {
        unload()
        try? FileManager.default.removeItem(at: bundleURL)
        state = .idle
        download = .none
    }

    /// Why this model can't be used on this device, or nil if it can.
    var unavailableReason: String? {
        guard Self.fitsThisDevice else { return "Needs more memory" }
        guard #available(iOS 27, *) else { return "Needs iOS 27" }
        guard isInstalled else { return "Model not installed" }
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
