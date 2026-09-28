import AVFoundation
import os
import UIKit

/// Keeps the mic on in the background and runs one dictation at a time when the wippr keyboard asks:
/// mic → transcript → cleanup → keyboard (types it) + clipboard. A transcript that is a shortcut's phrase types its keys instead.
/// In a terminal, the transcript becomes a shell command (`CommandWriter`), heard by Whisper if its model is downloaded.
@MainActor
final class DictationController {
    typealias Phase = KeyboardHandoff.Phase

    static let shared = DictationController()
    static var micEnabled: Bool { UserDefaults.standard.bool(forKey: "mic") }

    private let mic = Mic()
    private var phase: Phase = .off
    private var transcriber: (any SpeechInput)?
    /// The dictation's audio for Whisper, in case it ends in a terminal (the mode arrives with the stop).
    private var audio: CommandAudio?
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
        // Experimental models: Neural Engine memory counts against the app. On a warning, free them, picked or not:
        // on a 4 GB iPad keeping them got the app killed, which turns the mic off. A picked one reloads on its next
        // use, and Apple's model stands in until it's ready.
        NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in
                DictationController.shared.log.notice("memory warning")
                #if DEBUG
                print("memory warning")
                #endif
                NeuralEngine.cleaner.unload()
                NeuralEngine.transcriber.unload()
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
        KeyboardHandoff.setEditAvailable(Cleaner.isAvailable)
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
        KeyboardHandoff.setEditAvailable(Cleaner.isAvailable)
        set(.ready)
        poll = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            Task { @MainActor in DictationController.shared.tick() }
        }
        log.notice("mic on")
        CommandTranscriber.shared.preload()
    }

    private func stopMic() async {
        poll?.invalidate()
        poll = nil
        _ = try? await transcriber?.stop()
        transcriber = nil
        audio = nil
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
        audio = nil
        set(.processing)
        defer {
            cleaner = nil
            set(.ready)
        }
        let start = Date.now
        guard let raw = try? await transcriber.stop(), !raw.isEmpty else { return nil }
        let transcribed = Date.now
        let text = await (cleaner ?? Cleaner()).clean(raw)
        DictationTiming.record(released: start, picked: start, transcribed: transcribed, cleaned: .now, id: nil,
                               asr: TranscriberModel.of(transcriber))
        return text
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
            // Experimental, for testing: Parakeet once it has loaded; Apple's Transcriber otherwise (the default).
            let transcriber: any SpeechInput
            if TranscriberModel.current == .parakeet, let parakeet = ParakeetTranscriber() {
                transcriber = parakeet
            } else if TranscriberModel.current == .whisper, let whisper = WhisperTranscriber() {
                transcriber = whisper
            } else {
                transcriber = try await Transcriber()
            }
            let sink = try await transcriber.start(micFormat: mic.format)
            let audio = CommandAudio(micFormat: mic.format)
            mic.attach({ sink($0); audio.append($0) }, since: since)
            self.transcriber = transcriber
            self.audio = audio
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
        let samples = audio?.samples ?? []
        audio = nil
        set(.processing)
        let released = command.date ?? .now // a stop command's date is when the key was let go
        let picked = Date.now
        do {
            let raw = try await transcriber.stop()
            let transcribed = Date.now
            switch command.mode ?? .dictate {
            case .dictate:
                if let shortcut = Shortcuts.match(raw) {
                    KeyboardHandoff.send(Shortcuts.expand(shortcut.keys), keys: true)
                    break
                }
                await typeCleaned(raw, released: released, picked: picked, transcribed: transcribed,
                                  asr: TranscriberModel.of(transcriber))
            case .edit:
                // Empty text tells the keyboard the edit failed, so it leaves the field alone.
                KeyboardHandoff.send(await Editor.edit(command.text ?? "", instruction: raw) ?? "", edit: true)
            case .command:
                // Apple's transcript stays as another hearing. It often misses a short word ("exit"), so Whisper runs
                // even when Apple heard nothing. Whisper is for commands, which are short: on long speech it can
                // return one letter ("p"), so it's skipped there, and its words must roughly match Apple's count.
                var heard = [raw]
                let whispered = Double(samples.count) <= 6 * CommandTranscriber.sampleRate ? await CommandTranscriber.shared.transcribe(samples) : nil
                let appleWords = raw.split(separator: " ").count
                if let whispered, case let words = whispered.split(separator: " ").count,
                   words <= appleWords * 2 + 3, appleWords < 4 || words * 2 >= appleWords {
                    heard.insert(whispered, at: 0)
                }
                if let shortcut = Shortcuts.match(heard[0]) {
                    KeyboardHandoff.send(Shortcuts.expand(shortcut.keys), keys: true)
                    break
                }
                // Nil means prose (e.g. a prompt for an agent in the terminal): typed like dictation, from Apple's
                // transcript, which hears prose better than the shell-primed Whisper.
                guard let written = await CommandWriter.write(heard: heard, screen: command.text ?? "") else {
                    await typeCleaned(raw, released: released, picked: picked, transcribed: transcribed,
                                      asr: TranscriberModel.of(transcriber))
                    break
                }
                if !written.isEmpty { KeyboardHandoff.send(written, command: true) }
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

    /// Dictation: cleans the transcript, types it and copies it. The dates time the stages (`DictationTiming`).
    private func typeCleaned(_ raw: String, released: Date, picked: Date, transcribed: Date,
                             asr: TranscriberModel) async {
        let text = await (cleaner ?? Cleaner()).clean(raw)
        let cleaned = Date.now
        if !text.isEmpty {
            let id = KeyboardHandoff.send(text, released: released)
            copy(text)
            DictationTiming.record(released: released, picked: picked, transcribed: transcribed, cleaned: cleaned, id: id,
                                   asr: asr)
        }
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
