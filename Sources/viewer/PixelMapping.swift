import AppKit

/// 화면(문서) 좌표를 원본 픽셀 좌표로 바꾸는 순수 로직.
/// 그리는 쪽(ImageDisplayView.applyTransformedImage)과 읽는 쪽이 같은 정의를 쓰도록 변환을 여기서 공유한다.
enum PixelMapping {
    struct PixelCoord: Equatable {
        var x: Int
        var y: Int      // 비트맵 행 — 위에서 0
    }

    /// 원본을 (반전 → 회전) 순서로 그리는 변환. 회전은 AppKit 양의 방향(반시계), 중심 기준.
    static func displayTransform(sourceSize: NSSize, flipH: Bool, flipV: Bool, rotation: Int)
        -> (size: NSSize, transform: NSAffineTransform) {
        let rotation = ((rotation % 360) + 360) % 360
        precondition(rotation % 90 == 0, "이미지 회전은 90도 단위여야 한다")
        let rotated90 = rotation == 90 || rotation == 270
        let dstSize = rotated90 ? NSSize(width: sourceSize.height, height: sourceSize.width) : sourceSize
        let transform = NSAffineTransform()
        transform.translateX(by: dstSize.width / 2, yBy: dstSize.height / 2)
        transform.rotate(byDegrees: CGFloat(rotation))
        transform.scaleX(by: flipH ? -1 : 1, yBy: flipV ? -1 : 1)
        transform.translateX(by: -sourceSize.width / 2, yBy: -sourceSize.height / 2)
        return (dstSize, transform)
    }

    /// 문서 좌표(좌하단 원점, 포인트) → 원본 비트맵 픽셀. 밖이면 nil.
    /// 그리기: p_dst = T(c_dst) · R(θ) · S(flip) · T(-c_src) · p_src → 거꾸로: p_src = S · R(-θ) · (p_dst - c_dst) + c_src
    static func originalPixel(documentPoint p: CGPoint, sourceSize: CGSize, pixelWidth: Int, pixelHeight: Int,
                              flipH: Bool, flipV: Bool, rotation: Int) -> PixelCoord? {
        guard sourceSize.width.isFinite, sourceSize.height.isFinite,
              sourceSize.width > 0, sourceSize.height > 0,
              pixelWidth > 0, pixelHeight > 0 else { return nil }
        let rot = ((rotation % 360) + 360) % 360
        guard rot % 90 == 0 else { return nil }
        let swapped = rot == 90 || rot == 270
        let dw = swapped ? sourceSize.height : sourceSize.width
        let dh = swapped ? sourceSize.width : sourceSize.height
        guard p.x >= 0, p.y >= 0, p.x < dw, p.y < dh else { return nil }

        var x = p.x - dw / 2
        var y = p.y - dh / 2
        switch rot {          // R(-θ)
        case 90: (x, y) = (y, -x)
        case 180: (x, y) = (-x, -y)
        case 270: (x, y) = (-y, x)
        default: break
        }
        if flipH { x = -x }
        if flipV { y = -y }
        let sx = x + sourceSize.width / 2
        let sy = y + sourceSize.height / 2

        let px = Int((sx * Double(pixelWidth) / sourceSize.width).rounded(.down))
        let py = Int(((sourceSize.height - sy) * Double(pixelHeight) / sourceSize.height).rounded(.down))
        // 부동소수 오차로 경계에서 한 칸 벗어나는 것만 막는다 (밖 판정은 위에서 끝났다).
        return PixelCoord(x: min(max(px, 0), pixelWidth - 1), y: min(max(py, 0), pixelHeight - 1))
    }

    /// 클립뷰 좌표(배율 반영된 화면 쪽) → 문서 좌표. NSScrollView는 배율을 clipView.bounds 크기로 표현한다.
    static func documentPoint(clipViewPoint p: CGPoint, boundsOrigin: CGPoint, magnification: CGFloat) -> CGPoint {
        CGPoint(x: boundsOrigin.x + p.x / magnification, y: boundsOrigin.y + p.y / magnification)
    }
}
