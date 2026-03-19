import AppKit

/// 이미지 위에 드래그로 자르기 영역을 지정하는 오버레이
final class CropOverlayView: NSView {
    var onCropConfirmed: ((CGRect) -> Void)?
    var onCropCancelled: (() -> Void)?

    /// 원본 이미지 크기 (좌표 변환용)
    var imageSize: CGSize = .zero
    /// 현재 이미지가 표시되는 영역 (scrollView 내 imageView 프레임 × magnification)
    var imageRect: CGRect = .zero

    private var selectionRect: CGRect = .zero
    private var dragStart: CGPoint = .zero
    private var isDragging = false
    private var activeHandle: Handle = .none

    private let selectionLayer = CAShapeLayer()
    private let dimmingLayer = CAShapeLayer()
    private let infoLabel = NSTextField(labelWithString: "")

    private enum Handle {
        case none, body
        case topLeft, topRight, bottomLeft, bottomRight
        case top, bottom, left, right
    }

    private let handleSize: CGFloat = 8

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true

        // 딤 레이어
        dimmingLayer.fillColor = NSColor.black.withAlphaComponent(0.4).cgColor
        dimmingLayer.fillRule = .evenOdd
        layer?.addSublayer(dimmingLayer)

        // 선택 영역 테두리
        selectionLayer.fillColor = nil
        selectionLayer.strokeColor = NSColor.white.cgColor
        selectionLayer.lineWidth = 1.5
        selectionLayer.lineDashPattern = [6, 3]
        layer?.addSublayer(selectionLayer)

