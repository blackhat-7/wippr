import SwiftUI

/// 06 Turn on the mic: the app listens for the keyboard, so the mic stays on in the background.
struct MicStep: View {
    @Environment(\.wide) private var wide
    let next: () -> Void

    var body: some View {
        StepPage {
            StepTitle(overline: "Background mic", title: "Turn the mic on.\nLeave it on.",
                      message: "iOS doesn't let keyboards use the microphone, so the noboard app listens for them. Turn it on once and it stays on in the background.")
            Spacer(minLength: 32)
            MicCard(large: true)
                .background { Capsule().fill(Theme.accent.opacity(0.18)).blur(radius: 40) }
                .padding(.horizontal, wide ? 0 : -8)
            Spacer(minLength: 32)
            VStack(spacing: 0) {
                SpecRow(label: "Orange dot", value: "Shown while on")
                SpecRow(label: "Music", value: "Keeps playing")
                SpecRow(label: "Turn off", value: "Anytime, in noboard")
                    .overlay(alignment: .bottom) { Theme.border.frame(height: 1) }
                Text("Speech becomes text only while you hold the key.")
                    .textStyle(.caption, Theme.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 12)
            }
            .padding(.bottom, 20)
        } footer: {
            PrimaryButton("Continue", action: next)
        }
    }
}

/// 07 Try the real keyboard: a field that brings up the noboard keyboard itself.
struct RealKeyboardStep: View {
    @Environment(\.wide) private var wide
    @FocusState private var focused: Bool
    @State private var text = ""
    let finish: () -> Void

    var body: some View {
        StepPage {
            StepTitle(overline: "The real keyboard", title: "Now for real.",
                      message: "This time it's the noboard keyboard, the same one you'll use in every app.")
            TextField("", text: $text, prompt: Text("Say anything…").foregroundStyle(Theme.faint), axis: .vertical)
                .textStyle(TextStyle(size: 20, tracking: -0.015, lineHeight: 28))
                .tint(Theme.accent)
                .focused($focused)
                .lineLimit(4...)
                .padding(.vertical, 18)
                .padding(.horizontal, 20)
                .frame(minHeight: 180, alignment: .topLeading)
                .background(Theme.surface, in: .rect(cornerRadius: 24))
                .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Theme.accent))
                .background(RoundedRectangle(cornerRadius: 24).stroke(Theme.accent.opacity(0.15), lineWidth: 8))
                .contentShape(.rect)
                .onTapGesture { focused = true }
                .padding(.top, 28)
            VStack(alignment: .leading, spacing: 8) {
                Text("Then slide up and try").textStyle(.label, Theme.tertiary)
                Text("\"Make it more formal\"")
                Text("\"Turn it into bullets\"")
            }
            .textStyle(TextStyle(size: 17, weight: .medium, tracking: -0.01, lineHeight: 24), Theme.editText)
            .padding(.top, 20)
            .padding(.horizontal, 4)
            Spacer(minLength: 24)
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "globe")
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Theme.field, in: .circle)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Don't see noboard?").textStyle(.rowStrong)
                    Text("Tap the globe key until the \"Hold to talk\" bar appears.")
                        .textStyle(.row, Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.bottom, 12)
        } footer: {
            PrimaryButton("Finish setup") {
                focused = false
                finish()
            }
        }
        .onAppear { focused = true }
    }
}
