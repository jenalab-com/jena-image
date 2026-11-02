import AppKit

/// 불투명한 흰색 사이드바와, 설정 색·불투명도를 따르는 캔버스 바탕.
///
/// 캔버스는 예전엔 데스크톱이 비치는 블러였는데, 배경 색이 이미지 감상에 섞여 든다는 피드백(2026-11-02)으로
/// 기본을 옅은 회색 불투명으로 바꿨다. 설정에서 색과 불투명도를 바꿀 수 있고, 불투명도를 낮추면 블러가 다시 비친다.
final class LibrarySurfaceView: NSView {
    enum Kind { case sidebar, canvas }
    let effect = NSVisualEffectView()
    private let tint = NSView()
    private let kind: Kind
    private var observer: NSObjectProtocol?

    init(kind: Kind) {
        self.kind = kind
        super.init(frame: .zero)
        wantsLayer = true
        effect.material = kind == .sidebar ? .sidebar : .underWindowBackground
        effect.blendingMode = .behindWindow
        effect.state = .active
        addSubview(effect)
        if kind == .sidebar {
            effect.isHidden = true
            appearance = NSAppearance(named: .aqua)
            layer?.backgroundColor = NSColor.white.cgColor
        } else {
            tint.wantsLayer = true
            addSubview(tint)
            applyCanvasAppearance()
            observer = NotificationCenter.default.addObserver(
                forName: .settingsChanged, object: nil, queue: .main
            ) { [weak self] _ in self?.applyCanvasAppearance() }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

    override func layout() {
        super.layout()
        effect.frame = bounds
        tint.frame = bounds
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        if kind == .canvas { applyCanvasAppearance() }
    }

    private func applyCanvasAppearance() {
        let settings = AppSettings.shared
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let color = settings.canvasBackgroundColor ?? AppSettings.defaultCanvasColor(dark: dark)
        let opacity = settings.canvasBackgroundOpacity
        // 완전 불투명이면 블러를 아예 꺼서 데스크톱 비침과 그 비용을 없앤다.
        effect.isHidden = opacity >= 0.999
        tint.layer?.backgroundColor = color.withAlphaComponent(opacity).cgColor
    }
}

final class LibraryCardView: NSView {
    var isHighlighted = false { didSet { needsDisplay = true } }
    var isDropTarget = false { didSet { needsDisplay = true } }
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let base = NSColor(white: dark ? 0.21 : 0.99, alpha: 1)
        let selected = isHighlighted || isDropTarget
        layer?.backgroundColor = (selected ? base.blended(withFraction: 0.12, of: .controlAccentColor) ?? base : base).cgColor
        layer?.cornerRadius = 14
        layer?.masksToBounds = true
        layer?.borderWidth = selected ? 1.5 : 0
        layer?.borderColor = selected ? NSColor.controlAccentColor.withAlphaComponent(0.65).cgColor : nil
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

final class LibrarySidebarRowView: NSTableRowView {
    override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }

    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else { return }
        NSColor.labelColor.withAlphaComponent(0.08).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 6, dy: 2), xRadius: 6, yRadius: 6).fill()
    }
}
