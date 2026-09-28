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
            problems.append("Microphone access is off. Turn it on in Settings → noboard.")
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
        poll = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            Task { @MainActor in DictationController.shared.tick() }
        }
        log.notice("mic on")
    }

    private func stopMic() async {
        poll?.invalidate()
        poll = nil
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

    // MARK: Setup status and in-app practice (onboarding)

    enum InAppError: LocalizedError {
        case micDenied
        var errorDescription: String? { "Microphone access is off. Turn it on in Settings → noboard." }
    }

    /// Whether the noboard keyboard is added in Settings → General → Keyboard → Keyboards.
    static var keyboardAdded: Bool {
        (UserDefaults.standard.array(forKey: "AppleKeyboards") as? [String])?
            .contains { $0.hasPrefix(Bundle.main.bundleIdentifier! + ".keyboard") } ?? false
    }

    /// Starts a dictation from inside the app (onboarding's practice strip), turning the mic on for now if needed.
    func startInApp() async throws {
        guard await AVAudioApplication.requestRecordPermission() else { throw InAppError.micDenied }
        if phase == .off { try await startMic() }
        guard phase == .ready else { return }
        await startDictation(since: .now.addingTimeInterval(-0.15))
    }

    /// Stops the in-app dictation and returns the cleaned text instead of typing it through the keyboard.
    func finishInApp() async -> String? {
        guard let transcriber, phase == .recording else { return nil }
        mic.detach()
        self.transcriber = nil
        set(.processing)
        defer {
            cleaner = nil
            set(.ready)
        }
        guard let raw = try? await transcriber.stop(), !raw.isEmpty else { return nil }
        return await (cleaner ?? Cleaner()).clean(raw)
    }

    /// After practice, turns the mic back off unless the user chose to keep it on.
    func endInApp() async {
        if !Self.micEnabled, phase == .ready { await stopMic() }
    }

    /// Heartbeat for the keyboard, and handles its start/stop taps one at a time.
    private func tick() {
        ticks += 1
        if ticks % 20 == 0 { KeyboardHandoff.setStatus(phase) }
        if phase == .recording { KeyboardHandoff.setLevel(mic.level) }
        guard !busy, let command = KeyboardHandoff.command(), command.id != lastCommand else { return }
        lastCommand = command.id
        busy = true
        Task {
            if command.record, phase == .ready {
                await startDictation(since: (command.date ?? .now).addingTimeInterval(-0.15))
            } else if !command.record, phase == .recording {
                await finishDictation(command)
            }
            busy = false
        }
    }

    /// `since`: when the key went down. The mic's pre-roll covers the time until the model is ready.
    private func startDictation(since: Date) async {
        set(.recording)
        do {
            let transcriber = try await Transcriber()
            mic.attach(try await transcriber.start(micFormat: mic.format), since: since)
            self.transcriber = transcriber
            cleaner = Cleaner() // prewarms the model while the user speaks
        } catch {
            log.error("start: \(error, privacy: .public)")
            set(.ready)
        }
    }

    private func finishDictation(_ command: KeyboardHandoff.Command) async {
        guard let transcriber else { return }
        mic.detach()
        self.transcriber = nil
        set(.processing)
        do {
            let raw = try await transcriber.stop()
            switch command.mode ?? .dictate {
            case .dictate:
                let text = await (cleaner ?? Cleaner()).clean(raw)
                if !text.isEmpty {
                    KeyboardHandoff.send(text)
                    copy(text)
                }
            case .edit:
                // Empty text tells the keyboard the edit failed, so it leaves the field alone.
                KeyboardHandoff.send(await Editor.edit(command.text ?? "", instruction: raw) ?? "", edit: true)
            case .cancel:
                break
            }
            log.notice("\((command.mode ?? .dictate).rawValue, privacy: .public): \(raw.count) chars")
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
