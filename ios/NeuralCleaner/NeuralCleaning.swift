import Foundation

/// The bridge between the app and `NeuralCleaner.framework`. Compiled into both.
/// The framework needs iOS 27 (Core AI), the app supports iOS 26, so the app never links it:
/// it loads the framework at runtime on iOS 27 and talks to it through this Objective-C protocol.
@objc(WipprNeuralCleaning)
public protocol NeuralCleaning: NSObjectProtocol {
    /// Loads the model (compiles it for the Neural Engine the first time) so the next `clean` is fast.
    func prewarm(_ bundle: URL)
    /// The cleaned text, or nil on any failure.
    func clean(_ text: String, bundle: URL, completion: @escaping (String?) -> Void)
    /// Frees the model's memory; the next `clean` reloads it.
    func unload()
}
