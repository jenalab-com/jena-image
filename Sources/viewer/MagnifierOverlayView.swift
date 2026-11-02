import AppKit

/// 커서 옆에 따라다니는 작은 원형 확대경(픽셀 격자)과 HEX 한 줄 라벨. 마우스 이벤트는 통과시킨다.
final class MagnifierOverlayView: NSView {
    static let radius = 5                    // 11×11 격자
    private static let cell: CGFloat = 10
    private static let labelHeight: CGFloat = 20

    private var cursorPoint: CGPoint = .zero
    private var grid: [RGB8?] = []
    private var labelText = ""
    private var copiedTimer: Timer?
    private var showsCopied = false
    private var flipH = false
    private var flipV = false
    private var rotation = 0

    deinit { copiedTimer?.invalidate() }

    override var isFlipped: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    static var loupeSize: CGSize {
        let side = CGFloat(radius * 2 + 1) * cell
        return CGSize(width: side, height: side + labelHeight + 4)
    }

    /// `point`는 이 뷰 좌표(= scrollView 좌표). 격자의 가운데가 읽는 픽셀이다.
    func show(at point: CGPoint, grid: [RGB8?], flipH: Bool = false, flipV: Bool = false, rotation: Int = 0) {
        guard grid.count == (Self.radius * 2 + 1) * (Self.radius * 2 + 1) else { hideLoupe(); return }
        cursorPoint = point
        self.grid = grid
        self.flipH = flipH
        self.flipV = flipV
        self.rotation = rotation
        if let center = grid[grid.count / 2] { labelText = ColorFormat.hex(center) } else { labelText = "" }
        isHidden = false
        needsDisplay = true
    }

    func hideLoupe() {
        isHidden = true
        copiedTimer?.invalidate()
        copiedTimer = nil
        showsCopied = false
    }

    func flashCopied() {
        guard !isHidden else { return }
        showsCopied = true
        needsDisplay = true
        copiedTimer?.invalidate()
        copiedTimer = Timer.scheduledTimer(withTimeInterval: 0.9, repeats: false) { [weak self] _ in
            self?.showsCopied = false
            self?.needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !isHidden, !grid.isEmpty else { return }
        let size = Self.loupeSize
        let frame = MagnifierPlacement.frame(cursor: cursorPoint, size: size, bounds: bounds)
        let side = size.width
        let loupeRect = CGRect(x: frame.minX, y: frame.maxY - side, width: side, height: side)   // 위쪽에 확대경
        let labelRect = CGRect(x: frame.minX, y: frame.minY, width: side, height: Self.labelHeight)

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(ovalIn: loupeRect).addClip()
        // 가운데 색은 유지하고 주변 픽셀을 이미지와 같은 반전·회전으로 표시한다.
        let transform = NSAffineTransform()
        transform.translateX(by: loupeRect.midX, yBy: loupeRect.midY)
        transform.rotate(byDegrees: CGFloat(rotation))
        transform.scaleX(by: flipH ? -1 : 1, yBy: flipV ? -1 : 1)
        transform.translateX(by: -loupeRect.midX, yBy: -loupeRect.midY)
        transform.concat()
        let n = Self.radius * 2 + 1
        for row in 0..<n {
            for col in 0..<n {
                let rect = CGRect(x: loupeRect.minX + CGFloat(col) * Self.cell,
                                  y: loupeRect.maxY - CGFloat(row + 1) * Self.cell, width: Self.cell, height: Self.cell)
                if let c = grid[row * n + col] {
                    NSColor(srgbRed: CGFloat(c.r) / 255, green: CGFloat(c.g) / 255, blue: CGFloat(c.b) / 255, alpha: 1).setFill()
                } else {
                    NSColor(white: 0.5, alpha: 1).setFill()
                }
                rect.fill()
            }
        }
        NSColor.black.withAlphaComponent(0.18).setStroke()      // 픽셀 격자선
        for i in 1..<n {
            let o = CGFloat(i) * Self.cell
            NSBezierPath.strokeLine(from: CGPoint(x: loupeRect.minX + o, y: loupeRect.minY), to: CGPoint(x: loupeRect.minX + o, y: loupeRect.maxY))
            NSBezierPath.strokeLine(from: CGPoint(x: loupeRect.minX, y: loupeRect.minY + o), to: CGPoint(x: loupeRect.maxX, y: loupeRect.minY + o))
        }
        NSGraphicsContext.restoreGraphicsState()

        // 가운데 읽는 픽셀: 흰 테두리 + 바깥 검은 선
        let mid = CGRect(x: loupeRect.midX - Self.cell / 2, y: loupeRect.midY - Self.cell / 2, width: Self.cell, height: Self.cell)
        NSColor.black.setStroke(); let outer = NSBezierPath(rect: mid.insetBy(dx: -1, dy: -1)); outer.lineWidth = 1; outer.stroke()
        NSColor.white.setStroke(); let inner = NSBezierPath(rect: mid); inner.lineWidth = 1.5; inner.stroke()
        NSColor.white.setStroke(); let ring = NSBezierPath(ovalIn: loupeRect.insetBy(dx: 1, dy: 1)); ring.lineWidth = 2; ring.stroke()

        // HEX 라벨
        let text = showsCopied ? L10n.string(.colorCopied) : labelText
        NSColor.black.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: labelRect, xRadius: 6, yRadius: 6).fill()
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.white]
        let textSize = (text as NSString).size(withAttributes: attrs)
        (text as NSString).draw(at: CGPoint(x: labelRect.midX - textSize.width / 2, y: labelRect.midY - textSize.height / 2), withAttributes: attrs)
    }
}
