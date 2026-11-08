import AppKit

/// 창 상단(툴바) 버튼의 공통 규격 — 모든 버튼이 같은 높이·같은 둥근 사각형을 쓴다.
/// 시스템 툴바 항목은 종류마다 캡슐·원·체크박스로 모양이 제각각이라, 모양을 직접 그리는 버튼으로 통일한다.
enum HeaderMetrics {
    static let height: CGFloat = 28
    static let width: CGFloat = 32
    static let cornerRadius: CGFloat = 8
    static let symbolSize: CGFloat = 13
}

/// 툴바 아이콘 버튼. 평소엔 옅은 바탕의 둥근 사각형, 마우스를 올리거나 켜진 토글이면 바탕이 한 단계씩 진해진다.
final class HeaderButton: NSButton {
    private var isHovered = false { didSet { needsDisplay = true } }
    private var trackingArea: NSTrackingArea?
    private let titleText: String?

    init(symbol: String? = nil, title: String? = nil, label: String, toggle: Bool = false) {
        titleText = title
        super.init(frame: NSRect(x: 0, y: 0, width: HeaderMetrics.width, height: HeaderMetrics.height))
        isBordered = false
        bezelStyle = .smallSquare
        focusRingType = .none
        wantsLayer = true
        if toggle { setButtonType(.pushOnPushOff) }
        if let symbol {
            image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)?
                .withSymbolConfiguration(.init(pointSize: HeaderMetrics.symbolSize, weight: .regular))
            imagePosition = .imageOnly
        } else {
            imagePosition = .noImage
        }
        self.title = title ?? ""
        setAccessibilityLabel(label)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: HeaderMetrics.width),
            heightAnchor.constraint(equalToConstant: HeaderMetrics.height),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: NSSize { NSSize(width: HeaderMetrics.width, height: HeaderMetrics.height) }
    override var wantsUpdateLayer: Bool { true }
    override var state: NSControl.StateValue { didSet { needsDisplay = true } }
    override var isEnabled: Bool { didSet { needsDisplay = true; if !isEnabled { isHovered = false } } }

    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let on = state == .on
            // 쉬는 상태에도 보기 방식 그룹의 트랙과 같은 옅은 바탕을 깔아, 모든 버튼이 같은 모양으로 읽히게 한다.
            let alpha: CGFloat = on ? 0.13 : (isHovered ? 0.09 : (isEnabled ? 0.05 : 0.03))
            let fill = NSColor.labelColor.withAlphaComponent(alpha)
            let tint: NSColor = !isEnabled ? .tertiaryLabelColor : (on || isHovered ? .labelColor : .secondaryLabelColor)
            layer?.backgroundColor = fill.cgColor
            layer?.cornerRadius = HeaderMetrics.cornerRadius
            contentTintColor = tint
            if let titleText {
                let style = NSMutableParagraphStyle()
                style.alignment = .center
                attributedTitle = NSAttributedString(string: titleText, attributes: [
                    .font: NSFont.systemFont(ofSize: 12.5, weight: .semibold),
                    .foregroundColor: tint,
                    .paragraphStyle: style,
                ])
            }
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { isHovered = isEnabled }
    override func mouseExited(with event: NSEvent) { isHovered = false }
}

/// 버튼 여러 개 중 하나만 켜지는 그룹(보기 방식 전환). 옅은 트랙 위에 켜진 칸만 바탕색 알약으로 띄운다.
final class HeaderSegmentGroup: NSControl {
    private var buttons: [NSButton] = []

    var selectedSegment: Int = 0 {
        didSet {
            for (index, button) in buttons.enumerated() { button.state = index == selectedSegment ? .on : .off }
            needsDisplay = true
        }
    }

    init(symbols: [(symbol: String, label: String, tip: String)]) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        var previous: NSView?
        for (index, spec) in symbols.enumerated() {
            let button = NSButton()
            button.translatesAutoresizingMaskIntoConstraints = false
            button.isBordered = false
            button.bezelStyle = .smallSquare
            button.focusRingType = .none
            button.setButtonType(.momentaryChange)
            button.image = NSImage(systemSymbolName: spec.symbol, accessibilityDescription: spec.label)?
                .withSymbolConfiguration(.init(pointSize: HeaderMetrics.symbolSize, weight: .regular))
            button.imagePosition = .imageOnly
            button.toolTip = spec.tip
            button.tag = index
            button.target = self
            button.action = #selector(segmentTapped(_:))
            addSubview(button)
            NSLayoutConstraint.activate([
                button.topAnchor.constraint(equalTo: topAnchor),
                button.bottomAnchor.constraint(equalTo: bottomAnchor),
                button.widthAnchor.constraint(equalToConstant: HeaderMetrics.width),
                button.leadingAnchor.constraint(equalTo: previous?.trailingAnchor ?? leadingAnchor),
            ])
            buttons.append(button)
            previous = button
        }
        previous?.trailingAnchor.constraint(equalTo: trailingAnchor).isActive = true
        heightAnchor.constraint(equalToConstant: HeaderMetrics.height).isActive = true
        selectedSegment = 0
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: NSSize {
        NSSize(width: HeaderMetrics.width * CGFloat(buttons.count), height: HeaderMetrics.height)
    }

    @objc private func segmentTapped(_ sender: NSButton) {
        guard sender.tag != selectedSegment else { return }
        selectedSegment = sender.tag
        sendAction(action, to: target)
    }

    override func draw(_ dirtyRect: NSRect) {
        let radius = HeaderMetrics.cornerRadius
        NSColor.labelColor.withAlphaComponent(0.05).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
        for button in buttons {
            let selected = button.tag == selectedSegment
            button.contentTintColor = selected ? .labelColor : .secondaryLabelColor
            guard selected else { continue }
            // 버튼 frame은 베젤 정렬 여백이 섞이므로 정렬 사각형 기준으로 칸을 잡는다.
            let slot = button.alignmentRect(forFrame: button.frame)
            let rect = NSRect(x: slot.minX, y: 0, width: slot.width, height: bounds.height).insetBy(dx: 2, dy: 2)
            let pill = NSBezierPath(roundedRect: rect, xRadius: radius - 2, yRadius: radius - 2)
            NSColor.controlBackgroundColor.setFill()
            pill.fill()
            NSColor.labelColor.withAlphaComponent(0.10).setStroke()
            pill.lineWidth = 0.5
            pill.stroke()
        }
    }
}

/// 툴바 항목 — 뷰를 쓰는 항목은 시스템 자동 검사(validate)가 돌지 않으므로, 컨트롤러의 활성 규칙을 직접 물어 뷰까지 맞춘다.
final class HeaderToolbarItem: NSToolbarItem {
    var enabledRule: (() -> Bool)?

    override func validate() {
        let enabled = enabledRule?() ?? true
        isEnabled = enabled
        (view as? NSControl)?.isEnabled = enabled
    }
}
