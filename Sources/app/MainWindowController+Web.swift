import AppKit

extension MainWindowController {
    /// 웹 패널을 열고 접는다. 처음 열 때 패널을 만들어 사이드바 바로 오른쪽(목록·뷰어 왼쪽)에 넣고 지난 탭들을 복원한다.
    @objc func showWebMode(_ sender: Any?) {
        let firstOpen = webSplitItem == nil
        if firstOpen {
            let engine = makeWebEngine()
            let controller = WebPanelViewController(engine: engine, settings: settings)
            controller.onClose = { [weak self] in self?.showWebMode(nil) }
            engine.saveFolderProvider = { [weak self] in self?.webSaveFolderURL }
            engine.onSaveImage = { [weak self] report, folder in self?.saveWebImage(report, to: folder) }
            let saver = WebImageSaver(engine: engine)
            saver.onFinish = { [weak self] result, folder in self?.webImageSaveFinished(result, in: folder) }
            webImageSaver = saver
            webPanelVC = controller
            let item = NSSplitViewItem(viewController: controller)
            item.minimumThickness = WebPanelViewController.minimumWidth
            item.maximumThickness = WebPanelViewController.maximumWidth
            item.canCollapse = true
            // 창 크기가 바뀌면 목록·뷰어 칸(기본 250)이 먼저 늘고 줄도록 사이드바와 같은 260으로 둔다.
            item.holdingPriority = .init(260)
            webSplitItem = item
            splitViewController.insertSplitViewItem(item, at: 1)
            controller.loadInitialPage()
        }
        guard let item = webSplitItem else { return }
        let visible = firstOpen || item.isCollapsed
        setSidePanel(item, visible: visible, minimumWindowWidth: 980,
                     defaultWidth: WebPanelViewController.defaultWidth, firstOpen: firstOpen)
        if visible, webPanelVC?.engine.currentURL == nil { webPanelVC?.focusAddress() }
    }

    /// 보기 → 새 탭. 웹 패널이 펼쳐져 있을 때만 빈 탭을 열고 주소창에 포커스를 둔다.
    @objc func newWebTab(_ sender: Any?) {
        guard webSplitItem?.isCollapsed == false else { return }
        webPanelVC?.newTab()
    }

    /// 곁 패널(왼쪽 웹·오른쪽 AI) 공통: 다른 쪽을 접고, 창 최소 폭을 맞추고, 처음 열 때 나눔선 위치를 잡는다.
    func setSidePanel(_ item: NSSplitViewItem, visible: Bool, minimumWindowWidth: CGFloat, defaultWidth: CGFloat, firstOpen: Bool) {
        sidePanelMinimumWidths[ObjectIdentifier(item)] = minimumWindowWidth
        if firstOpen { observeSidePanel(item) }
        if visible {
            for other in [aiSplitItem, webSplitItem].compactMap({ $0 }) where other !== item { other.isCollapsed = true }
        }
        item.isCollapsed = !visible
        syncSidePanelState()
        if visible, let window, window.frame.width < minimumWindowWidth {
            window.setFrame(Self.widenedFrame(window.frame, to: minimumWindowWidth,
                                              within: (window.screen ?? NSScreen.main)?.visibleFrame), display: true)
        }
        let items = splitViewController.splitViewItems
        guard firstOpen, let index = items.firstIndex(of: item),
              let contentIndex = contentSplitItem.flatMap({ items.firstIndex(of: $0) }) else { return }
        let splitView = splitViewController.splitView
        splitViewController.view.layoutSubtreeIfNeeded()
        // 패널과 목록·뷰어 칸 사이의 나눔선을 옮겨 목록·뷰어 칸이 줄어들게 한다(사이에 다른 칸은 두지 않는다).
        if index < contentIndex {
            // 목록 왼쪽(웹): 패널의 왼쪽 끝에서 기본 폭만큼. 사이드바를 접어 두었으면 왼쪽 끝은 창 왼쪽 끝이다.
            let start = splitView.arrangedSubviews[index].frame.minX
            splitView.setPosition(start + defaultWidth, ofDividerAt: index)
        } else {
            // 목록 오른쪽(AI): 창 오른쪽 끝에서 기본 폭만큼.
            splitView.setPosition(splitView.bounds.width - defaultWidth, ofDividerAt: index - 1)
        }
    }

    /// 최소 폭까지 넓힌 창 틀. 화면의 보이는 영역 밖으로 나가면 왼쪽으로 당기고, 화면이 더 좁으면 화면 폭에 맞춘다.
    static func widenedFrame(_ frame: NSRect, to width: CGFloat, within visible: NSRect?) -> NSRect {
        var result = frame
        result.size.width = width
        guard let visible else { return result }
        result.size.width = min(width, visible.width)
        result.origin.x = max(visible.minX, min(result.origin.x, visible.maxX - result.width))
        return result
    }

