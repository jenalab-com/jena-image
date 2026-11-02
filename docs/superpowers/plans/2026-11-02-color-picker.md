# 색상 추출·돋보기 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 상세 화면에서 버튼 한 번으로 이미지의 대표 색을 비율 순 칩으로 보고(HEX·RGB·CMYK 복사), 돋보기(패널 토글 또는 ⌥ 누르는 동안)로 커서 아래 **원본 픽셀의 색**을 클릭 한 번에 HEX로 가져간다. 슬라이더를 움직이면 칩이 실시간으로 늘고 준다.

**Architecture:** 색 계산은 UI와 분리한 순수 로직으로 먼저 만든다 — `ColorFormat`(표기·sRGB↔Lab·ΔE), `ColorExtractionService`(축소 → 5bit 히스토그램 → ΔE 묶기), `PixelMapping`(문서 좌표 → 원본 픽셀, 반전·회전 역변환), `ColorInteraction`(클릭/드래그 임계값, ⌥ 단독 판정, 정보창 유예, 배치 계산). 히스토그램은 이미지당 한 번만 만들고, 슬라이더는 묶기 단계만 다시 돈다. UI는 `MagnifierOverlayView`(확대경, `scrollView` 위 덧씌움) → `ImageDisplayView`(돋보기 모드 마우스 처리) → `ColorPalettePanel`(하단 서랍) → `ViewerViewController`(버튼·⌥·취소) 순으로 얹는다. 계산 취소는 기존 `loadGeneration` 패턴을 그대로 쓴다.

**Tech Stack:** Swift 5 언어 모드(`swiftc` 직결), AppKit, CoreGraphics. 외부 패키지 없음. 테스트는 자체 러너(`Tests/main.swift`, `TestSupport.swift`의 `runTest`/`check`/`checkEqual`).

**Spec:** `docs/superpowers/specs/2026-11-02-color-picker-design.md` (승인됨). 배경 결정: `docs/superpowers/specs/2026-11-02-color-picker-brainstorm.md`. 시안: `docs/superpowers/mockups/2026-11-02-color-palette-placement.html`, `…-color-magnifier-style.html`.

## 구현 확인 (2026-11-02)

- Task 1 완료: `58bacdf`, Task 2 구현·테스트·커밋 완료: `edb5562`.
- Task 2의 최초 실패 테스트 실행 기록은 이번 점검에서 확인하지 못해 해당 체크는 남겨 둠.
- Task 3 측정·상수 반영 완료. 512px / CIEDE2000 / 최소 비율 0.0005, 슬라이더 설정은 Task 7에서 **8...20 / 기본값 12** 적용 완료.
- 측정 근거: `docs/devlog/2026-11-02-color-picker.md`, `test/색상추출_2026-11-02/benchmark.log`.
- Task 1~8 구현·검증 완료. Task 3~8은 이번 Git 인계에서 묶음 커밋하며 공개 저장소에는 Task 1~8 소스·테스트를 함께 반영한다. Task 9는 후속 구현·빌드·UI 스모크 검증 완료. Task 10 뷰어 버튼·패널 연결 및 검증 완료. Task 11~13은 미구현. 다음 구현은 **Task 11 추출 파이프라인 연결**.
- 아래 Task 7의 `2...40` 예시 등 초기 가정값보다 위 측정 결정을 우선한다.

## Global Constraints

- 최소 macOS 14.0 (`Info.plist` `LSMinimumSystemVersion`). `NSPopover`·`NSSlider`·`CGImage.cropping` 등 모두 사용 가능.
- 외부 패키지 없음. 빌드는 `make build`(`swiftc -O`로 `Sources/` 전체를 한 번에). 새 파일은 `Sources/` 아래에 두면 자동 포함. 순수 로직 파일은 `Makefile`의 `TEST_SOURCES`에 직접 추가해야 `make test`에 들어간다.
- 검증 명령 세 가지: `make build`(경고·에러 0), `make test`(순수 로직), `make test-ui`(`Tests/UI/*.swift`, 전체 소스 + 실제 `ViewerViewController`). `test-ui`는 `Tests/TestSupport.swift`만 공유하므로 공용 헬퍼는 거기에 둔다.
- 색 값은 **sRGB 8bit 기준**. CMYK는 ICC 없는 단순 변환(참고용 근사, 0–100 정수). ICC 변환·`.ase` 내보내기·결과 저장·비교 화면·AI 컬러 시스템은 **범위 밖** — 만들지 않는다.
- 비교 화면(`ComparePaneView`)도 `ImageDisplayView`를 쓴다. 돋보기 모드는 기본 꺼짐이어야 하고, 꺼져 있으면 기존 마우스 동작(더블클릭 닫기·패닝)이 **비트 단위로 같아야** 한다.
- 문자열은 `L10n`(`Localization.swift`)로. 키를 추가하면 한국어를 기준으로 두고 영어·일본어·중국어도 채운다(없으면 한국어로 폴백되긴 한다).
- 복사는 `NSPasteboard.general`에 문자열 하나. 슬라이더 값만 `AppSettings`에 저장(이미지별 결과 저장 없음).
- 코드 주석·devlog는 한국어, 식별자는 영어. 작업 끝에 `docs/devlog/2026-11-02-color-picker.md`(또는 실제 작업일)를 만든다.
- **커밋 메시지에 `Co-Authored-By` 줄을 넣지 않는다**(이 프로젝트 규칙. 과거 커밋 중 하나에 붙어 있어도 따라 하지 않는다). 형식은 `feat:`/`test:`/`docs:` 영어 한 줄.
- 숫자 중 **측정으로 정하는 값**: 축소 긴 변(초기 256px), 최소 비율(초기 0.1%), ΔE 식(CIE76 vs CIEDE2000), 슬라이더 기본값·범위. Task 3에서 재고 devlog에 기록한 뒤 상수를 확정한다. 그 전까지는 초기값으로 진행.

## Review Focus

1. **좌표 변환(반전·회전·배율 아래서 엉뚱한 픽셀을 읽음)** — 가장 위험. 그리는 쪽(`applyTransformedImage`)과 읽는 쪽이 같은 변환을 공유하고, 읽는 쪽은 "실제로 그려 본 결과"를 정답으로 비교한다. → Task 4 `PixelMapping: 16가지 반전·회전 조합이 실제 렌더링과 일치` (오라클 테스트), `손계산 회전 90`, UI `배율·반전 상태에서 창 좌표가 같은 원본 픽셀을 가리킨다`(Task 8). 수동: 줌 200%+좌우 반전+회전 후 알려진 색 이미지로 확인.
2. **연속 클릭 중 더블클릭으로 뷰어가 닫힘** — 돋보기 모드에서만 더블클릭 닫기를 막아야 하고, 꺼져 있을 땐 그대로 닫혀야 한다. → UI `돋보기 모드에선 더블클릭이 뷰어를 닫지 않고, 꺼지면 닫는다`(Task 8). 수동: 돋보기 켜고 같은 자리를 5번 빠르게 클릭.
3. **⌥와 ⌘ 조합** — ⌘⌥(또는 ⇧⌥·⌃⌥)에선 켜지면 안 되고, ⌘를 먼저 누르고 ⌥를 얹은 뒤 ⌘만 떼면(⌥ 단독이 됨) 그때 켜지는 건 허용. 창이 비활성화돼 `flagsChanged` 해제를 못 받아 ⌥가 "눌린 채" 남는 문제도 같이. → Task 5 `OptionKeyGate` 테스트 3개, UI `⌥ 단독만 임시 돋보기를 켜고 창 비활성화 시 해제`(Task 12). 수동: ⌘⌥ 누르기, ⌥ 누른 채 ⌘Tab.
4. **이미지 전환 후 늦게 도착한 추출 결과** — 이전 이미지의 칩이 새 이미지 위에 나타나면 안 된다. → Task 2 `취소 신호가 오면 히스토그램을 만들지 않는다`, UI `이미지를 넘기면 이전 이미지의 늦은 추출 결과를 버린다`(Task 11). 수동: 큰 이미지에서 패널을 연 직후 → 키로 다음 이미지.
5. **칩에서 정보창으로 마우스를 옮기면 정보창이 사라짐** — 칩과 정보창 사이 틈에서 `mouseExited`가 먼저 오기 때문. 유예 시간 안에 정보창에 들어오면 취소된다. → Task 6 `HoverGrace` 테스트 3개. 수동: 칩 → 정보창 복사 버튼으로 천천히/빠르게 이동, 옆 칩으로 바로 이동.
6. **돋보기 종료 후 확대경이 남음 / 패널·버튼 위에서 보임** — `ImageDisplayView`의 추적 영역은 위에 겹친 버튼 아래에서도 이벤트를 받는다. → `refreshMagnifier`가 `hitTest`로 이 뷰 소속인지 확인(Task 8), 수동 항목에 포함.
7. **큰 이미지에서 추출이 1초를 넘거나 슬라이더가 끊김** — → Task 3 측정(축소 크기·ΔE 식 결정), 슬라이더 재묶기는 백그라운드 + 최신 요청만 반영(Task 11).
8. **비교 화면 오염** — `ImageDisplayView`를 공유하므로 돋보기가 새어 나가면 안 된다. → UI `비교 칸의 ImageDisplayView는 돋보기·오버레이가 없다`(Task 8).

---

### Task 1: 모델 + ColorFormat (HEX·RGB·CMYK, sRGB↔Lab, ΔE) — TDD

**Files:**
- Create: `Sources/models/ColorSwatch.swift`
- Create: `Sources/services/ColorFormat.swift`
- Create: `Tests/ColorFormatTests.swift`
- Modify: `Tests/main.swift`, `Makefile` (`TEST_SOURCES`)

**Interfaces:**
- Produces:
  ```swift
  struct RGB8: Hashable { var r, g, b: UInt8; init(_ r: UInt8, _ g: UInt8, _ b: UInt8); var packed: UInt32; init(packed: UInt32) }
  struct LabColor: Hashable { var l, a, b: Double }
  struct ColorSwatch: Hashable { let color: RGB8; let ratio: Double; let lab: LabColor }   // AI 컬러 시스템 입력으로 그대로 쓴다
  enum DeltaEFormula { case cie76, ciede2000 }
  enum ColorFormat {
      static func hex(_ c: RGB8) -> String                       // "#E76F51"
      static func rgbString(_ c: RGB8) -> String                 // "231, 111, 81"
      static func cmyk(_ c: RGB8) -> (c: Int, m: Int, y: Int, k: Int)
      static func cmykString(_ c: RGB8) -> String                // "0, 52, 65, 9"
      static func hexList(_ swatches: [ColorSwatch]) -> String   // "#3F7CAC #E9C46A …"
      static func lab(_ c: RGB8) -> LabColor                     // D65
      static func deltaE(_ p: LabColor, _ q: LabColor, formula: DeltaEFormula) -> Double
  }
  ```

- [x] **Step 1: Makefile `TEST_SOURCES`에 추가**

`TEST_SOURCES` 목록의 `Sources/services/ThumbnailDiskStore.swift \` 아래에 두 줄을 넣는다(이후 Task에서 파일이 생길 때마다 같은 자리에 한 줄씩 추가).

```makefile
               Sources/models/ColorSwatch.swift \
               Sources/services/ColorFormat.swift \
```

- [x] **Step 2: 실패하는 테스트 작성**

`Tests/ColorFormatTests.swift` — 알려진 기준값을 쓴다. CIEDE2000 값은 Sharma/Wu/Dalal(2005) 검증표 1·2·7번 쌍이다. **불일치하면 구현을 의심하기 전에 논문 표를 다시 확인한다.**

```swift
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
```

`Tests/main.swift`의 `runDiskStoreTests()` 위에 `runColorFormatTests()` 한 줄을 추가한다.

- [x] **Step 3: 컴파일 실패 확인**

Run: `make test`
Expected: `cannot find 'RGB8' in scope` 류 컴파일 에러.

- [x] **Step 4: 모델 구현**

```swift
// Sources/models/ColorSwatch.swift
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
```

- [x] **Step 5: ColorFormat 구현**

```swift
// Sources/services/ColorFormat.swift
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
```

- [x] **Step 6: 테스트 통과 확인**

Run: `make test`
Expected: `✅ HEX는 …` 등 7개 테스트 통과, 마지막 줄 `all tests passed`.

- [x] **Step 7: 커밋**

```bash
git add Sources/models/ColorSwatch.swift Sources/services/ColorFormat.swift Tests/ColorFormatTests.swift Tests/main.swift Makefile
git commit -m "feat: color models and ColorFormat (hex/rgb/cmyk, Lab, deltaE)"
```

---

### Task 2: ColorExtractionService (축소·히스토그램·묶기) — TDD

**Files:**
- Create: `Sources/services/ColorExtractionService.swift`
- Create: `Tests/ColorExtractionTests.swift`
- Modify: `Tests/TestSupport.swift` (CGImage 만드는 헬퍼), `Tests/main.swift`, `Makefile`

**Interfaces:**
- Consumes: `RGB8`, `LabColor`, `ColorSwatch`, `ColorFormat` (Task 1).
- Produces:
  ```swift
  struct ColorHistogram {
      struct Bin { let count: Int; let topColor: RGB8; let topCount: Int; let lab: LabColor }
      let bins: [Bin]          // count 내림차순, 동률은 키 오름차순(결정적)
      let totalPixels: Int     // 계산에 쓴 불투명 픽셀 수
  }
  final class ColorJob: @unchecked Sendable { func cancel(); var isCancelled: Bool }
  enum ColorExtractionService {
      static let downscaleLongSide = 256       // 초기값 — Task 3에서 측정 후 확정
      static let minRatio = 0.001              // 초기값 — Task 3에서 측정 후 확정
      static let formula: DeltaEFormula = .cie76   // 초기값 — Task 3에서 결정
      static func downscaledRGBA(from image: CGImage, longSide: Int) -> (pixels: [UInt8], width: Int, height: Int)?
      static func buildHistogram(rgba: [UInt8], isCancelled: () -> Bool) -> ColorHistogram?
      static func buildHistogram(from image: CGImage, longSide: Int, isCancelled: () -> Bool) -> ColorHistogram?
      static func group(_ h: ColorHistogram, tolerance: Double, minRatio: Double, formula: DeltaEFormula) -> [ColorSwatch]
  }
  ```
- 규칙(설계 §4): 5bit/채널 양자화, 칸마다 **가장 많이 나온 실제 색** 기록, 개수 많은 칸부터 묶기, 묶음 대표색(= 그 묶음을 연 첫 칸의 대표색)과의 ΔE가 허용 범위 이하이면 합침(여러 묶음이 해당하면 가장 가까운 쪽), 칩 색은 묶음 안에서 가장 많이 나온 실제 색. 알파 128 미만 픽셀은 제외하고 비율 분모에서도 뺀다(설계가 침묵하는 부분 — 투명 PNG가 검정으로 도배되는 것을 막는다). **최소 비율보다 작은 칸은 새 묶음을 열지 못한다**(이미 있는 묶음에 합쳐지는 것만 가능) — 노이즈 큰 사진에서 묶음 수가 수천으로 불어 슬라이더가 끊기는 것을 막는 상한(묶음 ≤ 1/minRatio).

- [x] **Step 1: 테스트 헬퍼 추가**

`Tests/TestSupport.swift` 끝에 추가(`test-ui`도 이 파일을 공유한다).

```swift
import CoreGraphics

/// (x, y)는 위에서 아래로 0. 색은 sRGB 불투명 비트맵.
func makeTestImage(width: Int, height: Int, _ color: (Int, Int) -> RGB8) -> CGImage {
    var bytes = [UInt8](repeating: 255, count: width * height * 4)
    for y in 0..<height {
        for x in 0..<width {
            let c = color(x, y), i = (y * width + x) * 4
            bytes[i] = c.r; bytes[i + 1] = c.g; bytes[i + 2] = c.b
        }
    }
    let provider = CGDataProvider(data: Data(bytes) as CFData)!
    return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                   space: CGColorSpace(name: CGColorSpace.sRGB)!,
                   bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                   provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
}
```

- [x] **Step 2: 실패하는 테스트 작성**

```swift
// Tests/ColorExtractionTests.swift
import Foundation
import CoreGraphics

/// 색·개수 목록을 RGBA(불투명) 배열로 펼친다.
private func pixels(_ runs: [(RGB8, Int)], alpha: UInt8 = 255) -> [UInt8] {
    var out: [UInt8] = []
    for (c, n) in runs { for _ in 0..<n { out += [c.r, c.g, c.b, alpha] } }
    return out
}

