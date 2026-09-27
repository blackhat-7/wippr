import ActivityKit
import AVFoundation
import os
import UIKit

/// Owns one dictation at a time: Live Activity → mic → transcript → cleanup → clipboard + wippr keyboard.
/// Optionally listens all the time and dictates whatever follows "wipper".
@MainActor
final class DictationController {
    typealias State = DictationAttributes.ContentState

    static let shared = DictationController()

    private var phase: State.Phase = .ready
    private var transcriber: Transcriber?
    private var cleaner: Cleaner?
    private var pendingCopy: String?
    private var lastPreview = Date.distantPast
    private let log = Logger(subsystem: "cx.immortal.wippr", category: "dictation")

    // Always-on listening
    private var listener: Transcriber?
    private var heard = "" // everything transcribed since listening started
    private var consumed = 0 // characters of `heard` already handled
    private var wakeEnd: Task<Void, Never>?
    private var listeningSince = Date.distantPast
    /// "wipper" and the ways the recognizer spells it.
    private static let wakeWord = try! Regex(#"(?i)\b(?:wh?ipp?e?r|wippa|vipper)\b[\s,.:;!?-]*"#)
    private static let endOfSpeech: Duration = .seconds(1.5)
    static var listenEnabled: Bool { UserDefaults.standard.bool(forKey: "listen") }

    private init() {
        // Calls, Siri, route changes and media resets stop the engine; restart listening afterwards.
        for name in [AVAudioSession.interruptionNotification, .AVAudioEngineConfigurationChange,
                     AVAudioSession.mediaServicesWereResetNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { note in
                let type = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                guard type != AVAudioSession.InterruptionType.began.rawValue else { return }
                Task { @MainActor in await DictationController.shared.restartListening() }
            }
        }
    }

    /// Starts dictation and returns nil, or stops it and returns the cleaned text.
    func toggle() async throws -> String? {
        switch phase {
        case .ready:
            try await start()
            return nil
        case .recording:
            return try await finish()
        case .processing:
            return nil
        case .listening:
            if wakeEnd != nil { // stop tapped while dictating after "wipper"
                wakeEnd?.cancel()
                await endWakeDictation()
            } else {
                await stopListening()
            }
            return nil
        }
    }

    /// One-time setup, run from the app in the foreground.
    /// Returns the problems that block or degrade dictation; empty means ready.
    func setUp() async -> [String] {
        var problems: [String] = []
        if !(await AVAudioApplication.requestRecordPermission()) {
            problems.append("Microphone access is off. Turn it on in Settings → wippr.")
        }
        if !ActivityAuthorizationInfo().areActivitiesEnabled {
            problems.append("Live Activities are off. Turn them on in Settings → wippr.")
        }
        do {
            try await Transcriber.installAssets()
        } catch {
            problems.append("Speech model unavailable: \(error.localizedDescription)")
        }
        if !Cleaner.isAvailable {
            problems.append("Apple Intelligence is unavailable, so text is copied without cleanup.")
        }
        await appDidBecomeActive()
        return problems
    }

    /// Retries a refused clipboard write and brings back the island if iOS ended it (8-hour cap).
    func appDidBecomeActive() async {
        if let pendingCopy {
            UIPasteboard.general.string = pendingCopy
            self.pendingCopy = nil
            if let activity = Self.activity, activity.content.state.phase == .ready {
                var state = activity.content.state
                state.copied = true
                await activity.update(ActivityContent(state: state, staleDate: nil))
            }
        }
        if phase == .ready, Self.listenEnabled {
            do { try await startListening() } catch { log.error("listen: \(error, privacy: .public)") }
        }
        if phase == .ready, Self.activity == nil {
            try? await show(State(phase: .ready, text: "", copied: true))
        }
    }

    /// Turns always-on listening on or off. Turning it on must happen in the foreground.
    func setListening(_ on: Bool) async throws {
        UserDefaults.standard.set(on, forKey: "listen")
        if on { try await startListening() } else { await stopListening() }
    }

    private func start() async throws {
        phase = .recording
        do {
            // AudioRecordingIntent stops recording unless a Live Activity is running first.
            try await show(State(phase: .recording, text: "", copied: true))
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .default)
            try session.setActive(true)
            let transcriber = try await Transcriber { [weak self] text in
                Task { @MainActor in self?.preview(text) }
            }
            try await transcriber.start()
            self.transcriber = transcriber
            cleaner = Cleaner() // prewarms the model while the user speaks
        } catch {
            await reset()
            throw error
        }
    }

