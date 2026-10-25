import AppKit

private final class CategoryAssignment {
    let categoryID: UUID
    let urls: [URL]
    let included: Bool

    init(categoryID: UUID, urls: [URL], included: Bool) {
        self.categoryID = categoryID
        self.urls = urls
        self.included = included
    }
}

extension MainWindowController {
    func setupCategories() {
        sidebarVC.onAddCategory = { [weak self] in self?.createCategory(urls: [], openAfterCreation: true) }
        sidebarVC.onRenameCategory = { [weak self] id in self?.renameCategory(id) }
        sidebarVC.onSelectCategory = { [weak self] id in
            self?.activePanel = .sidebar
            self?.showCategory(id)
        }
        sidebarVC.onViewModeChanged = { [weak self] categories in
            guard let self else { return }
            if categories {
                do {
                    let list = try self.categoryStore.categories()
                    self.showCategory(self.lastCategoryID ?? list.first?.id)
                } catch { self.showError(error) }
            } else if let folder = self.currentFolderURL {
                self.navigateToFolder(folder)
                self.sidebarVC.selectFolder(at: folder)
            } else {
                self.showBookmarks()
            }
        }
        browserVC.categoryMenuProvider = { [weak self] urls in self?.categoryMenu(for: urls) ?? NSMenu() }
        viewerVC.categoryMenuProvider = { [weak self] urls in self?.categoryMenu(for: urls) ?? NSMenu() }
        browserVC.onRemoveFromCategory = { [weak self] urls in
            guard let self, let id = self.currentCategoryID else { return }
            do { try self.categoryStore.setMembership(urls, categoryID: id, included: false) }
            catch { self.showError(error) }
        }
        NotificationCenter.default.addObserver(forName: .categoriesChanged, object: categoryStore, queue: .main) { [weak self] _ in
            self?.refreshCategories()
        }
        refreshCategories()
    }

    func refreshCategories() {
        do {
            let categories = try categoryStore.categories()
            sidebarVC.setCategories(categories, selectedID: currentCategoryID)
            // 상세에서 분류를 바꿔도 이미지는 유지하고, 목록으로 돌아올 때 다시 읽는다.
            if browserVC.isCategoryMode, contentMode == .browser {
                let selected = Set(browserVC.selectedURLs())
                showCategory(currentCategoryID)
                browserVC.restoreSelection(urls: selected)
                statusBar.update(folderCount: 0,
                                 imageCount: categories.first(where: { $0.id == currentCategoryID })?.paths.count ?? 0,
                                 selectionCount: browserVC.selectedURLs().count)
            }
        } catch { showError(error) }
    }

    func showCategory(_ id: UUID?) {
        clearSimilaritySearch()
        do {
            let category = try categoryStore.categories().first { $0.id == id }
            folderLoadGeneration += 1
            currentCategoryID = category?.id
            if let category { lastCategoryID = category.id }
            switchToMode(.browser)
            let files = category?.urls.compactMap { ImageFile(url: $0) }.filter { !$0.isVideo } ?? []
            browserVC.displayCategory(files)
            updateToolbarState()
            sidebarVC.selectCategory(category?.id)
            window?.title = category?.name ?? "카테고리"
            statusBar.update(folderCount: 0, imageCount: files.count, selectionCount: 0)
        } catch { showError(error) }
    }

    private func categoryMenu(for urls: [URL]) -> NSMenu {
        let menu = NSMenu()
        do {
            let categories = try categoryStore.categories()
            for category in categories {
                let members = Set(category.paths)
                let count = urls.filter { members.contains($0.standardizedFileURL.path) }.count
                let item = NSMenuItem(title: category.name, action: #selector(assignCategory(_:)), keyEquivalent: "")
                item.target = self
                item.state = count == urls.count ? .on : (count == 0 ? .off : .mixed)
                item.representedObject = CategoryAssignment(categoryID: category.id, urls: urls, included: count != urls.count)
                menu.addItem(item)
            }
            if !categories.isEmpty { menu.addItem(.separator()) }
            let create = NSMenuItem(title: "새 카테고리…", action: #selector(createCategoryFromMenu(_:)), keyEquivalent: "")
            create.target = self
            create.representedObject = urls
            menu.addItem(create)
        } catch {
            let item = NSMenuItem(title: "카테고리 데이터를 읽을 수 없습니다", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        return menu
    }

    @objc private func assignCategory(_ sender: NSMenuItem) {
        guard let assignment = sender.representedObject as? CategoryAssignment else { return }
        do {
            try categoryStore.setMembership(assignment.urls, categoryID: assignment.categoryID, included: assignment.included)
        } catch { showError(error) }
    }

    @objc private func createCategoryFromMenu(_ sender: NSMenuItem) {
        createCategory(urls: sender.representedObject as? [URL] ?? [], openAfterCreation: false)
    }

    private func createCategory(urls: [URL], openAfterCreation: Bool) {
        let alert = NSAlert()
        alert.messageText = "카테고리 추가"
        alert.informativeText = "카테고리 이름을 입력하세요."
        alert.addButton(withTitle: "추가")
        alert.addButton(withTitle: "취소")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.placeholderString = "카테고리 이름"
        field.setAccessibilityLabel("카테고리 이름")
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        while alert.runModal() == .alertFirstButtonReturn {
            do {
                let category = try categoryStore.create(name: field.stringValue, urls: urls)
                if openAfterCreation {
                    sidebarVC.setCategoryView(true)
                    showCategory(category.id)
                }
                return
            } catch CategoryStoreError.emptyName {
                alert.informativeText = CategoryStoreError.emptyName.localizedDescription
            } catch CategoryStoreError.duplicateName {
                alert.informativeText = CategoryStoreError.duplicateName.localizedDescription
            } catch { showError(error); return }
        }
    }

    private func renameCategory(_ id: UUID) {
        do {
            guard let category = try categoryStore.categories().first(where: { $0.id == id }) else { return }
            let alert = NSAlert()
            alert.messageText = "카테고리 이름 변경"
            alert.informativeText = "새 이름을 입력하세요."
            alert.addButton(withTitle: "변경")
            alert.addButton(withTitle: "취소")
            let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
            field.stringValue = category.name
            field.setAccessibilityLabel("카테고리 이름")
            alert.accessoryView = field
            alert.window.initialFirstResponder = field
            while alert.runModal() == .alertFirstButtonReturn {
                do {
                    try categoryStore.rename(categoryID: id, name: field.stringValue)
                    return
                } catch CategoryStoreError.emptyName {
                    alert.informativeText = CategoryStoreError.emptyName.localizedDescription
                } catch CategoryStoreError.duplicateName {
                    alert.informativeText = CategoryStoreError.duplicateName.localizedDescription
                }
            }
        } catch { showError(error) }
    }

    func relocateCategories(from oldURL: URL, to newURL: URL) {
        if contentMode == .viewer, browserVC.isCategoryMode {
            viewerVC.updateCurrentImage(oldURL: oldURL, newURL: newURL)
        }
        do { try categoryStore.relocate(from: oldURL, to: newURL) }
        catch { showError(error) }
    }

    func removeDeletedFileFromCategories(_ url: URL) {
        do { try categoryStore.removeDeletedFile(at: url) }
        catch { showError(error) }
    }
}