func runColorExtractionTests() {
    runTest("칸마다 가장 많이 나온 실제 색을 기록한다") {
        // 5bit 양자화에서 (200,100,50)과 (201,101,51)은 같은 칸이다.
        let h = ColorExtractionService.buildHistogram(
            rgba: pixels([(RGB8(200, 100, 50), 5), (RGB8(201, 101, 51), 2)]), isCancelled: { false })!
        checkEqual(h.bins.count, 1, "한 칸")
        checkEqual(h.bins[0].count, 7, "칸 개수")
        checkEqual(h.bins[0].topColor, RGB8(200, 100, 50), "대표는 더 많이 나온 실제 색")
        checkEqual(h.bins[0].topCount, 5, "대표 색 개수")
        checkEqual(h.totalPixels, 7, "총 픽셀")
    }

    runTest("투명 픽셀은 히스토그램과 비율 분모에서 제외한다") {
        let data = pixels([(RGB8(255, 0, 0), 4)]) + pixels([(RGB8(0, 0, 0), 100)], alpha: 0)
        let h = ColorExtractionService.buildHistogram(rgba: data, isCancelled: { false })!
        checkEqual(h.totalPixels, 4, "불투명 픽셀만")
        let swatches = ColorExtractionService.group(h, tolerance: 10, minRatio: 0, formula: .cie76)
        checkEqual(swatches.map { $0.color }, [RGB8(255, 0, 0)], "검정이 끼지 않음")
        check(abs(swatches[0].ratio - 1.0) < 1e-9, "비율 100%")
    }

    runTest("축소는 긴 변을 맞추고 종횡비를 유지한다") {
        let big = makeTestImage(width: 1000, height: 500) { _, _ in RGB8(10, 20, 30) }
        let r = ColorExtractionService.downscaledRGBA(from: big, longSide: 256)!
        checkEqual(r.width, 256, "가로(긴 변)")
        checkEqual(r.height, 128, "세로")
        checkEqual(r.pixels.count, 256 * 128 * 4, "버퍼 크기")
        let small = makeTestImage(width: 40, height: 20) { _, _ in RGB8(1, 2, 3) }
        let s = ColorExtractionService.downscaledRGBA(from: small, longSide: 256)!
        checkEqual(s.width, 40, "작은 이미지는 키우지 않음")
    }

    // 서로 먼 색 5개: 빨강 3단계 + 파랑 + 초록. 개수는 모두 달라 동률이 없다.
    let palette: [(RGB8, Int)] = [(RGB8(255, 0, 0), 500), (RGB8(225, 0, 0), 400), (RGB8(195, 0, 0), 300),
                                  (RGB8(0, 0, 255), 200), (RGB8(0, 255, 0), 100)]
    let histogram = ColorExtractionService.buildHistogram(rgba: pixels(palette), isCancelled: { false })!

    runTest("허용 범위를 키우면 칩이 줄어든다") {
        let counts = [0.0, 5, 10, 20, 50, 100, 300].map {
            ColorExtractionService.group(histogram, tolerance: $0, minRatio: 0, formula: .cie76).count
        }
        checkEqual(counts.first!, 5, "허용 0이면 5칸 그대로")
        checkEqual(counts.last!, 1, "아주 크면 하나로")
        check(zip(counts, counts.dropFirst()).allSatisfy { $0 >= $1 }, "단조 감소: \(counts)")
        check(counts.contains(3), "빨강 3단계가 합쳐지는 구간 존재: \(counts)")
    }

    runTest("칩 색은 평균이 아니라 이미지에 실제 있는 색이다") {
        let actual = Set(palette.map { $0.0 })
        for tol in [0.0, 10, 30, 100, 300] {
            let swatches = ColorExtractionService.group(histogram, tolerance: tol, minRatio: 0, formula: .cie76)
            check(swatches.allSatisfy { actual.contains($0.color) }, "허용 \(tol): 모든 칩이 실제 색")
        }
        let merged = ColorExtractionService.group(histogram, tolerance: 100, minRatio: 0, formula: .cie76)
        checkEqual(merged[0].color, RGB8(255, 0, 0), "합쳐진 빨강 묶음의 칩은 가장 많이 나온 255,0,0")
    }

    runTest("비율은 큰 순서로 정렬되고, 최소 비율 0이면 합이 100%다") {
        for tol in [0.0, 30, 300] {
            let s = ColorExtractionService.group(histogram, tolerance: tol, minRatio: 0, formula: .cie76)
            check(abs(s.map { $0.ratio }.reduce(0, +) - 1.0) < 1e-9, "허용 \(tol): 합 100%")
            check(zip(s, s.dropFirst()).allSatisfy { $0.ratio >= $1.ratio }, "허용 \(tol): 내림차순")
        }
        let filtered = ColorExtractionService.group(histogram, tolerance: 0, minRatio: 0.2, formula: .cie76)
        check(filtered.map { $0.ratio }.reduce(0, +) <= 1.0 + 1e-9, "필터 후 합은 100% 이하")
    }

    runTest("최소 비율보다 작은 묶음은 칩에서 빠진다") {
        let h = ColorExtractionService.buildHistogram(
            rgba: pixels([(RGB8(30, 60, 200), 999), (RGB8(250, 250, 0), 1)]), isCancelled: { false })!
        checkEqual(ColorExtractionService.group(h, tolerance: 5, minRatio: 0.002, formula: .cie76).count, 1, "0.1% 짜리 제외")
        checkEqual(ColorExtractionService.group(h, tolerance: 5, minRatio: 0, formula: .cie76).count, 2, "필터 끄면 둘 다")
        // 작은 칸이 큰 묶음의 허용 범위 안이면 필터와 무관하게 큰 묶음에 합쳐진다.
        let near = ColorExtractionService.buildHistogram(
            rgba: pixels([(RGB8(30, 60, 200), 999), (RGB8(46, 60, 200), 1)]), isCancelled: { false })!
        let merged = ColorExtractionService.group(near, tolerance: 20, minRatio: 0.002, formula: .cie76)
        checkEqual(merged.count, 1, "가까운 작은 칸은 합류")
        check(abs(merged[0].ratio - 1.0) < 1e-9, "합류한 비율까지 반영")
    }

    runTest("히스토그램을 다시 만들지 않고 허용 범위만 바꿔도 처음부터 계산한 것과 같다") {
        let first = ColorExtractionService.group(histogram, tolerance: 10, minRatio: 0, formula: .cie76)
        _ = ColorExtractionService.group(histogram, tolerance: 100, minRatio: 0, formula: .cie76)
        _ = ColorExtractionService.group(histogram, tolerance: 0, minRatio: 0, formula: .cie76)
        let again = ColorExtractionService.group(histogram, tolerance: 10, minRatio: 0, formula: .cie76)
        checkEqual(first, again, "슬라이더를 오간 뒤에도 같은 결과(히스토그램 불변)")
        let fresh = ColorExtractionService.buildHistogram(rgba: pixels(palette), isCancelled: { false })!
        checkEqual(first, ColorExtractionService.group(fresh, tolerance: 10, minRatio: 0, formula: .cie76), "새로 만든 것과 동일")
    }

    runTest("취소 신호가 오면 히스토그램을 만들지 않는다") {
        let data = pixels([(RGB8(1, 2, 3), 40_000)])
        check(ColorExtractionService.buildHistogram(rgba: data, isCancelled: { true }) == nil, "취소되면 nil")
        let job = ColorJob()
        check(!job.isCancelled, "새 작업은 취소 아님")
        job.cancel()
        check(job.isCancelled, "cancel 후")
    }
}
```

`Tests/main.swift`에 `runColorExtractionTests()` 추가, `Makefile` `TEST_SOURCES`에 `Sources/services/ColorExtractionService.swift \` 추가.

- [ ] **Step 3: 컴파일 실패 확인**

Run: `make test`
Expected: `cannot find 'ColorExtractionService' in scope`.

- [x] **Step 4: 구현**

```swift
// Sources/services/ColorExtractionService.swift
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
    // 아래 세 값은 Task 3에서 측정한 뒤 확정한다.
    static let downscaleLongSide = 256
    static let minRatio = 0.001
    static let formula: DeltaEFormula = .cie76

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
```

`minRatio: 0`일 때 `seedMin`은 `max(1, 0)` = 1이라 모든 칸이 묶음을 열 수 있다. 필터의 `>= minRatio`도 항상 참이다.

- [x] **Step 5: 테스트 통과 확인**

Run: `make test`
Expected: Task 1의 7개 + 이 Task의 9개 = 16개 통과. `허용 범위를 키우면` 테스트의 `counts.contains(3)`이 실패하면 팔레트의 ΔE를 확인한다(빨강 255↔225 ΔE76 ≈ 14, 255↔195 ≈ 30, 빨강↔파랑/초록 > 170). 허용값 목록에 20·50이 들어 있어 3이 나와야 한다.

- [x] **Step 6: 커밋**

```bash
git add Sources/services/ColorExtractionService.swift Tests/ColorExtractionTests.swift Tests/TestSupport.swift Tests/main.swift Makefile
git commit -m "feat: ColorExtractionService with histogram reuse and greedy deltaE grouping"
```

---

### Task 3: 측정 — 축소 크기·최소 비율·ΔE 식·슬라이더 범위를 정하고 기록

설계가 "측정 후 정한다"고 둔 값들이다. 코드는 던져 버릴 벤치 하나뿐이고, 결과를 상수에 반영한다.

**Files:**
- Create (throwaway, 커밋 안 함): `/tmp/color-bench/main.swift`
- Modify: `Sources/services/ColorExtractionService.swift` (상수 3개 확정)
- Create: `docs/devlog/2026-11-02-color-picker.md` (측정 결과 섹션)

**Interfaces:**
- Produces: 결정 5개 — `downscaleLongSide`, `minRatio`, `formula`, 슬라이더 범위(`colorToleranceRange`), 슬라이더 기본값(`defaultColorTolerance`). Task 7이 뒤 둘을 `AppSettings`에 넣는다.

- [x] **Step 1: 표본 이미지 준비**

성격이 다른 5장 이상을 고른다 — 큰 사진(24MP 이상 1장, 가능하면 8K급), 일반 사진, 일러스트(평면 색 많음), 흑백/저채도, 투명 PNG. 경로를 셸 변수로 둔다.

```bash
export SAMPLES="$HOME/Pictures/sample-big.jpg $HOME/Pictures/sample-photo.jpg $HOME/Pictures/sample-illust.png $HOME/Pictures/sample-mono.jpg $HOME/Pictures/sample-alpha.png"
```

- [x] **Step 2: 벤치 작성**

```swift
// /tmp/color-bench/main.swift
import Foundation
import ImageIO

func ms(_ block: () -> Void) -> Double {
    let t = DispatchTime.now().uptimeNanoseconds; block()
    return Double(DispatchTime.now().uptimeNanoseconds - t) / 1_000_000
}

for path in CommandLine.arguments.dropFirst() {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else { print("skip \(path)"); continue }
    print("== \((path as NSString).lastPathComponent)  \(image.width)x\(image.height)")

    // (a) 축소 크기별 전처리 시간 + 상위 6칩(기준: 512)
    var reference: [String] = []
    for side in [512, 384, 256, 192, 128] {
        var h: ColorHistogram?
        let t = ms { h = ColorExtractionService.buildHistogram(from: image, longSide: side, isCancelled: { false }) }
        guard let hist = h else { continue }
        let top = ColorExtractionService.group(hist, tolerance: 12, minRatio: 0.001, formula: .cie76)
            .prefix(6).map { ColorFormat.hex($0.color) }
        if side == 512 { reference = top }
        let same = Set(top).intersection(reference).count
        print(String(format: "  side %3d: 전처리 %7.1f ms  bins %5d  상위6 기준(512)과 일치 %d/6  %@",
                     side, t, hist.bins.count, same, top.joined(separator: " ")))
    }

    // (b) ΔE 식 × 허용 범위 × 최소 비율 — 묶기 시간(슬라이더 한 틱)과 칩 수
    guard let hist = ColorExtractionService.buildHistogram(from: image, longSide: ColorExtractionService.downscaleLongSide, isCancelled: { false }) else { continue }
    for formula in [DeltaEFormula.cie76, .ciede2000] {
        for tol in [4.0, 8, 12, 20, 30] {
            for minRatio in [0.0005, 0.001, 0.002] {
                var count = 0
                var times: [Double] = []
                for _ in 0..<5 { times.append(ms { count = ColorExtractionService.group(hist, tolerance: tol, minRatio: minRatio, formula: formula).count }) }
                times.sort()
                print(String(format: "  %@ tol %4.0f min %.4f: 칩 %3d  묶기 중앙값 %6.2f ms", formula == .cie76 ? "CIE76   " : "CIEDE2000", tol, minRatio, count, times[2]))
            }
        }
    }
}
```

- [x] **Step 3: 빌드·실행**

```bash
mkdir -p /tmp/color-bench
swiftc -O -framework AppKit -framework ImageIO \
  Sources/models/ColorSwatch.swift Sources/services/ColorFormat.swift Sources/services/ColorExtractionService.swift \
  /tmp/color-bench/main.swift -o /tmp/color-bench/bench
/tmp/color-bench/bench $SAMPLES | tee /tmp/color-bench/result.txt
```
Expected: 이미지마다 축소 크기별 줄 5개와 ΔE 식별 줄 30개.

- [x] **Step 4: 결정 규칙에 따라 값 고르기**

| 값 | 규칙 |
|---|---|
| `downscaleLongSide` | 가장 큰 이미지에서 **전처리 ≤ 1000ms**이면서 상위 6칩이 512 기준과 5/6 이상 일치하는 가장 작은 값. 둘 다 만족하는 값이 256이면 256 유지. |
| `formula` | 슬라이더 한 틱(묶기)의 **중앙값이 CIEDE2000에서 16ms 이하**(60fps 한 프레임)이면 `.ciede2000`, 아니면 `.cie76`. CIEDE2000이 16ms를 넘지만 CIE76은 충분하면 `.cie76`. |
| `minRatio` | 일러스트·사진 모두에서 눈으로 볼 때 "먼지 칩"(0.1% 안팎의 작은 점)이 사라지고, 의미 있는 포인트 색이 살아남는 값. 0.0005 / 0.001 / 0.002 중 선택. |
| 슬라이더 범위·기본값 | 선택한 식으로 사진·일러스트 모두 칩 수가 대략 **4~30개** 사이에서 움직이는 구간을 범위로(예: `2...40`), 사진 기준 칩이 **10~16개** 나오는 값을 기본값으로. 식이 CIEDE2000이면 같은 ΔE에서 칩이 더 많이 남으므로 범위 상한을 낮춰 잡을 수 있다. |

- [x] **Step 5: 상수 확정**

`Sources/services/ColorExtractionService.swift`의 세 상수를 선택값으로 바꾸고 "Task 3에서 측정한 뒤 확정한다" 주석을 `// 측정 결정 (devlog 2026-11-02-color-picker 참고)`로 바꾼다. 아래 값은 **기본 가정**이며 측정으로 바뀌면 바뀐 값을 쓴다.

```swift
    // 측정 결정 (docs/devlog/2026-11-02-color-picker.md 참고)
    static let downscaleLongSide = 256
    static let minRatio = 0.001
    static let formula: DeltaEFormula = .cie76
```

- [x] **Step 6: devlog에 결과 기록**

```markdown
# 2026-11-02 — 색상 추출·돋보기

## 측정 결과 (Task 3)

- 표본: <파일명 5장, 해상도>
- 전처리 시간(가장 큰 이미지): 512px <ms> / 384px <ms> / 256px <ms> / 128px <ms>. 상위 6칩 기준(512) 일치: <n>/6 …
- 묶기 한 틱(중앙값): CIE76 <ms> / CIEDE2000 <ms> (tol 12, min 0.001, 사진 기준)
- 결정:
  - `downscaleLongSide` = <값> (이유: …)
  - `formula` = <cie76|ciede2000> (이유: 묶기 중앙값이 16ms 기준 <이하|초과>)
  - `minRatio` = <값> (이유: …)
  - 슬라이더 범위 = <lo>...<hi>, 기본값 = <값> (칩 수 <a>~<b>개 구간)
```

- [x] **Step 7: 테스트로 회귀 확인 후 커밋**

Run: `make test`
Expected: 16개 통과(상수가 바뀌어도 테스트는 모두 명시적으로 파라미터를 넘기므로 영향 없음).

```bash
git add Sources/services/ColorExtractionService.swift docs/devlog/2026-11-02-color-picker.md
git commit -m "chore: finalize color extraction parameters from measurements"
```

---

### Task 4: PixelMapping + PixelSampler (좌표 변환·원본 픽셀 읽기) — TDD

설계 §5: 가장 위험한 부분. 그리는 변환과 읽는 변환을 **같은 정의에서** 끌어오고, 읽는 쪽은 "실제로 그려 본 결과"와 비교한다.

**Files:**
- Create: `Sources/viewer/PixelMapping.swift`
- Create: `Sources/services/PixelSampler.swift`
- Modify: `Sources/viewer/ImageDisplayView.swift:335-350` (`applyTransformedImage`가 공유 변환을 쓰도록 — 동작 동일)
- Create: `Tests/PixelMappingTests.swift`
- Modify: `Tests/main.swift`, `Makefile`

