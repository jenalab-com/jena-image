import AppKit

/// 이미지 편집 서비스 — 자르기, 캔버스 크기, 이미지 크기 조절
final class ImageEditingService {

    /// 이미지 자르기 (rect는 원본 이미지 좌표계 기준, 좌하단 원점)
    func cropImage(_ image: NSImage, to rect: CGRect) -> NSImage? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }

        // NSImage 좌표(좌하단 원점)를 CGImage 좌표(좌상단 원점)로 변환
        let flippedRect = CGRect(
            x: rect.origin.x,
            y: CGFloat(cgImage.height) - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )

        guard let cropped = cgImage.cropping(to: flippedRect) else { return nil }
        return NSImage(cgImage: cropped, size: NSSize(width: cropped.width, height: cropped.height))
    }

    /// 캔버스 크기 변경 (기존 이미지를 지정된 정렬 위치에 배치)
    func resizeCanvas(_ image: NSImage, to newSize: CGSize, fillColor: NSColor, alignment: CanvasAlignment) -> NSImage? {
        let imageSize = image.size
        guard newSize.width >= 1, newSize.height >= 1 else { return nil }

        let origin = alignment.origin(imageSize: imageSize, canvasSize: newSize)

        let result = NSImage(size: newSize)
        result.lockFocus()
        fillColor.setFill()
        NSRect(origin: .zero, size: newSize).fill()
        image.draw(in: NSRect(origin: origin, size: imageSize),
                   from: .zero, operation: .sourceOver, fraction: 1.0)
        result.unlockFocus()
        return result
    }

    /// 이미지 크기 조절 (리샘플링)
    func resizeImage(_ image: NSImage, to newSize: CGSize) -> NSImage? {
        guard newSize.width >= 1, newSize.height >= 1 else { return nil }

        let result = NSImage(size: newSize)
        result.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: newSize),
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .sourceOver, fraction: 1.0)
        result.unlockFocus()
        return result
    }
}

// MARK: - Canvas Alignment

enum CanvasAlignment: Int, CaseIterable {
    case topLeft, topCenter, topRight
    case middleLeft, center, middleRight
    case bottomLeft, bottomCenter, bottomRight

    var displayName: String {
        switch self {
        case .topLeft: return "↖ 좌상단"
        case .topCenter: return "↑ 상단"
        case .topRight: return "↗ 우상단"
        case .middleLeft: return "← 좌측"
        case .center: return "● 중앙"
        case .middleRight: return "→ 우측"
        case .bottomLeft: return "↙ 좌하단"
        case .bottomCenter: return "↓ 하단"
        case .bottomRight: return "↘ 우하단"
        }
    }

    func origin(imageSize: CGSize, canvasSize: CGSize) -> CGPoint {
        let dx = canvasSize.width - imageSize.width
        let dy = canvasSize.height - imageSize.height

        let x: CGFloat
        switch self {
        case .topLeft, .middleLeft, .bottomLeft: x = 0
        case .topCenter, .center, .bottomCenter: x = dx / 2
        case .topRight, .middleRight, .bottomRight: x = dx
        }

        let y: CGFloat
        switch self {
        case .bottomLeft, .bottomCenter, .bottomRight: y = 0
        case .middleLeft, .center, .middleRight: y = dy / 2
        case .topLeft, .topCenter, .topRight: y = dy
        }

        return CGPoint(x: x, y: y)
    }
}
