import AVFoundation
import SwiftUI

/// 03 / 04 Try it: say the prompt while holding the strip below; the cleaned text lands in the card.
struct PracticeStep: View {
    enum Exercise {
        case email, notes

        var step: OnboardingStep { self == .email ? .tryEmail : .tryNotes }
    }

    @Environment(\.wide) private var wide
    @Environment(\.openURL) private var openURL
    let exercise: Exercise
    let practice: Practice
    let next: () -> Void

    var body: some View {
        let result = practice.results[exercise.step]
        StepPage {
            StepTitle(overline: exercise == .email ? "Try it · 1 of 2" : "Try it · 2 of 2",
                      title: exercise == .email ? "Write an email." : "Make a list.",
                      message: "Hold the bar below and say it just like this:")
            VStack(alignment: .leading, spacing: 12) {
                prompt
                output(result)
                note(result)
            }
            .padding(.top, 24)
            .padding(.bottom, 16)
            .animation(.easeOut(duration: 0.25), value: result)
        } footer: {
            PrimaryButton(exercise == .email ? "Next" : "Continue", action: next)
                .disabled(practice.state != .idle)
        }
    }

    private var prompt: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Say").textStyle(.label, Theme.faint)
            Text(exercise == .email
                 ? "\"hey tim um would love to connect friday at 3pm actually 4pm\""
                 : "\"things to do today order groceries call mom and uh book the dentist\"")
                .textStyle(TextStyle(size: 16, tracking: -0.01, lineHeight: 22, italic: true), Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.dashed, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
    }

    private func output(_ result: String?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(exercise == .email ? "To:" : "Notes").textStyle(.row, Theme.faint)
                Text(exercise == .email ? "Tim Okafor" : "Today").textStyle(TextStyle(size: 15, weight: .medium, lineHeight: 20))
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) { Theme.border.frame(height: 1) }
            HStack(alignment: .bottom, spacing: 2) {
                if let result {
                    Text(result).textStyle(.body(false))
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                }
                Caret()
                Spacer(minLength: 0)
            }
            .frame(minHeight: 72, alignment: .bottomLeading)
            .padding(.top, 14)
            .padding(.bottom, 18)
            .padding(.horizontal, 16)
        }
        .card(radius: 20)
    }

    @ViewBuilder private func note(_ result: String?) -> some View {
        if practice.micDenied {
            HStack(spacing: 8) {
                Text("Microphone access is off.").textStyle(.caption, Theme.mic)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .textStyle(TextStyle(size: 13, weight: .semibold, lineHeight: 18), .white)
            }
            .padding(.top, 8)
            .padding(.horizontal, 4)
        } else if let hint = practice.hint {
            Text(hint).textStyle(.caption, Theme.secondary)
                .padding(.top, 8)
                .padding(.horizontal, 4)
        } else if exercise == .notes, result != nil {
            HStack(spacing: 12) {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(.black)
                    .frame(width: 28, height: 28)
                    .background(.white, in: .circle)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Nice — that's noboard.").textStyle(TextStyle(size: 20, weight: .bold, tracking: -0.02, lineHeight: 26))
                    Text("Fillers gone, list formatted, all on-device.").textStyle(.row, Theme.secondary)
                }
            }
            .padding(.top, 12)
            .padding(.horizontal, 4)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        } else if exercise == .email, SetupStatus.shared.micPermission == .undetermined {
            HStack(spacing: 8) {
                Image(systemName: "mic").font(.system(size: 12)).foregroundStyle(Theme.tertiary)
                Text("Your first hold asks for the microphone. Audio stays on this \(deviceName).")
                    .textStyle(.caption, Theme.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 8)
            .padding(.horizontal, 4)
        }
    }
}

/// 03a The pre-prompt before iOS's microphone alert: what's on-device (Apple's speech model and
/// Apple Intelligence), then the system prompt and the speech-model download.
struct MicPermissionStep: View {
    @Environment(\.wide) private var wide
    @State private var working = false
    let done: () -> Void

    var body: some View {
        StepPage {
            StepTitle(overline: "Microphone", title: "Your voice stays\non this \(deviceName).",
                      message: "noboard needs the microphone to hear you. Apple's on-device models do the rest, on your \(deviceName).")
            Spacer(minLength: 16)
            ZStack {
                Circle().strokeBorder(Theme.border).frame(width: 184, height: 184)
                Circle().strokeBorder(Theme.stripBorder).frame(width: 136, height: 136)
                Circle().fill(RadialGradient(colors: [Theme.accent.opacity(0.35), .clear], center: .center, startRadius: 30, endRadius: 100))
                    .frame(width: 200, height: 200)
                Orb(phase: working ? .processing : .recording)
                    .frame(width: 88, height: 88)
            }
            .frame(maxWidth: .infinity)
            Spacer(minLength: 24)
            VStack(spacing: 0) {
                SpecRow(label: "Recognition", value: "Apple · on-device")
                SpecRow(label: "Cleanup", value: Cleaner.engine ?? "Off on this \(deviceName)")
                SpecRow(label: "Audio sent anywhere", value: "Never")
                    .overlay(alignment: .bottom) { Theme.border.frame(height: 1) }
                Text(working ? "Downloading Apple's speech model…" : "The first time, iOS downloads Apple's speech model.")
                    .textStyle(.caption, Theme.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 12)
            }
            .padding(.bottom, 20)
        } footer: {
            PrimaryButton(working ? "Setting up…" : "Allow microphone") {
                working = true
                Task {
                    _ = await SetupStatus.shared.recheck()
                    working = false
                    done()
                }
            }
            .disabled(working)
        }
    }
}
