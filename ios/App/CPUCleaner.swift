import Foundation
import LlamaCleaner
import Observation
import os
import UIKit

/// Experimental, for testing: S1-mini cleanup on the CPU with llama.cpp (the 4-bit GGUF, 484 MB). The Neural Engine
/// copy loads at ~2.9 GB and gets the app killed on a 4 GB iPad; this one needs ~1.3 GB, and the CPU also works in
/// the background without an entitlement. Same model and prompt as `NeuralEngine.clean`.
@MainActor @Observable
final class CPUCleaner {
    static let shared = CPUCleaner()

    enum Download: Equatable { case running(Double), failed(String) }
    private(set) var download: Download?

    static let source = ModelSource.s1miniGGUF
    private static var folder: URL { .applicationSupportDirectory.appending(path: "s1-mini-gguf") }
    private static var modelFile: URL { folder.appending(path: "s1-mini-q4_k_m.gguf") }
    /// Stored, so Home unlocks the choice as soon as the download finishes.
    private(set) var isInstalled = FileManager.default.fileExists(atPath: modelFile.path)

    private let engine = LlamaEngine()

    private init() {
        NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: nil) { [engine] _ in
            engine.unload()
        }
    }

    func startDownload() {
        if case .running = download { return }
        guard !isInstalled else { return }
        download = .running(0)
        Task {
            do {
                try await Self.source.download(to: Self.folder) { fraction in
                    Task { @MainActor in if case .running = self.download { self.download = .running(fraction) } }
                }
                isInstalled = true
                download = nil
                if CleanupModel.current == .s1miniCPU { preload() }
            } catch {
                download = .failed(error.localizedDescription)
            }
        }
    }

    /// Loads the model off the main thread, so the first cleanup doesn't wait for it.
    func preload() {
        guard isInstalled else { return }
        engine.load(Self.modelFile)
    }

    /// Frees the model's ~1.3 GB when another cleanup model is picked.
    func unload() { engine.unload() }

    /// S1-mini's cleanup (after the list rules); nil if the model isn't downloaded or fails.
    func clean(_ raw: String) async -> String? {
        guard !raw.isEmpty, isInstalled else { return nil }
        let text = Prepass.lists(raw)
        // About twice the input's tokens (~4 bytes each) + 64, so a repetition loop stops early.
        return await engine.respond(system: NeuralEngine.s1System, user: WritingStyle.current.s1Control + text,
                                    maxTokens: min(1024, text.utf8.count / 2 + 64), model: Self.modelFile)
    }
}

extension CPUCleaner: DownloadableModel {
    var downloadProgress: Double? { if case .running(let fraction) = download { fraction } else { nil } }
    var downloadError: String? { if case .failed(let error) = download { error } else { nil } }
    var downloadSize: Int64 { Self.source.size }
}
