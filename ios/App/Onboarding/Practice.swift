import AVFoundation
import SwiftUI
import UIKit

/// In-app practice dictation for the Try-it reps: hold the strip's pill to record, let go to get cleaned text.
@MainActor @Observable
final class Practice {
    enum State { case idle, listening, processing }

    private(set) var state = State.idle
    /// Cleaned text per step, shown in that step's card.
    private(set) var results: [OnboardingStep: String] = [:]
    /// A short note under the card: nothing heard, a tap instead of a hold, an error.
    private(set) var hint: String?
    private(set) var micDenied = false
    /// Bumped to flash / shake the orb.
    private(set) var pulse = 0
    private(set) var shake = 0
    var target = OnboardingStep.tryEmail
    /// Called on the first hold while mic permission is undetermined (shows the 03a pre-prompt).
    var askPermission: () -> Void = {}

    private var starting: Task<Void, Never>?
    private var pressedAt = Date.distantPast
    private let impact = UIImpactFeedbackGenerator(style: .medium)
    private let notice = UINotificationFeedbackGenerator()

    func press() {
        guard state == .idle else { return }
        switch AVAudioApplication.shared.recordPermission {
        case .undetermined: return askPermission()
        case .denied:
            micDenied = true
            shake += 1
            notice.notificationOccurred(.error)
            return
        default: break
        }
        hint = nil
        micDenied = false
        state = .listening
        pressedAt = .now
        impact.impactOccurred()
        starting = Task {
            do { try await DictationController.shared.startInApp() } catch DictationController.InAppError.micDenied {
                micDenied = true
            } catch {
                hint = error.localizedDescription
            }
        }
    }

    func letGo() {
        guard state == .listening else { return }
        state = .processing
        impact.impactOccurred(intensity: 0.5)
        let tapped = Date.now.timeIntervalSince(pressedAt) < 0.4
        let step = target
        Task {
            await starting?.value
            let text = await DictationController.shared.finishInApp()
            state = .idle
            if let text, !text.isEmpty {
                results[step] = text
                pulse += 1
                notice.notificationOccurred(.success)
            } else {
                if !micDenied {
                    hint = tapped ? "Hold the bar while you speak, then let go." : "Didn't catch that. Hold the bar and try again."
                }
                shake += 1
                notice.notificationOccurred(.warning)
            }
        }
    }

    /// Clears the note when permission changes (e.g. after the pre-prompt).
    func clearHint() {
        hint = nil
        micDenied = AVAudioApplication.shared.recordPermission == .denied
    }
}

/// The in-app copy of the keyboard strip: delete, the live orb, the wide "Hold to talk" pill, globe, return.
struct PracticeStrip: View {
    let practice: Practice

    var body: some View {
        KeyboardStrip(bottom: 0) {
            StripButton(state: practice.state, pulse: practice.pulse, shake: practice.shake)
                .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity) {} onPressingChanged: { down in
                    down ? practice.press() : practice.letGo()
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Hold to talk")
                .accessibilityAddTraits(.isButton)
        }
        .background(Theme.field.ignoresSafeArea(edges: .bottom))
    }
}

/// The keyboard row: 44 pt keys with the orb + pill between them. As in the real keyboard, on iPhone the
/// pill fills the row; on iPad it is 420 pt, docked left / centre / right (Home's "Keyboard button").
struct KeyboardStrip<Control: View>: View {
    @Environment(\.wide) private var wide
    @AppStorage("buttonPosition") private var position = KeyboardHandoff.ButtonPosition.center.rawValue
    var bottom: CGFloat
    @ViewBuilder var button: Control

    var body: some View {
        let dock = KeyboardHandoff.ButtonPosition(rawValue: position) ?? .center
        HStack(spacing: 6) {
            KeyCap(symbol: "delete.left")
            if wide {
                if dock != .left { Spacer(minLength: 0) }
                button.frame(width: 420 + 36 + 8)
                if dock != .right { Spacer(minLength: 0) }
            } else {
                button
            }
            KeyCap(symbol: "globe")
            KeyCap(symbol: "return")
        }
        .frame(height: 56) // as the keyboard: 10 pt above and below the 36 pt pill
        .padding(.horizontal, 6)
        .padding(.bottom, bottom)
        .background(Theme.field)
        .overlay(alignment: .top) { Theme.stripBorder.frame(height: 1) }
    }
}

struct KeyCap: View {
    var symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 18, weight: .regular))
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .background(Theme.key, in: .rect(cornerRadius: 10))
            .accessibilityHidden(true)
    }
}

/// The orb just left of the pill, as tall as it (36 pt), then the pill with its centred label:
/// "Hold to talk" / "Listening…" / "Cleaning up…", as in the Keyboard strip states sheet.
struct StripButton: View {
    var state: Practice.State
    var pulse = 0
    var shake = 0

    var body: some View {
        let active = state != .idle
        HStack(spacing: 8) {
            Orb(phase: phase, pulse: pulse, shake: shake)
                .frame(width: 36, height: 36)
            Text(label).textStyle(TextStyle(size: 16, weight: .semibold, tracking: -0.01, lineHeight: 20))
                .contentTransition(.opacity)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background(active ? Theme.accent.opacity(0.2) : Theme.pill, in: .capsule)
                .overlay { if active { Capsule().strokeBorder(Theme.accent) } }
                .scaleEffect(active ? 0.97 : 1)
        }
        .frame(height: 56)
        .contentShape(.rect)
        .animation(.easeOut(duration: 0.2), value: state)
    }
    private var phase: KeyboardHandoff.Phase {
        switch state {
        case .idle: .ready
        case .listening: .recording
        case .processing: .processing
        }
    }

    private var label: String {
        switch state {
        case .idle: "Hold to talk"
        case .listening: "Listening…"
        case .processing: "Cleaning up…"
        }
    }
}
