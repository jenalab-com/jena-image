import AppKit

/// 다른 이름으로 저장 패널의 accessory view (포맷 선택 + 품질 슬라이더)
final class ExportAccessoryView: NSView {
    var selectedFormat: ImageFormat = .jpeg {
        didSet { updateQualityVisibility() }
    }
    var quality: Float { Float(qualitySlider.integerValue) }

    private let formatPopup = NSPopUpButton()
    private let qualitySlider = NSSlider()
    private let qualityLabel = NSTextField(labelWithString: "품질:")
    private let qualityValueLabel = NSTextField(labelWithString: "85")

    override init(frame: NSRect) {
        super.init(frame: NSRect(x: 0, y: 0, width: 300, height: 64))
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        // 포맷 드롭다운
        let formatLabel = NSTextField(labelWithString: "포맷:")
        formatLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(formatLabel)

        formatPopup.translatesAutoresizingMaskIntoConstraints = false
        for format in ImageFormat.allCases {
            formatPopup.addItem(withTitle: format.displayName)
            formatPopup.lastItem?.representedObject = format
        }
        formatPopup.target = self
        formatPopup.action = #selector(formatChanged(_:))
        addSubview(formatPopup)

        // 품질 슬라이더
        qualityLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(qualityLabel)

        qualitySlider.translatesAutoresizingMaskIntoConstraints = false
        qualitySlider.minValue = 1
        qualitySlider.maxValue = 100
        qualitySlider.integerValue = 85
        qualitySlider.target = self
        qualitySlider.action = #selector(qualityChanged(_:))
        addSubview(qualitySlider)

        qualityValueLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(qualityValueLabel)

        NSLayoutConstraint.activate([
            formatLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            formatLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            formatPopup.leadingAnchor.constraint(equalTo: formatLabel.trailingAnchor, constant: 8),
            formatPopup.centerYAnchor.constraint(equalTo: formatLabel.centerYAnchor),
            formatPopup.widthAnchor.constraint(equalToConstant: 120),

            qualityLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            qualityLabel.topAnchor.constraint(equalTo: formatLabel.bottomAnchor, constant: 12),
            qualitySlider.leadingAnchor.constraint(equalTo: qualityLabel.trailingAnchor, constant: 8),
            qualitySlider.centerYAnchor.constraint(equalTo: qualityLabel.centerYAnchor),
            qualitySlider.widthAnchor.constraint(equalToConstant: 150),
            qualityValueLabel.leadingAnchor.constraint(equalTo: qualitySlider.trailingAnchor, constant: 8),
            qualityValueLabel.centerYAnchor.constraint(equalTo: qualityLabel.centerYAnchor),
        ])

        // 초기 포맷 선택
        if let index = ImageFormat.allCases.firstIndex(of: selectedFormat) {
            formatPopup.selectItem(at: index)
        }
        updateQualityVisibility()
    }

    @objc private func formatChanged(_ sender: NSPopUpButton) {
        guard let format = sender.selectedItem?.representedObject as? ImageFormat else { return }
        selectedFormat = format
    }

    @objc private func qualityChanged(_ sender: NSSlider) {
        qualityValueLabel.stringValue = "\(sender.integerValue)"
    }

    private func updateQualityVisibility() {
        let isVisible = selectedFormat.isLossy
        qualityLabel.isHidden = !isVisible
        qualitySlider.isHidden = !isVisible
        qualityValueLabel.isHidden = !isVisible
    }
}
