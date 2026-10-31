import AppKit

@MainActor
func runViewerSidebarTests(controller: MainWindowController, directory: URL) {
    let urls = [directory.appendingPathComponent("masonry-1.png"), directory.appendingPathComponent("masonry-2.png")]
    let provider = ThumbnailProvider(workerCount: 1, memoryCache: ThumbnailCache()) { url, _ in
        Thread.sleep(forTimeInterval: 0.1)
        return NSImage(contentsOf: url)
    }
    let strip = ThumbnailStripView(thumbnailProvider: provider)
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 160, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = strip
    NSApp.setActivationPolicy(.accessory)
    window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
    window.orderFront(nil)
    strip.display(images: urls.compactMap { ImageFile(url: $0) }, selectedIndex: 1)
    let table = descendants(strip, of: NSTableView.self).first!
    @MainActor func matches() -> Bool {
        strip.layoutSubtreeIfNeeded()
        for index in urls.indices {
            guard let cell = table.view(atColumn: 0, row: index, makeIfNecessary: true) as? NSTableCellView,
                  let imageView = cell.imageView, let image = imageView.image else { return false }
            cell.layoutSubtreeIfNeeded()
            let expected = 120 * image.size.height / image.size.width
            if abs(imageView.frame.width - 120) > 0.1 || abs(imageView.frame.height - expected) > 0.1 { return false }
            if table.rect(ofRow: index).height < expected + 10 { return false }
        }
        return true
    }
    runTest("상세 우측 썸네일은 폭 120을 유지하고 로딩과 캐시 재표시에서 원본 비율 높이를 쓴다") {
        check(waitUntil(timeout: 5) { matches() }, "가로/세로 썸네일과 행 높이 반영")
        check(table.rect(ofRow: 0).height > table.rect(ofRow: 1).height, "세로 이미지 행이 더 높다")
        strip.display(images: urls.compactMap { ImageFile(url: $0) }, selectedIndex: 1)
        check(waitUntil { matches() }, "캐시 경로도 비율 유지")
        checkEqual(table.selectedRow, 1, "재표시 시 현재 이미지 선택 유지")
    }
    window.close()

    runTest("상세 우클릭 이름 변경은 실제 파일과 현재 URL 및 제목을 갱신하고 취소는 유지한다") {
        let source = directory.appendingPathComponent("viewer-rename.png")
        try! FileManager.default.copyItem(at: urls[0], to: source)
        let target = directory.appendingPathComponent("renamed-viewer.png")
        let window = controller.window!
        controller.currentFolderURL = directory
        controller.currentCategoryID = nil
        controller.browserVC.display(folders: [], images: [source])
        controller.switchToMode(.viewer)
        controller.viewerVC.display(imageURL: source, imageList: [ImageFile(url: source)!])
        let display = descendants(controller.viewerVC.view, of: ImageDisplayView.self).first!
        let item = display.contextMenuProvider?()?.items.first { $0.title == "이름 변경…" }
        check(item != nil, "상세 이미지에 이름 변경 메뉴 연결")
        guard let item, let action = item.action else { return }
        NSApp.sendAction(action, to: item.target, from: item)
        check(waitUntil { window.attachedSheet != nil }, "이름 변경 창 표시")
        guard let sheet = window.attachedSheet,
              let field = descendants(sheet.contentView!, of: NSTextField.self).first(where: { $0.isEditable }) else {
            check(false, "이름 입력란"); return
        }
        checkEqual(field.stringValue, "viewer-rename", "확장자를 제외한 파일명 편집")
        field.stringValue = "renamed-viewer"
        window.endSheet(sheet, returnCode: .alertFirstButtonReturn)
        check(waitUntil { controller.viewerVC.currentImageURL == target }, "변경된 파일 URL 반영")
        check(FileManager.default.fileExists(atPath: target.path) && !FileManager.default.fileExists(atPath: source.path), "실제 파일 이동")
        checkEqual(window.title, target.lastPathComponent, "상세 제목 갱신")
        checkEqual(controller.contentMode, .viewer, "이름 변경 뒤 상세 유지")
        check(waitUntil { window.attachedSheet == nil }, "변경 시트 닫힘")
        controller.viewerVC.beginRenamingCurrentImage()
        check(waitUntil { window.attachedSheet != nil }, "다시 이름 변경")
        if let sheet = window.attachedSheet { window.endSheet(sheet, returnCode: .alertSecondButtonReturn) }
        check(waitUntil { window.attachedSheet == nil }, "취소 창 닫힘")
        checkEqual(controller.viewerVC.currentImageURL, target, "취소 시 파일 유지")
        controller.viewerDidRequestClose(controller.viewerVC)
        check(waitUntil(timeout: 5) { controller.browserVC.listedImageURLs.map { $0.resolvingSymlinksInPath() }.contains(target.resolvingSymlinksInPath()) }, "목록 복귀 시 새 이름 반영")
        check(!controller.browserVC.listedImageURLs.map { $0.resolvingSymlinksInPath() }.contains(source.resolvingSymlinksInPath()), "이전 파일명 제거")
    }
    NSApp.setActivationPolicy(.prohibited)
}
