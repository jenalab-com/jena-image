import AppKit

/// 비율 순 칩 한 개. 칩 아래에 비율(%).
private final class ColorChipView: NSView {
    static let size = CGSize(width: 44, height: 62)
    let swatch: ColorSwatch
    var onHover: ((Bool) -> Void)?
    var onClick: (() -> Void)?

    init(swatch: ColorSwatch) {
        self.swatch = swatch
        super.init(frame: CGRect(origin: .zero, size: Self.size))
        setAccessibilityLabel("\(ColorFormat.hex(swatch.color)) \(Int((swatch.ratio * 100).rounded()))%")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let c = swatch.color
        let chip = CGRect(x: 0, y: 18, width: bounds.width, height: bounds.height - 18)
        NSColor(srgbRed: CGFloat(c.r) / 255, green: CGFloat(c.g) / 255, blue: CGFloat(c.b) / 255, alpha: 1).setFill()
        let path = NSBezierPath(roundedRect: chip, xRadius: 6, yRadius: 6)
        path.fill()
        NSColor.separatorColor.setStroke(); path.lineWidth = 1; path.stroke()
        let pct = swatch.ratio >= 0.1 ? String(format: "%.0f%%", swatch.ratio * 100) : String(format: "%.1f%%", swatch.ratio * 100)
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.secondaryLabelColor]
        let s = (pct as NSString).size(withAttributes: attrs)
        (pct as NSString).draw(at: CGPoint(x: (bounds.width - s.width) / 2, y: 2), withAttributes: attrs)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }
    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
    override func mouseDown(with event: NSEvent) { onClick?() }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
}

/// 칩을 줄바꿈하며 배치하는 문서 뷰(위-왼쪽 원점).
private final class ChipFlowView: NSView {
    override var isFlipped: Bool { true }
    var chips: [ColorChipView] = [] {
        didSet { oldValue.forEach { $0.removeFromSuperview() }; chips.forEach(addSubview); relayout(width: bounds.width) }
    }

    func relayout(width: CGFloat) {
        let r = ChipFlowLayout.frames(count: chips.count, itemSize: ColorChipView.size, spacing: 8, width: max(width, 1))
        for (chip, frame) in zip(chips, r.frames) { chip.frame = frame }
        frame.size = CGSize(width: width, height: max(r.height, 1))
    }
}

/// 이미지 아래에서 올라오는 색상 서랍.
final class ColorPalettePanel: NSView {
    enum State { case loading, empty, ready([ColorSwatch]) }
    static let height: CGFloat = 150

    var onMagnifierToggled: ((Bool) -> Void)?
    var onToleranceChanged: ((Double) -> Void)?
    var onCopyAllHex: (() -> Void)?

    private let magnifierToggle = NSButton()
    private let slider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let countLabel = NSTextField(labelWithString: "")
    private let copyAllButton = NSButton(title: "", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "")
    private let progress = NSProgressIndicator()
    private let scroll = NSScrollView()
    private let flow = ChipFlowView()
    private let popover = ColorInfoPopover()

