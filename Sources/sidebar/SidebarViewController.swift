import AppKit

// MARK: - Delegate

protocol SidebarDelegate: AnyObject {
    func sidebar(_ sidebar: SidebarViewController, didSelectFolder url: URL)
    func sidebar(_ sidebar: SidebarViewController, didSelectImage file: ImageFile, inFolder url: URL)
    func sidebar(_ sidebar: SidebarViewController, didReceiveDrop imageURLs: [URL], toFolder url: URL)
    func sidebar(_ sidebar: SidebarViewController, didRequestRename url: URL, newName: String)
    func sidebarDidRequestAddFolder(_ sidebar: SidebarViewController)
    func sidebar(_ sidebar: SidebarViewController, didRequestCreateFolder name: String, in parentURL: URL)
    func sidebar(_ sidebar: SidebarViewController, didRequestRemoveFolder url: URL)
    func sidebar(_ sidebar: SidebarViewController, didRequestDelete urls: [URL])
    func sidebar(_ sidebar: SidebarViewController, didRequestExport url: URL)
}

// MARK: - Click-Aware Outline View

private final class ClickAwareOutlineView: NSOutlineView {
    var onClickSelectedRow: ((Int) -> Void)?

    override func mouseDown(with event: NSEvent) {
        let clickPoint = convert(event.locationInWindow, from: nil)
        let clickedRow = row(at: clickPoint)
        let wasSelected = clickedRow >= 0 && selectedRowIndexes.contains(clickedRow)
        let isSingleClick = event.clickCount == 1

        super.mouseDown(with: event)

        if isSingleClick && wasSelected && clickedRow >= 0 {
            onClickSelectedRow?(clickedRow)
        }
    }
}

// MARK: - ViewController

final class SidebarViewController: NSViewController {
    weak var delegate: SidebarDelegate?

    private let outlineView = ClickAwareOutlineView()
    private let scrollView = NSScrollView()
    private let addButton = NSButton()
    private let showFilesToggle = NSButton()
    private var showFilesInSidebar = true
    private var rootNodes: [FolderNode] = []
    private var renameWorkItem: DispatchWorkItem?
    private var renamingFileExtension: String?
    private var isRenameHandled = false
    private var isSuppressingSelectionDelegate = false

    override func loadView() {
        let visualEffect = NSVisualEffectView()
        visualEffect.material = .sidebar
        visualEffect.blendingMode = .behindWindow
        view = visualEffect
        setupScrollView()
        setupOutlineView()
        setupAddButton()
        setupContextMenu()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        registerDragTypes()
        observeFolderColorChanges()
    }

    // MARK: - Public

    /// 등록된 폴더 목록으로 사이드바 구성
    func setFolders(_ urls: [URL]) {
        rootNodes = urls.map { FolderNode(url: $0) }
        outlineView.reloadData()
    }

