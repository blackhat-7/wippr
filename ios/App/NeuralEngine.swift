import Foundation

/// S1-mini on the Neural Engine (iOS 27+), through the separately built `NeuralCleaner.framework`.
/// On iOS 26, or before the model is installed, `Cleaner` uses Apple Intelligence instead.
enum NeuralEngine {
    /// The Core AI export of S1-mini (a folder with the .aimodel files and the tokenizer).
    static let bundleURL = URL.applicationSupportDirectory.appending(path: "s1-mini-ios")

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: bundleURL.path)
    }

    static var isAvailable: Bool { isInstalled && cleaner != nil }

    /// The framework's cleaner, loaded once; nil below iOS 27 or if the framework won't load.
    private static let cleaner: NeuralCleaning? = {
        guard #available(iOS 27, *),
              let url = Bundle.main.privateFrameworksURL?.appending(path: "NeuralCleaner.framework"),
              let framework = Bundle(url: url), framework.load(),
              let type = NSClassFromString("WipprNeuralCleaner") as? NSObject.Type
        else { return nil }
        return type.init() as? NeuralCleaning
    }()

    static func prewarm() {
        cleaner?.prewarm(bundleURL)
    }

    static func unload() {
        cleaner?.unload()
    }

    /// The cleaned text, or nil if the Neural Engine path isn't available or fails.
    static func clean(_ raw: String) async -> String? {
        guard isInstalled, let cleaner else { return nil }
        let text = Prepass.lists(raw)
        return await withCheckedContinuation { done in
            cleaner.clean(text, bundle: bundleURL) { done.resume(returning: $0) }
        }
    }
}
