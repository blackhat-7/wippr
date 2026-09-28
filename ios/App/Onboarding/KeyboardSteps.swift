import SwiftUI

/// 05 Turn on the keyboard: one trip to Settings (Keyboards → noboard, Allow Full Access, come back).
/// The guide video floats over Settings in PiP. The keyboard doesn't work at all without Full Access, and the app
/// can only see it once the keyboard has appeared with it on, so after the keyboard is added the user switches to
/// it in a box on this page; the step moves on only when Full Access is confirmed.
struct KeyboardStep: View {
    @Environment(\.wide) private var wide
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    /// Made on appear (not in init, which SwiftUI repeats).
    @State private var guide: GuidePlayer?
    @State private var wentToSettings = false
    @FocusState private var checking: Bool
    @State private var checkText = ""
    /// Back from Settings with the keyboard added.
    let added: () -> Void
    /// The keyboard was already added before this visit.
    let skip: () -> Void

    var body: some View {
        let status = SetupStatus.shared
        StepPage {
            if wide { Spacer(minLength: 24) }
            StepTitle(overline: "Keyboard · one trip to Settings", title: "Switch it on.")
            HStack(alignment: .top, spacing: wide ? 40 : 18) {
                PhoneGuide(guide: guide)
                instructions
            }
            .padding(.top, wide ? 40 : 20)
            .padding(.bottom, wide ? 32 : 16)
            VStack(alignment: .leading, spacing: wide ? 16 : 12) {
                whyFullAccess
                statusRow(added: status.keyboardAdded)
                if status.keyboardAdded {
                    fullAccessRow(on: status.fullAccess)
                    if !status.fullAccess { fullAccessCheck }
                }
            }
            .padding(.horizontal, wide ? 24 : 0)
            .padding(.bottom, 16)
            if wide { Spacer(minLength: 24) }
        } footer: {
            PrimaryButton(status.keyboardAdded && status.fullAccess ? "Continue" : "Open Settings") {
                if status.keyboardAdded, status.fullAccess { return skip() }
                checking = false
                wentToSettings = true
                guide?.startPiP()
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
        }
        .onAppear {
            if guide == nil { guide = GuidePlayer.make() }
            guide?.play()
        }
        .onDisappear { guide?.stop() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            guide?.stopPiP()
            check()
        }
        .task {
            // Also catches Settings side by side on iPad.
            while !Task.isCancelled {
                status.refresh()
                if scenePhase == .active { check() }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func check() {
        let status = SetupStatus.shared
        status.refresh()
        if status.keyboardAdded, status.fullAccess {
            // Confirmed: back from Settings, or the keyboard just appeared in the check box.
            if wentToSettings || checking {
                wentToSettings = false
                checking = false
                added()
            }
        } else if wentToSettings, status.keyboardAdded, !checking {
            checking = true // bring up a keyboard so the user can switch to noboard and confirm Full Access
        }
    }

    private var instructions: some View {
        VStack(alignment: .leading, spacing: wide ? 26 : 18) {
            Text("In Settings").textStyle(wide ? .overline(true) : .label, Theme.tertiary)
            SettingsStep(number: 1, title: "Keyboards", detail: "Turn on noboard")
            SettingsStep(number: 2, title: "Allow Full Access", detail: "Turn it on")
            SettingsStep(number: 3, title: "Come back", detail: "Tap \"‹ noboard\" at the top left", outlined: true)
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: guide == nil ? "arrow.uturn.backward" : "pip")
                    .font(.system(size: wide ? 14 : 12))
                    .foregroundStyle(Theme.secondary)
                    .padding(.top, 2)
                Text(guide == nil ? "noboard checks it when you're back" : "Stays on screen while you're in Settings")
                    .textStyle(wide ? TextStyle(size: 16, lineHeight: 22) : .caption, Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) { Theme.border.frame(height: 1) }
        }
        .padding(.top, wide ? 16 : 6)
    }

    private var whyFullAccess: some View {
        VStack(alignment: .leading, spacing: wide ? 12 : 8) {
            Text("Why Full Access? So the keyboard can tell the app to start and stop.")
                .textStyle(wide ? TextStyle(size: 20, weight: .semibold, tracking: -0.01, lineHeight: 28) : .rowStrong)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(["No network code in the keyboard", "Never sees passwords (iOS uses its own)", "Stores nothing you type"], id: \.self) {
                    Text("–  \($0)")
                }
            }
            .textStyle(TextStyle(size: wide ? 18 : 15, tracking: -0.01, lineHeight: wide ? 30 : 22), Theme.secondary)
            Text("iOS shows the same warning for every keyboard that asks.")
                .textStyle(wide ? TextStyle(size: 15, lineHeight: 20) : .caption, Theme.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, wide ? 24 : 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Theme.border.frame(height: 1) }
    }

    private func fullAccessRow(on: Bool) -> some View {
        HStack(spacing: 10) {
            Circle().fill(on ? Theme.success : Theme.mic).frame(width: 8, height: 8)
            Text(on ? "Full Access on" : "Full Access not confirmed")
                .textStyle(TextStyle(size: wide ? 17 : 15, weight: .medium, tracking: -0.01, lineHeight: 20))
            Spacer()
            Text(on ? "Done" : "Required").textStyle(.label, on ? Theme.success : Theme.mic)
        }
        .padding(.vertical, wide ? 18 : 14)
        .padding(.horizontal, wide ? 20 : 16)
        .card(radius: wide ? 20 : 16)
        .animation(.easeOut, value: on)
    }

    /// Tap in, switch to noboard with the globe key: with Full Access on, the keyboard marks itself seen and the
    /// step moves on. Without it, noboard's bar says "Tap to finish setting up noboard", which brings them back here.
    private var fullAccessCheck: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("noboard doesn't work without Full Access. To check it's on, tap below and switch to noboard with the globe key.")
                .textStyle(wide ? TextStyle(size: 16, lineHeight: 22) : .caption, Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField("", text: $checkText, prompt: Text("Tap here, then 🌐 to noboard").foregroundStyle(Theme.faint))
                .textStyle(TextStyle(size: 17, tracking: -0.01, lineHeight: 22))
                .tint(Theme.accent)
                .focused($checking)
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
                .background(Theme.surface, in: .rect(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(checking ? Theme.accent : Theme.border))
                .contentShape(.rect)
                .onTapGesture { checking = true }
        }
    }

    private func statusRow(added: Bool) -> some View {
        HStack(spacing: 10) {
            Circle().fill(added ? Theme.success : Theme.mic).frame(width: 8, height: 8)
            Text(added ? "Keyboard added" : "Keyboard not added yet")
                .textStyle(TextStyle(size: wide ? 17 : 15, weight: .medium, tracking: -0.01, lineHeight: 20))
            Spacer()
            Text(added ? "Done" : "Checking").textStyle(.label, added ? Theme.success : Theme.faint)
        }
        .padding(.vertical, wide ? 18 : 14)
        .padding(.horizontal, wide ? 20 : 16)
        .card(radius: wide ? 20 : 16)
        .animation(.easeOut, value: added)
    }
}

private struct SettingsStep: View {
    @Environment(\.wide) private var wide
    var number: Int
    var title: String
    var detail: String
    var outlined = false

    var body: some View {
        HStack(alignment: .top, spacing: wide ? 14 : 10) {
            Text("\(number)")
                .textStyle(TextStyle(size: 12, weight: .semibold, lineHeight: 16), outlined ? Theme.secondary : .black)
                .frame(width: wide ? 28 : 22, height: wide ? 28 : 22)
                .background(outlined ? .clear : .white, in: .circle)
                .overlay { if outlined { Circle().strokeBorder(Theme.faint, lineWidth: 1.5) } }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).textStyle(TextStyle(size: wide ? 20 : 15, weight: .semibold, lineHeight: wide ? 26 : 20))
                Text(detail).textStyle(TextStyle(size: wide ? 16 : 13, lineHeight: wide ? 22 : 18), Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// The phone-shaped frame: the guide video when bundled, otherwise a still of the Settings screen.
private struct PhoneGuide: View {
    @Environment(\.wide) private var wide
    let guide: GuidePlayer?

    var body: some View {
        let k: CGFloat = wide ? 200 / 132 : 1
        ZStack(alignment: .topLeading) {
            Group {
                if let guide {
                    GuideVideo(guide: guide)
                } else {
                    settings(k)
                }
            }
            .clipShape(.rect(cornerRadius: (wide ? 32 : 21)))
            .padding(wide ? 8 : 6)
            if guide == nil { annotations(k) }
        }
        .frame(width: 132 * k, height: 286 * k)
        .background(Color(hex: 0x0A0A0A), in: .rect(cornerRadius: wide ? 40 : 27))
        .overlay(RoundedRectangle(cornerRadius: wide ? 40 : 27).strokeBorder(Theme.dashed, lineWidth: 1.5))
        .shadow(color: Theme.accent.opacity(0.12), radius: 20)
        .accessibilityElement()
        .accessibilityLabel("Settings, Keyboards: turn on noboard and Allow Full Access")
    }

    private func settings(_ k: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8 * k) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left").font(.system(size: 7 * k, weight: .semibold))
                Text("noboard").font(.system(size: 9 * k))
            }
            .foregroundStyle(Theme.accent)
            Text("Keyboards").textStyle(TextStyle(size: 15 * k, weight: .bold, tracking: -0.02))
            VStack(spacing: 0) {
                row("noboard", k)
                Color(hex: 0x38383A).frame(height: 0.5)
                row("Allow Full Access", k)
            }
            .background(Theme.field, in: .rect(cornerRadius: 8))
            Spacer(minLength: 0)
        }
        .padding(.top, 30 * k)
        .padding(.horizontal, 7 * k)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.black)
    }

    private func row(_ title: String, _ k: CGFloat) -> some View {
        HStack {
            Text(title).font(.system(size: 8 * k)).foregroundStyle(.white).lineLimit(1).fixedSize()
            Spacer(minLength: 2)
            Capsule().fill(Theme.success)
                .frame(width: 22 * k, height: 13 * k)
                .overlay(alignment: .trailing) { Circle().fill(.white).padding(1.5) }
        }
        .padding(.leading, 7 * k)
        .padding(.trailing, 6 * k)
        .padding(.vertical, 7)
    }

    /// The back-link highlight ring, the GUIDE tag and the video's progress bar.
    private func annotations(_ k: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Circle().fill(Theme.accent.opacity(0.25))
                .overlay(Circle().strokeBorder(Theme.tint, lineWidth: 1.5))
                .frame(width: 30 * k, height: 30 * k)
                .offset(x: 10 * k, y: 7 * k)
            HStack(spacing: 2) {
                Image(systemName: "arrowtriangle.left.fill").font(.system(size: 4 * k))
                Text("noboard").font(.system(size: 8 * k, weight: .semibold))
            }
            .foregroundStyle(.white)
            .offset(x: 16 * k, y: 15 * k)
            HStack(spacing: 4) {
                Circle().fill(Theme.accent).frame(width: 5, height: 5)
                Text("Guide").textStyle(TextStyle(size: 8, weight: .semibold, tracking: 0.08, mono: true, caps: true), Theme.tint)
            }
            .padding(.vertical, 3)
            .padding(.horizontal, 7)
            .background(Theme.accent.opacity(0.22), in: .capsule)
            .offset(x: 72 * k, y: 14 * k)
            Capsule().fill(Theme.hairline)
                .frame(width: 92 * k, height: 3)
                .overlay(alignment: .leading) { Capsule().fill(.white).frame(width: 64 * k) }
                .offset(x: 20 * k, y: (286 - 18 - 3) * k)
        }
        .allowsHitTesting(false)
    }
}

/// 05b Back from Settings: the keyboard is on; moves on by itself after a few seconds.
struct KeyboardDoneStep: View {
    @Environment(\.wide) private var wide
    @State private var elapsed: Double = 0
    let next: () -> Void
    private let wait: Double = 3

