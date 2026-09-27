import AVFoundation
import os

/// Keeps the microphone running while wippr is in the background, so the keyboard can start dictation at any time.
/// Audio is dropped unless a dictation is running, except for the last few seconds, which are replayed when one starts
/// so the first words aren't lost while the speech model spins up.
final class Mic: @unchecked Sendable {
    typealias Sink = @Sendable (AVAudioPCMBuffer) -> Void

    private struct State {
        var sink: Sink?
        var recent: [(date: Date, buffer: AVAudioPCMBuffer)] = []
    }

    private static let preRoll: TimeInterval = 3
    private let engine = AVAudioEngine()
    private let state = OSAllocatedUnfairLock(uncheckedState: State())

    var format: AVAudioFormat { engine.inputNode.outputFormat(forBus: 0) }

    func start() throws {
        engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [state] buffer, _ in
            guard let copy = Self.copy(buffer) else { return }
            let now = Date.now
            state.withLockUnchecked { state in
                state.recent.removeAll { now.timeIntervalSince($0.date) > Self.preRoll }
                state.recent.append((now, copy))
                state.sink?(copy)
            }
        }
        engine.prepare()
        try engine.start()
    }

    func stop() {
        detach()
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        state.withLockUnchecked { $0.recent = [] }
    }

    /// Sends audio from `since` onwards (up to a few seconds back) to `sink`, then everything new.
    func attach(_ sink: @escaping Sink, since: Date) {
        state.withLockUnchecked { state in
            for (date, buffer) in state.recent where date >= since { sink(buffer) }
            state.sink = sink
        }
    }

    func detach() { state.withLockUnchecked { $0.sink = nil } }

    /// The tap may reuse its buffer, and the pre-roll keeps buffers around.
    private static func copy(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength),
              let source = buffer.floatChannelData, let target = copy.floatChannelData else { return nil }
        copy.frameLength = buffer.frameLength
        for channel in 0..<Int(buffer.format.channelCount) {
            target[channel].update(from: source[channel], count: Int(buffer.frameLength))
        }
        return copy
    }
}
