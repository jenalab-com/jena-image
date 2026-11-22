import AppKit

extension MainWindowController {
    func aiReferenceURLs() -> [URL] {
        let urls = contentMode == .viewer ? viewerVC.currentImageURL.map { [$0] } ?? [] : browserVC.selectedURLs()
        return urls.filter { ImageFile(url: $0)?.isImage == true }
    }

    var aiDestinationURL: URL? {
        guard !browserVC.isCollectionMode, currentCategoryID == nil else { return nil }
        return currentFolderURL
    }

    @objc func showAIMode(_ sender: Any?) {
        let firstOpen = aiSplitItem == nil
        if firstOpen {
            let controller = AIChatViewController()
            controller.currentDestination = { [weak self] in self?.aiDestinationURL }
            controller.onOpenImages = { [weak self] urls in
                guard let self else { return }
                let files = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
                    .compactMap { ImageFile(url: $0) }.filter { $0.isImage }
                guard let first = files.first else {
                    self.showError(AIImageGenerationError(message: "저장된 이미지를 찾을 수 없습니다. 파일이 이동되거나 삭제되었는지 확인해 주세요."))
                    return
                }
                self.browser(self.browserVC, didRequestViewImage: first.url, inList: files)
            }
            controller.onSaved = { [weak self] _ in self?.refreshAfterExternalChange() }
            controller.onClose = { [weak self] in self?.showAIMode(nil) }
            aiChatVC = controller
            let item = NSSplitViewItem(viewController: controller)
            item.minimumThickness = AIChatViewController.minimumWidth
            item.maximumThickness = AIChatViewController.maximumWidth
            item.canCollapse = true
            item.holdingPriority = .init(260)
            aiSplitItem = item
            splitViewController.addSplitViewItem(item)
            controller.selectionChanged(aiReferenceURLs())
        }
        guard let item = aiSplitItem else { return }
        let visible = firstOpen || item.isCollapsed
        setSidePanel(item, visible: visible, minimumWindowWidth: 940,
                     defaultWidth: AIChatViewController.defaultWidth, firstOpen: firstOpen)
        if visible, !firstOpen { aiChatVC?.selectionChanged(aiReferenceURLs()) }
        aiChatVC?.refreshDestination()
    }
}
