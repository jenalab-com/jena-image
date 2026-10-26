import AppKit

// MARK: - NSToolbarDelegate

extension MainWindowController: NSToolbarDelegate {
    /// 툴바는 SF Symbol 이미지에 자기 크기 설정을 다시 입혀서 SymbolConfiguration이 먹지 않는다.
    /// 화살표 심볼은 글리프가 상자를 꽉 채워 돋보기보다 커 보이므로, 작은 포인트로 고정 비트맵에 그려 넣는다.
    /// `selected`면 강조색으로 칠해 "켜진 모드"를 보인다(템플릿이 아니므로 툴바가 색을 덮지 않는다).
    static func fitSymbol(_ name: String, label: String, selected: Bool = false) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 10, weight: .regular)
        guard let glyph = NSImage(systemSymbolName: name, accessibilityDescription: label)?
            .withSymbolConfiguration(config) else { return nil }
        let box = NSSize(width: 16, height: 15)  // 돋보기 심볼과 같은 상자
        let image = NSImage(size: box, flipped: false) { rect in
            let g = glyph.size
            let origin = NSPoint(x: (rect.width - g.width) / 2, y: (rect.height - g.height) / 2)
            glyph.draw(in: NSRect(origin: origin, size: g))
            if selected {
                NSColor.controlAccentColor.set()
                rect.fill(using: .sourceAtop)
            }
            return true
        }
        image.isTemplate = !selected
        image.accessibilityDescription = label
        return image
    }

    /// 맞춤 셋의 (식별자, 심볼, 라벨, 툴팁, 모드)
    static let fitItems: [(id: NSToolbarItem.Identifier, symbol: String, label: String, tip: String, mode: AppSettings.ViewerFitMode)] = [
        (ToolbarID.zoomFit, "arrow.up.left.and.arrow.down.right", "맞춤", "화면에 맞춤", .window),
        (ToolbarID.zoomFitHeight, "arrow.up.and.down", "세로 맞춤", "세로로 꽉 차게", .height),
        (ToolbarID.zoomFitWidth, "arrow.left.and.right", "가로 맞춤", "가로로 꽉 차게", .width),
    ]

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        if contentMode == .browser {
            let showsBack = browserVC.isSimilarityMode || browserVC.isSearchMode
            return [.toggleSidebar] + (showsBack ? [ToolbarID.back] : []) + [.flexibleSpace, ToolbarID.search, ToolbarID.layout, ToolbarID.sort, ToolbarID.compare, ToolbarID.share]
        }
        return [.toggleSidebar, ToolbarID.back, .flexibleSpace,
                ToolbarID.zoomOut, ToolbarID.zoomIn, ToolbarID.zoomActualSize,
                ToolbarID.zoomFit, ToolbarID.zoomFitHeight, ToolbarID.zoomFitWidth,
                .flexibleSpace, ToolbarID.sort, ToolbarID.compare, ToolbarID.share]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.toggleSidebar, ToolbarID.back, .flexibleSpace, ToolbarID.layout,
         ToolbarID.zoomOut, ToolbarID.zoomIn, ToolbarID.zoomActualSize,
         ToolbarID.zoomFit, ToolbarID.zoomFitHeight, ToolbarID.zoomFitWidth,
         ToolbarID.sort, ToolbarID.compare, ToolbarID.share, ToolbarID.search]
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)

        switch itemIdentifier {
        case ToolbarID.layout:
            let control = NSSegmentedControl()
            control.segmentCount = 2
            control.trackingMode = .selectOne
            control.segmentStyle = .rounded
            control.controlSize = .small
            control.setImage(NSImage(systemSymbolName: "rectangle.grid.1x2", accessibilityDescription: "Masonry"), forSegment: 0)
            control.setImage(NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "일반 격자"), forSegment: 1)
            control.setToolTip("Masonry — 원본 비율로 보기", forSegment: 0)
            control.setToolTip("일반 격자 — 같은 크기로 보기", forSegment: 1)
            control.setWidth(30, forSegment: 0)
            control.setWidth(30, forSegment: 1)
            control.selectedSegment = browserVC.layoutMode == .masonry ? 0 : 1
            control.setAccessibilityLabel("이미지 목록 레이아웃")
            control.target = self
            control.action = #selector(changeBrowserLayout(_:))
            item.view = control
            item.label = "보기 방식"
            item.toolTip = "Masonry / 일반 격자"
            item.visibilityPriority = .high

        case ToolbarID.back:
            item.isNavigational = true
            item.label = "뒤로"
            item.toolTip = contentMode == .browser ? "검색 전 목록으로 돌아가기" : "목록으로 돌아가기"
            item.image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "뒤로")
            item.action = #selector(toolbarBack(_:))
            item.target = self
            item.isEnabled = false

        case ToolbarID.zoomIn:
            item.label = "확대"
            item.toolTip = "확대"
            item.image = NSImage(systemSymbolName: "plus.magnifyingglass", accessibilityDescription: "확대")
            item.action = #selector(zoomIn(_:))
            item.target = self
            item.isEnabled = false

        case ToolbarID.zoomOut:
            item.label = "축소"
            item.toolTip = "축소"
            item.image = NSImage(systemSymbolName: "minus.magnifyingglass", accessibilityDescription: "축소")
            item.action = #selector(zoomOut(_:))
            item.target = self
            item.isEnabled = false

        case ToolbarID.zoomActualSize:
            item.label = "원본 크기"
            item.toolTip = "원본 크기(100%)"
            item.image = NSImage(systemSymbolName: "1.magnifyingglass", accessibilityDescription: "원본 크기")
            item.action = #selector(zoomActualSize(_:))
            item.target = self
            item.isEnabled = false

        case ToolbarID.zoomFit, ToolbarID.zoomFitHeight, ToolbarID.zoomFitWidth:
            // 돋보기 셋과 같은 모양의 나란한 버튼. 켜진 모드는 강조색 심볼로 표시(syncFitModeSelection이 갱신).
            guard let spec = Self.fitItems.first(where: { $0.id == itemIdentifier }) else { return nil }
            let selectors: [NSToolbarItem.Identifier: Selector] = [
                ToolbarID.zoomFit: #selector(zoomFit(_:)),
                ToolbarID.zoomFitHeight: #selector(zoomFitHeight(_:)),
                ToolbarID.zoomFitWidth: #selector(zoomFitWidth(_:)),
            ]
            item.label = spec.label
            item.toolTip = spec.tip
            item.image = Self.fitSymbol(spec.symbol, label: spec.label,
                                        selected: AppSettings.shared.viewerFitMode == spec.mode)
            item.action = selectors[itemIdentifier]
            item.target = self
            item.isEnabled = false

        case ToolbarID.sort:
            let menuItem = NSMenuToolbarItem(itemIdentifier: itemIdentifier)
            menuItem.label = "정렬"
            menuItem.toolTip = "정렬 기준"
            menuItem.image = NSImage(systemSymbolName: "arrow.up.arrow.down", accessibilityDescription: "정렬")
            menuItem.menu = sortMenu
            menuItem.showsIndicator = true
            return menuItem

        case ToolbarID.search:
            return makeSearchToolbarItem()

        case ToolbarID.share:
            // 시스템 공유 버튼. 대상은 delegate의 items(for:)가 매번 제공하고, 비어 있으면 자동 비활성.
            let shareItem = NSSharingServicePickerToolbarItem(itemIdentifier: itemIdentifier)
            shareItem.label = "공유"
            shareItem.toolTip = "선택한 파일 공유"
            shareItem.delegate = self
            return shareItem

        case ToolbarID.compare:
            item.label = "비교"
            item.toolTip = "선택한 이미지 비교"
            item.image = NSImage(systemSymbolName: "rectangle.split.2x1", accessibilityDescription: "비교")
            item.action = #selector(compareSelected(_:))
            item.target = self

        default:
            return nil
        }

        return item
    }
}

