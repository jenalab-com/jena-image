import AppKit

/// 메인 윈도우 컨트롤러 — Feature 간 중재자(Mediator) 역할
final class MainWindowController: NSWindowController, NSMenuItemValidation {

    // MARK: - Content Mode

    private enum ContentMode {
        case browser
        case viewer
    }

    // MARK: - Toolbar Identifiers

    private enum ToolbarID {
        static let toolbar = NSToolbar.Identifier("MainToolbar")
        static let back = NSToolbarItem.Identifier("back")
        static let zoomIn = NSToolbarItem.Identifier("zoomIn")
        static let zoomOut = NSToolbarItem.Identifier("zoomOut")
        static let zoomFit = NSToolbarItem.Identifier("zoomFit")
        static let addFolder = NSToolbarItem.Identifier("addFolder")
    }

    // MARK: - Dependencies

    private let fileService: FileServiceProtocol = FileService()
    private let imageService: ImageServiceProtocol = ImageService()
    private let securityService = SecurityScopeService()
    private let folderWatcher = FolderWatcher()

    // MARK: - Child ViewControllers

    private let splitViewController = NSSplitViewController()
    private let sidebarVC = SidebarViewController()
    private let browserVC: BrowserViewController
    private let viewerVC: ViewerViewController

    // MARK: - UI

    private let statusBar = StatusBarView()

    // MARK: - Active Panel

    private enum ActivePanel {
        case sidebar
        case browser
        case viewer
    }

    // MARK: - State

    private var currentFolderURL: URL?
    private var contentMode: ContentMode = .browser
    private var activePanel: ActivePanel = .browser

    // MARK: - Init

    init() {
        browserVC = BrowserViewController(imageService: imageService)
        viewerVC = ViewerViewController(imageService: imageService)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 750),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "JenaImage"
        window.titlebarAppearsTransparent = false
        window.titleVisibility = .visible
        window.toolbarStyle = .unified
        window.minSize = NSSize(width: 700, height: 500)
        window.setFrameAutosaveName("MainWindow")
        if !window.setFrameUsingName("MainWindow") {
            window.center()
        }

        super.init(window: window)