**Interfaces:**
- Consumes: `RGB8` (Task 1).
- Produces:
  ```swift
  enum PixelMapping {
      struct PixelCoord: Equatable { var x: Int; var y: Int }   // y는 위에서 0(비트맵 행)
      /// ImageDisplayView.applyTransformedImage와 공유하는 그리기 변환. rotation: 0/90/180/270
      static func displayTransform(sourceSize: NSSize, flipH: Bool, flipV: Bool, rotation: Int) -> (size: NSSize, transform: NSAffineTransform)
      /// 문서(이미지뷰) 좌표 → 원본 픽셀. 반전·회전을 거꾸로 적용. 밖이면 nil
      static func originalPixel(documentPoint: CGPoint, sourceSize: CGSize, pixelWidth: Int, pixelHeight: Int,
                                flipH: Bool, flipV: Bool, rotation: Int) -> PixelCoord?
      /// 클립뷰 좌표(배율 적용된 화면 쪽) → 문서 좌표
      static func documentPoint(clipViewPoint: CGPoint, boundsOrigin: CGPoint, magnification: CGFloat) -> CGPoint
  }
  enum PixelSampler {
      static func rasterize(_ image: NSImage) -> CGImage?
      static func color(in image: CGImage, x: Int, y: Int) -> RGB8?
      /// (2r+1)² 격자, 행 우선, 위-왼쪽부터. 이미지 밖·완전 투명 칸은 nil
      static func grid(in image: CGImage, centerX: Int, centerY: Int, radius: Int) -> [RGB8?]
  }
  ```
- 좌표 약속: 문서 좌표는 좌하단 원점·포인트 단위(`imageView` 프레임 = `image.size` 또는 회전 후 크기). `image.size`(포인트)와 `CGImage` 픽셀 수가 다를 수 있으므로(DPI 메타데이터, 벡터 래스터화) 포인트→픽셀 비율을 곱한다. 화면 배율은 문서 좌표에서 이미 소거된다(AppKit `convert(_:from:)`가 클립뷰 bounds 배율을 처리 — Task 8).

- [x] **Step 1: Makefile에 두 파일 추가**

`TEST_SOURCES`에 `Sources/viewer/PixelMapping.swift \`, `Sources/services/PixelSampler.swift \` 추가. (이 두 파일은 `ImageDisplayView`/`ViewerViewController`에 의존하지 않아 단독 컴파일된다.)

- [x] **Step 2: 실패하는 테스트 작성**

```swift
// Tests/PixelMappingTests.swift
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
}
```

`Tests/main.swift`에 `runPixelMappingTests()` 추가.

- [x] **Step 3: 컴파일 실패 확인**

Run: `make test`
Expected: `cannot find 'PixelMapping' in scope`.

- [x] **Step 4: PixelMapping 구현**

```swift
// Sources/viewer/PixelMapping.swift
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
        guard sourceSize.width > 0, sourceSize.height > 0, pixelWidth > 0, pixelHeight > 0 else { return nil }
        let rot = ((rotation % 360) + 360) % 360
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
```

- [x] **Step 5: PixelSampler 구현**

```swift
// Sources/services/PixelSampler.swift
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
                func un(_ v: UInt8) -> UInt8 { a == 255 ? v : UInt8(min(255, Int(v) * 255 / a)) }
                result[row * n + col] = RGB8(un(buffer[i]), un(buffer[i + 1]), un(buffer[i + 2]))
            }
        }
        return result
    }
}
```

- [x] **Step 6: 테스트 통과 확인**

Run: `make test`
Expected: Task 1~3의 16개 + 이 Task의 9개 = 25개 통과. `16가지 … 실제 렌더링과 일치`가 실패하면 로그의 `H·V·R` 조합을 본다. 특정 회전만 틀리면 `switch rot`의 부호, 반전이 섞인 조합만 틀리면 반전/회전 적용 순서를 의심한다 — 오라클(렌더)이 정답이므로 **구현을 고치고 테스트를 고치지 않는다.** 렌더 자체가 흐릿하게 나오면(`ctx.shouldAntialias`/`imageInterpolation`) 허용 오차 ±1을 넘는 색 번짐이 생기므로 그 두 줄을 먼저 확인한다.

- [x] **Step 7: `applyTransformedImage`가 공유 변환을 쓰게 바꾼다 (동작 동일)**

`Sources/viewer/ImageDisplayView.swift` `applyTransformedImage()`에서 `let srcSize = original.size` 부터 `transform.concat()`까지(현재 335~350행)를 아래로 교체한다. 나머지(`lockFocus`/`draw`/`unlockFocus`, 프레임 설정)는 그대로 둔다.

```swift
        let srcSize = original.size
        let (dstSize, transform) = PixelMapping.displayTransform(
            sourceSize: srcSize, flipH: isFlippedHorizontally, flipV: isFlippedVertically, rotation: rotationAngle)

        let result = NSImage(size: dstSize)
        result.lockFocus()
        transform.concat()
```

Run: `make build` → 경고·에러 0. `make test-ui` → 기존 UI 테스트 전부 통과(회전·반전 동작은 그대로여야 한다).

- [x] **Step 8: 커밋**

```bash
git add Sources/viewer/PixelMapping.swift Sources/services/PixelSampler.swift Sources/viewer/ImageDisplayView.swift Tests/PixelMappingTests.swift Tests/main.swift Makefile
git commit -m "feat: PixelMapping and PixelSampler with rendering-oracle tests"
```

---

### Task 5: 상호작용 순수 로직 (1) — 클릭/드래그 임계값, ⌥ 단독 판정

**Files:**
- Create: `Sources/viewer/ColorInteraction.swift`
- Create: `Tests/ColorInteractionTests.swift`
- Modify: `Tests/main.swift`, `Makefile`

**Interfaces:**
- Produces:
  ```swift
  struct ClickDragGesture {
      static let threshold: CGFloat = 3          // pt, 창 좌표 기준(화면 배율과 무관)
      init(start: CGPoint)
      mutating func update(to point: CGPoint)
      var hasExceededThreshold: Bool { get }     // 한 번 넘으면 되돌아와도 true
      var isClick: Bool { get }
  }
  enum OptionKeyGate {
      static func isOptionAlone(_ flags: NSEvent.ModifierFlags) -> Bool
  }
  ```
  이 파일은 Task 6에서 `HoverGrace`·`MagnifierPlacement`·`ChipFlowLayout`이 더해진다.

- [x] **Step 1: Makefile에 `Sources/viewer/ColorInteraction.swift \` 추가**

- [x] **Step 2: 실패하는 테스트 작성**

```swift
// Tests/ColorInteractionTests.swift
import AppKit

func runColorInteractionTests() {
    runTest("클릭: 3pt 이내로만 움직이고 떼면 클릭") {
        var g = ClickDragGesture(start: CGPoint(x: 100, y: 100))
        g.update(to: CGPoint(x: 102, y: 102))          // 거리 2.83
        check(g.isClick && !g.hasExceededThreshold, "2.83pt는 클릭")
        g.update(to: CGPoint(x: 103, y: 100))          // 정확히 3.0
        check(g.isClick, "정확히 3pt도 클릭(넘지 않음)")
    }

    runTest("드래그: 3pt를 넘으면 되돌아와도 드래그로 남는다") {
        var g = ClickDragGesture(start: .zero)
        g.update(to: CGPoint(x: 3.1, y: 0))
        check(g.hasExceededThreshold && !g.isClick, "3.1pt는 드래그")
        g.update(to: CGPoint(x: 0, y: 0))              // 제자리로 돌아와 떼도
        check(!g.isClick, "한번 패닝한 제스처는 클릭이 아니다 — 패닝 후 의도치 않은 복사 방지")
    }

    runTest("OptionKeyGate: ⌥ 단독만 true") {
        check(OptionKeyGate.isOptionAlone([.option]), "⌥")
        check(!OptionKeyGate.isOptionAlone([]), "아무것도 안 누름")
        check(!OptionKeyGate.isOptionAlone([.command]), "⌘만")
    }

    runTest("OptionKeyGate: ⌘⌥·⇧⌥·⌃⌥ 같은 조합 키는 false") {
        check(!OptionKeyGate.isOptionAlone([.command, .option]), "⌘⌥")
        check(!OptionKeyGate.isOptionAlone([.shift, .option]), "⇧⌥")
        check(!OptionKeyGate.isOptionAlone([.control, .option]), "⌃⌥")
        check(!OptionKeyGate.isOptionAlone([.command, .shift, .option]), "⌘⇧⌥")
    }

    runTest("OptionKeyGate: CapsLock·fn 같은 상태 플래그는 무시한다") {
        check(OptionKeyGate.isOptionAlone([.option, .capsLock]), "⌥+CapsLock")
        check(OptionKeyGate.isOptionAlone([.option, .function]), "⌥+fn(방향키 등에서 붙음)")
        check(OptionKeyGate.isOptionAlone([.option, .numericPad]), "⌥+숫자패드 플래그")
    }
}
```

`Tests/main.swift`에 `runColorInteractionTests()` 추가.

- [x] **Step 3: 컴파일 실패 확인** — `make test` → `cannot find 'ClickDragGesture'`.

- [x] **Step 4: 구현**

```swift
// Sources/viewer/ColorInteraction.swift
import AppKit

/// 누른 뒤 거의 움직이지 않고 떼면 클릭, 임계값을 넘으면 드래그(패닝).
struct ClickDragGesture {
    static let threshold: CGFloat = 3

    private let start: CGPoint
    private(set) var hasExceededThreshold = false

    init(start: CGPoint) { self.start = start }

    mutating func update(to point: CGPoint) {
        if hypot(point.x - start.x, point.y - start.y) > Self.threshold { hasExceededThreshold = true }
    }

    var isClick: Bool { !hasExceededThreshold }
}

/// ⌥ 임시 돋보기 판정. ⌘⌥ 같은 조합에선 켜지 않는다.
enum OptionKeyGate {
    static func isOptionAlone(_ flags: NSEvent.ModifierFlags) -> Bool {
        flags.intersection([.command, .option, .control, .shift]) == [.option]
    }
}
```

- [x] **Step 5: 통과 확인** — `make test` → 앞선 25개 + 5개 = 30개 통과.

- [x] **Step 6: 커밋**

```bash
git add Sources/viewer/ColorInteraction.swift Tests/ColorInteractionTests.swift Tests/main.swift Makefile
git commit -m "feat: ClickDragGesture and OptionKeyGate"
```

---

### Task 6: 상호작용 순수 로직 (2) — 정보창 유예, 확대경 배치, 칩 줄바꿈

**Files:**
- Modify: `Sources/viewer/ColorInteraction.swift`
- Modify: `Tests/ColorInteractionTests.swift`

**Interfaces:**
- Produces:
  ```swift
  /// 칩 ↔ 정보창 이동 중 mouseExited가 먼저 와도 정보창이 닫히지 않게 하는 유예.
  final class HoverGrace {
      typealias Scheduler = (_ delay: TimeInterval, _ work: @escaping () -> Void) -> (() -> Void)   // 반환값 = 취소 함수
      init(delay: TimeInterval = 0.12, schedule: @escaping Scheduler = HoverGrace.mainQueueScheduler)
      var onClose: (() -> Void)?
      func enter(); func exit()
      static let mainQueueScheduler: Scheduler
  }
  enum MagnifierPlacement {
      /// 좌하단 원점 좌표. 기본은 커서 오른쪽 아래, 가장자리면 반대편으로 뒤집는다.
      static func frame(cursor: CGPoint, size: CGSize, bounds: CGRect, offset: CGFloat = 18) -> CGRect
  }
  enum ChipFlowLayout {
      /// 위-왼쪽 원점(flipped) 좌표. 넘치면 줄바꿈.
      static func frames(count: Int, itemSize: CGSize, spacing: CGFloat, width: CGFloat) -> (frames: [CGRect], height: CGFloat)
  }
  ```

- [x] **Step 1: 테스트 추가**

`Tests/ColorInteractionTests.swift`에 함수 하나를 더한다(`runColorInteractionTests()` 안에 이어 붙여도 된다).

```swift
/// 시계를 손으로 돌리는 가짜 스케줄러.
private final class FakeClock {
    private(set) var pending: [(id: Int, work: () -> Void, cancelled: Bool)] = []
    private var nextID = 0
    lazy var scheduler: HoverGrace.Scheduler = { [unowned self] _, work in
        let id = self.nextID; self.nextID += 1
        self.pending.append((id, work, false))
        return { if let i = self.pending.firstIndex(where: { $0.id == id }) { self.pending[i].cancelled = true } }
    }
    /// 취소되지 않은 예약을 모두 실행한다.
    func advance() { let due = pending; pending = []; for p in due where !p.cancelled { p.work() } }
}

func runColorInteractionTests2() {
    runTest("HoverGrace: 칩에서 정보창으로 옮겨가도 닫히지 않는다") {
        let clock = FakeClock(); let grace = HoverGrace(delay: 0.12, schedule: clock.scheduler)
        var closed = 0; grace.onClose = { closed += 1 }
        grace.enter()        // 칩 위
        grace.exit()         // 칩을 벗어남 — 정보창에 닿기 전 틈
        grace.enter()        // 정보창 진입 (유예 안)
        clock.advance()
        checkEqual(closed, 0, "정보창으로 건너갔으니 닫히지 않음")
        grace.exit()         // 정보창을 벗어남
        clock.advance()
        checkEqual(closed, 1, "둘 다 벗어나면 유예 후 닫힘")
    }

    runTest("HoverGrace: 둘 다 벗어나면 유예 뒤 정확히 한 번 닫힌다") {
        let clock = FakeClock(); let grace = HoverGrace(delay: 0.12, schedule: clock.scheduler)
        var closed = 0; grace.onClose = { closed += 1 }
        grace.enter(); grace.exit()
        check(closed == 0, "유예 시간이 지나기 전엔 닫히지 않음")
        clock.advance()
        checkEqual(closed, 1, "유예 후 닫힘")
        clock.advance()
        checkEqual(closed, 1, "중복 닫힘 없음")
    }

    runTest("HoverGrace: 옆 칩으로 바로 이동(exit 직후 enter)하면 닫히지 않는다") {
        let clock = FakeClock(); let grace = HoverGrace(delay: 0.12, schedule: clock.scheduler)
        var closed = 0; grace.onClose = { closed += 1 }
        grace.enter(); grace.exit(); grace.enter(); grace.exit(); grace.enter()
        clock.advance()
        checkEqual(closed, 0, "취소된 예약은 실행되지 않음")
    }

    runTest("MagnifierPlacement: 기본은 커서 오른쪽 아래, 가장자리에서 뒤집힌다") {
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
        let size = CGSize(width: 110, height: 134)
        let normal = MagnifierPlacement.frame(cursor: CGPoint(x: 300, y: 400), size: size, bounds: bounds)
        checkEqual(normal, CGRect(x: 318, y: 400 - 18 - 134, width: 110, height: 134), "오른쪽 아래")

        let nearRight = MagnifierPlacement.frame(cursor: CGPoint(x: 780, y: 400), size: size, bounds: bounds)
        check(nearRight.maxX <= 780 - 18 + 0.001, "오른쪽 끝 근처: 커서 왼쪽으로 뒤집힘 \(nearRight)")
        let nearBottom = MagnifierPlacement.frame(cursor: CGPoint(x: 300, y: 30), size: size, bounds: bounds)
        check(nearBottom.minY >= 30 + 18 - 0.001, "아래 끝 근처: 커서 위쪽으로 뒤집힘 \(nearBottom)")
        let corner = MagnifierPlacement.frame(cursor: CGPoint(x: 790, y: 5), size: size, bounds: bounds)
        check(bounds.contains(corner), "모서리: 양쪽 다 뒤집혀도 bounds 안 \(corner)")
    }

    runTest("ChipFlowLayout: 폭을 넘으면 줄바꿈한다") {
        // 폭 300, 칩 40×60, 간격 8 → 한 줄 6개
        let r = ChipFlowLayout.frames(count: 13, itemSize: CGSize(width: 40, height: 60), spacing: 8, width: 300)
        checkEqual(r.frames.count, 13, "개수")
        checkEqual(r.frames[5], CGRect(x: 5 * 48, y: 0, width: 40, height: 60), "첫 줄 마지막")
        checkEqual(r.frames[6], CGRect(x: 0, y: 68, width: 40, height: 60), "둘째 줄 처음")
        checkEqual(r.height, 3 * 60 + 2 * 8, "세 줄 높이")
        checkEqual(ChipFlowLayout.frames(count: 0, itemSize: CGSize(width: 40, height: 60), spacing: 8, width: 300).height, 0, "빈 목록")
        let narrow = ChipFlowLayout.frames(count: 3, itemSize: CGSize(width: 40, height: 60), spacing: 8, width: 10)
        checkEqual(narrow.frames[2].minX, 0, "너무 좁아도 한 줄에 최소 1개")
    }
}
```

`Tests/main.swift`에 `runColorInteractionTests2()` 추가.

- [x] **Step 2: 컴파일 실패 확인** — `make test` → `cannot find 'HoverGrace'`.

- [x] **Step 3: 구현** (`Sources/viewer/ColorInteraction.swift` 끝에 추가)

```swift
/// 칩과 정보창은 서로 떨어진 뷰라 칩을 벗어나는 순간 mouseExited가 정보창 진입보다 먼저 온다.
/// 둘 다 벗어난 상태가 `delay` 이상 이어질 때만 닫는다.
final class HoverGrace {
    typealias Scheduler = (_ delay: TimeInterval, _ work: @escaping () -> Void) -> (() -> Void)