// MARK: - SidebarDelegate

extension MainWindowController: SidebarDelegate {
    func sidebar(_ sidebar: SidebarViewController, didSelectFolder url: URL) {
        activePanel = .sidebar
        navigateToFolder(url)
    }

    func sidebar(_ sidebar: SidebarViewController, didSelectImage file: ImageFile, inFolder url: URL) {
        activePanel = .sidebar
        // 해당 폴더로 이동 후 이미지 뷰어 열기
        if currentFolderURL != url || browserVC.isCollectionMode {
            navigateToFolder(url)
        }
        let folderImages = imageFilesInCurrentFolder()
        switchToMode(.viewer)
        viewerVC.display(imageURL: file.url, imageList: folderImages)
    }

    func sidebar(_ sidebar: SidebarViewController, didReceiveDrop imageURLs: [URL], toFolder url: URL) {
        performMoveToFolder(urls: imageURLs, target: url)
    }

    func sidebar(_ sidebar: SidebarViewController, didRequestRename url: URL, newName: String) {
        performRename(url: url, newName: newName)
    }

    func sidebarDidRequestAddFolder(_ sidebar: SidebarViewController) {
        addFolder(nil)
    }

    func sidebar(_ sidebar: SidebarViewController, didRequestCreateFolder name: String, in parentURL: URL) {
        let result = fileService.createFolder(in: parentURL, name: name)
        switch result {
        case .success:
            sidebarVC.reloadFolder(at: parentURL)
            if parentURL == currentFolderURL {
                refreshCurrentFolder()
            }
        case .failure(let error):
            showError(error)
        }
    }

