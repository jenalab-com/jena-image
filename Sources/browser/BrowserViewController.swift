import AppKit

// MARK: - Double-Click Collection View

private final class DoubleClickCollectionView: NSCollectionView {
    var onDoubleClick: ((IndexPath) -> Void)?
    var onClickSelectedItem: ((IndexPath) -> Void)?

    override func mouseDown(with event: NSEvent) {
        let clickPoint = convert(event.locationInWindow, from: nil)
        let isDoubleClick = event.clickCount == 2
        let isSingleClick = event.clickCount == 1

        // 싱글 클릭 시 이미 선택된 아이템인지 확인
        let clickedIndexPath = indexPathForItem(at: clickPoint)
        let wasSelected = clickedIndexPath.flatMap { selectionIndexPaths.contains($0) } ?? false

        super.mouseDown(with: event)

        if isDoubleClick, let indexPath = clickedIndexPath {
            onDoubleClick?(indexPath)
        } else if isSingleClick && wasSelected, let indexPath = clickedIndexPath {
            onClickSelectedItem?(indexPath)
        }
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

        loadThumbnails(for: imageItems)
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

        // 드래그 소스
        collectionView.setDraggingSourceOperationMask(.move, forLocal: true)

        // 더블 클릭
        collectionView.onDoubleClick = { [weak self] indexPath in
            self?.renameWorkItem?.cancel()
            self?.handleDoubleClick(at: indexPath)
        }

        // 이미 선택된 아이템 클릭 → 이름 변경
        collectionView.onClickSelectedItem = { [weak self] indexPath in
            self?.scheduleRename(at: indexPath)
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
}

// MARK: - NSMenuDelegate (우클릭 컨텍스트 메뉴)

extension BrowserViewController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let urls = selectedURLs()
        guard !urls.isEmpty else { return }

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
    }
}

// MARK: - Array Safe Subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
