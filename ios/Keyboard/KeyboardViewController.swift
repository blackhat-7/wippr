import os
import UIKit

/// A one-row keyboard: tap the mic, speak, tap again, and the text is typed into the focused field.
/// Keyboards can't use the mic, so the wippr app records and hands the text over (`KeyboardHandoff`).
final class KeyboardViewController: UIInputViewController {
    private let status = UILabel()
    private let globe = UIButton(configuration: .plain())
    private let micButton = UIButton(configuration: .plain())
    private var phase = KeyboardHandoff.Phase.off
    private var lastID = UserDefaults.standard.string(forKey: "lastID")
    private var poll: Timer?
    private let log = Logger(subsystem: "cx.immortal.wippr", category: "keyboard")

    override func viewDidLoad() {
        super.viewDidLoad()
        inputView?.allowsSelfSizing = true

        status.font = .preferredFont(forTextStyle: .footnote)
        status.textColor = .secondaryLabel
        status.lineBreakMode = .byTruncatingHead
        status.setContentHuggingPriority(.defaultLow, for: .horizontal)

        globe.setImage(UIImage(systemName: "globe"), for: .normal)
        globe.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        micButton.addTarget(self, action: #selector(toggleMic), for: .touchUpInside)
        let delete = key("delete.left", #selector(deleteBackward))
        let newline = key("return", #selector(insertReturn))

        let row = UIStackView(arrangedSubviews: [globe, micButton, status, delete, newline])
        row.spacing = 8
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(row)
        let height = view.heightAnchor.constraint(equalToConstant: 36)
        height.priority = UILayoutPriority(999)
        NSLayoutConstraint.activate([
            height,
            row.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            row.topAnchor.constraint(equalTo: view.topAnchor),
            row.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        log.notice("appear: full access \(self.hasFullAccess)")
        update()
        poll = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.update() }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        poll?.invalidate()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        globe.isHidden = !needsInputModeSwitchKey
    }

    private func update() {
        let phase = KeyboardHandoff.status()
        if phase != self.phase {
            self.phase = phase
            micButton.setImage(UIImage(systemName: phase == .recording ? "stop.circle.fill" : "mic.circle.fill"), for: .normal)
            micButton.tintColor = phase == .recording ? .systemRed : nil
            micButton.isEnabled = phase == .ready || phase == .recording
            status.text = switch phase {
            case .off: hasFullAccess ? "Open wippr and turn the mic on" : "Allow Full Access for wippr in Settings"
            case .ready: "Tap the mic to dictate"
            case .recording: "Listening… tap to stop"
            case .processing: "Writing…"
            }
        }
        insertLatest()
    }

    private func insertLatest() {
        guard let latest = KeyboardHandoff.latestText(), latest.id.uuidString != lastID else { return }
        lastID = latest.id.uuidString
        UserDefaults.standard.set(lastID, forKey: "lastID")
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        let space = before.last.map { !$0.isWhitespace } ?? false
        textDocumentProxy.insertText(space ? " " + latest.text : latest.text)
        log.notice("inserted \(latest.text.count) chars")
    }

    private func key(_ symbol: String, _ action: Selector) -> UIButton {
        let button = UIButton(configuration: .plain())
        button.setImage(UIImage(systemName: symbol), for: .normal)
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    @objc private func toggleMic() { KeyboardHandoff.sendCommand(record: phase != .recording) }
    @objc private func deleteBackward() { textDocumentProxy.deleteBackward() }
    @objc private func insertReturn() { textDocumentProxy.insertText("\n") }
}
