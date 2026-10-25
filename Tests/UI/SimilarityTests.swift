import AppKit
import CryptoKit

@MainActor
func runSimilarityTests(directory: URL) {
    let root = directory.appendingPathComponent("similarity-images")
    let cache = directory.appendingPathComponent("similarity-cache")
    try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let reference = root.appendingPathComponent("reference.png")
    let same = root.appendingPathComponent("same.png")
    let different = root.appendingPathComponent("different.png")
    try! FileManager.default.copyItem(at: directory.appendingPathComponent("masonry-1.png"), to: reference)
    try! FileManager.default.copyItem(at: reference, to: same)
    try! FileManager.default.copyItem(at: directory.appendingPathComponent("masonry-6.png"), to: different)
    let broken = root.appendingPathComponent("broken.png")
    try! Data("broken".utf8).write(to: broken)
    try! Data().write(to: root.appendingPathComponent("video.mp4"))
    var result: SimilarImageSearchResult?
    var error: Error?
    var finished = false
    let listed = [reference, same, same, different, broken, root.appendingPathComponent("video.mp4")]
    func search(_ service: ImageSimilarityService, candidates: [URL]? = nil) {
        finished = false
        result = nil
        error = nil
        Task {
            do { result = try await service.search(reference: reference, candidates: candidates ?? listed) }
            catch let caught { error = caught }
            finished = true
        }
        check(waitUntil(timeout: 60) { finished }, "실제 Vision 분석 완료")
        check(error == nil, "Vision 분석 성공: \(String(describing: error))")
    }
    let service = ImageSimilarityService(cacheDirectory: cache)
    runTest("실제 모델이 동일 이미지를 최상위로 찾고 중복 이미지와 영상을 제외한다") {
        search(service)
        checkEqual(result?.matches.first?.url, same, "동일 이미지가 최상위")
        check((result?.matches.first?.distance ?? 100) < 0.001, "동일 이미지의 특징 거리")
        checkEqual(result?.matches.count, 2, "기준 이미지·영상·중복 경로 제외")
        checkEqual(result?.skippedCount, 1, "손상 이미지 보고")
        checkEqual(result?.cachedCount, 0, "최초 분석")
        checkEqual(result?.cacheWriteFailures, 0, "특징 저장")
    }
    runTest("서비스 재생성 후에도 저장된 특징을 재사용한다") {
        search(ImageSimilarityService(cacheDirectory: cache))
        checkEqual(result?.cachedCount, 2, "디스크 특징 재사용")
    }
    runTest("변경한 이미지만 재분석하고 목록에서 사라진 이미지를 보고한다") {
        try! Data(contentsOf: reference).write(to: different, options: .atomic)
        try! FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(10)], ofItemAtPath: different.path)
        search(service, candidates: listed + [directory.appendingPathComponent("missing.png")])
        checkEqual(result?.cachedCount, 1, "변경되지 않은 후보만 재사용")
        checkEqual(result?.skippedCount, 2, "손상·사라진 이미지 보고")
    }
    runTest("손상된 특징 캐시를 원본에서 재생성한다") {
        let key = SHA256.hash(data: Data(same.path.utf8)).map { String(format: "%02x", $0) }.joined()
        try! Data("invalid cache".utf8).write(to: cache.appendingPathComponent(key + ".json"))
        search(service)
        checkEqual(result?.cachedCount, 1, "손상된 캐시만 재분석")
        checkEqual(result?.matches.count, 2, "캐시 손상으로 검색 결과를 잃지 않음")
    }
    runTest("취소된 검색은 결과를 반환하지 않는다") {
        var cancelled = false
        let task = Task {
            do { _ = try await service.search(reference: reference, candidates: listed) }
            catch is CancellationError { cancelled = true }
            catch { check(false, "예상하지 못한 취소 오류: \(error)") }
        }
        task.cancel()
        check(waitUntil { cancelled }, "취소 전파")
    }

    // UI 연결은 깨진 파일이 없는 별도 루트로 검증하며 사용자 설정·캐시는 건드리지 않는다.
    let uiRoot = directory.appendingPathComponent("similarity-ui-images")
    try! FileManager.default.createDirectory(at: uiRoot, withIntermediateDirectories: true)
    let candidate = uiRoot.appendingPathComponent("candidate.png")
    try! FileManager.default.copyItem(at: reference, to: candidate)
    let suite = "jena-similarity-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = CategoryStore(defaults: defaults)
    let category = try! store.create(name: "출발 카테고리", urls: [reference, candidate])
    let target = try! store.create(name: "유사 이미지 수집")
    let controller = MainWindowController(categoryStore: store, settings: AppSettings(defaults: defaults),
        similarityService: ImageSimilarityService(cacheDirectory: directory.appendingPathComponent("similarity-ui-cache")))
    let window = controller.window!
    window.isReleasedWhenClosed = false
    window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
    NSApp.setActivationPolicy(.accessory)
    window.orderFront(nil)
    controller.sidebarVC.addFolder(root)
    controller.showCategory(category.id)
    let browser = controller.browserVC
    runTest("새 검색 결과는 masonry와 격자 모두 목록 맨 위에서 시작한다") {
        window.setContentSize(NSSize(width: 700, height: 400))
        let files = (1...8).compactMap { ImageFile(url: directory.appendingPathComponent("masonry-\($0).png")) }
        let collection = descendants(browser.view, of: NSCollectionView.self).first!
        let scroll = collection.enclosingScrollView!
        for mode in BrowserLayoutMode.allCases {
            browser.setLayoutMode(mode)
            browser.displayBookmarks(files)
            window.contentView?.layoutSubtreeIfNeeded()
            collection.layoutSubtreeIfNeeded()
            scroll.contentView.scroll(to: NSPoint(x: 0, y: 250))
            scroll.reflectScrolledClipView(scroll.contentView)
            check(scroll.contentView.bounds.minY > 0, "검색 전 스크롤된 상태")
            browser.displaySimilarImages(files, resetScroll: true)
            check(abs(scroll.contentView.bounds.minY) < 1, "검색 결과를 맨 위에서 표시")
            _ = waitUntil(timeout: 0.15) { false }
            check(abs(scroll.contentView.bounds.minY) < 1, "비율 갱신 후에도 맨 위 유지")
        }
        controller.showCategory(category.id)
    }
    runTest("우클릭 검색 결과를 카테고리에 수집하고 상세에서 돌아와도 순서를 유지한다") {
        browser.restoreSelection(urls: [reference])
        let menu = NSMenu()
        browser.menuNeedsUpdate(menu)
        guard let find = menu.items.first(where: { $0.title == "비슷한 이미지 찾기" }) else {
            check(false, "검색 메뉴 존재"); return
        }
        NSApp.sendAction(find.action!, to: find.target, from: find)
        check(waitUntil(timeout: 60) { browser.isSimilarityMode && controller.similarityTask == nil }, "결과 표시")
        let back = window.toolbar?.items.first { $0.itemIdentifier == MainWindowController.ToolbarID.back }
        check(back?.isNavigational == true && back?.isEnabled == true, "뒤로 버튼을 제목 왼쪽 탐색 영역에 표시")
        checkEqual(controller.similarityPresentation?.result.matches.map(\.url), [candidate], "현재 카테고리의 이미지만 검색하고 등록 폴더의 다른 이미지는 제외")
        browser.restoreSelection(urls: [candidate])
        browser.menuNeedsUpdate(menu)
        check(!menu.items.contains { $0.title == "빼기" || $0.title == "카테고리에서 빼기" }, "검색 결과에서 잘못된 멤버십 제거 방지")
        guard let assign = menu.items.first(where: { $0.title == "카테고리 지정" })?.submenu?.items.first(where: { $0.title == target.name }) else {
            check(false, "결과 카테고리 지정 메뉴"); return
        }
        NSApp.sendAction(assign.action!, to: assign.target, from: assign)
        check((try! store.categories()).first(where: { $0.id == target.id })!.urls.contains(candidate), "검색 결과를 카테고리에 추가")
        check(browser.isSimilarityMode, "지정 후 검색 목록 유지")
        controller.browser(browser, didRequestViewImage: candidate, inList: [ImageFile(url: candidate)!])
        controller.viewerDidRequestClose(controller.viewerVC)
        check(browser.isSimilarityMode && controller.window!.title.contains("유사도순"), "상세에서 검색 결과로 복귀")
        controller.refreshAfterExternalChange()
        check(browser.isSimilarityMode, "자동 갱신으로 원래 폴더가 덮이지 않음")
        controller.toolbarBack(nil)
        checkEqual(controller.currentCategoryID, category.id, "출발 카테고리로 복귀")
        check(!browser.isSimilarityMode, "검색 모드 종료")
    }
    runTest("폴더 등록 없이 현재 목록을 검색하고 이전 분석을 그대로 재사용한다") {
        controller.sidebarVC.removeFolder(at: root)
        controller.showCategory(category.id)
        controller.findSimilarImages(to: reference)
        check(waitUntil(timeout: 60) { browser.isSimilarityMode && controller.similarityTask == nil }, "등록 폴더 없이 검색 완료")
        checkEqual(controller.similarityPresentation?.result.matches.map(\.url), [candidate], "현재 목록만 검색")
        checkEqual(controller.similarityPresentation?.result.cachedCount, 1, "기존 특징 캐시 재사용")
        controller.toolbarBack(nil)
    }
    runTest("검색 중 다른 카테고리로 이동하면 늦은 결과가 화면을 덮지 않는다") {
        controller.findSimilarImages(to: reference)
        controller.showCategory(target.id)
        check(controller.similarityTask == nil && controller.similaritySession == nil, "진행 작업 취소")
        _ = waitUntil(timeout: 0.3) { false }
        checkEqual(controller.currentCategoryID, target.id, "이동한 카테고리 유지")
        check(browser.isCategoryMode && !browser.isSimilarityMode, "늦은 결과 무시")
    }
    controller.clearSimilaritySearch()
    controller.browserVC.viewWillDisappear()
    for url in controller.folderWatcher.watchedURLs { controller.folderWatcher.unwatch(url) }
    window.close()
    NSApp.setActivationPolicy(.prohibited)
}
