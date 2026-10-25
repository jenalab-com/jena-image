import AppKit

/// 불투명한 흰색 사이드바와 네이티브 블러 캔버스.
final class LibrarySurfaceView: NSView {
    enum Kind { case sidebar, canvas }
    let effect = NSVisualEffectView()

    init(kind: Kind) {
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
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        effect.frame = bounds
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