    // "커서 위치 색" 칸
    private let cursorBox = NSStackView()
    private let cursorSwatch = NSView()
    private let cursorRows = ColorValueRow.Kind.allCases.map { ColorValueRow(kind: $0) }
    private var liveColor: RGB8?
    private var pickedColor: RGB8?
    private var magnifierOn = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.96).cgColor
        setupViews()
        setTolerance(AppSettings.shared.colorTolerance)
        setState(.empty)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Public

    func setState(_ state: State) {
        popover.close()
        switch state {
        case .loading:
            flow.chips = []
            statusLabel.stringValue = L10n.string(.colorExtracting); statusLabel.isHidden = false
            progress.startAnimation(nil); progress.isHidden = false
            countLabel.stringValue = ""; copyAllButton.isEnabled = false
            liveColor = nil
            pickedColor = nil
            refreshCursorBox()
        case .empty:
            flow.chips = []
            statusLabel.stringValue = L10n.string(.colorNoColors); statusLabel.isHidden = false
            progress.stopAnimation(nil); progress.isHidden = true
            countLabel.stringValue = ""; copyAllButton.isEnabled = false
        case .ready(let swatches):
            statusLabel.isHidden = true
            progress.stopAnimation(nil); progress.isHidden = true
            flow.chips = swatches.map(makeChip)
            flow.relayout(width: scroll.contentSize.width)
            countLabel.stringValue = String(format: L10n.string(.colorCountFormat), swatches.count)
            copyAllButton.isEnabled = !swatches.isEmpty
        }
    }

    func setTolerance(_ value: Double) { slider.doubleValue = value }

    func setMagnifierOn(_ on: Bool) {
        magnifierOn = on
        magnifierToggle.state = on ? .on : .off
        cursorBox.isHidden = !on
        refreshCursorBox()
    }

    func setHover(_ color: RGB8?) { liveColor = color; refreshCursorBox() }
    func setPicked(_ color: RGB8) { pickedColor = color; refreshCursorBox() }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { popover.close() }
        super.viewWillMove(toWindow: newWindow)
    }

    override func layout() {
        super.layout()
        flow.relayout(width: scroll.contentSize.width)
    }

    // MARK: - Private

    private func refreshCursorBox() {
        guard magnifierOn else { return }
        let color = liveColor ?? pickedColor
        cursorSwatch.layer?.backgroundColor = color.map {
            NSColor(srgbRed: CGFloat($0.r) / 255, green: CGFloat($0.g) / 255, blue: CGFloat($0.b) / 255, alpha: 1).cgColor
        } ?? NSColor.quaternaryLabelColor.cgColor
        cursorRows.forEach { $0.setColor(color) }
    }

    private func makeChip(_ swatch: ColorSwatch) -> ColorChipView {
        let chip = ColorChipView(swatch: swatch)
        chip.onHover = { [weak self, weak chip] inside in
            guard let self, let chip else { return }
            if inside { self.popover.chipEntered(chip, color: swatch.color) } else { self.popover.chipExited() }
        }
        chip.onClick = { [weak self] in
            ColorClipboard.copy(ColorFormat.hex(swatch.color))
            self?.popover.flashHexCopied()
        }
        return chip
    }

    private func setupViews() {
        popover.onCopy = { ColorClipboard.copy($0) }

        magnifierToggle.setButtonType(.pushOnPushOff)
        magnifierToggle.bezelStyle = .texturedRounded
        magnifierToggle.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: L10n.string(.colorMagnifier))
        magnifierToggle.toolTip = L10n.string(.colorMagnifier) + " (⌥)"
        magnifierToggle.refusesFirstResponder = true
        magnifierToggle.target = self
        magnifierToggle.action = #selector(magnifierToggled)

        let rangeLabel = NSTextField(labelWithString: L10n.string(.colorRange))
        rangeLabel.font = .systemFont(ofSize: 12)
        slider.minValue = AppSettings.colorToleranceRange.lowerBound
        slider.maxValue = AppSettings.colorToleranceRange.upperBound
        slider.isContinuous = true
        slider.refusesFirstResponder = true      // 슬라이더가 포커스를 가져가면 ⌥(flagsChanged)가 뷰어로 오지 않는다
        slider.target = self
        slider.action = #selector(sliderChanged)
        slider.widthAnchor.constraint(equalToConstant: 200).isActive = true
        countLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        countLabel.textColor = .secondaryLabelColor

        copyAllButton.title = L10n.string(.colorCopyAllHex)
        copyAllButton.bezelStyle = .rounded
        copyAllButton.controlSize = .small
        copyAllButton.refusesFirstResponder = true
        copyAllButton.target = self
        copyAllButton.action = #selector(copyAllTapped)

        let top = NSStackView(views: [magnifierToggle, rangeLabel, slider, countLabel, NSView(), copyAllButton])
        top.orientation = .horizontal
        top.spacing = 8

        // 커서 위치 색 칸
        let cursorTitle = NSTextField(labelWithString: L10n.string(.colorCursor))
        cursorTitle.font = .systemFont(ofSize: 11, weight: .semibold)
        cursorSwatch.wantsLayer = true
        cursorSwatch.layer?.cornerRadius = 4
        cursorSwatch.translatesAutoresizingMaskIntoConstraints = false
        cursorSwatch.heightAnchor.constraint(equalToConstant: 14).isActive = true
        cursorRows.forEach { row in row.onCopy = { ColorClipboard.copy($0) } }
        cursorBox.setViews([cursorTitle, cursorSwatch] + cursorRows, in: .top)
        cursorBox.orientation = .vertical
        cursorBox.alignment = .leading
        cursorBox.spacing = 3
        cursorBox.widthAnchor.constraint(equalToConstant: 240).isActive = true
        cursorSwatch.widthAnchor.constraint(equalTo: cursorBox.widthAnchor).isActive = true
        cursorRows.forEach { $0.widthAnchor.constraint(equalTo: cursorBox.widthAnchor).isActive = true }
        cursorBox.isHidden = true

        // 칩 영역
        scroll.documentView = flow
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.scrollerStyle = .overlay
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        progress.style = .spinning
        progress.controlSize = .small
        progress.isIndeterminate = true
        progress.isHidden = true
        let status = NSStackView(views: [progress, statusLabel])
        status.spacing = 8

        let body = NSStackView(views: [cursorBox, scroll])
        body.orientation = .horizontal
        body.alignment = .top
        body.spacing = 12

        for view in [top, body, status] as [NSView] { view.translatesAutoresizingMaskIntoConstraints = false; addSubview(view) }
        scroll.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            top.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            top.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            top.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            body.topAnchor.constraint(equalTo: top.bottomAnchor, constant: 8),
            body.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            body.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            body.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            scroll.heightAnchor.constraint(equalTo: body.heightAnchor),
            status.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
            status.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            heightAnchor.constraint(equalToConstant: Self.height),
        ])
    }

    @objc private func magnifierToggled() {
        let on = magnifierToggle.state == .on
        setMagnifierOn(on)
        onMagnifierToggled?(on)
    }
    @objc private func sliderChanged() { onToleranceChanged?(slider.doubleValue) }
    @objc private func copyAllTapped() { onCopyAllHex?() }
}
