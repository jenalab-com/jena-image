import AppKit

// MARK: - 공유 (macOS Share Sheet)

extension MainWindowController: NSSharingServicePickerDelegate {

    /// 공유할 수 있는 선택 항목 — 실제로 존재하는 파일(이미지·영상)만. 폴더와 깨진 북마크는 제외한다.
    func shareableURLs() -> [URL] {
        activeSelectedURLs().filter { url in
            ImageFile(url: url) != nil && FileManager.default.fileExists(atPath: url.path)
        }
    }

    /// 파일 메뉴 "공유…" — 선택 항목을 Share Sheet로 보낸다.
    @objc func shareSelected(_ sender: Any?) {
        share(urls: shareableURLs())
    }

    /// 툴바 공유 버튼 — 피커를 버튼 아래에 띄운다.
    @objc func shareFromToolbar(_ sender: NSButton) {
        let urls = shareableURLs()
        guard !urls.isEmpty else { return }
        let picker = NSSharingServicePicker(items: urls.map { $0 as NSURL })
        picker.delegate = self
        sharingPicker = picker
        picker.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
    }

    /// 공유 피커를 선택 항목(브라우저 셀 또는 뷰어 화면) 옆에 띄운다.
    func share(urls: [URL]) {
        guard !urls.isEmpty else { return }

        let anchorView: NSView
        let anchorRect: NSRect
        if contentMode == .viewer {
            anchorView = viewerVC.view
            anchorRect = viewerVC.view.bounds
        } else if let (rect, view) = browserVC.anchorForSelection() {
            anchorView = view
            anchorRect = rect
        } else {
            anchorView = browserVC.view
            anchorRect = browserVC.view.bounds
        }

        let picker = NSSharingServicePicker(items: urls.map { $0 as NSURL })
        picker.delegate = self
        sharingPicker = picker
        picker.show(relativeTo: anchorRect, of: anchorView, preferredEdge: .minY)
    }

    // MARK: NSSharingServicePickerDelegate

    func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, didChoose service: NSSharingService?) {
        sharingPicker = nil
    }
}
