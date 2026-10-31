import AppKit

/// 취소 후에도 결과를 보내는 느린 로더로 화면의 오래된 결과 차단을 검증한다.
private final class DelayedViewerImageService: ImageServiceProtocol {
    private typealias Completion = CheckedContinuation<Result<NSImage, ImageServiceError>, Never>
    private let lock = NSLock()
    private var pending: [URL: [Completion]] = [:]

    func loadImage(at url: URL) async -> Result<NSImage, ImageServiceError> {
        await withCheckedContinuation { continuation in
            lock.lock()
            pending[url, default: []].append(continuation)
            lock.unlock()
        }
    }

    func hasPending(_ url: URL) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return !(pending[url] ?? []).isEmpty
    }

    func complete(_ url: URL, result: Result<NSImage, ImageServiceError>) {
        lock.lock()
        let completion = pending[url]?.isEmpty == false ? pending[url]?.removeFirst() : nil
        lock.unlock()
        completion?.resume(returning: result)
    }

    func generateThumbnail(at url: URL, size: CGSize) async -> Result<NSImage, ImageServiceError> {
        .failure(.thumbnailFailed(url))
    }

    func exportImage(_ image: NSImage, to url: URL, format: ImageFormat, quality: Float) -> Result<Void, ImageServiceError> {
        .failure(.exportFailed("테스트에서는 저장하지 않습니다"))
    }
}

