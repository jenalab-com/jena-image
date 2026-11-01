import AppKit

@MainActor
func runCompareLayoutTests(directory: URL) {
    runTest("비교 창은 동기화 토글을 늘리지 않고 이미지 칸에 높이를 준다") {
        let urls = [directory.appendingPathComponent("a.png"), directory.appendingPathComponent("b.png")]
        let controller = CompareWindowController(files: urls.compactMap { ImageFile(url: $0) }, imageService: ImageService())
        guard let window = controller.window, let content = window.contentView else { return check(false, "비교 창 생성") }
        window.isReleasedWhenClosed = false
        window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
        window.orderFront(nil)
        content.layoutSubtreeIfNeeded()

        let toggle = descendants(content, of: NSButton.self).first { $0.title == "줌·팬 동기화" }
        let grid = descendants(content, of: NSGridView.self).first
        check((toggle?.frame.height ?? .infinity) < 30, "토글은 고유 높이 유지: \(toggle?.frame.height ?? -1)")
        check((grid?.frame.height ?? 0) > content.frame.height / 2, "그리드가 창 높이 대부분 사용: \(grid?.frame.height ?? -1)")
        window.close()
    }
}
