import AppKit

// MARK: - Toolbar Actions

extension MainWindowController {

    @objc func toolbarBack(_ sender: Any?) {
        if contentMode == .viewer {
            viewerDidRequestClose(viewerVC)
        }
    }

    @objc func zoomIn(_ sender: Any?) {
        guard contentMode == .viewer else { return }
        viewerVC.zoomIn()
    }

    @objc func zoomOut(_ sender: Any?) {
        guard contentMode == .viewer else { return }
        viewerVC.zoomOut()
    }

    @objc func zoomActualSize(_ sender: Any?) {
        guard contentMode == .viewer else { return }
        viewerVC.zoomActualSize()
    }

    @objc func zoomFit(_ sender: Any?) {
        guard contentMode == .viewer else { return }
        viewerVC.zoomFit()
    }
}

// MARK: - Active Selection Helper

extension MainWindowController {

    /// 사이드바에 포커스가 있는지 (first responder 기준)
    var isSidebarFocused: Bool {
        sidebarVC.isFocused
    }

    /// 현재 활성 패널에 따른 선택된 URL 목록
    func activeSelectedURLs() -> [URL] {
        if isSidebarFocused, let url = sidebarVC.selectedItemURL {
            return [url]
        }
        if contentMode == .viewer, let url = viewerVC.currentImageURL {
            return [url]
        }
        return browserVC.selectedURLs()
    }

    /// 현재 활성 패널에 선택된 항목이 있는지
    func hasActiveSelection() -> Bool {
        if isSidebarFocused { return sidebarVC.selectedItemIsNonRoot }
        if contentMode == .viewer { return viewerVC.currentImageURL != nil }
        return !browserVC.selectedURLs().isEmpty
    }

    /// 현재 활성 패널에 이미지가 선택되어 있는지
    func hasActiveImageSelection() -> Bool {
        if isSidebarFocused { return sidebarVC.selectedItemIsImage }
        if contentMode == .viewer { return viewerVC.currentImageURL != nil }
        return !browserVC.selectedURLs().isEmpty
    }
}

// MARK: - Menu Actions

extension MainWindowController {

    @objc func revealInFinder(_ sender: Any?) {
        let urls = activeSelectedURLs()
        if !urls.isEmpty {
            NSWorkspace.shared.activateFileViewerSelecting(urls)
        } else if let folder = currentFolderURL {
            NSWorkspace.shared.activateFileViewerSelecting([folder])
        }
    }

    @objc func copyFiles(_ sender: Any?) {
        // 텍스트 편집 중이면 텍스트 복사로 위임
        if let textView = window?.firstResponder as? NSTextView, textView.isFieldEditor {
            textView.copy(sender)
            return
        }

        let urls = activeSelectedURLs()
        guard !urls.isEmpty else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        var items: [NSPasteboardWriting] = urls.map { $0 as NSURL }
        if urls.count == 1, let image = NSImage(contentsOf: urls[0]) {
            items.append(image)
        }
        pasteboard.writeObjects(items)
    }

