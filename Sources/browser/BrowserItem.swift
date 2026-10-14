import AppKit

/// 브라우저 NSCollectionView의 셀 아이템
final class BrowserItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("BrowserItem")
    static let itemSize = NSSize(width: 120, height: 140)
    /// 하위 폴더 포함 보기에서 파일 이름 위에 붙는 상대 경로 줄 높이
    static let pathLineHeight: CGFloat = 14

    private let thumbnailView = NSImageView()
    private let pathLabel = NSTextField(labelWithString: "")
    private var pathLabelHeight: NSLayoutConstraint!
    /// 기준 폴더 아래 상대 경로 구성 요소. nil이면 경로 줄 자체를 접는다(일반 보기).
    private var folderPathComponents: [String]?
    private let nameLabel = NSTextField(labelWithString: "")
    private let playBadge = NSImageView()
    private let bookmarkBadge = NSImageView()
    private var isEditingName = false
    private var renameDelegate: RenameFieldDelegate?

    override func loadView() {
        view = NSView(frame: NSRect(origin: .zero, size: Self.itemSize))
        setupThumbnailView()
        setupPlayBadge()
        setupBookmarkBadge()
        setupPathLabel()
        setupNameLabel()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        updatePathLabelText()
    }

    override var isSelected: Bool {
        didSet { updateSelectionAppearance() }
    }

    // MARK: - Configuration

    func configure(with content: BrowserContent, thumbnail: NSImage?, isBookmarked: Bool = false, folderPath: [String]? = nil) {
        nameLabel.stringValue = content.name
        folderPathComponents = folderPath
        pathLabelHeight.constant = folderPath == nil ? 0 : Self.pathLineHeight
        pathLabel.isHidden = folderPath == nil
        updatePathLabelText()
        nameLabel.textColor = .labelColor  // 셀 재사용 리셋(깨진 북마크 회색이 남지 않도록)
        playBadge.isHidden = true
        bookmarkBadge.isHidden = !(content.isImage && isBookmarked)

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

            // 깨진 북마크: 파일이 존재하지 않으면 경고 플레이스홀더 표시
            if !FileManager.default.fileExists(atPath: file.url.path) {
                let config = NSImage.SymbolConfiguration(pointSize: 28, weight: .regular)
                thumbnailView.image = NSImage(
                    systemSymbolName: "exclamationmark.triangle",
                    accessibilityDescription: "원본을 찾을 수 없음"
                )?.withSymbolConfiguration(config)
                thumbnailView.contentTintColor = .tertiaryLabelColor
                thumbnailView.imageScaling = .scaleNone
                nameLabel.textColor = .tertiaryLabelColor
                playBadge.isHidden = true
            } else if file.isVideo {
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

        // 하위 폴더 포함 보기에선 어느 폴더의 파일인지 툴팁에 전체 상대 경로를 보여준다.
        if let folderPath, !folderPath.isEmpty {
            view.toolTip = folderPath.joined(separator: "/") + "/" + content.name
        } else {
            view.toolTip = content.name
        }
    }

    // MARK: - Path Label

    /// 경로 줄 문자열을 현재 라벨 폭에 맞춰 고른다.
    /// 1) `a/b/c` 전체가 들어가면 그대로
    /// 2) 안 들어가면 `시작폴더 … 끝폴더` (폴더 이름은 통째로 유지)
    /// 3) 그래도 안 들어가면 라벨의 가운데 말줄임에 맡긴다
    private func updatePathLabelText() {
        guard let comps = folderPathComponents, !comps.isEmpty else {
            pathLabel.stringValue = ""
            return
        }
        let available = pathLabel.bounds.width
        let full = comps.joined(separator: "/")
        guard available > 0 else { pathLabel.stringValue = full; return }

        if fits(full, in: available) || comps.count < 2 {
            pathLabel.stringValue = full
            return
        }
        pathLabel.stringValue = "\(comps.first!) … \(comps.last!)"
    }

    private func fits(_ text: String, in width: CGFloat) -> Bool {
        let attrs: [NSAttributedString.Key: Any] = [.font: pathLabel.font ?? .systemFont(ofSize: 10)]
        return (text as NSString).size(withAttributes: attrs).width <= width
    }

    func updateThumbnail(_ image: NSImage) {
        thumbnailView.image = image
    }

    // MARK: - Inline Rename

    func beginRename(completion: @escaping (String?) -> Void) {
        guard !isEditingName else { return }
        isEditingName = true

        let fullName = nameLabel.stringValue
        let fileExtension = (fullName as NSString).pathExtension
        let stem = fileExtension.isEmpty ? fullName : (fullName as NSString).deletingPathExtension

        let editField = NSTextField(string: stem)
        var frame = nameLabel.frame
        frame.size.height = max(frame.size.height, 22)
        editField.frame = frame
        editField.font = nameLabel.font
        editField.alignment = .center
        editField.isBordered = true
        editField.focusRingType = .exterior
        editField.tag = 999
        editField.usesSingleLineMode = true
        editField.cell?.isScrollable = true

        nameLabel.isHidden = true
        view.addSubview(editField)

        let fieldDelegate = RenameFieldDelegate(onCommit: { [weak self] newValue in
            let trimmed = newValue.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else {
                self?.endRename(newName: nil, completion: completion)
                return
            }
            let finalName = fileExtension.isEmpty ? trimmed : "\(trimmed).\(fileExtension)"
            self?.endRename(newName: finalName, completion: completion)
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
        thumbnailView.unregisterDraggedTypes()
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

    private func setupBookmarkBadge() {
        bookmarkBadge.translatesAutoresizingMaskIntoConstraints = false
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .bold)
        bookmarkBadge.image = NSImage(systemSymbolName: "star.fill", accessibilityDescription: "북마크됨")?
            .withSymbolConfiguration(config)
        bookmarkBadge.contentTintColor = .systemYellow
        bookmarkBadge.imageScaling = .scaleNone
        bookmarkBadge.wantsLayer = true
        bookmarkBadge.shadow = {
            let s = NSShadow()
            s.shadowColor = NSColor.black.withAlphaComponent(0.6)
            s.shadowBlurRadius = 2
            s.shadowOffset = NSSize(width: 0, height: -1)
            return s
        }()
        bookmarkBadge.isHidden = true
        view.addSubview(bookmarkBadge)

        NSLayoutConstraint.activate([
            bookmarkBadge.topAnchor.constraint(equalTo: thumbnailView.topAnchor, constant: 4),
            bookmarkBadge.trailingAnchor.constraint(equalTo: thumbnailView.trailingAnchor, constant: -4),
            bookmarkBadge.widthAnchor.constraint(equalToConstant: 16),
            bookmarkBadge.heightAnchor.constraint(equalToConstant: 16),
        ])
    }

    private func setupPathLabel() {
        pathLabel.translatesAutoresizingMaskIntoConstraints = false
        pathLabel.alignment = .center
        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.font = .systemFont(ofSize: 10)
        pathLabel.textColor = .secondaryLabelColor
        pathLabel.maximumNumberOfLines = 1
        pathLabel.isHidden = true
        view.addSubview(pathLabel)

        pathLabelHeight = pathLabel.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            pathLabel.topAnchor.constraint(equalTo: thumbnailView.bottomAnchor, constant: 4),
            pathLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4),
            pathLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),
            pathLabelHeight,
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
            // 경로 줄이 접혀 있으면(높이 0) 기존과 같은 위치가 된다
            nameLabel.topAnchor.constraint(equalTo: pathLabel.bottomAnchor, constant: 0),
            nameLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4),
            nameLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),
        ])
    }

    // MARK: - Drop Highlight

    private var isDropTarget = false

    func setDropHighlight(_ highlighted: Bool) {
        guard isDropTarget != highlighted else { return }
        isDropTarget = highlighted
        view.wantsLayer = true
        if highlighted {
            view.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor
            view.layer?.cornerRadius = 8
            view.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.6).cgColor
            view.layer?.borderWidth = 2
        } else {
            updateSelectionAppearance()
            view.layer?.borderColor = nil
            view.layer?.borderWidth = 0
        }
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
    private var isHandled = false

    init(onCommit: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.onCommit = onCommit
        self.onCancel = onCancel
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            guard !isHandled else { return true }
            isHandled = true
            onCommit(control.stringValue)
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            guard !isHandled else { return true }
            isHandled = true
            onCancel()
            return true
        }
        return false
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard !isHandled else { return }
        isHandled = true
        guard let textField = obj.object as? NSTextField else { return }
        onCommit(textField.stringValue)
    }
}
