import AVFoundation
import os
import UIKit

/// Keeps the mic on in the background and runs one dictation at a time when the wippr keyboard asks:
/// mic → transcript → cleanup → keyboard (types it) + clipboard.
@MainActor
final class DictationController {
    typealias Phase = KeyboardHandoff.Phase

    static let shared = DictationController()
    static var micEnabled: Bool { UserDefaults.standard.bool(forKey: "mic") }

    private let mic = Mic()
    private var phase: Phase = .off
    private var transcriber: Transcriber?
    private var cleaner: Cleaner?
    private var pendingCopy: String?
    private var lastCommand: UUID?
    private var busy = false
    private var poll: Timer?
    private var ticks = 0
    private var micSince = Date.distantPast
    private let log = Logger(subsystem: "cx.immortal.wippr", category: "dictation")

    private init() {
        // Calls, Siri, route changes and media resets stop the engine; restart the mic afterwards.
        for name in [AVAudioSession.interruptionNotification, .AVAudioEngineConfigurationChange,
                     AVAudioSession.mediaServicesWereResetNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { note in
                let type = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                guard type != AVAudioSession.InterruptionType.began.rawValue else { return }
                Task { @MainActor in await DictationController.shared.restartMic() }
            }
        }
    }

    /// One-time setup, run from the app in the foreground.
    /// Returns the problems that block or degrade dictation; empty means ready.
    func setUp() async -> [String] {
        var problems: [String] = []
        if !(await AVAudioApplication.requestRecordPermission()) {
            problems.append("Microphone access is off. Turn it on in Settings → wippr.")
        }
        do {
            try await Transcriber.installAssets()
        } catch {
            problems.append("Speech model unavailable: \(error.localizedDescription)")
        }
        if !Cleaner.isAvailable {
            problems.append("Apple Intelligence is unavailable, so text is typed without cleanup.")
        }
        await appDidBecomeActive()
        return problems
    }

    /// Retries a refused clipboard write and turns the mic back on if it should be on.
    func appDidBecomeActive() async {
        if let pendingCopy {
            UIPasteboard.general.string = pendingCopy
            self.pendingCopy = nil
        }
        if Self.micEnabled, phase == .off {
            do { try await startMic() } catch { log.error("mic: \(error, privacy: .public)") }
        }
    }

    /// Turns the background mic on or off. Turning it on must happen in the foreground.
    func setMic(_ on: Bool) async throws {
        UserDefaults.standard.set(on, forKey: "mic")
        if on { try await startMic() } else { await stopMic() }
    }

    private func startMic() async throws {
        guard phase == .off else { return }
        let session = AVAudioSession.sharedInstance()
        // Mixable, so music and other audio keep playing while the mic is on.
        try session.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers, .defaultToSpeaker, .allowBluetoothA2DP])
        try session.setActive(true)
        try mic.start()
        micSince = .now
        lastCommand = KeyboardHandoff.command()?.id // ignore taps from while the mic was off
        set(.ready)
        poll = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
            Task { @MainActor in DictationController.shared.tick() }
        }
        log.notice("mic on")
    }

    private func stopMic() async {
        poll?.invalidate()
        poll = nil
        mic.sink = nil
        _ = try? await transcriber?.stop()
        transcriber = nil
        cleaner = nil
        mic.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        set(.off)
        log.notice("mic off")
    }

    private func restartMic() async {
        // Starting the engine can itself post a configuration change.
        guard phase != .off, Date.now.timeIntervalSince(micSince) > 2 else { return }
        await stopMic()
        do { try await startMic() } catch { log.error("restart mic: \(error, privacy: .public)") }
    }

    /// Heartbeat for the keyboard, and handles its start/stop taps one at a time.
    private func tick() {
        ticks += 1
        if ticks % 5 == 0 { KeyboardHandoff.setStatus(phase) }
        guard !busy, let command = KeyboardHandoff.command(), command.id != lastCommand else { return }
        lastCommand = command.id
        busy = true
        Task {
            if command.record, phase == .ready {
                await startDictation()
            } else if !command.record, phase == .recording {
                await finishDictation()
            }
            busy = false
        }
    }

    private func startDictation() async {
        set(.recording)
        do {
            let transcriber = try await Transcriber()
            mic.sink = try await transcriber.start(micFormat: mic.format)
            self.transcriber = transcriber
            cleaner = Cleaner() // prewarms the model while the user speaks
        } catch {
            log.error("start: \(error, privacy: .public)")
            set(.ready)
        }
    }

    private func finishDictation() async {
        guard let transcriber else { return }
        mic.sink = nil
        self.transcriber = nil
        set(.processing)
        do {
            let raw = try await transcriber.stop()
            let text = await (cleaner ?? Cleaner()).clean(raw)
            if !text.isEmpty {
                KeyboardHandoff.send(text)
                copy(text)
            }
            log.notice("dictation: \(raw.count) chars")
        } catch {
            log.error("finish: \(error, privacy: .public)")
        }
        cleaner = nil
        set(.ready)
    }

    /// Clipboard fallback. iOS can refuse the write while the app is in the background; opening the app retries it.
    private func copy(_ text: String) {
        let before = UIPasteboard.general.changeCount
        UIPasteboard.general.string = text
        pendingCopy = UIPasteboard.general.changeCount != before ? nil : text
    }

    private func set(_ phase: Phase) {
        self.phase = phase
        KeyboardHandoff.setStatus(phase)
    }
}
