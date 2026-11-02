import AppKit

/// 기준 이미지: w×h, 각 픽셀 색이 위치로 유일하게 정해진다(비트맵 행 기준, 위에서 0).
private func marker(_ x: Int, _ y: Int) -> RGB8 { RGB8(UInt8(20 + x * 50), UInt8(20 + y * 80), 200) }

private func makeBitmap(width: Int, height: Int, _ color: (Int, Int) -> RGB8) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    let data = rep.bitmapData!
    for y in 0..<height {
        for x in 0..<width {
            let c = color(x, y), i = y * rep.bytesPerRow + x * 4
            data[i] = c.r; data[i + 1] = c.g; data[i + 2] = c.b; data[i + 3] = 255
        }
    }
    return rep
}

/// 앱과 같은 변환(displayTransform)으로 실제로 그린 결과.
private func render(_ src: NSBitmapImageRep, flipH: Bool, flipV: Bool, rotation: Int) -> NSBitmapImageRep {
    let size = NSSize(width: src.pixelsWide, height: src.pixelsHigh)
    let (dstSize, transform) = PixelMapping.displayTransform(sourceSize: size, flipH: flipH, flipV: flipV, rotation: rotation)
    let dst = makeBitmap(width: Int(dstSize.width), height: Int(dstSize.height)) { _, _ in RGB8(0, 0, 0) }
    let ctx = NSGraphicsContext(bitmapImageRep: dst)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    ctx.imageInterpolation = .none
    ctx.shouldAntialias = false
    transform.concat()
    src.draw(in: NSRect(origin: .zero, size: size))
    NSGraphicsContext.restoreGraphicsState()
    return dst
}

