import AppKit

/// 사이드바 디자인 토큰 — 밝은 단색 표면 위에 검정 포인트(로고·선택 행) 하나만 쓰는 모노톤 구성.
/// 사이드바는 다크 모드에서도 밝은 표면을 유지하므로(`LibrarySurfaceView`) 고정 색을 쓴다.
enum SidebarStyle {
    static let ink = NSColor(white: 0.07, alpha: 1)            // 로고·선택 행 바탕
    static let primaryText = NSColor(white: 0.16, alpha: 1)
    static let secondaryText = NSColor(white: 0.40, alpha: 1)
    static let tertiaryText = NSColor(white: 0.56, alpha: 1)
    static let iconTint = NSColor(white: 0.30, alpha: 1)
    static let mutedIconTint = NSColor(white: 0.58, alpha: 1)
    static let hoverFill = NSColor(white: 0, alpha: 0.045)
    static let trackFill = NSColor(white: 0, alpha: 0.05)
    static let toggleOnFill = NSColor(white: 0, alpha: 0.08)
    static let badgeFill = NSColor(white: 0, alpha: 0.055)
    static let guideLine = NSColor(white: 0, alpha: 0.10)
    static let divider = NSColor(white: 0, alpha: 0.07)

    static let rowHeight: CGFloat = 32
    static let groupRowHeight: CGFloat = 34
    static let indent: CGFloat = 16
    static let rowCornerRadius: CGFloat = 10
    /// 셀 왼쪽 끝에서 아이콘 중심까지 거리(아이콘 앞 여백 2 + 폭 17의 절반) — 가이드 선을 부모 아이콘 아래에 맞춘다.
    static let iconCenterOffset: CGFloat = 10.5
    /// 선택·호버 배경이 셀 왼쪽보다 이만큼 먼저 시작한다.
    static let rowLeadingPad: CGFloat = 8
    static let rowTrailingInset: CGFloat = 10

    static func symbol(_ name: String, size: CGFloat = 14, weight: NSFont.Weight = .regular) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: size, weight: weight))
    }

    /// 사이드바 상단 로고 — 앱 아이콘(검정 타일)을 그대로 쓰고, 번들 밖(테스트)에서는 시스템 아이콘으로 대신한다.
    static var logoImage: NSImage {
        Bundle.main.image(forResource: "JenaImage") ?? NSApp.applicationIconImage ?? NSImage()
    }
}

// MARK: - Folder Glyph

/// 사이드바의 모든 항목을 폴더 모양으로 통일하기 위한 아이콘.
/// 북마크·카테고리처럼 성격이 다른 항목은 폴더 오른쪽 아래에 작은 배지를 얹어 구분한다(배지 둘레는 투명하게 파낸다).
enum FolderGlyph {
    private static var cache: [String: NSImage] = [:]

    static func image(badge: String? = nil, size: CGFloat = 15) -> NSImage {
        let key = "\(badge ?? "-")@\(size)"
        if let cached = cache[key] { return cached }
        let base = SidebarStyle.symbol("folder", size: size) ?? NSImage()
        guard let badge, let badgeImage = SidebarStyle.symbol(badge, size: size * 0.5, weight: .bold) else {
            base.isTemplate = true
            cache[key] = base
            return base
        }
        let canvas = NSSize(width: base.size.width + 2, height: base.size.height + 2)
        let image = NSImage(size: canvas, flipped: false) { _ in
            base.draw(in: NSRect(x: 0, y: 2, width: base.size.width, height: base.size.height))
            let badgeSize = badgeImage.size
            let origin = NSPoint(x: canvas.width - badgeSize.width, y: 0)
            let badgeRect = NSRect(origin: origin, size: badgeSize)
            // 배지 둘레를 파내 폴더 선과 겹쳐도 읽히게 한다.
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            NSBezierPath(ovalIn: badgeRect.insetBy(dx: -1.6, dy: -1.6)).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            badgeImage.draw(in: badgeRect)
            return true
        }
        image.isTemplate = true
        cache[key] = image
        return image
    }
}

// MARK: - Icon Button

/// 사이드바 상단·하단의 아이콘 버튼. 평소엔 회색 글리프만 보이고, 마우스를 올리거나 켜져 있으면 옅은 바탕이 깔린다.
final class SidebarIconButton: NSButton {
    enum Kind {
        /// 일반 도구 버튼(토글이면 켜졌을 때 옅은 회색 바탕 + 진한 글리프)
        case tool
        /// 세그먼트 트랙 안의 버튼(켜졌을 때 흰 바탕 + 그림자)
        case segment
    }

