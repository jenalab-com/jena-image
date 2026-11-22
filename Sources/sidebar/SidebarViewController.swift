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
    func sidebarDidSelectBookmarks(_ sidebar: SidebarViewController)
    /// 폴더가 펼쳐짐 — 파일시스템 감시 대상에 추가할 시점
    func sidebar(_ sidebar: SidebarViewController, didExpandFolder url: URL)
    /// 폴더가 접힘 — 감시 대상에서 제외할 시점
    func sidebar(_ sidebar: SidebarViewController, didCollapseFolder url: URL)
    /// 상단 새로고침 버튼 — 트리와 현재 폴더 내용을 함께 다시 읽는다
    func sidebarDidRequestReload(_ sidebar: SidebarViewController)
    /// 상단 "하위 폴더 포함" 토글 — 현재 폴더를 새 모드로 다시 읽을 시점
    func sidebar(_ sidebar: SidebarViewController, didToggleRecursive enabled: Bool)
}

// MARK: - Sidebar Sentinel Types

/// 아웃라인 뷰 섹션 헤더 (그룹 행)
private final class SidebarGroup {
    let title: String
    init(_ title: String) { self.title = title }
}

/// 즐겨찾기 섹션의 북마크 항목
private final class SidebarBookmarksRow {}

private final class SidebarCategoryRow {
    let category: ImageCategory
    init(_ category: ImageCategory) { self.category = category }
}

// MARK: - Click-Aware Outline View

private final class ClickAwareOutlineView: NSOutlineView {
    var onClickSelectedRow: ((Int) -> Void)?
    var onDoubleClickRow: ((Int) -> Bool)?

    /// 펼침 삼각형은 감추고 셀 오른쪽 화살표(`SidebarItemCellView.chevronButton`)로 대신한다.
    override func frameOfOutlineCell(atRow row: Int) -> NSRect { .zero }

    override func mouseDown(with event: NSEvent) {
        let clickPoint = convert(event.locationInWindow, from: nil)
        let clickedRow = row(at: clickPoint)
        if event.clickCount == 2, clickedRow >= 0, onDoubleClickRow?(clickedRow) == true { return }
        let wasSelected = clickedRow >= 0 && selectedRowIndexes.contains(clickedRow)
        let isSingleClick = event.clickCount == 1
        // 셀 안의 버튼(펼침 화살표)을 눌렀다면 버튼이 직접 처리한다 — 선택 행 토글이 겹쳐 두 번 접히지 않게.
        let hitButton = superview.map { hitTest($0.convert(event.locationInWindow, from: nil)) is NSButton } ?? false

        super.mouseDown(with: event)

        if isSingleClick && wasSelected && clickedRow >= 0 && !hitButton {
            onClickSelectedRow?(clickedRow)
        }
    }
}

// MARK: - ViewController

final class SidebarViewController: NSViewController {
    weak var delegate: SidebarDelegate?

    private let outlineView = ClickAwareOutlineView()
    private let scrollView = NSScrollView()
    private let addButton = SidebarIconButton(symbol: "plus", label: "새 폴더")
    private let showFilesToggle = SidebarIconButton(symbol: "photo.on.rectangle", label: "파일 표시", toggle: true)
    private let reloadButton = SidebarIconButton(symbol: "arrow.clockwise", label: "새로고침")
    private let addRootFolderButton = SidebarIconButton(symbol: "folder.badge.plus", label: "폴더 추가")
    private let recursiveToggle = SidebarIconButton(symbol: "square.stack.3d.down.right", label: "하위 폴더 이미지 포함", toggle: true)
    private let folderModeButton = SidebarIconButton(kind: .segment, symbol: "folder", label: "폴더로 보기", toggle: true)
    private let categoryModeButton = SidebarIconButton(kind: .segment, symbol: "tag", label: "카테고리 보기", toggle: true)
    private let headerDivider = SidebarDivider()
    private let footerDivider = SidebarDivider()
    private let categoryEmptyLabel = NSTextField(labelWithString: "카테고리가 없습니다.\n+ 버튼으로 추가하세요.")
    private(set) var isCategoryView = false
    var onSelectCategory: ((UUID) -> Void)?
    var onAddCategory: (() -> Void)?
    var onRenameCategory: ((UUID) -> Void)?
    var onViewModeChanged: ((Bool) -> Void)?
    /// 웹 패널에서 끌어온 이미지 드래그인지.
    var isWebImageDrag: ((NSDraggingInfo) -> Bool)?
    /// 폴더 행에 놓은 웹 이미지를 그 폴더에 저장한다.
    var onWebImageDrop: ((NSDraggingInfo, _ folder: URL) -> Bool)?
    private var categoryRows: [SidebarCategoryRow] = []
    private var savedExpandedURLs: [URL] = []
    private var showFilesInSidebar = true
    private var rootNodes: [FolderNode] = []
    private var renameWorkItem: DispatchWorkItem?
    private var renamingFileExtension: String?
    private var isRenameHandled = false
    private var isSuppressingSelectionDelegate = false