    func sidebar(_ sidebar: SidebarViewController, didRequestRemoveFolder url: URL) {
        removeFolder(url)
    }

    func sidebar(_ sidebar: SidebarViewController, didRequestDelete urls: [URL]) {
        performDelete(urls: urls)
    }

    func sidebar(_ sidebar: SidebarViewController, didRequestExport url: URL) {
        performExport(url: url)
    }

    func sidebar(_ sidebar: SidebarViewController, didToggleRecursive enabled: Bool) {
        // 북마크 보기 중이면 폴더 목록으로 튕기지 않고, 다음 폴더 선택부터 새 모드가 적용된다.
        guard !browserVC.isCollectionMode, let url = currentFolderURL else { return }
        if contentMode == .viewer {
            // 뷰어에서 토글하면 현재 이미지는 그대로 두고 좌우 탐색 목록만 새 모드로 바꾼다.
            // (하위 폴더 이미지를 보던 중 끄면 현재 폴더 목록에 없을 수 있으므로 그때는 유지)
            let list = imageFilesInCurrentFolder()
            if let current = viewerVC.currentImageURL, list.contains(where: { $0.url == current }) {
                viewerVC.display(imageURL: current, imageList: list)
            }
            return
        }
        navigateToFolder(url)
    }

    func sidebarDidSelectBookmarks(_ sidebar: SidebarViewController) {
        activePanel = .sidebar
        showBookmarks()
    }

    func sidebar(_ sidebar: SidebarViewController, didExpandFolder url: URL) {
        // 펼친 폴더는 그 안에서 일어나는 생성·삭제를 바로 반영해야 하므로 감시 대상에 넣는다
        syncWatchedFolders()
    }

    func sidebar(_ sidebar: SidebarViewController, didCollapseFolder url: URL) {
        syncWatchedFolders()
    }

    func sidebarDidRequestReload(_ sidebar: SidebarViewController) {
        refreshAll(nil)
    }
}

// MARK: - BrowserDelegate

extension MainWindowController: BrowserDelegate {
    func browser(_ browser: BrowserViewController, didOpenFolder url: URL) {
        activePanel = .browser
        navigateToFolder(url)
        sidebarVC.selectFolder(at: url)
    }

    func browser(_ browser: BrowserViewController, didRequestViewImage url: URL, inList: [ImageFile]) {
        activePanel = .viewer
        switchToMode(.viewer)
        viewerVC.display(imageURL: url, imageList: inList)
        updateInfoPanelIfNeeded(for: url)
    }

    func browser(_ browser: BrowserViewController, didRequestDelete urls: [URL]) {
        performDelete(urls: urls)
    }

    func browser(_ browser: BrowserViewController, didRequestMove urls: [URL]) {
        performMove(urls: urls)
    }

    func browser(_ browser: BrowserViewController, didRequestCopy urls: [URL]) {
        performCopy(urls: urls)
    }

