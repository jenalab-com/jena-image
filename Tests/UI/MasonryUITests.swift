import AppKit
import ImageIO
import UniformTypeIdentifiers

@MainActor
func runMasonryUITests(directory: URL) {
    let suite = "jena-masonry-settings-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let sizes = [CGSize(width: 240, height: 360), CGSize(width: 400, height: 220),
                 CGSize(width: 300, height: 300), CGSize(width: 240, height: 460),
                 CGSize(width: 420, height: 260), CGSize(width: 260, height: 340),
                 CGSize(width: 320, height: 240), CGSize(width: 250, height: 390)]
    let urls = sizes.enumerated().map { index, size -> URL in
        let url = directory.appendingPathComponent("masonry-\(index + 1).png")
        let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor(calibratedHue: CGFloat(index) / 9, saturation: 0.35, brightness: 0.75, alpha: 1).cgColor)
        context.fill(CGRect(origin: .zero, size: size))
        context.setFillColor(NSColor.white.withAlphaComponent(0.35).cgColor)
        context.fillEllipse(in: CGRect(x: size.width * 0.15, y: size.height * 0.3,
                                      width: size.width * 0.7, height: size.width * 0.7))
        let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        check(CGImageDestinationFinalize(destination), "masonry 테스트 원본 생성")
        return url
    }
    let provider = ThumbnailProvider(workerCount: 2, memoryCache: ThumbnailCache()) { url, _ in NSImage(contentsOf: url) }
    let browser = BrowserViewController(thumbnailProvider: provider, settings: AppSettings(defaults: defaults))
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 640),
                          styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentViewController = browser
    window.setContentSize(NSSize(width: 820, height: 640))
    NSApp.setActivationPolicy(.accessory)
    window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
    window.orderFront(nil)
    window.displayIfNeeded()
    window.contentView?.layoutSubtreeIfNeeded()
    browser.display(folders: [], images: urls)
    let collection = descendants(browser.view, of: NSCollectionView.self).first!
    let layout = collection.collectionViewLayout as! MasonryLayout

    runTest("masonry 브라우저는 메타데이터 로딩 후 이미지 비율대로 배치한다") {
        check(waitUntil(timeout: 5) {
            collection.layoutSubtreeIfNeeded()
            layout.prepare()
            return sizes.indices.allSatisfy { index in
                guard let frame = layout.layoutAttributesForItem(at: IndexPath(item: index, section: 0))?.frame else { return false }
                let expected = (frame.width - 4) * sizes[index].height / sizes[index].width
                return abs(frame.height - BrowserItem.captionHeight - expected) < 1
            }
        }, "모든 이미지의 원본 비율 반영")
        check(layout.collectionViewContentSize.height > 640, "세로 스크롤 콘텐츠 높이")
    }

    runTest("masonry 크기 조절·창 리사이즈 후에도 선택한 이미지를 유지한다") {
        browser.restoreSelection(urls: [urls[0], urls[2]])
        let initialWidth = layout.layoutAttributesForItem(at: IndexPath(item: 0, section: 0))!.frame.width
        browser.updateThumbnailScale(2)
        collection.layoutSubtreeIfNeeded()
        layout.prepare()
        check(layout.layoutAttributesForItem(at: IndexPath(item: 0, section: 0))!.frame.width > initialWidth, "열 폭 증가")
        window.setContentSize(NSSize(width: 540, height: 640))
        window.contentView?.layoutSubtreeIfNeeded()
        collection.layoutSubtreeIfNeeded()
        layout.prepare()
        checkEqual(Set(browser.selectedURLs()), Set([urls[0], urls[2]]), "크기 변경 후 다중 선택 유지")
        let frames = sizes.indices.compactMap { layout.layoutAttributesForItem(at: IndexPath(item: $0, section: 0))?.frame }
        check(frames.allSatisfy { $0.maxX <= 540 }, "좁은 창 가로 범위 안에 배치")
        browser.updateThumbnailScale(1)
        window.setContentSize(NSSize(width: 820, height: 640))
        window.contentView?.layoutSubtreeIfNeeded()
        collection.layoutSubtreeIfNeeded()
    }

    runTest("masonry 셀은 둥근 이미지와 두 줄 파일명 공간을 함께 유지한다") {
        check(waitUntil(timeout: 3) { collection.layoutSubtreeIfNeeded(); return !collection.visibleItems().isEmpty }, "보이는 셀 생성")
        for case let item as BrowserItem in collection.visibleItems() {
            item.view.layoutSubtreeIfNeeded()
            let imageView = descendants(item.view, of: NSImageView.self).first { $0.layer?.cornerRadius == 12 }
            check(imageView != nil && imageView?.layer?.masksToBounds == true, "12pt 둥근 모서리 클리핑")
            if let imageView {
                check(abs(imageView.frame.height - (item.view.bounds.height - BrowserItem.captionHeight)) < 1, "고정 정사각형 제약 제거")
            }
        }
    }

    runTest("북마크·카테고리·하위 폴더 목록에도 masonry를 적용한다") {
        let files = urls.compactMap { ImageFile(url: $0) }
        browser.displayBookmarks(files)
        check(browser.isBookmarkMode && collection.collectionViewLayout is MasonryLayout, "북마크 레이아웃")
        browser.displayCategory(files)
        check(browser.isCategoryMode && collection.collectionViewLayout is MasonryLayout, "카테고리 레이아웃")
        browser.display(folders: [], images: urls, recursiveRoot: directory)
        checkEqual(layout.captionHeight, BrowserItem.captionHeight + BrowserItem.pathLineHeight, "경로 줄 공간 보존")
        browser.display(folders: [], images: urls)
    }

    _ = waitUntil(timeout: 3) {
        collection.layoutSubtreeIfNeeded()
        layout.prepare()
        guard let frame = layout.layoutAttributesForItem(at: IndexPath(item: 0, section: 0))?.frame,
              abs(frame.height - BrowserItem.captionHeight - (frame.width - 4) * 1.5) < 1 else { return false }
        let items = collection.visibleItems().compactMap { $0 as? BrowserItem }
        return !items.isEmpty && items.allSatisfy { $0.hasThumbnail }
    }
    runTest("masonry 갱신 후 화면 안의 모든 항목이 빠짐없이 표시된다") {
        _ = waitUntil(timeout: 0.35) { false }
        collection.layoutSubtreeIfNeeded()
        let expected = Set(layout.layoutAttributesForElements(in: collection.visibleRect).compactMap(\.indexPath))
        let visible = Set(collection.indexPathsForVisibleItems())
        checkEqual(visible, expected, "레이아웃 영역과 실제 표시 항목 일치")
        for indexPath in expected {
            guard let item = collection.item(at: indexPath) else { check(false, "보이는 셀 존재"); continue }
            check(!item.view.isHidden && item.view.alphaValue > 0, "셀 숨김 없음")
        }
    }
    if let bitmap = browser.view.bitmapImageRepForCachingDisplay(in: browser.view.bounds) {
        browser.view.cacheDisplay(in: browser.view.bounds, to: bitmap)
        let output = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("masonry-preview.png")
        try? bitmap.representation(using: .png, properties: [:])?.write(to: output)
        print("Masonry preview: \(output.path)")
    }
    browser.viewWillDisappear()
    window.close()
    NSApp.setActivationPolicy(.prohibited)
}