    /// 폴더 하나 추가
    func addFolder(_ url: URL) {
        // 중복 방지
        guard !rootNodes.contains(where: { $0.url.standardizedFileURL == url.standardizedFileURL }) else { return }
        rootNodes.append(FolderNode(url: url))
        outlineView.reloadData()
        // 새로 추가된 폴더 선택
        let row = outlineView.row(forItem: rootNodes.last!)
        if row >= 0 {
            outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
    }

    /// 폴더 제거
    func removeFolder(at url: URL) {
        rootNodes.removeAll { $0.url.standardizedFileURL == url.standardizedFileURL }
        outlineView.reloadData()
    }

    func selectFolder(at url: URL) {
        guard let node = findNode(for: url) else { return }
        let row = outlineView.row(forItem: node)
        guard row >= 0 else { return }
        outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
    }

    func selectFile(at url: URL) {
        let folderURL = url.deletingLastPathComponent()

        // 폴더 노드를 찾고 펼침
        guard let folderNode = findNode(for: folderURL) else {
            // 루트에서 해당 폴더까지 경로를 펼침
            expandToSubfolder(folderURL)
            guard let node = findNode(for: folderURL) else { return }
            selectFileInNode(node, fileURL: url)
            return
        }

        if !outlineView.isItemExpanded(folderNode) {
            outlineView.expandItem(folderNode)
        }
        selectFileInNode(folderNode, fileURL: url)
    }

    private func selectFileInNode(_ node: FolderNode, fileURL: URL) {
        node.loadChildren()
        // struct 아이템은 row(forItem:)으로 찾기 어려우므로 행 순회
        let nodeRow = outlineView.row(forItem: node)
        guard nodeRow >= 0 else { return }
        let childCount = node.totalChildCount
        for offset in 1...childCount {
            let row = nodeRow + offset
            guard row < outlineView.numberOfRows else { break }
            if let file = outlineView.item(atRow: row) as? ImageFile, file.url == fileURL {
                isSuppressingSelectionDelegate = true
                outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                isSuppressingSelectionDelegate = false
                outlineView.scrollRowToVisible(row)
                return
            }
        }
    }

    func reloadCurrentFolder() {
        guard let selected = selectedFolderNode() else { return }
        selected.invalidateChildren()
        selected.loadChildren()
        outlineView.reloadItem(selected, reloadChildren: true)
    }

    func reloadFolder(at url: URL) {
        guard let node = findNode(for: url) else { return }
        node.invalidateChildren()
        node.loadChildren()
        outlineView.reloadItem(node, reloadChildren: true)
    }

    /// 루트 노드에서 하위 폴더까지 순차적으로 펼침
    private func expandToSubfolder(_ url: URL) {
        let rootNode = rootNodes.first { url.path.hasPrefix($0.url.path) }
        guard let rootNode else { return }

        var pathComponents: [URL] = []
        var current = url
        while current.path != rootNode.url.path && current.path != "/" {
            pathComponents.insert(current, at: 0)
            current = current.deletingLastPathComponent()
        }

        outlineView.expandItem(rootNode)

        for componentURL in pathComponents {
            guard let node = findNode(for: componentURL) else { break }
            outlineView.expandItem(node)
        }
    }

    // MARK: - Context Menu

    @objc private func addFolderFromMenu(_ sender: Any?) {
        delegate?.sidebarDidRequestAddFolder(self)
    }

    // MARK: - New Subfolder (+ Button)

    private var isCreatingFolder = false
    private var newFolderParentNode: FolderNode?
    private var newFolderDelegate: NewFolderFieldDelegate?

    @objc private func createNewSubfolder(_ sender: Any?) {
        guard !isCreatingFolder else { return }

        // 선택된 폴더 결정 (이미지 선택 시 부모 폴더, 없으면 첫 루트)
        let parentNode: FolderNode?
        let row = outlineView.selectedRow
        if row >= 0 {
            let item = outlineView.item(atRow: row)
            if let node = item as? FolderNode {
                parentNode = node
            } else {
                parentNode = parentFolderNode(of: item as Any)
            }
        } else {
            parentNode = rootNodes.first
        }
        guard let parentNode else { return }
        newFolderParentNode = parentNode
        isCreatingFolder = true

        // 임시 폴더 노드를 먼저 추가 (빈 폴더도 expand 가능하도록)
        let tempNode = FolderNode(url: parentNode.url.appendingPathComponent(".newFolder"), isTemporary: true)
        parentNode.insertTemporaryChild(tempNode)
        outlineView.reloadItem(parentNode, reloadChildren: true)

        // 부모 폴더 펼침
        if !outlineView.isItemExpanded(parentNode) {
            outlineView.expandItem(parentNode)
        }

        // 임시 노드의 row 찾기
        let tempRow = outlineView.row(forItem: tempNode)
        guard tempRow >= 0,
              let cellView = outlineView.view(atColumn: 0, row: tempRow, makeIfNecessary: true) as? NSTableCellView,
              let textField = cellView.textField else {
            cleanupNewFolder()
            return
        }

        // 편집 모드 전환
        textField.stringValue = ""
        textField.placeholderString = "폴더 이름"
        textField.isEditable = true
        textField.isBordered = true
        textField.isBezeled = true
        textField.bezelStyle = .roundedBezel
        textField.drawsBackground = true
        textField.tag = tempRow

        let fieldDelegate = NewFolderFieldDelegate(
            onCommit: { [weak self] name in
                self?.commitNewFolder(name: name, textField: textField)
            },
            onCancel: { [weak self] in
                self?.cleanupNewFolder()
            }
        )
        newFolderDelegate = fieldDelegate
        textField.delegate = fieldDelegate
        view.window?.makeFirstResponder(textField)
        textField.currentEditor()?.selectAll(nil)
    }

    private func commitNewFolder(name: String, textField: NSTextField) {
        guard let parentNode = newFolderParentNode else { return }

        let trimmedName = name.trimmingCharacters(in: .whitespaces)

        if trimmedName.isEmpty {
            let alert = NSAlert()
            alert.messageText = "폴더 이름을 입력해 주세요."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "확인")
            alert.runModal()
            // 다시 편집 모드로
            view.window?.makeFirstResponder(textField)
            return
        }

        let parentURL = parentNode.url

        // 임시 노드 제거 및 상태 정리 (delegate 호출 전에 정리)
        cleanupNewFolder()

        // delegate로 폴더 생성 요청
        delegate?.sidebar(self, didRequestCreateFolder: trimmedName, in: parentURL)
    }

