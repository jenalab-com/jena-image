import AppKit

// MARK: - Double-Click Collection View

private final class DoubleClickCollectionView: NSCollectionView {
    var onDoubleClick: ((IndexPath) -> Void)?
    var onClickSelectedItem: ((IndexPath) -> Void)?
    var onDropOnItem: ((_ fileURLs: [URL], _ targetIndexPath: IndexPath) -> Bool)?
    var onDragOverItem: ((_ targetIndex: Int?) -> Void)?
    private var didDrag = false

    override func mouseDown(with event: NSEvent) {
        let clickPoint = convert(event.locationInWindow, from: nil)
        let isDoubleClick = event.clickCount == 2
        let isSingleClick = event.clickCount == 1

        // 싱글 클릭 시 이미 선택된 아이템인지 확인
        let clickedIndexPath = indexPathForItem(at: clickPoint)
        let wasSelected = clickedIndexPath.flatMap { selectionIndexPaths.contains($0) } ?? false

        didDrag = false
        super.mouseDown(with: event)

        guard !didDrag else { return }

        if isDoubleClick, let indexPath = clickedIndexPath {
            onDoubleClick?(indexPath)
        } else if isSingleClick && wasSelected, let indexPath = clickedIndexPath {
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
}

// MARK: - ViewController

final class BrowserViewController: NSViewController {
    weak var delegate: BrowserDelegate?

    private let collectionView = DoubleClickCollectionView()
    private let scrollView = NSScrollView()
    private let emptyLabel = NSTextField(labelWithString: "이 폴더는 비어 있습니다")

    private var contents: [BrowserContent] = []
    private var imageFiles: [ImageFile] = []
    private var currentFolderURL: URL?
    private var thumbnailTask: Task<Void, Never>?
    private var renameWorkItem: DispatchWorkItem?
    private var dropHighlightIndex: Int?

    private let imageService: ImageServiceProtocol
    private let thumbnailCache: ThumbnailCache

    init(imageService: ImageServiceProtocol = ImageService(), thumbnailCache: ThumbnailCache = .shared) {
        self.imageService = imageService
        self.thumbnailCache = thumbnailCache
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        view = NSView()
        setupScrollView()
        setupCollectionView()
        setupEmptyLabel()
        observeFolderColorChanges()
    }

    // MARK: - Public

    func display(folders: [URL], images: [URL]) {
        thumbnailTask?.cancel()

        let folderNodes = folders.map { BrowserContent.folder(FolderNode(url: $0)) }
        let imageItems = images.compactMap { ImageFile(url: $0) }
        imageFiles = imageItems
        contents = folderNodes + imageItems.map { BrowserContent.image($0) }

        emptyLabel.isHidden = !contents.isEmpty
        collectionView.reloadData()
        collectionView.deselectAll(nil)

        loadThumbnails(for: imageItems)
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
        guard let layout = collectionView.collectionViewLayout as? NSCollectionViewFlowLayout else { return }
        let baseWidth: CGFloat = 120
        let baseHeight: CGFloat = 140
        layout.itemSize = NSSize(width: baseWidth * scale, height: baseHeight * scale)
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

    // MARK: - Thumbnail Loading

    private func loadThumbnails(for images: [ImageFile]) {
        let thumbnailSize = CGSize(width: 100, height: 100)

        thumbnailTask = Task { [weak self] in
            guard let self else { return }

            for file in images {
                guard !Task.isCancelled else { return }

                if let cached = self.thumbnailCache.thumbnail(for: file.url) {
                    await MainActor.run { self.updateCellThumbnail(for: file.url, image: cached) }
                    continue
                }

                let result = await self.imageService.generateThumbnail(at: file.url, size: thumbnailSize)
                guard !Task.isCancelled else { return }

                if case .success(let thumbnail) = result {
                    self.thumbnailCache.store(thumbnail, for: file.url)
                    await MainActor.run { self.updateCellThumbnail(for: file.url, image: thumbnail) }
                }
            }
        }
    }

    private func updateCellThumbnail(for url: URL, image: NSImage) {
        guard let index = contents.firstIndex(where: { $0.url == url }) else { return }
        let indexPath = IndexPath(item: index, section: 0)
        guard let item = collectionView.item(at: indexPath) as? BrowserItem else { return }
        item.updateThumbnail(image)
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
            delegate?.browser(self, didRequestViewImage: file.url, inList: imageFiles)
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

    @objc private func contextOpen(_ sender: NSMenuItem) {
        guard let urls = sender.representedObject as? [URL], let url = urls.first else { return }
        if ImageFile(url: url) != nil {
            delegate?.browser(self, didRequestViewImage: url, inList: imageFiles)
        }
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
    }

    private func setupCollectionView() {
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
                return thumbnailCache.thumbnail(for: file.url)
            }
            return nil
        }()

        item.configure(with: content, thumbnail: thumbnail)
        return item
    }
}

// MARK: - NSCollectionViewDelegate

extension BrowserViewController: NSCollectionViewDelegate {
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

        if !urls.isEmpty {
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
