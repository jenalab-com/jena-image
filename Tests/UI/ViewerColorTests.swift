import AppKit

@MainActor
func runViewerColorTests(directory: URL) {
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

        for modifier in [NSEvent.ModifierFlags.shift, .control] {
            viewer.flagsChanged(with: flagsEvent([.option, modifier], window: window))
            check(!display.isMagnifierActive, "Shift/Control 조합에서는 임시 돋보기 비활성")
        }
        viewer.flagsChanged(with: flagsEvent([.option], window: window))
        viewer.showPrevious()
        check(!display.isMagnifierActive, "Option 유지 중 이미지 전환은 로딩 동안 비활성")
        check(waitUntil { color.isEnabled && display.isMagnifierActive && display.pixelSource != nil }, "새 원본 준비 후 임시 돋보기 복귀")
        viewer.flagsChanged(with: flagsEvent([], window: window))

        // 토글이 이미 켜져 있으면 ⌥는 변화 없음 (끄지 않는다)
        color.performClick(nil)
        let panel = descendants(viewer.view, of: ColorPalettePanel.self).first!
        descendants(panel, of: NSButton.self).first { $0.toolTip?.hasPrefix(L10n.string(.colorMagnifier)) == true }!.performClick(nil)
        check(display.isMagnifierActive, "토글 ON")
        viewer.flagsChanged(with: flagsEvent([.option], window: window))
        viewer.flagsChanged(with: flagsEvent([], window: window))
        check(display.isMagnifierActive, "⌥를 눌렀다 떼도 토글로 켠 돋보기는 유지")
        viewer.flagsChanged(with: flagsEvent([.option], window: window))
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        check(display.isMagnifierActive, "창 비활성화는 임시 상태만 해제하고 토글은 유지")
        viewer.viewWillDisappear()
        check(!display.isMagnifierActive, "뷰어 이탈 시 모든 돋보기 상태 해제")
    }

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
        let buildLock = NSLock()
        var builds = 0
        let previousTolerance = AppSettings.shared.colorTolerance
        AppSettings.shared.colorTolerance = AppSettings.colorToleranceRange.lowerBound
        defer { AppSettings.shared.colorTolerance = previousTolerance }
        viewer.histogramBuilder = { _, _ in
            buildLock.lock(); builds += 1; buildLock.unlock()
            let reds = [RGB8(255, 0, 0), RGB8(180, 0, 0)], blue = RGB8(0, 0, 255)
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
        buildLock.lock(); let buildCount = builds; buildLock.unlock()
        checkEqual(buildCount, 1, "히스토그램은 이미지당 한 번만")
        checkEqual(AppSettings.shared.colorTolerance, AppSettings.colorToleranceRange.upperBound, "슬라이더 값이 저장됨")

        color.performClick(nil)
        color.performClick(nil)
        let copyAll = descendants(panel, of: NSButton.self).first { $0.title == L10n.string(.colorCopyAllHex) }!
        check(waitUntil { copyAll.isEnabled }, "패널 재열기 시 캐시로 결과 복원")
        buildLock.lock(); let reopenedBuilds = builds; buildLock.unlock()
        checkEqual(reopenedBuilds, 1, "재열기도 히스토그램 재사용")
        let clipboard = NSPasteboard.general
        let savedItems = (clipboard.pasteboardItems ?? []).map { item -> NSPasteboardItem in
            let saved = NSPasteboardItem()
            for type in item.types { if let data = item.data(forType: type) { saved.setData(data, forType: type) } }
            return saved
        }
        defer { clipboard.clearContents(); clipboard.writeObjects(savedItems) }
        copyAll.performClick(nil)
        checkEqual(NSPasteboard.general.string(forType: .string), ColorFormat.hexList(viewer.currentSwatches), "HEX 전체 복사 = 비율 순 공백 구분")
        let display = descendants(viewer.view, of: ImageDisplayView.self).first!
        check(display.pixelSource != nil, "원본 픽셀 소스 준비")
        let picked = RGB8(12, 34, 56)
        panel.setMagnifierOn(true)
        display.onColorHover?(picked)
        display.onColorPicked?(picked)
        display.onColorHover?(nil)
        checkEqual(clipboard.string(forType: .string), ColorFormat.hex(picked), "돋보기 선택은 HEX 복사")
        check(descendants(panel, of: NSTextField.self).contains { $0.stringValue == ColorFormat.hex(picked) }, "커서 이탈 후 선택색 유지")
    }

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
        guard let color = descendants(viewer.view, of: NSButton.self).first(where: { $0.toolTip == L10n.string(.colorButton) }) else { return check(false, "색상 버튼 존재") }
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

    runTest("색상 패널 상태·콜백·값 행 스모크") {
        let panel = ColorPalettePanel(frame: NSRect(x: 0, y: 0, width: 800, height: 150))
        let window = NSWindow(contentRect: panel.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = panel
        defer { window.close() }
        let copyAll = descendants(panel, of: NSButton.self).first { $0.title == L10n.string(.colorCopyAllHex) }!
        check(!copyAll.isEnabled, "초기 빈 상태에서 전체 복사 금지")
        let color = RGB8(231, 111, 81)
        panel.setState(.ready([ColorSwatch(color: color, ratio: 1, lab: ColorFormat.lab(color))]))
        panel.layoutSubtreeIfNeeded()
        check(copyAll.isEnabled, "결과가 있으면 복사 활성")
        var copies = 0
        panel.onCopyAllHex = { copies += 1 }
        copyAll.performClick(nil)
        checkEqual(copies, 1, "전체 복사는 소유자 콜백으로 전달")
        var toggles = 0
        panel.onMagnifierToggled = { _ in toggles += 1 }
        panel.setMagnifierOn(true)
        checkEqual(toggles, 0, "표시 변경은 사용자 콜백을 호출하지 않음")
        panel.setPicked(color)
        panel.setHover(nil)
        check(descendants(panel, of: NSTextField.self).contains { $0.stringValue == ColorFormat.hex(color) }, "이미지를 벗어나면 마지막 선택색 유지")
        let rows = descendants(panel, of: ColorValueRow.self)
        check(rows.allSatisfy { $0.bounds.width > 0 && $0.bounds.height > 0 }, "값 행은 실제 배치 크기를 가짐")
        var copied = ""
        rows[0].onCopy = { copied = $0 }
        descendants(rows[0], of: NSButton.self).first!.performClick(nil)
        checkEqual(copied, ColorFormat.hex(color), "개별 행은 표기된 값을 전달")
        panel.setState(.loading)
        check(!copyAll.isEnabled, "로딩 중 이전 결과 복사 금지")
        check(!descendants(panel, of: NSTextField.self).contains { $0.stringValue == ColorFormat.hex(color) }, "새 이미지 로딩은 선택색 초기화")
        panel.setState(.empty)
    }

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

private func flagsEvent(_ flags: NSEvent.ModifierFlags, window: NSWindow) -> NSEvent {
    NSEvent.keyEvent(with: .flagsChanged, location: .zero, modifierFlags: flags, timestamp: 0,
                     windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "",
                     isARepeat: false, keyCode: 58)!
}