    @objc func pasteFiles(_ sender: Any?) {
        // 텍스트 편집 중이면 텍스트 붙여넣기로 위임
        if let textView = window?.firstResponder as? NSTextView, textView.isFieldEditor {
            textView.paste(sender)
            return
        }

        guard let folderURL = currentFolderURL else { return }

        let pasteboard = NSPasteboard.general

        // 클립보드에서 파일 URL 읽기
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true,
        ]) as? [URL], !urls.isEmpty else { return }

        // Finder 잘라내기(⌘⌥V) 감지: com.apple.pasteboard.promised-file-url 또는 cut flag
        let isCut = pasteboard.types?.contains(NSPasteboard.PasteboardType("com.apple.pasteboard.cut")) == true

        var pastedAny = false
        for url in urls {
            guard FileManager.default.fileExists(atPath: url.path) else { continue }

            if isCut {
                // 잘라넣기 → 이동
                let result = fileService.moveFile(from: url, to: folderURL)
                if case .success = result {
                    ThumbnailCache.shared.invalidate(for: url)
                    pastedAny = true
                    // 원본 폴더 갱신
                    sidebarVC.reloadFolder(at: url.deletingLastPathComponent())
                }
            } else {
                // 붙여넣기 → 복사
                let result = fileService.copyFile(from: url, to: folderURL)
                if case .success = result {
                    pastedAny = true
                }
            }
        }

        if pastedAny {
            if isCut {
                // 잘라넣기 후 클립보드 비우기
                pasteboard.clearContents()
            }
            refreshCurrentFolder()
            sidebarVC.reloadFolder(at: folderURL)
        }
    }

    @objc func selectAllItems(_ sender: Any?) {
        guard contentMode == .browser else { return }
        browserVC.selectAllItems()
    }

    @objc func toggleSidebar(_ sender: Any?) {
        guard let sidebarItem = splitViewController.splitViewItems.first else { return }
        sidebarItem.animator().isCollapsed = !sidebarItem.isCollapsed
    }

    @objc func goBack(_ sender: Any?) {
        if contentMode == .viewer {
            activePanel = .browser
            viewerDidRequestClose(viewerVC)
        }
    }

    @objc func navigatePreviousImage(_ sender: Any?) {
        guard contentMode == .viewer else { return }
        viewerVC.showPrevious()
    }

    @objc func navigateNextImage(_ sender: Any?) {
        guard contentMode == .viewer else { return }
        viewerVC.showNext()
    }

    @objc func toggleFullScreen(_ sender: Any?) {
        window?.toggleFullScreen(sender)
    }

    @objc func openImageEditor(_ sender: Any?) {
        guard contentMode == .viewer, viewerVC.isShowingImage else { return }
        viewerVC.openEditor()
    }

    @objc func toggleSlideshow(_ sender: Any?) {
        guard contentMode == .viewer else { return }
        viewerVC.toggleSlideshow()
    }

    @objc func moveSelected(_ sender: Any?) {
        let urls = activeSelectedURLs()
        if !urls.isEmpty { performMove(urls: urls) }
    }

    @objc func copySelected(_ sender: Any?) {
        let urls = activeSelectedURLs()
        if !urls.isEmpty { performCopy(urls: urls) }
    }

    @objc func duplicateSelected(_ sender: Any?) {
        let urls = activeSelectedURLs()
        if !urls.isEmpty { performDuplicate(urls: urls) }
    }

    @objc func renameSelected(_ sender: Any?) {
        if isSidebarFocused {
            sidebarVC.beginRenamingSelectedItem()
        } else if contentMode == .browser {
            browserVC.beginRenamingSelectedItem()
        }
    }

    @objc func exportCurrentImage(_ sender: Any?) {
        guard let url = activeSelectedURLs().first else { return }
        performExport(url: url)
    }

    @objc func deleteSelected(_ sender: Any?) {
        if isSidebarFocused, sidebarVC.selectedItemIsNonRoot, let url = sidebarVC.selectedItemURL {
            performDelete(urls: [url])
            if contentMode == .viewer {
                viewerVC.removeCurrentImage()
            }
        } else if contentMode == .viewer, let url = viewerVC.currentImageURL {
            performDelete(urls: [url])
            viewerVC.removeCurrentImage()
        } else {
            let urls = browserVC.selectedURLs()
            if !urls.isEmpty { performDelete(urls: urls) }
        }
    }

    @objc func printImage(_ sender: Any?) {
        // 뷰어 모드: 현재 보고 있는 이미지, 브라우저 모드: 선택된 첫 번째 이미지
        var image: NSImage?
        if contentMode == .viewer {
            image = viewerVC.currentImage
        } else if let url = activeSelectedURLs().first {
            image = NSImage(contentsOf: url)
        }
        guard let printImage = image else { return }

        let imageView = NSImageView(frame: NSRect(origin: .zero, size: printImage.size))
        imageView.image = printImage
        imageView.imageScaling = .scaleProportionallyUpOrDown

        let printInfo = NSPrintInfo.shared
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .fit
        printInfo.isHorizontallyCentered = true
        printInfo.isVerticallyCentered = true

        let printOp = NSPrintOperation(view: imageView, printInfo: printInfo)
        printOp.showsPrintPanel = true
        printOp.showsProgressPanel = true
        printOp.run()
    }
}

// MARK: - Menu Validation

