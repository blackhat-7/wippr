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
    private var idleUnload: Task<Void, Never>?
    /// Voice mode (a double-tap on the keyboard): its start command, whose mode and text each phrase uses.
    private var voiceMode: KeyboardHandoff.Command?
    /// Voice mode's current recording: when its audio starts, and whether the pause detector has heard speech in it.
    private var segmentSince = Date.now
    private var segmentHasSpeech = false
    private var checkingPause = false
    /// Voice mode's phrases, handled one after another.
    private var phrases: Task<Void, Never>?

    private init() {
        // Calls, Siri, route changes and media resets stop the engine; restart the mic afterwards.
        for name in [AVAudioSession.interruptionNotification, .AVAudioEngineConfigurationChange,
                     AVAudioSession.mediaServicesWereResetNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { note in
                let type = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                let info = note.userInfo.map { $0.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: " ") } ?? ""
                MicEvents.record("\(note.name.rawValue) \(info)")
                guard type != AVAudioSession.InterruptionType.began.rawValue else { return }
                Task { @MainActor in await DictationController.shared.restartMic() }
            }
        }
        NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { note in
            MicEvents.record("route change \(note.userInfo?[AVAudioSessionRouteChangeReasonKey] ?? "")")
        }
        for name in [UIApplication.didEnterBackgroundNotification, UIApplication.willEnterForegroundNotification,
                     UIApplication.willTerminateNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { note in
                MicEvents.record(note.name.rawValue)
            }
        }
        // Experimental models: Neural Engine memory counts against the app. On a warning, free the ones that
        // aren't picked (a picked one would only reload on its next use, and Apple's model would stand in).
        // Devices too small to hold one (4 GB) don't offer them at all (`NeuralSlot.fitsThisDevice`).
        NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in
                DictationController.shared.log.notice("memory warning")
                MicEvents.record("memory warning")
                #if DEBUG
                print("memory warning")
                #endif
                if CleanupModel.current != .s1mini { NeuralEngine.cleaner.unload() }
                if TranscriberModel.current != .parakeet { NeuralEngine.transcriber.unload() }
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
            do { try await startMic() } catch {
                log.error("mic: \(error, privacy: .public)")
                MicEvents.record("mic start failed: \(error)")
            }
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
        MicEvents.record("mic on: \(mic.format)")
        loadPickedModels()
        scheduleIdleUnload()
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
        MicEvents.record("mic off")
    }

    private func restartMic() async {
        // Starting the engine can itself post a configuration change.
        guard phase != .off, Date.now.timeIntervalSince(micSince) > 2 else { return MicEvents.record("restart skipped (\(phase))") }
        // Keep the session and restart only the engine: deactivating it and starting a new recording from the
        // background is refused, which left the mic off for good after one interruption.
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            mic.stop()
            try mic.start()
            micSince = .now
            MicEvents.record("mic restarted")
        } catch {
            log.error("restart mic: \(error, privacy: .public)")
            MicEvents.record("restart failed: \(error)")
            await stopMic()
        }
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
        if voiceMode != nil, !busy, !checkingPause, ticks % 4 == 0 { // 5 times a second
            checkingPause = true
            Task {
                await checkPause()
                checkingPause = false
            }
        }
        guard !busy, let command = KeyboardHandoff.command(), command.id != lastCommand else { return }
        lastCommand = command.id
        busy = true
        Task {
            if command.record {
                // A start while recording replaces that recording: a double-tap's first tap may still be running.
                if phase == .recording {
                    await finishDictation(KeyboardHandoff.Command(id: UUID(), record: false, date: .now, mode: .cancel))
                }
                if phase == .ready {
                    await startDictation(since: (command.date ?? .now).addingTimeInterval(-0.15),
                                         voiceMode: command.continuous == true ? command : nil)
                }
            } else if phase == .recording {
                await finishDictation(command)
            }
            busy = false
        }
    }

    /// `since`: when the key went down. The mic's pre-roll covers the time until the model is ready.
    /// `voiceMode`: the start command of voice mode, which keeps listening and handles each phrase at a pause.
    private func startDictation(since: Date, voiceMode: KeyboardHandoff.Command? = nil) async {
        set(.recording)
        loadPickedModels() // freed while idle; reloading while the user speaks
        let audio = CommandAudio(micFormat: mic.format)
        do {
            // Experimental, for testing: Parakeet once it has loaded; Apple's Transcriber otherwise (the default).
            // Voice mode always uses Apple's, which ends phrases at pauses.
            let transcriber: any SpeechInput
            if voiceMode == nil, TranscriberModel.current == .parakeet, let parakeet = ParakeetTranscriber() {
                transcriber = parakeet
            } else if voiceMode != nil {
                transcriber = try await Transcriber { [weak self] text, time in
                    self?.phraseEnded(text, at: time, audio: audio, since: since)
                }
            } else {
                transcriber = try await Transcriber()
            }
            self.voiceMode = voiceMode
            segmentSince = since
            segmentHasSpeech = false
            let sink = try await transcriber.start(micFormat: mic.format)
            mic.attach({ sink($0); audio.append($0) }, since: since)
            self.transcriber = transcriber
            self.audio = audio
            cleaner = Cleaner() // prewarms the model while the user speaks
        } catch {
            log.error("start: \(error, privacy: .public)")
            self.voiceMode = nil
            set(.ready)
        }
    }

    private func finishDictation(_ command: KeyboardHandoff.Command) async {
        guard let transcriber else { return }
        mic.detach()
        self.transcriber = nil
        set(.processing)
        if voiceMode != nil {
            // The last phrase arrives as the model finishes; after a cancel (the keyboard closed) it's dropped.
            if command.mode == .cancel { voiceMode = nil }
            _ = try? await transcriber.stop()
            await phrases?.value
            voiceMode = nil
            phrases = nil
            audio = nil
        } else {
            let samples = audio?.samples ?? []
            audio = nil
            let released = command.date ?? .now // a stop command's date is when the key was let go
            let picked = Date.now
            do {
                let raw = try await transcriber.stop()
                await respond(to: raw, samples: samples, command: command, released: released, picked: picked,
                              transcribed: .now, asr: TranscriberModel.of(transcriber))
            } catch {
                log.error("finish: \(error, privacy: .public)")
            }
        }
        cleaner = nil
        set(.ready)
        scheduleIdleUnload()
    }

    /// Voice mode: the pause detector heard speech stop for 0.6 s. The recording is finished like a released key, and
    /// a new one starts from just before now, so nothing said meanwhile is lost. Apple's model takes 2–5 s to end a
    /// phrase on its own (iPad 10th gen); that still ends one the detector misses, as over a fan.
    private func checkPause() async {
        guard let audio, voiceMode != nil else { return }
        let seconds = Date.now.timeIntervalSince(segmentSince)
        guard seconds > 1 else { return }
        let chances = await CommandTranscriber.shared.speechProbabilities(audio.samples(from: seconds - 1, to: seconds))
        guard audio === self.audio, !busy else { return } // a cut or stop came first
        if chances.contains(where: { $0 > 0.5 }) { segmentHasSpeech = true }
        guard segmentHasSpeech, chances.count >= 19, !chances.suffix(19).contains(where: { $0 > 0.5 }), let old = transcriber
        else { return }
        busy = true
        mic.detach()
        transcriber = nil
        await startDictation(since: .now.addingTimeInterval(-0.3), voiceMode: voiceMode)
        _ = try? await old.stop() // its last phrase arrives through `phraseEnded`
        busy = false
    }

    /// Voice mode: a phrase is done, ended by the pause detector or by Apple's model. It's handled like a released
    /// press, in order, while listening goes on. Whisper gets the phrase's audio with a little margin.
    private func phraseEnded(_ raw: String, at time: ClosedRange<TimeInterval>, audio: CommandAudio, since: Date) {
        guard let voiceMode else { return }
        let samples = audio.samples(from: time.lowerBound - 0.2, to: time.upperBound + 0.3)
        let previous = phrases
        let arrived = Date.now, spoken = since.addingTimeInterval(time.upperBound)
        phrases = Task {
            await previous?.value
            let started = Date.now
            await respond(to: raw, samples: samples, command: voiceMode, released: .now, picked: .now,
                          transcribed: .now, asr: .apple)
            #if DEBUG
            func ms(_ from: Date, _ to: Date) -> Int { Int(to.timeIntervalSince(from) * 1000) }
            DictationHistory.note("voice timing: phrase done \(ms(spoken, arrived)) ms after the last word, waited \(ms(arrived, started)) ms, handled in \(ms(started, .now)) ms")
            #endif
        }
    }

    /// Types what was heard for `command`'s mode: a shortcut's keys, a spoken delete, a command, or cleaned text.
    private func respond(to raw: String, samples: [Float], command: KeyboardHandoff.Command, released: Date,
                         picked: Date, transcribed: Date, asr: TranscriberModel) async {
        switch command.mode ?? .dictate {
        case .dictate:
            if let shortcut = Shortcuts.match(raw) {
                remember(KeyboardHandoff.send(Shortcuts.expand(shortcut.keys), keys: true), "shortcut", heard: raw, typed: shortcut.keys)
                break
            }
            if let delete = SpokenDelete.match(raw) {
                remember(KeyboardHandoff.send("", delete: delete), "delete", heard: raw, typed: delete.rawValue)
                break
            }
            await typeCleaned(raw, released: released, picked: picked, transcribed: transcribed,
                              asr: asr, mode: "dictate")
        case .edit:
            // Empty text tells the keyboard the edit failed, so it leaves the field alone.
            let edited = await Editor.edit(command.text ?? "", instruction: raw) ?? ""
            remember(KeyboardHandoff.send(edited, edit: true), "edit", heard: raw, typed: edited)
        case .command:
            // Apple's transcript stays as another hearing. It often misses a short word ("exit"), so Whisper runs
            // even when Apple heard nothing. Whisper is for commands, which are short: on long speech it can
            // return one letter ("p"), so it's skipped there, and its words must roughly match Apple's count.
            var heard = [raw]
            let useWhisper = TerminalTranscriber.current == .whisper && Double(samples.count) <= 6 * CommandTranscriber.sampleRate
            let whispered = useWhisper ? await CommandTranscriber.shared.transcribe(samples, checkSpeech: raw.isEmpty) : nil
            #if DEBUG
            if TerminalTranscriber.current == .whisper, !useWhisper { DictationHistory.note("whisper skipped: over 6 s") }
            #endif
            let appleWords = raw.split(separator: " ").count
            if let whispered, case let words = whispered.split(separator: " ").count,
               words <= appleWords * 2 + 3, appleWords < 4 || words * 2 >= appleWords {
                heard.insert(whispered, at: 0)
            }
            // What either recognizer heard, also as a command ("demux find" → "tmux find"); a key named alone
            // ("enter") is a built-in shortcut.
            if let shortcut = heard.lazy.flatMap({ [$0, CommandWriter.command($0)] }).compactMap(Shortcuts.match).first
                ?? heard.lazy.compactMap(Shortcuts.key).first ?? heard.lazy.compactMap(Shortcuts.soundAlike).first {
                remember(KeyboardHandoff.send(Shortcuts.expand(shortcut.keys), keys: true), "shortcut", heard: raw,
                         whisper: whispered, typed: shortcut.keys)
                break
            }
            if let delete = SpokenDelete.match(heard[0]) ?? SpokenDelete.match(raw) {
                remember(KeyboardHandoff.send("", delete: delete), "delete", heard: raw, whisper: whispered, typed: delete.rawValue)
                break
            }
            // Nil means prose (e.g. a prompt for an agent in the terminal): typed like dictation, from Apple's
            // transcript, which hears prose better than the shell-primed Whisper.
            guard let written = await CommandWriter.write(heard: heard, screen: command.text ?? "") else {
                await typeCleaned(raw, released: released, picked: picked, transcribed: transcribed,
                                  asr: asr, mode: "terminal prose", whisper: whispered)
                break
            }
            if !written.isEmpty {
                remember(KeyboardHandoff.send(written, command: true), "command", heard: raw, whisper: whispered, typed: written)
            }
        case .cancel:
            break
        }
        log.notice("\((command.mode ?? .dictate).rawValue, privacy: .public): \(raw.count) chars")
    }

    /// Dictation: cleans the transcript, types it and copies it. The dates time the stages (`DictationTiming`).
    private func typeCleaned(_ raw: String, released: Date, picked: Date, transcribed: Date,
                             asr: TranscriberModel, mode: String, whisper: String? = nil) async {
        let text = await (cleaner ?? Cleaner()).clean(raw)
        let cleaned = Date.now
        if !text.isEmpty {
            let id = KeyboardHandoff.send(text, released: released)
            remember(id, mode, heard: raw, whisper: whisper, typed: text, cleanup: CleanupModel.last?.model.rawValue)
            copy(text)
            DictationTiming.record(released: released, picked: picked, transcribed: transcribed, cleaned: cleaned, id: id,
                                   asr: asr)
        }
    }

    /// Debug builds keep this device's dictations for tuning (`DictationHistory`); release builds have no such code.
    private func remember(_ id: UUID, _ mode: String, heard: String, whisper: String? = nil, typed: String, cleanup: String? = nil) {
        #if DEBUG
        DictationHistory.dictation(id: id, mode: mode, heard: heard, whisper: whisper, typed: typed, cleanup: cleanup)
        #endif
    }

    /// Big models held by a background app are what iOS kills first when it needs memory, and the mic goes with the
    /// app. So they're freed after two idle minutes and reloaded as soon as a press starts a dictation (cached, so
    /// usually ready by the time it ends; Apple's model covers one that isn't).
    private func scheduleIdleUnload() {
        idleUnload?.cancel()
        idleUnload = Task {
            try? await Task.sleep(for: .seconds(120))
            guard !Task.isCancelled, phase == .ready else { return }
            NeuralEngine.cleaner.unload()
            NeuralEngine.transcriber.unload()
            CPUCleaner.shared.unload()
            CommandTranscriber.shared.unload()
            MicEvents.record("models freed (idle)")
        }
    }

    private func loadPickedModels() {
        idleUnload?.cancel()
        if CleanupModel.current == .s1mini { NeuralEngine.cleaner.load() }
        if CleanupModel.current == .s1miniCPU { CPUCleaner.shared.preload() }
        if TranscriberModel.current == .parakeet { NeuralEngine.transcriber.load() }
        CommandTranscriber.shared.preload() // only if Whisper is picked and stays loaded on this device
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
