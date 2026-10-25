import AppKit

@MainActor
func runLibraryDesignTests(directory: URL) {
    let suite = "jena-library-design-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults)
    let store = CategoryStore(defaults: defaults)
    let urls = (1...8).map { directory.appendingPathComponent("masonry-\($0).png") }
    let all = try! store.create(name: "레퍼런스", urls: urls)
    _ = try! store.create(name: "색감", urls: Array(urls.prefix(3)))
    _ = try! store.create(name: "구도", urls: Array(urls.suffix(4)))
    let controller = MainWindowController(categoryStore: store, settings: settings)
    let window = controller.window!
    window.isReleasedWhenClosed = false
    window.setContentSize(NSSize(width: 1120, height: 760))
    window.appearance = NSAppearance(named: .aqua)
    let captureWindow = ProcessInfo.processInfo.environment["JENA_CAPTURE_WINDOW"] == "1"
    window.setFrameOrigin(captureWindow ? NSPoint(x: 100, y: 100) : NSPoint(x: -10000, y: -10000))
    NSApp.setActivationPolicy(.accessory)
    controller.sidebarVC.setCategoryView(true)
    controller.showCategory(all.id)
    window.orderFront(nil)
    window.displayIfNeeded()
    window.contentView?.layoutSubtreeIfNeeded()
    let browser = controller.browserVC
    let collection = descendants(browser.view, of: NSCollectionView.self).first!
    let layout = collection.collectionViewLayout as! MasonryLayout

    func layoutControl() -> NSSegmentedControl? {
        window.toolbar?.items.first { $0.itemIdentifier == MainWindowController.ToolbarID.layout }?.view as? NSSegmentedControl
    }

    runTest("썸네일의 투명 부분은 체크무늬이고 불투명 이미지 색은 유지된다") {
        let thumbnail = ThumbnailImageView(frame: NSRect(x: 0, y: 0, width: 32, height: 32))
        thumbnail.imageScaling = .scaleNone
        thumbnail.image = NSImage(size: thumbnail.bounds.size, flipped: false) { _ in
            NSColor.white.setFill()
            NSRect(x: 16, y: 0, width: 16, height: 32).fill()
            return true
        }
        let rendered = NSImage(size: thumbnail.bounds.size, flipped: false) { rect in
            thumbnail.draw(rect)
            return true
        }
        let bitmap = NSBitmapImageRep(data: rendered.tiffRepresentation!)!
        let dark = bitmap.colorAt(x: 2, y: 2)!.usingColorSpace(.deviceRGB)!
        let light = bitmap.colorAt(x: 10, y: 2)!.usingColorSpace(.deviceRGB)!
        let white = bitmap.colorAt(x: 24, y: 2)!.usingColorSpace(.deviceRGB)!
        check(abs(dark.redComponent - light.redComponent) > 0.1, "투명 영역에 두 톤의 체크무늬 표시")
        check(white.redComponent > 0.98 && white.greenComponent > 0.98 && white.blueComponent > 0.98, "흰색 원본은 회색으로 덮이지 않음")
        check(dark.alphaComponent == 1 && light.alphaComponent == 1, "배경에 관계없이 체크무늬 대비 유지")
    }
    func chooseLayout(_ segment: Int) {
        guard let control = layoutControl() else { check(false, "보기 전환 버튼 존재"); return }
        control.selectedSegment = segment
        NSApp.sendAction(control.action!, to: control.target, from: control)
        collection.layoutSubtreeIfNeeded()
        layout.prepare()
    }
    func savePreview(_ name: String) {
        _ = waitUntil(timeout: 2) {
            collection.layoutSubtreeIfNeeded()
            let items = collection.visibleItems().compactMap { $0 as? BrowserItem }
            return !items.isEmpty && items.allSatisfy { $0.hasThumbnail }
        }
        _ = waitUntil(timeout: 0.35) { false }
        window.displayIfNeeded()
        guard let view = window.contentView?.superview,
              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        let output = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent(name + ".png")
        if captureWindow {
            let capture = Process()
            capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            capture.arguments = ["-x", "-o", "-l", String(window.windowNumber), output.deletingPathExtension().path + "-composited.png"]
            do {
                try capture.run()
                capture.waitUntilExit()
            } catch {
                print("Window capture unavailable: \(error)")
            }
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try? bitmap.representation(using: .png, properties: [:])?.write(to: output)
        print("Library preview: \(output.path)")
    }

    runTest("사이드바는 흰색이고 목록에만 네이티브 반투명 표면을 사용한다") {
        let sidebar = controller.sidebarVC.view as? LibrarySurfaceView
        let canvas = browser.view as? LibrarySurfaceView
        check(sidebar?.effect.isHidden == true && sidebar?.layer?.backgroundColor == NSColor.white.cgColor, "사이드바 불투명 흰색")
        check(canvas?.effect.material == .underWindowBackground && canvas?.effect.blendingMode == .behindWindow, "목록 뒤 배경을 블러 처리")
        check(window.isOpaque && window.backgroundColor.alphaComponent == 1, "창 전체의 투명 합성 방지")
        check(descendants(browser.view, of: NSScrollView.self).allSatisfy { !$0.drawsBackground }, "리스트 블러를 흰색 스크롤 배경이 가리지 않음")
        check(descendants(controller.sidebarVC.view, of: NSScrollView.self).allSatisfy { !$0.drawsBackground }, "사이드바 흰색 표면 유지")
        check(collection.backgroundColors.allSatisfy { $0.alphaComponent == 0 }, "컬렉션 배경 투명")
    }

    runTest("상세 기본 배경은 목록과 같고 단색 배경 선택도 유지한다") {
        let display = ImageDisplayView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        display.applyBackground(.system)
        let surface = descendants(display, of: LibrarySurfaceView.self).first!
        let scroll = descendants(display, of: NSScrollView.self).first!
        check(!surface.isHidden && surface.effect.material == .underWindowBackground, "상세 캔버스 재질")
        check(!scroll.drawsBackground && !scroll.contentView.drawsBackground, "이미지 뒤 블러를 가리지 않음")
        display.applyBackground(.dark)
        check(surface.isHidden && scroll.drawsBackground, "사용자가 지정한 어두운 배경 유지")
    }

    runTest("상단 버튼으로 격자로 전환해도 현재 카테고리와 선택을 유지한다") {
        browser.restoreSelection(urls: [urls[0], urls[2]])
        chooseLayout(1)
        checkEqual(browser.layoutMode, .grid, "격자 선택")
        checkEqual(controller.currentCategoryID, all.id, "카테고리 유지")
        checkEqual(Set(browser.selectedURLs()), Set([urls[0], urls[2]]), "선택 이미지 유지")
        let frames = urls.indices.compactMap { layout.layoutAttributesForItem(at: IndexPath(item: $0, section: 0))?.frame }
        checkEqual(Set(frames.map(\.height)).count, 1, "이미지 높이가 달라도 셀은 같은 크기")
        checkEqual(AppSettings(defaults: defaults).browserLayoutMode, .grid, "설정 재생성 후 선택 복원")
        checkEqual(BrowserViewController(settings: AppSettings(defaults: defaults)).layoutMode, .grid, "새 브라우저에서도 격자 복원")
    }

    runTest("상세 화면에서는 줌 도구를 제공하고 복귀 시 보기 방식 버튼을 복원한다") {
        controller.browser(browser, didRequestViewImage: urls[0], inList: urls.compactMap { ImageFile(url: $0) })
        check(window.toolbar!.items.contains { $0.itemIdentifier == MainWindowController.ToolbarID.zoomIn }, "상세 확대 버튼")
        check(layoutControl() == nil, "상세에서 목록 전환 버튼 제외")
        savePreview("library-detail")
        controller.viewerDidRequestClose(controller.viewerVC)
        checkEqual(layoutControl()?.selectedSegment, 1, "격자 선택 복원")
        check(!window.toolbar!.items.contains { $0.itemIdentifier == MainWindowController.ToolbarID.zoomIn }, "목록에 불필요한 줌 버튼 없음")
    }
    browser.restoreSelection(urls: [])
    savePreview("library-grid")

    runTest("격자에서 masonry로 돌아가면 원본 비율과 선택을 유지한다") {
        browser.restoreSelection(urls: [urls[1]])
        chooseLayout(0)
        check(waitUntil(timeout: 3) {
            collection.layoutSubtreeIfNeeded()
            layout.prepare()
            let frames = urls.indices.compactMap { layout.layoutAttributesForItem(at: IndexPath(item: $0, section: 0))?.frame }
            return Set(frames.map(\.height)).count > 1
        }, "서로 다른 이미지 높이 복원")
        checkEqual(browser.selectedURLs(), [urls[1]], "선택 유지")
        checkEqual(settings.browserLayoutMode, .masonry, "마지막 선택 저장")
    }
    browser.restoreSelection(urls: [])
    savePreview("library-masonry")

    runTest("밝은 모드와 어두운 모드 모두 카드 표면을 다시 그린다") {
        let lightCard = collection.visibleItems().first?.view as? LibraryCardView
        lightCard?.updateLayer()
        let lightColor = lightCard?.layer?.backgroundColor
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView?.layoutSubtreeIfNeeded()
        let darkCard = collection.visibleItems().first?.view as? LibraryCardView
        darkCard?.updateLayer()
        check(lightColor != nil && darkCard?.layer?.backgroundColor != lightColor, "다크 모드 카드 색 변경")
        check(controller.sidebarVC.view.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua, "다크 모드에서도 흰색 사이드바의 글자는 어둡게 유지")
    }
    savePreview("library-dark")
    controller.browserVC.viewWillDisappear()
    window.close()
    NSApp.setActivationPolicy(.prohibited)
}