    static let mainQueueScheduler: Scheduler = { delay, work in
        let item = DispatchWorkItem(block: work)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
        return { item.cancel() }
    }

    var onClose: (() -> Void)?
    private let delay: TimeInterval
    private let schedule: Scheduler
    private var insideCount = 0
    private var cancelPending: (() -> Void)?

    init(delay: TimeInterval = 0.12, schedule: @escaping Scheduler = HoverGrace.mainQueueScheduler) {
        self.delay = delay
        self.schedule = schedule
    }

    func enter() {
        insideCount += 1
        cancelPending?()
        cancelPending = nil
    }

    func exit() {
        insideCount = max(0, insideCount - 1)
        guard insideCount == 0 else { return }
        cancelPending?()
        cancelPending = schedule(delay) { [weak self] in
            guard let self, self.insideCount == 0 else { return }
            self.cancelPending = nil
            self.onClose?()
        }
    }
}

enum MagnifierPlacement {
    /// 좌하단 원점(비뒤집힘) 좌표. 기본은 커서 오른쪽 아래, 가장자리에 닿으면 반대편으로 뒤집는다.
    static func frame(cursor: CGPoint, size: CGSize, bounds: CGRect, offset: CGFloat = 18) -> CGRect {
        var x = cursor.x + offset
        if x + size.width > bounds.maxX { x = cursor.x - offset - size.width }
        var y = cursor.y - offset - size.height
        if y < bounds.minY { y = cursor.y + offset }
        x = min(max(x, bounds.minX), bounds.maxX - size.width)
        y = min(max(y, bounds.minY), bounds.maxY - size.height)
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }
}

enum ChipFlowLayout {
    /// 위-왼쪽 원점(flipped) 좌표. 한 줄에 최소 1개.
    static func frames(count: Int, itemSize: CGSize, spacing: CGFloat, width: CGFloat) -> (frames: [CGRect], height: CGFloat) {
        guard count > 0 else { return ([], 0) }
        let perRow = max(1, Int(((width + spacing) / (itemSize.width + spacing)).rounded(.down)))
        var frames: [CGRect] = []
        for i in 0..<count {
            let row = i / perRow, col = i % perRow
            frames.append(CGRect(x: CGFloat(col) * (itemSize.width + spacing),
                                 y: CGFloat(row) * (itemSize.height + spacing),
                                 width: itemSize.width, height: itemSize.height))
        }
        let rows = (count + perRow - 1) / perRow
        return (frames, CGFloat(rows) * itemSize.height + CGFloat(rows - 1) * spacing)
    }
}
```

- [x] **Step 4: 통과 확인** — `make test` → 앞선 30개 + 이 Task 5개 = 35개 통과.

- [x] **Step 5: 커밋**

```bash
git add Sources/viewer/ColorInteraction.swift Tests/ColorInteractionTests.swift Tests/main.swift
git commit -m "feat: HoverGrace, MagnifierPlacement and ChipFlowLayout"
```

---

### Task 7: AppSettings 슬라이더 값 + 로컬라이즈 문자열

**Files:**
- Modify: `Sources/services/AppSettings.swift` (키 1개, 프로퍼티, 상수)
- Modify: `Sources/services/Localization.swift` (`L10nKey` 케이스 + 네 언어 문자열)
- Create: `Tests/UI/ViewerColorTests.swift`
- Modify: `Tests/UI/main.swift`

**Interfaces:**
- Produces:
  ```swift
  AppSettings.colorToleranceRange: ClosedRange<Double>      // Task 3 결정값 (기본 가정 2...40)
  AppSettings.defaultColorTolerance: Double                 // Task 3 결정값 (기본 가정 12)
  var colorTolerance: Double { get set }                    // 범위로 clamp, 앱 전체 마지막 값
  L10nKey: .colorButton, .colorMagnifier, .colorRange, .colorCountFormat, .colorCopyAllHex,
           .colorCopied, .colorCursor, .colorExtracting, .colorNoColors, .colorCopyValue
  ```

- [x] **Step 1: 실패하는 테스트 작성**

`Tests/UI/ViewerColorTests.swift`를 새로 만든다. 이후 Task 8·10·11·12의 UI 테스트도 이 파일에 함수로 추가한다.

```swift
import AppKit

@MainActor
func runViewerColorTests(directory: URL) {
    runTest("AppSettings.colorTolerance: 기본값·저장·범위 고정") {
        let suiteName = "jena-color-settings-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        checkEqual(settings.colorTolerance, AppSettings.defaultColorTolerance, "저장값 없으면 기본값")
        settings.colorTolerance = 20
        checkEqual(AppSettings(defaults: defaults).colorTolerance, 20, "다른 인스턴스(재실행)에서도 유지")
        settings.colorTolerance = 999
        checkEqual(settings.colorTolerance, AppSettings.colorToleranceRange.upperBound, "상한으로 고정")
        settings.colorTolerance = -5
        checkEqual(settings.colorTolerance, AppSettings.colorToleranceRange.lowerBound, "하한으로 고정")
    }

    runTest("색상 기능 문자열이 모든 언어에서 비어 있지 않다") {
        let keys: [L10nKey] = [.colorButton, .colorMagnifier, .colorRange, .colorCountFormat, .colorCopyAllHex,
                               .colorCopied, .colorCursor, .colorExtracting, .colorNoColors, .colorCopyValue]
        let saved = L10n.language
        defer { L10n.language = saved }
        for language in Language.allCases {
            L10n.language = language
            for key in keys { check(L10n.string(key) != key.rawValue && !L10n.string(key).isEmpty, "\(language) \(key)") }
        }
        L10n.language = .korean
        checkEqual(String(format: L10n.string(.colorCountFormat), 14), "14색", "개수 표기")
    }
}
```

`Tests/UI/main.swift`의 `runCompareLayoutTests` 줄 아래에 추가:

```swift
MainActor.assumeIsolated { runViewerColorTests(directory: temporary) }
```

- [x] **Step 2: 실패 확인** — `make test-ui` → `value of type 'AppSettings' has no member 'colorTolerance'`.

- [x] **Step 3: AppSettings 구현**

`Key` enum 끝(`canvasBackgroundOpacity` 아래)에 `case colorTolerance = "colorTolerance"`를 추가하고, `slideshowInterval` 블록 아래(닫는 `}` 앞)에 추가한다. 범위·기본값은 Task 3 결정값을 쓴다(아래는 기본 가정).

```swift
    // MARK: - Color Picker

    /// 색상 패널 허용 범위(ΔE) 슬라이더. 범위·기본값은 devlog 2026-11-02-color-picker 측정 결과.
    static let colorToleranceRange: ClosedRange<Double> = 2...40
    static let defaultColorTolerance: Double = 12

    var colorTolerance: Double {
        get {
            let v = defaults.object(forKey: Key.colorTolerance.rawValue) as? Double ?? Self.defaultColorTolerance
            return min(max(v, Self.colorToleranceRange.lowerBound), Self.colorToleranceRange.upperBound)
        }
        set {
            let v = min(max(newValue, Self.colorToleranceRange.lowerBound), Self.colorToleranceRange.upperBound)
            defaults.set(v, forKey: Key.colorTolerance.rawValue)
        }
    }
```

- [x] **Step 4: 문자열 추가**

`L10nKey`의 `case continueAction` 아래에:

```swift

    // Color picker
    case colorButton
    case colorMagnifier
    case colorRange
    case colorCountFormat
    case colorCopyAllHex
    case colorCopied
    case colorCursor
    case colorExtracting
    case colorNoColors
    case colorCopyValue
```

네 언어 딕셔너리 각각의 `.continueAction: …,` 아래에 추가:

```swift
            // .korean
            .colorButton: "색상", .colorMagnifier: "돋보기", .colorRange: "범위", .colorCountFormat: "%d색",
            .colorCopyAllHex: "HEX 전체 복사", .colorCopied: "복사됨", .colorCursor: "커서 위치 색",
            .colorExtracting: "색을 추출하는 중…", .colorNoColors: "추출된 색이 없어요", .colorCopyValue: "복사",
            // .english
            .colorButton: "Colors", .colorMagnifier: "Magnifier", .colorRange: "Range", .colorCountFormat: "%d colors",
            .colorCopyAllHex: "Copy all HEX", .colorCopied: "Copied", .colorCursor: "Color under cursor",
            .colorExtracting: "Extracting colors…", .colorNoColors: "No colors found", .colorCopyValue: "Copy",
            // .japanese
            .colorButton: "カラー", .colorMagnifier: "拡大鏡", .colorRange: "範囲", .colorCountFormat: "%d色",
            .colorCopyAllHex: "HEXをすべてコピー", .colorCopied: "コピーしました", .colorCursor: "カーソル位置の色",
            .colorExtracting: "色を抽出中…", .colorNoColors: "色がありません", .colorCopyValue: "コピー",
            // .chinese
            .colorButton: "颜色", .colorMagnifier: "放大镜", .colorRange: "范围", .colorCountFormat: "%d 种颜色",
            .colorCopyAllHex: "复制全部 HEX", .colorCopied: "已复制", .colorCursor: "光标处颜色",
            .colorExtracting: "正在提取颜色…", .colorNoColors: "没有可用颜色", .colorCopyValue: "复制",
```

(각 주석 `// .korean` 등은 넣지 않고, 해당 언어 딕셔너리 안에 해당 줄만 넣는다.)

- [x] **Step 5: 통과 확인**

Run: `make build && make test-ui`
Expected: 새 테스트 2개 통과, 기존 UI 테스트 그대로 통과. 한국어 개수 표기는 `"%d색"`이라 `14색`.

- [x] **Step 6: 커밋**

```bash
git add Sources/services/AppSettings.swift Sources/services/Localization.swift Tests/UI/ViewerColorTests.swift Tests/UI/main.swift
git commit -m "feat: persisted color tolerance setting and color picker strings"
```

---

### Task 8: MagnifierOverlayView + ImageDisplayView 돋보기 모드

**Files:**
- Create: `Sources/viewer/MagnifierOverlayView.swift`
- Modify: `Sources/viewer/ImageDisplayView.swift` (공개 프로퍼티·콜백, 추적 영역, 마우스 처리, 원본 픽셀 조회)
- Modify: `Tests/UI/ViewerColorTests.swift`

**Interfaces:**
- Consumes: `PixelMapping`, `PixelSampler`, `ClickDragGesture`, `MagnifierPlacement` (Task 4~6).
- Produces (`ImageDisplayView`):
  ```swift
  var isMagnifierActive: Bool          // 패널 토글 또는 ⌥. 기본 false
  var pixelSource: CGImage?            // 원본 픽셀 소스. nil이면 돋보기는 동작하지 않는다
  var onColorHover: ((RGB8?) -> Void)? // 커서 아래 색(이미지 밖이면 nil)
  var onColorPicked: ((RGB8) -> Void)? // 클릭(mouseUp)으로 고른 색
  func originalPixel(atWindowPoint: CGPoint) -> PixelMapping.PixelCoord?
  ```
- 동작 규칙: `isMagnifierActive == false`이면 마우스 처리가 **기존과 완전히 같다**(`mouseDown`의 더블클릭 닫기·`closedHand` push/pop 포함). 켜져 있으면 — 누른 시점의 상태(`gestureStartedInMagnifier`)로 그 제스처를 판단, 더블클릭 닫기 안 함, 3pt 이내 mouseUp = 선택(복사), 초과 = 패닝(확대경 숨김, 패닝 시작 시점에 `closedHand` push), 패닝이 끝나면 확대경 다시 표시.

- [x] **Step 1: 실패하는 UI 테스트 작성**

`Tests/UI/ViewerColorTests.swift`에 추가한다(`runViewerColorTests` 안에 이어서). 오프스크린 창에 `ImageDisplayView`를 직접 올려 이벤트를 합성한다.

```swift
private func mouseEvent(_ type: NSEvent.EventType, at p: NSPoint, window: NSWindow, clickCount: Int = 1) -> NSEvent {
    NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                       context: nil, eventNumber: 0, clickCount: clickCount, pressure: 1)!
}

/// 40×20 이미지를 올린 오프스크린 창과 ImageDisplayView.
@MainActor
private func makeDisplay() -> (window: NSWindow, display: ImageDisplayView, center: NSPoint) {
    let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 400, height: 300),
                          styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let display = ImageDisplayView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
    window.contentView = display
    window.orderFront(nil)
    let cg = makeTestImage(width: 40, height: 20) { x, y in RGB8(UInt8(x * 6), UInt8(y * 12), 90) }
    display.display(NSImage(cgImage: cg, size: NSSize(width: 40, height: 20)))
    display.pixelSource = cg
    window.contentView?.layoutSubtreeIfNeeded()
    let center = display.convert(NSPoint(x: display.bounds.midX, y: display.bounds.midY), to: nil)
    return (window, display, center)
}
```

그리고 `runViewerColorTests` 안에 테스트 세 개를 추가한다.

```swift
    runTest("돋보기 모드에선 더블클릭이 뷰어를 닫지 않고, 꺼지면 닫는다") {
        let (window, display, center) = makeDisplay()
        defer { window.close() }
        var doubleClicks = 0, picks: [RGB8] = []
        display.onDoubleClick = { doubleClicks += 1 }
        display.onColorPicked = { picks.append($0) }

        display.isMagnifierActive = true
        for count in 1...3 {          // 같은 자리를 빠르게 세 번: clickCount 1,2,3
            display.mouseDown(with: mouseEvent(.leftMouseDown, at: center, window: window, clickCount: count))
            display.mouseUp(with: mouseEvent(.leftMouseUp, at: center, window: window, clickCount: count))
        }
        checkEqual(doubleClicks, 0, "돋보기 중엔 더블클릭 닫기 없음")
        checkEqual(picks.count, 3, "세 번 모두 색 선택")

        display.isMagnifierActive = false
        display.mouseDown(with: mouseEvent(.leftMouseDown, at: center, window: window, clickCount: 2))
        display.mouseUp(with: mouseEvent(.leftMouseUp, at: center, window: window, clickCount: 2))
        checkEqual(doubleClicks, 1, "꺼지면 기존처럼 더블클릭으로 닫음")
        checkEqual(picks.count, 3, "꺼진 뒤엔 선택 안 함")
    }

    runTest("돋보기 모드: 3pt 이내는 선택, 넘으면 패닝이고 선택하지 않는다") {
        let (window, display, center) = makeDisplay()
        defer { window.close() }
        var picks = 0
        display.onColorPicked = { _ in picks += 1 }
        display.isMagnifierActive = true

        display.mouseDown(with: mouseEvent(.leftMouseDown, at: center, window: window))
        display.mouseDragged(with: mouseEvent(.leftMouseDragged, at: NSPoint(x: center.x + 2, y: center.y), window: window))
        display.mouseUp(with: mouseEvent(.leftMouseUp, at: NSPoint(x: center.x + 2, y: center.y), window: window))
        checkEqual(picks, 1, "2pt 이동 후 뗌 = 클릭")

        display.mouseDown(with: mouseEvent(.leftMouseDown, at: center, window: window))
        display.mouseDragged(with: mouseEvent(.leftMouseDragged, at: NSPoint(x: center.x + 12, y: center.y), window: window))
        display.mouseUp(with: mouseEvent(.leftMouseUp, at: NSPoint(x: center.x + 12, y: center.y), window: window))
        checkEqual(picks, 1, "12pt 드래그는 패닝 — 선택 안 함")

        // 누른 시점 상태로 판단: 누른 뒤 돋보기가 꺼져도(⌥를 뗌) 클릭이면 선택된다.
        display.mouseDown(with: mouseEvent(.leftMouseDown, at: center, window: window))
        display.isMagnifierActive = false
        display.mouseUp(with: mouseEvent(.leftMouseUp, at: center, window: window))
        checkEqual(picks, 2, "⌥를 누른 채 누르고 뗀 경우 누른 시점 기준")
    }

    runTest("배율·반전 상태에서 창 좌표가 같은 원본 픽셀을 가리킨다") {
        let (window, display, center) = makeDisplay()
        defer { window.close() }
        display.applyTransform(magnification: 2, centerInImage: CGPoint(x: 0.5, y: 0.5))
        window.contentView?.layoutSubtreeIfNeeded()

        // 문서 좌표가 소수점이 되도록 0.37을 더한다 (픽셀 경계에 걸리지 않게).
        let p = NSPoint(x: center.x + 10.37, y: center.y + 3.37)
        let before = display.originalPixel(atWindowPoint: p)!
        let moved = display.originalPixel(atWindowPoint: NSPoint(x: p.x + 10, y: p.y))!
        checkEqual(moved.x - before.x, 5, "배율 2: 창에서 10pt = 원본 5픽셀")

        display.flipHorizontal()
        let flippedH = display.originalPixel(atWindowPoint: p)!
        checkEqual(before.x + flippedH.x, 39, "좌우 반전: x가 40-1-x로 대응")
        checkEqual(before.y, flippedH.y, "좌우 반전은 y 불변")
        display.flipVertical()
        let flippedBoth = display.originalPixel(atWindowPoint: p)!
        checkEqual(before.y + flippedBoth.y, 19, "상하 반전: y가 20-1-y로 대응")

        display.resetFlip()
        display.rotateRight()
        window.contentView?.layoutSubtreeIfNeeded()
        check(display.originalPixel(atWindowPoint: NSPoint(x: center.x + 1000, y: center.y)) == nil, "이미지 밖은 nil")
    }

    runTest("비교 칸의 ImageDisplayView는 돋보기·오버레이가 없다") {
        let (window, display, center) = makeDisplay()
        defer { window.close() }
        check(!display.isMagnifierActive, "기본은 꺼짐")
        display.mouseMoved(with: mouseEvent(.mouseMoved, at: center, window: window))
        check(descendants(display, of: MagnifierOverlayView.self).isEmpty, "꺼져 있으면 오버레이를 만들지도 않음")
        var doubleClicks = 0
        display.onDoubleClick = { doubleClicks += 1 }
        display.mouseDown(with: mouseEvent(.leftMouseDown, at: center, window: window, clickCount: 2))
        checkEqual(doubleClicks, 1, "더블클릭 동작 그대로")
    }
```

