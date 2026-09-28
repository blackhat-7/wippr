import Foundation
internal import llama
import os

/// Owns the llama.cpp model and context; everything runs on `queue`, one call at a time.
/// Its own framework so the app never imports `llama`: its ggml headers differ from whisper.cpp's, and Swift
/// refuses both in one module. Only this Swift API is public.
public final class LlamaEngine: @unchecked Sendable {
    private let queue = DispatchQueue(label: "cx.immortal.wippr.llama", qos: .userInitiated)
    private var model: OpaquePointer?
    private var context: OpaquePointer?
    private var sampler: UnsafeMutablePointer<llama_sampler>?
    private let log = Logger(subsystem: "cx.immortal.wippr", category: "llama")

    public init() { llama_backend_init() }

    public func load(_ file: URL) { queue.async { _ = self.loaded(file) } }

    public func unload() {
        queue.async { [self] in
            guard model != nil else { return }
            llama_sampler_free(sampler)
            llama_free(context)
            llama_model_free(model)
            (model, context, sampler) = (nil, nil, nil)
            log.notice("freed")
        }
    }

    public func respond(system: String, user: String, maxTokens: Int, model file: URL) async -> String? {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: self.generate(system: system, user: user, maxTokens: maxTokens, file: file)) }
        }
    }

    /// On `queue` only.
    private func loaded(_ file: URL) -> Bool {
        if model != nil { return true }
        let start = ContinuousClock.now
        var modelParams = llama_model_default_params()
        modelParams.n_gpu_layers = 0 // CPU: iOS blocks the GPU in the background
        guard let model = llama_model_load_from_file(file.path, modelParams) else {
            log.error("model load failed")
            return false
        }
        var contextParams = llama_context_default_params()
        contextParams.n_ctx = 2048
        contextParams.n_batch = 2048 // the whole prompt goes to one llama_decode, which takes at most n_batch tokens
        contextParams.n_threads = 4
        contextParams.n_threads_batch = 4
        guard let context = llama_init_from_model(model, contextParams) else {
            llama_model_free(model)
            log.error("context init failed")
            return false
        }
        let sampler = llama_sampler_chain_init(llama_sampler_chain_default_params())
        llama_sampler_chain_add(sampler, llama_sampler_init_greedy())
        (self.model, self.context, self.sampler) = (model, context, sampler)
        log.notice("loaded in \((ContinuousClock.now - start) / .milliseconds(1), format: .fixed(precision: 0)) ms")
        return true
    }

    /// On `queue` only. Greedy, like the benchmark; S1-mini's chat template with thinking off.
    private func generate(system: String, user: String, maxTokens: Int, file: URL) -> String? {
        // Not loaded yet (just picked, or freed on a memory warning): load it next and return nil now, so the
        // caller uses Apple's model (or raw text) instead of waiting seconds for the load.
        guard model != nil else {
            queue.async { _ = self.loaded(file) }
            return nil
        }
        guard let model, let context, let sampler else { return nil }
        let start = ContinuousClock.now
        let vocab = llama_model_get_vocab(model)
        let prompt = "<|im_start|>system\n\(system)<|im_end|>\n<|im_start|>user\n\(user)<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n"
        var tokens = [llama_token](repeating: 0, count: prompt.utf8.count + 16)
        let count = llama_tokenize(vocab, prompt, Int32(prompt.utf8.count), &tokens, Int32(tokens.count), true, true)
        guard count > 0, count < 2048 - Int32(maxTokens) else { return nil }
        tokens.removeLast(tokens.count - Int(count))
        llama_memory_clear(llama_get_memory(context), true)
        llama_sampler_reset(sampler)
        let prefilled = tokens.withUnsafeMutableBufferPointer { llama_decode(context, llama_batch_get_one($0.baseAddress, count)) }
        guard prefilled == 0 else { return nil }
        var output = [CChar]()
        var generated = 0
        for _ in 0..<maxTokens {
            var token = llama_sampler_sample(sampler, context, -1)
            if llama_vocab_is_eog(vocab, token) { break }
            var piece = [CChar](repeating: 0, count: 64)
            let length = llama_token_to_piece(vocab, token, &piece, Int32(piece.count), 0, false)
            if length > 0 { output += piece.prefix(Int(length)) }
            generated += 1
            guard llama_decode(context, llama_batch_get_one(&token, 1)) == 0 else { return nil }
        }
        let text = String(decoding: output.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        log.notice("\(count) prompt + \(generated) tokens: \((ContinuousClock.now - start) / .milliseconds(1), format: .fixed(precision: 0)) ms")
        return text.isEmpty ? nil : text
    }
}
