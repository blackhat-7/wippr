import os
import UIKit

/// A one-row keyboard: hold the button, speak, let go, and the text is typed into the focused field.
/// Slide up while holding for edit mode: the speech becomes an instruction that rewrites the selection
/// (or the text before the cursor), or writes something new in an empty field. A quick tap right after undoes an edit.
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
    /// The last edit, undoable with a quick tap for a few seconds.
    private var undo: (inserted: String, original: String, until: Date)?
    /// What's drawn; nil until the first update so it always draws once.
    private var phase: KeyboardHandoff.Phase?
    /// A start or stop the app hasn't confirmed yet, shown optimistically until it does or it expires.
    private var pending: (record: Bool, until: Date)?
    private var lastID = UserDefaults.standard.string(forKey: "lastID")
    private var poll: Timer?
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
        orb.setContentHuggingPriority(.required, for: .horizontal)
        let inside = UIStackView(arrangedSubviews: [orb, status])
        inside.spacing = 8
        inside.alignment = .center
        inside.translatesAutoresizingMaskIntoConstraints = false
        pill.backgroundColor = .systemBlue.withAlphaComponent(0.12)
        pill.layer.cornerRadius = 18
        pill.layer.cornerCurve = .continuous
        pill.isUserInteractionEnabled = false
        pill.translatesAutoresizingMaskIntoConstraints = false
        pill.addSubview(inside)
        hold.translatesAutoresizingMaskIntoConstraints = false
        hold.addSubview(pill)
        view.addSubview(hold)
        hold.addTarget(self, action: #selector(pressDown), for: .touchDown)
        hold.addTarget(self, action: #selector(pressUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        hold.addTarget(self, action: #selector(dragged(_:_:)), for: [.touchDragInside, .touchDragOutside])
        hold.isAccessibilityElement = true
        hold.accessibilityLabel = "Hold to talk"
        hold.accessibilityTraits = .button

        delete = key("delete.left", #selector(deleteBackward))
        delete.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(delete)
        keys.addArrangedSubview(globe)
        keys.addArrangedSubview(key("return", #selector(insertReturn)))
        keys.spacing = 8
        keys.alignment = .center
        keys.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(keys)
        let height = view.heightAnchor.constraint(equalToConstant: 44)
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
            pill.leadingAnchor.constraint(greaterThanOrEqualTo: delete.trailingAnchor, constant: 8),
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
            case .left: [width, pill.leadingAnchor.constraint(equalTo: delete.trailingAnchor, constant: 8)]
            case .center: [width, pill.centerXAnchor.constraint(equalTo: view.centerXAnchor)]
            case .right: [width, pill.trailingAnchor.constraint(equalTo: keys.leadingAnchor, constant: -8)]
            }
        } else {
            [pill.leadingAnchor.constraint(equalTo: delete.trailingAnchor, constant: 8),
             pill.trailingAnchor.constraint(equalTo: keys.leadingAnchor, constant: -8)]
        }
        NSLayoutConstraint.activate(placement)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        placeButton()
        log.notice("appear: full access \(self.hasFullAccess), status \(KeyboardHandoff.status().rawValue, privacy: .public)")
        update()
        orb.resume()
        if hasFullAccess { [press, letGo].forEach { $0.prepare() }; notify.prepare(); tick.prepare() }
        poll = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.update() }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        poll?.invalidate()
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

    private func draw(_ phase: KeyboardHandoff.Phase) {
        self.phase = phase
        orb.phase = phase
        status.text = switch phase {
        case .off: offHint
        case .ready: "Hold to talk"
        case .recording: editMode ? "Edit: say what to change" : "Listening…  ↑ slide up to edit"
        case .processing: target != nil ? "Editing…" : "Writing…"
        }
    }

    private var offHint: String { hasFullAccess ? "Open noboard and turn the mic on" : "Allow Full Access for noboard in Settings" }

    private func insertLatest() {
        guard let latest = KeyboardHandoff.latestText(), latest.id.uuidString != lastID else { return }
        lastID = latest.id.uuidString
        UserDefaults.standard.set(lastID, forKey: "lastID")
        if latest.edit == true { return applyEdit(latest.text) }
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        let space = before.last.map { !$0.isWhitespace } ?? false
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

    private func undoEdit() {
        guard let undo else { return }
        self.undo = nil
        for _ in undo.inserted { textDocumentProxy.deleteBackward() }
        textDocumentProxy.insertText(undo.original)
        buzz { letGo.impactOccurred() }
        status.text = "Undone"
    }

    private func key(_ symbol: String, _ action: Selector) -> UIButton {
        let button = UIButton(configuration: .plain())
        button.setImage(UIImage(systemName: symbol), for: .normal)
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    @objc private func pressDown() {
        guard let phase, phase != .off else {
            log.notice("press while off")
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

    /// Haptics need Full Access in a keyboard.
    private func buzz(_ haptic: () -> Void) { if hasFullAccess { haptic() } }

    @objc private func deleteBackward() { textDocumentProxy.deleteBackward() }
    @objc private func insertReturn() { textDocumentProxy.insertText("\n") }
}