- [x] **Step 2: 실패 확인** — `make test-ui` → `value of type 'ImageDisplayView' has no member 'isMagnifierActive'`.

- [x] **Step 3: MagnifierOverlayView 구현**

```swift
// Sources/viewer/MagnifierOverlayView.swift
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

    override var isFlipped: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    static var loupeSize: CGSize {
        let side = CGFloat(radius * 2 + 1) * cell
        return CGSize(width: side, height: side + labelHeight + 4)
    }

    /// `point`는 이 뷰 좌표(= scrollView 좌표). 격자의 가운데가 읽는 픽셀이다.
    func show(at point: CGPoint, grid: [RGB8?]) {
        cursorPoint = point
        self.grid = grid
        if let center = grid[grid.count / 2] { labelText = ColorFormat.hex(center) } else { labelText = "" }
        isHidden = false
        needsDisplay = true
    }

    func hideLoupe() {
        guard !isHidden else { return }
        isHidden = true
        copiedTimer?.invalidate()
        showsCopied = false
    }

    func flashCopied() {
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
```

- [x] **Step 4: ImageDisplayView에 돋보기 모드 추가**

(a) `// MARK: - Click-Drag Pan` 위에 새 섹션을 넣는다.

```swift
    // MARK: - Magnifier

    /// 패널 토글 또는 ⌥로 켜진 돋보기. 꺼져 있으면 기존 마우스 동작이 그대로다(비교 화면도 이 상태).
    var isMagnifierActive = false {
        didSet {
            guard oldValue != isMagnifierActive else { return }
            if isMagnifierActive { refreshMagnifierAtMouse() } else { hideMagnifier() }
            window?.invalidateCursorRects(for: self)
        }
    }

    /// 원본 픽셀 소스. 화면에 그려진 결과가 아니라 여기서 읽는다. nil이면 돋보기는 동작하지 않는다.
    var pixelSource: CGImage? {
        didSet { if pixelSource != nil, isMagnifierActive { refreshMagnifierAtMouse() } else if pixelSource == nil { hideMagnifier() } }
    }

    var onColorHover: ((RGB8?) -> Void)?
    var onColorPicked: ((RGB8) -> Void)?

    private var magnifierOverlay: MagnifierOverlayView?
    private var magnifierTrackingArea: NSTrackingArea?
    private var gesture: ClickDragGesture?
    private var gestureStartedInMagnifier = false
    private var didPushPanCursor = false

    private var canMagnify: Bool { isMagnifierActive && pixelSource != nil && !isLoading && cropOverlay == nil && !isHidden }

    /// 창 좌표 → 원본 픽셀. 반전·회전·배율을 거꾸로 적용한다. 이미지 밖이면 nil.
    func originalPixel(atWindowPoint windowPoint: CGPoint) -> PixelMapping.PixelCoord? {
        guard let source = originalImage, let cg = pixelSource else { return nil }
        let document = imageView.convert(windowPoint, from: nil)    // 배율·패닝은 clipView.bounds가 처리한다
        return PixelMapping.originalPixel(documentPoint: document, sourceSize: source.size,
                                          pixelWidth: cg.width, pixelHeight: cg.height,
                                          flipH: isFlippedHorizontally, flipV: isFlippedVertically, rotation: rotationAngle)
    }

    /// 버튼처럼 이 뷰 위에 겹친 다른 뷰 아래에서는 추적 영역이 이벤트를 받아도 확대경을 띄우지 않는다.
    private func isMouseOverSelf(_ windowPoint: CGPoint) -> Bool {
        guard let hit = window?.contentView?.hitTest(windowPoint) else { return false }
        return hit === self || hit.isDescendant(of: self)
    }

    private func refreshMagnifier(atWindowPoint windowPoint: CGPoint) {
        guard canMagnify, !didPushPanCursor, isMouseOverSelf(windowPoint) else { hideMagnifier(); return }
        guard let cg = pixelSource, let px = originalPixel(atWindowPoint: windowPoint) else {
            hideMagnifier(); onColorHover?(nil); return
        }
        let grid = PixelSampler.grid(in: cg, centerX: px.x, centerY: px.y, radius: MagnifierOverlayView.radius)
        let overlay = ensureMagnifierOverlay()
        overlay.show(at: scrollView.convert(windowPoint, from: nil), grid: grid)
        onColorHover?(grid[grid.count / 2])
        NSCursor.crosshair.set()
    }

    private func refreshMagnifierAtMouse() {
        guard let window else { return }
        refreshMagnifier(atWindowPoint: window.mouseLocationOutsideOfEventStream)
    }

    private func hideMagnifier() {
        magnifierOverlay?.hideLoupe()
        onColorHover?(nil)
    }

    private func ensureMagnifierOverlay() -> MagnifierOverlayView {
        if let overlay = magnifierOverlay { return overlay }
        let overlay = MagnifierOverlayView(frame: scrollView.bounds)
        overlay.autoresizingMask = [.width, .height]
        scrollView.addSubview(overlay)
        magnifierOverlay = overlay
        return overlay
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area = magnifierTrackingArea { removeTrackingArea(area) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .cursorUpdate, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        magnifierTrackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        guard isMagnifierActive else { return }
        refreshMagnifier(atWindowPoint: event.locationInWindow)
    }

    override func mouseExited(with event: NSEvent) {
        if isMagnifierActive { hideMagnifier() }
    }

    override func cursorUpdate(with event: NSEvent) {
        if canMagnify, originalPixel(atWindowPoint: event.locationInWindow) != nil { NSCursor.crosshair.set() } else { super.cursorUpdate(with: event) }
    }
```

(b) `clearImage()`와 `display(_:)`에서 이전 이미지의 소스를 비운다. `clearImage()`의 `originalImage = nil` 바로 위, `display(_:)`의 `originalImage = image` 바로 위에 각각 `pixelSource = nil`을 추가한다.

(c) `// MARK: - Click-Drag Pan`의 세 메서드를 아래로 교체한다. **돋보기가 꺼진 경로는 기존 코드와 동일**하게 유지한다(주석으로 표시).

```swift
    override func mouseDown(with event: NSEvent) {
        guard cropOverlay == nil else { return }

        gestureStartedInMagnifier = canMagnify      // 누른 시점 상태로 이 제스처를 판단한다
        didPushPanCursor = false

        if gestureStartedInMagnifier {
            // 연속 클릭으로 뷰어가 닫히지 않도록 더블클릭 닫기는 건너뛰고 클릭으로 처리한다.
            onSingleClick?()
            isPanning = true
            panStart = event.locationInWindow
            gesture = ClickDragGesture(start: event.locationInWindow)
            return
        }

        // ── 돋보기 꺼짐: 기존 동작 그대로 ──
        if event.clickCount == 2 {
            onDoubleClick?()
            return
        }

        onSingleClick?()

        // 줌이 적용된 상태에서 클릭 드래그 → 패닝
        isPanning = true
        panStart = event.locationInWindow
        NSCursor.closedHand.push()
    }

    override func mouseDragged(with event: NSEvent) {
        guard cropOverlay == nil, isPanning else { return }

        if gestureStartedInMagnifier {
            gesture?.update(to: event.locationInWindow)
            guard gesture?.hasExceededThreshold == true else { return }    // 3pt 이내는 패닝하지 않는다
            if !didPushPanCursor {
                didPushPanCursor = true
                NSCursor.closedHand.push()
                hideMagnifier()                                            // 패닝 중엔 확대경 숨김
            }
        }

        let current = event.locationInWindow
        let dx = current.x - panStart.x
        let dy = current.y - panStart.y
        panStart = current

        var origin = clipView.bounds.origin
        origin.x -= dx
        origin.y -= dy
        clipView.setBoundsOrigin(origin)
        notifyTransformChanged()
    }

    override func mouseUp(with event: NSEvent) {
        guard cropOverlay == nil else { return }

        if gestureStartedInMagnifier {
            let wasClick = gesture?.isClick ?? false
            gesture = nil
            gestureStartedInMagnifier = false
            isPanning = false
            if didPushPanCursor { NSCursor.pop(); didPushPanCursor = false }
            if wasClick {
                if let cg = pixelSource, let px = originalPixel(atWindowPoint: event.locationInWindow),
                   let color = PixelSampler.color(in: cg, x: px.x, y: px.y) {
                    onColorPicked?(color)
                    magnifierOverlay?.flashCopied()
                }
            } else {
                refreshMagnifier(atWindowPoint: event.locationInWindow)    // 패닝이 끝나면 확대경 복귀
            }
            return
        }

        // ── 돋보기 꺼짐: 기존 동작 그대로 ──
        if isPanning {
            isPanning = false
            NSCursor.pop()
        }
    }
```

- [x] **Step 5: 통과 확인**

Run: `make build && make test-ui`
Expected: 새 UI 테스트 4개 통과, 기존 UI 테스트 전부 통과. `make build` 경고·에러 0.
`배율·반전 …` 테스트에서 `moved.x - before.x == 5`가 어긋나면 `originalPixel(atWindowPoint:)`의 `convert(_:from:)` 결과가 배율을 반영하는지(= `scrollView.magnification`이 2인지, `applyTransform`이 먼저 `layoutSubtreeIfNeeded()` 뒤에 적용됐는지)를 먼저 본다.

- [x] **Step 6: 커밋**

```bash
git add Sources/viewer/MagnifierOverlayView.swift Sources/viewer/ImageDisplayView.swift Tests/UI/ViewerColorTests.swift
git commit -m "feat: magnifier overlay and magnifier mode in ImageDisplayView"
```

---

### Task 9: ColorPalettePanel (슬라이더·칩·정보창·커서 위치 색·HEX 전체 복사)

화면 구성이 중심이라 자동 테스트는 Task 10~12의 연결 테스트에서 한다. 이 Task는 빌드와 스모크 확인까지.

**Files:**
- Create: `Sources/viewer/ColorClipboard.swift`
- Create: `Sources/viewer/ColorInfoPopover.swift`
- Create: `Sources/viewer/ColorPalettePanel.swift`

**Interfaces:**
- Consumes: `ColorSwatch`, `ColorFormat`, `HoverGrace`, `ChipFlowLayout`, `AppSettings.colorToleranceRange` (Task 1·6·7).
- Produces:
  ```swift
  enum ColorClipboard { static func copy(_ string: String) }
  final class ColorPalettePanel: NSView {
      enum State { case loading, empty, ready([ColorSwatch]) }
      static let height: CGFloat = 150
      var onMagnifierToggled: ((Bool) -> Void)?
      var onToleranceChanged: ((Double) -> Void)?
      var onCopyAllHex: (() -> Void)?
      func setState(_ state: State)
      func setTolerance(_ value: Double)
      func setMagnifierOn(_ on: Bool)            // 콜백 없이 토글 표시만 바꾼다
      func setHover(_ color: RGB8?)              // 커서 아래 색(밖이면 nil)
      func setPicked(_ color: RGB8)              // 마지막으로 클릭한 색
  }
  ```

- [x] **Step 1: ColorClipboard**

```swift
// Sources/viewer/ColorClipboard.swift
import AppKit

/// 색 값 복사. NSPasteboard.general에 문자열 하나만 넣는다.
enum ColorClipboard {
    static func copy(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }
}
```

- [x] **Step 2: 정보창 (값 행 + 팝오버)**

```swift
// Sources/viewer/ColorInfoPopover.swift
import AppKit

/// "HEX #E76F51 [복사]" 한 줄. 패널의 "커서 위치 색"과 칩 정보창이 같이 쓴다.
final class ColorValueRow: NSView {
    enum Kind: CaseIterable {
        case hex, rgb, cmyk
        var title: String { switch self { case .hex: "HEX"; case .rgb: "RGB"; case .cmyk: "CMYK" } }
        func text(_ c: RGB8) -> String {
            switch self { case .hex: ColorFormat.hex(c); case .rgb: ColorFormat.rgbString(c); case .cmyk: ColorFormat.cmykString(c) }
        }
    }

    let kind: Kind
    var onCopy: ((String) -> Void)?
    private let valueLabel = NSTextField(labelWithString: "—")
    private let copyButton = NSButton()
    private var value = ""
    private var resetWork: DispatchWorkItem?

    init(kind: Kind) {
        self.kind = kind
        super.init(frame: .zero)
        let title = NSTextField(labelWithString: kind.title)
        title.font = .systemFont(ofSize: 11, weight: .semibold)
        title.textColor = .secondaryLabelColor
        title.widthAnchor.constraint(equalToConstant: 38).isActive = true
        valueLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        valueLabel.lineBreakMode = .byClipping
        copyButton.bezelStyle = .inline
        copyButton.isBordered = false
        copyButton.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: L10n.string(.colorCopyValue))
        copyButton.toolTip = L10n.string(.colorCopyValue)
        copyButton.refusesFirstResponder = true       // 포커스를 가져가면 ⌥(flagsChanged)가 뷰어로 오지 않는다
        copyButton.target = self
        copyButton.action = #selector(copyTapped)
        let stack = NSStackView(views: [title, valueLabel, NSView(), copyButton])
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func setColor(_ color: RGB8?) {
        resetWork?.cancel()
        value = color.map(kind.text) ?? ""
        valueLabel.stringValue = color == nil ? "—" : value
        copyButton.isEnabled = color != nil
    }

    /// 값 자리에 "복사됨"을 약 1초 보여 준다.
    func flashCopied() {
        resetWork?.cancel()
        valueLabel.stringValue = L10n.string(.colorCopied)
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.valueLabel.stringValue = self.value.isEmpty ? "—" : self.value
        }
        resetWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    @objc private func copyTapped() {
        guard !value.isEmpty else { return }
        onCopy?(value)
        flashCopied()
    }
}

/// 칩 정보창 내용: 색 견본 + HEX·RGB·CMYK 행. 마우스 진입·이탈을 유예 로직에 알린다.
final class ColorInfoView: NSView {
    let rows = ColorValueRow.Kind.allCases.map { ColorValueRow(kind: $0) }
    var onMouseEntered: (() -> Void)?
    var onMouseExited: (() -> Void)?
    private let swatch = NSView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        swatch.wantsLayer = true
        swatch.layer?.cornerRadius = 6
        swatch.layer?.borderWidth = 1
        swatch.layer?.borderColor = NSColor.separatorColor.cgColor
        swatch.translatesAutoresizingMaskIntoConstraints = false
        swatch.heightAnchor.constraint(equalToConstant: 36).isActive = true
        let stack = NSStackView(views: [swatch] + rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            swatch.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -24),
            widthAnchor.constraint(equalToConstant: 230),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func setColor(_ color: RGB8) {
        swatch.layer?.backgroundColor = NSColor(srgbRed: CGFloat(color.r) / 255, green: CGFloat(color.g) / 255,
                                                blue: CGFloat(color.b) / 255, alpha: 1).cgColor
        rows.forEach { $0.setColor(color) }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }
    override func mouseEntered(with event: NSEvent) { onMouseEntered?() }
    override func mouseExited(with event: NSEvent) { onMouseExited?() }
}

/// 칩 위쪽에 붙는 정보창. NSPopover는 별도 창이라 패널 경계에 잘리지 않고, 칩에서 정보창으로 마우스를 옮길 수 있다.
/// 닫힘은 HoverGrace가 정한다(칩 ↔ 정보창 사이 틈에서 닫히지 않게).
final class ColorInfoPopover: NSObject {
    private let popover = NSPopover()
    private let info = ColorInfoView()
    private let grace = HoverGrace()
    private weak var currentChip: NSView?
    var onCopy: ((String) -> Void)?

    override init() {
        super.init()
        let controller = NSViewController()
        controller.view = info
        popover.contentViewController = controller
        popover.behavior = .applicationDefined      // 바깥 클릭·포커스 이동으로 닫히지 않게. 닫힘은 우리가 정한다.
        popover.animates = false
        info.onMouseEntered = { [weak self] in self?.grace.enter() }
        info.onMouseExited = { [weak self] in self?.grace.exit() }
        info.rows.forEach { row in row.onCopy = { [weak self] in self?.onCopy?($0) } }
        grace.onClose = { [weak self] in self?.close() }
    }

    func chipEntered(_ chip: NSView, color: RGB8) {
        grace.enter()
        info.setColor(color)
        if currentChip !== chip || !popover.isShown {
            if popover.isShown { popover.close() }
            currentChip = chip
            popover.show(relativeTo: chip.bounds, of: chip, preferredEdge: .maxY)   // 칩 위쪽 (chip은 비뒤집힘 뷰)
        }
    }

    func chipExited() { grace.exit() }

    /// 칩을 클릭해 HEX를 복사했을 때 HEX 줄에 "복사됨".
    func flashHexCopied() { info.rows.first { $0.kind == .hex }?.flashCopied() }

    func close() {
        popover.close()
        currentChip = nil
    }
}
```

