import AppKit

/// 브라우저 NSCollectionView의 셀 아이템
final class BrowserItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("BrowserItem")
    static let itemSize = NSSize(width: 120, height: 140)

    private let thumbnailView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let playBadge = NSImageView()
    private var isEditingName = false
    private var renameDelegate: RenameFieldDelegate?

    override func loadView() {
        view = NSView(frame: NSRect(origin: .zero, size: Self.itemSize))
        setupThumbnailView()
        setupPlayBadge()
        setupNameLabel()
    }

    override var isSelected: Bool {
        didSet { updateSelectionAppearance() }
    }

    // MARK: - Configuration

    func configure(with content: BrowserContent, thumbnail: NSImage?) {
        nameLabel.stringValue = content.name
        playBadge.isHidden = true

        switch content {
        case .folder(let node):
            let config = NSImage.SymbolConfiguration(pointSize: 32, weight: .regular)
            thumbnailView.image = NSImage(
                systemSymbolName: "folder.fill",
                accessibilityDescription: content.name
            )?.withSymbolConfiguration(config)
            thumbnailView.contentTintColor = FolderColorService.shared.color(for: node.url)
            thumbnailView.imageScaling = .scaleNone
            thumbnailView.layer?.borderWidth = 0
            thumbnailView.layer?.backgroundColor = nil
        case .image(let file):
            thumbnailView.imageScaling = .scaleProportionallyDown
            thumbnailView.layer?.borderWidth = 0.5
            thumbnailView.layer?.backgroundColor = nil
            if file.isVideo {
                thumbnailView.image = thumbnail ?? NSImage(
                    systemSymbolName: "film",
                    accessibilityDescription: content.name
                )
                thumbnailView.contentTintColor = thumbnail == nil ? .secondaryLabelColor : nil
                playBadge.isHidden = false
            } else {
                thumbnailView.image = thumbnail
                thumbnailView.contentTintColor = nil
            }
        }

        view.toolTip = content.name
    }

    func updateThumbnail(_ image: NSImage) {
        thumbnailView.image = image
    }

    // MARK: - Inline Rename

    func beginRename(completion: @escaping (String?) -> Void) {
        guard !isEditingName else { return }
        isEditingName = true

        let editField = NSTextField(string: nameLabel.stringValue)
        editField.frame = nameLabel.frame
        editField.font = nameLabel.font
        editField.alignment = .center
        editField.isBordered = true
        editField.focusRingType = .exterior
        editField.tag = 999

        // 확장자 제외 이름만 선택
        let fullName = editField.stringValue
        if let dotIndex = fullName.lastIndex(of: ".") {
            let range = fullName.startIndex..<dotIndex
            editField.currentEditor()?.selectedRange = NSRange(range, in: fullName)
        }

        nameLabel.isHidden = true
        view.addSubview(editField)

        let fieldDelegate = RenameFieldDelegate(onCommit: { [weak self] newValue in
            self?.endRename(newName: newValue, completion: completion)
        }, onCancel: { [weak self] in
            self?.endRename(newName: nil, completion: completion)
        })
        renameDelegate = fieldDelegate
        editField.delegate = fieldDelegate
        view.window?.makeFirstResponder(editField)
    }

    private func endRename(newName: String?, completion: (String?) -> Void) {
        if let editField = view.viewWithTag(999) {
            editField.removeFromSuperview()
        }
        nameLabel.isHidden = false
        isEditingName = false
        renameDelegate = nil
        completion(newName)
    }

    // MARK: - Setup

    private func setupThumbnailView() {
        thumbnailView.translatesAutoresizingMaskIntoConstraints = false
        thumbnailView.imageScaling = .scaleProportionallyDown
        thumbnailView.wantsLayer = true
        thumbnailView.layer?.cornerRadius = 6
        thumbnailView.layer?.masksToBounds = true
        thumbnailView.layer?.borderColor = NSColor.separatorColor.cgColor
        thumbnailView.layer?.borderWidth = 0.5
        view.addSubview(thumbnailView)

        NSLayoutConstraint.activate([
            thumbnailView.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            thumbnailView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            thumbnailView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            thumbnailView.heightAnchor.constraint(equalTo: thumbnailView.widthAnchor),
        ])
    }

    private func setupPlayBadge() {
        playBadge.translatesAutoresizingMaskIntoConstraints = false
        playBadge.image = NSImage(systemSymbolName: "play.circle.fill", accessibilityDescription: "영상")
        playBadge.contentTintColor = .white
        playBadge.wantsLayer = true
        playBadge.shadow = {
            let s = NSShadow()
            s.shadowColor = NSColor.black.withAlphaComponent(0.5)
            s.shadowBlurRadius = 2
            s.shadowOffset = NSSize(width: 0, height: -1)
            return s
        }()
        playBadge.isHidden = true
        view.addSubview(playBadge)

        NSLayoutConstraint.activate([
            playBadge.centerXAnchor.constraint(equalTo: thumbnailView.centerXAnchor),
            playBadge.centerYAnchor.constraint(equalTo: thumbnailView.centerYAnchor),
            playBadge.widthAnchor.constraint(equalToConstant: 28),
            playBadge.heightAnchor.constraint(equalToConstant: 28),
        ])
    }

    private func setupNameLabel() {
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.alignment = .center
        nameLabel.lineBreakMode = .byTruncatingMiddle
        nameLabel.font = .systemFont(ofSize: 11)
        nameLabel.textColor = .labelColor
        nameLabel.maximumNumberOfLines = 2
        view.addSubview(nameLabel)

        NSLayoutConstraint.activate([
            nameLabel.topAnchor.constraint(equalTo: thumbnailView.bottomAnchor, constant: 4),
            nameLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4),
            nameLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),
        ])
    }

    private func updateSelectionAppearance() {
        view.wantsLayer = true
        if isSelected {
            view.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor
            view.layer?.cornerRadius = 8
            nameLabel.textColor = .controlAccentColor
            thumbnailView.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.5).cgColor
            thumbnailView.layer?.borderWidth = 2
        } else {
            view.layer?.backgroundColor = nil
            nameLabel.textColor = .labelColor
            thumbnailView.layer?.borderColor = NSColor.separatorColor.cgColor
            thumbnailView.layer?.borderWidth = 0.5
        }
    }
}

// MARK: - Rename Field Delegate

private final class RenameFieldDelegate: NSObject, NSTextFieldDelegate {
    let onCommit: (String) -> Void
    let onCancel: () -> Void

    init(onCommit: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.onCommit = onCommit
        self.onCancel = onCancel
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            onCommit(control.stringValue)
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            onCancel()
            return true
        }
        return false
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let textField = obj.object as? NSTextField else { return }
        onCommit(textField.stringValue)
    }
}