    private let kind: Kind
    private var isHovered = false { didSet { needsDisplay = true } }
    private var trackingArea: NSTrackingArea?

    init(kind: Kind = .tool, symbol: String, label: String, toggle: Bool = false) {
        self.kind = kind
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        isBordered = false
        bezelStyle = .smallSquare
        imagePosition = .imageOnly
        if toggle { setButtonType(.toggle) }
        setSymbol(symbol, label: label)
        wantsLayer = true
        focusRingType = .none
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setSymbol(_ name: String, label: String) {
        image = SidebarStyle.symbol(name, size: 13, weight: .medium)
        image?.accessibilityDescription = label
        setAccessibilityLabel(label)
    }

    override var state: NSControl.StateValue {
        didSet {
            needsDisplay = true
            superview?.needsDisplay = true
        }
    }
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        let on = state == .on
        let background: NSColor
        let tint: NSColor
        switch kind {
        case .tool:
            background = on ? SidebarStyle.toggleOnFill : (isHovered ? SidebarStyle.hoverFill : .clear)
            tint = on || isHovered ? SidebarStyle.ink : SidebarStyle.secondaryText
        case .segment:
            // 선택 바탕은 트랙(`SidebarSegmentTrack`)이 그린다.
            background = .clear
            tint = on || isHovered ? SidebarStyle.ink : SidebarStyle.tertiaryText
        }
        layer?.backgroundColor = background.cgColor
        layer?.cornerRadius = kind == .segment ? 7 : 8
        layer?.masksToBounds = false
        contentTintColor = tint
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
    override func viewDidHide() { super.viewDidHide(); isHovered = false }
}

/// 폴더/카테고리 보기 전환 버튼을 담는 옅은 회색 트랙.
final class SidebarSegmentTrack: NSView {
    init(buttons: [NSButton]) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        var previous: NSView?
        for button in buttons {
            addSubview(button)
            NSLayoutConstraint.activate([
                button.topAnchor.constraint(equalTo: topAnchor, constant: 2),
                button.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
                button.widthAnchor.constraint(equalToConstant: 30),
                button.leadingAnchor.constraint(equalTo: previous?.trailingAnchor ?? leadingAnchor, constant: previous == nil ? 2 : 1),
            ])
            previous = button
        }
        previous?.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2).isActive = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        SidebarStyle.trackFill.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 9, yRadius: 9).fill()
        // 켜진 버튼 자리에 흰 알약을 깔고 머리카락 테두리로 띄운다.
        // 버튼 frame은 베젤 정렬 여백 때문에 실제 배치보다 커서, 정렬 사각형 기준으로 그린다.
        for case let button as NSButton in subviews where button.state == .on {
            let slot = button.alignmentRect(forFrame: button.frame)
            let rect = NSRect(x: slot.minX, y: 2, width: slot.width, height: bounds.height - 4)
            let pill = NSBezierPath(roundedRect: rect.insetBy(dx: 0.25, dy: 0.25), xRadius: 7, yRadius: 7)
            NSColor.white.setFill()
            pill.fill()
            NSColor(white: 0, alpha: 0.08).setStroke()
            pill.lineWidth = 0.5
            pill.stroke()
        }
    }
}

// MARK: - Row View

/// 사이드바 행 — 선택은 검정 둥근 바탕, 호버는 옅은 회색, 하위 폴더는 부모 아이콘 아래로 가는 가는 세로선으로 묶는다.
final class LibrarySidebarRowView: NSTableRowView {
    /// 조상 폴더 아이콘 중심의 x 좌표들 — 이 위치마다 세로 가이드 선을 긋는다(루트 폴더 행은 빈 배열).
    var guideXs: [CGFloat] = [] { didSet { needsDisplay = true } }
    private var isHovered = false { didSet { needsDisplay = true } }
    private var trackingArea: NSTrackingArea?

    override var interiorBackgroundStyle: NSView.BackgroundStyle { isSelected ? .emphasized : .normal }

    private var cellMinX: CGFloat {
        subviews.first { $0 is NSTableCellView }?.frame.minX ?? 0
    }

    private var pillRect: NSRect {
        let minX = max(4, cellMinX - SidebarStyle.rowLeadingPad)
        return NSRect(x: minX, y: 1, width: max(0, bounds.width - SidebarStyle.rowTrailingInset - minX),
                      height: bounds.height - 2)
    }

