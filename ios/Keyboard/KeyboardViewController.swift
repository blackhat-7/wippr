import os
import UIKit

/// A one-row keyboard: hold the button, speak, let go, and the text is typed into the focused field.
/// Slide up while holding for edit mode: the speech becomes an instruction that rewrites the selection
/// (or the text before the cursor), or writes something new in an empty field. A quick tap right after undoes an edit.
/// In a terminal the speech becomes a shell command instead (`isCommandField`).
/// Keyboards can't use the mic, so the wippr app records and hands the text over (`KeyboardHandoff`).
final class KeyboardViewController: UIInputViewController {
    private let status = UILabel()
    private let globe = UIButton(configuration: .plain())
    private let orb = OrbView()
    /// The visible "Hold to talk" button.
    private let pill = UIView()
    private var delete = UIButton()
    private let keys = UIStackView()
    private var placement: [NSLayoutConstraint] = []
    /// The whole keyboard except the three keys: press anywhere to talk.
    private let hold = UIControl()
    private var pressedAt: Date?
    private let press = UIImpactFeedbackGenerator(style: .medium)
    private let letGo = UIImpactFeedbackGenerator(style: .soft)
    private let notify = UINotificationFeedbackGenerator()
    private let tick = UISelectionFeedbackGenerator()
    /// Slid up into edit mode during the current press.
    private var editMode = false
    /// The text sent for editMode: the selection, or else everything before the cursor.
    private var target: (selected: String?, before: String)?
    /// The last edit or command, undoable with a quick tap for a few seconds.
    private var undo: (inserted: String, original: String, until: Date)?
    /// What's drawn; nil until the first update so it always draws once.
    private var phase: KeyboardHandoff.Phase?
    /// Whether the drawn status is for a terminal field.
    private var drawnCommandField = false
    /// A start or stop the app hasn't confirmed yet, shown optimistically until it does or it expires.
    private var pending: (record: Bool, until: Date)?
    private var poll: Timer?
    /// Repeats delete while the key is held.
    private var deleteRepeat: Timer?
    private let log = Logger(subsystem: "cx.immortal.wippr", category: "keyboard")

