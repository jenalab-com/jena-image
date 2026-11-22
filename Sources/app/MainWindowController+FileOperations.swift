import AppKit

// MARK: - File Operations

extension MainWindowController {

    /// `completion`은 실제로 지워진 항목을 받는다(없으면 빈 배열). 첫 확인 창에서 취소하면 불리지 않는다.
    func performDelete(urls: [URL], completion: (([URL]) -> Void)? = nil) {
        let count = urls.count
        let alert = NSAlert()
        alert.messageText = "\(count)개 항목을 휴지통으로 이동하시겠습니까?"
        alert.informativeText = "이 작업은 취소할 수 있습니다."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "삭제")
        alert.addButton(withTitle: "취소")
        alert.buttons.first?.keyEquivalent = "\r"

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        trashConfirmed(urls: urls, completion: completion)
    }

    /// 확인을 받은 뒤의 삭제. 휴지통으로 옮길 수 없는 항목은 바로 삭제할지 한 번 더 묻는다(Finder와 같은 흐름).
    ///
    /// Google Drive 같은 파일 제공자 폴더에서는 앱이 직접 만들지 않은 파일을 휴지통으로 옮길 수 없다 —
    /// macOS가 전체 디스크 접근 권한을 요구하고(2026-11-22 확인: 권한 판정 `kTCCServiceSystemPolicyAllFiles` 거부),
    /// `NSWorkspace.recycle`도 똑같이 거절된다. 삭제 자체는 그 권한 없이도 된다.
    func trashConfirmed(urls: [URL], completion: (([URL]) -> Void)? = nil) {
        // 삭제 대상 폴더의 watcher 해제
        for url in urls {
            folderWatcher.unwatch(url)
        }

        var notDeleted: Set<URL> = []
        var failures: [(url: URL, reason: String)] = []
        var needsPermanent: [(url: URL, refusal: TrashRefusal)] = []
        for url in urls {
            switch fileService.trashFile(at: url) {
            case .success: break
            case .failure(.trashUnavailable(_, let refusal, let reason)):
                // 폴더는 바로 삭제하지 않는다 — 안의 것까지 되돌릴 수 없이 지워지고, 도중에 실패하면 일부만 사라진다.
                if Self.isFolder(url) {
                    failures.append((url, reason + "\n  폴더는 바로 삭제하지 않습니다. Finder에서 지우거나 JenaImage에 전체 디스크 접근 권한을 주세요."))
                } else {
                    needsPermanent.append((url, refusal))
                }
            case .failure(let error): failures.append((url, error.localizedDescription))
            }
        }

        if !needsPermanent.isEmpty {
            let targets = needsPermanent.map(\.url)
            let trashed = urls.count - needsPermanent.count - failures.count
            let confirmed = askPermanentDelete?(targets)
                ?? confirmPermanentDelete(targets, refusals: needsPermanent.map(\.refusal), trashedCount: trashed)
            if confirmed {
                for url in targets {
                    if case .failure(let error) = fileService.deleteFilePermanently(at: url) {
                        failures.append((url, error.localizedDescription))
                    }
                }
            } else {
                // 사용자가 그만둔 것은 실패가 아니다 — 알리지 않고 그대로 둔다.
                notDeleted.formUnion(targets)
            }
        }
        notDeleted.formUnion(failures.map(\.url))
        finishDelete(urls: urls, notDeleted: notDeleted, failures: failures, completion: completion)
    }

    /// 실제 폴더인지(폴더를 가리키는 심볼릭 링크는 링크만 지워지므로 폴더로 치지 않는다).
    static func isFolder(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        return values?.isDirectory == true && values?.isSymbolicLink != true
    }

    /// "휴지통에 넣을 수 없습니다. 바로 삭제할까요?" 창을 띄우고 답을 돌려준다.
    private func confirmPermanentDelete(_ urls: [URL], refusals: [TrashRefusal], trashedCount: Int) -> Bool {
        let alert = Self.makePermanentDeleteAlert(urls, refusals: refusals, trashedCount: trashedCount)
        switch alert.runModal() {
        case .alertSecondButtonReturn:
            return true
        case .alertThirdButtonReturn:
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                NSWorkspace.shared.open(url)
            }
            return false
        default:
            return false
        }
    }

    /// 바로 삭제 확인 창. 실수로 Enter를 눌러도 지워지지 않게 **취소가 첫(기본) 버튼**이다.
    /// 둘째가 "바로 삭제", 권한으로 풀 수 있는 경우에만 셋째 "권한 설정 열기…"가 붙는다.
    static func makePermanentDeleteAlert(_ urls: [URL], refusals: [TrashRefusal], trashedCount: Int) -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = permanentDeleteQuestion(urls)
        let permissionCanHelp = refusals.contains(.noPermission)
        var paragraphs: [String] = []
        if trashedCount > 0 { paragraphs.append("고른 항목 중 \(trashedCount)개는 휴지통으로 옮겼습니다.") }
        if permissionCanHelp {
            paragraphs.append("macOS가 휴지통으로 옮기는 것을 허용하지 않았습니다. Google Drive 같은 클라우드 폴더에서는 앱에 '전체 디스크 접근 권한'이 없을 때 이렇게 됩니다.")
            paragraphs.append("바로 삭제하면 이 Mac의 휴지통에 들어가지 않아 여기서는 되돌릴 수 없습니다. 클라우드 폴더라면 그 서비스의 휴지통에 남을 수도 있습니다.")
        } else {
            paragraphs.append("이 볼륨에는 휴지통이 없습니다. 바로 삭제하면 되돌릴 수 없습니다.")
        }
        alert.informativeText = paragraphs.joined(separator: "\n\n")
        alert.addButton(withTitle: "취소")
        alert.addButton(withTitle: "바로 삭제").hasDestructiveAction = true
        if permissionCanHelp { alert.addButton(withTitle: "권한 설정 열기…") }
        return alert
    }

    static func permanentDeleteQuestion(_ urls: [URL]) -> String {
        urls.count == 1
            ? "'\(urls[0].lastPathComponent)'을(를) 휴지통에 넣을 수 없습니다. 바로 삭제할까요?"
            : "\(urls.count)개 항목을 휴지통에 넣을 수 없습니다. 바로 삭제할까요?"
    }

    /// 삭제 뒤처리: 지워진 항목의 썸네일·북마크·카테고리를 정리하고, 실패를 알리고, 화면을 갱신한다.
    /// `notDeleted`는 남아 있는 항목 전부(실패 + 사용자가 그만둔 것), `failures`는 그중 알릴 것.
    private func finishDelete(urls: [URL], notDeleted: Set<URL>, failures: [(url: URL, reason: String)], completion: (([URL]) -> Void)?) {
        let deleted = urls.filter { !notDeleted.contains($0) }
        for url in deleted {
            ThumbnailProvider.shared.invalidate(for: url)
            bookmarkStore.remove(url)
            removeDeletedFileFromCategories(url)
        }

        if !failures.isEmpty {
            if let onDeleteFailure {
                onDeleteFailure(failures)
            } else {
                showError(FileServiceError.operationFailed(Self.deleteFailureMessage(failures, total: urls.count)))
            }
        }

        // 현재 폴더가 삭제되었으면 부모로 이동
        let parentFolders = Set(urls.map { $0.deletingLastPathComponent() })
        if !browserVC.isCategoryMode, let current = currentFolderURL, deleted.contains(where: { current.path == $0.path || current.path.hasPrefix($0.path + "/") }) {
            if let parent = parentFolders.first {
                navigateToFolder(parent)
            }
        } else {
            if !browserVC.isBookmarkMode { refreshCurrentFolder() }
        }
        for folder in parentFolders {
            sidebarVC.reloadFolder(at: folder)
        }
        completion?(deleted)
    }

    /// 삭제 실패 안내. 어떤 파일이 왜 안 지워졌는지 그대로 보여 준다(여럿이면 앞의 셋만).
    static func deleteFailureMessage(_ failures: [(url: URL, reason: String)], total: Int) -> String {
        let head = failures.count == total
            ? "\(failures.count)개 항목을 삭제하지 못했습니다."
            : "\(total)개 중 \(failures.count)개 항목을 삭제하지 못했습니다."
        var lines = failures.prefix(3).map { "• \($0.url.lastPathComponent)\n  \($0.reason)" }
        if failures.count > 3 { lines.append("… 외 \(failures.count - 3)개") }
        return ([head] + lines).joined(separator: "\n")
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
            // 이미 그 폴더에 있으면 옮길 것이 없다. 겹침으로 보면 덮어쓰기가 원본 자신을 지운다.
            if url.isSameItem(as: target.appendingPathComponent(url.lastPathComponent)) { continue }
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
                needsFolderRefreshAfterViewerRename = true
            } else if !browserVC.isBookmarkMode {
                refreshCurrentFolder()
            }
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
            // 원본과 대상이 같은 파일이면 지우는 순간 원본이 사라진다.
            guard !source.isSameItem(as: destination) else { return }
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
        UniqueFileName.make(for: name, in: folder) { fileService.fileExists(at: $0) }
    }
}
