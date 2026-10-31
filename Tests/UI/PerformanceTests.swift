import AppKit

private final class PerformanceValue<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value
    init(_ value: Value) { self.value = value }
    func read() -> Value { lock.lock(); defer { lock.unlock() }; return value }
    func set(_ value: Value) { lock.lock(); self.value = value; lock.unlock() }
    func update(_ body: (inout Value) -> Void) { lock.lock(); body(&value); lock.unlock() }
}

private func performanceImage(width: Int, height: Int) -> NSImage {
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(NSColor.gray.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return NSImage(cgImage: context.makeImage()!, size: NSSize(width: width, height: height))
}

@MainActor
func runPerformanceTests(directory: URL) {
    let suite = "jena-performance-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults)
    let root = directory.appendingPathComponent("performance")
    try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let source = root.appendingPathComponent("source.png")
    let original = performanceImage(width: 400, height: 200)
    try! NSBitmapImageRep(cgImage: original.cgImage(forProposedRect: nil, context: nil, hints: nil)!)
        .representation(using: .png, properties: [:])!.write(to: source)

    runTest("그리드는 비율 파일 조회를 생략하고 masonry 전환 시 백그라운드에서 읽는다") {
        settings.browserLayoutMode = .grid
        let calls = PerformanceValue(0)
        let mainThreadRead = PerformanceValue(false)
        let provider = ThumbnailProvider(workerCount: 1, memoryCache: ThumbnailCache()) { _, _ in nil }
        let browser = BrowserViewController(thumbnailProvider: provider, settings: settings, aspectRatioReader: { _ in
            calls.update { $0 += 1 }
            if Thread.isMainThread { mainThreadRead.set(true) }
            return 2
        })
        _ = browser.view
        browser.display(folders: [], images: [source])
        _ = waitUntil(timeout: 0.2) { false }
        checkEqual(calls.read(), 0, "그리드는 원본 비율을 읽지 않음")
        browser.setLayoutMode(.masonry)
        check(waitUntil { calls.read() == 1 }, "masonry에서 비율 조회")
        check(!mainThreadRead.read(), "원본 메타데이터 조회는 메인 스레드 밖")
        browser.viewWillDisappear()
    }

    runTest("캐시 비율을 복원하면 원본 크기 메타데이터를 다시 읽지 않는다") {
        settings.browserLayoutMode = .masonry
        let cache = ThumbnailCache()
        cache.store(performanceImage(width: 440, height: 220), for: source)
        let calls = PerformanceValue(0)
        let provider = ThumbnailProvider(workerCount: 1, memoryCache: cache) { _, _ in nil }
        let browser = BrowserViewController(thumbnailProvider: provider, settings: settings, aspectRatioReader: { _ in
            calls.update { $0 += 1 }; return 1
        })
        _ = browser.view
        browser.display(folders: [], images: [source])
        let layout = descendants(browser.view, of: NSCollectionView.self).first!.collectionViewLayout as! MasonryLayout
        check(waitUntil { layout.aspectRatios == [2] }, "캐시의 실제 썸네일 비율 복원")
        checkEqual(calls.read(), 0, "원본 메타데이터 중복 조회 없음")
        browser.viewWillDisappear()
    }

    runTest("디스크 저장이 막혀 있어도 썸네일은 먼저 표시된다") {
        let queue = DispatchQueue(label: "test.thumbnail.delayed-write")
        queue.suspend()
        let disk = ThumbnailDiskStore(directory: root.appendingPathComponent("disk"), limitBytes: 1_000_000, writeQueue: queue)
        // 큐 한도까지 저장이 밀려 있어도 현재 썸네일 전달을 막으면 안 된다.
        let cg = original.cgImage(forProposedRect: nil, context: nil, hints: nil)!
        for _ in 0..<16 {
            disk.storeAsync(cg, url: source, px: 220, sourceStamp: ThumbnailCache.stamp(for: source))
        }
        let provider = ThumbnailProvider(workerCount: 1, memoryCache: ThumbnailCache(), diskStore: disk) { _, _ in
            performanceImage(width: 440, height: 220)
        }
        var displayed = false
        provider.request(source, minPixel: 440, priority: .visible) { if case .image = $0 { displayed = true } }
        check(waitUntil { displayed }, "저장 큐가 멈춰 있어도 이미지 전달")
        checkEqual(disk.usedBytes, 0, "표시 시점에는 아직 디스크 저장 전")
        queue.resume()
        check(waitUntil(timeout: 5) { disk.lookup(url: source, minPx: 440, levels: ThumbnailProvider.levels) != nil }, "나중에 저장 완료")
        queue.sync {}
    }

    runTest("저장 대기 중 원본 변경·캐시 비우기는 오래된 썸네일을 남기지 않는다") {
        let queue = DispatchQueue(label: "test.thumbnail.stale-write")
        let disk = ThumbnailDiskStore(directory: root.appendingPathComponent("stale-disk"), limitBytes: 1_000_000, writeQueue: queue)
        let image = original.cgImage(forProposedRect: nil, context: nil, hints: nil)!
        queue.suspend()
        disk.storeAsync(image, url: source, px: 440, sourceStamp: ThumbnailCache.stamp(for: source))
        try! FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 100)], ofItemAtPath: source.path)
        queue.resume()
        queue.sync {}
        checkEqual(disk.usedBytes, 0, "원본 변경 전 그림을 새 스탬프로 저장하지 않음")
        queue.suspend()
        disk.storeAsync(image, url: source, px: 440, sourceStamp: ThumbnailCache.stamp(for: source))
        disk.clear()
        queue.resume()
        queue.sync {}
        checkEqual(disk.usedBytes, 0, "비우기 이전에 대기하던 저장 취소")
    }

    runTest("취소한 원본 로딩은 앞 작업 완료 후에도 디코딩하지 않는다") {
        let executor = ImageLoadExecutor()
        let gate = DispatchSemaphore(value: 0)
        let started = PerformanceValue(false)
        let decoded = PerformanceValue(false)
        let finished = PerformanceValue(false)
        Task.detached {
            _ = await executor.load(at: source) {
                started.set(true)
                _ = gate.wait(timeout: .now() + 5)
                return .failure(.loadFailed(source))
            }
        }
        check(waitUntil { started.read() }, "첫 디코딩 실행")
        let obsolete = Task.detached {
            _ = await executor.load(at: source) {
                decoded.set(true)
                return .failure(.loadFailed(source))
            }
            finished.set(true)
        }
        obsolete.cancel()
        gate.signal()
        check(waitUntil { finished.read() }, "취소 요청도 정상 종료")
        check(!decoded.read(), "취소한 대기 요청은 원본을 열지 않음")
    }

    runTest("색상 미리보기는 축소 비트맵이고 적용 결과는 원본 해상도를 유지한다") {
        let image = performanceImage(width: 3200, height: 1600)
        let service = ImageAdjustmentPreviewService()
        let adjustment = ImageAdjustment(brightness: 0.1, contrast: 1, saturation: 1, highlights: 0, shadows: 0)
        var preview: NSImage?
        let task = Task { preview = await service.render(image, adjustment: adjustment) }
        check(waitUntil(timeout: 5) { preview != nil }, "비동기 미리보기 완료")
        if let preview {
            let cg = preview.cgImage(forProposedRect: nil, context: nil, hints: nil)!
            checkEqual(cg.width, 1600, "미리보기 최대 폭")
            checkEqual(cg.height, 800, "미리보기 종횡비")
            checkEqual(preview.size, image.size, "뷰 좌표와 줌 크기 유지")
        }
        let applied = ImageEditingService().adjustImage(image, brightness: adjustment.brightness)!
        checkEqual(applied.cgImage(forProposedRect: nil, context: nil, hints: nil)!.width, 3200, "적용은 원본 해상도")
        task.cancel()
    }

    runTest("부모 집계 중 자식 요청을 합치고 무효화된 집계는 중단한다") {
        let child = root.appendingPathComponent("child")
        let started = PerformanceValue(0)
        let cancelled = PerformanceValue(false)
        let gate = DispatchSemaphore(value: 0)
        let service = FolderMediaCountService { url, isCancelled in
            started.update { $0 += 1 }
            if started.read() == 1 {
                while gate.wait(timeout: .now() + 0.02) == .timedOut {
                    if isCancelled() { cancelled.set(true); return [:] }
                }
            }
            return [root.path: 12, child.path: 5]
        }
        _ = service.count(for: root)
        check(waitUntil { started.read() == 1 }, "상위 집계 시작")
        _ = service.count(for: child)
        _ = waitUntil(timeout: 0.1) { false }
        checkEqual(started.read(), 1, "자식 중복 탐색 없음")
        service.invalidate(root)
        _ = service.count(for: root)
        check(waitUntil { cancelled.read() }, "무효화된 작업 취소")
        check(waitUntil { service.count(for: root) == 12 }, "새 집계 결과 도착")
        checkEqual(service.count(for: child), 5, "하위 결과 공유")
        checkEqual(started.read(), 2, "재집계는 한 번만")
        gate.signal()
    }

    runTest("실제 재귀 열거는 완료 전 첫 묶음을 전달하고 최종 정렬을 유지한다") {
        let folder = root.appendingPathComponent("scan/child")
        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for index in 0..<96 {
            try! Data().write(to: folder.appendingPathComponent("image-\(index).png"))
        }
        let service = FileService()
        var counts: [Int] = []
        let result = service.recursiveImages(at: folder.deletingLastPathComponent(), sortKey: .name, ascending: true,
            progress: { counts.append($0.imageCount); check($0.previewURLs.count <= 64, "미리보기 크기 제한") },
            isCancelled: { false })
        check(counts.contains { $0 > 0 && $0 < 96 }, "전체 열거 전 부분 결과 전달")
        if case .success(let urls) = result {
            checkEqual(urls.count, 96, "하위 폴더 결과 누락 없음")
            checkEqual(urls, urls.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }, "최종 정렬 유지")
        } else { check(false, "재귀 열거 성공") }
        var shouldCancel = false
        let cancelledResult = service.recursiveImages(at: folder, sortKey: .name, ascending: true,
            progress: { _ in shouldCancel = true }, isCancelled: { shouldCancel })
        if case .success = cancelledResult { check(false, "취소 후 전체 결과를 반환하면 안 됨") }
    }

    runFolderLoadingTests(root: root, settings: settings, defaults: defaults, source: source)
}

