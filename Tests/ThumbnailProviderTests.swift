import AppKit

private func makeImage(px: Int) -> NSImage {
    let img = NSImage(size: NSSize(width: px, height: px))
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    img.addRepresentation(rep)
    return img
}

@MainActor
func runProviderTests() {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("provider-tests-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    let fileA = tmp.appendingPathComponent("a.jpg")
    let fileB = tmp.appendingPathComponent("b.jpg")
    FileManager.default.createFile(atPath: fileA.path, contents: Data([1, 2, 3]))
    FileManager.default.createFile(atPath: fileB.path, contents: Data([4, 5, 6]))

    runTest("testProviderCoalescesSameKey: 같은 URL 두 요청 → 생성 1회, 완료 2회") {
        let gate = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var generateCalls = 0
        let provider = ThumbnailProvider(workerCount: 1, memoryCache: ThumbnailCache(memoryLimit: 50_000_000)) { _, _ in
            gate.wait()
            lock.lock(); generateCalls += 1; lock.unlock()
            return makeImage(px: 440)
        }
        var completions = 0
        let t1 = provider.request(fileA, minPixel: 440, priority: .visible) { if case .image = $0 { completions += 1 } }
        let t2 = provider.request(fileA, minPixel: 440, priority: .visible) { if case .image = $0 { completions += 1 } }
        check(t1 != nil && t2 != nil, "둘 다 비동기 토큰")
        gate.signal()
        check(waitUntil { completions == 2 }, "완료 2회")
        lock.lock(); let calls = generateCalls; lock.unlock()
        checkEqual(calls, 1, "생성 호출 수")
    }

    runTest("실행 중인 선로드 항목이 visible로 승격돼도 생성은 1회, 두 요청 모두 완료") {
        let gate = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var generateCalls = 0
        let provider = ThumbnailProvider(workerCount: 1, memoryCache: ThumbnailCache(memoryLimit: 50_000_000)) { _, _ in
            lock.lock(); generateCalls += 1; lock.unlock()
            gate.wait()  // 디코딩 중인 상태를 흉내 낸다
            return makeImage(px: 440)
        }
        var completions = 0
        provider.request(fileB, minPixel: 440, priority: .prefetch) { if case .image = $0 { completions += 1 } }
        check(waitUntil { lock.lock(); defer { lock.unlock() }; return generateCalls == 1 }, "워커가 디코딩에 들어감")
        provider.request(fileB, minPixel: 440, priority: .visible) { if case .image = $0 { completions += 1 } }
        gate.signal()
        check(waitUntil { completions == 2 }, "완료 2회")
        _ = waitUntil(timeout: 0.2) { false }  // 재등록이 있었다면 이 사이 두 번째 생성이 들어온다
        lock.lock(); let calls = generateCalls; lock.unlock()
        checkEqual(calls, 1, "승격이 재디코딩을 일으키지 않음")
    }

    runTest("메모리 적중은 동기 완료 + nil 토큰") {
        let cache = ThumbnailCache(memoryLimit: 50_000_000)
        cache.store(makeImage(px: 440), for: fileA)
        let provider = ThumbnailProvider(workerCount: 1, memoryCache: cache) { _, _ in makeImage(px: 440) }
        var got = false
        let token = provider.request(fileA, minPixel: 440, priority: .visible) { if case .image = $0 { got = true } }
        check(token == nil, "토큰 nil")
        check(got, "동기 완료")
    }

    runTest("작은 썸네일만 있으면 큰 요청은 재생성한다(승격)") {
        let cache = ThumbnailCache(memoryLimit: 50_000_000)
        cache.store(makeImage(px: 220), for: fileA)
        let provider = ThumbnailProvider(workerCount: 1, memoryCache: cache) { _, _ in makeImage(px: 440) }
        var px = 0
        let token = provider.request(fileA, minPixel: 440, priority: .visible) {
            if case .image(let img) = $0 { px = img.representations.first!.pixelsWide }
        }
        check(token != nil, "비동기 토큰")
        check(waitUntil { px == 440 }, "440으로 재생성")
    }

    runTest("취소 후에는 완료가 오지 않는다") {
        let gate = DispatchSemaphore(value: 0)
        let provider = ThumbnailProvider(workerCount: 1, memoryCache: ThumbnailCache(memoryLimit: 50_000_000)) { _, _ in
            gate.wait(); return makeImage(px: 440)
        }
        var completed = false
        provider.request(fileB, minPixel: 440, priority: .visible) { _ in }  // 워커 점유
        Thread.sleep(forTimeInterval: 0.05)
        let token = provider.request(fileA, minPixel: 440, priority: .visible) { _ in completed = true }!
        provider.cancel(token)
        gate.signal(); gate.signal()
        _ = waitUntil(timeout: 0.3) { false }
        check(!completed, "취소된 요청은 완료되지 않음")
    }

    runTest("생성 실패는 .failed, 같은 파일 재요청 시 생성을 다시 부르지 않는다") {
        let lock = NSLock()
        var calls = 0
        let provider = ThumbnailProvider(workerCount: 1, memoryCache: ThumbnailCache(memoryLimit: 50_000_000)) { _, _ in
            lock.lock(); calls += 1; lock.unlock(); return nil
        }
        var results: [ThumbnailResult] = []
        provider.request(fileA, minPixel: 440, priority: .visible) { results.append($0) }
        check(waitUntil { results.count == 1 }, "첫 완료")
        provider.request(fileA, minPixel: 440, priority: .visible) { results.append($0) }
        check(waitUntil { results.count == 2 }, "둘째 완료")
        if case .failed = results[0] {} else { check(false, "첫 결과 failed") }
        if case .failed = results[1] {} else { check(false, "둘째 결과 failed") }
        lock.lock(); let c = calls; lock.unlock()
        checkEqual(c, 1, "생성 호출 수")
    }

    runTest("minPixel을 단계로 올림: 160 → 220, 441 → 440(최대)") {
        checkEqual(ThumbnailProvider.level(forMinPixel: 160), 220, "160")
        checkEqual(ThumbnailProvider.level(forMinPixel: 220), 220, "220")
        checkEqual(ThumbnailProvider.level(forMinPixel: 300), 330, "300")
        checkEqual(ThumbnailProvider.level(forMinPixel: 441), 440, "441")
    }

    runTest("디스크에 있으면 생성을 부르지 않고 메모리에도 채운다") {
        let diskDir = tmp.appendingPathComponent("disk")
        let disk = ThumbnailDiskStore(directory: diskDir, limitBytes: 100_000_000)
        let cg = makeImage(px: 440).cgImage(forProposedRect: nil, context: nil, hints: nil)!
        disk.store(cg, url: fileA, px: 440)

        let lock = NSLock()
        var calls = 0
        let cache = ThumbnailCache(memoryLimit: 50_000_000)
        let provider = ThumbnailProvider(workerCount: 1, memoryCache: cache, diskStore: disk) { _, _ in
            lock.lock(); calls += 1; lock.unlock(); return makeImage(px: 440)
        }
        var got = false
        provider.request(fileA, minPixel: 440, priority: .visible) { if case .image = $0 { got = true } }
        check(waitUntil { got }, "디스크 적중 완료")
        lock.lock(); let c = calls; lock.unlock()
        checkEqual(c, 0, "생성 호출 없음")
        check(cache.thumbnail(for: fileA, minPixelSize: 440) != nil, "메모리에 채워짐")
    }

    runTest("생성 결과는 디스크에 저장된다") {
        let diskDir = tmp.appendingPathComponent("disk2")
        let disk = ThumbnailDiskStore(directory: diskDir, limitBytes: 100_000_000)
        let provider = ThumbnailProvider(workerCount: 1, memoryCache: ThumbnailCache(memoryLimit: 50_000_000), diskStore: disk) { _, _ in
            makeImage(px: 440)
        }
        var got = false
        provider.request(fileB, minPixel: 440, priority: .visible) { if case .image = $0 { got = true } }
        check(waitUntil { got }, "완료")
        check(waitUntil { disk.usedBytes > 0 }, "디스크 저장")
        check(disk.lookup(url: fileB, minPx: 440, levels: ThumbnailProvider.levels) != nil, "디스크 적중")
    }

    try? FileManager.default.removeItem(at: tmp)
}
