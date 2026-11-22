import AppKit

// MARK: - NSToolbarDelegate

extension MainWindowController: NSToolbarDelegate {
    /// 맞춤 셋의 (식별자, 심볼, 라벨, 툴팁, 모드)
    static let fitItems: [(id: NSToolbarItem.Identifier, symbol: String, label: String, tip: String, mode: AppSettings.ViewerFitMode)] = [
        (ToolbarID.zoomFit, "arrow.up.left.and.arrow.down.right", "맞춤", "화면에 맞춤", .window),
        (ToolbarID.zoomFitHeight, "arrow.up.and.down", "세로 맞춤", "세로로 꽉 차게", .height),
        (ToolbarID.zoomFitWidth, "arrow.left.and.right", "가로 맞춤", "가로로 꽉 차게", .width),
    ]

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        // 사이드바 토글은 항상 맨 왼쪽(제목보다 앞) — 내비게이션 항목으로 둔다.
        // 웹 버튼은 그 바로 오른쪽: 웹 패널이 사이드바 옆에 열리므로 여는 버튼도 같은 쪽에 둔다.
        if contentMode == .browser {
            let showsBack = browserVC.isSimilarityMode || browserVC.isSearchMode
            return [ToolbarID.sidebar, ToolbarID.web] + (showsBack ? [ToolbarID.back] : []) + [.flexibleSpace, ToolbarID.search, ToolbarID.checkerboard, ToolbarID.layout, ToolbarID.sort, ToolbarID.compare, ToolbarID.ai, ToolbarID.share]
        }
        return [ToolbarID.sidebar, ToolbarID.web, ToolbarID.back, .flexibleSpace,
                ToolbarID.zoomOut, ToolbarID.zoomIn, ToolbarID.zoomActualSize,
                ToolbarID.zoomFit, ToolbarID.zoomFitHeight, ToolbarID.zoomFitWidth,
                .flexibleSpace, ToolbarID.checkerboard, ToolbarID.sort, ToolbarID.compare, ToolbarID.ai, ToolbarID.share]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [ToolbarID.sidebar, ToolbarID.web, ToolbarID.back, .flexibleSpace, ToolbarID.layout,
         ToolbarID.zoomOut, ToolbarID.zoomIn, ToolbarID.zoomActualSize,
         ToolbarID.zoomFit, ToolbarID.zoomFitHeight, ToolbarID.zoomFitWidth,
         ToolbarID.sort, ToolbarID.compare, ToolbarID.ai, ToolbarID.share, ToolbarID.search, ToolbarID.checkerboard]
    }

    /// 툴바 항목의 활성 규칙 한곳 — 모드 전환(updateToolbarState)과 주기적 검사(HeaderToolbarItem.validate)가 함께 쓴다.
    func isToolbarItemEnabled(_ identifier: NSToolbarItem.Identifier) -> Bool {
        switch identifier {
        case ToolbarID.back:
            return contentMode == .viewer || browserVC.isSimilarityMode || browserVC.isSearchMode
        case ToolbarID.sort:
            return !browserVC.isSimilarityMode
        case ToolbarID.zoomIn, ToolbarID.zoomOut, ToolbarID.zoomActualSize,
             ToolbarID.zoomFit, ToolbarID.zoomFitHeight, ToolbarID.zoomFitWidth:
            return contentMode == .viewer
        case ToolbarID.compare:
            let imageCount = browserVC.selectedURLs()
                .compactMap { ImageFile(url: $0) }.filter { !$0.isVideo }.count
            return imageCount >= 2
        case ToolbarID.share:
            return !shareableURLs().isEmpty
        default:
            return true
        }
    }

    /// 같은 규격(HeaderButton)의 버튼을 담은 툴바 항목.
    private func headerItem(_ identifier: NSToolbarItem.Identifier, label: String, tip: String,
                            symbol: String? = nil, title: String? = nil, toggle: Bool = false,
                            action: Selector) -> HeaderToolbarItem {
        let item = HeaderToolbarItem(itemIdentifier: identifier)
        let button = HeaderButton(symbol: symbol, title: title, label: label, toggle: toggle)
        button.toolTip = tip
        button.target = self
        button.action = action
        item.view = button
        item.label = label
        item.toolTip = tip
        item.enabledRule = { [weak self] in self?.isToolbarItemEnabled(identifier) ?? true }
        return item
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch itemIdentifier {
        case ToolbarID.sidebar:
            let item = headerItem(itemIdentifier, label: "사이드바", tip: "사이드바 보기/숨기기 (⌥⌘S)",
                                  symbol: "sidebar.left", action: #selector(toggleSidebar(_:)))
            item.isNavigational = true
            return item

        case ToolbarID.layout:
            let item = HeaderToolbarItem(itemIdentifier: itemIdentifier)
            let control = HeaderSegmentGroup(symbols: [
                ("rectangle.grid.1x2", "Masonry", "Masonry — 원본 비율로 보기"),
                ("square.grid.2x2", "일반 격자", "일반 격자 — 같은 크기로 보기"),
            ])
            control.selectedSegment = browserVC.layoutMode == .masonry ? 0 : 1
            control.setAccessibilityLabel("이미지 목록 레이아웃")
            control.target = self
            control.action = #selector(changeBrowserLayout(_:))
            item.view = control
            item.label = "보기 방식"
            item.toolTip = "Masonry / 일반 격자"
            item.visibilityPriority = .high
            return item

        case ToolbarID.back:
            let item = headerItem(itemIdentifier, label: "뒤로",
                                  tip: contentMode == .browser ? "검색 전 목록으로 돌아가기" : "목록으로 돌아가기",
                                  symbol: "chevron.left", action: #selector(toolbarBack(_:)))
            item.isNavigational = true
            return item

        case ToolbarID.zoomIn:
            return headerItem(itemIdentifier, label: "확대", tip: "확대",
                              symbol: "plus.magnifyingglass", action: #selector(zoomIn(_:)))

        case ToolbarID.zoomOut:
            return headerItem(itemIdentifier, label: "축소", tip: "축소",
                              symbol: "minus.magnifyingglass", action: #selector(zoomOut(_:)))

        case ToolbarID.zoomActualSize:
            return headerItem(itemIdentifier, label: "원본 크기", tip: "원본 크기(100%)",
                              symbol: "1.magnifyingglass", action: #selector(zoomActualSize(_:)))

        case ToolbarID.zoomFit, ToolbarID.zoomFitHeight, ToolbarID.zoomFitWidth:
            // 셋 중 켜진 맞춤 모드만 눌린 상태로 보인다(syncFitModeSelection이 갱신).
            guard let spec = Self.fitItems.first(where: { $0.id == itemIdentifier }) else { return nil }
            let selectors: [NSToolbarItem.Identifier: Selector] = [
                ToolbarID.zoomFit: #selector(zoomFit(_:)),
                ToolbarID.zoomFitHeight: #selector(zoomFitHeight(_:)),
                ToolbarID.zoomFitWidth: #selector(zoomFitWidth(_:)),
            ]
            let item = headerItem(itemIdentifier, label: spec.label, tip: spec.tip,
                                  symbol: spec.symbol, action: selectors[itemIdentifier]!)
            (item.view as? NSButton)?.state = AppSettings.shared.viewerFitMode == spec.mode ? .on : .off
            return item

        case ToolbarID.sort:
            return headerItem(itemIdentifier, label: "정렬", tip: "정렬 기준",
                              symbol: "arrow.up.arrow.down", action: #selector(showSortMenu(_:)))

        case ToolbarID.search:
            return makeSearchToolbarItem()

        case ToolbarID.checkerboard:
            // 투명 영역 바탕 토글. 켜면 체크무늬, 끄면 흰색. 설정값은 AppSettings에 남아 다음 실행에도 유지.
            let item = headerItem(itemIdentifier, label: "투명 체크무늬",
                                  tip: "이미지의 투명한 부분을 체크무늬로 표시합니다. 끄면 흰색으로 보입니다.",
                                  symbol: "checkerboard.rectangle", toggle: true, action: #selector(toggleCheckerboard(_:)))
            (item.view as? NSButton)?.state = AppSettings.shared.showsTransparencyCheckerboard ? .on : .off
            item.view?.setAccessibilityLabel("투명 영역을 체크무늬로 표시")
            return item

        case ToolbarID.share:
            return headerItem(itemIdentifier, label: "공유", tip: "선택한 파일 공유",
                              symbol: "square.and.arrow.up", action: #selector(shareFromToolbar(_:)))

        case ToolbarID.ai:
            return headerItem(itemIdentifier, label: "AI 모드", tip: "AI 이미지 생성",
                              title: "AI", action: #selector(showAIMode(_:)))

        case ToolbarID.web:
            let item = headerItem(itemIdentifier, label: "웹 브라우저", tip: "웹 브라우저",
                                  symbol: "globe", toggle: true, action: #selector(showWebMode(_:)))
            (item.view as? NSButton)?.state = webSplitItem?.isCollapsed == false ? .on : .off
            // 내비게이션 항목이어야 창 제목보다 앞(사이드바 토글과 제목 사이)에 놓인다.
            item.isNavigational = true
            return item

        case ToolbarID.compare:
            return headerItem(itemIdentifier, label: "비교", tip: "선택한 이미지 비교",
                              symbol: "rectangle.split.2x1", action: #selector(compareSelected(_:)))

        default:
            return nil
        }
    }

    /// 정렬 버튼 — 버튼 바로 아래에 정렬 메뉴를 띄운다.
    @objc func showSortMenu(_ sender: NSButton) {
        sortMenu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
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
        performDelete(urls: urls) { [weak self] deleted in self?.removeViewedImageIfDeleted(deleted) }
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
        defer { needsFolderRefreshAfterViewerRename = false }
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
            if browserVC.isFolderLoading {
                if let current = viewer.currentImageURL { pendingSelectionURLs.insert(current) }
                navigateToFolder(url)
                sidebarVC.revealFolder(at: url)
                return
            }
            window?.title = url.lastPathComponent
            // 뷰어에서 파일을 넘기는 동안 사이드바 선택이 파일에 머무르므로, 목록으로 돌아오면 폴더로 되돌린다.
            // (하위 폴더 포함 보기에서는 다른 폴더의 파일이 선택된 채 남아 더 어색하다) 델리게이트는 억제해 재로드를 막는다.
            sidebarVC.revealFolder(at: url)
            if needsFolderRefreshAfterViewerRename { refreshAfterExternalChange() }
        }
    }

    func viewer(_ viewer: ViewerViewController, didRequestDelete url: URL) {
        performDelete(urls: [url]) { [weak self] deleted in self?.removeViewedImageIfDeleted(deleted) }
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
