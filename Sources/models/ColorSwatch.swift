import Foundation

/// sRGB 8bit 색.
struct RGB8: Hashable {
    var r: UInt8
    var g: UInt8
    var b: UInt8

    init(_ r: UInt8, _ g: UInt8, _ b: UInt8) { self.r = r; self.g = g; self.b = b }

    /// 0xRRGGBB — 히스토그램 키와 결정적 동률 처리용.
    var packed: UInt32 { UInt32(r) << 16 | UInt32(g) << 8 | UInt32(b) }
    init(packed: UInt32) { self.init(UInt8((packed >> 16) & 0xFF), UInt8((packed >> 8) & 0xFF), UInt8(packed & 0xFF)) }
}

/// CIE Lab(D65).
struct LabColor: Hashable {
    var l: Double
    var a: Double
    var b: Double
}

/// 추출 결과 칩 하나. AI 컬러 시스템의 입력으로 그대로 쓸 수 있게 {색, 차지 비율, Lab}만 둔다.
struct ColorSwatch: Hashable {
    let color: RGB8
    /// 계산에 쓴 불투명 픽셀 전체 대비 비율(0...1). 최소 비율 필터로 빠진 묶음이 있으면 합이 1보다 작다.
    let ratio: Double
    /// 칩 색(`color`)의 Lab.
    let lab: LabColor
}
