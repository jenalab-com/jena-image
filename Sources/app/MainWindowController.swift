import AppKit

/// 메인 윈도우 컨트롤러 — Feature 간 중재자(Mediator) 역할.
///
/// 책임이 큰 컨트롤러라 기능별로 extension 파일로 분리되어 있다:
/// - `MainWindowController+FileOperations.swift` : 삭제/이동/복사/이름변경/내보내기
/// - `MainWindowController+Actions.swift`        : 툴바·메뉴 @objc 액션, 메뉴 검증
/// - `MainWindowController+Delegates.swift`      : Toolbar/Sidebar/Browser/Viewer 델리게이트
///
/// 본 파일은 코어(생명주기·상태·네비게이션·셋업)만 담는다.
/// 위 extension들이 공유하는 멤버는 같은 모듈 내 다른 파일에서 접근해야 하므로
/// `private`이 아닌 `internal`(기본 접근 수준)로 선언한다.
final class MainWindowController: NSWindowController, NSMenuItemValidation {

    // MARK: - Content Mode

    enum ContentMode {
        case browser
        case viewer
    }

    // MARK: - Toolbar Identifiers

    enum ToolbarID {
        static let toolbar = NSToolbar.Identifier("MainToolbar")
        static let back = NSToolbarItem.Identifier("back")
        static let zoomIn = NSToolbarItem.Identifier("zoomIn")
        static let zoomOut = NSToolbarItem.Identifier("zoomOut")
        static let zoomFit = NSToolbarItem.Identifier("zoomFit")
        static let addFolder = NSToolbarItem.Identifier("addFolder")
        static let sort = NSToolbarItem.Identifier("sort")
    }

    // MARK: - Dependencies

    let fileService: FileServiceProtocol = FileService()
    let imageService: ImageServiceProtocol = ImageService()
    let securityService = SecurityScopeService()
    let folderWatcher = FolderWatcher()

    // MARK: - Child ViewControllers

    let splitViewController = NSSplitViewController()
    let sidebarVC = SidebarViewController()
    let browserVC: BrowserViewController
    let viewerVC: ViewerViewController

    // MARK: - UI

    let statusBar = StatusBarView()

    // MARK: - Active Panel

    enum ActivePanel {
        case sidebar
        case browser
        case viewer
    }

    // MARK: - State

    var currentFolderURL: URL?
    var contentMode: ContentMode = .browser
    var activePanel: ActivePanel = .browser

    // 폴더 변경 디바운스용 (FolderWatcher 콜백에서 사용)
    var folderChangeWorkItem: DispatchWorkItem?

    // 정렬 툴바 메뉴 (열릴 때 menuNeedsUpdate로 현재 상태를 갱신)
    lazy var sortMenu: NSMenu = {
        let menu = NSMenu()
        menu.delegate = self
        return menu
    }()

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

    func removeFolder(_ url: URL) {
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

    func navigateToFolder(_ url: URL) {
        currentFolderURL = url
        folderWatcher.watch(url)
        switchToMode(.browser)

        let sortKey = AppSettings.shared.sortKey
        let ascending = AppSettings.shared.sortAscending
        // 디렉토리 열거를 백그라운드에서 수행해 대용량 폴더에서도 UI를 막지 않는다.
        Task { @MainActor in
            let result = await Task.detached(priority: .userInitiated) { [fileService] in
                fileService.contentsOfFolder(at: url, sortKey: sortKey, ascending: ascending)
            }.value
            // 열거 도중 다른 폴더로 전환했거나 뷰어로 빠졌으면 결과를 폐기 (stale 방지)
            guard self.currentFolderURL == url, self.contentMode == .browser else { return }
            switch result {
            case .success(let contents):
                self.browserVC.display(folders: contents.folders, images: contents.images)
                self.window?.title = url.lastPathComponent
                self.statusBar.update(
                    folderCount: contents.folders.count,
                    imageCount: contents.images.count,
                    selectionCount: 0
                )
            case .failure(let error):
                self.showError(error)
            }
        }
    }

    func switchToMode(_ mode: ContentMode) {
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

    // MARK: - Folder Watcher

    private func setupFolderWatcher() {
        folderWatcher.onChange = { [weak self] changedURL in
            self?.handleFolderChange(at: changedURL)
        }
    }

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

    /// 외부(Finder 등)에서 파일이 변경된 후 앱이 활성화될 때 호출
    func refreshAfterExternalChange() {
        guard let url = currentFolderURL else { return }

        // 뷰어 모드는 디렉토리 열거가 필요 없다.
        if contentMode == .viewer {
            viewerVC.reloadCurrentImage()
            sidebarVC.reloadCurrentFolder()
            return
        }

        // 브라우저 모드: 디렉토리 열거를 백그라운드에서 수행.
        let sortKey = AppSettings.shared.sortKey
        let ascending = AppSettings.shared.sortAscending
        Task { @MainActor in
            let result = await Task.detached(priority: .userInitiated) { [fileService] in
                fileService.contentsOfFolder(at: url, sortKey: sortKey, ascending: ascending)
            }.value
            guard self.currentFolderURL == url, self.contentMode == .browser,
                  case .success(let contents) = result else { return }

            // 기존 선택을 URL로 보존 후 복원 (인덱스가 바뀌어도 올바른 항목 유지)
            let selectedURLs = Set(self.browserVC.selectedURLs())
            self.browserVC.display(folders: contents.folders, images: contents.images)
            if !selectedURLs.isEmpty {
                self.browserVC.restoreSelection(urls: selectedURLs)
            }
            self.statusBar.update(
                folderCount: contents.folders.count,
                imageCount: contents.images.count,
                selectionCount: selectedURLs.count
            )
            self.sidebarVC.reloadCurrentFolder()
        }
    }

    // MARK: - Helpers

    func refreshCurrentFolder() {
        guard let url = currentFolderURL else { return }
        navigateToFolder(url)
        sidebarVC.reloadCurrentFolder()
    }

    func imageFilesInCurrentFolder() -> [ImageFile] {
        guard let url = currentFolderURL,
              case .success(let contents) = fileService.contentsOfFolder(
                at: url,
                sortKey: AppSettings.shared.sortKey,
                ascending: AppSettings.shared.sortAscending
              ) else { return [] }
        return contents.images.compactMap { ImageFile(url: $0) }
    }

    func showError(_ error: Error) {
        let alert = NSAlert(error: error as NSError)
        alert.runModal()
    }

    func updateToolbarState() {
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
