// Tests/ThumbnailDiskStoreTests.swift
import Foundation
import CoreGraphics

private func makeCGImage(px: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: px, height: px))
    return ctx.makeImage()!
}

private func makeSource(_ dir: URL, _ name: String, bytes: Int, mtime: Date? = nil) -> URL {
    let url = dir.appendingPathComponent(name)
    FileManager.default.createFile(atPath: url.path, contents: Data(repeating: 7, count: bytes))
    if let mtime { try! FileManager.default.setAttributes([.modificationDate: mtime], ofItemAtPath: url.path) }
    return url
}

func runDiskStoreTests() {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("diskstore-tests-\(UUID().uuidString)")
    let src = root.appendingPathComponent("src")
    try! FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
    let levels = [220, 330, 440]

    runTest("키는 경로·mtime·size·px를 모두 담는다") {
        let k = ThumbnailDiskStore.key(path: "/a/b.jpg", mtimeSec: 1700000000, fileSize: 1234, px: 440)
        check(k.hasSuffix("_1700000000_1234_440"), "접미사")
        checkEqual(k.count, 16 + "_1700000000_1234_440".count, "해시 16자")
        check(k != ThumbnailDiskStore.key(path: "/a/c.jpg", mtimeSec: 1700000000, fileSize: 1234, px: 440), "경로 다르면 다름")
    }

    runTest("testKeyChangesWithSize: mtime 같고 size만 달라도 다른 키") {
        let a = ThumbnailDiskStore.key(path: "/a.jpg", mtimeSec: 1, fileSize: 100, px: 440)
        let b = ThumbnailDiskStore.key(path: "/a.jpg", mtimeSec: 1, fileSize: 101, px: 440)
        check(a != b, "size 반영")
    }

    runTest("store 후 lookup 적중, usedBytes 증가") {
        let store = ThumbnailDiskStore(directory: root.appendingPathComponent("c1"), limitBytes: 100_000_000)
        check(store.isAvailable, "디렉터리 생성")
        let file = makeSource(src, "a.jpg", bytes: 10)
        check(store.lookup(url: file, minPx: 440, levels: levels) == nil, "비어 있음")
        store.store(makeCGImage(px: 440), url: file, px: 440)
        check(store.usedBytes > 0, "usedBytes 증가")
        let hit = store.lookup(url: file, minPx: 440, levels: levels)
        checkEqual(hit?.width ?? 0, 440, "적중 크기")
    }

    runTest("더 큰 px 항목이 작은 요청을 만족한다, 작은 항목은 큰 요청을 못 만족한다") {
        let store = ThumbnailDiskStore(directory: root.appendingPathComponent("c2"), limitBytes: 100_000_000)
        let file = makeSource(src, "b.jpg", bytes: 10)
        store.store(makeCGImage(px: 330), url: file, px: 330)
        checkEqual(store.lookup(url: file, minPx: 220, levels: levels)?.width ?? 0, 330, "220 요청 → 330 적중")
        check(store.lookup(url: file, minPx: 440, levels: levels) == nil, "440 요청 → 없음")
    }

    runTest("원본 mtime이 바뀌면 적중하지 않는다") {
        let store = ThumbnailDiskStore(directory: root.appendingPathComponent("c3"), limitBytes: 100_000_000)
        let file = makeSource(src, "c.jpg", bytes: 10, mtime: Date(timeIntervalSince1970: 1_000_000))
        store.store(makeCGImage(px: 440), url: file, px: 440)
        try! FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 2_000_000)], ofItemAtPath: file.path)
        check(store.lookup(url: file, minPx: 440, levels: levels) == nil, "mtime 변경 후 미적중")
    }

    runTest("testLoweringLimitTriggersGC: 한도를 내리면 오래된 것부터 지워 90% 이하로") {
        let store = ThumbnailDiskStore(directory: root.appendingPathComponent("c4"), limitBytes: 100_000_000)
        var files: [URL] = []
        for i in 0..<6 {
            let f = makeSource(src, "g\(i).jpg", bytes: 10)
            files.append(f)
            store.store(makeCGImage(px: 440), url: f, px: 440)
            Thread.sleep(forTimeInterval: 0.02)  // 저장 시각 차이
        }
        let perItem = store.usedBytes / 6
        store.limitBytes = perItem * 3  // GC는 비동기(utility 큐)라 기다려야 한다
        let target = Int(Double(perItem * 3) * 0.9) + perItem
        check(waitUntil { store.usedBytes <= target }, "90% 근처까지 감소")
        check(store.lookup(url: files[0], minPx: 440, levels: levels) == nil, "가장 오래된 것 삭제")
        check(store.lookup(url: files[5], minPx: 440, levels: levels) != nil, "가장 최근 것 유지")
    }

    runTest("lookup 적중은 LRU 순서를 갱신한다") {
        let store = ThumbnailDiskStore(directory: root.appendingPathComponent("c5"), limitBytes: 100_000_000)
        var files: [URL] = []
        for i in 0..<3 {
            let f = makeSource(src, "l\(i).jpg", bytes: 10)
            files.append(f)
            store.store(makeCGImage(px: 440), url: f, px: 440)
            Thread.sleep(forTimeInterval: 0.02)
        }
        Thread.sleep(forTimeInterval: 0.02)
        _ = store.lookup(url: files[0], minPx: 440, levels: levels)  // 가장 오래된 것을 방금 씀
        let perItem = store.usedBytes / 3
        store.limitBytes = perItem * 2
        check(waitUntil { store.usedBytes <= Int(Double(perItem * 2) * 0.9) + perItem }, "GC 완료")
        check(store.lookup(url: files[0], minPx: 440, levels: levels) != nil, "최근 사용한 것 유지")
        check(store.lookup(url: files[1], minPx: 440, levels: levels) == nil, "안 쓴 오래된 것 삭제")
    }

    runTest("limitBytes 변경은 호출자를 막지 않는다") {
        let store = ThumbnailDiskStore(directory: root.appendingPathComponent("c8"), limitBytes: 100_000_000)
        for i in 0..<4 {
            store.store(makeCGImage(px: 440), url: makeSource(src, "n\(i).jpg", bytes: 10), px: 440)
        }
        let started = Date()
        store.limitBytes = 1  // 전부 지워야 하는 상황
        check(Date().timeIntervalSince(started) < 0.05, "setter가 GC를 기다리지 않음")
        check(waitUntil { store.usedBytes == 0 }, "비동기 GC로 0까지")
    }

    runTest("clear는 전부 지우고 usedBytes 0") {
        let store = ThumbnailDiskStore(directory: root.appendingPathComponent("c6"), limitBytes: 100_000_000)
        let f = makeSource(src, "z.jpg", bytes: 10)
        store.store(makeCGImage(px: 440), url: f, px: 440)
        store.clear()
        checkEqual(store.usedBytes, 0, "usedBytes")
        check(store.lookup(url: f, minPx: 440, levels: levels) == nil, "비어 있음")
        check(store.isAvailable, "clear 후에도 사용 가능")
    }

    runTest("recount는 디렉터리 실제 크기로 맞춘다") {
        let dir = root.appendingPathComponent("c7")
        let store = ThumbnailDiskStore(directory: dir, limitBytes: 100_000_000)
        let f = makeSource(src, "r.jpg", bytes: 10)
        store.store(makeCGImage(px: 440), url: f, px: 440)
        let before = store.usedBytes
        let store2 = ThumbnailDiskStore(directory: dir, limitBytes: 100_000_000)  // 새 인스턴스는 0부터
        checkEqual(store2.usedBytes, 0, "초기값")
        store2.recount()
        checkEqual(store2.usedBytes, before, "재계산")
    }

    try? FileManager.default.removeItem(at: root)
}