private final class DelayedFolderService: FileServiceProtocol {
    let gate = DispatchSemaphore(value: 0)
    let cancelled = PerformanceValue(false)
    let source: URL
    init(source: URL) { self.source = source }
    func contentsOfFolder(at url: URL, sortKey: SortKey, ascending: Bool) -> Result<(folders: [URL], images: [URL]), FileServiceError> {
        .success(([], []))
    }
    func recursiveImages(at url: URL, sortKey: SortKey, ascending: Bool) -> Result<[URL], FileServiceError> { .success([]) }
    func recursiveImages(at url: URL, sortKey: SortKey, ascending: Bool, progress: (FolderScanProgress) -> Void,
                         isCancelled: () -> Bool) -> Result<[URL], FileServiceError> {
        if url.lastPathComponent == "empty" { return .success([]) }
        progress(FolderScanProgress(previewURLs: [source], imageCount: 1))
        while gate.wait(timeout: .now() + 0.02) == .timedOut {
            if isCancelled() {
                cancelled.set(true)
                // 취소 직전 도착한 늦은 콜백도 새 화면에 반영되면 안 된다.
                progress(FolderScanProgress(previewURLs: [source], imageCount: 1))
                return .success([source])
            }
        }
        return .success([source])
    }
    func moveFile(from source: URL, to destinationFolder: URL) -> Result<URL, FileServiceError> { .failure(.permissionDenied(source)) }
    func copyFile(from source: URL, to destinationFolder: URL) -> Result<URL, FileServiceError> { .failure(.permissionDenied(source)) }
    func duplicateFile(at url: URL) -> Result<URL, FileServiceError> { .failure(.permissionDenied(url)) }
    func trashFile(at url: URL) -> Result<Void, FileServiceError> { .failure(.permissionDenied(url)) }
    func renameFile(at url: URL, newName: String) -> Result<URL, FileServiceError> { .failure(.permissionDenied(url)) }
    func createFolder(in parentURL: URL, name: String) -> Result<URL, FileServiceError> { .failure(.permissionDenied(parentURL)) }
    func fileExists(at url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }
}

