import AppKit

/// 원본 비트맵에서 색을 읽는다. 화면에 그려진 결과가 아니라 CGImage에서 직접 읽어
/// 확대 보간·화면 색 관리가 값에 섞이지 않게 한다. 읽을 때 sRGB로 변환한다.
enum PixelSampler {
    /// NSImage → CGImage. EXIF 회전본(NSCIImageRep)이나 벡터 이미지는 여기서 한 번 래스터화된다 — 이미지당 한 번만 부를 것.
    static func rasterize(_ image: NSImage) -> CGImage? {
        image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    static func color(in image: CGImage, x: Int, y: Int) -> RGB8? {
        guard x >= 0, y >= 0, x < image.width, y < image.height else { return nil }
        return grid(in: image, centerX: x, centerY: y, radius: 0)[0]
    }

    /// (2r+1)² 격자. 행 우선, 위-왼쪽부터. 이미지 밖이거나 완전 투명인 칸은 nil.
    static func grid(in image: CGImage, centerX: Int, centerY: Int, radius: Int) -> [RGB8?] {
        guard radius >= 0 else { return [] }
        let n = radius * 2 + 1
        var result = [RGB8?](repeating: nil, count: n * n)
        let wanted = CGRect(x: centerX - radius, y: centerY - radius, width: n, height: n)
        let inter = wanted.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard !inter.isNull, inter.width >= 1, inter.height >= 1, let crop = image.cropping(to: inter) else { return result }

        var buffer = [UInt8](repeating: 0, count: n * n * 4)
        buffer.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            ctx.interpolationQuality = .none
            let dx = inter.minX - wanted.minX, dy = inter.minY - wanted.minY     // 격자 안에서의 위-왼쪽 오프셋
            ctx.draw(crop, in: CGRect(x: dx, y: CGFloat(n) - dy - inter.height, width: inter.width, height: inter.height))
        }
        for row in 0..<n {
            for col in 0..<n {
                let i = (row * n + col) * 4
                let a = Int(buffer[i + 3])
                if a == 0 { continue }
                func unpremultiply(_ value: UInt8) -> UInt8 {
                    a == 255 ? value : UInt8(min(255, Int(value) * 255 / a))
                }
                result[row * n + col] = RGB8(unpremultiply(buffer[i]), unpremultiply(buffer[i + 1]), unpremultiply(buffer[i + 2]))
            }
        }
        return result
    }
}