    private func cleanupNewFolder() {
        guard isCreatingFolder else { return }
        isCreatingFolder = false

        if let parentNode = newFolderParentNode {
            parentNode.removeTemporaryChild()
            outlineView.reloadItem(parentNode, reloadChildren: true)
        }

        newFolderParentNode = nil
        newFolderDelegate = nil
    }

    @objc private func toggleShowFiles(_ sender: NSButton) {
        showFilesInSidebar = sender.state == .on
        outlineView.reloadData()
    }

    @objc private func removeFolderFromMenu(_ sender: Any?) {
        let clickedRow = outlineView.clickedRow
        guard clickedRow >= 0, let node = outlineView.item(atRow: clickedRow) as? FolderNode else { return }
        // 루트 노드만 제거 가능
        guard rootNodes.contains(where: { $0.url == node.url }) else { return }
        delegate?.sidebar(self, didRequestRemoveFolder: node.url)
    }

    @objc private func deleteFromMenu(_ sender: Any?) {
        let clickedRow = outlineView.clickedRow
        guard clickedRow >= 0 else { return }
        let item = outlineView.item(atRow: clickedRow)

        let url: URL
        if let imageFile = item as? ImageFile {
            url = imageFile.url
        } else if let node = item as? FolderNode {
            // 루트 노드는 삭제 대상이 아님
            guard !rootNodes.contains(where: { $0.url == node.url }) else { return }
            url = node.url
        } else {
            return
        }

        delegate?.sidebar(self, didRequestDelete: [url])
    }

