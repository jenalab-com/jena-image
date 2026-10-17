import AppKit
import Quartz

// MARK: - Double-Click Collection View

private final class DoubleClickCollectionView: NSCollectionView {
    var onDoubleClick: ((IndexPath) -> Void)?
    var onClickSelectedItem: ((IndexPath) -> Void)?
    var onDropOnItem: ((_ fileURLs: [URL], _ targetIndexPath: IndexPath) -> Bool)?
    var onDragOverItem: ((_ targetIndex: Int?) -> Void)?
    var onSpaceKey: (() -> Void)?
    private var didDrag = false

    override func keyDown(with event: NSEvent) {
        // 스페이스바 → QuickLook 미리보기 (keyCode 49 = space)
        if event.keyCode == 49 {
            onSpaceKey?()
        } else {
            super.keyDown(with: event)
        }
    }

    /// 우클릭한 항목이 선택에 없으면 그 항목만 선택한 뒤 메뉴를 띄운다 (Finder 동작).
    /// 이미 선택된 항목 위에서 우클릭하면 다중 선택을 유지한다.
    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        if let indexPath = indexPathForItem(at: point) {
            if !selectionIndexPaths.contains(indexPath) {
                deselectAll(nil)
                selectItems(at: [indexPath], scrollPosition: [])
            }
        } else {
            // 빈 곳 우클릭: 선택 해제 → 빈 영역용 메뉴(새 폴더 등)
            deselectAll(nil)
        }
        return super.menu(for: event)
    }

    // MARK: 선택 앵커 (Finder 방식 Shift 범위 선택)

    /// 마지막으로 수정키 없이 또는 Cmd로 클릭한 항목. Shift 클릭은 여기서부터 클릭한 항목까지를 선택한다.
    private var selectionAnchor: IndexPath?
    /// 앵커를 찍은 직후의 선택 집합. Shift 범위는 여기에 합쳐져, Cmd로 골라둔 다른 항목이 유지된다(Finder 동작).
    private var anchorSelection: Set<IndexPath> = []

    /// 목록이 바뀌면(폴더 이동·북마크 보기 등) 앵커는 의미가 없다.
    func resetSelectionAnchor() {
        selectionAnchor = nil
        anchorSelection = []
    }

    override func mouseDown(with event: NSEvent) {
        let clickPoint = convert(event.locationInWindow, from: nil)
        let isDoubleClick = event.clickCount == 2
        let isSingleClick = event.clickCount == 1
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isShift = flags.contains(.shift)
        let isCommand = flags.contains(.command)

        let clickedIndexPath = indexPathForItem(at: clickPoint)
        let wasSelected = clickedIndexPath.flatMap { selectionIndexPaths.contains($0) } ?? false

        // Shift 클릭: 앵커 ~ 클릭 항목 범위를 앵커 시점 선택에 합친다. 기본 구현(토글)은 타지 않는다.
        if isSingleClick, isShift, !isCommand, allowsMultipleSelection, let clicked = clickedIndexPath {
            window?.makeFirstResponder(self)
            let count = numberOfItems(inSection: 0)
            let anchor = (selectionAnchor.map { $0.item < count } ?? false) ? selectionAnchor! : clicked
            if selectionAnchor == nil { anchorSelection = selectionIndexPaths; selectionAnchor = clicked }
            let lo = min(anchor.item, clicked.item), hi = max(anchor.item, clicked.item)
            let range = Set((lo...hi).map { IndexPath(item: $0, section: 0) })
            selectionIndexPaths = anchorSelection.union(range)
            return
        }

        didDrag = false
        super.mouseDown(with: event)  // 일반 클릭(단일 선택)·Cmd 클릭(토글)·드래그는 기본 구현

        guard !didDrag else { return }

        // 수정키 없는 클릭과 Cmd 클릭이 다음 Shift 범위의 앵커가 된다.
        if isSingleClick, let clicked = clickedIndexPath {
            selectionAnchor = clicked
            anchorSelection = selectionIndexPaths
        }

        if isDoubleClick, let indexPath = clickedIndexPath {
            onDoubleClick?(indexPath)
        } else if isSingleClick && wasSelected && !isCommand && !isShift, let indexPath = clickedIndexPath {
            // 수정키가 있으면 선택 조정이지 "이름 변경" 의도가 아니다
            onClickSelectedItem?(indexPath)
        }
    }

    override func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
        didDrag = true
        super.draggingSession(session, willBeginAt: screenPoint)
    }

    // MARK: - Drop Handling

    private func itemIndexPath(at windowPoint: NSPoint) -> IndexPath? {
        guard let layout = collectionViewLayout as? NSCollectionViewFlowLayout else { return nil }
        let point = convert(windowPoint, from: nil)

        let inset = layout.sectionInset
        let itemW = layout.itemSize.width
        let itemH = layout.itemSize.height
        let gapX = layout.minimumInteritemSpacing
        let gapY = layout.minimumLineSpacing

        let x = point.x - inset.left
        let y = point.y - inset.top
        guard x >= 0, y >= 0 else { return nil }

        let col = Int(x / (itemW + gapX))
        let row = Int(y / (itemH + gapY))

        // 아이템 영역 내인지 확인 (간격 제외)
        let cellX = CGFloat(col) * (itemW + gapX)
        let cellY = CGFloat(row) * (itemH + gapY)
        guard x <= cellX + itemW, y <= cellY + itemH else { return nil }

        let contentWidth = bounds.width - inset.left - inset.right
        let cols = max(1, Int((contentWidth + gapX) / (itemW + gapX)))
        let index = row * cols + col

        let total = numberOfItems(inSection: 0)
        guard index >= 0, index < total else { return nil }
        return IndexPath(item: index, section: 0)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        if let indexPath = itemIndexPath(at: sender.draggingLocation) {
            onDragOverItem?(indexPath.item)
            return .move
        }
        onDragOverItem?(nil)
        return super.draggingUpdated(sender)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onDragOverItem?(nil)
        super.draggingExited(sender)
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        onDragOverItem?(nil)
        super.draggingEnded(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        onDragOverItem?(nil)
        guard let indexPath = itemIndexPath(at: sender.draggingLocation) else {
            return super.performDragOperation(sender)
        }

        var fileURLs: [URL] = []
        for item in sender.draggingPasteboard.pasteboardItems ?? [] {
            if let urlString = item.string(forType: .fileURL),
               let url = URL(string: urlString) {
                fileURLs.append(url)
            }
        }

        guard !fileURLs.isEmpty else { return super.performDragOperation(sender) }

        return onDropOnItem?(fileURLs, indexPath) ?? false
    }
}

