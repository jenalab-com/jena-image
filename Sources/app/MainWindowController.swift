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
        static let zoomActualSize = NSToolbarItem.Identifier("zoomActualSize")
        static let zoomFit = NSToolbarItem.Identifier("zoomFit")
        static let zoomFitHeight = NSToolbarItem.Identifier("zoomFitHeight")
        static let zoomFitWidth = NSToolbarItem.Identifier("zoomFitWidth")
        static let sort = NSToolbarItem.Identifier("sort")
        static let ai = NSToolbarItem.Identifier("aiImageGeneration")
        static let compare = NSToolbarItem.Identifier("compare")
        static let layout = NSToolbarItem.Identifier("browserLayout")
        static let share = NSToolbarItem.Identifier("share")
        static let search = NSToolbarItem.Identifier("search")
    }

    // MARK: - Dependencies

    let fileService: FileServiceProtocol
    private let settings: AppSettings
    let imageService: ImageServiceProtocol = ImageService()
    let securityService = SecurityScopeService()
    let folderWatcher = FolderWatcher()
    let bookmarkStore = BookmarkStore()
    let categoryStore: CategoryStore
    let similarityService: ImageSimilarityService
    var similarityTask: Task<Void, Never>?
    var similaritySession: UUID?
    var similarityProgressAlert: NSAlert?
    var similarityPresentation: SimilarityPresentation?
    private var similarityCloseObserver: NSObjectProtocol?

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

    var currentCategoryID: UUID?
    var lastCategoryID: UUID?
    private var folderLoadTask: Task<Void, Never>?
    var folderLoadGeneration = 0 {
        didSet { folderLoadTask?.cancel() }
    }
    var currentFolderURL: URL? { didSet { aiChatVC?.refreshDestination() } }
    var contentMode: ContentMode = .browser
    var activePanel: ActivePanel = .browser

    // 폴더 변경 디바운스용 (FolderWatcher 콜백에서 사용) — 폴더별로 따로 관리해야
    // 서로 다른 폴더의 연속 변경이 서로를 취소하지 않는다.
    var folderChangeWorkItems: [URL: DispatchWorkItem] = [:]

    // 다음 폴더 로드가 끝나면 선택할 URL (클립보드 이미지 저장 직후 새 파일 강조용)
    var pendingSelectionURLs: Set<URL> = []

    // 공유 피커 — 표시 중엔 참조를 유지해야 한다
    var sharingPicker: NSSharingServicePicker?

    // 파일명 검색 상태. 툴바 검색 필드는 모드 전환으로 툴바가 다시 짜여도 한 인스턴스를 유지한다.
    var searchPresentation: SearchPresentation?
    var searchSourceURLs: [URL]?
    var searchToolbarItem: NSSearchToolbarItem?

    // 일괄 내보내기 시트 보관
    var batchExportController: BatchExportWindowController?

    var needsFolderRefreshAfterViewerRename = false
    var aiChatVC: AIChatViewController?
    var aiSplitItem: NSSplitViewItem?

    // 비교 창 보관
    private var compareWindowController: CompareWindowController?

    // 이미지 정보 패널 보관
    private var infoWindowController: ImageInfoWindowController?

    // 정렬 툴바 메뉴 (열릴 때 menuNeedsUpdate로 현재 상태를 갱신)
    lazy var sortMenu: NSMenu = {
        let menu = NSMenu()
        menu.delegate = self
        return menu
    }()

    // MARK: - Init

    init(categoryStore: CategoryStore = CategoryStore(), settings: AppSettings = .shared,
         similarityService: ImageSimilarityService = ImageSimilarityService(),
         fileService: FileServiceProtocol = FileService()) {
        self.fileService = fileService
        self.settings = settings
        self.categoryStore = categoryStore
        self.similarityService = similarityService
        browserVC = BrowserViewController(imageService: imageService, settings: settings)
        viewerVC = ViewerViewController(imageService: imageService)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 750),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "JenaImage"
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.backgroundColor = .windowBackgroundColor
        window.titleVisibility = .visible
        window.toolbarStyle = .unifiedCompact
        window.minSize = NSSize(width: 700, height: 500)
        window.setFrameAutosaveName("MainWindow")
        if !window.setFrameUsingName("MainWindow") {
            window.center()
        }

        super.init(window: window)

        setupToolbar()
        setupDelegates()
        setupLayout()
        setupCategories()
        browserVC.onFindSimilarImage = { [weak self] url in self?.findSimilarImages(to: url) }
        similarityCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            self?.folderLoadGeneration += 1
            self?.clearSimilaritySearch()
        }
        setupFolderWatcher()
        setupThumbnailSettings()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    deinit {
        folderLoadTask?.cancel()
        similarityTask?.cancel()
        if let observer = similarityCloseObserver { NotificationCenter.default.removeObserver(observer) }
    }

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
        syncWatchedFolders()
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

    /// 최근 폴더 메뉴에서 고른 폴더로 이동. 사이드바 루트 아래면 트리에서 펼쳐 선택하고,
    /// 어느 루트에도 속하지 않으면 "폴더 추가"와 같이 루트로 등록한다.
    @objc func openRecentFolder(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            AppSettings.shared.removeRecentFolder(url)
            let alert = NSAlert()
            alert.messageText = "폴더를 찾을 수 없습니다"
            alert.informativeText = "'\(url.path)'이(가) 이동되었거나 삭제되었습니다. 최근 폴더 목록에서 제거했습니다."
            alert.alertStyle = .warning
            alert.runModal()
            return
        }
        if sidebarVC.revealFolder(at: url) {
            navigateToFolder(url)
        } else {
            securityService.addBookmark(for: url)
            securityService.startAccessing(url)
            sidebarVC.addFolder(url)
            navigateToFolder(url)
        }
    }

    @objc func clearRecentFolders(_ sender: Any?) {
        AppSettings.shared.clearRecentFolders()
    }

    /// 선택된 URL들로 비교 창을 연다(2장 이상, 비디오 제외).
    func compareFiles(_ urls: [URL]) {
        let files = urls.compactMap { ImageFile(url: $0) }.filter { !$0.isVideo }
        guard files.count >= 2 else { return }
        let controller = CompareWindowController(files: Array(files.prefix(4)), imageService: ImageService())
        controller.onClose = { [weak self] in self?.compareWindowController = nil }
        controller.showWindow(nil)
        compareWindowController = controller
    }

    @objc func compareSelected(_ sender: Any?) {
        compareFiles(browserVC.selectedURLs())
    }

    func removeFolder(_ url: URL) {
        securityService.stopAccessing(url)
        securityService.removeBookmark(for: url)
        sidebarVC.removeFolder(at: url)
        folderWatcher.unwatch(url)
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
        clearSimilaritySearch()
        clearSearch()
        currentCategoryID = nil
        folderLoadGeneration += 1
        let generation = folderLoadGeneration
        sidebarVC.setCategoryView(false)
        currentFolderURL = url
        settings.addRecentFolder(url)
        syncWatchedFolders()
        switchToMode(.browser)
        browserVC.display(folders: [], images: [])
        browserVC.setFolderLoading(true)
        statusBar.showFolderLoading(foundCount: 0)
        window?.title = "\(url.lastPathComponent) · 탐색 중…"
        let recursive = settings.recursiveBrowsing
        updateToolbarState()

        // 디렉토리 열거를 백그라운드에서 수행해 대용량 폴더에서도 UI를 막지 않는다.
        folderLoadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var previewCount = 0
            let result = await self.enumerateFolderContents(at: url) { [weak self] progress in
                Task { @MainActor [weak self] in
                    guard let self, self.folderLoadGeneration == generation,
                          self.currentFolderURL == url, self.contentMode == .browser,
                          self.browserVC.isFolderLoading else { return }
                    if progress.previewURLs.count > previewCount {
                        previewCount = progress.previewURLs.count
                        let selected = Set(self.browserVC.selectedURLs())
                        self.browserVC.display(folders: [], images: progress.previewURLs, recursiveRoot: url)
                        self.browserVC.restoreSelection(urls: selected)
                        self.browserVC.setFolderLoading(true)
                    }
                    self.statusBar.showFolderLoading(foundCount: progress.imageCount)
                }
            }
            // 열거 도중 다른 폴더로 전환했거나 뷰어로 빠졌으면 결과를 폐기 (stale 방지)
            guard !Task.isCancelled, self.folderLoadGeneration == generation, self.currentFolderURL == url, self.contentMode == .browser else { return }
            switch result {
            case .success(let contents):
                let selected = Set(self.browserVC.selectedURLs()).union(self.pendingSelectionURLs)
                self.browserVC.display(
                    folders: contents.folders,
                    images: contents.images,
                    recursiveRoot: recursive ? url : nil
                )
                self.window?.title = url.lastPathComponent
                self.pendingSelectionURLs = []
                if !selected.isEmpty { self.browserVC.restoreSelection(urls: selected) }
                self.statusBar.update(
                    folderCount: contents.folders.count,
                    imageCount: contents.images.count,
                    selectionCount: self.browserVC.selectedURLs().count
                )
            case .failure(let error):
                self.browserVC.showFolderLoadFailure()
                self.statusBar.update(folderCount: 0, imageCount: 0, selectionCount: 0)
                self.window?.title = url.lastPathComponent
                self.showError(error)
            }
        }
    }

    func switchToMode(_ mode: ContentMode) {
        guard contentMode != mode else { return }
        contentMode = mode
        if mode == .viewer { folderLoadGeneration += 1 }

        // NSSplitViewItem.viewController는 교체 불가 — item 자체를 교체
        let oldItem = splitViewController.splitViewItems[1]
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
        splitViewController.insertSplitViewItem(newItem, at: 1)

        updateToolbarState()
    }

    // MARK: - Thumbnail Settings

    /// 앱 시작 시 저장된 캐시 한도를 반영하고, 설정 창의 "적용"을 받는다.
    func setupThumbnailSettings() {
        ThumbnailProvider.shared.setMemoryLimit(bytes: AppSettings.shared.thumbnailCacheMB * 1024 * 1024)
        NotificationCenter.default.addObserver(
            forName: .thumbnailSettingsApplied, object: nil, queue: .main
        ) { [weak self] _ in
            self?.applyThumbnailSettings()
        }
    }

    /// 한도 갱신 + 캐시 비움 + 현재 폴더 재로드. 비용이 드는 작업이라 실시간이 아니라 "적용" 때만 수행.
    private func applyThumbnailSettings() {
        ThumbnailProvider.shared.setMemoryLimit(bytes: AppSettings.shared.thumbnailCacheMB * 1024 * 1024)
        ThumbnailProvider.shared.clearMemory()
        guard contentMode == .browser else { return }
        refreshAfterExternalChange()
    }

    // MARK: - Folder Watcher

    private func setupFolderWatcher() {
        folderWatcher.onChange = { [weak self] changedURL in
            self?.handleFolderChange(at: changedURL)
        }
    }

    private func handleFolderChange(at url: URL) {
        // 짧은 시간 내 같은 폴더의 연속 이벤트를 하나로 합침 (디바운스)
        folderChangeWorkItems[url]?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.folderChangeWorkItems.removeValue(forKey: url)
            // 폴더 자체가 사라진 경우: 감시를 끊고 부모를 갱신해 목록에서 지운다
            guard FileManager.default.fileExists(atPath: url.path) else {
                self.folderWatcher.unwatch(url)
                self.sidebarVC.reloadFolder(at: url.deletingLastPathComponent())
                return
            }
            self.sidebarVC.reloadFolder(at: url)
            // 새로 생긴 하위 폴더도 바로 감시 대상에 넣는다
            self.syncWatchedFolders()
            if url == self.currentFolderURL {
                self.refreshAfterExternalChange()
            }
        }
        folderChangeWorkItems[url] = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
    }

    /// 감시 대상을 "루트 폴더 + 현재 폴더 + 사이드바에서 펼쳐진 폴더"로 맞춘다.
    /// 접히거나 사라진 폴더는 감시를 해제해 파일 디스크립터가 무한정 늘지 않게 한다.
    func syncWatchedFolders() {
        var targets = Set(sidebarVC.rootFolderURLs)
        targets.formUnion(sidebarVC.expandedFolderURLs)
        if let currentFolderURL { targets.insert(currentFolderURL) }

        for url in folderWatcher.watchedURLs where !targets.contains(url) {
            folderWatcher.unwatch(url)
        }
        for url in targets {
            folderWatcher.watch(url)
        }
    }

    /// 외부(Finder 등)에서 파일이 변경된 후 앱이 활성화될 때 호출
    func refreshAfterExternalChange() {
        if similarityTask != nil { return }
        if browserVC.isSimilarityMode {
            if contentMode == .viewer { viewerVC.reloadCurrentImage() }
            else { refreshSimilarityResults() }
            return
        }
        if browserVC.isSearchMode {
            if contentMode == .viewer { viewerVC.reloadCurrentImage() }
            else { refreshSearchResults() }
            return
        }
        if browserVC.isCategoryMode {
            if contentMode == .viewer { viewerVC.reloadCurrentImage() }
            else { refreshCategories() }
            return
        }
        if browserVC.isBookmarkMode, contentMode == .browser {
            showBookmarks()
            return
        }
        guard let url = currentFolderURL else { return }

        // 뷰어 모드는 디렉토리 열거가 필요 없다.
        if contentMode == .viewer {
            viewerVC.reloadCurrentImage()
            sidebarVC.reloadCurrentFolder()
            return
        }

        // 브라우저 모드: 디렉토리 열거를 백그라운드에서 수행.
        folderLoadGeneration += 1
        let generation = folderLoadGeneration
        folderLoadTask = Task { @MainActor in
            let result = await self.enumerateFolderContents(at: url)
            guard self.folderLoadGeneration == generation,
                  self.currentFolderURL == url, self.contentMode == .browser,
                  case .success(let contents) = result else { return }

            // 기존 선택을 URL로 보존 후 복원 (인덱스가 바뀌어도 올바른 항목 유지)
            let selectedURLs = Set(self.browserVC.selectedURLs())
            self.browserVC.display(
                folders: contents.folders,
                images: contents.images,
                recursiveRoot: AppSettings.shared.recursiveBrowsing ? url : nil
            )
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

    /// 사이드바 북마크 항목 → 메인을 북마크 그리드로 전환.
    func showBookmarks() {
        clearSimilaritySearch()
        clearSearch()
        folderLoadGeneration += 1
        currentCategoryID = nil
        switchToMode(.browser)
        let files = bookmarkStore.bookmarks.compactMap { ImageFile(url: $0) }
        browserVC.displayBookmarks(files)
        updateToolbarState()
        window?.title = "북마크"
        statusBar.update(folderCount: 0, imageCount: files.count, selectionCount: 0)
    }

    // MARK: - Helpers

    /// 사이드바 트리 + 현재 폴더 내용을 모두 디스크 기준으로 다시 읽는다 (⌘⇧R / 사이드바 새로고침 버튼)
    @objc func refreshAll(_ sender: Any?) {
        sidebarVC.reloadAll(sender)
        syncWatchedFolders()
        refreshAfterExternalChange()
    }

    func refreshCurrentFolder() {
        if browserVC.isSimilarityMode { refreshSimilarityResults(); return }
        if browserVC.isSearchMode { refreshSearchResults(); return }
        if browserVC.isCategoryMode {
            if contentMode == .browser { showCategory(currentCategoryID) }
            return
        }
        guard let url = currentFolderURL else { return }
        navigateToFolder(url)
        sidebarVC.reloadCurrentFolder()
    }

    func imageFilesInCurrentFolder() -> [ImageFile] {
        guard let url = currentFolderURL,
              case .success(let contents) = folderContents(at: url) else { return [] }
        return contents.images.compactMap { ImageFile(url: $0) }
    }

    // MARK: - Image Info Panel

    /// 이미지 정보 패널을 연다. 처음 호출할 때 창을 만든다.
    func showInfo(for url: URL) {
        if infoWindowController == nil {
            infoWindowController = ImageInfoWindowController()
        }
        infoWindowController?.show(for: url)
    }

    /// 정보 패널이 열려 있으면 표시 중인 파일을 새 정보로 갱신한다.
    func updateInfoPanelIfNeeded(for url: URL) {
        infoWindowController?.updateIfVisible(for: url)
    }

    // MARK: - Folder Enumeration (일반 / 하위 폴더 포함)

    /// 현재 보기 모드에 맞춰 폴더 내용을 읽는다.
    /// - 일반: 직속 하위 폴더 + 직속 이미지
    /// - 하위 폴더 포함(`AppSettings.recursiveBrowsing`): 폴더 타일 없이, 모든 하위 폴더의 이미지를 평면으로
    func folderContents(at url: URL) -> Result<(folders: [URL], images: [URL]), FileServiceError> {
        let sortKey = AppSettings.shared.sortKey
        let ascending = AppSettings.shared.sortAscending
        if AppSettings.shared.recursiveBrowsing {
            return fileService.recursiveImages(at: url, sortKey: sortKey, ascending: ascending)
                .map { (folders: [], images: $0) }
        }
        return fileService.contentsOfFolder(at: url, sortKey: sortKey, ascending: ascending)
    }

    /// `folderContents(at:)`를 백그라운드 스레드에서 수행한다 (재귀 열거는 특히 오래 걸릴 수 있음).
    private func enumerateFolderContents(at url: URL,
        progress: @escaping (FolderScanProgress) -> Void = { _ in }) async -> Result<(folders: [URL], images: [URL]), FileServiceError> {
        let sortKey = settings.sortKey
        let ascending = settings.sortAscending
        let recursive = settings.recursiveBrowsing
        let task = Task.detached(priority: .userInitiated) { [fileService] () -> Result<(folders: [URL], images: [URL]), FileServiceError> in
            if recursive {
                return fileService.recursiveImages(at: url, sortKey: sortKey, ascending: ascending,
                                                   progress: progress, isCancelled: { Task.isCancelled })
                    .map { (folders: [], images: $0) }
            }
            return fileService.contentsOfFolder(at: url, sortKey: sortKey, ascending: ascending)
        }
        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    func showError(_ error: Error) {
        let alert = NSAlert(error: error as NSError)
        alert.runModal()
    }

    func updateToolbarState() {
        aiChatVC?.refreshDestination()
        guard let toolbar = window?.toolbar else { return }
        let identifiers = toolbarDefaultItemIdentifiers(toolbar)
        if toolbar.items.map(\.itemIdentifier) != identifiers {
            while !toolbar.items.isEmpty { toolbar.removeItem(at: 0) }
            for (index, identifier) in identifiers.enumerated() { toolbar.insertItem(withItemIdentifier: identifier, at: index) }
        }
        syncFitModeSelection()
        for item in toolbar.items {
            switch item.itemIdentifier {
            case ToolbarID.back:
                item.isEnabled = contentMode == .viewer || browserVC.isSimilarityMode || browserVC.isSearchMode
            case ToolbarID.sort:
                item.isEnabled = !browserVC.isSimilarityMode
            case ToolbarID.zoomIn, ToolbarID.zoomOut, ToolbarID.zoomActualSize,
                 ToolbarID.zoomFit, ToolbarID.zoomFitHeight, ToolbarID.zoomFitWidth:
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
        syncFitModeSelection()
    }

    /// 주어진 URL들을 북마크 토글. 모두 북마크돼 있으면 일괄 제거, 아니면 일괄 추가.
    func toggleBookmark(_ urls: [URL]) {
        let images = urls.compactMap { ImageFile(url: $0) }.filter { !$0.isVideo }.map { $0.url }
        guard !images.isEmpty else { return }
        let allBookmarked = images.allSatisfy { bookmarkStore.contains($0) }
        for url in images {
            if allBookmarked { bookmarkStore.remove(url) } else { bookmarkStore.add(url) }
        }
    }

    @objc func toggleBookmarkSelected(_ sender: Any?) {
        toggleBookmark(browserVC.selectedURLs())
    }

    func refreshViewerBookmarkButton() {
        guard let url = viewerVC.currentImageURL else { return }
        viewerVC.updateBookmarkButton(isBookmarked: bookmarkStore.contains(url))
    }

    private func setupDelegates() {
        sidebarVC.delegate = self
        browserVC.delegate = self
        browserVC.onSelectionChanged = { [weak self] urls in
            guard let self, self.aiSplitItem?.isCollapsed == false else { return }
            self.aiChatVC?.selectionChanged(urls)
        }
        viewerVC.delegate = self

        browserVC.isBookmarkedProvider = { [weak self] url in self?.bookmarkStore.contains(url) ?? false }
        viewerVC.onToggleBookmark = { [weak self] url in self?.toggleBookmark([url]) }

        NotificationCenter.default.addObserver(
            forName: .bookmarksChanged, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            if self.browserVC.isBookmarkMode, self.contentMode == .browser {
                self.showBookmarks()
            } else {
                self.browserVC.refreshBookmarkIndicators()  // 폴더 보기의 ★ 배지 갱신
            }
            self.refreshViewerBookmarkButton()
        }

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
        sidebarItem.minimumThickness = 220
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
            statusBar.heightAnchor.constraint(equalToConstant: 28),
        ])

        let containerVC = NSViewController()
        containerVC.view = container
        containerVC.addChild(splitViewController)
        window?.contentViewController = containerVC
    }
}