    @objc private func revealInFinderFromMenu(_ sender: Any?) {
        let clickedRow = outlineView.clickedRow
        guard clickedRow >= 0 else { return }
        let item = outlineView.item(atRow: clickedRow)
        let url: URL?
        if let imageFile = item as? ImageFile { url = imageFile.url }
        else if let node = item as? FolderNode { url = node.url }
        else { url = nil }
        if let url { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }

    @objc private func renameFromMenu(_ sender: Any?) {
        let clickedRow = outlineView.clickedRow
        guard clickedRow >= 0 else { return }
        let item = outlineView.item(atRow: clickedRow)
        // 루트 폴더는 이름 변경 불가
        if let node = item as? FolderNode, rootNodes.contains(where: { $0.url == node.url }) { return }
        beginRename(at: clickedRow)
    }

    @objc private func exportFromMenu(_ sender: Any?) {
        let clickedRow = outlineView.clickedRow
        guard clickedRow >= 0,
              let imageFile = outlineView.item(atRow: clickedRow) as? ImageFile else { return }
        delegate?.sidebar(self, didRequestExport: imageFile.url)
    }

    // MARK: - Click on Selected Row

    private func handleClickOnSelectedRow(at row: Int) {
        let item = outlineView.item(atRow: row)

        if let node = item as? FolderNode {
            // 폴더: 토글 펼침/접기
            if outlineView.isItemExpanded(node) {
                outlineView.collapseItem(node)
            } else {
                outlineView.expandItem(node)
            }
        } else if item is ImageFile {
            // 이미지: 이름 변경
            scheduleRename(at: row)
        }
    }

    // MARK: - Rename

    private func scheduleRename(at row: Int) {
        renameWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.beginRename(at: row)
        }
        renameWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: workItem)
    }

    private func beginRename(at row: Int) {
        guard let cellView = outlineView.view(atColumn: 0, row: row, makeIfNecessary: false) as? NSTableCellView,
              let textField = cellView.textField else { return }

        isRenameHandled = false
        textField.isEditable = true
        textField.isBordered = true
        textField.isBezeled = true
        textField.bezelStyle = .roundedBezel
        textField.drawsBackground = true
        textField.delegate = self
        textField.tag = row

        // 이미지 파일은 확장자 제외하고 파일명만 편집 가능
        let item = outlineView.item(atRow: row)
        if let imageFile = item as? ImageFile {
            let ext = (imageFile.name as NSString).pathExtension
            renamingFileExtension = ext.isEmpty ? nil : ext
            if !ext.isEmpty {
                textField.stringValue = (imageFile.name as NSString).deletingPathExtension
            }
        } else {
            renamingFileExtension = nil
        }

        view.window?.makeFirstResponder(textField)
        textField.currentEditor()?.selectAll(nil)
    }

    private func endRename(_ textField: NSTextField) {
        // 원래 이름(확장자 포함)으로 복원
        if let info = itemInfo(atRow: textField.tag) {
            textField.stringValue = info.name
        }
        textField.isEditable = false
        textField.isBordered = false
        textField.isBezeled = false
        textField.drawsBackground = false
        textField.delegate = nil
        renamingFileExtension = nil
    }

    // MARK: - Setup

    private func setupScrollView() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.documentView = outlineView
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    private func setupAddButton() {
        addButton.translatesAutoresizingMaskIntoConstraints = false
        addButton.bezelStyle = .smallSquare
        addButton.isBordered = false
        addButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "새 폴더")
        addButton.toolTip = "선택한 폴더에 새 폴더 만들기"
        addButton.target = self
        addButton.action = #selector(createNewSubfolder(_:))
        view.addSubview(addButton)

        // 폴더만/파일까지 토글
        showFilesToggle.translatesAutoresizingMaskIntoConstraints = false
        showFilesToggle.bezelStyle = .smallSquare
        showFilesToggle.isBordered = false
        showFilesToggle.setButtonType(.toggle)
        showFilesToggle.image = NSImage(systemSymbolName: "doc", accessibilityDescription: "파일 표시")
        showFilesToggle.toolTip = "파일 표시/숨기기"
        showFilesToggle.state = .on
        showFilesToggle.target = self
        showFilesToggle.action = #selector(toggleShowFiles(_:))
        view.addSubview(showFilesToggle)

        NSLayoutConstraint.activate([
            scrollView.bottomAnchor.constraint(equalTo: addButton.topAnchor),
            addButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4),
            addButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -2),
            addButton.widthAnchor.constraint(equalToConstant: 24),
            addButton.heightAnchor.constraint(equalToConstant: 24),

            showFilesToggle.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),
            showFilesToggle.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -2),
            showFilesToggle.widthAnchor.constraint(equalToConstant: 24),
            showFilesToggle.heightAnchor.constraint(equalToConstant: 24),
        ])
    }

    private static let menuRevealTag  = 1
    private static let menuRenameTag  = 2
    private static let menuExportTag  = 3
    private static let menuRemoveTag  = 4
    private static let menuDeleteTag  = 5
    private static let menuColorTag   = 6

    private func setupContextMenu() {
        let menu = NSMenu()
        menu.delegate = self

        let revealItem = NSMenuItem(title: "Finder에서 보기", action: #selector(revealInFinderFromMenu(_:)), keyEquivalent: "")
        revealItem.target = self
        revealItem.tag = Self.menuRevealTag
        menu.addItem(revealItem)

        let renameItem = NSMenuItem(title: "이름 변경", action: #selector(renameFromMenu(_:)), keyEquivalent: "")
        renameItem.target = self
        renameItem.tag = Self.menuRenameTag
        menu.addItem(renameItem)

        let exportItem = NSMenuItem(title: "다른 이름으로 저장", action: #selector(exportFromMenu(_:)), keyEquivalent: "")
        exportItem.target = self
        exportItem.tag = Self.menuExportTag
        menu.addItem(exportItem)

        menu.addItem(.separator())

        let removeItem = NSMenuItem(title: "사이드바에서 제거", action: #selector(removeFolderFromMenu(_:)), keyEquivalent: "")
        removeItem.target = self
        removeItem.tag = Self.menuRemoveTag
        menu.addItem(removeItem)

        let deleteItem = NSMenuItem(title: "삭제", action: #selector(deleteFromMenu(_:)), keyEquivalent: "")
        deleteItem.target = self
        deleteItem.tag = Self.menuDeleteTag
        menu.addItem(deleteItem)

        menu.addItem(.separator())
        let colorItem = NSMenuItem(title: "폴더 색상", action: nil, keyEquivalent: "")
        colorItem.tag = Self.menuColorTag
        menu.addItem(colorItem)

        outlineView.menu = menu
    }

    private func setupOutlineView() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("FolderColumn"))
        column.title = "Folders"
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.headerView = nil
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.rowSizeStyle = .default

        outlineView.onClickSelectedRow = { [weak self] row in
            self?.handleClickOnSelectedRow(at: row)
        }
    }

    private func registerDragTypes() {
        outlineView.registerForDraggedTypes([.fileURL])
    }

    // MARK: - Public Selection Info

    /// 사이드바에 포커스가 있는지 여부
    var isFocused: Bool {
        guard let firstResponder = view.window?.firstResponder else { return false }
        return firstResponder === outlineView || (firstResponder as? NSView)?.isDescendant(of: outlineView) == true
    }

    /// 현재 선택된 항목의 URL (이미지 또는 비루트 폴더)
    var selectedItemURL: URL? {
        let row = outlineView.selectedRow
        guard row >= 0 else { return nil }
        let item = outlineView.item(atRow: row)
        if let imageFile = item as? ImageFile {
            return imageFile.url
        }
        if let node = item as? FolderNode {
            return node.url
        }
        return nil
    }

    /// 현재 선택된 항목이 루트 폴더가 아닌 항목인지
    var selectedItemIsNonRoot: Bool {
        let row = outlineView.selectedRow
        guard row >= 0 else { return false }
        let item = outlineView.item(atRow: row)
        if item is ImageFile { return true }
        if let node = item as? FolderNode {
            return !rootNodes.contains(where: { $0.url == node.url })
        }
        return false
    }

    /// 현재 선택된 항목이 이미지인지
    var selectedItemIsImage: Bool {
        let row = outlineView.selectedRow
        guard row >= 0 else { return false }
        return outlineView.item(atRow: row) is ImageFile
    }

    /// 선택된 행에서 이름 변경 시작
    func beginRenamingSelectedItem() {
        let row = outlineView.selectedRow
        guard row >= 0 else { return }
        let item = outlineView.item(atRow: row)
        // 루트 폴더는 이름 변경 불가
        if let node = item as? FolderNode, rootNodes.contains(where: { $0.url == node.url }) {
            return
        }
        beginRename(at: row)
    }

    // MARK: - Helpers

    private func selectedFolderNode() -> FolderNode? {
        let row = outlineView.selectedRow
        guard row >= 0 else { return nil }
        return outlineView.item(atRow: row) as? FolderNode
    }

    private func parentFolderNode(of item: Any) -> FolderNode? {
        let parent = outlineView.parent(forItem: item)
        return parent as? FolderNode
    }

    private func findNode(for url: URL) -> FolderNode? {
        for root in rootNodes {
            if let found = findNode(for: url, in: root) { return found }
        }
        return nil
    }

    private func findNode(for url: URL, in node: FolderNode) -> FolderNode? {
        if node.url == url { return node }
        guard let children = node.children else { return nil }
        for child in children {
            if let found = findNode(for: url, in: child) { return found }
        }
        return nil
    }
}

// MARK: - NSOutlineViewDataSource

extension SidebarViewController: NSOutlineViewDataSource {
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil { return rootNodes.count }
        guard let node = item as? FolderNode else { return 0 }
        node.loadChildren()
        return showFilesInSidebar ? node.totalChildCount : node.folderChildCount
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil { return rootNodes[index] }
        let node = item as! FolderNode
        return node.child(at: index, includeFiles: showFilesInSidebar)!
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let node = item as? FolderNode else { return false }
        if showFilesInSidebar { return node.hasChildren }
        return node.folderChildCount > 0 || !node.isLoaded
    }

    // 드래그 소스: 이미지 파일을 드래그 가능하게
    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
        if let imageFile = item as? ImageFile {
            return imageFile.url as NSURL
        }
        return nil
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        draggingSession session: NSDraggingSession,
        willBeginAt screenPoint: NSPoint,
        forItems draggedItems: [Any]
    ) {
        // 드래그 시작 시 예약된 이름 변경 취소
        renameWorkItem?.cancel()
        renameWorkItem = nil
    }

    // 드래그 앤 드롭 타겟
    func outlineView(
        _ outlineView: NSOutlineView,
        validateDrop info: NSDraggingInfo,
        proposedItem item: Any?,
        proposedChildIndex index: Int
    ) -> NSDragOperation {
        guard item is FolderNode else { return [] }
        return .move
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        acceptDrop info: NSDraggingInfo,
        item: Any?,
        childIndex index: Int
    ) -> Bool {
        guard let targetNode = item as? FolderNode else { return false }

        let pasteboard = info.draggingPasteboard
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true,
        ]) as? [URL], !urls.isEmpty else { return false }

        delegate?.sidebar(self, didReceiveDrop: urls, toFolder: targetNode.url)
        return true
    }
}