// MARK: - Delegate

protocol BrowserDelegate: AnyObject {
    func browser(_ browser: BrowserViewController, didOpenFolder url: URL)
    func browser(_ browser: BrowserViewController, didRequestViewImage url: URL, inList: [ImageFile])
    func browser(_ browser: BrowserViewController, didRequestDelete urls: [URL])
    func browser(_ browser: BrowserViewController, didRequestMove urls: [URL])
    func browser(_ browser: BrowserViewController, didRequestCopy urls: [URL])
    func browser(_ browser: BrowserViewController, didRequestRename url: URL, newName: String)
    func browser(_ browser: BrowserViewController, didRequestExport url: URL)
    func browser(_ browser: BrowserViewController, didRequestCreateFolder name: String)
    func browser(_ browser: BrowserViewController, didRequestMoveToFolder urls: [URL], destination: URL)
    func browserDidRequestCompare(_ browser: BrowserViewController, urls: [URL])
    func browserDidToggleBookmark(_ browser: BrowserViewController, urls: [URL])
    func browserDidRequestRemoveBookmark(_ browser: BrowserViewController, urls: [URL])
}

// MARK: - ViewController

final class BrowserViewController: NSViewController {
    weak var delegate: BrowserDelegate?

    /// MainWindowController가 주입하는 북마크 상태 조회 클로저
    var isBookmarkedProvider: ((URL) -> Bool)?

    private let collectionView = DoubleClickCollectionView()
    private let scrollView = NSScrollView()
    private let emptyLabel = NSTextField(labelWithString: "이 폴더는 비어 있습니다")
    private let bookmarkEmptyLabel = NSTextField(labelWithString: "북마크가 비어 있어요")

    private(set) var isBookmarkMode = false
    private var contents: [BrowserContent] = []
    private var imageFiles: [ImageFile] = []
    private var currentFolderURL: URL?
    /// 하위 폴더 포함 보기의 기준 폴더. nil이면 일반 보기(경로 줄 없음).
    private var recursiveRootURL: URL?
    private var thumbnailScale: CGFloat = 1.0

    private var thumbnailMinPixelSize: Int { AppSettings.shared.thumbnailMaxPixel.rawValue }
    private var renameWorkItem: DispatchWorkItem?
    private var dropHighlightIndex: Int?
    /// 선로드(앞뒤 2화면) 요청 토큰. 다음 선로드 때 전부 취소하고 다시 건다.
    private var prefetchTokens: [ThumbnailRequestToken] = []
    private var prefetchWorkItem: DispatchWorkItem?

    private let imageService: ImageServiceProtocol
    private let thumbnailProvider: ThumbnailProvider

    /// `thumbnailProvider`의 기본값을 `.shared`로 두면 기본 인자가 비격리 문맥에서 평가돼 MainActor 경고가 난다.
    /// 그래서 nil을 받아 MainActor인 init 안에서 `.shared`로 푼다.
    init(imageService: ImageServiceProtocol = ImageService(), thumbnailProvider: ThumbnailProvider? = nil) {
        self.imageService = imageService
        self.thumbnailProvider = thumbnailProvider ?? .shared
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        view = NSView()
        setupScrollView()
        setupCollectionView()
        setupEmptyLabel()
        setupBookmarkEmptyLabel()
        observeFolderColorChanges()
    }

