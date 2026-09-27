import AVFoundation
import os

/// Keeps the microphone running while wippr is in the background, so the keyboard can start dictation at any time.
/// Audio is dropped unless a dictation is running (`sink`).
final class Mic: @unchecked Sendable {
    typealias Sink = @Sendable (AVAudioPCMBuffer) -> Void

    private let engine = AVAudioEngine()
    private let current = OSAllocatedUnfairLock<Sink?>(initialState: nil)

    var format: AVAudioFormat { engine.inputNode.outputFormat(forBus: 0) }

    var sink: Sink? {
        get { current.withLock { $0 } }
        set { current.withLock { $0 = newValue } }
    }

    func start() throws {
        engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [current] buffer, _ in
            current.withLock { $0 }?(buffer)
        }
        engine.prepare()
        try engine.start()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }
}