    override func layout() {
        super.layout()
        needsDisplay = true
    }

    override func drawBackground(in dirtyRect: NSRect) {
        if !guideXs.isEmpty {
            SidebarStyle.guideLine.setFill()
            // 조상 폴더마다 그 아이콘 중심 아래로 세로선을 그어, 같은 부모의 하위 항목이 하나로 이어져 보이게 한다.
            for x in guideXs {
                NSRect(x: round(x) - 0.5, y: 0, width: 1, height: bounds.height).fill()
            }
        }
        if isHovered && !isSelected && !isGroupRowStyle {
            SidebarStyle.hoverFill.setFill()
            NSBezierPath(roundedRect: pillRect, xRadius: SidebarStyle.rowCornerRadius, yRadius: SidebarStyle.rowCornerRadius).fill()
        }
    }

    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else { return }
        SidebarStyle.ink.setFill()
        NSBezierPath(roundedRect: pillRect, xRadius: SidebarStyle.rowCornerRadius, yRadius: SidebarStyle.rowCornerRadius).fill()
    }

    override func drawDraggingDestinationFeedback(in dirtyRect: NSRect) {
        NSColor.controlAccentColor.withAlphaComponent(0.14).setFill()
        let path = NSBezierPath(roundedRect: pillRect, xRadius: SidebarStyle.rowCornerRadius, yRadius: SidebarStyle.rowCornerRadius)
        path.fill()
        NSColor.controlAccentColor.withAlphaComponent(0.6).setStroke()
        path.lineWidth = 1.5
        path.stroke()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    override func prepareForReuse() {
        super.prepareForReuse()
        isHovered = false
    }
}

// MARK: - Item Cell

/// 폴더·이미지·북마크·카테고리 행 공용 셀 — [아이콘][이름 ……][개수 배지][펼침 화살표]
final class SidebarItemCellView: NSTableCellView {
    enum Role { case root, folder, file, special }

    let iconView = NSImageView()
    let nameField = NSTextField(labelWithString: "")
    let chevronButton = NSButton()
    private let badge = NSView()
    private let badgeLabel = NSTextField(labelWithString: "")
    private var nameToBadge: NSLayoutConstraint!
    private var nameToChevron: NSLayoutConstraint!
    private var badgeToChevron: NSLayoutConstraint!
    private var badgeToEdge: NSLayoutConstraint!

    var role: Role = .folder { didSet { applyStyle() } }
    /// 사용자 지정 폴더 색(기본색이면 nil — 모노톤 아이콘)
    var iconColor: NSColor? { didSet { applyStyle() } }
    /// 이름을 고치는 중이면 선택 행이라도 편집 필드 글자를 어둡게 둔다.
    var isEditingName = false { didSet { applyStyle() } }

    var count: String = "" {
        didSet {
            badgeLabel.stringValue = count
            badge.isHidden = count.isEmpty
            updateTrailingLayout()
        }
    }

    var isExpandable = false { didSet { chevronButton.isHidden = !isExpandable; updateTrailingLayout() } }
    var isExpanded = false { didSet { if oldValue != isExpanded { updateChevronImage() } } }

    private func updateChevronImage() {
        chevronButton.image = SidebarStyle.symbol(isExpanded ? "chevron.down" : "chevron.right", size: 10, weight: .semibold)
        chevronButton.setAccessibilityLabel(isExpanded ? "접기" : "펼치기")
    }

    override var backgroundStyle: NSView.BackgroundStyle { didSet { applyStyle() } }

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyDown
        addSubview(iconView)
        imageView = iconView

        nameField.translatesAutoresizingMaskIntoConstraints = false
        nameField.lineBreakMode = .byTruncatingTail
        nameField.cell?.truncatesLastVisibleLine = true
        nameField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(nameField)
        textField = nameField

        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.wantsLayer = true
        badge.layer?.cornerRadius = 8
        badge.isHidden = true
        addSubview(badge)
        badgeLabel.translatesAutoresizingMaskIntoConstraints = false
        badgeLabel.font = .monospacedDigitSystemFont(ofSize: 10.5, weight: .medium)
        badgeLabel.alignment = .center
        badgeLabel.setContentHuggingPriority(.required, for: .horizontal)
        badgeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        badge.addSubview(badgeLabel)

