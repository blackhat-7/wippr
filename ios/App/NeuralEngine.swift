import Foundation
import Observation

/// Experimental, for testing: S1-mini on the Neural Engine (iOS 27+), through the separately built
/// `NeuralCleaner.framework`. Only used when Home's cleanup model is S1-mini; with the default (Apple Intelligence)
/// the framework is never loaded.
@MainActor @Observable
final class NeuralEngine {
    static let shared = NeuralEngine()

    enum State: Equatable {
        case idle, loading, ready
        case failed(String)
    }

    /// The model's load state; `clean` only runs once it's `ready`.
    private(set) var state = State.idle

    /// The Core AI export of S1-mini (a folder with the .aimodel files and the tokenizer).
    nonisolated static let bundleURL = URL.applicationSupportDirectory.appending(path: "s1-mini-ios")

    /// Why S1-mini can't be used on this device, or nil if it can.
    static var unavailableReason: String? {
        guard #available(iOS 27, *) else { return "Needs iOS 27" }
        guard FileManager.default.fileExists(atPath: bundleURL.path) else { return "Model not installed" }
        return nil
    }

    /// The framework's cleaner, loaded on first use.
    @ObservationIgnored private var cleaner: NeuralCleaning?

    private func framework() -> NeuralCleaning? {
        if let cleaner { return cleaner }
        guard #available(iOS 27, *),
              let url = Bundle.main.privateFrameworksURL?.appending(path: "NeuralCleaner.framework"),
              let framework = Bundle(url: url), framework.load(),
              let type = NSClassFromString("WipprNeuralCleaner") as? NSObject.Type
        else { return nil }
        cleaner = type.init() as? NeuralCleaning
        return cleaner
    }

    /// Loads the model in the background (the first load compiles it for the Neural Engine and can take minutes).
    func load() {
        switch state {
        case .loading, .ready: return
        case .idle, .failed: break
        }
        if let reason = Self.unavailableReason { return state = .failed(reason) }
        guard let cleaner = framework() else { return state = .failed("NeuralCleaner.framework didn't load") }
        state = .loading
        cleaner.prewarm(Self.bundleURL) { error in
            Task { @MainActor in self.state = error.map { .failed($0) } ?? .ready }
        }
    }

    /// Frees the model's memory. Does nothing if S1-mini was never used.
    func unload() {
        guard let cleaner else { return }
        cleaner.unload()
        state = .idle
    }

    /// The cleaned text; nil until the model has loaded, or if it fails.
    func clean(_ raw: String) async -> String? {
        guard state == .ready, let cleaner, !raw.isEmpty else {
            if state == .idle { load() } // e.g. freed after a memory warning
            return nil
        }
        let text = Prepass.lists(raw)
        return await withCheckedContinuation { done in
            cleaner.clean(text, bundle: Self.bundleURL) { done.resume(returning: $0) }
        }
    }
}