// MARK: - NSOutlineViewDelegate

extension SidebarViewController: NSOutlineViewDelegate {
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        if let node = item as? FolderNode {
            let isRoot = rootNodes.contains(where: { $0.url == node.url })
            let identifier = NSUserInterfaceItemIdentifier(isRoot ? "RootFolderCell" : "FolderCell")
            let cell = outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
                ?? createSidebarCell(identifier: identifier)

            cell.textField?.stringValue = node.name
            cell.imageView?.image = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: node.name)
            cell.imageView?.contentTintColor = FolderColorService.shared.color(for: node.url)

            // 미디어 파일 개수 표시
            let countLabel = cell.viewWithTag(Self.countLabelTag) as? NSTextField
            node.loadChildren()
            let count = node.mediaFileCount
            countLabel?.stringValue = count > 0 ? "\(count)" : ""
            return cell
        }

        if let imageFile = item as? ImageFile {
            let identifier = NSUserInterfaceItemIdentifier("ImageCell")
            let cell = outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
                ?? createSidebarCell(identifier: identifier)

            cell.textField?.stringValue = imageFile.name
            cell.imageView?.image = NSImage(
                systemSymbolName: "photo",
                accessibilityDescription: imageFile.name
            )
            cell.imageView?.contentTintColor = .secondaryLabelColor
            // 이미지 셀에서는 개수 레이블 숨김
            let countLabel = cell.viewWithTag(Self.countLabelTag) as? NSTextField
            countLabel?.stringValue = ""
            return cell
        }

        return nil
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        renameWorkItem?.cancel()
        guard !isSuppressingSelectionDelegate else { return }
        let row = outlineView.selectedRow
        guard row >= 0 else { return }
        let item = outlineView.item(atRow: row)

        if let node = item as? FolderNode {
            // 첫 선택 시 자동 펼침
            if !outlineView.isItemExpanded(node) {
                outlineView.expandItem(node)
            }
            delegate?.sidebar(self, didSelectFolder: node.url)
        } else if let imageFile = item as? ImageFile,
                  let parentNode = parentFolderNode(of: item!) {
            delegate?.sidebar(self, didSelectImage: imageFile, inFolder: parentNode.url)
        }
    }

    func outlineViewItemWillExpand(_ notification: Notification) {
        guard let node = notification.userInfo?["NSObject"] as? FolderNode else { return }
        node.loadChildren()
    }

    private static let countLabelTag = 100

    private func createSidebarCell(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = identifier

        let imageView = NSImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(imageView)
        cell.imageView = imageView

        let textField = NSTextField(labelWithString: "")
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.lineBreakMode = .byTruncatingTail
        cell.addSubview(textField)
        cell.textField = textField

        // 미디어 개수 레이블 (폴더 셀에서 사용)
        let countLabel = NSTextField(labelWithString: "")
        countLabel.translatesAutoresizingMaskIntoConstraints = false
        countLabel.font = .systemFont(ofSize: 10)
        countLabel.textColor = .tertiaryLabelColor
        countLabel.alignment = .right
        countLabel.lineBreakMode = .byClipping
        countLabel.tag = Self.countLabelTag
        countLabel.setContentHuggingPriority(.required, for: .horizontal)
        countLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        cell.addSubview(countLabel)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
            imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 16),
            imageView.heightAnchor.constraint(equalToConstant: 16),
            textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 4),
            textField.trailingAnchor.constraint(lessThanOrEqualTo: countLabel.leadingAnchor, constant: -4),
            textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            countLabel.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            countLabel.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])

        return cell
    }
}

