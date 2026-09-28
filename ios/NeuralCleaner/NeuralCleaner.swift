import CoreAILanguageModels
import Foundation
import FoundationModels
import os

/// Dictation cleanup with Superwhisper S1-mini (Qwen3-0.6B cleanup fine-tune) on the Neural Engine, via Core AI.
/// The model is Apple's iOS export (`coreai.llm.export --platform iOS`, mixed 4/8-bit palettized), which Core AI
/// runs on the Neural Engine; iOS blocks the GPU for background apps, and the app is in the background whenever
/// the keyboard asks for text. Loaded by the app at runtime on iOS 27 only (see NeuralCleaning.swift).
@objc(WipprNeuralCleaner)
public final class NeuralCleaner: NSObject, NeuralCleaning, @unchecked Sendable {
    /// S1-mini's trained system prompt and control line; its model card says not to change them.
    private static let system = "You are a text normalizer for speech-to-text transcripts. The input begins with a control line specifying the styling, structure, and context settings; clean the transcript to match those settings and output only the cleaned text."
    private static let control = "[Styling: semi-formal] [Structure: lists] [Context: general]\n"

    private let state = State()
    private let log = Logger(subsystem: "cx.immortal.wippr", category: "neural")

    override public required init() { super.init() }

    public func prewarm(_ bundle: URL) {
        Task { _ = try? await state.model(at: bundle) }
    }

    public func clean(_ text: String, bundle: URL, completion: @escaping (String?) -> Void) {
        Task {
            let start = Date.now
            do {
                let model = try await state.model(at: bundle)
                let session = LanguageModelSession(model: model, instructions: Self.system)
                let response = try await session.respond(
                    to: Self.control + text,
                    options: GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 1024)
                )
                let out = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                log.notice("cleaned \(text.count) chars in \(Int(Date.now.timeIntervalSince(start) * 1000)) ms")
                completion(out.isEmpty ? nil : out)
            } catch {
                log.error("clean: \(error, privacy: .public)")
                #if DEBUG
                print("neural: clean: \(error)")
                #endif
                completion(nil)
            }
        }
    }

    public func unload() {
        Task { await state.unload() }
    }

    private actor State {
        /// The load in progress or done. Shared, so prewarm and clean calls that arrive during the
        /// (slow) load wait for it instead of each loading another copy of the model.
        private var loading: (url: URL, task: Task<CoreAILanguageModel, Error>)?

        func model(at url: URL) async throws -> CoreAILanguageModel {
            if let loading, loading.url == url { return try await loading.task.value }
            let task = Task {
                let start = Date.now
                let model = try await CoreAILanguageModel(resourcesAt: url, mode: .eager)
                #if DEBUG
                print("neural: loaded model in \(Int(Date.now.timeIntervalSince(start) * 1000)) ms")
                #endif
                return model
            }
            loading = (url, task)
            do {
                return try await task.value
            } catch {
                if loading?.url == url { loading = nil } // let the next call retry
                throw error
            }
        }

        func unload() {
            if let task = loading?.task {
                Task { try? await task.value.unload() }
            }
            loading = nil
        }
    }
}