func runPixelMappingTests() {
    runTest("항등: 반전·회전 없으면 문서 좌표가 곧 픽셀 (y는 위에서 시작)") {
        // 3×2 이미지. 문서 (0.5, 1.5)는 좌상단 픽셀, (2.5, 0.5)는 우하단 픽셀.
        func at(_ x: Double, _ y: Double) -> PixelMapping.PixelCoord? {
            PixelMapping.originalPixel(documentPoint: CGPoint(x: x, y: y), sourceSize: CGSize(width: 3, height: 2),
                                       pixelWidth: 3, pixelHeight: 2, flipH: false, flipV: false, rotation: 0)
        }
        checkEqual(at(0.5, 1.5), .init(x: 0, y: 0), "좌상단")
        checkEqual(at(2.5, 0.5), .init(x: 2, y: 1), "우하단")
        checkEqual(at(1.2, 0.7), .init(x: 1, y: 1), "중간")
    }

    runTest("손계산: 좌우 반전·상하 반전") {
        func at(_ x: Double, _ y: Double, h: Bool, v: Bool) -> PixelMapping.PixelCoord? {
            PixelMapping.originalPixel(documentPoint: CGPoint(x: x, y: y), sourceSize: CGSize(width: 3, height: 2),
                                       pixelWidth: 3, pixelHeight: 2, flipH: h, flipV: v, rotation: 0)
        }
        checkEqual(at(0.5, 1.5, h: true, v: false), .init(x: 2, y: 0), "좌우 반전: 화면 좌상단은 원본 우상단")
        checkEqual(at(0.5, 1.5, h: false, v: true), .init(x: 0, y: 1), "상하 반전: 화면 좌상단은 원본 좌하단")
        checkEqual(at(0.5, 1.5, h: true, v: true), .init(x: 2, y: 1), "둘 다")
    }

    runTest("손계산: 회전 90 — 원본 좌상단 픽셀은 화면 좌하단에 보인다") {
        // 3×2 원본을 90° 돌리면 문서는 2×3. 앱의 rotateRight()는 rotationAngle += 90 (AppKit 양의 방향).
        func at(_ x: Double, _ y: Double, r: Int) -> PixelMapping.PixelCoord? {
            PixelMapping.originalPixel(documentPoint: CGPoint(x: x, y: y), sourceSize: CGSize(width: 3, height: 2),
                                       pixelWidth: 3, pixelHeight: 2, flipH: false, flipV: false, rotation: r)
        }
        checkEqual(at(0.5, 0.5, r: 90), .init(x: 0, y: 0), "90: 문서 좌하단 = 원본 좌상단")
        checkEqual(at(0.5, 0.5, r: 180), .init(x: 2, y: 0), "180: 문서 좌하단 = 원본 우상단")
        checkEqual(at(0.5, 0.5, r: 270), .init(x: 2, y: 1), "270: 문서 좌하단 = 원본 우하단")
        check(at(2.5, 0.5, r: 90) == nil, "90 회전 후 문서 폭은 2 — x=2.5는 밖")
    }

    runTest("경계: 이미지 밖은 nil, 모서리 안쪽은 마지막 픽셀") {
        func at(_ x: Double, _ y: Double) -> PixelMapping.PixelCoord? {
            PixelMapping.originalPixel(documentPoint: CGPoint(x: x, y: y), sourceSize: CGSize(width: 4, height: 3),
                                       pixelWidth: 4, pixelHeight: 3, flipH: false, flipV: false, rotation: 0)
        }
        check(at(-0.01, 1) == nil && at(4, 1) == nil && at(1, -0.01) == nil && at(1, 3) == nil, "네 변 바깥")
        checkEqual(at(3.999, 0.001), .init(x: 3, y: 2), "우하단 모서리 안쪽")
        checkEqual(at(0, 3 - 0.001), .init(x: 0, y: 0), "좌상단 모서리 안쪽")
    }

    runTest("포인트 크기와 픽셀 수가 다르면(DPI·벡터) 비율을 곱한다") {
        // 2×1pt 이미지가 4×2px 비트맵.
        let r = PixelMapping.originalPixel(documentPoint: CGPoint(x: 1.6, y: 0.3), sourceSize: CGSize(width: 2, height: 1),
                                           pixelWidth: 4, pixelHeight: 2, flipH: false, flipV: false, rotation: 0)
        checkEqual(r, .init(x: 3, y: 1), "x=floor(1.6*2), 행=floor((1-0.3)*2)")
    }

    runTest("PixelMapping: 16가지 반전·회전 조합이 실제 렌더링과 일치") {
        let w = 4, h = 3
        let src = makeBitmap(width: w, height: h, marker)
        var checked = 0
        for flipH in [false, true] {
            for flipV in [false, true] {
                for rotation in [0, 90, 180, 270] {
                    let dst = render(src, flipH: flipH, flipV: flipV, rotation: rotation)
                    let dw = dst.pixelsWide, dh = dst.pixelsHigh
                    let data = dst.bitmapData!
                    for dy in 0..<dh {
                        for dx in 0..<dw {
                            // 렌더된 화면 픽셀 (dx, dy[위에서])의 중심 = 문서 좌표 (dx+0.5, dh-(dy+0.5))
                            let doc = CGPoint(x: Double(dx) + 0.5, y: Double(dh - dy) - 0.5)
                            guard let p = PixelMapping.originalPixel(
                                documentPoint: doc, sourceSize: CGSize(width: w, height: h), pixelWidth: w, pixelHeight: h,
                                flipH: flipH, flipV: flipV, rotation: rotation) else {
                                check(false, "H\(flipH) V\(flipV) R\(rotation) (\(dx),\(dy)) 밖으로 나옴"); continue
                            }
                            let expected = marker(p.x, p.y)
                            let i = dy * dst.bytesPerRow + dx * 4
                            let got = RGB8(data[i], data[i + 1], data[i + 2])
                            if abs(Int(got.r) - Int(expected.r)) > 1 || abs(Int(got.g) - Int(expected.g)) > 1 {
                                check(false, "H\(flipH) V\(flipV) R\(rotation) (\(dx),\(dy)): 그려진 색 \(got) != 원본(\(p.x),\(p.y)) \(expected)")
                            }
                            checked += 1
                        }
                    }
                }
            }
        }
        checkEqual(checked, 16 * w * h, "모든 조합·모든 픽셀을 검사")
    }

    runTest("배율·패닝: 클립뷰 좌표 → 문서 좌표") {
        let p = PixelMapping.documentPoint(clipViewPoint: CGPoint(x: 30, y: 40), boundsOrigin: CGPoint(x: 10, y: 20), magnification: 2)
        checkEqual(p, CGPoint(x: 25, y: 40), "원점 + 점/배율")
        let centered = PixelMapping.documentPoint(clipViewPoint: CGPoint(x: 100, y: 50), boundsOrigin: CGPoint(x: -20, y: -10), magnification: 0.5)
        checkEqual(centered, CGPoint(x: 180, y: 90), "이미지가 작아 CenteringClipView가 음수 원점을 쓸 때")
    }

    runTest("PixelSampler: 한 픽셀과 격자 읽기, 밖은 nil") {
        let img = makeTestImage(width: 5, height: 4) { x, y in RGB8(UInt8(x * 40), UInt8(y * 60), 77) }
        checkEqual(PixelSampler.color(in: img, x: 3, y: 2), RGB8(120, 120, 77), "(3,2)")
        check(PixelSampler.color(in: img, x: 5, y: 0) == nil && PixelSampler.color(in: img, x: 0, y: -1) == nil, "범위 밖")
        let g = PixelSampler.grid(in: img, centerX: 0, centerY: 0, radius: 1)
        checkEqual(g.count, 9, "3×3")
        checkEqual(g[4], RGB8(0, 0, 77), "가운데 = (0,0)")
        checkEqual(g[5], RGB8(40, 0, 77), "오른쪽 = (1,0)")
        checkEqual(g[7], RGB8(0, 60, 77), "아래 = (0,1)")
        check(g[0] == nil && g[1] == nil && g[3] == nil, "왼쪽·위쪽은 이미지 밖이라 nil")
    }

    runTest("PixelSampler: 큰 이미지 모서리 격자와 sRGB 값 보존") {
        let img = makeTestImage(width: 3000, height: 2000) { x, y in RGB8(UInt8(x % 256), UInt8(y % 256), 9) }
        let g = PixelSampler.grid(in: img, centerX: 2999, centerY: 1999, radius: 2)
        checkEqual(g.count, 25, "5×5")
        checkEqual(g[12], RGB8(UInt8(2999 % 256), UInt8(1999 % 256), 9), "가운데 값 그대로")
        check(g[14] == nil && g[24] == nil, "오른쪽·아래 모서리 밖은 nil")
    }

    runTest("회전 각도 정규화와 유효하지 않은 이미지 좌표 처리") {
        for (angle, normalized) in [(-90, 270), (450, 90)] {
            let size = NSSize(width: 4, height: 3)
            let actual = PixelMapping.displayTransform(sourceSize: size, flipH: true, flipV: false, rotation: angle)
            let expected = PixelMapping.displayTransform(sourceSize: size, flipH: true, flipV: false, rotation: normalized)
            checkEqual(actual.size, expected.size, "정규화 후 문서 크기")
            checkEqual(actual.transform.transform(NSPoint(x: 1, y: 2)),
                       expected.transform.transform(NSPoint(x: 1, y: 2)), "그리기 변환도 같은 각도를 사용")
            checkEqual(PixelMapping.originalPixel(documentPoint: CGPoint(x: 0.5, y: 0.5), sourceSize: size,
                                                  pixelWidth: 4, pixelHeight: 3, flipH: true, flipV: false, rotation: angle),
                       PixelMapping.originalPixel(documentPoint: CGPoint(x: 0.5, y: 0.5), sourceSize: size,
                                                  pixelWidth: 4, pixelHeight: 3, flipH: true, flipV: false, rotation: normalized),
                       "읽기 변환도 같은 각도를 사용")
        }
        for size in [CGSize.zero, CGSize(width: CGFloat.infinity, height: 3)] {
            check(PixelMapping.originalPixel(documentPoint: .zero, sourceSize: size, pixelWidth: 4, pixelHeight: 3,
                                              flipH: false, flipV: false, rotation: 0) == nil, "유효하지 않은 크기는 읽지 않음")
        }
        check(PixelMapping.originalPixel(documentPoint: CGPoint(x: CGFloat.nan, y: 1), sourceSize: CGSize(width: 4, height: 3),
                                          pixelWidth: 4, pixelHeight: 3, flipH: false, flipV: false, rotation: 0) == nil,
              "유효하지 않은 좌표는 정수 변환 전에 제외")
    }

    runTest("PixelSampler: 투명은 빈 칸, 반투명은 배경과 합성하지 않은 색") {
        let bytes: [UInt8] = [0, 0, 0, 0, 128, 64, 0, 128]
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        let image = CGImage(width: 2, height: 1, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 8,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        check(PixelSampler.color(in: image, x: 0, y: 0) == nil, "투명을 검정으로 복사하지 않음")
        checkEqual(PixelSampler.color(in: image, x: 1, y: 0), RGB8(255, 127, 0), "미리 곱해진 알파 복원")
        let grid = PixelSampler.grid(in: image, centerX: 1, centerY: 0, radius: 1)
        checkEqual(grid.compactMap { $0 }, [RGB8(255, 127, 0)], "이미지 밖과 투명 칸은 모두 nil")
        check(PixelSampler.grid(in: image, centerX: 100, centerY: 100, radius: 1).allSatisfy { $0 == nil },
              "격자 전체가 밖이면 빈 칸")
        check(PixelSampler.grid(in: image, centerX: 0, centerY: 0, radius: -1).isEmpty, "음수 반경은 빈 격자")
    }

    runTest("PixelSampler: 선형 RGB 50%를 sRGB 약 188로 변환한다") {
        let provider = CGDataProvider(data: Data([UInt8(128), 128, 128, 255]) as CFData)!
        let image = CGImage(width: 1, height: 1, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 4,
                            space: CGColorSpace(name: CGColorSpace.linearSRGB)!,
                            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        guard let color = PixelSampler.color(in: image, x: 0, y: 0) else {
            check(false, "색 공간 변환 결과가 있어야 함"); return
        }
        check([color.r, color.g, color.b].allSatisfy { abs(Int($0) - 188) <= 1 }, "원본 바이트 128을 그대로 반환하지 않음")
    }

    runTest("PixelSampler: 작은 포인트 크기의 NSImage도 원본 픽셀 해상도를 유지한다") {
        let original = makeTestImage(width: 4, height: 2) { x, y in RGB8(UInt8(x * 50), UInt8(y * 100), 77) }
        let image = NSImage(cgImage: original, size: NSSize(width: 2, height: 1))
        guard let rasterized = PixelSampler.rasterize(image) else {
            check(false, "원본 래스터화 성공"); return
        }
        checkEqual(rasterized.width, 4, "포인트 폭 2로 축소하지 않음")
        checkEqual(rasterized.height, 2, "원본 높이 유지")
        checkEqual(PixelSampler.color(in: rasterized, x: 3, y: 1), RGB8(150, 100, 77), "원본 우하단 픽셀")
    }

}
