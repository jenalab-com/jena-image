import AppKit

/// 파일명 검색 결과 화면의 상태. 닫을 때 돌아갈 곳을 함께 기억한다.
struct SearchPresentation {
    let query: String
    /// 검색 범위 — 폴더 모드면 현재 폴더(하위 폴더 포함), 북마크·카테고리 모드면 nil(그때 목록 안에서 찾음)
    let scopeFolder: URL?
    let returnCategory: UUID?
    let returnBookmarks: Bool
    let returnFolder: URL?
}

// MARK: - 파일명 검색 (툴바 검색 필드)

extension MainWindowController: NSSearchFieldDelegate {

    /// 툴바 검색 필드. 툴바가 모드에 따라 다시 짜여도 같은 인스턴스를 돌려줘 입력한 글자가 남는다.
    func makeSearchToolbarItem() -> NSSearchToolbarItem {
        if let existing = searchToolbarItem { return existing }
        let item = NSSearchToolbarItem(itemIdentifier: ToolbarID.search)
        item.label = "검색"
        item.toolTip = "파일명으로 검색 (⌘F)"
        item.preferredWidthForSearchField = 200
        item.resignsFirstResponderWithCancel = true
        let field = item.searchField
        field.placeholderString = "파일명 검색"
        field.sendsWholeSearchString = true   // Return을 눌렀을 때만 검색
        field.sendsSearchStringImmediately = false
        field.target = self
        field.action = #selector(searchFieldAction(_:))
        field.delegate = self
        searchToolbarItem = item
        return item
    }

    /// 편집 메뉴 "검색" ⌘F — 검색 필드에 포커스를 준다.
    @objc func focusSearchField(_ sender: Any?) {
        guard contentMode == .browser else { return }
        searchToolbarItem?.beginSearchInteraction()
    }

    /// 검색 필드에서 Return(검색) 또는 취소(x·ESC → 빈 문자열)가 들어온다.
    @objc func searchFieldAction(_ sender: NSSearchField) {
        let query = sender.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            closeSearchResults()
        } else {
            searchFiles(matching: query)
        }
    }

    /// 파일명 검색 실행. 폴더 모드에선 현재 폴더와 하위 폴더 전체, 북마크·카테고리·유사 모드에선 그 목록 안에서 찾는다.
    /// - Parameter resetScroll: 새 검색이면 맨 위로, 같은 조건의 재검색(뷰어 복귀·파일 변경)이면 스크롤을 유지한다.
    func searchFiles(matching query: String, resetScroll: Bool = true) {
        guard contentMode == .browser else { return }
        let terms = Self.searchTerms(from: query)
        guard !terms.isEmpty else { return }

        // 결과 화면에서 다시 검색해도 뒤로 가기는 처음 출발한 목록으로 이어진다.
        let previous = searchPresentation
        let scopeFolder = previous?.scopeFolder
            ?? ((browserVC.isCollectionMode) ? nil : currentFolderURL)
        let presentation = SearchPresentation(
            query: query,
            scopeFolder: scopeFolder,
            returnCategory: previous?.returnCategory ?? currentCategoryID,
            returnBookmarks: previous?.returnBookmarks ?? browserVC.isBookmarkMode,
            returnFolder: previous?.returnFolder ?? currentFolderURL
        )

        if let folder = scopeFolder {
            folderLoadGeneration += 1
            let generation = folderLoadGeneration
            let sortKey = AppSettings.shared.sortKey
            let ascending = AppSettings.shared.sortAscending
            let service = fileService
            Task { @MainActor in
                let result = await Task.detached(priority: .userInitiated) {
                    service.recursiveImages(at: folder, sortKey: sortKey, ascending: ascending)
                }.value
                guard self.folderLoadGeneration == generation, self.contentMode == .browser else { return }
                switch result {
                case .success(let urls):
                    self.searchPresentation = presentation
                    self.presentSearchResults(urls.filter { Self.matches($0, terms: terms) }, resetScroll: resetScroll)
                case .failure(let error):
                    self.showError(error)
                }
            }
        } else {
            // 북마크·카테고리·유사 목록: 이미 화면에 있는 이미지 안에서 바로 거른다.
            let listed = searchSourceURLs ?? browserVC.listedImageURLs
            searchSourceURLs = listed
            searchPresentation = presentation
            presentSearchResults(listed.filter { Self.matches($0, terms: terms) }, resetScroll: resetScroll)
        }
    }

    /// 현재 검색을 같은 조건으로 다시 돌린다(파일 변경·정렬 변경·뷰어 복귀 뒤).
    func refreshSearchResults() {
        guard let presentation = searchPresentation, contentMode == .browser else { return }
        if presentation.scopeFolder != nil {
            searchFiles(matching: presentation.query, resetScroll: false)
        } else {
            let terms = Self.searchTerms(from: presentation.query)
            let listed = (searchSourceURLs ?? []).filter { FileManager.default.fileExists(atPath: $0.path) }
            presentSearchResults(listed.filter { Self.matches($0, terms: terms) }, resetScroll: false)
        }
    }

    private func presentSearchResults(_ urls: [URL], resetScroll: Bool) {
        guard let presentation = searchPresentation else { return }
        let selected = Set(browserVC.selectedURLs())
        let files = urls.compactMap { ImageFile(url: $0) }
        currentCategoryID = nil
        browserVC.displaySearchResults(files, query: presentation.query, resetScroll: resetScroll)
        if !selected.isEmpty { browserVC.restoreSelection(urls: selected) }
        let scopeName = presentation.scopeFolder?.lastPathComponent
            ?? (presentation.returnBookmarks ? "북마크" : "현재 목록")
        window?.title = "검색 · \"\(presentation.query)\" · \(scopeName) · \(files.count)개"
        statusBar.update(folderCount: 0, imageCount: files.count, selectionCount: browserVC.selectedURLs().count)
        updateToolbarState()
    }

    /// 검색 상태를 지운다(폴더 이동·북마크/카테고리 전환 시). 필드의 글자도 함께 비운다.
    func clearSearch() {
        searchPresentation = nil
        searchSourceURLs = nil
        searchToolbarItem?.searchField.stringValue = ""
    }

    /// 검색 결과를 닫고 출발했던 목록으로 돌아간다.
    func closeSearchResults() {
        guard let presentation = searchPresentation else {
            searchToolbarItem?.searchField.stringValue = ""
            return
        }
        clearSearch()
        if let category = presentation.returnCategory { showCategory(category) }
        else if presentation.returnBookmarks { showBookmarks() }
        else if let folder = presentation.returnFolder { navigateToFolder(folder) }
        else { showBookmarks() }
    }

    // MARK: NSSearchFieldDelegate

    /// x 버튼·ESC로 검색을 끝내면 결과를 닫는다. (sendsWholeSearchString이라 action이 빈 문자열로 오지 않을 수 있어 여기서 처리)
    func searchFieldDidEndSearching(_ sender: NSSearchField) {
        if searchPresentation != nil { closeSearchResults() }
    }

    // MARK: 매칭

    /// 공백으로 나눈 낱말을 모두 포함해야 일치(AND). 대소문자·발음 구별 부호는 무시한다.
    static func searchTerms(from query: String) -> [String] {
        query.split(whereSeparator: { $0.isWhitespace }).map(String.init).filter { !$0.isEmpty }
    }

    static func matches(_ url: URL, terms: [String]) -> Bool {
        let name = url.lastPathComponent
        return terms.allSatisfy { name.localizedStandardContains($0) }
    }
}
