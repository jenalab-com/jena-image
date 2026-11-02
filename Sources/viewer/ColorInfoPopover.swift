import AppKit

/// "HEX #E76F51 [복사]" 한 줄. 패널의 "커서 위치 색"과 칩 정보창이 같이 쓴다.
final class ColorValueRow: NSView {
    enum Kind: CaseIterable {
        case hex, rgb, cmyk
        var title: String { switch self { case .hex: "HEX"; case .rgb: "RGB"; case .cmyk: "CMYK" } }
        func text(_ c: RGB8) -> String {
            switch self { case .hex: ColorFormat.hex(c); case .rgb: ColorFormat.rgbString(c); case .cmyk: ColorFormat.cmykString(c) }
        }
    }

    let kind: Kind
    var onCopy: ((String) -> Void)?
    private let valueLabel = NSTextField(labelWithString: "—")
    private let copyButton = NSButton()
    private var value = ""
    private var resetWork: DispatchWorkItem?

    init(kind: Kind) {
        self.kind = kind
        super.init(frame: .zero)
        let title = NSTextField(labelWithString: kind.title)
        title.font = .systemFont(ofSize: 11, weight: .semibold)
        title.textColor = .secondaryLabelColor
        title.widthAnchor.constraint(equalToConstant: 38).isActive = true
        valueLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        valueLabel.lineBreakMode = .byClipping
        copyButton.bezelStyle = .inline
        copyButton.isBordered = false
        copyButton.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: L10n.string(.colorCopyValue))
        copyButton.toolTip = L10n.string(.colorCopyValue)
        copyButton.refusesFirstResponder = true       // 포커스를 가져가면 ⌥(flagsChanged)가 뷰어로 오지 않는다
        copyButton.isEnabled = false
        copyButton.target = self
        copyButton.action = #selector(copyTapped)
        let stack = NSStackView(views: [title, valueLabel, NSView(), copyButton])
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func setColor(_ color: RGB8?) {
        resetWork?.cancel()
        value = color.map(kind.text) ?? ""
        valueLabel.stringValue = color == nil ? "—" : value
        copyButton.isEnabled = color != nil
    }

    /// 값 자리에 "복사됨"을 약 1초 보여 준다.
    func flashCopied() {
        resetWork?.cancel()
        valueLabel.stringValue = L10n.string(.colorCopied)
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.valueLabel.stringValue = self.value.isEmpty ? "—" : self.value
        }
        resetWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    @objc private func copyTapped() {
        guard !value.isEmpty else { return }
        onCopy?(value)
        flashCopied()
    }
}

/// 칩 정보창 내용: 색 견본 + HEX·RGB·CMYK 행. 마우스 진입·이탈을 유예 로직에 알린다.
final class ColorInfoView: NSView {
    let rows = ColorValueRow.Kind.allCases.map { ColorValueRow(kind: $0) }
    var onMouseEntered: (() -> Void)?
    var onMouseExited: (() -> Void)?
    private let swatch = NSView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        swatch.wantsLayer = true
        swatch.layer?.cornerRadius = 6
        swatch.layer?.borderWidth = 1
        swatch.layer?.borderColor = NSColor.separatorColor.cgColor
        swatch.translatesAutoresizingMaskIntoConstraints = false
        swatch.heightAnchor.constraint(equalToConstant: 36).isActive = true
        let stack = NSStackView(views: [swatch] + rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            swatch.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -24),
            widthAnchor.constraint(equalToConstant: 260),
        ])
        rows.forEach { $0.widthAnchor.constraint(equalTo: swatch.widthAnchor).isActive = true }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func setColor(_ color: RGB8) {
        swatch.layer?.backgroundColor = NSColor(srgbRed: CGFloat(color.r) / 255, green: CGFloat(color.g) / 255,
                                                blue: CGFloat(color.b) / 255, alpha: 1).cgColor
        rows.forEach { $0.setColor(color) }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }
    override func mouseEntered(with event: NSEvent) { onMouseEntered?() }
    override func mouseExited(with event: NSEvent) { onMouseExited?() }
}

/// 칩 위쪽에 붙는 정보창. NSPopover는 별도 창이라 패널 경계에 잘리지 않고, 칩에서 정보창으로 마우스를 옮길 수 있다.
/// 닫힘은 HoverGrace가 정한다(칩 ↔ 정보창 사이 틈에서 닫히지 않게).
final class ColorInfoPopover: NSObject {
    private let popover = NSPopover()
    private let info = ColorInfoView()
    private var grace = HoverGrace()
    private weak var currentChip: NSView?
    var onCopy: ((String) -> Void)?

    override init() {
        super.init()
        let controller = NSViewController()
        controller.view = info
        popover.contentViewController = controller
        popover.behavior = .applicationDefined      // 바깥 클릭·포커스 이동으로 닫히지 않게. 닫힘은 우리가 정한다.
        popover.animates = false
        info.onMouseEntered = { [weak self] in self?.grace.enter() }
        info.onMouseExited = { [weak self] in self?.grace.exit() }
        info.rows.forEach { row in row.onCopy = { [weak self] in self?.onCopy?($0) } }
        grace.onClose = { [weak self] in self?.close() }
    }

    func chipEntered(_ chip: NSView, color: RGB8) {
        grace.enter()
        info.setColor(color)
        if currentChip !== chip || !popover.isShown {
            if popover.isShown { popover.close() }
            currentChip = chip
            popover.show(relativeTo: chip.bounds, of: chip, preferredEdge: .maxY)   // 칩 위쪽 (chip은 비뒤집힘 뷰)
        }
    }

    func chipExited() { grace.exit() }

    /// 칩을 클릭해 HEX를 복사했을 때 HEX 줄에 "복사됨".
    func flashHexCopied() { info.rows.first { $0.kind == .hex }?.flashCopied() }

    func close() {
        grace = HoverGrace()
        grace.onClose = { [weak self] in self?.close() }
        popover.close()
        currentChip = nil
    }
}