@MainActor
func runViewerLoadingTests(directory: URL) {
    let service = DelayedViewerImageService()
    let viewer = ViewerViewController(imageService: service)
    let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 820, height: 640),
                          styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentViewController = viewer
    window.setContentSize(NSSize(width: 820, height: 640))
    window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
    NSApp.setActivationPolicy(.accessory)
    window.orderFront(nil)
    window.displayIfNeeded()
    window.contentView?.layoutSubtreeIfNeeded()
    let display = descendants(viewer.view, of: ImageDisplayView.self).first!
    let editButton = descendants(viewer.view, of: NSButton.self).first { $0.title == "편집" }!
    let urls = ["viewer-first.png", "viewer-second.png", "viewer-third.png"].map { directory.appendingPathComponent($0) }
    let files = urls.compactMap { ImageFile(url: $0) }
    let firstImage = NSImage(size: NSSize(width: 200, height: 100))
    let finalImage = NSImage(size: NSSize(width: 100, height: 200))
    defer { window.close(); NSApp.setActivationPolicy(.prohibited) }

    runTest("상세 최초 진입은 로딩을 표시하고 성공하면 원본과 편집 기능을 표시한다") {
        viewer.display(imageURL: urls[0], imageList: files)
        check(display.isLoading, "원본 요청 전부터 로딩 표시")
        check(viewer.currentImage == nil && !viewer.isShowingImage, "로딩 중에는 편집 가능한 원본 없음")
        check(!editButton.isEnabled, "로딩 중 편집 비활성")
        checkEqual(window.title, urls[0].lastPathComponent, "새 파일명을 즉시 표시")
        let label = descendants(display, of: NSTextField.self).first { $0.stringValue == "이미지를 불러오는 중…" }
        check(label != nil && label?.isHiddenOrHasHiddenAncestor == false, "실제 화면 트리에 로딩 문구 표시")
        check(waitUntil {
            window.contentView?.layoutSubtreeIfNeeded()
            display.layoutSubtreeIfNeeded()
            return display.bounds.width > 100 && display.bounds.height > 100
        }, "상세 이미지 영역 레이아웃 완료")
        check((label?.frame.width ?? 0) > 0, "로딩 문구의 실제 레이아웃 폭")
        if let output = ProcessInfo.processInfo.environment["JENA_VIEWER_LOADING_ARTIFACTS"] {
            for (name, appearance, background) in [
                ("light-on-dark", NSAppearance.Name.aqua, AppSettings.ViewerBackground.dark),
                ("dark-on-light", NSAppearance.Name.darkAqua, AppSettings.ViewerBackground.light),
            ] {
                window.appearance = NSAppearance(named: appearance)
                display.applyBackground(background)
                display.layoutSubtreeIfNeeded()
                if let bitmap = display.bitmapImageRepForCachingDisplay(in: display.bounds) {
                    display.cacheDisplay(in: display.bounds, to: bitmap)
                    do {
                        guard let png = bitmap.representation(using: .png, properties: [:]) else {
                            check(false, "로딩 화면 PNG 생성"); continue
                        }
                        try png.write(to: URL(fileURLWithPath: output).appendingPathComponent(name + ".png"))
                    } catch { check(false, "로딩 화면 캡처 저장: \(error)") }
                } else { check(false, "로딩 화면 캡처 영역 생성") }
            }
            window.appearance = nil
            display.applyBackground(AppSettings.shared.viewerBackground)
        }
        check(waitUntil { service.hasPending(urls[0]) }, "첫 요청 시작")
        service.complete(urls[0], result: .success(firstImage))
        check(waitUntil { viewer.currentImage === firstImage && !display.isLoading }, "성공 후 원본 표시 및 로딩 해제")
        check(editButton.isEnabled, "원본이 도착하면 편집 활성")
    }

    runTest("다음 이미지로 이동하는 즉시 이전 원본과 픽셀을 제거한다") {
        viewer.showNext()
        checkEqual(viewer.currentImageURL, urls[1], "선택 파일 변경")
        checkEqual(window.title, urls[1].lastPathComponent, "로딩 중에도 제목은 새 파일명")
        check(display.isLoading && viewer.currentImage == nil, "기존 원본을 유지하지 않고 로딩 표시")
        check(descendants(display, of: NSImageView.self).allSatisfy { $0.image == nil }, "이전 이미지 픽셀이 남지 않음")
        check(!editButton.isEnabled, "이전 원본을 새 파일로 편집할 수 없음")
        viewer.rotateRight()
        check(descendants(display, of: NSImageView.self).allSatisfy { $0.image == nil }, "로딩 중 회전으로 이전 이미지가 복원되지 않음")
        check(waitUntil { service.hasPending(urls[1]) }, "두 번째 요청 시작")
    }

    runTest("빠른 연속 이동에서 늦은 이전 결과는 현재 로딩과 이미지를 덮지 않는다") {
        viewer.showNext()
        check(waitUntil { service.hasPending(urls[2]) }, "세 번째 요청 시작")
        service.complete(urls[1], result: .success(firstImage))
        _ = waitUntil(timeout: 0.1) { false }
        check(display.isLoading && viewer.currentImage == nil, "늦은 두 번째 결과를 무시")
        checkEqual(window.title, urls[2].lastPathComponent, "현재 파일 제목 유지")
        service.complete(urls[2], result: .success(finalImage))
        check(waitUntil { viewer.currentImage === finalImage && !display.isLoading }, "최신 원본만 표시")
    }

    runTest("원본 로딩 실패 시 로딩을 종료하고 이전 이미지를 편집 대상으로 남기지 않는다") {
        viewer.reloadCurrentImage()
        check(display.isLoading && viewer.currentImage == nil, "재로딩도 즉시 전환")
        check(waitUntil { service.hasPending(urls[2]) }, "재로딩 요청 시작")
        service.complete(urls[2], result: .failure(.loadFailed(urls[2])))
        check(waitUntil { !display.isLoading }, "실패 후 회전 표시 종료")
        check(viewer.currentImage == nil && !editButton.isEnabled, "실패한 새 파일에 이전 원본을 연결하지 않음")
    }

    runTest("상세 화면을 벗어나면 로딩을 정리하고 늦은 결과를 표시하지 않는다") {
        viewer.reloadCurrentImage()
        check(waitUntil { service.hasPending(urls[2]) }, "대기 중인 원본 요청")
        viewer.viewWillDisappear()
        check(!display.isLoading && viewer.currentImage == nil, "화면 이탈 시 로딩 정리")
        service.complete(urls[2], result: .success(finalImage))
        _ = waitUntil(timeout: 0.1) { false }
        check(viewer.currentImage == nil, "취소된 결과로 숨은 뷰가 갱신되지 않음")
    }
    runViewerThumbnailLoadingTests(directory: directory)

}

