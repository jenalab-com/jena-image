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
    private static let nameFont = NSFont.systemFont(ofSize: 10)
    private static let maxNameLines = 3
    /// 셀 좌우 여백(leading 4 + trailing 4)
    private static let nameHorizontalInset: CGFloat = 8
    /// 썸네일 위(4) + 썸네일-텍스트 간격(2) + 텍스트 아래(4)
    private static let rowVerticalPadding: CGFloat = 10

    /// 마지막으로 row 높이를 계산한 테이블 너비. 너비가 바뀌면 재계산한다.
    private var lastLayoutWidth: CGFloat = 0

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

    func reloadThumbnail(at index: Int) {
        guard images.indices.contains(index) else { return }
        tableView.reloadData(forRowIndexes: IndexSet(integer: index), columnIndexes: IndexSet(integer: 0))
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
        tableView.usesAutomaticRowHeights = false
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

    // MARK: - Layout

    override func layout() {
        super.layout()
        // 스플릿 뷰 폭이 바뀌면 이름 줄 수가 달라지므로 row 높이를 다시 계산한다.
        let width = tableView.bounds.width
        guard abs(width - lastLayoutWidth) > 0.5, !images.isEmpty else { return }
        lastLayoutWidth = width
        tableView.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0 ..< images.count))
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

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        let name = images[row].nameWithoutExtension
        return Self.rowVerticalPadding + Self.thumbnailSize.height + nameHeight(for: name)
    }

    /// 주어진 이름을 현재 셀 너비에서 그렸을 때의 텍스트 높이(최대 3줄, 그 이상은 잘림).
    private func nameHeight(for name: String) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: Self.nameFont]
        let singleLine = ("X" as NSString).boundingRect(
            with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        ).height

        let available = max(tableView.bounds.width - Self.nameHorizontalInset, 1)
        let full = (name as NSString).boundingRect(
            with: CGSize(width: available, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        ).height

        let lines = min(max(1, Int((full / singleLine).rounded())), Self.maxNameLines)
        return ceil(singleLine * CGFloat(lines))
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
        textField.font = Self.nameFont
        textField.lineBreakMode = .byTruncatingTail
        textField.usesSingleLineMode = false
        textField.cell?.wraps = true
        textField.alignment = .center
        textField.maximumNumberOfLines = Self.maxNameLines
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
