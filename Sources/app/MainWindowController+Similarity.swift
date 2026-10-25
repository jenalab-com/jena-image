import AppKit

struct SimilarityPresentation {
    let reference: URL
    let result: SimilarImageSearchResult
    let returnCategory: UUID?
    let returnBookmarks: Bool
    let returnFolder: URL?
}

extension MainWindowController {
    func findSimilarImages(to reference: URL) {
        guard let window, similarityTask == nil else { return }
        let candidates = browserVC.listedImageURLs
        // 검색 결과에서 다시 검색해도 뒤로 가기는 처음 출발한 목록으로 이어진다.
        let previous = similarityPresentation
        let returnCategory = previous?.returnCategory ?? currentCategoryID
        let returnBookmarks = previous?.returnBookmarks ?? browserVC.isBookmarkMode
        let returnFolder = previous?.returnFolder ?? currentFolderURL
        folderLoadGeneration += 1
        let session = UUID()
        similaritySession = session
        let alert = NSAlert()
        alert.messageText = "비슷한 이미지 찾기"
        alert.informativeText = "현재 목록의 이미지 \(candidates.count)개 안에서 찾습니다. 저장된 분석은 재사용합니다."
        alert.addButton(withTitle: "취소")
        let progress = NSProgressIndicator(frame: NSRect(x: 0, y: 0, width: 340, height: 16))
        progress.style = .bar
        progress.isIndeterminate = true
        progress.startAnimation(nil)
        alert.accessoryView = progress
        similarityProgressAlert = alert
        alert.beginSheetModal(for: window) { [weak self] _ in
            guard let self, self.similaritySession == session else { return }
            self.similarityTask?.cancel()
            self.similarityTask = nil
            self.similaritySession = nil
            self.similarityProgressAlert = nil
        }
        let service = similarityService
        similarityTask = Task { [weak self] in
            do {
                let result = try await service.search(reference: reference, candidates: candidates) { [weak self] message in
                    Task { @MainActor [weak self] in
                        guard let self, self.similaritySession == session else { return }
                        self.similarityProgressAlert?.informativeText = message
                    }
                }
                guard let self, self.similaritySession == session, !Task.isCancelled else { return }
                self.endSimilarityProgress()
                self.similarityPresentation = SimilarityPresentation(reference: reference, result: result,
                    returnCategory: returnCategory, returnBookmarks: returnBookmarks, returnFolder: returnFolder)
                self.currentCategoryID = nil
                self.switchToMode(.browser)
                self.refreshSimilarityResults(resetScroll: true)
                if result.skippedCount > 0 || result.cacheWriteFailures > 0 {
                    let note = NSAlert()
                    note.messageText = "비슷한 이미지 검색 완료"
                    note.informativeText = "검색 가능 \(result.analyzedCount)개 중 가까운 \(result.matches.count)개를 표시합니다.\n건너뛴 이미지 \(result.skippedCount)개\n미다운로드 iCloud 파일과 분석할 수 없는 형식은 제외됩니다."
                    if result.cacheWriteFailures > 0 { note.informativeText += "\n일부 분석 결과를 저장하지 못해 다음 검색에서 다시 분석할 수 있습니다." }
                    note.beginSheetModal(for: window, completionHandler: nil)
                }
            } catch {
                guard let self, self.similaritySession == session else { return }
                self.endSimilarityProgress()
                if !(error is CancellationError) {
                    NSAlert(error: error as NSError).beginSheetModal(for: window, completionHandler: nil)
                }
            }
        }
    }

    private func endSimilarityProgress() {
        similaritySession = nil
        similarityTask = nil
        if let alert = similarityProgressAlert, let parent = alert.window.sheetParent { parent.endSheet(alert.window) }
        similarityProgressAlert = nil
    }

    func clearSimilaritySearch() {
        similarityTask?.cancel()
        endSimilarityProgress()
        similarityPresentation = nil
    }

    func refreshSimilarityResults(resetScroll: Bool = false) {
        guard let presentation = similarityPresentation, contentMode == .browser else { return }
        let selected = Set(browserVC.selectedURLs())
        let files = presentation.result.matches.compactMap { match -> ImageFile? in
            guard FileManager.default.fileExists(atPath: match.url.path) else { return nil }
            return ImageFile(url: match.url)
        }
        browserVC.displaySimilarImages(files, resetScroll: resetScroll)
        browserVC.restoreSelection(urls: selected)
        window?.title = "비슷한 이미지 · \(presentation.reference.lastPathComponent) · \(files.count)개 (유사도순)"
        statusBar.update(folderCount: 0, imageCount: files.count, selectionCount: browserVC.selectedURLs().count)
        updateToolbarState()
    }

    func closeSimilarityResults() {
        guard let presentation = similarityPresentation else { return }
        if let category = presentation.returnCategory { showCategory(category) }
        else if presentation.returnBookmarks { showBookmarks() }
        else if let folder = presentation.returnFolder { navigateToFolder(folder) }
        else { showBookmarks() }
    }
}