@MainActor
private func runViewerThumbnailLoadingTests(directory: URL) {
    func makeThumbnail(width: Int, height: Int, color: NSColor) -> NSImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(color.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(NSColor.systemYellow.cgColor)
        context.fillEllipse(in: CGRect(x: width / 5, y: height / 2, width: width / 4, height: width / 4))
        context.setFillColor(NSColor.systemGreen.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height / 3))
        return NSImage(cgImage: context.makeImage()!, size: NSSize(width: width, height: height))
    }
    let thumbnails = [makeThumbnail(width: 80, height: 50, color: .systemBlue),
                      makeThumbnail(width: 50, height: 80, color: .systemRed)]
    let urls = (0..<2).map { directory.appendingPathComponent("loading-preview-\($0).png") }
    let files = urls.compactMap { ImageFile(url: $0) }
    let cache = ThumbnailCache()
    for index in urls.indices {
        let rep = NSBitmapImageRep(cgImage: thumbnails[index].cgImage(forProposedRect: nil, context: nil, hints: nil)!)
        try! rep.representation(using: .png, properties: [:])!.write(to: urls[index])
        cache.store(thumbnails[index], for: urls[index])
    }
    let provider = ThumbnailProvider(workerCount: 2, memoryCache: cache) { url, _ in
        thumbnails[urls.firstIndex(of: url)!]
    }
    let service = DelayedViewerImageService()
    let viewer = ViewerViewController(imageService: service, thumbnailProvider: provider)
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 640),
                          styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentViewController = viewer
    window.setContentSize(NSSize(width: 820, height: 640))
    window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
    NSApp.setActivationPolicy(.accessory)
    window.orderFront(nil)
    let display = descendants(viewer.view, of: ImageDisplayView.self).first!
    let preview = descendants(display, of: NSImageView.self).first { !$0.contentFilters.isEmpty }!
    let label = descendants(display, of: NSTextField.self).first { $0.stringValue == "이미지를 불러오는 중…" }!
    defer { window.close(); NSApp.setActivationPolicy(.prohibited) }

    runTest("상세 로딩은 작은 캐시 썸네일도 즉시 크게 확대하고 흐리게 표시한다") {
        viewer.display(imageURL: urls[0], imageList: files)
        check(preview.image === thumbnails[0] && !preview.isHidden, "캐시 미리보기는 비동기 원본을 기다리지 않음")
        check(label.isHiddenOrHasHiddenAncestor, "썸네일이 있으면 중앙 로딩 문구 숨김")
        check(viewer.currentImage == nil && !viewer.isShowingImage, "미리보기를 편집 가능한 원본으로 취급하지 않음")
        check(preview.imageScaling == .scaleProportionallyUpOrDown, "작은 이미지도 화면에 맞게 확대")
        checkEqual(preview.contentFilters.first?.name, "CIGaussianBlur", "썸네일에 블러 적용")
        let opacity = preview.layer?.animation(forKey: ImageDisplayView.loadingOpacityAnimationKey) as? CAKeyframeAnimation
        checkEqual(opacity?.values as? [Double], [0.25, 0.4, 0.55, 0.7, 0.85, 1], "미리보기 불투명도가 단계별 증가")
        checkEqual(opacity?.duration, 1.5, "6개 지점을 0.3초 간격으로 연결")
        checkEqual(opacity?.keyTimes, [0, 0.2, 0.4, 0.6, 0.8, 1], "0.3초마다 불투명도 단계 도달")
        check(opacity?.autoreverses == true, "100% 도달 후 25%까지 역방향으로 이어진다")
        check(opacity?.repeatCount == .infinity, "오래 기다려도 로딩 효과 반복")
        check(waitUntil {
            window.contentView?.layoutSubtreeIfNeeded()
            return preview.bounds.width > 500 && preview.bounds.height > 400
        }, "80px 썸네일을 원본 표시 영역 크기로 확대")
        checkEqual(thumbnails[0].size, NSSize(width: 80, height: 50), "공유 캐시 이미지 크기는 변경하지 않음")
        if let output = ProcessInfo.processInfo.environment["JENA_VIEWER_PREVIEW_ARTIFACTS"] {
            display.applyBackground(.dark)
            display.layoutSubtreeIfNeeded()
            if let bitmap = display.bitmapImageRepForCachingDisplay(in: display.bounds) {
                display.cacheDisplay(in: display.bounds, to: bitmap)
                do {
                    let png = bitmap.representation(using: .png, properties: [:])!
                    try png.write(to: URL(fileURLWithPath: output).appendingPathComponent("blurred-preview.png"))
                } catch { check(false, "미리보기 캡처 저장: \(error)") }
            } else { check(false, "미리보기 캡처 영역 생성") }
        }
        check(waitUntil { service.hasPending(urls[0]) }, "첫 원본 요청 시작")
    }

    runTest("미리보기 로딩 효과는 원본 표시와 실패 및 취소 시 제거된다") {
        let target = ImageDisplayView(frame: NSRect(x: 0, y: 0, width: 500, height: 400))
        let preview = descendants(target, of: NSImageView.self).first { $0.accessibilityLabel() == "불러오는 이미지 미리보기" }!
        for finish in [{ target.display(thumbnails[0]) }, { target.displayError() }, { target.clearImage() }] {
            target.displayLoading()
            target.displayLoadingPreview(thumbnails[0])
            check(preview.layer?.animation(forKey: ImageDisplayView.loadingOpacityAnimationKey) != nil, "새 로딩마다 효과 시작")
            finish()
            check(preview.layer?.animation(forKey: ImageDisplayView.loadingOpacityAnimationKey) == nil, "종료 후 효과 제거")
            check(preview.isHidden && !target.isLoading, "로딩 상태 종료")
        }
    }

    runTest("다음 파일은 자신의 썸네일로 바뀌며 원본 도착 후 블러 미리보기를 제거한다") {
        viewer.showNext()
        check(preview.image === thumbnails[1], "이전 파일 대신 새 파일 썸네일 표시")
        check(waitUntil { service.hasPending(urls[1]) }, "새 원본 요청 시작")
        service.complete(urls[0], result: .success(thumbnails[0]))
        _ = waitUntil(timeout: 0.1) { false }
        check(preview.image === thumbnails[1] && display.isLoading, "이전 원본 결과가 현재 썸네일을 덮지 않음")
        service.complete(urls[1], result: .success(thumbnails[1]))
        check(waitUntil { viewer.currentImage === thumbnails[1] }, "현재 원본 표시")
        check(!display.isLoading && preview.image == nil && preview.isHidden, "원본에는 블러 오버레이가 남지 않음")
    }

    runTest("늦게 도착한 썸네일은 로딩 중에만 표시하며 원본을 덮어쓰지 않는다") {
        let gates = [DispatchSemaphore(value: 0), DispatchSemaphore(value: 0)]
        let slowCache = ThumbnailCache()
        let slowProvider = ThumbnailProvider(workerCount: 2, memoryCache: slowCache) { url, _ in
            let index = urls.firstIndex(of: url)!
            _ = gates[index].wait(timeout: .now() + 5)
            return thumbnails[index]
        }
        let slowService = DelayedViewerImageService()
        let slowViewer = ViewerViewController(imageService: slowService, thumbnailProvider: slowProvider)
        window.contentViewController = slowViewer
        window.setContentSize(NSSize(width: 820, height: 640))
        let slowDisplay = descendants(slowViewer.view, of: ImageDisplayView.self).first!
        let slowPreview = descendants(slowDisplay, of: NSImageView.self).first { !$0.contentFilters.isEmpty }!
        slowViewer.display(imageURL: urls[0], imageList: files)
        check(slowDisplay.isLoading && slowPreview.image == nil, "썸네일도 없을 때만 기본 로딩 표시")
        check(waitUntil { slowService.hasPending(urls[0]) }, "느린 원본 요청 시작")
        gates[0].signal()
        check(waitUntil { slowPreview.image === thumbnails[0] }, "원본 로딩 중 썸네일이 도착하면 미리보기 표시")
        check(slowViewer.currentImage == nil, "미리보기와 원본 상태 분리")
        slowService.complete(urls[0], result: .success(thumbnails[0]))
        check(waitUntil { !slowDisplay.isLoading }, "첫 원본 표시 완료")
        slowViewer.showNext()
        check(waitUntil { slowService.hasPending(urls[1]) }, "다음 원본 요청 시작")
        slowService.complete(urls[1], result: .success(thumbnails[1]))
        check(waitUntil { slowViewer.currentImage === thumbnails[1] }, "썸네일보다 원본이 먼저 도착")
        gates[1].signal()
        _ = waitUntil(timeout: 0.3) { false }
        check(slowPreview.image == nil && slowPreview.isHidden && !slowDisplay.isLoading, "늦은 썸네일이 원본 위에 나타나지 않음")
        slowViewer.viewWillDisappear()
    }
}