        chevronButton.translatesAutoresizingMaskIntoConstraints = false
        chevronButton.isBordered = false
        chevronButton.bezelStyle = .smallSquare
        chevronButton.imagePosition = .imageOnly
        chevronButton.focusRingType = .none
        chevronButton.isHidden = true
        addSubview(chevronButton)
        updateChevronImage()

        nameToBadge = nameField.trailingAnchor.constraint(lessThanOrEqualTo: badge.leadingAnchor, constant: -6)
        nameToChevron = nameField.trailingAnchor.constraint(lessThanOrEqualTo: chevronButton.leadingAnchor, constant: -4)
        badgeToChevron = badge.trailingAnchor.constraint(equalTo: chevronButton.leadingAnchor, constant: -2)
        badgeToEdge = badge.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 17),
            iconView.heightAnchor.constraint(equalToConstant: 17),

            nameField.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 9),
            nameField.centerYAnchor.constraint(equalTo: centerYAnchor),
            nameField.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),

            badge.centerYAnchor.constraint(equalTo: centerYAnchor),
            badge.heightAnchor.constraint(equalToConstant: 17),
            badge.widthAnchor.constraint(greaterThanOrEqualToConstant: 22),
            badgeLabel.leadingAnchor.constraint(equalTo: badge.leadingAnchor, constant: 6),
            badgeLabel.trailingAnchor.constraint(equalTo: badge.trailingAnchor, constant: -6),
            badgeLabel.centerYAnchor.constraint(equalTo: badge.centerYAnchor),

            chevronButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            chevronButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevronButton.widthAnchor.constraint(equalToConstant: 20),
            chevronButton.heightAnchor.constraint(equalToConstant: 20),
        ])
        updateTrailingLayout()
        applyStyle()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func updateTrailingLayout() {
        let hasBadge = !count.isEmpty
        nameToBadge.isActive = hasBadge
        nameToChevron.isActive = !hasBadge && isExpandable
        badgeToChevron.isActive = hasBadge && isExpandable
        badgeToEdge.isActive = hasBadge && !isExpandable
    }

    private func applyStyle() {
        let selected = backgroundStyle == .emphasized
        let darkText = isEditingName || !selected
        switch role {
        case .root:
            nameField.font = .systemFont(ofSize: 13, weight: selected ? .semibold : .medium)
        case .file:
            nameField.font = .systemFont(ofSize: 12.5, weight: selected ? .medium : .regular)
        case .folder, .special:
            nameField.font = .systemFont(ofSize: 13, weight: selected ? .semibold : .regular)
        }
        nameField.textColor = darkText ? (role == .file ? SidebarStyle.secondaryText : SidebarStyle.primaryText) : .white

        if let iconColor {
            iconView.contentTintColor = iconColor
        } else if selected {
            iconView.contentTintColor = .white
        } else {
            iconView.contentTintColor = role == .file ? SidebarStyle.mutedIconTint : SidebarStyle.iconTint
        }
        badge.layer?.backgroundColor = (selected ? NSColor(white: 1, alpha: 0.16) : SidebarStyle.badgeFill).cgColor
        badgeLabel.textColor = selected ? NSColor(white: 1, alpha: 0.9) : SidebarStyle.secondaryText
        chevronButton.contentTintColor = selected ? NSColor(white: 1, alpha: 0.85) : SidebarStyle.tertiaryText
    }
}

// MARK: - Group Header Cell

/// "폴더 (3)"처럼 섹션 이름과 항목 수를 함께 보여주는 헤더.
final class SidebarGroupCellView: NSTableCellView {
    private let titleField = NSTextField(labelWithString: "")

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        titleField.translatesAutoresizingMaskIntoConstraints = false
        titleField.lineBreakMode = .byTruncatingTail
        addSubview(titleField)
        textField = titleField
        NSLayoutConstraint.activate([
            titleField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            titleField.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -4),
            titleField.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(title: String, count: Int?) {
        let text = NSMutableAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: SidebarStyle.tertiaryText,
        ])
        if let count {
            text.append(NSAttributedString(string: "  \(count)", attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .regular),
                .foregroundColor: NSColor(white: 0.68, alpha: 1),
            ]))
        }
        titleField.attributedStringValue = text
    }
}

/// 섹션 사이의 머리카락 선.
final class SidebarDivider: NSView {
    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = SidebarStyle.divider.cgColor
        heightAnchor.constraint(equalToConstant: 1).isActive = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