    // MARK: - Public

    /// - Parameter recursiveRoot: 하위 폴더 포함 보기의 기준 폴더. 넘기면 각 셀에 기준 폴더 아래 상대 경로 줄이 붙는다.
    func display(folders: [URL], images: [URL], recursiveRoot: URL? = nil) {
        isBookmarkMode = false
        cancelAllThumbnailRequests()
        if recursiveRootURL != recursiveRoot {
            recursiveRootURL = recursiveRoot
            applyItemSize()
        }

        let folderNodes = folders.map { BrowserContent.folder(FolderNode(url: $0)) }
        let imageItems = images.compactMap { ImageFile(url: $0) }
        imageFiles = imageItems
        contents = folderNodes + imageItems.map { BrowserContent.image($0) }

        emptyLabel.isHidden = !contents.isEmpty
        bookmarkEmptyLabel.isHidden = true
        collectionView.reloadData()
        collectionView.deselectAll(nil)
        collectionView.resetSelectionAnchor()

        schedulePrefetch()
    }

    /// 북마크(임의 위치 이미지) 평면 목록을 표시한다.
    func displayBookmarks(_ files: [ImageFile]) {
        isBookmarkMode = true
        cancelAllThumbnailRequests()
        if recursiveRootURL != nil {
            recursiveRootURL = nil
            applyItemSize()
        }
        imageFiles = files
        contents = files.map { BrowserContent.image($0) }
        collectionView.reloadData()
        collectionView.deselectAll(nil)
        collectionView.resetSelectionAnchor()
        schedulePrefetch()
        updateEmptyState()
    }

    private func updateEmptyState() {
        emptyLabel.isHidden = true
        bookmarkEmptyLabel.isHidden = !(isBookmarkMode && contents.isEmpty)
    }

    /// URL 기반으로 선택 복원
    func restoreSelection(urls: Set<URL>) {
        var indexPaths = Set<IndexPath>()
        for (i, content) in contents.enumerated() {
            if urls.contains(content.url) {
                indexPaths.insert(IndexPath(item: i, section: 0))
            }
        }
        collectionView.selectionIndexPaths = indexPaths
    }

    func updateThumbnailScale(_ scale: CGFloat) {
        thumbnailScale = scale
        applyItemSize()
        schedulePrefetch()  // 셀 크기가 바뀌면 화면 분량이 바뀐다
    }

    /// 셀 크기 = 기본 크기 × 배율. 하위 폴더 포함 보기에선 경로 줄 높이만큼 더한다(글자 크기는 고정이므로 배율 미적용).
    private func applyItemSize() {
        guard let layout = collectionView.collectionViewLayout as? NSCollectionViewFlowLayout else { return }
        let base = BrowserItem.itemSize
        let extra: CGFloat = recursiveRootURL == nil ? 0 : BrowserItem.pathLineHeight
        layout.itemSize = NSSize(width: base.width * thumbnailScale, height: base.height * thumbnailScale + extra)
        layout.invalidateLayout()
    }

    var hasSelection: Bool {
        !collectionView.selectionIndexPaths.isEmpty
    }

    func selectedURLs() -> [URL] {
        collectionView.selectionIndexPaths
            .compactMap { contents[safe: $0.item]?.url }
    }

    func selectAllItems() {
        let allIndexPaths = Set((0..<contents.count).map { IndexPath(item: $0, section: 0) })
        collectionView.selectionIndexPaths = allIndexPaths
    }

    func beginRenamingSelectedItem() {
        guard let indexPath = collectionView.selectionIndexPaths.first else { return }
        scheduleRename(at: indexPath)
    }

    // MARK: - Thumbnail Loading (당겨 가기)

    private func cancelAllThumbnailRequests() {
        prefetchWorkItem?.cancel()
        prefetchTokens.removeAll()
        thumbnailProvider.cancelAllPending()
        for case let item as BrowserItem in collectionView.visibleItems() {
            item.thumbnailToken = nil
        }
    }

    /// 셀이 화면에 들어올 때. 메모리 적중이면 동기 완료라 토큰이 nil로 돌아온다.
    private func requestThumbnail(for item: BrowserItem, url: URL) {
        guard !item.hasThumbnail, item.thumbnailToken == nil else { return }
        let token = thumbnailProvider.request(url, minPixel: thumbnailMinPixelSize, priority: .visible) { [weak item] result in
            guard let item, item.representedURL == url else { return }
            item.thumbnailToken = nil
            item.showThumbnailResult(result)
        }
        item.thumbnailToken = token
    }

    private func cancelThumbnail(for item: BrowserItem) {
        if let token = item.thumbnailToken {
            thumbnailProvider.cancel(token)
            item.thumbnailToken = nil
        }
    }