    func browser(_ browser: BrowserViewController, didRequestRename url: URL, newName: String) {
        performRename(url: url, newName: newName)
    }

    func browser(_ browser: BrowserViewController, didRequestExport url: URL) {
        performExport(url: url)
    }

    func browser(_ browser: BrowserViewController, didRequestCreateFolder name: String) {
        guard let parentURL = currentFolderURL else { return }
        let result = fileService.createFolder(in: parentURL, name: name)
        switch result {
        case .success:
            sidebarVC.reloadFolder(at: parentURL)
            refreshCurrentFolder()
        case .failure(let error):
            showError(error)
        }
    }

    func browser(_ browser: BrowserViewController, didRequestMoveToFolder urls: [URL], destination: URL) {
        performMoveToFolder(urls: urls, target: destination)
    }

    func browserDidRequestCompare(_ browser: BrowserViewController, urls: [URL]) {
        compareFiles(urls)
    }

    func browserDidToggleBookmark(_ browser: BrowserViewController, urls: [URL]) {
        toggleBookmark(urls)
    }

    func browserDidRequestRemoveBookmark(_ browser: BrowserViewController, urls: [URL]) {
        urls.forEach { bookmarkStore.remove($0) }
    }

    func browser(_ browser: BrowserViewController, didRequestShowInfo url: URL) {
        showInfo(for: url)
    }

    func browser(_ browser: BrowserViewController, didRequestBatchExport urls: [URL]) {
        performBatchExport(urls: urls)
    }

    func browser(_ browser: BrowserViewController, didRequestShare urls: [URL]) {
        share(urls: urls.filter { ImageFile(url: $0) != nil && FileManager.default.fileExists(atPath: $0.path) })
    }
}

// MARK: - ViewerDelegate

extension MainWindowController: ViewerDelegate {
    func viewerDidRequestClose(_ viewer: ViewerViewController) {
        if browserVC.isSimilarityMode {
            switchToMode(.browser)
            refreshSimilarityResults()
            return
        }
        if browserVC.isSearchMode {
            switchToMode(.browser)
            refreshSearchResults()
            return
        }
        if browserVC.isCategoryMode { showCategory(currentCategoryID); return }
        if browserVC.isBookmarkMode { showBookmarks(); return }
        switchToMode(.browser)
        if let url = currentFolderURL {
            window?.title = url.lastPathComponent
            // 뷰어에서 파일을 넘기는 동안 사이드바 선택이 파일에 머무르므로, 목록으로 돌아오면 폴더로 되돌린다.
            // (하위 폴더 포함 보기에서는 다른 폴더의 파일이 선택된 채 남아 더 어색하다) 델리게이트는 억제해 재로드를 막는다.
            sidebarVC.revealFolder(at: url)
        }
    }

    func viewer(_ viewer: ViewerViewController, didRequestDelete url: URL) {
        performDelete(urls: [url])
        viewer.removeCurrentImage()
    }

    func viewer(_ viewer: ViewerViewController, didRequestExport url: URL) {
        performExport(url: url)
    }

    func viewer(_ viewer: ViewerViewController, didRequestRename url: URL, newName: String) {
        performRename(url: url, newName: newName)
    }

    func viewer(_ viewer: ViewerViewController, didSwitchToVideo isVideo: Bool) {
        statusBar.setViewerMode(true, isVideo: isVideo)
    }

    func viewer(_ viewer: ViewerViewController, didNavigateToFile url: URL) {
        if !browserVC.isCollectionMode { sidebarVC.selectFile(at: url) }
        updateInfoPanelIfNeeded(for: url)
    }

    func viewerDidEndEditing(_ viewer: ViewerViewController) {
    }

    func viewerIsBookmarked(_ viewer: ViewerViewController, url: URL) -> Bool {
        bookmarkStore.contains(url)
    }

    func viewer(_ viewer: ViewerViewController, didSaveEditedImageToFolder folderURL: URL) {
        // 저장된 폴더가 현재 폴더이면 브라우저 갱신
        if folderURL == currentFolderURL {
            refreshCurrentFolder()
        }
        // 사이드바 폴더 미디어 수 갱신
        sidebarVC.reloadFolder(at: folderURL)
    }
}