// MARK: - NSTextFieldDelegate (Inline Rename)

extension SidebarViewController: NSTextFieldDelegate {
    private func itemInfo(atRow row: Int) -> (url: URL, name: String)? {
        let item = outlineView.item(atRow: row)
        if let node = item as? FolderNode { return (node.url, node.name) }
        if let file = item as? ImageFile { return (file.url, file.name) }
        return nil
    }

    private func fullNameFromStem(_ stem: String) -> String {
        if let ext = renamingFileExtension, !ext.isEmpty {
            return "\(stem).\(ext)"
        }
        return stem
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            guard !isRenameHandled else { return true }
            isRenameHandled = true
            guard let textField = control as? NSTextField,
                  let info = itemInfo(atRow: textField.tag) else { return false }
            let stem = textField.stringValue.trimmingCharacters(in: .whitespaces)
            let newName = fullNameFromStem(stem)
            endRename(textField)
            if !stem.isEmpty && newName != info.name {
                delegate?.sidebar(self, didRequestRename: info.url, newName: newName)
            }
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            guard !isRenameHandled else { return true }
            isRenameHandled = true
            guard let textField = control as? NSTextField,
                  let info = itemInfo(atRow: textField.tag) else { return false }
            textField.stringValue = info.name
            endRename(textField)
            return true
        }
        return false
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard !isRenameHandled else { return }
        isRenameHandled = true
        guard let textField = obj.object as? NSTextField else { return }
        guard let info = itemInfo(atRow: textField.tag) else {
            endRename(textField)
            return
        }
        let stem = textField.stringValue.trimmingCharacters(in: .whitespaces)
        let newName = fullNameFromStem(stem)
        endRename(textField)
        if !stem.isEmpty && newName != info.name {
            delegate?.sidebar(self, didRequestRename: info.url, newName: newName)
        }
    }
}

