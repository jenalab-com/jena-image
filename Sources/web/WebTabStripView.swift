import AppKit

/// 웹 패널 머리줄 아래의 탭 줄. 탭 항목(제목 + 닫기)을 나란히 두고 끝에 새 탭 버튼을 둔다.
/// 항목 폭은 자리를 나눠 90~180이고, 최소 폭으로도 넘치면 옆으로 스크롤한다.
/// 새로 연 탭과 고른 탭은 보이게 스크롤한다.
final class WebTabStripView: NSView {
    static let height: CGFloat = 28
    static let minimumItemWidth: CGFloat = 90
    static let maximumItemWidth: CGFloat = 180
    private static let spacing: CGFloat = 2
    private static let inset: CGFloat = 8
    private static let buttonSize: CGFloat = 24

    let newTabButton: NSButton
    private(set) var items: [WebTabItemView] = []
    var onSelect: ((Int) -> Void)?
    var onClose: ((Int) -> Void)?
    var onNewTab: (() -> Void)?

    private let scrollView = WebTabStripScrollView()
    /// 지금 보이는 부분(항목 `frame`과 같은 좌표).
    var visibleItemsRect: NSRect { scrollView.documentVisibleRect }
    private let documentView = WebTabStripDocumentView()
    private var selectedID: Int?
    private var revealID: Int?

    override init(frame frameRect: NSRect) {
        newTabButton = NSButton(image: NSImage(systemSymbolName: "plus", accessibilityDescription: "새 탭")!, target: nil, action: nil)
        super.init(frame: frameRect)
        newTabButton.target = self
        newTabButton.action = #selector(newTabClicked)
        newTabButton.isBordered = false
        newTabButton.contentTintColor = .secondaryLabelColor
        newTabButton.toolTip = "새 탭"
        newTabButton.setAccessibilityLabel("새 탭")
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = false
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.documentView = documentView
        addSubview(scrollView)
        addSubview(newTabButton)
    }
    required init?(coder: NSCoder) { fatalError() }

    /// 엔진의 탭 목록으로 항목을 맞춘다. 있던 항목은 다시 쓰고, 새로 생긴 탭이나 바뀐 고른 탭을 보이게 한다.
    func update(tabs: [WebTabInfo], selectedID: Int?) {
        var existing = Dictionary(uniqueKeysWithValues: items.map { ($0.tabID, $0) })
        var added: [Int] = []
        items = tabs.map { tab in
            let item = existing.removeValue(forKey: tab.id) ?? makeItem(tab.id)
            if item.superview !== documentView { documentView.addSubview(item); added.append(tab.id) }
            item.update(tab, selected: tab.id == selectedID)
            return item
        }
        for item in existing.values { item.removeFromSuperview() }
        // 새로 생긴 탭 중에 고른 탭이 있으면(복원·새 탭) 그 탭을, 아니면 마지막으로 생긴 탭을 보인다.
        if let selectedID, added.contains(selectedID) {
            revealID = selectedID
        } else if let id = added.last {
            revealID = id
        } else if selectedID != self.selectedID {
            revealID = selectedID
        }
        self.selectedID = selectedID
        needsLayout = true
    }

    private func makeItem(_ id: Int) -> WebTabItemView {
        let item = WebTabItemView(tabID: id)
        item.onSelect = { [weak self] in self?.onSelect?(id) }
        item.titleButton.target = self
        item.titleButton.action = #selector(itemClicked(_:))
        item.closeButton.target = self
        item.closeButton.action = #selector(closeClicked(_:))
        return item
    }

    override func layout() {
        super.layout()
        let count = CGFloat(items.count)
        let available = max(0, bounds.width - Self.inset * 2 - Self.buttonSize - 4)
        let fair = count > 0 ? (available - Self.spacing * (count - 1)) / count : 0
        let itemWidth = min(Self.maximumItemWidth, max(Self.minimumItemWidth, fair))
        let contentWidth = count > 0 ? count * itemWidth + Self.spacing * (count - 1) : 0
        let viewport = min(contentWidth, available)
        scrollView.frame = NSRect(x: Self.inset, y: 0, width: viewport, height: bounds.height)
        documentView.frame = NSRect(x: 0, y: 0, width: contentWidth, height: bounds.height)
        for (index, item) in items.enumerated() {
            item.frame = NSRect(x: CGFloat(index) * (itemWidth + Self.spacing), y: 2, width: itemWidth, height: bounds.height - 4)
        }
        newTabButton.frame = NSRect(x: scrollView.frame.maxX + 4, y: (bounds.height - Self.buttonSize) / 2,
                                    width: Self.buttonSize, height: Self.buttonSize)
        // 탭이 줄어 내용이 좁아졌으면 스크롤 위치를 안으로 당긴다.
        let clip = scrollView.contentView
        clip.scroll(to: NSPoint(x: min(clip.bounds.minX, max(0, contentWidth - viewport)), y: 0))
        // 폭이 아직 없을 때(창에 붙기 전)는 보이기 요청을 남겨 두었다가 다음 배치에서 한다.
        if bounds.width > 0, let id = revealID, let item = items.first(where: { $0.tabID == id }) {
            revealID = nil
            item.scrollToVisible(item.bounds)
        }
        scrollView.reflectScrolledClipView(clip)
    }

