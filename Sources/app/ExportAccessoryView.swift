import AppKit

/// 다른 이름으로 저장 패널의 accessory view (포맷 선택 + 품질 슬라이더)
final class ExportAccessoryView: NSView {
    /// 쓸 수 없는 포맷을 넣으면 목록의 첫 포맷(JPEG)으로 바꾼다.
    var selectedFormat: ImageFormat = .jpeg {
        didSet {
            // didSet 안에서 다시 대입해도 관찰자는 재호출되지 않으므로 보정 뒤 갱신까지 여기서 끝낸다.
            if !ImageFormat.writableFormats.contains(selectedFormat) {
                selectedFormat = ImageFormat.writableFormats[0]
            }
            if let index = ImageFormat.writableFormats.firstIndex(of: selectedFormat), formatPopup.indexOfSelectedItem != index {
                formatPopup.selectItem(at: index)
            }
            updateQualityVisibility()
        }
    }
    var quality: Float {
        get { Float(qualitySlider.integerValue) }
        set {
            qualitySlider.integerValue = Int(newValue)
            qualityValueLabel.stringValue = "\(qualitySlider.integerValue)"
        }
    }

    /// 일괄 내보내기 진행 중 잠그기 위한 스위치
    var isEnabled: Bool = true {
        didSet {
            formatPopup.isEnabled = isEnabled
            qualitySlider.isEnabled = isEnabled
        }
    }

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
        for format in ImageFormat.writableFormats {
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
        if let index = ImageFormat.writableFormats.firstIndex(of: selectedFormat) {
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