        setupToolbar()
        setupDelegates()
        setupLayout()
        setupFolderWatcher()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Window Lifecycle

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        restoreOrRequestFolder()
    }

    // MARK: - Folder Access

    private func restoreOrRequestFolder() {
        let urls = securityService.restoreBookmarks()
        for url in urls {
            securityService.startAccessing(url)
        }
        sidebarVC.setFolders(urls)
        if let first = urls.first {
            navigateToFolder(first)
        } else {
            addFolder(nil)
        }
    }

    @objc func addFolder(_ sender: Any?) {
        guard let url = securityService.requestFolderAccess() else { return }
        securityService.startAccessing(url)
        sidebarVC.addFolder(url)
        navigateToFolder(url)
    }

    private func removeFolder(_ url: URL) {
        securityService.stopAccessing(url)
        securityService.removeBookmark(for: url)
        sidebarVC.removeFolder(at: url)
        // 현재 보고 있던 폴더가 제거되면 첫 번째 폴더로 이동
        if currentFolderURL?.path.hasPrefix(url.path) == true {
            if let first = securityService.restoreBookmarks().first {
                navigateToFolder(first)
            } else {
                currentFolderURL = nil
                browserVC.display(folders: [], images: [])
                window?.title = "JenaImage"
            }
        }
    }

    // MARK: - Navigation

    private func navigateToFolder(_ url: URL) {
        currentFolderURL = url
        folderWatcher.watch(url)
        switchToMode(.browser)

        let result = fileService.contentsOfFolder(at: url)
        switch result {
        case .success(let contents):
            browserVC.display(folders: contents.folders, images: contents.images)
            window?.title = url.lastPathComponent
            statusBar.update(
                folderCount: contents.folders.count,
                imageCount: contents.images.count,
                selectionCount: 0
            )
        case .failure(let error):
            showError(error)
        }
    }

    private func switchToMode(_ mode: ContentMode) {
        guard contentMode != mode else { return }
        contentMode = mode

        // NSSplitViewItem.viewController는 교체 불가 — item 자체를 교체
        let oldItem = splitViewController.splitViewItems.last!
        splitViewController.removeSplitViewItem(oldItem)

        let newVC: NSViewController
        switch mode {
        case .browser:
            newVC = browserVC
            statusBar.setViewerMode(false)
        case .viewer:
            newVC = viewerVC
            statusBar.setViewerMode(true)
        }

        let newItem = NSSplitViewItem(viewController: newVC)
        newItem.minimumThickness = 400
        splitViewController.addSplitViewItem(newItem)

        updateToolbarState()
    }

    // MARK: - File Operations

    private func performDelete(urls: [URL]) {
        let count = urls.count
        let alert = NSAlert()
        alert.messageText = "\(count)개 항목을 휴지통으로 이동하시겠습니까?"
        alert.informativeText = "이 작업은 취소할 수 있습니다."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "삭제")
        alert.addButton(withTitle: "취소")
        alert.buttons.first?.keyEquivalent = "\r"

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        // 삭제 대상 폴더의 watcher 해제
        for url in urls {
            folderWatcher.unwatch(url)
        }

        var failedURLs: [URL] = []
        for url in urls {
            if case .failure = fileService.trashFile(at: url) {
                failedURLs.append(url)
            } else {
                ThumbnailCache.shared.invalidate(for: url)
            }
        }

        if !failedURLs.isEmpty {
            showError(FileServiceError.operationFailed("일부 파일을 삭제할 수 없습니다"))
        }

        // 현재 폴더가 삭제되었으면 부모로 이동
        let parentFolders = Set(urls.map { $0.deletingLastPathComponent() })
        if let current = currentFolderURL, urls.contains(where: { current.path.hasPrefix($0.path) }) {
            if let parent = parentFolders.first {
                navigateToFolder(parent)
            }
        } else {
            refreshCurrentFolder()
        }
        for folder in parentFolders {
            sidebarVC.reloadFolder(at: folder)
        }
    }

    private func performMove(urls: [URL]) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.prompt = "이동"
        panel.message = "이동할 폴더를 선택하세요"

        guard panel.runModal() == .OK, let target = panel.url else { return }
        performMoveToFolder(urls: urls, target: target)
    }

    private func performMoveToFolder(urls: [URL], target: URL) {
        let sourceFolders = Set(urls.map { $0.deletingLastPathComponent() })

        for url in urls {
            let result = fileService.moveFile(from: url, to: target)
            switch result {
            case .success:
                ThumbnailCache.shared.invalidate(for: url)
            case .failure(let error):
                if case .nameConflict = error {
                    handleFileConflict(source: url, target: target, isMove: true)
                } else {
                    showError(error)
                }
            }
        }
        refreshCurrentFolder()
        sidebarVC.reloadFolder(at: target)
        for sourceFolder in sourceFolders {
            if sourceFolder != target {
                sidebarVC.reloadFolder(at: sourceFolder)
            }
        }
    }

    private func performCopy(urls: [URL]) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.prompt = "복사"
        panel.message = "복사할 폴더를 선택하세요"

        guard panel.runModal() == .OK, let target = panel.url else { return }

        for url in urls {
            let result = fileService.copyFile(from: url, to: target)
            if case .failure(let error) = result {
                if case .nameConflict = error {
                    handleFileConflict(source: url, target: target, isMove: false)
                } else {
                    showError(error)
                }
            }
        }
    }

    private func performRename(url: URL, newName: String) {
        let result = fileService.renameFile(at: url, newName: newName)
        switch result {
        case .success(let newURL):
            ThumbnailCache.shared.invalidate(for: url)
            if contentMode == .viewer {
                viewerVC.updateCurrentImage(oldURL: url, newURL: newURL)
            }
            refreshCurrentFolder()
            let parentFolder = url.deletingLastPathComponent()
            sidebarVC.reloadFolder(at: parentFolder)
        case .failure(let error):
            showError(error)
        }
    }

    private func performExport(url: URL) {
        Task { @MainActor in
            let loadResult = await imageService.loadImage(at: url)
            guard case .success(let image) = loadResult else {
                showError(ImageServiceError.loadFailed(url))
                return
            }

            let panel = NSSavePanel()
            panel.nameFieldStringValue = url.lastPathComponent

            let accessory = ExportAccessoryView()
            if let currentFormat = ImageFormat.from(extension: url.pathExtension) {
                accessory.selectedFormat = currentFormat
            }
            panel.accessoryView = accessory

            guard panel.runModal() == .OK, let saveURL = panel.url else { return }

            let format = accessory.selectedFormat
            let quality = accessory.quality
            let exportResult = self.imageService.exportImage(image, to: saveURL, format: format, quality: quality)

            if case .failure(let error) = exportResult {
                showError(error)
            }
        }
    }

    private func handleFileConflict(source: URL, target: URL, isMove: Bool) {
        let fileName = source.lastPathComponent
        let alert = NSAlert()
        alert.messageText = "'\(fileName)' 파일이 이미 존재합니다."
        alert.addButton(withTitle: "이름 변경")
        alert.addButton(withTitle: "덮어쓰기")
        alert.addButton(withTitle: "건너뛰기")

        let response = alert.runModal()
        let destination = target.appendingPathComponent(fileName)

        switch response {
        case .alertFirstButtonReturn:
            let newName = generateUniqueName(for: fileName, in: target)
            let newDest = target.appendingPathComponent(newName)
            if isMove {
                try? FileManager.default.moveItem(at: source, to: newDest)
            } else {
                try? FileManager.default.copyItem(at: source, to: newDest)
            }
        case .alertSecondButtonReturn:
            try? FileManager.default.removeItem(at: destination)
            if isMove {
                try? FileManager.default.moveItem(at: source, to: destination)
            } else {
                try? FileManager.default.copyItem(at: source, to: destination)
            }
        default: break
        }
    }

    private func generateUniqueName(for name: String, in folder: URL) -> String {
        let baseName = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var counter = 2

        while true {
            let candidate = ext.isEmpty ? "\(baseName) \(counter)" : "\(baseName) \(counter).\(ext)"
            let candidateURL = folder.appendingPathComponent(candidate)
            if !fileService.fileExists(at: candidateURL) { return candidate }
            counter += 1
        }
    }

    // MARK: - Toolbar Actions

    @objc private func toolbarBack(_ sender: Any?) {
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

    // MARK: - Active Selection Helper

    /// 사이드바에 포커스가 있는지 (first responder 기준)
    private var isSidebarFocused: Bool {
        sidebarVC.isFocused
    }

    /// 현재 활성 패널에 따른 선택된 URL 목록
    private func activeSelectedURLs() -> [URL] {
        if isSidebarFocused, let url = sidebarVC.selectedItemURL {
            return [url]
        }
        if contentMode == .viewer, let url = viewerVC.currentImageURL {
            return [url]
        }
        return browserVC.selectedURLs()
    }

    /// 현재 활성 패널에 선택된 항목이 있는지
    private func hasActiveSelection() -> Bool {
        if isSidebarFocused { return sidebarVC.selectedItemIsNonRoot }
        if contentMode == .viewer { return viewerVC.currentImageURL != nil }
        return !browserVC.selectedURLs().isEmpty
    }

    /// 현재 활성 패널에 이미지가 선택되어 있는지
    private func hasActiveImageSelection() -> Bool {
        if isSidebarFocused { return sidebarVC.selectedItemIsImage }
        if contentMode == .viewer { return viewerVC.currentImageURL != nil }
        return !browserVC.selectedURLs().isEmpty
    }

    // MARK: - Menu Actions

    @objc func revealInFinder(_ sender: Any?) {
        let urls = activeSelectedURLs()
        if !urls.isEmpty {
            NSWorkspace.shared.activateFileViewerSelecting(urls)
        } else if let folder = currentFolderURL {
            NSWorkspace.shared.activateFileViewerSelecting([folder])
        }
    }

    @objc func copyFiles(_ sender: Any?) {
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

    // MARK: - Image Editing Actions

    @objc func openImageEditor(_ sender: Any?) {
        guard contentMode == .viewer, viewerVC.isShowingImage else { return }
        viewerVC.openEditor()
    }

    @objc func moveSelected(_ sender: Any?) {
        let urls = activeSelectedURLs()
        if !urls.isEmpty { performMove(urls: urls) }
    }

    @objc func copySelected(_ sender: Any?) {
        let urls = activeSelectedURLs()
        if !urls.isEmpty { performCopy(urls: urls) }
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

    // MARK: - Menu Validation

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let isViewer = contentMode == .viewer

        switch menuItem.action {
        // 이미지 선택 필요 (클립보드 복사, 내보내기)
        case #selector(copyFiles(_:)),
             #selector(exportCurrentImage(_:)),
             #selector(printImage(_:)):
            return hasActiveImageSelection()

        // 붙여넣기: 현재 폴더가 있고 클립보드에 파일 URL이 있을 때
        case #selector(pasteFiles(_:)):
            guard currentFolderURL != nil else { return false }
            return NSPasteboard.general.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])

        // 선택 필요 (이미지 또는 비루트 폴더)
        case #selector(deleteSelected(_:)),
             #selector(moveSelected(_:)),
             #selector(copySelected(_:)):
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
             #selector(navigateNextImage(_:)):
            return isViewer

        // 브라우저 모드에서만 활성
        case #selector(selectAllItems(_:)):
            return !isViewer

        default:
            return true
        }
    }

    // MARK: - Folder Watcher

    private func setupFolderWatcher() {
        folderWatcher.onChange = { [weak self] changedURL in
            self?.handleFolderChange(at: changedURL)
        }
    }

    private var folderChangeWorkItem: DispatchWorkItem?

    private func handleFolderChange(at url: URL) {
        // 짧은 시간 내 연속 이벤트를 하나로 합침 (디바운스)
        folderChangeWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            // 폴더가 삭제된 경우 무시
            guard FileManager.default.fileExists(atPath: url.path) else {
                self.folderWatcher.unwatch(url)
                return
            }
            self.sidebarVC.reloadFolder(at: url)
            if url == self.currentFolderURL {
                self.refreshAfterExternalChange()
            }
        }
        folderChangeWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
    }

    // MARK: - External Change

    /// 외부(Finder 등)에서 파일이 변경된 후 앱이 활성화될 때 호출
    func refreshAfterExternalChange() {
        guard let url = currentFolderURL else { return }
        let result = fileService.contentsOfFolder(at: url)
        guard case .success(let contents) = result else { return }

        if contentMode == .browser {
            browserVC.display(folders: contents.folders, images: contents.images)
            statusBar.update(
                folderCount: contents.folders.count,
                imageCount: contents.images.count,
                selectionCount: 0
            )
        } else if contentMode == .viewer {
            viewerVC.reloadCurrentImage()
        }
        sidebarVC.reloadCurrentFolder()
    }

    // MARK: - Helpers

    private func refreshCurrentFolder() {
        guard let url = currentFolderURL else { return }
        navigateToFolder(url)
        sidebarVC.reloadCurrentFolder()
    }

    private func imageFilesInCurrentFolder() -> [ImageFile] {
        guard let url = currentFolderURL,
              case .success(let contents) = fileService.contentsOfFolder(at: url) else { return [] }
        return contents.images.compactMap { ImageFile(url: $0) }
    }

    private func showError(_ error: Error) {
        let alert = NSAlert(error: error as NSError)
        alert.runModal()
    }

    private func updateToolbarState() {
        guard let toolbar = window?.toolbar else { return }
        for item in toolbar.items {
            switch item.itemIdentifier {
            case ToolbarID.back:
                item.isEnabled = contentMode == .viewer
            case ToolbarID.zoomIn, ToolbarID.zoomOut, ToolbarID.zoomFit:
                item.isEnabled = contentMode == .viewer
            default: break
            }
        }
    }

    // MARK: - Setup

    private func setupToolbar() {
        let toolbar = NSToolbar(identifier: ToolbarID.toolbar)
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window?.toolbar = toolbar
    }

    private func setupDelegates() {
        sidebarVC.delegate = self
        browserVC.delegate = self
        viewerVC.delegate = self

        statusBar.onThumbnailScaleChanged = { [weak self] scale in
            self?.browserVC.updateThumbnailScale(scale)
        }
        statusBar.onFlipHorizontal = { [weak self] in
            self?.viewerVC.flipHorizontal()
        }
        statusBar.onFlipVertical = { [weak self] in
            self?.viewerVC.flipVertical()
        }
        statusBar.onRotateLeft = { [weak self] in
            self?.viewerVC.rotateLeft()
        }
        statusBar.onRotateRight = { [weak self] in
            self?.viewerVC.rotateRight()
        }
        statusBar.onResetFlip = { [weak self] in
            self?.viewerVC.resetFlip()
        }
    }

    private func setupLayout() {
        // Split view
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarVC)
        sidebarItem.minimumThickness = 200
        sidebarItem.maximumThickness = 300

        let contentItem = NSSplitViewItem(viewController: browserVC)
        contentItem.minimumThickness = 400

        splitViewController.addSplitViewItem(sidebarItem)
        splitViewController.addSplitViewItem(contentItem)

        // Container with status bar
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        splitViewController.view.translatesAutoresizingMaskIntoConstraints = false
        statusBar.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(splitViewController.view)
        container.addSubview(statusBar)

        NSLayoutConstraint.activate([
            splitViewController.view.topAnchor.constraint(equalTo: container.topAnchor),
            splitViewController.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            splitViewController.view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            splitViewController.view.bottomAnchor.constraint(equalTo: statusBar.topAnchor),
            statusBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            statusBar.heightAnchor.constraint(equalToConstant: 22),
        ])

        let containerVC = NSViewController()
        containerVC.view = container
        containerVC.addChild(splitViewController)
        window?.contentViewController = containerVC
    }
}

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
            ToolbarID.addFolder,
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

        case ToolbarID.addFolder:
            item.label = "폴더 추가"
            item.toolTip = "사이드바에 폴더 추가"
            item.image = NSImage(systemSymbolName: "folder.badge.plus", accessibilityDescription: "폴더 추가")
            item.action = #selector(addFolder(_:))
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
