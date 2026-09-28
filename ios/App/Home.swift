import SwiftUI

/// 08 Home: mic switch, keyboard and cleanup status, tips. On iPad (regular width) a 720 pt column with
/// two-column cards, a privacy card and the keyboard-button position.
struct HomeView: View {
    @Environment(\.wide) private var wide
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("buttonPosition") private var buttonPosition = KeyboardHandoff.ButtonPosition.center.rawValue
    @State private var shortcuts = Shortcuts.all
    /// The shortcut open in the editor; a new one isn't in `shortcuts` yet.
    @State private var editing: Shortcut?
    /// The result of the last Copy all / Paste.
    @State private var copyNote: String?
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
                shortcutList
                CommandModelCard()
                    .padding(.top, wide ? 44 : 32)
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
        .onChange(of: shortcuts) { _, shortcuts in Shortcuts.all = shortcuts }
        .sheet(item: $editing) { ShortcutEditor($0, in: $shortcuts) }
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

    /// Phrase → keys rows; tap to edit, long-press to delete.
    private var shortcutList: some View {
        VStack(alignment: .leading, spacing: wide ? 12 : 8) {
            Text("Shortcuts").textStyle(.label, Theme.tertiary)
                .padding(.horizontal, wide ? 0 : 8)
            VStack(spacing: 0) {
                if shortcuts.isEmpty {
                    Text("Say \u{201C}next window\u{201D} and noboard types Ctrl+B, N. For tmux, vim, anything.")
                        .textStyle(.caption, Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 14)
                }
                ForEach(shortcuts) { shortcut in
                    Button { editing = shortcut } label: {
                        HStack(spacing: 10) {
                            Text("\u{201C}\(shortcut.phrase)\u{201D}").textStyle(.rowStrong).lineLimit(1)
                            Spacer(minLength: 8)
                            KeysView(keys: shortcut.keys)
                            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.faint)
                        }
                        .frame(minHeight: 52)
                        .contentShape(.rect)
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityHint("Edit")
                    .contextMenu {
                        Button("Delete", systemImage: "trash", role: .destructive) { shortcuts.removeAll { $0.id == shortcut.id } }
                    }
                    .overlay(alignment: .bottom) { Theme.border.frame(height: 1) }
                }
                Button { editing = Shortcut(phrase: "", keys: "") } label: {
                    Label("Add shortcut", systemImage: "plus")
                        .textStyle(.rowStrong, Theme.accent)
                        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                        .contentShape(.rect)
                }
                .buttonStyle(PressStyle())
            }
            .padding(.horizontal, 18)
            .card(radius: 24)
            copyPaste
        }
        .padding(.top, wide ? 44 : 32)
    }

    /// Moves shortcuts between installs (e.g. a TestFlight build and your own) as plain text on the clipboard.
    private var copyPaste: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if !shortcuts.isEmpty {
                    Button("Copy all", systemImage: "doc.on.doc") {
                        UIPasteboard.general.string = Shortcuts.text(shortcuts)
                        copyNote = "Copied \(shortcuts.count) \(shortcuts.count == 1 ? "shortcut" : "shortcuts"). Tap Paste in the other noboard."
                    }
                    .buttonStyle(.borderedProminent)
                }
                PasteButton(payloadType: String.self) { strings in
                    let (added, updated) = Shortcuts.paste(strings.joined(separator: "\n"), into: &shortcuts)
                    copyNote = added + updated == 0
                        ? "Nothing new to paste. Paste lines like: next window = <C-b>n"
                        : "Added \(added), updated \(updated)."
                }
            }
            .buttonBorderShape(.capsule)
            .tint(Theme.key)
            Text(copyNote ?? "To move shortcuts to another install of noboard, copy them there and paste here.")
                .textStyle(.caption, Theme.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, wide ? 0 : 8)
        .padding(.top, 4)
    }

    private var tips: some View {
        let items = [
            Tip(icon: AnyView(OrbDot(size: 22)), title: "Hold to talk", detail: "Let go and clean text is typed in."),
            Tip(icon: AnyView(TipIcon(symbol: "arrow.up", color: Theme.editStroke, fill: Theme.edit.opacity(0.16))),
                title: "Slide up to edit", detail: "\"Make it shorter\", \"turn into bullets\"."),
            Tip(icon: AnyView(TipIcon(symbol: "arrow.uturn.backward", color: .white, fill: Theme.field)),
                title: "Undo an edit", detail: "Tap the bar within 5 seconds."),
            Tip(icon: AnyView(TipIcon(symbol: "command", color: .white, fill: Theme.key)),
                title: "Say a shortcut", detail: "One word types keys like Ctrl+B. Set them up above."),
            Tip(icon: AnyView(TipIcon(symbol: "terminal", color: .white, fill: Theme.key)),
                title: "Talk to your terminal", detail: "In Termius or any terminal, say a command: \"git push dash dash force\"."),
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

/// Downloads Whisper for command mode (`CommandTranscriber`). Never automatic: it's 264 MB.
private struct CommandModelCard: View {
    @Environment(\.wide) private var wide
    @State private var ready = CommandTranscriber.isDownloaded
    /// 0…1 while downloading.
    @State private var progress: Double?
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: wide ? 12 : 8) {
            Text("Terminal commands").textStyle(.label, Theme.tertiary)
                .padding(.horizontal, wide ? 0 : 8)
            HStack(spacing: 14) {
                Text(failed ? "Download failed. Check your connection and try again."
                     : "A 264 MB on-device model makes dictated commands much more accurate.")
                    .textStyle(.caption, Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if ready {
                    HStack(spacing: 6) {
                        StatusBadge(ok: true, size: 18)
                        Text("Ready").textStyle(.rowStrong)
                    }
                } else if let progress {
                    Text(progress, format: .percent.precision(.fractionLength(0)))
                        .textStyle(.rowStrong, Theme.secondary)
                        .monospacedDigit()
                } else {
                    Button("Download", action: download)
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.capsule)
                        .tint(Theme.key)
                }
            }
            .padding(18)
            .overlay(alignment: .bottom) {
                if let progress, !ready {
                    ProgressView(value: progress).tint(Theme.accent).padding(.horizontal, 18).padding(.bottom, 8)
                }
            }
            .card(radius: 24)
        }
    }

    private func download() {
        failed = false
        progress = 0
        Task {
            do {
                try await CommandTranscriber.download { progress = $0 }
                ready = true
                CommandTranscriber.shared.preload()
            } catch {
                failed = true
            }
            progress = nil
        }
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
