import ActivityKit
import AVFoundation
import UIKit

/// Owns one dictation at a time: Live Activity → mic → transcript → cleanup → clipboard.
@MainActor
final class DictationController {
    typealias State = DictationAttributes.ContentState

    static let shared = DictationController()

    private var phase: State.Phase = .ready
    private var transcriber: Transcriber?
    private var cleaner: Cleaner?
    private var pendingCopy: String?
    private var lastPreview = Date.distantPast

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
        if phase == .ready, Self.activity == nil {
            try? await show(State(phase: .ready, text: "", copied: true))
        }
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
            return text
        } catch {
            await reset()
            throw error
        }
    }

    /// Returns false when iOS refused the write (it can while the app is in the background).
    private func copy(_ text: String) -> Bool {
        guard !text.isEmpty else { return true }
        let before = UIPasteboard.general.changeCount
        UIPasteboard.general.string = text
        let copied = UIPasteboard.general.changeCount != before
        pendingCopy = copied ? nil : text
        return copied
    }

    private func preview(_ text: String) {
        guard phase == .recording, Date.now.timeIntervalSince(lastPreview) > 0.5 else { return }
        lastPreview = .now
        Task { try? await show(State(phase: .recording, text: text, copied: true)) }
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
