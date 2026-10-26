import AppKit

// MARK: - File Operations

extension MainWindowController {

    func performDelete(urls: [URL]) {
        let count = urls.count
        let alert = NSAlert()
        alert.messageText = "\(count)개 항목을 휴지통으로 이동하시겠습니까?"
        alert.informativeText = "이 작업은 취소할 수 있습니다."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "삭제")
        alert.addButton(withTitle: "취소")
        alert.buttons.first?.keyEquivalent = "\r"

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        // 삭제 대상 폴더의 watcher 해제
        for url in urls {
            folderWatcher.unwatch(url)
        }

        var failedURLs: [URL] = []
        for url in urls {
            if case .failure = fileService.trashFile(at: url) {
                failedURLs.append(url)
            } else {
                ThumbnailProvider.shared.invalidate(for: url)
                bookmarkStore.remove(url)
                removeDeletedFileFromCategories(url)
            }
        }

        if !failedURLs.isEmpty {
            showError(FileServiceError.operationFailed("일부 파일을 삭제할 수 없습니다"))
        }

        // 현재 폴더가 삭제되었으면 부모로 이동
        let parentFolders = Set(urls.map { $0.deletingLastPathComponent() })
        if !browserVC.isCategoryMode, let current = currentFolderURL, urls.contains(where: { current.path.hasPrefix($0.path) }) {
            if let parent = parentFolders.first {
                navigateToFolder(parent)
            }
        } else {
            if !browserVC.isBookmarkMode { refreshCurrentFolder() }
        }
        for folder in parentFolders {
            sidebarVC.reloadFolder(at: folder)
        }
    }

    func performMove(urls: [URL]) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.prompt = "이동"
        panel.message = "이동할 폴더를 선택하세요"

        guard panel.runModal() == .OK, let target = panel.url else { return }
        performMoveToFolder(urls: urls, target: target)
    }

    func performMoveToFolder(urls: [URL], target: URL) {
        let sourceFolders = Set(urls.map { $0.deletingLastPathComponent() })

        for url in urls {
            let result = fileService.moveFile(from: url, to: target)
            switch result {
            case .success(let newURL):
                ThumbnailProvider.shared.invalidate(for: url)
                relocateCategories(from: url, to: newURL)
            case .failure(let error):
                if case .nameConflict = error {
                    handleFileConflict(source: url, target: target, isMove: true)
                } else {
                    showError(error)
                }
            }
        }
        refreshCurrentFolder()
        sidebarVC.reloadFolder(at: target)
        for sourceFolder in sourceFolders {
            if sourceFolder != target {
                sidebarVC.reloadFolder(at: sourceFolder)
            }
        }
    }

    func performCopy(urls: [URL]) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.prompt = "복사"
        panel.message = "복사할 폴더를 선택하세요"

        guard panel.runModal() == .OK, let target = panel.url else { return }

        for url in urls {
            let result = fileService.copyFile(from: url, to: target)
            if case .failure(let error) = result {
                if case .nameConflict = error {
                    handleFileConflict(source: url, target: target, isMove: false)
                } else {
                    showError(error)
                }
            }
        }
    }

    func performDuplicate(urls: [URL]) {
        guard !urls.isEmpty else { return }
        for url in urls {
            if case .failure(let error) = fileService.duplicateFile(at: url) {
                showError(error)
            }
        }
        refreshCurrentFolder()
    }

    func performRename(url: URL, newName: String) {
        let result = fileService.renameFile(at: url, newName: newName)
        switch result {
        case .success(let newURL):
            ThumbnailProvider.shared.invalidate(for: url)
            bookmarkStore.rename(from: url, to: newURL)
            relocateCategories(from: url, to: newURL)
            if contentMode == .viewer {
                viewerVC.updateCurrentImage(oldURL: url, newURL: newURL)
            }
            if !browserVC.isBookmarkMode { refreshCurrentFolder() }
            let parentFolder = url.deletingLastPathComponent()
            sidebarVC.reloadFolder(at: parentFolder)
        case .failure(let error):
            showError(error)
        }
    }

    func performExport(url: URL) {
        Task { @MainActor in
            let loadResult = await imageService.loadImage(at: url)
            guard case .success(let image) = loadResult else {
                showError(ImageServiceError.loadFailed(url))
                return
            }

            let panel = NSSavePanel()
            panel.nameFieldStringValue = url.lastPathComponent

            let accessory = ExportAccessoryView()
            if let currentFormat = ImageFormat.from(extension: url.pathExtension) {
                accessory.selectedFormat = currentFormat
            }
            panel.accessoryView = accessory

            guard panel.runModal() == .OK, let saveURL = panel.url else { return }

            let format = accessory.selectedFormat
            let quality = accessory.quality
            let exportResult = self.imageService.exportImage(image, to: saveURL, format: format, quality: quality)

            if case .failure(let error) = exportResult {
                showError(error)
            }
        }
    }

    /// 선택한 이미지들을 같은 설정으로 내보내는 시트를 연다(비디오 제외).
    func performBatchExport(urls: [URL]) {
        guard let window, batchExportController == nil else { return }
        let images = urls.compactMap { ImageFile(url: $0) }.filter { !$0.isVideo }.map(\.url)
        guard !images.isEmpty else { return }
        let controller = BatchExportWindowController(sources: images)
        controller.onFinish = { [weak self] report, destination in
            guard let self else { return }
            self.batchExportController = nil
            if !report.succeeded.isEmpty {
                self.sidebarVC.reloadFolder(at: destination)
                if destination == self.currentFolderURL || AppSettings.shared.recursiveBrowsing {
                    self.refreshCurrentFolder()
                }
            }
            guard !report.failed.isEmpty else { return }
            let alert = NSAlert()
            alert.messageText = "일부 이미지를 내보내지 못했습니다"
            let lines = report.failed.prefix(8).map { "• \($0.source.lastPathComponent) — \($0.reason)" }
            var text = "성공 \(report.succeeded.count)개, 실패 \(report.failed.count)개\n" + lines.joined(separator: "\n")
            if report.failed.count > 8 { text += "\n…" }
            alert.informativeText = text
            alert.alertStyle = .warning
            alert.beginSheetModal(for: window, completionHandler: nil)
        }
        batchExportController = controller
        controller.beginSheet(for: window)
    }

    /// 클립보드 이미지를 PNG로 현재 폴더에 저장하고, 목록을 갱신한 뒤 새 파일을 선택한다.
    /// 파일명은 macOS 스크린샷과 같은 "클립보드 이미지 YYYY-MM-DD HH.mm.ss.png" 꼴, 겹치면 번호를 붙인다.
    func saveClipboardImage(_ image: NSImage, to folder: URL) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let baseName = "클립보드 이미지 \(formatter.string(from: Date())).png"
        let name = fileService.fileExists(at: folder.appendingPathComponent(baseName))
            ? generateUniqueName(for: baseName, in: folder)
            : baseName
        let destination = folder.appendingPathComponent(name)

        switch imageService.exportImage(image, to: destination, format: .png, quality: 100) {
        case .success:
            pendingSelectionURLs = [destination]
            refreshCurrentFolder()
            sidebarVC.reloadFolder(at: folder)
        case .failure(let error):
            showError(error)
        }
    }

    private func handleFileConflict(source: URL, target: URL, isMove: Bool) {
        let fileName = source.lastPathComponent
        let alert = NSAlert()
        alert.messageText = "'\(fileName)' 파일이 이미 존재합니다."
        alert.addButton(withTitle: "이름 변경")
        alert.addButton(withTitle: "덮어쓰기")
        alert.addButton(withTitle: "건너뛰기")

        let response = alert.runModal()
        let destination = target.appendingPathComponent(fileName)

        switch response {
        case .alertFirstButtonReturn:
            let newName = generateUniqueName(for: fileName, in: target)
            let newDest = target.appendingPathComponent(newName)
            if isMove {
                do {
                    try FileManager.default.moveItem(at: source, to: newDest)
                    relocateCategories(from: source, to: newDest)
                } catch { showError(error) }
            } else {
                try? FileManager.default.copyItem(at: source, to: newDest)
            }
        case .alertSecondButtonReturn:
            try? FileManager.default.removeItem(at: destination)
            if isMove {
                do {
                    try FileManager.default.moveItem(at: source, to: destination)
                    relocateCategories(from: source, to: destination)
                } catch { showError(error) }
            } else {
                try? FileManager.default.copyItem(at: source, to: destination)
            }
        default: break
        }
    }

    func generateUniqueName(for name: String, in folder: URL) -> String {
        let baseName = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var counter = 2

        while true {
            let candidate = ext.isEmpty ? "\(baseName) \(counter)" : "\(baseName) \(counter).\(ext)"
            let candidateURL = folder.appendingPathComponent(candidate)
            if !fileService.fileExists(at: candidateURL) { return candidate }
            counter += 1
        }
    }
}