- [x] **Step 3: 패널**

```swift
// Sources/viewer/ColorPalettePanel.swift
import AppKit

/// 비율 순 칩 한 개. 칩 아래에 비율(%).
private final class ColorChipView: NSView {
    static let size = CGSize(width: 44, height: 62)
    let swatch: ColorSwatch
    var onHover: ((Bool) -> Void)?
    var onClick: (() -> Void)?

    init(swatch: ColorSwatch) {
        self.swatch = swatch
        super.init(frame: CGRect(origin: .zero, size: Self.size))
        setAccessibilityLabel("\(ColorFormat.hex(swatch.color)) \(Int((swatch.ratio * 100).rounded()))%")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let c = swatch.color
        let chip = CGRect(x: 0, y: 18, width: bounds.width, height: bounds.height - 18)
        NSColor(srgbRed: CGFloat(c.r) / 255, green: CGFloat(c.g) / 255, blue: CGFloat(c.b) / 255, alpha: 1).setFill()
        let path = NSBezierPath(roundedRect: chip, xRadius: 6, yRadius: 6)
        path.fill()
        NSColor.separatorColor.setStroke(); path.lineWidth = 1; path.stroke()
        let pct = swatch.ratio >= 0.1 ? String(format: "%.0f%%", swatch.ratio * 100) : String(format: "%.1f%%", swatch.ratio * 100)
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.secondaryLabelColor]
        let s = (pct as NSString).size(withAttributes: attrs)
        (pct as NSString).draw(at: CGPoint(x: (bounds.width - s.width) / 2, y: 2), withAttributes: attrs)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }
    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
    override func mouseDown(with event: NSEvent) { onClick?() }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
}

/// 칩을 줄바꿈하며 배치하는 문서 뷰(위-왼쪽 원점).
private final class ChipFlowView: NSView {
    override var isFlipped: Bool { true }
    var chips: [ColorChipView] = [] {
        didSet { oldValue.forEach { $0.removeFromSuperview() }; chips.forEach(addSubview); relayout(width: bounds.width) }
    }

    func relayout(width: CGFloat) {
        let r = ChipFlowLayout.frames(count: chips.count, itemSize: ColorChipView.size, spacing: 8, width: max(width, 1))
        for (chip, frame) in zip(chips, r.frames) { chip.frame = frame }
        frame.size = CGSize(width: width, height: max(r.height, 1))
    }
}

/// 이미지 아래에서 올라오는 색상 서랍.
final class ColorPalettePanel: NSView {
    enum State { case loading, empty, ready([ColorSwatch]) }
    static let height: CGFloat = 150

    var onMagnifierToggled: ((Bool) -> Void)?
    var onToleranceChanged: ((Double) -> Void)?
    var onCopyAllHex: (() -> Void)?

    private let magnifierToggle = NSButton()
    private let slider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let countLabel = NSTextField(labelWithString: "")
    private let copyAllButton = NSButton(title: "", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "")
    private let progress = NSProgressIndicator()
    private let scroll = NSScrollView()
    private let flow = ChipFlowView()
    private let popover = ColorInfoPopover()

    // "커서 위치 색" 칸
    private let cursorBox = NSStackView()
    private let cursorSwatch = NSView()
    private let cursorRows = ColorValueRow.Kind.allCases.map { ColorValueRow(kind: $0) }
    private var liveColor: RGB8?
    private var pickedColor: RGB8?
    private var magnifierOn = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.96).cgColor
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Public

    func setState(_ state: State) {
        switch state {
        case .loading:
            flow.chips = []
            statusLabel.stringValue = L10n.string(.colorExtracting); statusLabel.isHidden = false
            progress.startAnimation(nil); progress.isHidden = false
            countLabel.stringValue = ""; copyAllButton.isEnabled = false
            popover.close()
        case .empty:
            flow.chips = []
            statusLabel.stringValue = L10n.string(.colorNoColors); statusLabel.isHidden = false
            progress.stopAnimation(nil); progress.isHidden = true
            countLabel.stringValue = ""; copyAllButton.isEnabled = false
        case .ready(let swatches):
            statusLabel.isHidden = true
            progress.stopAnimation(nil); progress.isHidden = true
            flow.chips = swatches.map(makeChip)
            flow.relayout(width: scroll.contentSize.width)
            countLabel.stringValue = String(format: L10n.string(.colorCountFormat), swatches.count)
            copyAllButton.isEnabled = !swatches.isEmpty
        }
    }

    func setTolerance(_ value: Double) { slider.doubleValue = value }

    func setMagnifierOn(_ on: Bool) {
        magnifierOn = on
        magnifierToggle.state = on ? .on : .off
        cursorBox.isHidden = !on
        refreshCursorBox()
    }

    func setHover(_ color: RGB8?) { liveColor = color; refreshCursorBox() }
    func setPicked(_ color: RGB8) { pickedColor = color; refreshCursorBox() }

    override func layout() {
        super.layout()
        flow.relayout(width: scroll.contentSize.width)
    }

    // MARK: - Private

    private func refreshCursorBox() {
        guard magnifierOn else { return }
        let color = liveColor ?? pickedColor
        cursorSwatch.layer?.backgroundColor = color.map {
            NSColor(srgbRed: CGFloat($0.r) / 255, green: CGFloat($0.g) / 255, blue: CGFloat($0.b) / 255, alpha: 1).cgColor
        } ?? NSColor.quaternaryLabelColor.cgColor
        cursorRows.forEach { $0.setColor(color) }
    }

    private func makeChip(_ swatch: ColorSwatch) -> ColorChipView {
        let chip = ColorChipView(swatch: swatch)
        chip.onHover = { [weak self, weak chip] inside in
            guard let self, let chip else { return }
            if inside { self.popover.chipEntered(chip, color: swatch.color) } else { self.popover.chipExited() }
        }
        chip.onClick = { [weak self] in
            ColorClipboard.copy(ColorFormat.hex(swatch.color))
            self?.popover.flashHexCopied()
        }
        return chip
    }

    private func setupViews() {
        popover.onCopy = { ColorClipboard.copy($0) }

        magnifierToggle.setButtonType(.pushOnPushOff)
        magnifierToggle.bezelStyle = .texturedRounded
        magnifierToggle.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: L10n.string(.colorMagnifier))
        magnifierToggle.toolTip = L10n.string(.colorMagnifier) + " (⌥)"
        magnifierToggle.refusesFirstResponder = true
        magnifierToggle.target = self
        magnifierToggle.action = #selector(magnifierToggled)

        let rangeLabel = NSTextField(labelWithString: L10n.string(.colorRange))
        rangeLabel.font = .systemFont(ofSize: 12)
        slider.minValue = AppSettings.colorToleranceRange.lowerBound
        slider.maxValue = AppSettings.colorToleranceRange.upperBound
        slider.isContinuous = true
        slider.refusesFirstResponder = true      // 슬라이더가 포커스를 가져가면 ⌥(flagsChanged)가 뷰어로 오지 않는다
        slider.target = self
        slider.action = #selector(sliderChanged)
        slider.widthAnchor.constraint(equalToConstant: 200).isActive = true
        countLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        countLabel.textColor = .secondaryLabelColor

        copyAllButton.title = L10n.string(.colorCopyAllHex)
        copyAllButton.bezelStyle = .rounded
        copyAllButton.controlSize = .small
        copyAllButton.refusesFirstResponder = true
        copyAllButton.target = self
        copyAllButton.action = #selector(copyAllTapped)

        let top = NSStackView(views: [magnifierToggle, rangeLabel, slider, countLabel, NSView(), copyAllButton])
        top.orientation = .horizontal
        top.spacing = 8

        // 커서 위치 색 칸
        let cursorTitle = NSTextField(labelWithString: L10n.string(.colorCursor))
        cursorTitle.font = .systemFont(ofSize: 11, weight: .semibold)
        cursorSwatch.wantsLayer = true
        cursorSwatch.layer?.cornerRadius = 4
        cursorSwatch.translatesAutoresizingMaskIntoConstraints = false
        cursorSwatch.heightAnchor.constraint(equalToConstant: 14).isActive = true
        cursorRows.forEach { row in row.onCopy = { ColorClipboard.copy($0) } }
        cursorBox.setViews([cursorTitle, cursorSwatch] + cursorRows, in: .top)
        cursorBox.orientation = .vertical
        cursorBox.alignment = .leading
        cursorBox.spacing = 3
        cursorBox.widthAnchor.constraint(equalToConstant: 190).isActive = true
        cursorBox.isHidden = true

        // 칩 영역
        scroll.documentView = flow
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.scrollerStyle = .overlay
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        progress.style = .spinning
        progress.controlSize = .small
        progress.isIndeterminate = true
        progress.isHidden = true
        let status = NSStackView(views: [progress, statusLabel])
        status.spacing = 8

        let body = NSStackView(views: [cursorBox, scroll])
        body.orientation = .horizontal
        body.alignment = .top
        body.spacing = 12

        for view in [top, body, status] as [NSView] { view.translatesAutoresizingMaskIntoConstraints = false; addSubview(view) }
        scroll.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            top.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            top.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            top.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            body.topAnchor.constraint(equalTo: top.bottomAnchor, constant: 8),
            body.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            body.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            body.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            scroll.heightAnchor.constraint(equalTo: body.heightAnchor),
            status.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
            status.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            heightAnchor.constraint(equalToConstant: Self.height),
        ])
    }

    @objc private func magnifierToggled() {
        let on = magnifierToggle.state == .on
        setMagnifierOn(on)
        onMagnifierToggled?(on)
    }
    @objc private func sliderChanged() { onToleranceChanged?(slider.doubleValue) }
    @objc private func copyAllTapped() { onCopyAllHex?() }
}
```

- [x] **Step 4: 빌드 확인**

Run: `make build`
Expected: 경고·에러 0. (`NSStackView.setViews` 등에서 에러가 나면 `cursorBox`는 `NSStackView(views:)`로 만들고 속성은 이어서 지정해도 된다 — 동작은 같다.)

- [x] **Step 5: 커밋**

```bash
git add Sources/viewer/ColorClipboard.swift Sources/viewer/ColorInfoPopover.swift Sources/viewer/ColorPalettePanel.swift
git commit -m "feat: ColorPalettePanel with chips, info popover and cursor color box"
```

---

### Task 10: ViewerViewController 연결 (1) — 버튼·패널 열고 닫기·레이아웃·활성 조건

**Files:**
- Modify: `Sources/viewer/ViewerViewController.swift`
- Modify: `Tests/UI/ViewerColorTests.swift`

**Interfaces:**
- Consumes: `ColorPalettePanel` (Task 9), `ImageDisplayView.isMagnifierActive/pixelSource` (Task 8), `AppSettings.shared.colorTolerance`.
- Produces: 하단 버튼 줄 `[카테고리][북마크][색상][편집][썸네일 토글]`. 색상 버튼은 `toolTip == "색상"`, 토글(`NSButton.state`). 패널은 `contentContainer` 안 이미지 아래.

규칙(설계 §3.1·§3.4): 활성 조건은 편집 버튼과 동일(동영상이면 숨김, 원본 로딩 끝나야 활성). 패널을 닫으면 돋보기도 꺼진다. 패널이 열린 채 이미지가 바뀌어도 패널과 돋보기 토글은 유지된다.

- [x] **Step 1: 실패하는 UI 테스트 작성**

`ViewerLoadingTests.swift`의 지연 서비스는 `private`이라 재사용할 수 없으므로, 이 파일에 즉시 응답하는 서비스를 둔다(이미지 크기로 이미지를 구분).

```swift
/// 파일 이름에 든 크기("w-100x50.png")로 이미지를 즉시 돌려주는 서비스.
private final class SizedImageService: ImageServiceProtocol {
    func loadImage(at url: URL) async -> Result<NSImage, ImageServiceError> {
        let parts = url.deletingPathExtension().lastPathComponent.split(separator: "-").last?.split(separator: "x").compactMap { Int($0) } ?? [20, 10]
        let cg = makeTestImage(width: parts[0], height: parts[1]) { x, y in RGB8(UInt8(x % 256), UInt8(y % 256), 50) }
        return .success(NSImage(cgImage: cg, size: NSSize(width: parts[0], height: parts[1])))
    }
    func generateThumbnail(at url: URL, size: CGSize) async -> Result<NSImage, ImageServiceError> { .failure(.thumbnailFailed(url)) }
    func exportImage(_ image: NSImage, to url: URL, format: ImageFormat, quality: Float) -> Result<Void, ImageServiceError> { .failure(.exportFailed("test")) }
}

@MainActor
private func makeViewer(files: [String], directory: URL) -> (viewer: ViewerViewController, window: NSWindow, urls: [URL]) {
    let viewer = ViewerViewController(imageService: SizedImageService())
    let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 820, height: 640), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentViewController = viewer
    window.setContentSize(NSSize(width: 820, height: 640))
    NSApp.setActivationPolicy(.accessory)
    window.orderFront(nil)
    let urls = files.map { directory.appendingPathComponent($0) }
    viewer.display(imageURL: urls[0], imageList: urls.compactMap { ImageFile(url: $0) })
    window.contentView?.layoutSubtreeIfNeeded()
    return (viewer, window, urls)
}
```

> `ImageFile(url:)`은 파일 존재/확장자를 본다. `directory`에 위 이름의 빈 파일을 미리 만든다(`FileManager.default.createFile`). 테스트 함수 맨 앞에서 `["a-200x100.png", "b-100x200.png"]`를 만든다.

`runViewerColorTests`에 추가:

```swift
    for name in ["a-200x100.png", "b-100x200.png"] {
        FileManager.default.createFile(atPath: directory.appendingPathComponent(name).path, contents: Data([0]))
    }

    runTest("색상 버튼: 편집 버튼 왼쪽, 로딩 중엔 비활성, 로딩이 끝나면 활성") {
        let (viewer, window, _) = makeViewer(files: ["a-200x100.png", "b-100x200.png"], directory: directory)
        defer { window.close() }
        let buttons = descendants(viewer.view, of: NSButton.self)
        guard let color = buttons.first(where: { $0.toolTip == L10n.string(.colorButton) }),
              let edit = buttons.first(where: { $0.title == "편집" }) else { return check(false, "버튼 존재") }
        check(color.frame.maxX <= edit.frame.minX, "색상 버튼은 편집 버튼의 왼쪽")
        let bookmark = buttons.first { $0.accessibilityLabel() == "북마크" }
        check(bookmark == nil || bookmark!.frame.maxX <= color.frame.minX, "북마크는 색상 버튼의 왼쪽")
        check(waitUntil { edit.isEnabled }, "원본 로딩 후 편집 활성")
        check(color.isEnabled, "색상 버튼도 같은 규칙으로 활성")
        viewer.showNext()
        check(!color.isEnabled && !edit.isEnabled, "다음 이미지 로딩 중에는 둘 다 비활성")
        check(waitUntil { color.isEnabled }, "로딩이 끝나면 다시 활성")
    }

    runTest("패널을 열면 이미지 영역이 줄고, 닫으면 돋보기도 꺼지며, 이미지가 바뀌어도 열린 상태는 유지된다") {
        let (viewer, window, _) = makeViewer(files: ["a-200x100.png", "b-100x200.png"], directory: directory)
        defer { window.close() }
        let color = descendants(viewer.view, of: NSButton.self).first { $0.toolTip == L10n.string(.colorButton) }!
        let display = descendants(viewer.view, of: ImageDisplayView.self).first!
        check(waitUntil { color.isEnabled }, "로딩")
        let panelFree = display.frame.height

        color.performClick(nil)
        window.contentView?.layoutSubtreeIfNeeded()
        let panel = descendants(viewer.view, of: ColorPalettePanel.self).first!
        check(!panel.isHidden, "패널 열림")
        check(display.frame.height < panelFree - 100, "패널 높이만큼 이미지 영역이 줄어듦(이미지를 가리지 않음)")
        check(display.frame.minY >= panel.frame.maxY - 0.5, "이미지는 패널 위쪽에 놓임")

        // 패널의 돋보기 토글을 켠다
        let toggle = descendants(panel, of: NSButton.self).first { $0.toolTip?.hasPrefix(L10n.string(.colorMagnifier)) == true }!
        toggle.performClick(nil)
        check(display.isMagnifierActive, "토글 ON → 돋보기 활성")

        viewer.showNext()
        check(waitUntil { color.isEnabled }, "다음 이미지 로딩")
        check(!panel.isHidden && display.isMagnifierActive, "이미지가 바뀌어도 패널·돋보기 유지")

        color.performClick(nil)
        window.contentView?.layoutSubtreeIfNeeded()
        check(panel.isHidden, "닫힘")
        checkEqual(display.frame.height, panelFree, "이미지 영역 복원")
        check(!display.isMagnifierActive, "패널을 닫으면 돋보기도 꺼짐")
        color.performClick(nil)
        check(!display.isMagnifierActive && toggle.state == .off, "다시 열면 꺼진 상태로 시작")
    }
```

