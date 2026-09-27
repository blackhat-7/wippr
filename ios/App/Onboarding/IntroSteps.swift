import SwiftUI

/// 01 Welcome: the mark in a soft blue glow, the name and the promise.
struct WelcomeStep: View {
    @Environment(\.wide) private var wide
    let next: () -> Void

    var body: some View {
        StepPage {
            if wide { Spacer(minLength: 32) } else { Spacer(minLength: 24) }
            VStack(alignment: .leading, spacing: wide ? 40 : 32) {
                Logo(size: wide ? 232 : 168)
                    .background { glow.offset(x: wide ? 0 : 16, y: wide ? 110 : 60) }
                VStack(alignment: .leading, spacing: wide ? 16 : 12) {
                    Text("noboard").textStyle(.display(wide))
                    Text("Hold, speak, let go.\nClean text in any app.").textStyle(.tagline(wide), Theme.secondary)
                }
            }
            .padding(.bottom, wide ? 0 : 32)
            if wide { Spacer(minLength: 32) }
        } footer: {
            PrimaryButton("Get started", action: next)
            VStack(spacing: 4) {
                Text("Powered by Apple Intelligence")
                Text("On-device · Audio never leaves your \(deviceName)")
            }
            .textStyle(TextStyle(size: wide ? 12 : 11, weight: .medium, tracking: 0.08, lineHeight: 16, mono: true, caps: true), Theme.tertiary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
        }
    }

    /// The design's radial glow: accent at 28 % → 8 % at 40 % → clear at 70 % of the circle's corner distance.
    private var glow: some View {
        let side: CGFloat = wide ? 600 : 420
        return RadialGradient(stops: [
            .init(color: Theme.accent.opacity(0.28), location: 0),
            .init(color: Theme.accent.opacity(0.08), location: 0.4),
            .init(color: Theme.accent.opacity(0), location: 0.7),
        ], center: .center, startRadius: 0, endRadius: side / 2 * 1.414)
        .frame(width: side, height: side)
        .allowsHitTesting(false)
    }
}

/// 02 How it works: a message field being filled by the keyboard strip, and the slide-up edit.
struct HowItWorksStep: View {
    @Environment(\.wide) private var wide
    let next: () -> Void

    var body: some View {
        StepPage {
            StepTitle(overline: "How it works", title: "Hold. Speak.\nLet go.",
                      message: "Clean text is typed into whatever field you're in. Apple Intelligence fixes fillers, punctuation and mishearings, on your \(deviceName).")
            Spacer(minLength: 32)
            demo.padding(.horizontal, wide ? 0 : -8)
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.editStroke)
                    .frame(width: 32, height: 32)
                    .background(Theme.edit.opacity(0.16), in: .circle)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Slide up to edit").textStyle(.rowStrong)
                    Text("While holding, slide up and say \"make it more formal\". noboard rewrites what's there.")
                        .textStyle(.row, Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 24)
            .padding(.bottom, 16)
        } footer: {
            PrimaryButton("Continue", action: next)
        }
    }

    private var demo: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Message · Maya").textStyle(.label, Theme.faint)
                HStack(alignment: .bottom, spacing: 2) {
                    Text("Running ten minutes late, save me a seat by the window?")
                        .textStyle(.body(false))
                        .fixedSize(horizontal: false, vertical: true)
                    Caret()
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .background(Theme.field, in: .rect(cornerRadius: 20))
            }
            .padding(.top, 20)
            .padding(.bottom, 24)
            .padding(.horizontal, 20)
            KeyboardStrip(bottom: 0) {
                StripButton(state: .idle)
            }
        }
        .clipShape(.rect(cornerRadius: 28))
        .card(radius: 28)
    }
}

/// The blue text cursor, blinking.
struct Caret: View {
    var height: CGFloat = 22

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.55)) { context in
            RoundedRectangle(cornerRadius: 1)
                .fill(Theme.accent)
                .frame(width: 2, height: height)
                .opacity(Int(context.date.timeIntervalSinceReferenceDate / 0.55) % 2 == 0 ? 1 : 0)
        }
        .accessibilityHidden(true)
    }
}
