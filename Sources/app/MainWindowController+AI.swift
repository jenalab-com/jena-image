import AppKit

extension MainWindowController {
    func aiReferenceURLs() -> [URL] {
        let urls = contentMode == .viewer ? viewerVC.currentImageURL.map { [$0] } ?? [] : browserVC.selectedURLs()
        return urls.filter { ImageFile(url: $0)?.isImage == true }
    }

    @objc func showAIMode(_ sender: Any?) {
        if aiWindowController == nil {
            let controller = AIImageWindowController()
            controller.selectedImages = { [weak self] in self?.aiReferenceURLs() ?? [] }
            controller.onSaved = { [weak self] _ in self?.refreshAfterExternalChange() }
            aiWindowController = controller
        }
        aiWindowController?.configure(references: aiReferenceURLs(), destination: currentFolderURL)
        aiWindowController?.showWindow(nil)
    }
}