    private func finish() async throws -> String? {
        guard let transcriber else { return nil } // still starting
        self.transcriber = nil
        phase = .processing
        do {
            try await show(State(phase: .processing, text: "", copied: true))
            let raw = try await transcriber.stop()
            let text = await (cleaner ?? Cleaner()).clean(raw)
            let copied = copy(text)
            cleaner = nil
            phase = .ready
            try await show(State(phase: .ready, text: text, copied: copied))
            deactivateAudio()
            if Self.listenEnabled { try? await startListening() }
            return text
        } catch {
            await reset()
            throw error
        }
    }

    /// Returns false when iOS refused the write (it can while the app is in the background).
    private func copy(_ text: String) -> Bool {
        guard !text.isEmpty else { return true }
        KeyboardHandoff.send(text)
        let before = UIPasteboard.general.changeCount
        UIPasteboard.general.string = text
        let copied = UIPasteboard.general.changeCount != before
        pendingCopy = copied ? nil : text
        return copied
    }

    private func preview(_ text: String) {
        guard phase == .recording || phase == .listening, Date.now.timeIntervalSince(lastPreview) > 0.5 else { return }
        lastPreview = .now
        Task { try? await show(State(phase: .recording, text: text, copied: true)) }
    }

    // MARK: Always-on listening

    private func startListening() async throws {
        guard phase == .ready, listener == nil else { return }
        let session = AVAudioSession.sharedInstance()
        // Mixable, so music and other audio keep playing while wippr listens.
        try session.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers, .defaultToSpeaker, .allowBluetoothA2DP])
        try session.setActive(true)
        heard = ""
        consumed = 0
        let listener = try await Transcriber { [weak self] text in
            Task { @MainActor in self?.hear(text) }
        }
        try await listener.start()
        self.listener = listener
        listeningSince = .now
        phase = .listening
        cleaner = Cleaner()
        try? await show(State(phase: .listening, text: "", copied: true))
        log.info("listening")
    }

    private func stopListening() async {
        wakeEnd?.cancel()
        wakeEnd = nil
        let listener = self.listener
        self.listener = nil
        _ = try? await listener?.stop()
        if phase == .listening { await reset() }
        log.info("stopped listening")
    }

    private func restartListening() async {
        // Starting the engine can itself post a configuration change.
        guard listener != nil, Date.now.timeIntervalSince(listeningSince) > 2 else { return }
        await stopListening()
        do { try await startListening() } catch { log.error("relisten: \(error, privacy: .public)") }
    }

    /// Waits for "wipper", then for the speaker to pause.
    private func hear(_ text: String) {
        heard = text
        guard phase == .listening else { return }
        let new = text.dropFirst(consumed)
        guard let wake = new.firstMatch(of: Self.wakeWord) else { return }
        let spoken = String(new[wake.range.upperBound...])
        log.debug("heard: \(spoken, privacy: .public)")
        preview(spoken)
        wakeEnd?.cancel()
        // Give the speaker longer to start than to pause.
        let wait = spoken.isEmpty ? Duration.seconds(5) : Self.endOfSpeech
        wakeEnd = Task { [weak self] in
            try? await Task.sleep(for: wait)
            guard !Task.isCancelled else { return }
            await self?.endWakeDictation()
        }
    }

    private func endWakeDictation() async {
        wakeEnd = nil
        let new = heard.dropFirst(consumed)
        guard let wake = new.firstMatch(of: Self.wakeWord) else { return }
        let raw = String(new[wake.range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        // Leave some slack: the recognizer can still revise the last words.
        consumed = max(heard.count - 12, heard.distance(from: heard.startIndex, to: wake.range.upperBound))
        guard !raw.isEmpty else {
            try? await show(State(phase: .listening, text: "", copied: true))
            return
        }
        try? await show(State(phase: .processing, text: "", copied: true))
        let text = await (cleaner ?? Cleaner()).clean(raw)
        cleaner = Cleaner() // a session keeps its history; start fresh for the next dictation
        let copied = copy(text)
        log.info("wake dictation: \(raw.count) chars")
        try? await show(State(phase: .listening, text: text, copied: copied))
    }

    private func reset() async {
        transcriber = nil
        cleaner = nil
        phase = .ready
        try? await show(State(phase: .ready, text: "", copied: true))
        deactivateAudio()
    }

    private func deactivateAudio() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Updates the island, or starts it if there is none.
    private func show(_ state: State) async throws {
        var state = state
        state.text = String(state.text.suffix(300)) // Live Activity payloads are capped at 4 KB
        let content = ActivityContent(state: state, staleDate: nil)
        if let activity = Self.activity {
            await activity.update(content)
        } else {
            _ = try Activity.request(attributes: DictationAttributes(), content: content)
        }
    }

    private static var activity: Activity<DictationAttributes>? {
        Activity<DictationAttributes>.activities.first { $0.activityState == .active }
    }
}