        // 크기 정보 라벨
        infoLabel.translatesAutoresizingMaskIntoConstraints = false
        infoLabel.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        infoLabel.textColor = .white
        infoLabel.backgroundColor = NSColor.black.withAlphaComponent(0.6)
        infoLabel.isBezeled = false
        infoLabel.drawsBackground = true
        infoLabel.isHidden = true
        addSubview(infoLabel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Reset

    func resetSelection() {
        // 기본 선택: 이미지 영역 전체
        selectionRect = imageRect
        updateLayers()
        infoLabel.isHidden = false
    }

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        activeHandle = hitHandle(at: point)

        if activeHandle == .none {
            // 새 선택 시작
            isDragging = true
            dragStart = clampToImageRect(point)
            selectionRect = CGRect(origin: dragStart, size: .zero)
        } else if activeHandle == .body {
            dragStart = point
        } else {
            dragStart = point
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        if isDragging {
            let current = clampToImageRect(point)
            selectionRect = CGRect(
                x: min(dragStart.x, current.x),
                y: min(dragStart.y, current.y),
                width: abs(current.x - dragStart.x),
                height: abs(current.y - dragStart.y)
            )
        } else if activeHandle == .body {
            let dx = point.x - dragStart.x
            let dy = point.y - dragStart.y
            var newRect = selectionRect.offsetBy(dx: dx, dy: dy)
            // 이미지 영역 내 클램핑
            newRect.origin.x = max(imageRect.minX, min(newRect.origin.x, imageRect.maxX - newRect.width))
            newRect.origin.y = max(imageRect.minY, min(newRect.origin.y, imageRect.maxY - newRect.height))
            selectionRect = newRect
            dragStart = point
        } else {
            resizeSelection(handle: activeHandle, to: point)
        }

        updateLayers()
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
        activeHandle = .none

        // 너무 작은 선택은 무시
        if selectionRect.width < 4 || selectionRect.height < 4 {
            resetSelection()
        }
    }

    // MARK: - Keyboard

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36: // Return — 자르기 확인
            confirmCrop()
        case 53: // ESC — 취소
            onCropCancelled?()
        default:
            super.keyDown(with: event)
        }
    }

    // MARK: - Confirm

    private func confirmCrop() {
        guard selectionRect.width >= 4, selectionRect.height >= 4 else { return }

        // 화면 좌표 → 이미지 좌표 변환
        let scaleX = imageSize.width / imageRect.width
        let scaleY = imageSize.height / imageRect.height

        let imageOriginX = (selectionRect.origin.x - imageRect.origin.x) * scaleX
        let imageOriginY = (selectionRect.origin.y - imageRect.origin.y) * scaleY
        let imageWidth = selectionRect.width * scaleX
        let imageHeight = selectionRect.height * scaleY

        let cropRect = CGRect(x: imageOriginX, y: imageOriginY, width: imageWidth, height: imageHeight)
        onCropConfirmed?(cropRect)
    }

    // MARK: - Handle Detection

    private func hitHandle(at point: CGPoint) -> Handle {
        let r = selectionRect
        let hs = handleSize * 2

        if abs(point.x - r.minX) < hs && abs(point.y - r.minY) < hs { return .bottomLeft }
        if abs(point.x - r.maxX) < hs && abs(point.y - r.minY) < hs { return .bottomRight }
        if abs(point.x - r.minX) < hs && abs(point.y - r.maxY) < hs { return .topLeft }
        if abs(point.x - r.maxX) < hs && abs(point.y - r.maxY) < hs { return .topRight }
        if abs(point.y - r.maxY) < hs && point.x > r.minX && point.x < r.maxX { return .top }
        if abs(point.y - r.minY) < hs && point.x > r.minX && point.x < r.maxX { return .bottom }
        if abs(point.x - r.minX) < hs && point.y > r.minY && point.y < r.maxY { return .left }
        if abs(point.x - r.maxX) < hs && point.y > r.minY && point.y < r.maxY { return .right }
        if r.contains(point) { return .body }
        return .none
    }

    private func resizeSelection(handle: Handle, to point: CGPoint) {
        let p = clampToImageRect(point)
        var r = selectionRect

        switch handle {
        case .topLeft:
            r = CGRect(x: p.x, y: r.minY, width: r.maxX - p.x, height: p.y - r.minY)
        case .topRight:
            r = CGRect(x: r.minX, y: r.minY, width: p.x - r.minX, height: p.y - r.minY)
        case .bottomLeft:
            r = CGRect(x: p.x, y: p.y, width: r.maxX - p.x, height: r.maxY - p.y)
        case .bottomRight:
            r = CGRect(x: r.minX, y: p.y, width: p.x - r.minX, height: r.maxY - p.y)
        case .top:
            r = CGRect(x: r.minX, y: r.minY, width: r.width, height: p.y - r.minY)
        case .bottom:
            r = CGRect(x: r.minX, y: p.y, width: r.width, height: r.maxY - p.y)
        case .left:
            r = CGRect(x: p.x, y: r.minY, width: r.maxX - p.x, height: r.height)
        case .right:
            r = CGRect(x: r.minX, y: r.minY, width: p.x - r.minX, height: r.height)
        default: break
        }

        // 최소 크기 보장
        if r.width >= 4 && r.height >= 4 {
            selectionRect = r
        }
    }

    private func clampToImageRect(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: max(imageRect.minX, min(point.x, imageRect.maxX)),
            y: max(imageRect.minY, min(point.y, imageRect.maxY))
        )
    }

    // MARK: - Rendering

    private func updateLayers() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        // 딤 영역 (선택 영역 바깥)
        let fullPath = CGMutablePath()
        fullPath.addRect(bounds)
        fullPath.addRect(selectionRect)
        dimmingLayer.path = fullPath

        // 선택 테두리
        selectionLayer.path = CGPath(rect: selectionRect, transform: nil)

        // 핸들 그리기
        layer?.sublayers?.filter { $0.name == "handle" }.forEach { $0.removeFromSuperlayer() }
        let corners: [CGPoint] = [
            CGPoint(x: selectionRect.minX, y: selectionRect.minY),
            CGPoint(x: selectionRect.maxX, y: selectionRect.minY),
            CGPoint(x: selectionRect.minX, y: selectionRect.maxY),
            CGPoint(x: selectionRect.maxX, y: selectionRect.maxY),
        ]
        for corner in corners {
            let handle = CALayer()
            handle.name = "handle"
            handle.frame = CGRect(x: corner.x - handleSize / 2, y: corner.y - handleSize / 2,
                                  width: handleSize, height: handleSize)
            handle.backgroundColor = NSColor.white.cgColor
            handle.borderColor = NSColor.controlAccentColor.cgColor
            handle.borderWidth = 1
            layer?.addSublayer(handle)
        }

        // 크기 정보 라벨
        let scaleX = imageSize.width / imageRect.width
        let scaleY = imageSize.height / imageRect.height
        let pixelW = Int(selectionRect.width * scaleX)
        let pixelH = Int(selectionRect.height * scaleY)
        infoLabel.stringValue = " \(pixelW) × \(pixelH) px "
        infoLabel.sizeToFit()
        infoLabel.isHidden = false

        // 라벨 위치: 선택 영역 아래 중앙
        let labelX = selectionRect.midX - infoLabel.frame.width / 2
        let labelY = selectionRect.minY - infoLabel.frame.height - 4
        infoLabel.frame.origin = CGPoint(
            x: max(0, min(labelX, bounds.width - infoLabel.frame.width)),
            y: max(0, labelY)
        )

        CATransaction.commit()
    }

    override func updateLayer() {
        updateLayers()
    }

    // MARK: - Cursor

    override func resetCursorRects() {
        let r = selectionRect
        let hs = handleSize * 2

        addCursorRect(CGRect(x: r.minX - hs, y: r.maxY - hs, width: hs * 2, height: hs * 2), cursor: .crosshair)
        addCursorRect(CGRect(x: r.maxX - hs, y: r.maxY - hs, width: hs * 2, height: hs * 2), cursor: .crosshair)
        addCursorRect(CGRect(x: r.minX - hs, y: r.minY - hs, width: hs * 2, height: hs * 2), cursor: .crosshair)
        addCursorRect(CGRect(x: r.maxX - hs, y: r.minY - hs, width: hs * 2, height: hs * 2), cursor: .crosshair)
        addCursorRect(selectionRect.insetBy(dx: hs, dy: hs), cursor: .openHand)
    }
}
