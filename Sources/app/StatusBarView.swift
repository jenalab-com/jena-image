import AppKit

/// 윈도우 하단 상태 바 — 파일 수, 선택 정보, 썸네일 크기 슬라이더, 이미지 반전 버튼
final class StatusBarView: NSView {
    var onThumbnailScaleChanged: ((CGFloat) -> Void)?
    var onFlipHorizontal: (() -> Void)?
    var onFlipVertical: (() -> Void)?
    var onResetFlip: (() -> Void)?

    private let infoLabel = NSTextField(labelWithString: "")
    private let separator = NSBox()
    private let sizeSlider = NSSlider()
    private let smallIcon = NSImageView()
    private let largeIcon = NSImageView()

    private let flipHButton = NSButton()
    private let flipVButton = NSButton()
    private let resetFlipButton = NSButton()

    private static let minScale: CGFloat = 0.6
    private static let maxScale: CGFloat = 2.0

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func update(folderCount: Int, imageCount: Int, selectionCount: Int) {
        var parts: [String] = []

        if folderCount > 0 {
            parts.append("폴더 \(folderCount)개")
        }
        if imageCount > 0 {
            parts.append("이미지 \(imageCount)개")
        }
        if selectionCount > 0 {
            parts.append("\(selectionCount)개 선택됨")
        }

        infoLabel.stringValue = parts.isEmpty ? "" : parts.joined(separator: "  ·  ")
    }

    func setViewerMode(_ isViewer: Bool, isVideo: Bool = false) {
        if isViewer {
            infoLabel.stringValue = ""
        }
        sizeSlider.isHidden = isViewer
        smallIcon.isHidden = isViewer
        largeIcon.isHidden = isViewer

        // 반전 버튼은 이미지 뷰어에서만 표시 (영상에서는 숨김)
        let showFlip = isViewer && !isVideo
        flipHButton.isHidden = !showFlip
        flipVButton.isHidden = !showFlip
        resetFlipButton.isHidden = !showFlip
    }

    private func setupViews() {
        wantsLayer = true

        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)

        infoLabel.translatesAutoresizingMaskIntoConstraints = false
        infoLabel.font = .systemFont(ofSize: 11)
        infoLabel.textColor = .secondaryLabelColor
        infoLabel.lineBreakMode = .byTruncatingTail
        addSubview(infoLabel)

        // 썸네일 크기 슬라이더
        smallIcon.translatesAutoresizingMaskIntoConstraints = false
        smallIcon.image = NSImage(systemSymbolName: "square.grid.3x3", accessibilityDescription: "작게")
        smallIcon.contentTintColor = .secondaryLabelColor
        addSubview(smallIcon)

        sizeSlider.translatesAutoresizingMaskIntoConstraints = false
        sizeSlider.minValue = Double(Self.minScale)
        sizeSlider.maxValue = Double(Self.maxScale)
        sizeSlider.doubleValue = 1.0
        sizeSlider.controlSize = .small
        sizeSlider.target = self
        sizeSlider.action = #selector(sliderChanged(_:))
        sizeSlider.isContinuous = true
        addSubview(sizeSlider)

        largeIcon.translatesAutoresizingMaskIntoConstraints = false
        largeIcon.image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "크게")
        largeIcon.contentTintColor = .secondaryLabelColor
        addSubview(largeIcon)

        // 이미지 반전 버튼 (뷰어 모드에서만 표시)
        for (button, symbolName, tooltip, action) in [
            (flipHButton, "arrow.left.and.right.righttriangle.left.righttriangle.right", "좌우 반전", #selector(flipHTapped)),
            (flipVButton, "arrow.up.and.down.righttriangle.up.righttriangle.down", "상하 반전", #selector(flipVTapped)),
            (resetFlipButton, "arrow.counterclockwise", "원래대로", #selector(resetFlipTapped)),
        ] as [(NSButton, String, String, Selector)] {
            button.translatesAutoresizingMaskIntoConstraints = false
            button.bezelStyle = .inline
            button.isBordered = false
            button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: tooltip)
            button.toolTip = tooltip
            button.target = self
            button.action = action
            button.contentTintColor = .secondaryLabelColor
            button.isHidden = true
            addSubview(button)
        }

        NSLayoutConstraint.activate([
            separator.topAnchor.constraint(equalTo: topAnchor),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),

            infoLabel.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 1),
            infoLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),

            // 썸네일 슬라이더 (브라우저 모드)
            largeIcon.centerYAnchor.constraint(equalTo: centerYAnchor),
            largeIcon.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            largeIcon.widthAnchor.constraint(equalToConstant: 14),
            largeIcon.heightAnchor.constraint(equalToConstant: 14),

            sizeSlider.centerYAnchor.constraint(equalTo: centerYAnchor),
            sizeSlider.trailingAnchor.constraint(equalTo: largeIcon.leadingAnchor, constant: -4),
            sizeSlider.widthAnchor.constraint(equalToConstant: 80),

            smallIcon.centerYAnchor.constraint(equalTo: centerYAnchor),
            smallIcon.trailingAnchor.constraint(equalTo: sizeSlider.leadingAnchor, constant: -4),
            smallIcon.widthAnchor.constraint(equalToConstant: 14),
            smallIcon.heightAnchor.constraint(equalToConstant: 14),

            infoLabel.trailingAnchor.constraint(lessThanOrEqualTo: smallIcon.leadingAnchor, constant: -8),

            // 이미지 반전 버튼 (뷰어 모드)
            resetFlipButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            resetFlipButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            resetFlipButton.widthAnchor.constraint(equalToConstant: 20),
            resetFlipButton.heightAnchor.constraint(equalToConstant: 20),

            flipVButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            flipVButton.trailingAnchor.constraint(equalTo: resetFlipButton.leadingAnchor, constant: -8),
            flipVButton.widthAnchor.constraint(equalToConstant: 20),
            flipVButton.heightAnchor.constraint(equalToConstant: 20),

            flipHButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            flipHButton.trailingAnchor.constraint(equalTo: flipVButton.leadingAnchor, constant: -8),
            flipHButton.widthAnchor.constraint(equalToConstant: 20),
            flipHButton.heightAnchor.constraint(equalToConstant: 20),
        ])
    }

    @objc private func sliderChanged(_ sender: NSSlider) {
        onThumbnailScaleChanged?(CGFloat(sender.doubleValue))
    }

    @objc private func flipHTapped() { onFlipHorizontal?() }
    @objc private func flipVTapped() { onFlipVertical?() }
    @objc private func resetFlipTapped() { onResetFlip?() }
}
