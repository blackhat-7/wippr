import CoreAILanguageModels
import Foundation
import FoundationModels
import os
#if DEBUG
import Tokenizers
#endif

/// A Core AI chat model on the Neural Engine: S1-mini (cleanup) or Qwen3-1.7B (edit mode), each exported with
/// `coreai.llm.export --platform iOS`. The app owns the prompts. Loaded by the app at runtime on iOS 27 only.
@objc(WipprNeuralLanguageModel)
public final class NeuralLanguageModelImpl: NSObject, NeuralLanguageModel, @unchecked Sendable {
    private let state = State()
    private let log = Logger(subsystem: "cx.immortal.wippr", category: "neural")

    override public required init() { super.init() }

    public func prewarm(_ bundle: URL, completion: @escaping (String?) -> Void) {
        Task {
            do {
                _ = try await state.model(at: bundle)
                completion(nil)
            } catch {
                log.error("load: \(error, privacy: .public)")
                completion("\(error)")
            }
        }
    }

    public func respond(to prompt: String, instructions: String, maxTokens: Int, bundle: URL,
                        completion: @escaping (String?) -> Void) {
        Task {
            let start = Date.now
            do {
                let model = try await state.model(at: bundle)
                #if DEBUG
                await Self.dumpPrompt(prompt, instructions: instructions, bundle: bundle)
                #endif
                let session = LanguageModelSession(model: model, instructions: instructions)
                let response = try await session.respond(
                    to: prompt, options: GenerationOptions(samplingMode: .greedy, maximumResponseTokens: maxTokens))
                let out = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                log.notice("\(bundle.lastPathComponent, privacy: .public): \(prompt.count) chars in \(Int(Date.now.timeIntervalSince(start) * 1000)) ms")
                completion(out.isEmpty ? nil : out)
            } catch {
                log.error("respond: \(error, privacy: .public)")
                #if DEBUG
                print("neural: respond: \(error)")
                #endif
                completion(nil)
            }
        }
    }

    #if DEBUG
    /// Prints the prompt the chat template builds (what Core AI feeds the model), once per model per launch.
    private static let dumped = OSAllocatedUnfairLock(initialState: Set<URL>())
    private static func dumpPrompt(_ prompt: String, instructions: String, bundle: URL) async {
        guard dumped.withLock({ $0.insert(bundle).inserted }) else { return }
        do {
            let tokenizer = try await LanguageBundle(at: bundle).loadTokenizer()
            let tokens = try tokenizer.applyChatTemplate(messages: [
                ["role": "system", "content": instructions], ["role": "user", "content": prompt],
            ])
            print("neural: prompt \(tokens.count) tokens, ends \(tokens.suffix(8)):\n\(tokenizer.decode(tokens: tokens))<END>")
        } catch {
            print("neural: prompt dump failed: \(error)")
        }
    }
    #endif

    public func unload() {
        Task { await state.unload() }
    }

    private actor State {
        /// The load in progress or done. Shared, so prewarm and respond calls that arrive during the
        /// (slow) load wait for it instead of each loading another copy of the model.
        private var loading: (url: URL, task: Task<CoreAILanguageModel, Error>)?

        func model(at url: URL) async throws -> CoreAILanguageModel {
            if let loading, loading.url == url { return try await loading.task.value }
            let task = Task {
                let start = Date.now
                let model = try await CoreAILanguageModel(resourcesAt: url, mode: .eager)
                #if DEBUG
                print("neural: loaded \(url.lastPathComponent) in \(Int(Date.now.timeIntervalSince(start) * 1000)) ms")
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
