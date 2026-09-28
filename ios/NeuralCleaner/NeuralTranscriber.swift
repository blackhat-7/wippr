import CoreAISpeech
import Foundation
import os

/// Parakeet TDT (exported with Apple's recipe, `--streaming --dtype float16`) on the Neural Engine, via Core AI.
/// Audio streams in while the key is held, so on release only the last window is left to transcribe.
@objc(WipprNeuralTranscriber)
public final class NeuralTranscriber: NSObject, NeuralTranscribing, @unchecked Sendable {
    private struct Session {
        let input: AsyncStream<[Float]>.Continuation
        let done: Task<String, Error>
    }

    private let model = OSAllocatedUnfairLock<SpeechRecognitionModel?>(initialState: nil)
    private let session = OSAllocatedUnfairLock<Session?>(initialState: nil)
    private let log = Logger(subsystem: "cx.immortal.wippr", category: "neural")

    override public required init() { super.init() }

    public var sampleRate: Double { 16000 }

    public func prewarm(_ bundle: URL, completion: @escaping (String?) -> Void) {
        if model.withLock({ $0 }) != nil { return completion(nil) }
        Task {
            do {
                let start = Date.now
                let loaded = try await SpeechRecognitionModel(resourcesAt: bundle)
                try await loaded.prewarm(sampleCount: Int(sampleRate)) // compiles the encoder window once
                #if DEBUG
                print("neural: loaded \(bundle.lastPathComponent) in \(Int(Date.now.timeIntervalSince(start) * 1000)) ms")
                #endif
                model.withLock { $0 = loaded }
                completion(nil)
            } catch {
                log.error("load: \(error, privacy: .public)")
                completion("\(error)")
            }
        }
    }

    public func start() -> Bool {
        guard let model = model.withLock({ $0 }) else { return false }
        return session.withLock { session in
            guard session == nil else { return false }
            let (input, continuation) = AsyncStream.makeStream(of: [Float].self)
            let done = Task {
                let updates = try await model.startStream()
                // Each segment (cut at a pause) is delivered once as `.finalized`; finishStream only returns the last.
                let segments = Task {
                    var texts: [Int: String] = [:]
                    for try await update in updates {
                        if case .finalized(let segment) = update { texts[segment.segmentIndex] = segment.text }
                    }
                    return texts
                }
                for await samples in input { try await model.append(pcm: samples) }
                let last = try await model.finishStream()
                var texts = try await segments.value
                if texts.isEmpty { texts[0] = last }
                return texts.sorted { $0.key < $1.key }
                    .map { $0.value.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    .joined(separator: " ")
            }
            session = Session(input: continuation, done: done)
            return true
        }
    }

    public func append(_ samples: Data) {
        let floats = samples.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        session.withLock { _ = $0?.input.yield(floats) }
    }

    public func finish(completion: @escaping (String?) -> Void) {
        guard let current = session.withLock({ s -> Session? in defer { s = nil }; return s }) else { return completion(nil) }
        current.input.finish()
        Task {
            do {
                let text = try await current.done.value.trimmingCharacters(in: .whitespacesAndNewlines)
                completion(text)
            } catch {
                log.error("transcribe: \(error, privacy: .public)")
                #if DEBUG
                print("neural: transcribe: \(error)")
                #endif
                completion(nil)
            }
        }
    }

    public func unload() {
        model.withLock { $0 = nil }
    }
}
