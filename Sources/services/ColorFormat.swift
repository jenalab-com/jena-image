import Foundation

enum DeltaEFormula { case cie76, ciede2000 }

/// 색 표기 변환과 지각 거리(ΔE). 값은 모두 sRGB 8bit 기준이다.
enum ColorFormat {
    static func hex(_ c: RGB8) -> String {
        String(format: "#%02X%02X%02X", UInt32(c.r), UInt32(c.g), UInt32(c.b))
    }

    static func rgbString(_ c: RGB8) -> String { "\(c.r), \(c.g), \(c.b)" }

    /// ICC 프로파일 없는 단순 변환. 포토샵의 CMYK 값과 다를 수 있는 참고용 근사값이다.
    static func cmyk(_ c: RGB8) -> (c: Int, m: Int, y: Int, k: Int) {
        let r = Double(c.r) / 255, g = Double(c.g) / 255, b = Double(c.b) / 255
        let mx = max(r, g, b)
        guard mx > 0 else { return (0, 0, 0, 100) }
        func pct(_ v: Double) -> Int { Int((v * 100).rounded()) }
        return (pct((mx - r) / mx), pct((mx - g) / mx), pct((mx - b) / mx), pct(1 - mx))
    }

    static func cmykString(_ c: RGB8) -> String {
        let v = cmyk(c)
        return "\(v.c), \(v.m), \(v.y), \(v.k)"
    }

    /// "HEX 전체 복사": 비율 순서 그대로 공백으로 잇는다.
    static func hexList(_ swatches: [ColorSwatch]) -> String {
        swatches.map { hex($0.color) }.joined(separator: " ")
    }

    // MARK: - Lab

    static func lab(_ c: RGB8) -> LabColor {
        func linear(_ v: UInt8) -> Double {
            let s = Double(v) / 255
            return s <= 0.04045 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
        }
        let r = linear(c.r), g = linear(c.g), b = linear(c.b)
        // sRGB → XYZ(D65), 기준 흰색으로 정규화
        let x = (0.4124564 * r + 0.3575761 * g + 0.1804375 * b) / 0.95047
        let y = 0.2126729 * r + 0.7151522 * g + 0.0721750 * b
        let z = (0.0193339 * r + 0.1191920 * g + 0.9503041 * b) / 1.08883
        func f(_ t: Double) -> Double { t > 216.0 / 24389 ? cbrt(t) : (24389.0 / 27 * t + 16) / 116 }
        let fx = f(x), fy = f(y), fz = f(z)
        return LabColor(l: 116 * fy - 16, a: 500 * (fx - fy), b: 200 * (fy - fz))
    }

    // MARK: - ΔE

    static func deltaE(_ p: LabColor, _ q: LabColor, formula: DeltaEFormula) -> Double {
        switch formula {
        case .cie76:
            let dl = p.l - q.l, da = p.a - q.a, db = p.b - q.b
            return (dl * dl + da * da + db * db).squareRoot()
        case .ciede2000:
            return deltaE2000(p, q)
        }
    }

    /// CIEDE2000 (kL = kC = kH = 1). Sharma, Wu, Dalal 2005 구현 노트를 따른다.
    private static func deltaE2000(_ p: LabColor, _ q: LabColor) -> Double {
        let rad = Double.pi / 180
        let c1 = hypot(p.a, p.b), c2 = hypot(q.a, q.b)
        let cBar7 = pow((c1 + c2) / 2, 7)
        let g = 0.5 * (1 - (cBar7 / (cBar7 + pow(25.0, 7))).squareRoot())
        let a1 = (1 + g) * p.a, a2 = (1 + g) * q.a
        let c1p = hypot(a1, p.b), c2p = hypot(a2, q.b)
        func hue(_ b: Double, _ a: Double) -> Double {
            if a == 0 && b == 0 { return 0 }
            let h = atan2(b, a) / rad
            return h < 0 ? h + 360 : h
        }
        let h1p = hue(p.b, a1), h2p = hue(q.b, a2)

        let dLp = q.l - p.l
        let dCp = c2p - c1p
        var dhp = 0.0
        if c1p * c2p != 0 {
            dhp = h2p - h1p
            if dhp > 180 { dhp -= 360 } else if dhp < -180 { dhp += 360 }
        }
        let dHp = 2 * (c1p * c2p).squareRoot() * sin(dhp / 2 * rad)

        let lBar = (p.l + q.l) / 2
        let cBarP = (c1p + c2p) / 2
        var hBarP = h1p + h2p
        if c1p * c2p != 0 {
            if abs(h1p - h2p) <= 180 { hBarP = (h1p + h2p) / 2 }
            else if h1p + h2p < 360 { hBarP = (h1p + h2p + 360) / 2 }
            else { hBarP = (h1p + h2p - 360) / 2 }
        }
        let t = 1 - 0.17 * cos((hBarP - 30) * rad) + 0.24 * cos(2 * hBarP * rad)
            + 0.32 * cos((3 * hBarP + 6) * rad) - 0.20 * cos((4 * hBarP - 63) * rad)
        let dTheta = 30 * exp(-pow((hBarP - 275) / 25, 2))
        let rC = 2 * (pow(cBarP, 7) / (pow(cBarP, 7) + pow(25.0, 7))).squareRoot()
        let sL = 1 + 0.015 * pow(lBar - 50, 2) / (20 + pow(lBar - 50, 2)).squareRoot()
        let sC = 1 + 0.045 * cBarP
        let sH = 1 + 0.015 * cBarP * t
        let rT = -sin(2 * dTheta * rad) * rC

        let tl = dLp / sL, tc = dCp / sC, th = dHp / sH
        return (tl * tl + tc * tc + th * th + rT * tc * th).squareRoot()
    }
}
