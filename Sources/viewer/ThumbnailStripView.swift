import AppKit

/// 뷰어 우측 세로 썸네일 목록
final class ThumbnailStripView: NSView {
    var onImageSelected: ((Int) -> Void)?

    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private var images: [ImageFile] = []
    private var selectedIndex: Int = 0

    private let thumbnailCache: ThumbnailCache
    private let imageService: ImageServiceProtocol

    private static let thumbnailSize = CGSize(width: 80, height: 60)
    private static let rowHeight: CGFloat = 76

    init(
        imageService: ImageServiceProtocol = ImageService(),
        thumbnailCache: ThumbnailCache = .shared
    ) {
        self.imageService = imageService
        self.thumbnailCache = thumbnailCache
        super.init(frame: .zero)
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Public

    func display(images: [ImageFile], selectedIndex: Int) {
        self.images = images
        self.selectedIndex = selectedIndex
        tableView.reloadData()
        scrollToSelectedRow()
    }

    func selectImage(at index: Int) {
        guard images.indices.contains(index) else { return }
        selectedIndex = index
        tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        scrollToSelectedRow()
    }

    func selectPrevious() -> Int? {
        guard selectedIndex > 0 else { return nil }
        selectImage(at: selectedIndex - 1)
        return selectedIndex
    }

    func selectNext() -> Int? {
        guard selectedIndex < images.count - 1 else { return nil }
        selectImage(at: selectedIndex + 1)
        return selectedIndex
    }

    // MARK: - Setup

    private func setupViews() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.documentView = tableView
        addSubview(scrollView)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("ThumbnailColumn"))
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = Self.rowHeight
        tableView.dataSource = self
        tableView.delegate = self
        tableView.selectionHighlightStyle = .regular
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    private func scrollToSelectedRow() {
        tableView.scrollRowToVisible(selectedIndex)
    }
}

// MARK: - NSTableViewDataSource

extension ThumbnailStripView: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        images.count
    }
}

// MARK: - NSTableViewDelegate

extension ThumbnailStripView: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let file = images[row]
        let identifier = NSUserInterfaceItemIdentifier("ThumbnailStripCell")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
            ?? createCell(identifier: identifier)

        cell.textField?.stringValue = file.nameWithoutExtension

        if let cached = thumbnailCache.thumbnail(for: file.url) {
            cell.imageView?.image = cached
        } else {
            cell.imageView?.image = nil
            loadThumbnail(for: file, cell: cell)
        }

        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        guard row >= 0, row != selectedIndex else { return }
        selectedIndex = row
        onImageSelected?(row)
    }

    private func createCell(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = identifier

        let imageView = NSImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = .scaleProportionallyUpOrDown
        cell.addSubview(imageView)
        cell.imageView = imageView

        let textField = NSTextField()
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.font = .systemFont(ofSize: 10)
        textField.lineBreakMode = .byTruncatingMiddle
        textField.alignment = .center
        textField.maximumNumberOfLines = 1
        textField.isEditable = false
        textField.isSelectable = false
        textField.isBordered = false
        textField.isBezeled = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        cell.addSubview(textField)
        cell.textField = textField

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: cell.topAnchor, constant: 4),
            imageView.centerXAnchor.constraint(equalTo: cell.centerXAnchor),
            imageView.widthAnchor.constraint(equalToConstant: Self.thumbnailSize.width),
            imageView.heightAnchor.constraint(equalToConstant: Self.thumbnailSize.height),
            textField.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 2),
            textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
        ])

        return cell
    }

    private func loadThumbnail(for file: ImageFile, cell: NSTableCellView) {
        Task { [weak self] in
            guard let self else { return }
            let result = await self.imageService.generateThumbnail(at: file.url, size: Self.thumbnailSize)
            if case .success(let image) = result {
                self.thumbnailCache.store(image, for: file.url)
                await MainActor.run { cell.imageView?.image = image }
            }
        }
    }
}