    @objc private func newTabClicked() { onNewTab?() }
    @objc private func itemClicked(_ sender: NSButton) {
        guard let item = sender.superview as? WebTabItemView else { return }
        onSelect?(item.tabID)
    }
    @objc private func closeClicked(_ sender: NSButton) {
        guard let item = sender.superview as? WebTabItemView else { return }
        onClose?(item.tabID)
    }
}

/// 탭 항목: 제목 + 닫기 버튼. 닫기 버튼 밖 어디를 눌러도 고른다.
/// 고른 탭은 사이드바의 선택 행처럼 진한 바탕(밝은 화면은 검정, 어두운 화면은 흰색)에 반전 글씨로 구분한다.
final class WebTabItemView: NSView {
    let tabID: Int
    var onSelect: (() -> Void)?
    let titleButton = NSButton(title: "", target: nil, action: nil)
    let closeButton = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "탭 닫기")!, target: nil, action: nil)
    private(set) var isSelected = false

    init(tabID: Int) {
        self.tabID = tabID
        super.init(frame: .zero)
        titleButton.isBordered = false
        titleButton.alignment = .left
        titleButton.lineBreakMode = .byTruncatingTail
        titleButton.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        closeButton.isBordered = false
        closeButton.imagePosition = .imageOnly
        closeButton.image = closeButton.image?.withSymbolConfiguration(.init(pointSize: 9, weight: .medium))
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.toolTip = "탭 닫기"
        for control in [titleButton, closeButton] {
            control.translatesAutoresizingMaskIntoConstraints = false
            addSubview(control)
        }
        NSLayoutConstraint.activate([
            titleButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            titleButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleButton.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -2),
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 18),
            closeButton.heightAnchor.constraint(equalToConstant: 18),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func update(_ tab: WebTabInfo, selected: Bool) {
        titleButton.title = tab.title
        titleButton.toolTip = tab.address.isEmpty ? tab.title : "\(tab.title)\n\(tab.address)"
        titleButton.font = .systemFont(ofSize: 12, weight: selected ? .semibold : .regular)
        titleButton.contentTintColor = selected ? .textBackgroundColor : .secondaryLabelColor
        closeButton.contentTintColor = selected ? .textBackgroundColor : .secondaryLabelColor
        closeButton.setAccessibilityLabel("탭 닫기: \(tab.title)")
        setAccessibilityLabel(tab.title)
        setAccessibilitySelected(selected)
        if isSelected != selected {
            isSelected = selected
            needsDisplay = true
        }
    }

    override func mouseDown(with event: NSEvent) { onSelect?() }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        if isSelected {
            NSColor.labelColor.setFill()
            path.fill()
        } else {
            NSColor.separatorColor.setStroke()
            path.stroke()
        }
    }
}

/// 세로 휠 굴림도 옆으로 넘기는 탭 줄 스크롤 뷰(가로 스크롤만 있다).
private final class WebTabStripScrollView: NSScrollView {
    override func scrollWheel(with event: NSEvent) {
        guard event.scrollingDeltaX == 0, event.scrollingDeltaY != 0, let document = documentView else {
            super.scrollWheel(with: event); return
        }
        let step = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 10
        let maxX = max(0, document.frame.width - contentView.bounds.width)
        contentView.scroll(to: NSPoint(x: min(maxX, max(0, contentView.bounds.minX - step)), y: 0))
        reflectScrolledClipView(contentView)
    }
}

/// 왼쪽부터 쌓는 탭 줄 내용.
private final class WebTabStripDocumentView: NSView {
    override var isFlipped: Bool { true }
}
