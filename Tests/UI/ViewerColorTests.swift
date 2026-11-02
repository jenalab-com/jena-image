import AppKit

@MainActor
func runViewerColorTests(directory: URL) {
    runTest("AppSettings.colorTolerance: 기본값·저장·범위 고정") {
        let suiteName = "jena-color-settings-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        checkEqual(settings.colorTolerance, 12, "저장값 없으면 측정 기본값 12")
        checkEqual(AppSettings.colorToleranceRange, 8...20, "Task 3 실측 범위")
        settings.colorTolerance = 13.5
        checkEqual(AppSettings(defaults: UserDefaults(suiteName: suiteName)!).colorTolerance, 13.5, "소수 값도 새 설정 인스턴스에서 복원")
        settings.colorTolerance = 20
        checkEqual(AppSettings(defaults: defaults).colorTolerance, 20, "다른 인스턴스(재실행)에서도 유지")
        settings.colorTolerance = 999
        checkEqual(settings.colorTolerance, AppSettings.colorToleranceRange.upperBound, "상한으로 고정")
        settings.colorTolerance = -5
        checkEqual(settings.colorTolerance, AppSettings.colorToleranceRange.lowerBound, "하한으로 고정")
    }

    runTest("AppSettings.colorTolerance: 잘못된 저장값과 비정상 숫자를 복구한다") {
        let suiteName = "jena-color-settings-invalid-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        for (raw, expected) in [(999.0, 20.0), (-5.0, 8.0)] {
            defaults.set(raw, forKey: "colorTolerance")
            checkEqual(settings.colorTolerance, expected, "외부 저장값도 읽을 때 범위 제한")
        }
        defaults.set("invalid", forKey: "colorTolerance")
        checkEqual(settings.colorTolerance, 12, "문자열 오염은 기본값")
        for value in [Double.nan, .infinity, -.infinity] {
            defaults.set(value, forKey: "colorTolerance")
            checkEqual(settings.colorTolerance, 12, "비정상 저장값 복구")
            settings.colorTolerance = value
            checkEqual(defaults.double(forKey: "colorTolerance"), 12, "비정상 숫자를 저장하지 않음")
        }
    }

    runTest("색상 기능 문자열이 모든 언어에서 비어 있지 않다") {
        let keys: [L10nKey] = [.colorButton, .colorMagnifier, .colorRange, .colorCountFormat, .colorCopyAllHex,
                               .colorCopied, .colorCursor, .colorExtracting, .colorNoColors, .colorCopyValue]
        let saved = L10n.language
        let savedPreference = UserDefaults.standard.object(forKey: "appLanguage")
        defer {
            L10n.language = saved
            if let savedPreference { UserDefaults.standard.set(savedPreference, forKey: "appLanguage") }
            else { UserDefaults.standard.removeObject(forKey: "appLanguage") }
        }
        L10n.language = .korean
        let korean = Dictionary(uniqueKeysWithValues: keys.map { ($0, L10n.string($0)) })
        let counts: [Language: String] = [.korean: "14색", .english: "14 colors", .japanese: "14色", .chinese: "14 种颜色"]
        for language in Language.allCases {
            L10n.language = language
            for key in keys {
                check(L10n.string(key) != key.rawValue && !L10n.string(key).isEmpty, "\(language) \(key)")
                if language != .korean { check(L10n.string(key) != korean[key], "\(language) \(key): 한국어 폴백으로 누락을 숨기지 않음") }
            }
            checkEqual(String(format: L10n.string(.colorCountFormat), 14), counts[language]!, "언어별 개수 표기")
        }
        L10n.language = .korean
        checkEqual(String(format: L10n.string(.colorCountFormat), 14), "14색", "개수 표기")
    }
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


    runTest("돋보기: 놓는 위치도 판정하고 이미지 교체 중 제스처는 취소한다") {
        let (window, display, center) = makeDisplay()
        defer { window.close() }
        var picks = 0
        display.onColorPicked = { _ in picks += 1 }
        display.isMagnifierActive = true
        display.mouseDown(with: mouseEvent(.leftMouseDown, at: center, window: window))
        display.mouseUp(with: mouseEvent(.leftMouseUp, at: NSPoint(x: center.x + 6, y: center.y), window: window))
        checkEqual(picks, 0, "드래그 이벤트가 생략돼도 6pt 이동이면 복사하지 않음")
        display.mouseDown(with: mouseEvent(.leftMouseDown, at: center, window: window))
        let replacement = makeTestImage(width: 40, height: 20) { _, _ in RGB8(255, 0, 0) }
        display.display(NSImage(cgImage: replacement, size: NSSize(width: 40, height: 20)))
        display.pixelSource = replacement
        display.mouseUp(with: mouseEvent(.leftMouseUp, at: center, window: window))
        checkEqual(picks, 0, "누른 이미지와 다른 이미지의 색을 선택하지 않음")
    }

    runTest("돋보기: 이미지 밖·버튼 위·패닝·로딩·끄기에서 숨긴다") {
        let (window, display, center) = makeDisplay()
        defer { window.close() }
        var hovered: RGB8?
        display.onColorHover = { hovered = $0 }
        display.isMagnifierActive = true
        display.mouseMoved(with: mouseEvent(.mouseMoved, at: center, window: window))
        guard let overlay = descendants(display, of: MagnifierOverlayView.self).first else {
            check(false, "커서 이동으로 확대경 생성"); return
        }
        check(!overlay.isHidden && hovered != nil, "이미지 위 확대경·색 표시")
        check(overlay.hitTest(.zero) == nil, "확대경이 마우스 이벤트를 가로채지 않음")
        display.mouseMoved(with: mouseEvent(.mouseMoved, at: NSPoint(x: 2, y: 2), window: window))
        check(overlay.isHidden && hovered == nil, "이미지 밖 여백에서 숨김")
        check(NSCursor.current != NSCursor.crosshair, "여백에 십자 커서가 남지 않음")
        let button = NSButton(frame: NSRect(x: center.x - 10, y: center.y - 10, width: 20, height: 20))
        display.addSubview(button)
        display.mouseMoved(with: mouseEvent(.mouseMoved, at: center, window: window))
        check(overlay.isHidden && hovered == nil, "이미지 위 버튼에서는 숨김")
        button.removeFromSuperview()
        display.mouseMoved(with: mouseEvent(.mouseMoved, at: center, window: window))
        display.mouseDown(with: mouseEvent(.leftMouseDown, at: center, window: window))
        let dragged = NSPoint(x: center.x + 6, y: center.y)
        display.mouseDragged(with: mouseEvent(.leftMouseDragged, at: dragged, window: window))
        check(overlay.isHidden, "패닝 중 숨김")
        display.mouseUp(with: mouseEvent(.leftMouseUp, at: dragged, window: window))
        check(!overlay.isHidden, "패닝 종료 후 복귀")
        display.isMagnifierActive = false
        check(overlay.isHidden && hovered == nil, "끄면 즉시 숨김")
        display.isMagnifierActive = true
        display.mouseMoved(with: mouseEvent(.mouseMoved, at: center, window: window))
        display.displayLoading()
        check(overlay.isHidden && display.pixelSource == nil, "새 이미지 로딩 시 이전 원본과 확대경 제거")
    }

    runTest("돋보기: 200% 배율에서 16가지 반전·회전 모두 같은 원본 색을 선택한다") {
        let (window, display, _) = makeDisplay()
        defer { window.close() }
        display.applyTransform(magnification: 2, centerInImage: CGPoint(x: 0.5, y: 0.5))
        display.isMagnifierActive = true
        var picked: RGB8?
        display.onColorPicked = { picked = $0 }
        for horizontal in [false, true] {
            for vertical in [false, true] {
                for angle in [0, 90, 180, 270] {
                    display.resetFlip()
                    if horizontal { display.flipHorizontal() }
                    if vertical { display.flipVertical() }
                    for _ in 0..<(angle / 90) { display.rotateRight() }
                    window.contentView?.layoutSubtreeIfNeeded()
                    let imageView = descendants(display, of: NSImageView.self).first { $0.image != nil }!
                    let transform = PixelMapping.displayTransform(sourceSize: NSSize(width: 40, height: 20),
                                                                  flipH: horizontal, flipV: vertical, rotation: angle).transform
                    let point = imageView.convert(transform.transform(NSPoint(x: 7.5, y: 13.5)), to: nil)
                    checkEqual(display.originalPixel(atWindowPoint: point), .init(x: 7, y: 6), "회전·반전 후 같은 픽셀")
                    picked = nil
                    display.mouseDown(with: mouseEvent(.leftMouseDown, at: point, window: window))
                    display.mouseUp(with: mouseEvent(.leftMouseUp, at: point, window: window))
                    checkEqual(picked, RGB8(42, 72, 90), "원본 값 그대로 선택")
                }
            }
        }
    }

    runTest("실제 ComparePaneView에는 돋보기 소스와 오버레이가 없다") {
        let pane = ComparePaneView(file: ImageFile(url: directory.appendingPathComponent("b.png"))!, imageService: ImageService())
        pane.imageDisplayView.display(NSImage(cgImage: makeTestImage(width: 4, height: 4) { _, _ in RGB8(255, 0, 0) }, size: NSSize(width: 4, height: 4)))
        check(!pane.imageDisplayView.isMagnifierActive, "비교 칸은 비활성")
        check(pane.imageDisplayView.pixelSource == nil, "비교 칸에 픽셀 소스를 준비하지 않음")
        check(descendants(pane, of: MagnifierOverlayView.self).isEmpty, "비교 칸에 오버레이 없음")
    }

    runTest("확대경 렌더링: 중심·주변 픽셀과 회전 방향, HEX 라벨") {
        let overlay = MagnifierOverlayView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 400, height: 300),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = overlay
        window.orderFront(nil)
        defer { window.close() }
        let cursor = CGPoint(x: 120, y: 220)
        let grid: [RGB8?] = (0..<121).map { (index: Int) -> RGB8? in
            let red = UInt8((index % 11) * 20)
            let green = UInt8((index / 11) * 20)
            return RGB8(red, green, 90)
        }
        let frame = MagnifierPlacement.frame(cursor: cursor, size: MagnifierOverlayView.loupeSize, bounds: overlay.bounds)
        for angle in [0, 90, 180, 270] {
            overlay.show(at: cursor, grid: grid, rotation: angle)
            overlay.displayIfNeeded()
            guard let bitmap = overlay.bitmapImageRepForCachingDisplay(in: overlay.bounds) else {
                check(false, "확대경 렌더 버퍼"); return
            }
            overlay.cacheDisplay(in: overlay.bounds, to: bitmap)
            guard let cg = bitmap.cgImage else { check(false, "렌더 결과"); return }
            let scale = CGFloat(bitmap.pixelsWide) / overlay.bounds.width
            let center = CGPoint(x: frame.midX, y: frame.maxY - frame.width / 2)
            let overlayHeight = overlay.bounds.height
            func sample(_ point: CGPoint) -> RGB8? {
                PixelSampler.color(in: cg, x: Int(point.x * scale), y: Int((overlayHeight - point.y) * scale))
            }
            func checkRendered(_ actual: RGB8?, _ expected: RGB8?, _ message: String) {
                guard let actual, let expected else { check(false, message + ": 렌더 색 없음"); return }
                // 실제 창의 화면 색 공간 → sRGB 재변환에서 생기는 8bit 반올림만 허용한다.
                check(abs(Int(actual.r) - Int(expected.r)) <= 1 && abs(Int(actual.g) - Int(expected.g)) <= 1
                      && abs(Int(actual.b) - Int(expected.b)) <= 1, message + ": \(actual) / \(expected)")
            }
            checkRendered(sample(center), RGB8(100, 100, 90), "가운데 선택 픽셀 유지")
            var whiteTextPixels = 0
            for y in stride(from: frame.minY + 2, to: frame.minY + 18, by: 2) {
                for x in stride(from: frame.minX + 4, to: frame.maxX - 4, by: 2) {
                    if let color = sample(CGPoint(x: x, y: y)), color.r > 220 && color.g > 220 && color.b > 220 {
                        whiteTextPixels += 1
                    }
                }
            }
            check(whiteTextPixels > 5, "회전 후에도 HEX 라벨의 흰 글자가 렌더됨")
            let source = PixelMapping.originalPixel(documentPoint: CGPoint(x: 6.5, y: 5.5), sourceSize: CGSize(width: 11, height: 11),
                                                    pixelWidth: 11, pixelHeight: 11, flipH: false, flipV: false, rotation: angle)!
            checkRendered(sample(CGPoint(x: center.x + 10, y: center.y)), grid[source.y * 11 + source.x], "오른쪽 이웃도 표시 회전과 일치")
            if let output = ProcessInfo.processInfo.environment["JENA_COLOR_SNAPSHOT_DIR"], let png = bitmap.representation(using: .png, properties: [:]) {
                do { try png.write(to: URL(fileURLWithPath: output).appendingPathComponent("magnifier-\(angle).png")) }
                catch { check(false, "확대경 렌더 저장 실패: \(error)") }
            }
        }
        overlay.show(at: cursor, grid: [])
        check(overlay.isHidden, "잘못된 격자는 인덱스 오류 없이 숨김")
    }

}

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
