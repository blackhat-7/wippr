import SwiftUI

/// Add or edit one shortcut: the phrase, the keys (with chips for Ctrl, Esc, Tab, Enter and arrows) and a
/// preview of what gets typed. Saves into `shortcuts`.
struct ShortcutEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var shortcuts: [Shortcut]
    let id: Shortcut.ID
    @State private var phrase: String
    @State private var keys: String
    /// Ctrl was tapped: the next letter typed into the keys field becomes `<C-letter>`.
    @State private var ctrl = false
    @FocusState private var keysFocused: Bool

    init(_ shortcut: Shortcut, in shortcuts: Binding<[Shortcut]>) {
        _shortcuts = shortcuts
        id = shortcut.id
        _phrase = State(initialValue: shortcut.phrase)
        _keys = State(initialValue: shortcut.keys)
    }

    private var isNew: Bool { !shortcuts.contains { $0.id == id } }
    private var trimmedPhrase: String { phrase.trimmingCharacters(in: .whitespacesAndNewlines) }
    /// Another shortcut that already has this phrase, as it's heard (case, spaces and punctuation ignored).
    private var taken: Shortcut? {
        let spoken = Shortcuts.normalize(phrase)
        return shortcuts.first { $0.id != id && Shortcuts.normalize($0.phrase) == spoken }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    field("When you say") {
                        TextField("", text: $phrase, prompt: Text("next window").foregroundStyle(Theme.faint))
                            .textStyle(TextStyle(size: 17, tracking: -0.01, lineHeight: 22))
                            .submitLabel(.next)
                            .onSubmit { keysFocused = true }
                            .fieldBox()
                        if let taken {
                            Text("\u{201C}\(taken.phrase)\u{201D} is already a shortcut. Say something else.")
                                .textStyle(.caption, Theme.mic)
                        }
                    }
                    field("Type") {
                        TextField("", text: $keys, prompt: Text("<C-b>n").foregroundStyle(Theme.faint))
                            .textStyle(TextStyle(size: 17, lineHeight: 22, mono: true))
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .focused($keysFocused)
                            .fieldBox()
                        chips
                        Text(ctrl ? "Now type a letter for Ctrl." : "Tap a key to add it. Anything else is typed as is.")
                            .textStyle(.caption, ctrl ? Theme.tint : Theme.tertiary)
                    }
                    field("Preview") {
                        HStack(spacing: 10) {
                            Text("\u{201C}\(trimmedPhrase.isEmpty ? "…" : trimmedPhrase)\u{201D}")
                                .textStyle(.rowStrong)
                                .lineLimit(1)
                            Image(systemName: "arrow.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.tertiary)
                            if keys.isEmpty {
                                Text("nothing yet").textStyle(.row, Theme.faint)
                            } else {
                                KeysView(keys: keys)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(16)
                        .card(radius: 16)
                        Text("Say the phrase on its own. Case, spaces and punctuation don't matter.")
                            .textStyle(.caption, Theme.tertiary)
                    }
                    if !isNew {
                        Button("Delete shortcut", role: .destructive) {
                            shortcuts.removeAll { $0.id == id }
                            dismiss()
                        }
                        .textStyle(.rowStrong, .red)
                        .buttonStyle(PressStyle())
                        .frame(maxWidth: .infinity, minHeight: 44)
                    }
                }
                .padding(20)
            }
            .background(Theme.background)
            .navigationTitle(isNew ? "New shortcut" : "Edit shortcut")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(Shortcuts.normalize(phrase).isEmpty || keys.isEmpty || taken != nil)
                }
            }
            .onChange(of: keys) { old, new in
                guard ctrl else { return }
                ctrl = false
                if new.count == old.count + 1, new.hasPrefix(old), let letter = new.last, letter.isASCII, letter.isLetter {
                    keys = old + "<C-\(letter.lowercased())>"
                }
            }
        }
    }

    private func field(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label).textStyle(.label, Theme.tertiary)
            content()
        }
    }

    private var chips: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
            chip(ctrl ? "Ctrl +" : "Ctrl", accessibility: "Control, then type a letter", selected: ctrl) {
                ctrl.toggle()
                if ctrl { keysFocused = true }
            }
            ForEach(Shortcuts.keyNames, id: \.self) { name in
                chip(KeysView.symbol(name), accessibility: KeysView.spoken(name)) {
                    ctrl = false
                    keys += "<\(name)>"
                }
            }
        }
    }

    private func chip(_ title: String, accessibility: String, selected: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .textStyle(TextStyle(size: 14, weight: .medium, lineHeight: 18, mono: true), selected ? .black : .white)
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(selected ? Theme.tint : Theme.key, in: .rect(cornerRadius: 9))
                .contentShape(.rect)
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(accessibility)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func save() {
        let shortcut = Shortcut(id: id, phrase: trimmedPhrase, keys: keys)
        if let index = shortcuts.firstIndex(where: { $0.id == id }) {
            shortcuts[index] = shortcut
        } else {
            shortcuts.append(shortcut)
        }
        dismiss()
    }
}

private extension View {
    /// The editor's input box: #1C1C1E, 14 pt corners.
    func fieldBox() -> some View {
        tint(Theme.accent)
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .background(Theme.field, in: .rect(cornerRadius: 14))
    }
}

/// Keys as they read: `<C-b>n` shows a "Ctrl+B" chip, then "n". Spaces show as ␣.
struct KeysView: View {
    var keys: String

    var body: some View {
        let parts = Shortcuts.parts(keys)
        HStack(spacing: 4) {
            ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                switch part {
                case .ctrl, .key:
                    Text(Self.label(part))
                        .textStyle(TextStyle(size: 13, weight: .semibold, lineHeight: 16, mono: true))
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 7)
                        .frame(minWidth: 26, minHeight: 24)
                        .background(Theme.key, in: .rect(cornerRadius: 6))
                case .text(let text):
                    Text(text.replacing(" ", with: "␣"))
                        .textStyle(TextStyle(size: 15, weight: .medium, lineHeight: 20, mono: true))
                        .lineLimit(1)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(parts.map {
            switch $0 {
            case .ctrl(let letter): "Control \(letter.uppercased())"
            case .key(let name): Self.spoken(name)
            case .text(let text): text
            }
        }.joined(separator: ", "))
    }

    private static let arrows = ["Up": "↑", "Down": "↓", "Left": "←", "Right": "→"]

    /// What a key's chip shows: arrows as ↑ ↓ ← →, other names as they are.
    static func symbol(_ name: String) -> String { arrows[name] ?? name }

    private static func label(_ part: Shortcuts.Part) -> String {
        switch part {
        case .ctrl(let letter): "Ctrl+\(letter.uppercased())"
        case .key(let name): symbol(name)
        case .text(let text): text
        }
    }

    /// What VoiceOver reads for a key.
    static func spoken(_ name: String) -> String { arrows[name] == nil ? name : "\(name) arrow" }
}