// MARK: - NSMenuDelegate (Context Menu)

extension SidebarViewController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        let clickedRow = outlineView.clickedRow
        guard clickedRow >= 0 else {
            for item in menu.items { item.isHidden = true }
            return
        }

        let clickedItem = outlineView.item(atRow: clickedRow)
        let isRootFolder: Bool
        let isDeletable: Bool

        if let node = clickedItem as? FolderNode {
            isRootFolder = rootNodes.contains(where: { $0.url == node.url })
            isDeletable = !isRootFolder // 하위 폴더만 삭제 가능
        } else if clickedItem is ImageFile {
            isRootFolder = false
            isDeletable = true
        } else {
            isRootFolder = false
            isDeletable = false
        }

        let isImage = clickedItem is ImageFile
        let isRenamable = !isRootFolder  // 루트 폴더 제외 모두 이름 변경 가능

        for item in menu.items {
            switch item.tag {
            case Self.menuRevealTag:
                item.isHidden = false
            case Self.menuRenameTag:
                item.isHidden = !isRenamable
            case Self.menuExportTag:
                item.isHidden = !isImage
            case Self.menuRemoveTag:
                item.isHidden = !isRootFolder
            case Self.menuDeleteTag:
                item.isHidden = !isDeletable
            case Self.menuColorTag:
                // 폴더일 때만 색상 서브메뉴 표시
                let isFolder = clickedItem is FolderNode
                item.isHidden = !isFolder
                if isFolder, let node = clickedItem as? FolderNode {
                    item.submenu = FolderColorService.createColorMenu(
                        for: node.url, target: self, action: #selector(setFolderColor(_:))
                    )
                }
            default:
                break
            }
        }
    }
}

// MARK: - Folder Color

extension SidebarViewController {
    @objc private func setFolderColor(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        FolderColorService.shared.setColorIndex(sender.tag, for: url)
    }

    func observeFolderColorChanges() {
        NotificationCenter.default.addObserver(
            forName: .folderColorChanged, object: nil, queue: .main
        ) { [weak self] _ in
            self?.outlineView.reloadData()
        }
    }
}

// MARK: - NewFolderFieldDelegate

private final class NewFolderFieldDelegate: NSObject, NSTextFieldDelegate {
    let onCommit: (String) -> Void
    let onCancel: () -> Void
    private var isHandled = false

    init(onCommit: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.onCommit = onCommit
        self.onCancel = onCancel
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            guard !isHandled else { return true }
            isHandled = true
            onCommit(control.stringValue)
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            guard !isHandled else { return true }
            isHandled = true
            onCancel()
            return true
        }
        return false
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard !isHandled else { return }
        isHandled = true
        onCancel()
    }
}