    var body: some View {
        let status = SetupStatus.shared
        StepPage {
            StepTitle(overline: "Keyboard", title: "Welcome back.\nThe keyboard's on.")
            Spacer(minLength: 24)
            VStack(alignment: .leading, spacing: 28) {
                Image(systemName: "checkmark")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 112, height: 112)
                    .background(.white, in: .circle)
                    .background { Circle().fill(Theme.accent.opacity(0.35)).blur(radius: 40) }
                    .symbolEffect(.bounce, value: elapsed > 0)
                VStack(spacing: 0) {
                    doneRow("noboard keyboard", on: status.keyboardAdded, off: "Not added")
                    doneRow("Allow Full Access", on: status.fullAccess, off: "Not confirmed")
                        .overlay(alignment: .bottom) { Theme.border.frame(height: 1) }
                }
            }
            Spacer(minLength: 24)
        } footer: {
            HStack(spacing: 12) {
                GeometryReader { geo in
                    Capsule().fill(Theme.hairline)
                        .overlay(alignment: .leading) {
                            Capsule().fill(.white).frame(width: geo.size.width * min(elapsed / wait, 1))
                        }
                }
                .frame(height: 3)
                Text("Next in \(max(Int((wait - elapsed).rounded(.up)), 0))s").textStyle(.label, Theme.tertiary)
                    .monospacedDigit()
            }
            PrimaryButton("Continue", action: next)
        }
        .task {
            let start = Date.now
            while !Task.isCancelled, elapsed < wait {
                try? await Task.sleep(for: .milliseconds(50))
                elapsed = Date.now.timeIntervalSince(start)
            }
            if !Task.isCancelled { next() }
        }
    }

    private func doneRow(_ title: String, on: Bool, off: String) -> some View {
        HStack {
            Text(title).textStyle(TextStyle(size: 17, weight: .medium, lineHeight: 22))
            Spacer()
            Text(on ? "On" : off).textStyle(TextStyle(size: 12, weight: .medium, tracking: 0.08, lineHeight: 16, mono: true, caps: true),
                                            on ? Theme.success : Theme.tertiary)
        }
        .padding(.vertical, 12)
        .overlay(alignment: .top) { Theme.border.frame(height: 1) }
    }
}