- [x] **Step 2: 실패 확인** — `make test-ui` → 색상 버튼을 못 찾아 `check` 실패.

- [x] **Step 3: ViewerViewController 수정**

(a) 프로퍼티 — `// 하단 버튼` 블록에 추가하고, `private var slideshowTimer` 아래에 상태를 둔다.

```swift
    private let colorButton = NSButton(title: "", target: nil, action: nil)
    private let colorPanel = ColorPalettePanel()
    private var imageBottomToContainer: NSLayoutConstraint!
    private var imageBottomToPanel: NSLayoutConstraint!
    /// 사용자가 연 상태. 동영상으로 넘어가 잠시 숨겨져도 유지된다.
    private var isColorPanelOpen = false
    private var isMagnifierToggleOn = false
    private var isOptionHeld = false
    private var isOriginalReady = false
```

(b) `setupSplitView()` — `imageDisplayView.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),` 줄(현재 511행)을 배열에서 **지우고**, `NSLayoutConstraint.activate([...])` 뒤에 추가한다.

```swift
        imageBottomToContainer = imageDisplayView.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor)
        imageBottomToPanel = imageDisplayView.bottomAnchor.constraint(equalTo: colorPanel.topAnchor)
        imageBottomToContainer.isActive = true

        // 색상 패널: 이미지 아래, 하단 버튼 줄(약 40pt) 위. 열리면 이미지 영역이 그만큼 줄어든다.
        colorPanel.translatesAutoresizingMaskIntoConstraints = false
        colorPanel.isHidden = true
        contentContainer.addSubview(colorPanel)
        NSLayoutConstraint.activate([
            colorPanel.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            colorPanel.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            colorPanel.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor, constant: -40),
        ])
```

주의: `contentContainer.addSubview(colorPanel)`은 `setupEditButton()`이 버튼을 올리기 **전**(`loadView()`에서 `setupSplitView()` 다음에 `setupEditButton()`)이므로 버튼이 패널 위에 그려진다 — 그대로 둔다.

(c) `setupEditButton()` — 색상 버튼 설정과 체인 변경.

```swift
        colorButton.translatesAutoresizingMaskIntoConstraints = false
        colorButton.bezelStyle = .rounded
        colorButton.controlSize = .small
        colorButton.image = NSImage(systemSymbolName: "eyedropper", accessibilityDescription: L10n.string(.colorButton))
        colorButton.toolTip = L10n.string(.colorButton)
        colorButton.setButtonType(.pushOnPushOff)
        colorButton.refusesFirstResponder = true
        colorButton.isEnabled = false
        colorButton.target = self
        colorButton.action = #selector(colorButtonTapped)
        contentContainer.addSubview(colorButton)
```

`contentContainer.addSubview(bookmarkButton)` 아래에 위 블록을 두고, 제약 두 줄을 바꾼다.

```swift
            // 변경 전: bookmarkButton.trailingAnchor == editButton.leadingAnchor
            colorButton.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor, constant: -8),
            colorButton.trailingAnchor.constraint(equalTo: editButton.leadingAnchor, constant: -6),
            bookmarkButton.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor, constant: -8),
            bookmarkButton.trailingAnchor.constraint(equalTo: colorButton.leadingAnchor, constant: -6),
```

(d) `viewDidLoad()` 끝에 패널 콜백 연결.

```swift
        colorPanel.onMagnifierToggled = { [weak self] on in
            self?.isMagnifierToggleOn = on
            self?.updateMagnifierActive()
        }
```

(e) 활성 조건 — 편집 버튼을 만지는 네 군데(93행 `viewWillDisappear`, 302행 `showImage`, 320행 성공, `showVideo`)를 헬퍼로 바꾼다.

```swift
// viewWillDisappear() 의 `editButton.isEnabled = false` →
        closeColorPanel()
        isOptionHeld = false
        setOriginalReady(false)

// showVideo(_:) 의 `imageDisplayView.clearImage()` 다음 줄에 →
        setOriginalReady(false)

// showImage(_:) 의 `editButton.isEnabled = false` →
        setOriginalReady(false)

// showImage 성공 분기의 `self.editButton.isEnabled = true` →
                self.setOriginalReady(true)

// showImage 실패 분기 `self.imageDisplayView.displayError()` 다음 줄에 →
                self.colorPanel.setState(.empty)
```

(f) `switchContentView(toVideo:)`의 `editButton.isHidden = toVideo` 아래에 추가.

```swift
        colorButton.isHidden = toVideo
        applyColorPanelVisibility()
        updateMagnifierActive()
```

(g) `// MARK: - Bottom Buttons` 아래에 메서드들을 추가한다.

```swift
    // MARK: - Color Panel

    /// 원본 로딩이 끝났을 때만 색상 기능을 켠다(썸네일 미리보기로 뽑으면 저해상도 값이 나온다). 편집 버튼과 같은 규칙.
    private func setOriginalReady(_ ready: Bool) {
        isOriginalReady = ready
        editButton.isEnabled = ready
        colorButton.isEnabled = ready
        if !ready { imageDisplayView.pixelSource = nil }
        if isColorPanelOpen && !ready { colorPanel.setState(.loading) }
        updateMagnifierActive()
    }

    @objc private func colorButtonTapped() {
        if isColorPanelOpen { closeColorPanel() } else { openColorPanel() }
    }

    private func openColorPanel() {
        guard isOriginalReady, !isShowingVideo else { colorButton.state = .off; return }
        isColorPanelOpen = true
        colorButton.state = .on
        colorPanel.setTolerance(AppSettings.shared.colorTolerance)
        colorPanel.setMagnifierOn(false)             // 패널을 연다고 돋보기가 켜지지 않는다
        isMagnifierToggleOn = false
        colorPanel.setState(.loading)
        applyColorPanelVisibility()
        updateMagnifierActive()
    }

    private func closeColorPanel() {
        isColorPanelOpen = false
        isMagnifierToggleOn = false
        colorButton.state = .off
        colorPanel.setMagnifierOn(false)
        applyColorPanelVisibility()
        updateMagnifierActive()
    }

    private func applyColorPanelVisibility() {
        let visible = isColorPanelOpen && !isShowingVideo
        colorPanel.isHidden = !visible
        // 둘을 동시에 켜지 않도록 끄는 쪽을 먼저 처리한다.
        if visible { imageBottomToContainer.isActive = false; imageBottomToPanel.isActive = true }
        else { imageBottomToPanel.isActive = false; imageBottomToContainer.isActive = true }
    }

    /// 돋보기 = (패널이 열려 있고 토글이 켜짐) 또는 ⌥ 단독. 원본 로딩이 끝난 이미지에서만.
    private func updateMagnifierActive() {
        let toggled = isColorPanelOpen && isMagnifierToggleOn
        imageDisplayView.isMagnifierActive = isOriginalReady && !isShowingVideo && (toggled || isOptionHeld)
    }
```

- [x] **Step 4: 통과 확인**

Run: `make build && make test-ui`
Expected: 새 UI 테스트 2개 + 기존 테스트 통과. 기존 `ViewerLoadingTests`가 `editButton` 활성 시점을 검사하므로 그 테스트가 그대로 통과해야 한다(회귀 확인 지점).

- [x] **Step 5: 커밋**

```bash
git add Sources/viewer/ViewerViewController.swift Tests/UI/ViewerColorTests.swift
git commit -m "feat: color button, bottom drawer layout and enable rules in viewer"
```

---

### Task 11: ViewerViewController 연결 (2) — 추출 파이프라인·취소·슬라이더·HEX 전체 복사·돋보기 색 전달

**Files:**
- Modify: `Sources/viewer/ViewerViewController.swift`
- Modify: `Tests/UI/ViewerColorTests.swift`

**Interfaces:**
- Consumes: `ColorExtractionService`, `ColorJob`, `PixelSampler`, `ColorFormat.hexList` (Task 1~4).
- Produces: 테스트 주입점 `var histogramBuilder: (CGImage, ColorJob) -> ColorHistogram?` 와 읽기 전용 `private(set) var currentSwatches: [ColorSwatch]`.
- 흐름: 이미지 로딩 완료 후 패널이 열려 있거나 ⌥가 눌려 있으면 → 백그라운드에서 `PixelSampler.rasterize`(필요 시) + 히스토그램 → 메인에서 `loadGeneration`과 `ColorJob.isCancelled`로 낡은 결과 폐기 → `imageDisplayView.pixelSource` 설정 + `regroupColors()`. 슬라이더는 `colorHistogram`을 재사용해 묶기만 다시 돈다(최신 요청만 반영).

- [ ] **Step 1: 실패하는 UI 테스트 작성**

```swift
    runTest("이미지를 넘기면 이전 이미지의 늦은 추출 결과를 버린다") {
        let (viewer, window, _) = makeViewer(files: ["a-200x100.png", "b-100x200.png"], directory: directory)
        defer { window.close() }
        let gate = DispatchSemaphore(value: 0)
        let lock = NSLock(); var started: [Int] = []
        // 너비로 이미지를 구분: 200 = A, 100 = B. A의 계산은 게이트가 열릴 때까지 붙잡아 둔다.
        viewer.histogramBuilder = { image, job in
            lock.lock(); started.append(image.width); lock.unlock()
            if image.width == 200 { gate.wait() }
            let color = image.width == 200 ? RGB8(255, 0, 0) : RGB8(0, 0, 255)
            let lab = ColorFormat.lab(color)
            return ColorHistogram(bins: [.init(count: 10, topColor: color, topCount: 10, lab: lab)], totalPixels: 10)
        }
        let color = descendants(viewer.view, of: NSButton.self).first { $0.toolTip == L10n.string(.colorButton) }!
        check(waitUntil { color.isEnabled }, "A 로딩")
        color.performClick(nil)                                   // 패널 열기 → A 추출 시작(게이트에서 대기)
        check(waitUntil { lock.lock(); defer { lock.unlock() }; return started.contains(200) }, "A 계산 시작")

        viewer.showNext()                                         // B로 전환: A 작업 취소
        check(waitUntil(timeout: 3) { color.isEnabled && viewer.currentSwatches.map { $0.color } == [RGB8(0, 0, 255)] }, "B 결과가 표시됨")
        gate.signal()                                             // 이제서야 A 계산이 끝남
        _ = waitUntil(timeout: 0.5) { false }
        checkEqual(viewer.currentSwatches.map { $0.color }, [RGB8(0, 0, 255)], "늦게 끝난 A 결과가 B를 덮지 않음")
    }

    runTest("슬라이더는 히스토그램을 다시 만들지 않고 묶기만 다시 돈다 / HEX 전체 복사") {
        let (viewer, window, _) = makeViewer(files: ["a-200x100.png"], directory: directory)
        defer { window.close() }
        var builds = 0
        viewer.histogramBuilder = { _, _ in
            builds += 1
            let reds = [RGB8(255, 0, 0), RGB8(225, 0, 0)], blue = RGB8(0, 0, 255)
            let bins = ([reds[0], reds[1], blue]).enumerated().map { i, c in
                ColorHistogram.Bin(count: 500 - i * 100, topColor: c, topCount: 500 - i * 100, lab: ColorFormat.lab(c)) }
            return ColorHistogram(bins: bins, totalPixels: 1200)
        }
        let color = descendants(viewer.view, of: NSButton.self).first { $0.toolTip == L10n.string(.colorButton) }!
        check(waitUntil { color.isEnabled }, "로딩")
        color.performClick(nil)
        check(waitUntil { viewer.currentSwatches.count == 3 }, "처음엔 3칩 (기본 허용 범위): \(viewer.currentSwatches.count)")

        let panel = descendants(viewer.view, of: ColorPalettePanel.self).first!
        let slider = descendants(panel, of: NSSlider.self).first!
        slider.doubleValue = AppSettings.colorToleranceRange.upperBound
        slider.performClick(nil)
        check(waitUntil { viewer.currentSwatches.count < 3 }, "허용 범위를 키우면 칩이 줄어듦")
        checkEqual(builds, 1, "히스토그램은 이미지당 한 번만")
        checkEqual(AppSettings.shared.colorTolerance, AppSettings.colorToleranceRange.upperBound, "슬라이더 값이 저장됨")
        AppSettings.shared.colorTolerance = AppSettings.defaultColorTolerance      // 전역 설정 원복

        let copyAll = descendants(panel, of: NSButton.self).first { $0.title == L10n.string(.colorCopyAllHex) }!
        copyAll.performClick(nil)
        checkEqual(NSPasteboard.general.string(forType: .string), ColorFormat.hexList(viewer.currentSwatches), "HEX 전체 복사 = 비율 순 공백 구분")
    }
```

(첫 테스트의 `viewer.histogramBuilder`는 백그라운드 큐에서 호출되므로 클로저 안에서 UI를 만지지 않는다. `builds`는 한 번만 증가하므로 데이터 경쟁이 사실상 없지만, 불안하면 `lock`으로 감싼다.)

- [ ] **Step 2: 실패 확인** — `make test-ui` → `has no member 'histogramBuilder'`.

- [ ] **Step 3: 구현**

(a) 프로퍼티(Task 10에서 만든 블록 아래).

```swift
    /// 테스트에서 느린 계산을 흉내 낼 수 있도록 주입 가능. 백그라운드 큐에서 호출된다.
    var histogramBuilder: (CGImage, ColorJob) -> ColorHistogram? = { image, job in
        ColorExtractionService.buildHistogram(from: image, longSide: ColorExtractionService.downscaleLongSide,
                                              isCancelled: { job.isCancelled })
    }
    private(set) var currentSwatches: [ColorSwatch] = []
    private var colorHistogram: ColorHistogram?
    private var colorJob: ColorJob?
    private var regroupToken = 0
```

(b) `cancelImageLoading()` 안에 추가(기존 `loadGeneration += 1` 아래). 이미지가 바뀌는 모든 경로(`showImage`/`showVideo`/`reloadCurrentImage`)가 이 함수를 지난다.

```swift
        cancelColorWork()
```

```swift
    private func cancelColorWork() {
        colorJob?.cancel()
        colorJob = nil
        colorHistogram = nil
        regroupToken += 1          // 진행 중인 묶기 결과도 버린다
        currentSwatches = []
        imageDisplayView.pixelSource = nil
    }
```

(c) `setOriginalReady(_:)` 끝에 `if ready { ensureColorData() }`를 추가하고, `openColorPanel()`의 마지막(`updateMagnifierActive()` 다음)에 `ensureColorData()`를 추가한다. Task 12에서 ⌥ 경로도 같은 함수를 부른다.

(d) 추출·묶기 메서드.

```swift
    /// 패널이 열렸거나 ⌥가 눌려 있고 원본이 준비됐을 때 필요한 데이터(원본 픽셀 소스, 히스토그램)를 만든다.
    private func ensureColorData() {
        guard isOriginalReady, !isShowingVideo, let image = imageDisplayView.currentImage,
              isColorPanelOpen || isOptionHeld else { return }
        let wantsHistogram = isColorPanelOpen
        let hasPixels = imageDisplayView.pixelSource != nil
        if hasPixels && (!wantsHistogram || colorHistogram != nil) { return }

        colorJob?.cancel()
        let job = ColorJob()
        colorJob = job
        let generation = loadGeneration
        let existing = imageDisplayView.pixelSource
        let build = histogramBuilder
        let box = UncheckedBox(image)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let cg = existing ?? PixelSampler.rasterize(box.value)
            let histogram: ColorHistogram? = (wantsHistogram && !job.isCancelled) ? cg.flatMap { build($0, job) } : nil
            DispatchQueue.main.async {
                // 이미지가 바뀌었거나(loadGeneration) 작업이 취소됐으면 결과를 버린다.
                guard let self, !job.isCancelled, self.loadGeneration == generation else { return }
                self.colorJob = nil
                self.imageDisplayView.pixelSource = cg
                if wantsHistogram {
                    self.colorHistogram = histogram
                    if histogram == nil { self.colorPanel.setState(.empty) } else { self.regroupColors() }
                }
            }
        }
    }

    /// 히스토그램을 다시 만들지 않고 묶기만 다시 돈다. 가장 최근 요청만 반영한다.
    private func regroupColors() {
        guard isColorPanelOpen, let histogram = colorHistogram else { return }
        regroupToken += 1
        let token = regroupToken
        let generation = loadGeneration
        let tolerance = AppSettings.shared.colorTolerance
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            let swatches = ColorExtractionService.group(histogram, tolerance: tolerance)
            DispatchQueue.main.async {
                guard let self, self.regroupToken == token, self.loadGeneration == generation else { return }
                self.currentSwatches = swatches
                self.colorPanel.setState(swatches.isEmpty ? .empty : .ready(swatches))
            }
        }
    }
```