    /// 스크롤이 멈추고 0.1초 뒤, 보이는 범위 앞뒤 2화면 분량을 선로드한다.
    private func schedulePrefetch() {
        prefetchWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.prefetchAroundVisibleRect() }
        prefetchWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
    }

    private func prefetchAroundVisibleRect() {
        for t in prefetchTokens { thumbnailProvider.cancel(t) }
        prefetchTokens.removeAll()

        // 자가 치유: 보이는 셀 중 썸네일도 진행 중인 요청도 없는 것은 다시 건다.
        // (willDisplay/didEndDisplaying 순서 역전, reloadData 경로 등 어떤 이유로 요청이 끊겨도 스크롤 멈춤 뒤 0.1초 안에 회복)
        for case let cell as BrowserItem in collectionView.visibleItems() {
            guard !cell.hasThumbnail, cell.thumbnailToken == nil, let url = cell.representedURL,
                  let indexPath = collectionView.indexPath(for: cell),
                  let content = contents[safe: indexPath.item], case .image = content, content.url == url
            else { continue }
            requestThumbnail(for: cell, url: url)
        }

        let visible = collectionView.visibleRect
        guard visible.height > 0, let layout = collectionView.collectionViewLayout else { return }
        let extended = visible.insetBy(dx: 0, dy: -visible.height * 2)
        let visibleIndexes = Set(collectionView.indexPathsForVisibleItems())
        let targets = layout.layoutAttributesForElements(in: extended)
            .compactMap(\.indexPath)
            .filter { !visibleIndexes.contains($0) }

        let minPixel = thumbnailMinPixelSize
        for indexPath in targets {
            guard let content = contents[safe: indexPath.item], case .image(let file) = content else { continue }
            // 선로드는 메모리 캐시에 채우기만 한다. 셀이 보이게 되면 willDisplay가 적중으로 받아 간다.
            if let token = thumbnailProvider.request(file.url, minPixel: minPixel, priority: .prefetch, completion: { _ in }) {
                prefetchTokens.append(token)
            }
        }
    }

    @objc private func scrollBoundsChanged(_ note: Notification) {
        schedulePrefetch()
    }

    // MARK: - Rename

    private func scheduleRename(at indexPath: IndexPath) {
        renameWorkItem?.cancel()
        guard let content = contents[safe: indexPath.item] else { return }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self,
                  let item = self.collectionView.item(at: indexPath) as? BrowserItem else { return }
            item.beginRename { [weak self] newName in
                guard let self, let newName, !newName.isEmpty else { return }
                self.delegate?.browser(self, didRequestRename: content.url, newName: newName)
            }
        }
        renameWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: workItem)
    }

    // MARK: - Actions

    private func handleDoubleClick(at indexPath: IndexPath) {
        guard let content = contents[safe: indexPath.item] else { return }
        switch content {
        case .folder(let node):
            delegate?.browser(self, didOpenFolder: node.url)
        case .image(let file):
            // 깨진 북마크(파일 없음)는 열기 불가
            guard FileManager.default.fileExists(atPath: file.url.path) else { return }
            let list: [ImageFile]
            if isBookmarkMode {
                list = contents.compactMap { if case .image(let f) = $0 { return f } else { return nil } }
            } else {
                list = imageFiles
            }
            delegate?.browser(self, didRequestViewImage: file.url, inList: list)
        }
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36:  // Enter — 이름 변경 (이미지) 또는 폴더 열기
            handleEnterKey()
        case 51:  // Delete
            let urls = selectedURLs()
            if !urls.isEmpty { delegate?.browser(self, didRequestDelete: urls) }
        default:
            super.keyDown(with: event)
        }
    }

    private func handleEnterKey() {
        guard let indexPath = collectionView.selectionIndexPaths.first,
              let content = contents[safe: indexPath.item] else { return }

        switch content {
        case .folder(let node):
            delegate?.browser(self, didOpenFolder: node.url)
        case .image:
            guard let item = collectionView.item(at: indexPath) as? BrowserItem else { return }
            item.beginRename { [weak self] newName in
                guard let self, let newName, !newName.isEmpty else { return }
                self.delegate?.browser(self, didRequestRename: content.url, newName: newName)
            }
        }
    }

    // MARK: - Context Menu

    private func buildContextMenu(for urls: [URL]) -> NSMenu {
        let menu = NSMenu()

        let hasImages = urls.contains { ImageFile.allSupportedExtensions.contains($0.pathExtension.lowercased()) }

        if urls.count == 1, hasImages {
            menu.addItem(withTitle: "열기", action: #selector(contextOpen(_:)), keyEquivalent: "")
            menu.addItem(NSMenuItem.separator())
            menu.addItem(withTitle: "이름 변경", action: #selector(contextRename(_:)), keyEquivalent: "")
        }

        menu.addItem(withTitle: "복사", action: #selector(contextCopy(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "이동", action: #selector(contextMove(_:)), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "삭제", action: #selector(contextDelete(_:)), keyEquivalent: "")

        if urls.count == 1, hasImages {
            menu.addItem(NSMenuItem.separator())
            menu.addItem(withTitle: "다른 이름으로 저장", action: #selector(contextExport(_:)), keyEquivalent: "")
        }

        for item in menu.items {
            item.target = self
            item.representedObject = urls
        }

        return menu
    }

    /// 우클릭 메뉴 "미리보기" — 선택 항목을 QuickLook 패널(원본 해상도)로 띄운다. 스페이스바와 같은 패널.
    @objc private func contextQuickLook(_ sender: NSMenuItem) {
        showQuickLook()
    }

    @objc private func contextOpen(_ sender: NSMenuItem) {
        guard let urls = sender.representedObject as? [URL], let url = urls.first else { return }
        guard ImageFile(url: url) != nil,
              FileManager.default.fileExists(atPath: url.path) else { return }
        let list: [ImageFile]
        if isBookmarkMode {
            list = contents.compactMap { if case .image(let f) = $0 { return f } else { return nil } }
        } else {
            list = imageFiles
        }
        delegate?.browser(self, didRequestViewImage: url, inList: list)
    }

    @objc private func contextRemoveBookmark(_ sender: NSMenuItem) {
        let urls = selectedURLs()
        guard !urls.isEmpty else { return }
        delegate?.browserDidRequestRemoveBookmark(self, urls: urls)
    }

    @objc private func contextRename(_ sender: NSMenuItem) {
        guard let urls = sender.representedObject as? [URL], let url = urls.first else { return }
        guard let index = contents.firstIndex(where: { $0.url == url }),
              let item = collectionView.item(at: IndexPath(item: index, section: 0)) as? BrowserItem else { return }

        item.beginRename { [weak self] newName in
            guard let self, let newName, !newName.isEmpty else { return }
            self.delegate?.browser(self, didRequestRename: url, newName: newName)
        }
    }

    @objc private func contextCopy(_ sender: NSMenuItem) {
        guard let urls = sender.representedObject as? [URL] else { return }
        delegate?.browser(self, didRequestCopy: urls)
    }

    @objc private func contextMove(_ sender: NSMenuItem) {
        guard let urls = sender.representedObject as? [URL] else { return }
        delegate?.browser(self, didRequestMove: urls)
    }

    @objc private func contextDelete(_ sender: NSMenuItem) {
        guard let urls = sender.representedObject as? [URL] else { return }
        delegate?.browser(self, didRequestDelete: urls)
    }

    @objc private func contextExport(_ sender: NSMenuItem) {
        guard let urls = sender.representedObject as? [URL], let url = urls.first else { return }
        delegate?.browser(self, didRequestExport: url)
    }

    @objc private func contextCompare(_ sender: NSMenuItem) {
        let urls = selectedURLs()
        guard urls.count >= 2 else { return }
        delegate?.browserDidRequestCompare(self, urls: urls)
    }

    @objc private func contextToggleBookmark(_ sender: NSMenuItem) {
        let urls = selectedURLs()
        guard !urls.isEmpty else { return }
        delegate?.browserDidToggleBookmark(self, urls: urls)
    }

    @objc private func contextNewFolder(_ sender: NSMenuItem) {
        let alert = NSAlert()
        alert.messageText = "새 폴더"
        alert.informativeText = "새 폴더의 이름을 입력하세요."
        alert.addButton(withTitle: "생성")
        alert.addButton(withTitle: "취소")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        input.placeholderString = "폴더 이름"
        alert.accessoryView = input
        alert.window.initialFirstResponder = input

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = input.stringValue.trimmingCharacters(in: .whitespaces)
        if name.isEmpty {
            let warn = NSAlert()
            warn.messageText = "폴더 이름을 입력해 주세요."
            warn.alertStyle = .warning
            warn.addButton(withTitle: "확인")
            warn.runModal()
            return
        }
        delegate?.browser(self, didRequestCreateFolder: name)
    }

    // MARK: - Setup

    private func setupScrollView() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.documentView = collectionView
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        // 스크롤이 멈추면 앞뒤 2화면 선로드. 프로그램 스크롤(선택 복원 등)도 bounds 변경으로 잡는다.
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(scrollBoundsChanged), name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
    }

    private func setupCollectionView() {
        collectionView.wantsLayer = true  // 호버 확대 셀의 zPosition이 이웃 셀 위로 적용되도록
        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = BrowserItem.itemSize
        layout.minimumInteritemSpacing = 8
        layout.minimumLineSpacing = 8
        layout.sectionInset = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)

        collectionView.collectionViewLayout = layout
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = true
        collectionView.allowsEmptySelection = true
        collectionView.register(BrowserItem.self, forItemWithIdentifier: BrowserItem.identifier)
        collectionView.dataSource = self
        collectionView.delegate = self

        // 드래그 소스 & 드롭 대상
        collectionView.setDraggingSourceOperationMask(.move, forLocal: true)
        collectionView.registerForDraggedTypes([.fileURL])

        // 더블 클릭
        collectionView.onDoubleClick = { [weak self] indexPath in
            self?.renameWorkItem?.cancel()
            self?.handleDoubleClick(at: indexPath)
        }

        // 이미 선택된 아이템 클릭 → 이름 변경
        collectionView.onClickSelectedItem = { [weak self] indexPath in
            self?.scheduleRename(at: indexPath)
        }

        // 폴더로 드래그 앤 드롭
        collectionView.onDragOverItem = { [weak self] targetIndex in
            self?.handleDragOver(targetIndex: targetIndex)
        }
        collectionView.onDropOnItem = { [weak self] fileURLs, targetIndexPath in
            self?.handleDrop(fileURLs: fileURLs, targetIndexPath: targetIndexPath) ?? false
        }

        // 스페이스바 → QuickLook 미리보기
        collectionView.onSpaceKey = { [weak self] in
            self?.toggleQuickLook()
        }

        // 우클릭 컨텍스트 메뉴
        let menu = NSMenu()
        menu.delegate = self
        collectionView.menu = menu
    }

    private func setupEmptyLabel() {
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.font = .systemFont(ofSize: 14)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.isHidden = true
        view.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    private func setupBookmarkEmptyLabel() {
        bookmarkEmptyLabel.translatesAutoresizingMaskIntoConstraints = false
        bookmarkEmptyLabel.font = .systemFont(ofSize: 14)
        bookmarkEmptyLabel.textColor = .secondaryLabelColor
        bookmarkEmptyLabel.alignment = .center
        bookmarkEmptyLabel.isHidden = true
        view.addSubview(bookmarkEmptyLabel)

        NSLayoutConstraint.activate([
            bookmarkEmptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            bookmarkEmptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }
}

// MARK: - NSCollectionViewDataSource

extension BrowserViewController: NSCollectionViewDataSource {
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        contents.count
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        itemForRepresentedObjectAt indexPath: IndexPath
    ) -> NSCollectionViewItem {
        let item = collectionView.makeItem(
            withIdentifier: BrowserItem.identifier,
            for: indexPath
        ) as! BrowserItem

        let content = contents[indexPath.item]
        let thumbnail: NSImage? = {
            if case .image(let file) = content {
                return thumbnailProvider.cachedThumbnail(for: file.url, minPixel: thumbnailMinPixelSize)
            }
            return nil
        }()

        // 북마크 그리드 자체에선 모두 북마크이므로 배지 생략, 일반 폴더 보기에서만 표시.
        let isBookmarked = !isBookmarkMode && (isBookmarkedProvider?(content.url) ?? false)
        item.configure(
            with: content,
            thumbnail: thumbnail,
            isBookmarked: isBookmarked,
            folderPath: relativeFolderComponents(of: content)
        )
        return item
    }

    /// 하위 폴더 포함 보기에서 기준 폴더 → 파일의 부모 폴더까지의 상대 경로 구성 요소.
    /// 일반 보기이거나 기준 폴더 직속이면 nil(경로 줄 숨김이 아니라 빈 줄 — 셀 높이는 모드 단위로 통일).
    private func relativeFolderComponents(of content: BrowserContent) -> [String]? {
        guard let root = recursiveRootURL, content.isImage else { return nil }
        let rootComps = root.standardizedFileURL.pathComponents
        let parentComps = content.url.deletingLastPathComponent().standardizedFileURL.pathComponents
        guard parentComps.count > rootComps.count,
              Array(parentComps.prefix(rootComps.count)) == rootComps else { return [] }
        return Array(parentComps.dropFirst(rootComps.count))
    }

    /// 북마크 변경 시 그리드의 ★ 배지를 갱신한다(일반 폴더 보기에서 호출).
    func refreshBookmarkIndicators() {
        collectionView.reloadData()
    }
}

// MARK: - NSCollectionViewDelegate

extension BrowserViewController: NSCollectionViewDelegate {
    func collectionView(_ collectionView: NSCollectionView, willDisplay item: NSCollectionViewItem,
                        forRepresentedObjectAt indexPath: IndexPath) {
        guard let cell = item as? BrowserItem,
              let content = contents[safe: indexPath.item],
              case .image(let file) = content
        else { return }
        requestThumbnail(for: cell, url: file.url)
    }

    func collectionView(_ collectionView: NSCollectionView, didEndDisplaying item: NSCollectionViewItem,
                        forRepresentedObjectAt indexPath: IndexPath) {
        guard let cell = item as? BrowserItem else { return }
        // 이 콜백은 셀이 이미 다른 자리에 재사용된 뒤 도착하기도 한다. 그때 취소하면 새 자리의 요청이 끊겨
        // 셀이 다시 스크롤될 때까지 스켈레톤으로 남는다. 셀이 아직 옛 자리의 파일을 보고 있을 때만 취소한다.
        if let content = contents[safe: indexPath.item], cell.representedURL != content.url { return }
        cancelThumbnail(for: cell)
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        pasteboardWriterForItemAt indexPath: IndexPath
    ) -> NSPasteboardWriting? {
        guard let content = contents[safe: indexPath.item], content.isImage else { return nil }
        return content.url as NSURL
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        draggingSession session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        dragOperation operation: NSDragOperation
    ) {
        updateDropHighlight(targetIndex: nil)
    }

    // MARK: - Drop Handling

    private func updateDropHighlight(targetIndex: Int?) {
        if let prev = dropHighlightIndex, prev != targetIndex {
            if let item = collectionView.item(at: IndexPath(item: prev, section: 0)) as? BrowserItem {
                item.setDropHighlight(false)
            }
        }
        if let idx = targetIndex {
            if let item = collectionView.item(at: IndexPath(item: idx, section: 0)) as? BrowserItem {
                item.setDropHighlight(true)
            }
        }
        dropHighlightIndex = targetIndex
    }

    private func handleDragOver(targetIndex: Int?) {
        guard let idx = targetIndex, let content = contents[safe: idx], content.isFolder else {
            updateDropHighlight(targetIndex: nil)
            return
        }
        updateDropHighlight(targetIndex: idx)
    }

    private func handleDrop(fileURLs: [URL], targetIndexPath: IndexPath) -> Bool {
        updateDropHighlight(targetIndex: nil)
        guard let target = contents[safe: targetIndexPath.item], target.isFolder else { return false }
        delegate?.browser(self, didRequestMoveToFolder: fileURLs, destination: target.url)
        return true
    }
}

// MARK: - NSMenuDelegate (우클릭 컨텍스트 메뉴)

extension BrowserViewController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let urls = selectedURLs()

        // ── 북마크 모드 전용 메뉴 ──────────────────────────────────────────────
        if isBookmarkMode {
            if urls.isEmpty { return }

            // 깨진 북마크(파일 없음)가 하나라도 포함되면 열기/이름변경/삭제 비활성화
            let hasBroken = urls.contains { !FileManager.default.fileExists(atPath: $0.path) }

            let openItem = NSMenuItem(title: "열기", action: hasBroken ? nil : #selector(contextOpen(_:)), keyEquivalent: "")
            openItem.target = self
            openItem.representedObject = urls
            menu.addItem(openItem)

            let previewItem = NSMenuItem(title: "미리보기", action: hasBroken ? nil : #selector(contextQuickLook(_:)), keyEquivalent: "")
            previewItem.target = self
            previewItem.representedObject = urls
            menu.addItem(previewItem)

            let removeItem = NSMenuItem(title: "빼기", action: #selector(contextRemoveBookmark(_:)), keyEquivalent: "")
            removeItem.target = self
            removeItem.representedObject = urls
            menu.addItem(removeItem)

            menu.addItem(NSMenuItem.separator())

            if urls.count == 1 {
                let renameItem = NSMenuItem(title: "이름 변경", action: hasBroken ? nil : #selector(contextRename(_:)), keyEquivalent: "")
                renameItem.target = self
                renameItem.representedObject = urls
                menu.addItem(renameItem)
            }

            let deleteItem = NSMenuItem(title: "삭제", action: hasBroken ? nil : #selector(contextDelete(_:)), keyEquivalent: "")
            deleteItem.target = self
            deleteItem.representedObject = urls
            menu.addItem(deleteItem)

            return
        }
        // ──────────────────────────────────────────────────────────────────────

        if !urls.isEmpty {
            let hasImages = urls.contains { ImageFile.allSupportedExtensions.contains($0.pathExtension.lowercased()) }

            if urls.count == 1, hasImages {
                menu.addItem(withTitle: "열기", action: #selector(contextOpen(_:)), keyEquivalent: "")
            }
            if hasImages {
                // 여러 장 선택 시에도 QuickLook 패널에서 ←/→로 순회할 수 있다
                menu.addItem(withTitle: "미리보기", action: #selector(contextQuickLook(_:)), keyEquivalent: "")
            }
            if urls.count == 1, hasImages {
                menu.addItem(NSMenuItem.separator())
                menu.addItem(withTitle: "이름 변경", action: #selector(contextRename(_:)), keyEquivalent: "")
            }

            let nonVideoCount = urls.compactMap { ImageFile(url: $0) }.filter { !$0.isVideo }.count
            if nonVideoCount >= 2 {
                menu.addItem(withTitle: "비교", action: #selector(contextCompare(_:)), keyEquivalent: "")
                menu.addItem(NSMenuItem.separator())
            }

            menu.addItem(withTitle: "복사", action: #selector(contextCopy(_:)), keyEquivalent: "")
            menu.addItem(withTitle: "이동", action: #selector(contextMove(_:)), keyEquivalent: "")
            menu.addItem(NSMenuItem.separator())
            menu.addItem(withTitle: "삭제", action: #selector(contextDelete(_:)), keyEquivalent: "")

            if urls.count == 1, hasImages {
                menu.addItem(NSMenuItem.separator())
                menu.addItem(withTitle: "다른 이름으로 저장", action: #selector(contextExport(_:)), keyEquivalent: "")
            }

            // 폴더 색상 서브메뉴 (폴더 1개 선택 시)
            if urls.count == 1 {
                let isFolder = contents.first(where: { $0.url == urls[0] }).map {
                    if case .folder = $0 { return true } else { return false }
                } ?? false
                if isFolder {
                    menu.addItem(NSMenuItem.separator())
                    let colorItem = NSMenuItem(title: "폴더 색상", action: nil, keyEquivalent: "")
                    colorItem.submenu = FolderColorService.createColorMenu(
                        for: urls[0], target: self, action: #selector(setFolderColor(_:))
                    )
                    menu.addItem(colorItem)
                }
            }

            // 북마크 토글 (이미지가 1장 이상 선택된 경우)
            let imageURLs = urls.filter { ImageFile(url: $0)?.isVideo == false }
            if !imageURLs.isEmpty {
                let allBookmarked = imageURLs.allSatisfy { isBookmarkedProvider?($0) ?? false }
                let title = allBookmarked ? "북마크에서 빼기" : "북마크에 추가"
                menu.addItem(withTitle: title, action: #selector(contextToggleBookmark(_:)), keyEquivalent: "")
            }

            for item in menu.items where item.representedObject == nil {
                item.target = self
                item.representedObject = urls
            }

            menu.addItem(NSMenuItem.separator())
        }

        // 새 폴더 (항상 표시)
        let newFolderItem = NSMenuItem(title: "새 폴더", action: #selector(contextNewFolder(_:)), keyEquivalent: "")
        newFolderItem.target = self
        menu.addItem(newFolderItem)
    }
}

extension BrowserViewController {
    @objc private func setFolderColor(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        FolderColorService.shared.setColorIndex(sender.tag, for: url)
    }

    func observeFolderColorChanges() {
        NotificationCenter.default.addObserver(
            forName: .folderColorChanged, object: nil, queue: .main
        ) { [weak self] _ in
            self?.collectionView.reloadData()
        }
    }
}

// MARK: - Array Safe Subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - QuickLook Preview

extension BrowserViewController {

    /// 스페이스바로 QuickLook 미리보기 패널을 토글한다. (Finder 동작과 동일)
    func toggleQuickLook() {
        guard !contents.isEmpty, let panel = QLPreviewPanel.shared() else { return }
        if QLPreviewPanel.sharedPreviewPanelExists(), panel.isVisible {
            panel.orderOut(nil)
        } else {
            panel.makeKeyAndOrderFront(nil)
        }
    }

    /// 메뉴에서 호출 — 이미 떠 있으면 현재 선택으로 이동만 하고, 아니면 연다.
    func showQuickLook() {
        guard !contents.isEmpty, let panel = QLPreviewPanel.shared() else { return }

        // QuickLook은 첫 응답자에서 시작해 응답자 체인을 올라가며 acceptsPreviewPanelControl을 찾는다.
        // 포커스가 사이드바에 있으면 브라우저까지 오지 못해 "선택된 항목 없음" 빈 패널이 뜨므로,
        // 먼저 그리드로 포커스를 옮기고 패널에 컨트롤러를 다시 찾게 한다.
        view.window?.makeFirstResponder(collectionView)
        if QLPreviewPanel.sharedPreviewPanelExists(), panel.isVisible {
            panel.updateController()
            if let first = collectionView.selectionIndexPaths.min() {
                panel.currentPreviewItemIndex = first.item
            }
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.makeKeyAndOrderFront(nil)
            panel.updateController()
        }
    }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        true
    }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = self
        panel.delegate = self
        // 현재 선택 항목부터 미리보기 시작 (없으면 첫 항목)
        if let first = collectionView.selectionIndexPaths.min() {
            panel.currentPreviewItemIndex = first.item
        }
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
        panel.delegate = nil
    }
}

extension BrowserViewController: QLPreviewPanelDataSource {
    func numberOfPreviewItems(in panel: QLPreviewPanel) -> Int {
        contents.count
    }

    func previewPanel(_ panel: QLPreviewPanel, previewItemAt index: Int) -> QLPreviewItem {
        contents[index].url as NSURL
    }
}

extension BrowserViewController: QLPreviewPanelDelegate {
    /// 미리보기 패널이 떠 있을 때 스페이스바를 다시 누르면 닫는다.
    /// 그 외 키(←→ 등)는 QuickLook 기본 동작(항목 순회)에 맡긴다.
    func previewPanel(_ panel: QLPreviewPanel, handle event: NSEvent) -> Bool {
        if event.type == .keyDown, event.keyCode == 49 {
            panel.orderOut(nil)
            return true
        }
        return false
    }
}