extension MainWindowController: NSToolbarItemValidation {

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        if item.itemIdentifier == ToolbarID.compare {
            let imageCount = browserVC.selectedURLs()
                .compactMap { ImageFile(url: $0) }.filter { !$0.isVideo }.count
            return imageCount >= 2
        }
        return true
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let isViewer = contentMode == .viewer

        // 텍스트 편집 중이면 복사/붙여넣기 항상 활성화
        let isEditingText = (window?.firstResponder as? NSTextView)?.isFieldEditor == true

        if menuItem.action == #selector(compareSelected(_:)) {
            let imageCount = browserVC.selectedURLs()
                .compactMap { ImageFile(url: $0) }.filter { !$0.isVideo }.count
            return imageCount >= 2
        }

        if menuItem.action == #selector(toggleBookmarkSelected(_:)) {
            return browserVC.selectedURLs().compactMap { ImageFile(url: $0) }.filter { !$0.isVideo }.count >= 1
        }

        switch menuItem.action {
        // 복사: 텍스트 편집 중이면 활성, 아니면 이미지 선택 필요
        case #selector(copyFiles(_:)):
            if isEditingText { return true }
            return hasActiveImageSelection()

        case #selector(exportCurrentImage(_:)),
             #selector(printImage(_:)):
            return hasActiveImageSelection()

        // 붙여넣기: 텍스트 편집 중이면 활성, 아니면 파일 URL 확인
        case #selector(pasteFiles(_:)):
            if isEditingText { return true }
            guard currentFolderURL != nil else { return false }
            return NSPasteboard.general.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])

        // 선택 필요 (이미지 또는 비루트 폴더)
        case #selector(deleteSelected(_:)),
             #selector(moveSelected(_:)),
             #selector(copySelected(_:)),
             #selector(duplicateSelected(_:)):
            return hasActiveSelection()

        // 이름 변경: 사이드바(비루트) 또는 브라우저 선택
        case #selector(renameSelected(_:)):
            if isSidebarFocused { return sidebarVC.selectedItemIsNonRoot }
            if isViewer { return false }
            return browserVC.hasSelection

        // 이미지 편집: 뷰어 모드 + 이미지 표시 중
        case #selector(openImageEditor(_:)):
            return isViewer && viewerVC.isShowingImage

        // 뷰어 모드에서만 활성
        case #selector(zoomIn(_:)),
             #selector(zoomOut(_:)),
             #selector(zoomActualSize(_:)),
             #selector(zoomFit(_:)),
             #selector(goBack(_:)),
             #selector(navigatePreviousImage(_:)),
             #selector(navigateNextImage(_:)),
             #selector(toggleSlideshow(_:)):
            return isViewer

        // 브라우저 모드에서만 활성
        case #selector(selectAllItems(_:)):
            return !isViewer

        default:
            return true
        }
    }
}

// MARK: - Sort

extension MainWindowController: NSMenuDelegate {

    /// 정렬 메뉴가 열릴 때마다 현재 정렬 상태(체크 표시)를 반영해 재구성한다.
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === sortMenu else { return }
        menu.removeAllItems()

        let labels: [(String, SortKey)] = [
            ("이름", .name),
            ("날짜", .date),
            ("크기", .size),
            ("종류", .kind),
        ]
        let current = AppSettings.shared.sortKey
        for (title, key) in labels {
            let item = NSMenuItem(title: title, action: #selector(sortByMenuItem(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = key
            item.state = (key == current) ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let ascItem = NSMenuItem(title: "오름차순", action: #selector(toggleSortOrder(_:)), keyEquivalent: "")
        ascItem.target = self
        ascItem.state = AppSettings.shared.sortAscending ? .on : .off
        menu.addItem(ascItem)
    }

    @objc func sortByMenuItem(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? SortKey else { return }
        // 같은 기준을 다시 고르면 정렬 방향을 토글 (Finder 동작과 동일)
        if AppSettings.shared.sortKey == key {
            AppSettings.shared.sortAscending.toggle()
        } else {
            AppSettings.shared.sortKey = key
        }
        refreshCurrentFolder()
    }

    @objc func toggleSortOrder(_ sender: Any?) {
        AppSettings.shared.sortAscending.toggle()
        refreshCurrentFolder()
    }
}