`UncheckedBox`는 파일 맨 아래(`Array` 확장 위)에 둔다. NSImage를 백그라운드로 넘기기 위한 것이다.

```swift
/// NSImage처럼 Sendable이 아닌 값을 백그라운드 큐로 넘기기 위한 상자. 읽기만 한다.
private final class UncheckedBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}
```

(e) `viewDidLoad()`에 콜백을 더 연결한다.

```swift
        colorPanel.onToleranceChanged = { [weak self] value in
            AppSettings.shared.colorTolerance = value
            self?.regroupColors()
        }
        colorPanel.onCopyAllHex = { [weak self] in
            guard let self else { return }
            ColorClipboard.copy(ColorFormat.hexList(self.currentSwatches))
        }
        imageDisplayView.onColorHover = { [weak self] color in self?.colorPanel.setHover(color) }
        imageDisplayView.onColorPicked = { [weak self] color in
            ColorClipboard.copy(ColorFormat.hex(color))     // 클릭 = HEX 즉시 복사
            self?.colorPanel.setPicked(color)               // 패널의 "커서 위치 색"에 남긴다
        }
```

(f) `regroupColors()` 최초 호출 보장: `ensureColorData()`의 `wantsHistogram` 분기가 끝나면 `regroupColors()`를 부르므로 패널을 연 직후에는 `.loading` → 결과 순서로 표시된다. 패널이 열려 있고 이미지가 바뀌면 `showImage`의 `setOriginalReady(false)`가 `.loading`으로 비우고, 로딩이 끝나면 `setOriginalReady(true)` → `ensureColorData()`가 다시 추출한다.

- [ ] **Step 4: 통과 확인**

Run: `make build && make test-ui`
Expected: 새 UI 테스트 2개 통과. `이전 이미지의 늦은 추출 결과` 테스트가 불안정하면(타이밍) `waitUntil` 시간을 늘리되, **`cancelImageLoading()`에서 `cancelColorWork()`를 부르는지**부터 확인한다 — 이것이 핵심이다.

- [ ] **Step 5: 커밋**

```bash
git add Sources/viewer/ViewerViewController.swift Tests/UI/ViewerColorTests.swift
git commit -m "feat: background color extraction with cancel, regroup on slider and HEX copy-all"
```

---

### Task 12: ViewerViewController 연결 (3) — ⌥ 임시 돋보기 (`flagsChanged`)

**Files:**
- Modify: `Sources/viewer/ViewerViewController.swift`
- Modify: `Tests/UI/ViewerColorTests.swift`

**Interfaces:**
- Consumes: `OptionKeyGate` (Task 5), `ensureColorData()`/`updateMagnifierActive()` (Task 10·11).
- 규칙(설계 §3.4): ⌥ **단독**일 때만 임시로 켠다. 패널이 닫혀 있어도 동작(확대경+HEX 한 줄, 클릭 시 HEX 복사). 원본 로딩이 끝난 이미지에서만. 토글이 이미 켜져 있으면 ⌥는 변화 없음(켜기만 하고 끄지 않음 — `updateMagnifierActive`의 `toggled || isOptionHeld`가 보장). 창이 비활성화되면 ⌥ 상태를 풀어 "눌린 채 남는" 일을 막는다.

- [ ] **Step 1: 실패하는 UI 테스트 작성**

```swift
private func flagsEvent(_ flags: NSEvent.ModifierFlags, window: NSWindow) -> NSEvent {
    NSEvent.keyEvent(with: .flagsChanged, location: .zero, modifierFlags: flags, timestamp: 0,
                     windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "",
                     isARepeat: false, keyCode: 58)!
}

    runTest("⌥ 단독만 임시 돋보기를 켜고, 조합 키·창 비활성화·로딩 중에는 켜지 않는다") {
        let (viewer, window, _) = makeViewer(files: ["a-200x100.png", "b-100x200.png"], directory: directory)
        defer { window.close() }
        let display = descendants(viewer.view, of: ImageDisplayView.self).first!
        let color = descendants(viewer.view, of: NSButton.self).first { $0.toolTip == L10n.string(.colorButton) }!

        viewer.showNext()
        viewer.flagsChanged(with: flagsEvent([.option], window: window))
        check(!display.isMagnifierActive, "원본 로딩 중에는 ⌥를 눌러도 켜지지 않음")
        viewer.flagsChanged(with: flagsEvent([], window: window))
        check(waitUntil { color.isEnabled }, "로딩 완료")

        viewer.flagsChanged(with: flagsEvent([.option], window: window))
        check(display.isMagnifierActive, "⌥ 단독 + 패널 닫힘 → 임시 돋보기 켜짐")
        check(waitUntil { display.pixelSource != nil }, "원본 픽셀 소스가 준비됨(지연 래스터화)")
        viewer.flagsChanged(with: flagsEvent([], window: window))
        check(!display.isMagnifierActive, "⌥를 떼면 꺼짐")

        viewer.flagsChanged(with: flagsEvent([.command, .option], window: window))
        check(!display.isMagnifierActive, "⌘⌥ 조합에서는 켜지지 않음")
        viewer.flagsChanged(with: flagsEvent([.option], window: window))
        check(display.isMagnifierActive, "⌘를 떼고 ⌥ 단독이 되면 켜짐(설계: ⌥ 단독일 때)")

        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        check(!display.isMagnifierActive, "창이 비활성화되면 ⌥ 상태 해제 — 해제 이벤트를 못 받아도 눌린 채 남지 않음")

        // 토글이 이미 켜져 있으면 ⌥는 변화 없음 (끄지 않는다)
        color.performClick(nil)
        let panel = descendants(viewer.view, of: ColorPalettePanel.self).first!
        descendants(panel, of: NSButton.self).first { $0.toolTip?.hasPrefix(L10n.string(.colorMagnifier)) == true }!.performClick(nil)
        check(display.isMagnifierActive, "토글 ON")
        viewer.flagsChanged(with: flagsEvent([.option], window: window))
        viewer.flagsChanged(with: flagsEvent([], window: window))
        check(display.isMagnifierActive, "⌥를 눌렀다 떼도 토글로 켠 돋보기는 유지")
    }
```

- [ ] **Step 2: 실패 확인** — `make test-ui` → 새 테스트 실패(`flagsChanged`를 오버라이드하지 않아 `isMagnifierActive`가 안 켜짐).

- [ ] **Step 3: 구현**

(a) 프로퍼티와 창 비활성화 관찰.

```swift
    private var windowResignObserver: NSObjectProtocol?
```

`viewDidAppear()` 오버라이드를 추가하고(없으면 새로), `viewWillDisappear()`에서 해제한다.

```swift
    override func viewDidAppear() {
        super.viewDidAppear()
        windowResignObserver.map(NotificationCenter.default.removeObserver)
        // ⌥를 누른 채 ⌘Tab 등으로 창을 벗어나면 flagsChanged 해제를 못 받는다. 비활성화 시 직접 푼다.
        windowResignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: view.window, queue: .main
        ) { [weak self] _ in
            guard let self, self.isOptionHeld else { return }
            self.isOptionHeld = false
            self.updateMagnifierActive()
        }
    }
```

`viewWillDisappear()`(Task 10에서 `isOptionHeld = false`를 이미 넣었다)에 `windowResignObserver.map(NotificationCenter.default.removeObserver); windowResignObserver = nil`을 추가하고, `deinit`에서도 같은 해제를 한다.

> 테스트가 `viewDidAppear`를 거치도록 `makeViewer`가 `window.orderFront(nil)`로 창을 띄운다. 오프스크린 창에서 `viewDidAppear`가 호출되지 않으면 테스트 쪽에서 `viewer.viewDidAppear()`를 한 번 직접 호출한다.

(b) `keyDown` 위에 `flagsChanged`를 추가한다. 뷰어는 `display()`에서 첫 응답자가 되고, 패널의 슬라이더·버튼은 `refusesFirstResponder`라 포커스를 가져가지 않으므로 ⌥ 이벤트가 여기로 온다.

```swift
    // MARK: - Option Key (temporary magnifier)

    override func flagsChanged(with event: NSEvent) {
        let held = OptionKeyGate.isOptionAlone(event.modifierFlags)    // ⌘⌥ 같은 조합에서는 false
        if held != isOptionHeld {
            isOptionHeld = held
            if held { ensureColorData() }        // 원본 픽셀 소스를 지연 준비(패널이 닫혀 있어도)
            updateMagnifierActive()
        }
        super.flagsChanged(with: event)
    }
```

`setOriginalReady(_:)`는 이미 `updateMagnifierActive()`와 `ensureColorData()`를 부르므로, ⌥를 누른 채 이미지가 바뀌어도 로딩이 끝나면 자동으로 이어진다.

- [ ] **Step 4: 통과 확인**

Run: `make build && make test && make test-ui`
Expected: 모두 통과. `make test`는 순수 로직 35개, `make test-ui`는 기존 + 색상 UI 테스트 전부.

- [ ] **Step 5: 커밋**

```bash
git add Sources/viewer/ViewerViewController.swift Tests/UI/ViewerColorTests.swift
git commit -m "feat: temporary magnifier while holding option alone"
```

---

### Task 13: 마무리 — 수동 검증, devlog, 현황판

**Files:**
- Modify: `docs/devlog/2026-11-02-color-picker.md`
- Modify: `README.md` (기능 목록이 있으면 한 줄)
- Modify: `~/Documents/project/source/skills/global/projects.md` jena-image 줄 (현 단계·갱신일)

- [ ] **Step 1: 전체 자동 검증**

```bash
make build && make test && make test-ui
```
Expected: 경고·에러 0, `all tests passed`, `all category UI tests passed`.

- [ ] **Step 2: 설계 §7 수동 확인 실행** (`make run` 후. 전부 직접 해 보고 항목별 결과를 기록한다)

1. **큰 이미지에서 추출 시간**: 24MP 이상 사진을 열고 색상 버튼 → 칩이 뜰 때까지 1초 안팎인가. 첫 이미지와 두 번째 이미지 모두.
2. **슬라이더 반응**: 드래그하는 동안 칩 수가 끊김 없이 따라오는가. 값이 앱 재실행 후에도 유지되는가.
3. **⌥ 단독**: 패널을 닫은 채 ⌥ 누르는 동안만 확대경+HEX 한 줄, 클릭 시 HEX 복사(`⌘V`로 붙여 확인), 뗴면 사라짐.
4. **⌥ 조합 키**: ⌘⌥, ⇧⌥, ⌃⌥에서 켜지지 않음. ⌥를 누른 채 ⌘Tab으로 앱을 벗어났다 돌아와도 돋보기가 눌린 채 남지 않음.
5. **연속 클릭 시 뷰어가 닫히지 않음**: 돋보기를 켜고 같은 자리를 5번 빠르게 클릭 → 닫히지 않고 매번 복사. 돋보기를 끄고 더블클릭 → 기존처럼 닫힘. ESC·색상 버튼으로는 닫힘.
6. **이미지 전환 중 패널 상태**: 패널을 연 채 ←/→로 넘김 → 패널 유지, 칩 영역은 로딩 표시 후 새 칩. 토글 ON이었으면 ON 유지. 큰 이미지에서 패널을 연 직후 바로 다음 이미지로 넘겨도 이전 이미지의 칩이 나타나지 않음.
7. **좌표 정확도**: 2×2처럼 색이 구분되는 테스트 이미지(또는 체커 패턴)로 확대 200%·좌우 반전·상하 반전·회전 90/180/270을 섞어 가며, 확대경 가운데 칸 색이 **화면에서 보이는 그 픽셀 색**과 일치.
8. **정보창**: 칩에 마우스 → 칩 위쪽에 정보창. 칩에서 정보창으로 천천히/빠르게 이동해도 닫히지 않음. 복사 버튼 3종, 칩 클릭 시 HEX 복사 + HEX 줄 "복사됨" 약 1초. 옆 칩으로 바로 옮기면 정보창이 따라옴. 정보창이 옆 칩을 가리지 않음.
9. **레이아웃**: 패널이 이미지를 가리지 않고 이미지 영역이 줄어듦. 하단 버튼 줄(카테고리·북마크·색상·편집·썸네일 토글)이 패널과 겹치지 않음. 칩이 많을 때 줄바꿈/스크롤. 오른쪽 썸네일 목록을 접고 펼쳐도 정상.
10. **동영상/비활성**: 동영상에서는 색상 버튼이 숨고 패널도 가려짐(다음 이미지에서 복귀). 로딩 중에는 색상 버튼 비활성.
11. **패널·버튼 위에서 확대경 숨김**: 커서가 패널이나 하단 버튼 위에 있을 때 확대경이 이미지 위에 남지 않음. 이미지 밖 여백에서도 숨김, 십자 커서는 이미지 위에서만.
12. **패닝**: 돋보기 중 3pt 넘게 드래그하면 패닝(확대경 숨김), 끝나면 복귀. 3pt 이내 클릭은 복사.
13. **비교 화면**: 비교 창에서 돋보기·색상 기능이 전혀 나타나지 않고 더블클릭 닫기 등 기존 동작 그대로.
14. **투명 PNG·흑백 이미지**: 투명 영역이 검정 칩으로 나오지 않음.

- [ ] **Step 3: devlog 마무리**

`docs/devlog/2026-11-02-color-picker.md`의 측정 섹션 아래에 이어 쓴다.

```markdown
## 변경 사항

- 추출: `ColorExtractionService`(축소 → 5bit 히스토그램 → ΔE 묶기), `ColorFormat`, `ColorSwatch`.
  히스토그램은 이미지당 한 번, 슬라이더는 묶기만 다시. 묶음 수 상한(1/minRatio)으로 노이즈 큰 사진에서도 한 틱이 가볍다.
- 좌표: `PixelMapping`(그리는 변환과 읽는 변환을 공유, 실제 렌더링을 정답으로 16조합 검증), `PixelSampler`(원본 CGImage에서 sRGB로 읽음).
- UI: `MagnifierOverlayView`, `ImageDisplayView` 돋보기 모드(누른 시점 상태로 제스처 판단, 돋보기 중에만 더블클릭 닫기 금지),
  `ColorPalettePanel`(하단 서랍), 칩 정보창은 `NSPopover` + `HoverGrace`.
- 연결: 색상 버튼(편집 왼쪽, 같은 활성 규칙), ⌥ 단독(`flagsChanged`), 창 비활성화 시 ⌥ 해제, 이미지 전환 시 `loadGeneration`+`ColorJob`으로 취소.
- 설정: `AppSettings.colorTolerance`(앱 전체 마지막 값).

## 검증

- `make build` 경고·에러 0, `make test` <N>개, `make test-ui` 통과.
- 수동 14항목: <항목별 결과>

## 트레이드오프·메모

- CMYK는 ICC 없는 단순 변환(참고용). 포토샵 값과 다를 수 있다.
- 투명 픽셀(알파 128 미만)은 추출에서 제외, 비율 분모에서도 뺀다. 설계 문서는 침묵하던 부분.
- 최소 비율 필터 때문에 칩 비율의 합은 100% 이하일 수 있다(필터 끄면 정확히 100%).
- 동영상으로 넘어가면 패널은 잠시 숨기고 다음 이미지에서 복귀한다(설계는 동영상 중 패널 상태를 정하지 않았다).
- 이후: 팔레트 파일 내보내기(.ase), ICC CMYK, AI 컬러 시스템(`[ColorSwatch]` 입력).
```

- [ ] **Step 4: README·현황판**

`README.md`에 기능 목록이 있으면 "색상 추출·돋보기(⌥)" 한 줄을 추가한다. `projects.md`의 jena-image 줄 '현 단계'를 "색상 추출·돋보기 구현 완료 · 다음: 릴리스 또는 팔레트 내보내기", 갱신일을 작업일로 바꾼다.

- [ ] **Step 5: 커밋** (`Co-Authored-By` 줄 없이)

```bash
git add docs README.md
git commit -m "docs: color picker devlog and manual verification results"
```
