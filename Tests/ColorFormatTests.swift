import Foundation

private func near(_ a: Double, _ b: Double, _ tol: Double) -> Bool { abs(a - b) <= tol }

func runColorFormatTests() {
    runTest("HEX는 대문자 #RRGGBB, 한 자리 값도 0으로 채운다") {
        checkEqual(ColorFormat.hex(RGB8(0, 0, 0)), "#000000", "검정")
        checkEqual(ColorFormat.hex(RGB8(255, 255, 255)), "#FFFFFF", "흰색")
        checkEqual(ColorFormat.hex(RGB8(255, 0, 0)), "#FF0000", "순색 빨강")
        checkEqual(ColorFormat.hex(RGB8(1, 10, 171)), "#010AAB", "0 채움·대문자")
    }

    runTest("RGB 표기는 쉼표+공백") {
        checkEqual(ColorFormat.rgbString(RGB8(231, 111, 81)), "231, 111, 81", "예시 색")
        checkEqual(ColorFormat.rgbString(RGB8(0, 0, 0)), "0, 0, 0", "검정")
    }

    runTest("CMYK 단순 변환: 경계값과 설계 문서 예시(#E76F51)") {
        let black = ColorFormat.cmyk(RGB8(0, 0, 0))
        checkEqual([black.c, black.m, black.y, black.k], [0, 0, 0, 100], "검정은 K만 100")
        let white = ColorFormat.cmyk(RGB8(255, 255, 255))
        checkEqual([white.c, white.m, white.y, white.k], [0, 0, 0, 0], "흰색은 전부 0")
        let red = ColorFormat.cmyk(RGB8(255, 0, 0))
        checkEqual([red.c, red.m, red.y, red.k], [0, 100, 100, 0], "순색 빨강")
        checkEqual(ColorFormat.cmykString(RGB8(231, 111, 81)), "0, 52, 65, 9", "설계 문서의 CMYK 0,52,… 와 일치")
    }

    runTest("sRGB→Lab: D65 기준 알려진 값") {
        let white = ColorFormat.lab(RGB8(255, 255, 255))
        check(near(white.l, 100, 0.05) && near(white.a, 0, 0.05) && near(white.b, 0, 0.05), "흰색 \(white)")
        let black = ColorFormat.lab(RGB8(0, 0, 0))
        check(near(black.l, 0, 0.01) && near(black.a, 0, 0.01) && near(black.b, 0, 0.01), "검정 \(black)")
        let red = ColorFormat.lab(RGB8(255, 0, 0))
        check(near(red.l, 53.24, 0.1) && near(red.a, 80.09, 0.1) && near(red.b, 67.20, 0.1), "빨강 \(red)")
        let green = ColorFormat.lab(RGB8(0, 255, 0))
        check(near(green.l, 87.73, 0.1) && near(green.a, -86.18, 0.1) && near(green.b, 83.18, 0.1), "초록 \(green)")
        let blue = ColorFormat.lab(RGB8(0, 0, 255))
        check(near(blue.l, 32.30, 0.1) && near(blue.a, 79.19, 0.1) && near(blue.b, -107.86, 0.1), "파랑 \(blue)")
    }

    runTest("ΔE76은 Lab 유클리드 거리") {
        let p = LabColor(l: 50, a: 0, b: 0), q = LabColor(l: 53, a: 4, b: 0)
        check(near(ColorFormat.deltaE(p, q, formula: .cie76), 5, 1e-9), "3-4-5 삼각형")
        checkEqual(ColorFormat.deltaE(p, p, formula: .cie76), 0, "같은 색은 0")
    }

    runTest("CIEDE2000: Sharma 검증표 1·2·7번 쌍") {
        let cases: [(LabColor, LabColor, Double)] = [
            (LabColor(l: 50, a: 2.6772, b: -79.7751), LabColor(l: 50, a: 0, b: -82.7485), 2.0425),
            (LabColor(l: 50, a: 3.1571, b: -77.2803), LabColor(l: 50, a: 0, b: -82.7485), 2.8615),
            (LabColor(l: 50, a: 2.5, b: 0), LabColor(l: 50, a: 0, b: -2.5), 4.3065),
        ]
        for (i, c) in cases.enumerated() {
            let d = ColorFormat.deltaE(c.0, c.1, formula: .ciede2000)
            check(near(d, c.2, 0.001), "쌍 \(i): \(d) != \(c.2)")
            // 대칭성
            check(near(d, ColorFormat.deltaE(c.1, c.0, formula: .ciede2000), 0.001), "쌍 \(i) 대칭")
        }
    }

    runTest("HEX 전체 복사 문자열은 비율 순서를 그대로 공백으로 잇는다") {
        let l = LabColor(l: 0, a: 0, b: 0)
        let list = [ColorSwatch(color: RGB8(0x3F, 0x7C, 0xAC), ratio: 0.5, lab: l),
                    ColorSwatch(color: RGB8(0xE9, 0xC4, 0x6A), ratio: 0.3, lab: l)]
        checkEqual(ColorFormat.hexList(list), "#3F7CAC #E9C46A", "공백 구분")
        checkEqual(ColorFormat.hexList([]), "", "빈 목록")
    }
}