@MainActor
private func runFolderLoadingTests(root: URL, settings: AppSettings, defaults: UserDefaults, source: URL) {
    settings.recursiveBrowsing = true
    let service = DelayedFolderService(source: source)
    let controller = MainWindowController(categoryStore: CategoryStore(defaults: defaults), settings: settings, fileService: service)
    defer {
        service.gate.signal()
        controller.folderLoadGeneration += 1
        for url in controller.folderWatcher.watchedURLs { controller.folderWatcher.unwatch(url) }
        controller.window?.close()
    }
    runTest("느린 하위 폴더 탐색은 빈 폴더가 아닌 로딩 상태와 부분 이미지를 보여준다") {
        controller.navigateToFolder(root)
        check(controller.browserVC.isFolderLoading, "클릭 직후 탐색 상태")
        let labels = descendants(controller.browserVC.view, of: NSTextField.self)
        check(labels.contains { !$0.isHidden && $0.stringValue == "이미지를 찾는 중…" }, "빈 폴더 오인 방지 문구")
        check(waitUntil { controller.browserVC.listedImageURLs == [source] }, "전체 탐색 완료 전에 이미지 표시")
        check(controller.browserVC.isFolderLoading, "부분 이미지가 있어도 탐색 중 상태 유지")
        controller.browserVC.restoreSelection(urls: [source])
        service.gate.signal()
        check(waitUntil { !controller.browserVC.isFolderLoading }, "완료 후 로딩 해제")
        checkEqual(controller.browserVC.selectedURLs(), [source], "미리보기에서 고른 이미지 선택 보존")
    }
    runTest("탐색 중 미리보기를 열었다가 돌아오면 전체 목록 탐색을 재개한다") {
        controller.navigateToFolder(root)
        check(waitUntil { controller.browserVC.listedImageURLs == [source] }, "미리보기 표시")
        controller.switchToMode(.viewer)
        check(waitUntil { service.cancelled.read() }, "뷰어 진입 시 탐색 취소")
        controller.viewerDidRequestClose(controller.viewerVC)
        check(controller.browserVC.isFolderLoading, "브라우저 복귀 시 재탐색")
        service.gate.signal()
        check(waitUntil { !controller.browserVC.isFolderLoading }, "재탐색 완료")
        checkEqual(controller.browserVC.listedImageURLs, [source], "최종 목록 복원")
        service.cancelled.set(false)
    }
    runTest("탐색 중 폴더를 바꾸면 이전 작업을 취소하고 늦은 결과를 무시한다") {
        controller.navigateToFolder(root)
        check(waitUntil { controller.browserVC.listedImageURLs == [source] }, "첫 폴더 미리보기")
        controller.navigateToFolder(root.appendingPathComponent("empty"))
        check(waitUntil { service.cancelled.read() && !controller.browserVC.isFolderLoading }, "이전 탐색 취소와 새 탐색 완료")
        check(controller.browserVC.listedImageURLs.isEmpty, "이전 결과가 새 폴더에 섞이지 않음")
        let labels = descendants(controller.browserVC.view, of: NSTextField.self)
        check(labels.contains { !$0.isHidden && $0.stringValue == "이 폴더는 비어 있습니다" }, "완료 후에만 빈 폴더 표시")
    }
}
