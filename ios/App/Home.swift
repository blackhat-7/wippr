import SwiftUI

/// 08 Home: mic switch, keyboard and cleanup status, tips. On iPad (regular width) a 720 pt column with
/// two-column cards, a privacy card and the keyboard-button position.
struct HomeView: View {
    @Environment(\.wide) private var wide
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("buttonPosition") private var buttonPosition = KeyboardHandoff.ButtonPosition.center.rawValue
    /// Re-check found the keyboard missing: go back through the keyboard steps.
    let reopenSetup: () -> Void

    var body: some View {
        let status = SetupStatus.shared
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header(status)
                VStack(alignment: .leading, spacing: wide ? 10 : 8) {
                    Text("Ready to talk.").textStyle(wide ? TextStyle(size: 64, weight: .bold, tracking: -0.04, lineHeight: 68) : .title(false))
                    Text("Switch to noboard in any app and hold.")
                        .textStyle(wide ? TextStyle(size: 20, tracking: -0.01, lineHeight: 28) : .body(false), Theme.secondary)
                }
                .padding(.top, wide ? 72 : 28)
                .padding(.bottom, wide ? 40 : 24)
                .padding(.horizontal, wide ? 0 : 8)
                cards(status)
                problems(status)
                tips
            }
            .padding(.horizontal, wide ? 0 : 16)
            .padding(.top, wide ? 24 : 0)
            .padding(.bottom, 32)
            .frame(maxWidth: wide ? 720 : .infinity)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Theme.background)
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active { status.refresh() }
        }
        .onChange(of: buttonPosition, initial: true) { _, position in
            KeyboardHandoff.setButtonPosition(KeyboardHandoff.ButtonPosition(rawValue: position) ?? .center)
        }
    }

    private func header(_ status: SetupStatus) -> some View {
        HStack {
            HStack(spacing: 10) {
                Logo(size: 28, weight: 72)
                Text("noboard").textStyle(TextStyle(size: 20, weight: .bold, tracking: -0.035, lineHeight: 24))
            }
            Spacer()
            Button {
                Task {
                    _ = await status.recheck()
                    if !status.keyboardAdded { reopenSetup() }
                }
            } label: {
                HStack(spacing: 6) {
                    if status.checking { ProgressView().controlSize(.small).tint(Theme.secondary) }
                    Text(status.checking ? "Checking…" : "Re-check setup")
                        .textStyle(TextStyle(size: 15, weight: .medium, lineHeight: 20), Theme.secondary)
                }
                .frame(minHeight: 44)
                .contentShape(.rect)
            }
            .buttonStyle(PressStyle())
            .disabled(status.checking)
        }
        .frame(height: 44)
        .padding(.top, 8)
        .padding(.horizontal, wide ? 0 : 8)
    }

    @ViewBuilder private func cards(_ status: SetupStatus) -> some View {
        let keyboard = StatusCard(
            label: "Keyboard", ok: status.keyboardAdded && status.fullAccess,
            title: status.keyboardAdded ? "Added" : "Not added",
            detail: !status.keyboardAdded ? "Tap Re-check setup to add it"
                : status.fullAccess ? "Full Access on" : "Open it once to confirm Full Access")
        let cleanup = StatusCard(
            label: "Cleanup", ok: status.cleanupAvailable,
            title: status.cleanupAvailable ? "On-device" : "Off",
            detail: status.cleanupAvailable ? "Apple Intelligence · on-device"
                : "Not available on this device · text is typed without cleanup")
        if wide {
            VStack(spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    MicCard()
                    keyboard
                }
                .fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .top, spacing: 12) {
                    cleanup
                    StatusCard(label: "Privacy", ok: true, title: "Audio stays here", detail: "Nothing leaves this \(deviceName)")
                }
                .fixedSize(horizontal: false, vertical: true)
                ButtonPositionCard(position: $buttonPosition)
            }
        } else {
            VStack(spacing: 10) {
                MicCard()
                HStack(spacing: 10) {
                    keyboard
                    cleanup
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private func problems(_ status: SetupStatus) -> some View {
        if let problems = status.problems {
            VStack(alignment: .leading, spacing: 8) {
                if problems.isEmpty {
                    Label("Everything's set up.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Theme.success)
                }
                ForEach(problems, id: \.self) {
                    Label($0, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.mic)
                }
            }
            .textStyle(.caption)
            .padding(.top, 16)
            .padding(.horizontal, wide ? 0 : 8)
        }
    }

    private var tips: some View {
        let items = [
            Tip(icon: AnyView(OrbDot(size: 22)), title: "Hold to talk", detail: "Let go and clean text is typed in."),
            Tip(icon: AnyView(TipIcon(symbol: "arrow.up", color: Theme.editStroke, fill: Theme.edit.opacity(0.16))),
                title: "Slide up to edit", detail: "\"Make it shorter\", \"turn into bullets\"."),
            Tip(icon: AnyView(TipIcon(symbol: "arrow.uturn.backward", color: .white, fill: Theme.field)),
                title: "Undo an edit", detail: "Tap the bar within 5 seconds."),
        ]
        return VStack(alignment: .leading, spacing: wide ? 12 : 8) {
            Text("Tips").textStyle(.label, Theme.tertiary)
            if wide {
                HStack(alignment: .top, spacing: 32) {
                    ForEach(items) { tip in
                        VStack(alignment: .leading, spacing: 14) {
                            tip.icon.frame(width: 32, height: 32)
                            tip.text
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.top, 24)
                .overlay(alignment: .top) { Theme.border.frame(height: 1) }
            } else {
                VStack(spacing: 0) {
                    ForEach(items) { tip in
                        HStack(spacing: 14) {
                            tip.icon.frame(width: 32, height: 32)
                            tip.text
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 12)
                        .overlay(alignment: .bottom) {
                            if tip.id != items.last?.id { Theme.border.frame(height: 1) }
                        }
                    }
                }
            }
        }
        .padding(.top, wide ? 44 : 32)
        .padding(.horizontal, wide ? 0 : 8)
    }
}

private struct Tip: Identifiable {
    var icon: AnyView
    var title: String
    var detail: String
    var id: String { title }

    var text: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).textStyle(TextStyle(size: 16, weight: .semibold, tracking: -0.01, lineHeight: 21))
            Text(detail).textStyle(TextStyle(size: 14, lineHeight: 19), Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct TipIcon: View {
    var symbol: String
    var color: Color
    var fill: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: 32, height: 32)
            .background(fill, in: .circle)
    }
}

/// A small status card: caps label + badge on top, title and detail at the bottom.
private struct StatusCard: View {
    var label: String
    var ok: Bool
    var title: String
    var detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text(label).textStyle(.label, Theme.tertiary)
                Spacer()
                StatusBadge(ok: ok)
            }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).textStyle(TextStyle(size: 17, weight: .semibold, tracking: -0.01, lineHeight: 22))
                Text(detail).textStyle(.caption, Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .frame(minHeight: 134)
        .card(radius: 24)
    }
}

/// iPad: where the keyboard's 420 pt "Hold to talk" button sits (Left / Center / Right), with a preview.
private struct ButtonPositionCard: View {
    @Binding var position: String

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Keyboard button · iPad").textStyle(.label, Theme.tertiary)
                    Text("Where \"Hold to talk\" sits").textStyle(TextStyle(size: 17, weight: .semibold, tracking: -0.01, lineHeight: 22))
                }
                Spacer()
                segments
            }
            preview
            Text("On iPad the button is 420 pt wide so your thumb can reach it. On iPhone it always fills the row.")
                .textStyle(.caption, Theme.tertiary)
        }
        .padding(22)
        .card(radius: 28)
    }

    private var segments: some View {
        HStack(spacing: 0) {
            ForEach(KeyboardHandoff.ButtonPosition.allCases, id: \.self) { option in
                let selected = option.rawValue == position
                Button {
                    position = option.rawValue
                } label: {
                    Text(option.rawValue.capitalized)
                        .textStyle(TextStyle(size: 15, weight: selected ? .semibold : .medium, lineHeight: 20), selected ? .white : Theme.secondary)
                        .frame(width: 84, height: 34)
                        .background(selected ? Theme.key : .clear, in: .rect(cornerRadius: 9))
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Theme.field, in: .rect(cornerRadius: 12))
        .animation(.easeOut(duration: 0.2), value: position)
        .sensoryFeedback(.selection, trigger: position)
        .accessibilityRepresentation {
            Picker("Keyboard button", selection: $position) {
                ForEach(KeyboardHandoff.ButtonPosition.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0.rawValue) }
            }
        }
    }

    /// A scaled-down keyboard row showing the pill at the chosen position.
    private var preview: some View {
        let current = KeyboardHandoff.ButtonPosition(rawValue: position) ?? .center
        return HStack(spacing: 6) {
            miniKey("delete.left")
            if current != .left { Spacer(minLength: 0) }
            // As on the keyboard: the orb just left of the pill, as tall as it.
            HStack(spacing: 8) {
                OrbDot(size: 30)
                Text("Hold to talk").textStyle(TextStyle(size: 13, weight: .semibold, lineHeight: 16))
                    .frame(width: 275, height: 30)
                    .background(Theme.pill, in: .capsule)
                    .overlay(Capsule().strokeBorder(Theme.accent))
            }
            if current != .right { Spacer(minLength: 0) }
            miniKey("globe")
            miniKey("return")
        }
        .padding(7)
        .background(Theme.field, in: .rect(cornerRadius: 14))
        .animation(.spring(duration: 0.35), value: position)
    }

    private func miniKey(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 13))
            .foregroundStyle(.white)
            .frame(width: 34, height: 34)
            .background(Theme.key, in: .rect(cornerRadius: 8))
    }
}
