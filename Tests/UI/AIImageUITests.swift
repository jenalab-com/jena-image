import AppKit

@MainActor
func runAIImageUITests(controller: MainWindowController, directory: URL) {
    let image = directory.appendingPathComponent("ai-reference.png")
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    try! bitmap.representation(using: .png, properties: [:])!.write(to: image)
    runTest("AI 모드는 이미지 선택과 저장 폴더를 가져오고 입력을 유지한다") {
        controller.currentFolderURL = directory
        controller.switchToMode(.browser)
        controller.browserVC.display(folders: [], images: [image])
        controller.browserVC.restoreSelection(urls: [image])
        controller.showAIMode(nil)
        guard let ai = controller.aiWindowController, let view = ai.window?.contentView else {
            check(false, "AI 창 표시"); return
        }
        checkEqual(ai.referenceURLs, [image], "선택 이미지 전달")
        checkEqual(ai.destinationURL, directory, "현재 폴더를 저장 위치로 사용")
        let buttons = descendants(view, of: NSButton.self)
        buttons.first { $0.title == "참조 비우기" }?.performClick(nil)
        check(ai.referenceURLs.isEmpty, "참조 없는 생성 지원")
        buttons.first { $0.title == "목록 선택 가져오기" }?.performClick(nil)
        checkEqual(ai.referenceURLs, [image], "선택 다시 가져오기")
        let prompt = descendants(view, of: NSTextView.self).first { $0.isEditable && !$0.isFieldEditor }
        prompt?.string = "프롬프트 보존"
        ai.window?.close()
        controller.showAIMode(nil)
        checkEqual(prompt?.string, "프롬프트 보존", "창을 다시 열어도 설명 유지")
        check(controller.toolbarDefaultItemIdentifiers(controller.window!.toolbar!).contains(MainWindowController.ToolbarID.ai), "툴바에서 AI 모드 접근")
        ai.window?.contentView?.layoutSubtreeIfNeeded()
        let scroll = view.subviews.compactMap { $0 as? NSScrollView }.first
        check((scroll?.documentView?.frame.height ?? 0) > 0, "폼 레이아웃 높이")
        check((prompt?.frame.width ?? 0) > 100, "프롬프트 입력 영역 너비")
        if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: ".build/ai-mode-preview.png"))
        }
        ai.window?.close()
    }
}