    // MARK: - 섹션 센티넬 (source-list 구조)
    private let favoritesGroup = SidebarGroup("즐겨찾기")
    private let foldersGroup   = SidebarGroup("폴더")
    private let bookmarksRow   = SidebarBookmarksRow()
    private let categoriesGroup = SidebarGroup("카테고리")

    override func loadView() {
        view = LibrarySurfaceView(kind: .sidebar)
        setupHeaderBar()
        setupScrollView()
        setupOutlineView()
        setupAddButton()
        setupContextMenu()
        categoryEmptyLabel.translatesAutoresizingMaskIntoConstraints = false
        categoryEmptyLabel.font = .systemFont(ofSize: 12)
        categoryEmptyLabel.textColor = SidebarStyle.tertiaryText
        categoryEmptyLabel.alignment = .center
        categoryEmptyLabel.isHidden = true
        view.addSubview(categoryEmptyLabel)
        NSLayoutConstraint.activate([
            categoryEmptyLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            categoryEmptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
        ])
        updateViewModeAppearance()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        registerDragTypes()
        observeFolderColorChanges()
    }

    // MARK: - Public

    func setCategories(_ categories: [ImageCategory], selectedID: UUID?) {
        categoryRows = categories.map(SidebarCategoryRow.init)
        guard isViewLoaded else { return }
        if isCategoryView {
            let wasBookmarks = outlineView.item(atRow: outlineView.selectedRow) is SidebarBookmarksRow
            isSuppressingSelectionDelegate = true
            outlineView.reloadData()
            expandGroups()
            if wasBookmarks, selectedID == nil {
                let row = outlineView.row(forItem: bookmarksRow)
                if row >= 0 { outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
            } else { selectCategory(selectedID) }
            isSuppressingSelectionDelegate = false
        }
        categoryEmptyLabel.isHidden = !isCategoryView || !categories.isEmpty
    }

    func selectCategory(_ id: UUID?) {
        guard isCategoryView, let item = categoryRows.first(where: { $0.category.id == id }) else { return }
        let row = outlineView.row(forItem: item)
        guard row >= 0 else { return }
        let wasSuppressing = isSuppressingSelectionDelegate
        isSuppressingSelectionDelegate = true
        outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        isSuppressingSelectionDelegate = wasSuppressing
    }

    func setCategoryView(_ enabled: Bool) {
        guard isCategoryView != enabled else { return }
        renameWorkItem?.cancel()
        if enabled { savedExpandedURLs = expandedFolderURLs }
        isCategoryView = enabled
        isSuppressingSelectionDelegate = true
        outlineView.deselectAll(nil)
        outlineView.reloadData()
        expandGroups()
        if !enabled {
            for url in savedExpandedURLs.sorted(by: { $0.path.count < $1.path.count }) {
                if let node = findNode(for: url) { outlineView.expandItem(node) }
            }
        }
        isSuppressingSelectionDelegate = false
        updateViewModeAppearance()
    }

    private func updateViewModeAppearance() {
        folderModeButton.state = isCategoryView ? .off : .on
        categoryModeButton.state = isCategoryView ? .on : .off
        recursiveToggle.isHidden = isCategoryView
        showFilesToggle.isHidden = isCategoryView
        addRootFolderButton.setSymbol(isCategoryView ? "plus" : "folder.badge.plus",
                                      label: isCategoryView ? "카테고리 추가" : "폴더 추가")
        addRootFolderButton.toolTip = isCategoryView ? "카테고리 추가" : "사이드바에 폴더 추가"
        addButton.toolTip = isCategoryView ? "카테고리 추가" : "선택한 폴더에 새 폴더 만들기"
        reloadButton.toolTip = isCategoryView ? "카테고리 목록 새로고침" : "폴더 목록 새로고침 (⌘⇧R)"
        categoryEmptyLabel.isHidden = !isCategoryView || !categoryRows.isEmpty
    }

    @objc private func folderModeTapped(_ sender: Any?) {
        guard isCategoryView else { return }
        setCategoryView(false)
        onViewModeChanged?(false)
    }

    @objc private func categoryModeTapped(_ sender: Any?) {
        guard !isCategoryView else { return }
        setCategoryView(true)
        onViewModeChanged?(true)
    }

    /// 등록된 폴더 목록으로 사이드바 구성
    func setFolders(_ urls: [URL]) {
        rootNodes = urls.map { FolderNode(url: $0) }
        outlineView.reloadData()
        expandGroups()
    }

    /// 폴더 하나 추가
    func addFolder(_ url: URL) {
        // 중복 방지
        guard !rootNodes.contains(where: { $0.url.standardizedFileURL == url.standardizedFileURL }) else { return }
        rootNodes.append(FolderNode(url: url))
        outlineView.reloadData()
        expandGroups()
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
        expandGroups()
    }

    func selectFolder(at url: URL) {
        guard let node = findNode(for: url) else { return }
        let row = outlineView.row(forItem: node)
        guard row >= 0 else { return }
        outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
    }

    /// 루트 아래 폴더를 트리에서 펼쳐 선택한다(델리게이트 억제 — 호출자가 직접 이동시킨다).
    /// 어느 루트에도 속하지 않으면 false.
    @discardableResult
    func revealFolder(at url: URL) -> Bool {
        guard !isCategoryView else { return false }
        if findNode(for: url) == nil { expandToSubfolder(url) }
        guard let node = findNode(for: url) else { return false }
        let row = outlineView.row(forItem: node)
        guard row >= 0 else { return false }
        isSuppressingSelectionDelegate = true
        outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        isSuppressingSelectionDelegate = false
        outlineView.scrollRowToVisible(row)
        return true
    }

    func selectFile(at url: URL) {
        guard !isCategoryView else { return }
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
        reload(node: selected)
    }

    func reloadFolder(at url: URL) {
        guard let node = findNode(for: url) else { return }
        reload(node: node)
    }

    /// 사이드바 전체 새로고침 — 모든 루트와, 이미 펼쳐본 하위 폴더를 디스크에서 다시 읽는다.
    /// 펼침 상태와 선택 항목은 그대로 유지된다.
    @objc func reloadAll(_ sender: Any?) {
        FolderMediaCountService.shared.invalidateAll()
        for root in rootNodes {
            reload(node: root)
        }
    }

    @objc private func reloadTapped(_ sender: Any?) {
        delegate?.sidebarDidRequestReload(self)
    }

    @objc private func recursiveTapped(_ sender: NSButton) {
        let enabled = sender.state == .on
        AppSettings.shared.recursiveBrowsing = enabled
        updateRecursiveToggleAppearance()
        delegate?.sidebar(self, didToggleRecursive: enabled)
    }

    /// 켜짐 상태는 강조색으로 표시해 한눈에 모드를 알 수 있게 한다.
    private func updateRecursiveToggleAppearance() {
        let on = recursiveToggle.state == .on
        recursiveToggle.toolTip = on
            ? "하위 폴더 이미지 포함 보기: 켜짐 (클릭하면 끔)"
            : "하위 폴더 이미지 포함 보기: 꺼짐 (클릭하면 켬)"
    }

    /// 노드 하나를 디스크 기준으로 갱신하고, 선택 항목을 URL 기준으로 복원한다.
    private func reload(node: FolderNode) {
        let selectedURL = selectedItemURL
        FolderMediaCountService.shared.invalidate(node.url)
        node.refresh()
        outlineView.reloadItem(node, reloadChildren: true)
        restoreSelection(to: selectedURL)
    }

    /// 새로고침으로 행 번호가 밀렸을 때, 같은 URL의 행을 다시 선택한다.
    /// (델리게이트를 억제해 폴더 재진입·뷰어 전환 같은 부작용을 막는다)
    private func restoreSelection(to url: URL?) {
        guard let url else { return }
        if let current = selectedItemURL, current == url { return }

        for row in 0..<outlineView.numberOfRows {
            let item = outlineView.item(atRow: row)
            let itemURL: URL?
            if let node = item as? FolderNode { itemURL = node.url }
            else if let file = item as? ImageFile { itemURL = file.url }
            else { itemURL = nil }

            guard itemURL == url else { continue }
            isSuppressingSelectionDelegate = true
            outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            isSuppressingSelectionDelegate = false
            return
        }
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

    // MARK: - 그룹 섹션 펼침 유지

    private func expandGroups() {
        outlineView.expandItem(favoritesGroup)
        outlineView.expandItem(isCategoryView ? categoriesGroup : foldersGroup)
    }

    // MARK: - Context Menu

    @objc private func addFolderFromMenu(_ sender: Any?) {
        if isCategoryView { onAddCategory?(); return }
        delegate?.sidebarDidRequestAddFolder(self)
    }

    // MARK: - New Subfolder (+ Button)

    private var isCreatingFolder = false
    private var newFolderParentNode: FolderNode?
    private var newFolderDelegate: NewFolderFieldDelegate?

    @objc private func createNewSubfolder(_ sender: Any?) {
        if isCategoryView { onAddCategory?(); return }
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
        (cellView as? SidebarItemCellView)?.isEditingName = true
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
        expandGroups()
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
        if let id = (sender as? NSMenuItem)?.representedObject as? UUID {
            onRenameCategory?(id)
            return
        }
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
        if let categoryRow = item as? SidebarCategoryRow {
            onSelectCategory?(categoryRow.category.id)
            return
        }

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
        // 센티넬 타입(SidebarGroup, SidebarBookmarksRow)은 무시
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
        guard !(outlineView.item(atRow: row) is SidebarCategoryRow) else { return }
        guard let cellView = outlineView.view(atColumn: 0, row: row, makeIfNecessary: false) as? NSTableCellView,
              let textField = cellView.textField else { return }

        isRenameHandled = false
        (cellView as? SidebarItemCellView)?.isEditingName = true
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
        (textField.superview as? SidebarItemCellView)?.isEditingName = false
        renamingFileExtension = nil
    }

    // MARK: - Setup

    /// 상단 — [로고 JenaImage] 아래에 [폴더|카테고리 전환] …… [폴더 추가][하위 폴더 포함][새로고침], 그 밑에 구분선.
    private func setupHeaderBar() {
        let logo = NSImageView(image: SidebarStyle.logoImage)
        logo.translatesAutoresizingMaskIntoConstraints = false
        logo.imageScaling = .scaleProportionallyUpOrDown
        logo.setAccessibilityLabel("JenaImage")
        view.addSubview(logo)

        let title = NSTextField(labelWithString: "JenaImage")
        title.font = .systemFont(ofSize: 15, weight: .bold)
        title.textColor = SidebarStyle.ink
        title.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(title)

        addRootFolderButton.toolTip = "사이드바에 폴더 추가"
        addRootFolderButton.target = self
        addRootFolderButton.action = #selector(addFolderFromMenu(_:))

        reloadButton.toolTip = "폴더 목록 새로고침 (⌘⇧R)"
        reloadButton.target = self
        reloadButton.action = #selector(reloadTapped(_:))

        recursiveToggle.state = AppSettings.shared.recursiveBrowsing ? .on : .off
        recursiveToggle.target = self
        recursiveToggle.action = #selector(recursiveTapped(_:))
        updateRecursiveToggleAppearance()

        folderModeButton.toolTip = "폴더로 보기"
        folderModeButton.target = self
        folderModeButton.action = #selector(folderModeTapped(_:))
        categoryModeButton.toolTip = "카테고리 보기"
        categoryModeButton.target = self
        categoryModeButton.action = #selector(categoryModeTapped(_:))
        let modeTrack = SidebarSegmentTrack(buttons: [folderModeButton, categoryModeButton])
        view.addSubview(modeTrack)
        // 스택에 두면 카테고리 보기에서 숨긴 버튼 자리가 비지 않고 오른쪽으로 모인다.
        let tools = NSStackView(views: [addRootFolderButton, recursiveToggle, reloadButton])
        tools.translatesAutoresizingMaskIntoConstraints = false
        tools.spacing = 2
        tools.detachesHiddenViews = true
        view.addSubview(tools)
        view.addSubview(headerDivider)

        NSLayoutConstraint.activate([
            logo.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            logo.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            logo.widthAnchor.constraint(equalToConstant: 30),
            logo.heightAnchor.constraint(equalToConstant: 30),
            title.leadingAnchor.constraint(equalTo: logo.trailingAnchor, constant: 8),
            title.centerYAnchor.constraint(equalTo: logo.centerYAnchor),
            title.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -14),

            modeTrack.topAnchor.constraint(equalTo: logo.bottomAnchor, constant: 16),
            modeTrack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            modeTrack.heightAnchor.constraint(equalToConstant: 28),

            tools.centerYAnchor.constraint(equalTo: modeTrack.centerYAnchor),
            tools.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            tools.leadingAnchor.constraint(greaterThanOrEqualTo: modeTrack.trailingAnchor, constant: 8),

            headerDivider.topAnchor.constraint(equalTo: modeTrack.bottomAnchor, constant: 14),
            headerDivider.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            headerDivider.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
        ])
        for button in [addRootFolderButton, recursiveToggle, reloadButton] {
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: 28),
                button.heightAnchor.constraint(equalToConstant: 28),
            ])
        }
    }

    private func setupScrollView() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.documentView = outlineView
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: headerDivider.bottomAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    /// 하단 — 구분선 아래 [새 폴더] …… [파일 표시 토글]
    private func setupAddButton() {
        addButton.toolTip = "선택한 폴더에 새 폴더 만들기"
        addButton.target = self
        addButton.action = #selector(createNewSubfolder(_:))
        view.addSubview(addButton)
        view.addSubview(footerDivider)

        showFilesToggle.toolTip = "사이드바에 이미지 파일 표시/숨기기"
        showFilesToggle.state = .on
        showFilesToggle.target = self
        showFilesToggle.action = #selector(toggleShowFiles(_:))
        view.addSubview(showFilesToggle)

        NSLayoutConstraint.activate([
            scrollView.bottomAnchor.constraint(equalTo: footerDivider.topAnchor, constant: -4),
            footerDivider.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            footerDivider.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            footerDivider.bottomAnchor.constraint(equalTo: addButton.topAnchor, constant: -8),

            addButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            addButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -10),
            addButton.widthAnchor.constraint(equalToConstant: 28),
            addButton.heightAnchor.constraint(equalToConstant: 28),

            showFilesToggle.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            showFilesToggle.centerYAnchor.constraint(equalTo: addButton.centerYAnchor),
            showFilesToggle.widthAnchor.constraint(equalToConstant: 28),
            showFilesToggle.heightAnchor.constraint(equalToConstant: 28),
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
        outlineView.backgroundColor = .clear
        outlineView.rowSizeStyle = .custom
        outlineView.rowHeight = SidebarStyle.rowHeight
        outlineView.intercellSpacing = NSSize(width: 0, height: 2)
        outlineView.indentationPerLevel = SidebarStyle.indent
        outlineView.focusRingType = .none
        // source-list 스타일 적용 (macOS 11 이하 호환을 위해 style 설정 후 deprecated API 폴백)
        if #available(macOS 12.0, *) {
            outlineView.style = .sourceList
        } else {
            outlineView.selectionHighlightStyle = .sourceList
        }

        outlineView.onClickSelectedRow = { [weak self] row in
            self?.handleClickOnSelectedRow(at: row)
        }
        outlineView.onDoubleClickRow = { [weak self] row in
            guard let self, let item = self.outlineView.item(atRow: row) as? SidebarCategoryRow else { return false }
            self.onRenameCategory?(item.category.id)
            return true
        }
    }

    private func registerDragTypes() {
        outlineView.registerForDraggedTypes([.fileURL] + WebPageEngine.imageDragTypes)
    }

    // MARK: - Public Selection Info

    /// 사이드바에 포커스가 있는지 여부
    var isFocused: Bool {
        guard let firstResponder = view.window?.firstResponder else { return false }
        return firstResponder === outlineView || (firstResponder as? NSView)?.isDescendant(of: outlineView) == true
    }

    /// 사이드바에 등록된 루트 폴더 URL 목록
    var rootFolderURLs: [URL] {
        rootNodes.map { $0.url }
    }

    /// 현재 펼쳐져 있는 폴더 URL 목록 (파일시스템 감시 대상 산정용)
    var expandedFolderURLs: [URL] {
        (0..<outlineView.numberOfRows).compactMap { row in
            guard let node = outlineView.item(atRow: row) as? FolderNode,
                  outlineView.isItemExpanded(node) else { return nil }
            return node.url
        }
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

    // MARK: 트리 구조
    // nil → [favoritesGroup, foldersGroup]
    // favoritesGroup → [bookmarksRow]
    // foldersGroup   → rootNodes
    // FolderNode     → 기존 로직 유지

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil { return 2 }
        if item is SidebarGroup {
            if (item as AnyObject) === favoritesGroup { return 1 }
            if (item as AnyObject) === foldersGroup   { return rootNodes.count }
            if (item as AnyObject) === categoriesGroup { return categoryRows.count }
        }
        guard let node = item as? FolderNode else { return 0 }
        node.loadChildren()
        return showFilesInSidebar ? node.totalChildCount : node.folderChildCount
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil {
            return index == 0 ? favoritesGroup : (isCategoryView ? categoriesGroup : foldersGroup)
        }
        if let group = item as? SidebarGroup {
            if group === favoritesGroup { return bookmarksRow }
            if group === foldersGroup   { return rootNodes[index] }
            if group === categoriesGroup { return categoryRows[index] }
        }
        let node = item as! FolderNode
        return node.child(at: index, includeFiles: showFilesInSidebar)!
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        if item is SidebarGroup { return true }
        if item is SidebarBookmarksRow { return false }
        guard let node = item as? FolderNode else { return false }
        if showFilesInSidebar { return node.hasChildren }
        return node.folderChildCount > 0 || !node.isLoaded
    }

    // 드래그 소스: 이미지 파일을 드래그 가능하게 (센티넬은 nil 반환)
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

    // 드래그 앤 드롭 타겟 (FolderNode만 허용; 센티넬은 [] 반환)
    // 파일 드래그는 옮기기, 웹 패널의 이미지 드래그는 복사(저장). 그 밖의 드래그는 받지 않는다.
    func outlineView(
        _ outlineView: NSOutlineView,
        validateDrop info: NSDraggingInfo,
        proposedItem item: Any?,
        proposedChildIndex index: Int
    ) -> NSDragOperation {
        guard item is FolderNode else { return [] }
        if isWebImageDrag?(info) == true { return .copy }
        let isFileDrag = info.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
        return isFileDrag ? .move : []
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        acceptDrop info: NSDraggingInfo,
        item: Any?,
        childIndex index: Int
    ) -> Bool {
        guard let targetNode = item as? FolderNode else { return false }
        if isWebImageDrag?(info) == true { return onWebImageDrop?(info, targetNode.url) ?? false }

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
    func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
        LibrarySidebarRowView()
    }

    /// 행이 붙을 때 조상 폴더들의 실제 셀 위치로 가이드 선 좌표를 정한다(소스 리스트의 단계별 들여쓰기가 일정하지 않아 계산 대신 측정).
    func outlineView(_ outlineView: NSOutlineView, didAdd rowView: NSTableRowView, forRow row: Int) {
        guard let rowView = rowView as? LibrarySidebarRowView else { return }
        var xs: [CGFloat] = []
        var ancestor = outlineView.parent(forItem: outlineView.item(atRow: row))
        while let node = ancestor as? FolderNode {
            let ancestorRow = outlineView.row(forItem: node)
            if ancestorRow >= 0 {
                xs.append(outlineView.frameOfCell(atColumn: 0, row: ancestorRow).minX + SidebarStyle.iconCenterOffset)
            }
            ancestor = outlineView.parent(forItem: node)
        }
        rowView.guideXs = xs
    }

    func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
        item is SidebarGroup ? SidebarStyle.groupRowHeight : SidebarStyle.rowHeight
    }

    /// 그룹 헤더 판별 — SidebarGroup만 true
    func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
        return item is SidebarGroup
    }

    /// 그룹은 선택 불가; 나머지는 모두 선택 가능
    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        return !(item is SidebarGroup)
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        // 그룹 헤더 셀 — "폴더  3"
        if let group = item as? SidebarGroup {
            let id = NSUserInterfaceItemIdentifier("GroupCell")
            let cell = outlineView.makeView(withIdentifier: id, owner: self) as? SidebarGroupCellView
                ?? SidebarGroupCellView(identifier: id)
            let count: Int? = group === foldersGroup ? rootNodes.count
                : group === categoriesGroup ? categoryRows.count : nil
            cell.configure(title: group.title, count: count)
            return cell
        }

        // 북마크 행 셀 — 폴더 모양에 별 배지
        if item is SidebarBookmarksRow {
            let cell = itemCell(identifier: "BookmarksCell")
            cell.role = .special
            cell.iconColor = nil
            cell.textField?.stringValue = "북마크"
            cell.imageView?.image = FolderGlyph.image(badge: "star.fill")
            cell.count = ""
            cell.isExpandable = false
            return cell
        }

        // 카테고리 행 셀 — 폴더 모양에 태그 배지
        if let row = item as? SidebarCategoryRow {
            let cell = itemCell(identifier: "CategoryCell")
            cell.role = .special
            cell.iconColor = nil
            cell.textField?.stringValue = row.category.name
            cell.imageView?.image = FolderGlyph.image(badge: "tag.fill")
            cell.count = "\(row.category.paths.count)"
            cell.isExpandable = false
            return cell
        }

        // 폴더 셀
        if let node = item as? FolderNode {
            let isRoot = rootNodes.contains(where: { $0.url == node.url })
            let cell = itemCell(identifier: isRoot ? "RootFolderCell" : "FolderCell")
            cell.role = isRoot ? .root : .folder
            cell.textField?.stringValue = node.name
            cell.imageView?.image = FolderGlyph.image()
            // 기본색은 모노톤으로 두고, 사용자가 고른 색만 아이콘에 입힌다.
            cell.iconColor = FolderColorService.shared.colorIndex(for: node.url) == 0
                ? nil : FolderColorService.shared.color(for: node.url)

            // 하위 폴더까지 합친 미디어 파일 총계. 아직 안 세었으면 비워 두고, 계산이 끝나면 onUpdate로 다시 채운다.
            node.loadChildren()   // 펼침 화살표 판단(빈 폴더는 화살표 없음)을 위해 직속 내용은 미리 읽는다
            cell.count = Self.countText(for: node.url)
            cell.isExpandable = self.outlineView(outlineView, isItemExpandable: node)
            cell.isExpanded = outlineView.isItemExpanded(node)
            return cell
        }

        // 이미지 셀
        if let imageFile = item as? ImageFile {
            let cell = itemCell(identifier: "ImageCell")
            cell.role = .file
            cell.iconColor = nil
            cell.textField?.stringValue = imageFile.name
            cell.imageView?.image = SidebarStyle.symbol("photo", size: 13)
            cell.count = ""
            cell.isExpandable = false
            return cell
        }

        return nil
    }

    private func itemCell(identifier: String) -> SidebarItemCellView {
        let id = NSUserInterfaceItemIdentifier(identifier)
        if let cell = outlineView.makeView(withIdentifier: id, owner: self) as? SidebarItemCellView { return cell }
        let cell = SidebarItemCellView(identifier: id)
        cell.chevronButton.target = self
        cell.chevronButton.action = #selector(chevronTapped(_:))
        return cell
    }

    @objc private func chevronTapped(_ sender: NSButton) {
        let row = outlineView.row(for: sender)
        guard row >= 0, let node = outlineView.item(atRow: row) as? FolderNode else { return }
        if outlineView.isItemExpanded(node) {
            outlineView.collapseItem(node)
        } else {
            outlineView.expandItem(node)
        }
    }

    /// 펼침/접힘이 바뀐 폴더 행의 화살표 방향만 갱신한다.
    private func updateChevron(for node: FolderNode) {
        let row = outlineView.row(forItem: node)
        guard row >= 0,
              let cell = outlineView.view(atColumn: 0, row: row, makeIfNecessary: false) as? SidebarItemCellView else { return }
        cell.isExpandable = outlineView(outlineView, isItemExpandable: node)
        cell.isExpanded = outlineView.isItemExpanded(node)
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        renameWorkItem?.cancel()
        guard !isSuppressingSelectionDelegate else { return }
        let row = outlineView.selectedRow
        guard row >= 0 else { return }
        let item = outlineView.item(atRow: row)

        if let row = item as? SidebarCategoryRow {
            onSelectCategory?(row.category.id)
            return
        }

        // 북마크 행 선택
        if item is SidebarBookmarksRow {
            delegate?.sidebarDidSelectBookmarks(self)
            return
        }

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

    func outlineViewItemDidExpand(_ notification: Notification) {
        guard let node = notification.userInfo?["NSObject"] as? FolderNode else { return }
        updateChevron(for: node)
        delegate?.sidebar(self, didExpandFolder: node.url)
    }

    func outlineViewItemDidCollapse(_ notification: Notification) {
        guard let node = notification.userInfo?["NSObject"] as? FolderNode else { return }
        updateChevron(for: node)
        delegate?.sidebar(self, didCollapseFolder: node.url)
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
        menu.item(withTag: Self.menuRenameTag)?.representedObject = nil
        for item in menu.items { item.isHidden = false }
        let clickedRow = outlineView.clickedRow
        guard clickedRow >= 0 else {
            for item in menu.items { item.isHidden = true }
            return
        }

        let clickedItem = outlineView.item(atRow: clickedRow)

        if let row = clickedItem as? SidebarCategoryRow {
            for item in menu.items { item.isHidden = item.tag != Self.menuRenameTag }
            menu.item(withTag: Self.menuRenameTag)?.representedObject = row.category.id
            return
        }

        // 센티넬 타입(그룹 헤더, 북마크 행)은 메뉴 항목 전부 숨김
        if clickedItem is SidebarGroup || clickedItem is SidebarBookmarksRow {
            for item in menu.items { item.isHidden = true }
            return
        }

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
        FolderMediaCountService.shared.onUpdate = { [weak self] in self?.refreshVisibleCounts() }
    }

    /// 폴더 총계 계산이 끝나면 보이는 폴더 행의 숫자만 다시 그린다(행 재생성 없이 레이블만 갱신).
    private func refreshVisibleCounts() {
        let visible = outlineView.rows(in: outlineView.visibleRect)
        guard visible.length > 0 else { return }
        for row in visible.location..<(visible.location + visible.length) {
            guard let node = outlineView.item(atRow: row) as? FolderNode,
                  let cell = outlineView.view(atColumn: 0, row: row, makeIfNecessary: false) as? SidebarItemCellView else { continue }
            cell.count = Self.countText(for: node.url)
        }
    }

    private static func countText(for url: URL) -> String {
        guard let count = FolderMediaCountService.shared.count(for: url) else { return "" }
        return count > 0 ? "\(count)" : ""
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
