import Foundation
import CoreGraphics

/// 취소 가능한 백그라운드 작업 표지. 계산 루프가 `isCancelled`를 주기적으로 확인한다.
final class ColorJob: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
}

/// 5bit/채널 양자화 히스토그램. 이미지당 한 번만 만들고 슬라이더는 `group`만 다시 돈다.
struct ColorHistogram {
    struct Bin {
        let count: Int
        let topColor: RGB8      // 이 칸에서 가장 많이 나온 실제 색
        let topCount: Int
        let lab: LabColor       // topColor의 Lab
    }
    let bins: [Bin]
    let totalPixels: Int
}

enum ColorExtractionService {
    // 측정 결정 (pro docs/devlog/2026-11-02-color-picker.md 참고).
    static let downscaleLongSide = 512
    static let minRatio = 0.0005
    static let formula: DeltaEFormula = .ciede2000

    // MARK: - 1. 축소

    /// 긴 변을 `longSide`로 줄인(작으면 그대로) sRGB 8bit premultipliedLast 버퍼.
    static func downscaledRGBA(from image: CGImage, longSide: Int) -> (pixels: [UInt8], width: Int, height: Int)? {
        let long = max(image.width, image.height)
        guard long > 0, longSide > 0 else { return nil }
        let scale = min(1.0, Double(longSide) / Double(long))
        let w = max(1, Int((Double(image.width) * scale).rounded()))
        let h = max(1, Int((Double(image.height) * scale).rounded()))
        var buffer = [UInt8](repeating: 0, count: w * h * 4)
        let drawn = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        return drawn ? (buffer, w, h) : nil
    }

    // MARK: - 2~3. 양자화·Lab

    /// RGBA(premultiplied) 버퍼로 히스토그램을 만든다. 알파 128 미만은 제외. 취소되면 nil.
    static func buildHistogram(rgba: [UInt8], isCancelled: () -> Bool) -> ColorHistogram? {
        var colorCounts: [UInt32: Int] = [:]
        var total = 0
        let pixelCount = rgba.count / 4
        for i in 0..<pixelCount {
            if i & 0x3FFF == 0, isCancelled() { return nil }
            let a = Int(rgba[i * 4 + 3])
            if a < 128 { continue }
            var r = Int(rgba[i * 4]), g = Int(rgba[i * 4 + 1]), b = Int(rgba[i * 4 + 2])
            if a < 255 { r = min(255, r * 255 / a); g = min(255, g * 255 / a); b = min(255, b * 255 / a) }
            colorCounts[RGB8(UInt8(r), UInt8(g), UInt8(b)).packed, default: 0] += 1
            total += 1
        }
        if isCancelled() { return nil }

        struct Acc { var count = 0; var top: UInt32 = 0; var topCount = 0 }
        var accs: [UInt32: Acc] = [:]
        for (color, n) in colorCounts {
            let key = ((color >> 19) & 0x1F) << 10 | ((color >> 11) & 0x1F) << 5 | ((color >> 3) & 0x1F)
            var acc = accs[key, default: Acc()]
            acc.count += n
            if n > acc.topCount || (n == acc.topCount && color < acc.top) { acc.top = color; acc.topCount = n }
            accs[key] = acc
        }
        let sorted = accs.sorted { $0.value.count != $1.value.count ? $0.value.count > $1.value.count : $0.key < $1.key }
        let bins = sorted.map { _, acc -> ColorHistogram.Bin in
            let color = RGB8(packed: acc.top)
            return ColorHistogram.Bin(count: acc.count, topColor: color, topCount: acc.topCount, lab: ColorFormat.lab(color))
        }
        return ColorHistogram(bins: bins, totalPixels: total)
    }

    static func buildHistogram(from image: CGImage, longSide: Int = downscaleLongSide,
                               isCancelled: () -> Bool) -> ColorHistogram? {
        guard let small = downscaledRGBA(from: image, longSide: longSide), !isCancelled() else { return nil }
        return buildHistogram(rgba: small.pixels, isCancelled: isCancelled)
    }

    // MARK: - 4~6. 묶기·칩 색·정렬

    static func group(_ h: ColorHistogram, tolerance: Double, minRatio: Double = minRatio,
                      formula: DeltaEFormula = formula) -> [ColorSwatch] {
        guard h.totalPixels > 0 else { return [] }
        struct Group {
            let anchor: LabColor      // 묶음을 연 첫 칸의 대표색 — ΔE 비교 기준
            var count: Int
            var top: RGB8             // 묶음 안에서 가장 많이 나온 실제 색
            var topCount: Int
            var topLab: LabColor
        }
        let seedMin = max(1, Int((Double(h.totalPixels) * minRatio).rounded(.up)))
        var groups: [Group] = []
        for bin in h.bins {
            var best = -1
            var bestDistance = Double.infinity
            for (i, g) in groups.enumerated() {
                let d = ColorFormat.deltaE(g.anchor, bin.lab, formula: formula)
                if d <= tolerance && d < bestDistance { best = i; bestDistance = d }
            }
            if best >= 0 {
                groups[best].count += bin.count
                if bin.topCount > groups[best].topCount {
                    groups[best].top = bin.topColor; groups[best].topCount = bin.topCount; groups[best].topLab = bin.lab
                }
            } else if bin.count >= seedMin {
                groups.append(Group(anchor: bin.lab, count: bin.count, top: bin.topColor, topCount: bin.topCount, topLab: bin.lab))
            }
        }
        let total = Double(h.totalPixels)
        return groups
            .filter { Double($0.count) / total >= minRatio }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.top.packed < $1.top.packed }
            .map { ColorSwatch(color: $0.top, ratio: Double($0.count) / total, lab: $0.topLab) }
    }
}
