import UIKit

/// A one-row keyboard that types whatever wippr just transcribed into the focused field.
/// Keyboards can't use the mic, so wippr records in its own app and hands the text over (`KeyboardHandoff`).
final class KeyboardViewController: UIInputViewController {
    private let status = UILabel()
    private let globe = UIButton(configuration: .plain())
    private var lastID = UserDefaults.standard.string(forKey: "lastID")

    override func viewDidLoad() {
        super.viewDidLoad()
        inputView?.allowsSelfSizing = true

        status.text = "Say “wipper” then speak"
        status.font = .preferredFont(forTextStyle: .footnote)
        status.textColor = .secondaryLabel
        status.lineBreakMode = .byTruncatingHead
        status.setContentHuggingPriority(.defaultLow, for: .horizontal)

        globe.setImage(UIImage(systemName: "globe"), for: .normal)
        globe.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        let delete = key("delete.left", #selector(deleteBackward))
        let newline = key("return", #selector(insertReturn))

        let row = UIStackView(arrangedSubviews: [globe, status, delete, newline])
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

        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(), Unmanaged.passUnretained(self).toOpaque(),
            { _, observer, _, _, _ in
                guard let observer else { return }
                let keyboard = Unmanaged<KeyboardViewController>.fromOpaque(observer).takeUnretainedValue()
                DispatchQueue.main.async { keyboard.insertLatest() }
            },
            KeyboardHandoff.notification, nil, .deliverImmediately
        )
    }

    deinit {
        CFNotificationCenterRemoveEveryObserver(CFNotificationCenterGetDarwinNotifyCenter(), Unmanaged.passUnretained(self).toOpaque())
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        insertLatest() // text dictated just before the field was tapped
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        globe.isHidden = !needsInputModeSwitchKey
    }

    private func insertLatest() {
        guard let (id, text) = KeyboardHandoff.latest(), id != lastID else { return }
        lastID = id
        UserDefaults.standard.set(id, forKey: "lastID")
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        let space = before.last.map { !$0.isWhitespace } ?? false
        textDocumentProxy.insertText(space ? " " + text : text)
        status.text = text
    }

    private func key(_ symbol: String, _ action: Selector) -> UIButton {
        let button = UIButton(configuration: .plain())
        button.setImage(UIImage(systemName: symbol), for: .normal)
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    @objc private func deleteBackward() { textDocumentProxy.deleteBackward() }
    @objc private func insertReturn() { textDocumentProxy.insertText("\n") }
}