    override func viewDidLoad() {
        super.viewDidLoad()
        inputView?.allowsSelfSizing = true

        status.font = .systemFont(ofSize: 15, weight: .semibold)
        status.textColor = .label
        status.lineBreakMode = .byTruncatingHead
        status.setContentHuggingPriority(.defaultLow, for: .horizontal)

        globe.setImage(UIImage(systemName: "globe"), for: .normal)
        globe.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        let inside = UIStackView(arrangedSubviews: [status])
        inside.alignment = .center
        inside.translatesAutoresizingMaskIntoConstraints = false
        // The orb sits just left of the button, as tall as it.
        orb.isUserInteractionEnabled = false
        orb.translatesAutoresizingMaskIntoConstraints = false
        pill.backgroundColor = .systemBlue.withAlphaComponent(0.12)
        pill.layer.cornerRadius = 18
        pill.layer.cornerCurve = .continuous
        pill.isUserInteractionEnabled = false
        pill.translatesAutoresizingMaskIntoConstraints = false
        pill.addSubview(inside)
        hold.translatesAutoresizingMaskIntoConstraints = false
        hold.addSubview(pill)
        hold.addSubview(orb)
        view.addSubview(hold)
        hold.addTarget(self, action: #selector(pressDown), for: .touchDown)
        hold.addTarget(self, action: #selector(pressUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        hold.addTarget(self, action: #selector(dragged(_:_:)), for: [.touchDragInside, .touchDragOutside])
        hold.isAccessibilityElement = true
        hold.accessibilityLabel = "Hold to talk"
        hold.accessibilityTraits = .button

        delete = key("delete.left", #selector(deleteDown), for: .touchDown)
        delete.addTarget(self, action: #selector(deleteUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        delete.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(delete)
        keys.addArrangedSubview(globe)
        keys.addArrangedSubview(key("return", #selector(insertReturn)))
        keys.spacing = 8
        keys.alignment = .center
        keys.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(keys)
        let height = view.heightAnchor.constraint(equalToConstant: 56) // 10 pt above and below the 36 pt button
        height.priority = UILayoutPriority(999)
        NSLayoutConstraint.activate([
            height,
            hold.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hold.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hold.topAnchor.constraint(equalTo: view.topAnchor),
            hold.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            delete.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            delete.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            keys.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            keys.topAnchor.constraint(equalTo: view.topAnchor),
            keys.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            // The visible button spans everything between the keys; the whole strip still listens.
            orb.leadingAnchor.constraint(greaterThanOrEqualTo: delete.trailingAnchor, constant: 8),
            orb.trailingAnchor.constraint(equalTo: pill.leadingAnchor, constant: -8),
            orb.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
            orb.heightAnchor.constraint(equalTo: pill.heightAnchor),
            orb.widthAnchor.constraint(equalTo: orb.heightAnchor),
            pill.trailingAnchor.constraint(lessThanOrEqualTo: keys.leadingAnchor, constant: -8),
            pill.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            pill.heightAnchor.constraint(equalToConstant: 36),
            inside.centerXAnchor.constraint(equalTo: pill.centerXAnchor),
            inside.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
            inside.leadingAnchor.constraint(greaterThanOrEqualTo: pill.leadingAnchor, constant: 12),
            inside.trailingAnchor.constraint(lessThanOrEqualTo: pill.trailingAnchor, constant: -12),
        ])
    }

    /// iPhone: the button fills the space between the keys. iPad: a fixed-width button docked left, centre or right.
    private func placeButton() {
        NSLayoutConstraint.deactivate(placement)
        let width = pill.widthAnchor.constraint(equalToConstant: 420)
        width.priority = UILayoutPriority(999) // shrinks in narrow windows (Slide Over, split view)
        placement = if traitCollection.userInterfaceIdiom == .pad {
            switch KeyboardHandoff.buttonPosition() {
            case .left: [width, orb.leadingAnchor.constraint(equalTo: delete.trailingAnchor, constant: 8)]
            case .center: [width, pill.centerXAnchor.constraint(equalTo: view.centerXAnchor)]
            case .right: [width, pill.trailingAnchor.constraint(equalTo: keys.leadingAnchor, constant: -8)]
            }
        } else {
            [orb.leadingAnchor.constraint(equalTo: delete.trailingAnchor, constant: 8),
             pill.trailingAnchor.constraint(equalTo: keys.leadingAnchor, constant: -8)]
        }
        NSLayoutConstraint.activate(placement)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        placeButton()
        if hasFullAccess { KeyboardHandoff.markKeyboardSeen() }
        log.notice("appear: full access \(self.hasFullAccess), status \(KeyboardHandoff.status().rawValue, privacy: .public)")
        let proxy = textDocumentProxy
        log.notice("traits: autocorrection \(proxy.autocorrectionType?.rawValue ?? -1), autocapitalization \(proxy.autocapitalizationType?.rawValue ?? -1), keyboard \(proxy.keyboardType?.rawValue ?? -1), content \(proxy.textContentType?.rawValue ?? "nil", privacy: .public), command \(self.isCommandField, privacy: .public)")
        update()
        orb.resume()
        if hasFullAccess { [press, letGo].forEach { $0.prepare() }; notify.prepare(); tick.prepare() }
        poll = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.update() }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        poll?.invalidate()
        deleteUp()
        orb.pauseRendering()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        globe.isHidden = !needsInputModeSwitchKey
    }

    private func update() {
        let real = KeyboardHandoff.status()
        if let pending, Date.now > pending.until || (real == .recording) == pending.record {
            self.pending = nil
            draw(real)
        } else if pending == nil, real != phase {
            draw(real)
        }
        insertLatest()
    }

    /// The focused field changed (e.g. from a chat box to a terminal): show which mode a press will use.
    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        if let phase, isCommandField != drawnCommandField { draw(phase) }
    }

    private func draw(_ phase: KeyboardHandoff.Phase) {
        self.phase = phase
        drawnCommandField = isCommandField
        orb.phase = phase
        status.text = switch phase {
        case .off: offHint
        case .ready: isCommandField ? "Hold to say a command" : "Hold to talk"
        case .recording: editMode ? "Edit: say what to change" : isCommandField ? "Listening… (command)" : "Listening…  ↑ slide up to edit"
        case .processing: target != nil ? "Editing…" : isCommandField ? "Writing command…" : "Writing…"
        }
    }

    /// A terminal (Termius, Blink, …): no autocorrection or autocapitalization, and not a field that is clearly something else.
    private var isCommandField: Bool {
        let proxy = textDocumentProxy
        let other: [UIKeyboardType] = [.emailAddress, .URL, .webSearch, .numberPad, .phonePad, .decimalPad, .asciiCapableNumberPad]
        let otherContent: [UITextContentType] = [.username, .emailAddress, .URL, .password, .newPassword, .oneTimeCode]
        return proxy.autocorrectionType == .no && proxy.autocapitalizationType == UITextAutocapitalizationType.none
            && !other.contains(proxy.keyboardType ?? .default)
            && !(proxy.textContentType?.map(otherContent.contains) ?? false)
    }

    private var offHint: String { hasFullAccess ? "Mic is off · tap to turn it on" : "Tap to finish setting up noboard" }

    private func insertLatest() {
        // Read the shared value each time: a host (e.g. Termius) can keep several keyboard instances polling at once,
        // and each would otherwise type the same text.
        guard let latest = KeyboardHandoff.latestText(), latest.id.uuidString != UserDefaults.standard.string(forKey: "lastID") else { return }
        UserDefaults.standard.set(latest.id.uuidString, forKey: "lastID")
        if latest.edit == true { return applyEdit(latest.text) }
        if latest.command == true { return insertCommand(latest.text) }
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        let space = latest.keys != true && before.last.map { !$0.isWhitespace } ?? false
        textDocumentProxy.insertText(space ? " " + latest.text : latest.text)
        buzz { notify.notificationOccurred(.success) }
        orb.flash()
        log.notice("inserted \(latest.text.count) chars")
    }

    /// Replaces the edited text if the field still holds it; otherwise just types the result.
    private func applyEdit(_ result: String) {
        let target = self.target
        self.target = nil
        guard let target, !result.isEmpty else {
            buzz { notify.notificationOccurred(.error) }
            orb.shake()
            status.text = "Couldn't edit that"
            return
        }
        var original = ""
        if let selected = target.selected, textDocumentProxy.selectedText == selected {
            original = selected // typing replaces the selection
        } else if target.selected == nil, textDocumentProxy.documentContextBeforeInput ?? "" == target.before {
            original = target.before
            for _ in original { textDocumentProxy.deleteBackward() }
        }
        textDocumentProxy.insertText(result)
        undo = (result, original, .now + 5)
        buzz { notify.notificationOccurred(.success) }
        orb.flash()
        status.text = "Edited · tap to undo"
        log.notice("edited \(original.count) → \(result.count) chars")
    }

    /// Types a written command as is, never with a newline (that would run it), undoable like an edit.
    private func insertCommand(_ command: String) {
        let text = command.filter { !$0.isNewline }
        textDocumentProxy.insertText(text)
        undo = (text, "", .now + 5)
        buzz { notify.notificationOccurred(.success) }
        orb.flash()
        status.text = "Command · tap to undo"
        log.notice("command \(text.count) chars")
    }

    private func undoEdit() {
        guard let undo else { return }
        self.undo = nil
        for _ in undo.inserted { textDocumentProxy.deleteBackward() }
        textDocumentProxy.insertText(undo.original)
        buzz { letGo.impactOccurred() }
        status.text = "Undone"
    }

    private func key(_ symbol: String, _ action: Selector, for event: UIControl.Event = .touchUpInside) -> UIButton {
        let button = UIButton(configuration: .plain())
        button.setImage(UIImage(systemName: symbol), for: .normal)
        button.addTarget(self, action: action, for: event)
        return button
    }

    @objc private func pressDown() {
        guard let phase, phase != .off else {
            log.notice("press while off")
            // Take them straight to the fix: the app turns the mic on (or shows keyboard setup) by itself.
            openApp(URL(string: hasFullAccess ? "noboard://mic" : "noboard://keyboard")!)
            buzz { notify.notificationOccurred(.error) }
            orb.shake()
            status.text = offHint
            status.alpha = 0.2
            UIView.animate(withDuration: 0.4) { self.status.alpha = 1 }
            return
        }
        pressedAt = .now
        editMode = false
        pressed(true)
        buzz { press.impactOccurred() }
        send(record: true)
    }

    @objc private func pressUp() {
        guard let pressedAt else { return }
        self.pressedAt = nil
        pressed(false)
        buzz { letGo.impactOccurred() }
        let tap = Date.now.timeIntervalSince(pressedAt) < 0.3
        if tap, let undo, undo.until > .now {
            send(record: false, mode: .cancel)
            undoEdit()
            return
        }
        if editMode {
            let selected = textDocumentProxy.selectedText.flatMap { $0.isEmpty ? nil : $0 }
            let before = textDocumentProxy.documentContextBeforeInput ?? ""
            target = (selected, before)
            send(record: false, mode: .edit, text: selected ?? before)
        } else if isCommandField {
            target = nil
            send(record: false, mode: .command, text: String((textDocumentProxy.documentContextBeforeInput ?? "").suffix(300)))
        } else {
            target = nil
            send(record: false)
        }
        editMode = false
        if tap { status.text = "Hold to talk" }
    }

    /// Sliding up out of the keyboard switches the press to edit mode; sliding back down returns to dictation.
    @objc private func dragged(_ control: UIControl, _ event: UIEvent) {
        guard pressedAt != nil, let y = event.allTouches?.first?.location(in: view).y else { return }
        let wantsEdit = editMode ? y < -10 : y < -30
        guard wantsEdit != editMode else { return }
        editMode = wantsEdit
        buzz { tick.selectionChanged() }
        pressed(true)
        if pending?.record == true || phase == .recording { draw(.recording) }
    }

    /// Sends start or stop and shows its result straight away; `update()` falls back to the real phase
    /// once the app confirms, or after 3 s if it never does.
    private func send(record: Bool, mode: KeyboardHandoff.Mode = .dictate, text: String? = nil) {
        let before = KeyboardHandoff.command()?.id
        KeyboardHandoff.sendCommand(record: record, mode: mode, text: text)
        let after = KeyboardHandoff.command()?.id
        log.notice("record \(record, privacy: .public) from \(self.phase?.rawValue ?? "nil", privacy: .public), command written \(after != nil && after != before, privacy: .public)")
        pending = (record, .now + 3)
        draw(record ? .recording : .processing)
    }

    private func pressed(_ down: Bool) {
        UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0) {
            self.pill.transform = down ? CGAffineTransform(scaleX: 0.97, y: 0.94) : .identity
            self.pill.backgroundColor = (self.editMode ? UIColor.systemPurple : .systemBlue).withAlphaComponent(down ? 0.25 : 0.12)
        }
    }

    /// Keyboards have no public way to open their app. `UIApplication.open(_:options:completionHandler:)` is marked
    /// unavailable in extensions, so find the application object on the responder chain and call it by selector.
    private func openApp(_ url: URL) {
        typealias Open = @convention(c) (NSObject, Selector, NSURL, NSDictionary, Any?) -> Void
        let selector = NSSelectorFromString("openURL:options:completionHandler:")
        var responder: UIResponder? = self
        while let current = responder {
            if current.isKind(of: NSClassFromString("UIApplication")!), let method = current.method(for: selector) {
                unsafeBitCast(method, to: Open.self)(current, selector, url as NSURL, [:] as NSDictionary, nil)
                return
            }
            responder = current.next
        }
        log.error("no application on the responder chain")
    }

    /// Haptics need Full Access in a keyboard.
    private func buzz(_ haptic: () -> Void) { if hasFullAccess { haptic() } }

    /// Deletes on touch down, then, like the system keyboard, keeps deleting while held.
    @objc private func deleteDown() {
        textDocumentProxy.deleteBackward()
        deleteRepeat?.invalidate()
        deleteRepeat = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            self?.deleteRepeat = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in self?.textDocumentProxy.deleteBackward() }
        }
    }

    @objc private func deleteUp() {
        deleteRepeat?.invalidate()
        deleteRepeat = nil
    }

    @objc private func insertReturn() { textDocumentProxy.insertText("\n") }
}
