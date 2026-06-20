import AppKit

// MARK: - NSToolbarDelegate

extension MainWindowController: NSToolbarDelegate {
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            ToolbarID.back,
            .flexibleSpace,
            ToolbarID.zoomOut,
            ToolbarID.zoomIn,
            ToolbarID.zoomFit,
            .flexibleSpace,
            ToolbarID.sort,
            ToolbarID.addFolder,
            ToolbarID.compare,
        ]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)

        switch itemIdentifier {
        case ToolbarID.back:
            item.label = "뒤로"
            item.toolTip = "브라우저로 돌아가기"
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

        case ToolbarID.zoomFit:
            item.label = "맞춤"
            item.toolTip = "화면에 맞춤"
            item.image = NSImage(systemSymbolName: "arrow.up.left.and.arrow.down.right", accessibilityDescription: "맞춤")
            item.action = #selector(zoomFit(_:))
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

        case ToolbarID.addFolder:
            item.label = "폴더 추가"
            item.toolTip = "사이드바에 폴더 추가"
            item.image = NSImage(systemSymbolName: "folder.badge.plus", accessibilityDescription: "폴더 추가")
            item.action = #selector(addFolder(_:))
            item.target = self

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
        if currentFolderURL != url {
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
}

// MARK: - ViewerDelegate

extension MainWindowController: ViewerDelegate {
    func viewerDidRequestClose(_ viewer: ViewerViewController) {
        switchToMode(.browser)
        if let url = currentFolderURL {
            window?.title = url.lastPathComponent
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
        sidebarVC.selectFile(at: url)
    }

    func viewerDidEndEditing(_ viewer: ViewerViewController) {
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