    /// 나눔선을 끌어 접고 펼쳐도(버튼을 거치지 않아도) 상태를 맞춘다. 항목의 접힘을 관찰하고,
    /// 나눔선을 놓은 뒤의 크기 변화에서도 한 번 더 맞춘다(같은 값이면 바뀌는 것이 없다).
    private func observeSidePanel(_ item: NSSplitViewItem) {
        sidePanelObservations.append(item.observe(\.isCollapsed) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.syncSidePanelState() }
        })
        guard sidePanelResizeObserver == nil else { return }
        sidePanelResizeObserver = NotificationCenter.default.addObserver(
            forName: NSSplitView.didResizeSubviewsNotification, object: splitViewController.splitView, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncSidePanelState() }
        }
    }

    /// 펼친 곁 패널에 따라 창 최소 폭·툴바 웹 버튼·웹 페이지의 보임 표시를 맞춘다.
    func syncSidePanelState() {
        let expanded = [aiSplitItem, webSplitItem].compactMap { $0 }.filter { !$0.isCollapsed }
        let minimumWidth = expanded.compactMap { sidePanelMinimumWidths[ObjectIdentifier($0)] }.max() ?? 700
        window?.minSize = NSSize(width: minimumWidth, height: 500)
        webPanelVC?.engine.isPresented = webSplitItem?.isCollapsed == false
        syncWebToolbarButton()
    }

    /// 툴바 웹 버튼은 패널이 펼쳐져 있을 때만 켜진다(버튼·메뉴·닫기·AI 열기·나눔선 어느 길로 바뀌어도).
    func syncWebToolbarButton() {
        let item = window?.toolbar?.items.first { $0.itemIdentifier == ToolbarID.web }
        (item?.view as? NSButton)?.state = webSplitItem?.isCollapsed == false ? .on : .off
    }

    // MARK: 이미지 저장

    /// 웹 이미지를 저장할 지금 폴더. 목록이 실제 폴더를 보여 줄 때만 있다(AI 패널과 같은 규칙).
    var webSaveFolderURL: URL? { aiDestinationURL }

    /// 폴더는 부르는 쪽이 고른 순간의 것이다. 내려받는 동안 화면이 바뀌어도 그대로 간다.
    func saveWebImage(_ report: WebImageReport, to folder: URL) {
        webImageSaver?.save(report, to: folder)
    }

    /// 웹 패널에서 끌어온 이미지를 놓는다. `folder`가 nil이면 지금 폴더. 저장할 주소는 보드가 아니라 스크립트가 알린 값이다.
    func handleWebImageDrop(from info: NSDraggingInfo, to folder: URL?) -> Bool {
        guard let engine = webPanelVC?.engine, engine.isDragSource(info.draggingSource),
              let report = engine.takeDraggedImage(), let destination = folder ?? webSaveFolderURL else { return false }
        // 놓은 드래그는 다 썼다. 새 dragstart 없는 다음 드래그로 같은 이미지를 다시 저장하지 않는다.
        engine.clearDraggedImage()
        saveWebImage(report, to: destination)
        return true
    }

    /// 목록·사이드바의 웹 이미지 놓기를 잇는다. 패널이 아직 없으면 웹 드래그가 아니다.
    func connectWebImageDrops() {
        let isWebImageDrag: (NSDraggingInfo) -> Bool = { [weak self] info in
            guard let self, let panel = self.webPanelVC, panel.engine.isDragSource(info.draggingSource) else { return false }
            if panel.engine.takeDraggedImage() != nil { return true }
            // 패널에서 끌어왔지만 이미지가 아니다(글·링크·영상 등). 왜 놓을 수 없는지 패널에 알린다.
            let notice = "끌어온 항목에서 저장할 이미지를 찾지 못했습니다."
            if panel.statusLabel.stringValue != notice { panel.showStatus(notice) }
            return false
        }
        browserVC.isWebImageDrag = isWebImageDrag
        browserVC.hasWebSaveFolder = { [weak self] in self?.webSaveFolderURL != nil }
        browserVC.onWebImageDrop = { [weak self] info, folder in self?.handleWebImageDrop(from: info, to: folder) ?? false }
        sidebarVC.isWebImageDrag = isWebImageDrag
        sidebarVC.onWebImageDrop = { [weak self] info, folder in self?.handleWebImageDrop(from: info, to: folder) ?? false }
    }

    /// 결과는 상태 줄에 알린다. 목록 화면이 바로 그 폴더를 보고 있을 때만 목록을 갱신하고 새 파일을 고른다
    /// (뷰어로 보던 이미지는 바꾸지 않는다).
    private func webImageSaveFinished(_ result: Result<URL, WebImageSaveError>, in folder: URL) {
        sidebarVC.reloadFolder(at: folder)
        switch result {
        case .success(let file):
            webPanelVC?.showStatus("저장했습니다: \(file.lastPathComponent)")
            if contentMode == .browser, webSaveFolderURL == folder {
                pendingSelectionURLs = [file]
                refreshCurrentFolder()
            }
        case .failure(let error):
            webPanelVC?.showStatus("저장하지 못했습니다: \(error.localizedDescription)")
        }
    }
}
