import AppKit

/// LRU 기반 썸네일 메모리 캐시 (NSCache 래핑)
///
/// 항목마다 원본의 스탬프(mtime·size)를 함께 둔다. 조회 시 현재 스탬프와 다르면 옛 항목을 버리고 nil을 돌려,
/// Finder·외부 편집기로 파일이 바뀌어도 폴더를 다시 그릴 때 옛 그림이 남지 않는다(디스크 계층의 mtime 키와 같은 역할).
final class ThumbnailCache {
    static let shared = ThumbnailCache()

    private final class Entry {
        let image: NSImage
        let stamp: String
        init(image: NSImage, stamp: String) { self.image = image; self.stamp = stamp }
    }

    private let cache = NSCache<NSURL, Entry>()

    private static let defaultMemoryLimit = 500 * 1024 * 1024  // 500MB

    init(memoryLimit: Int = ThumbnailCache.defaultMemoryLimit) {
        cache.totalCostLimit = memoryLimit
    }

    /// 설정 "적용" 시 호출. 한도를 넘는 항목은 NSCache가 알아서 밀어낸다.
    func setMemoryLimit(bytes: Int) {
        cache.totalCostLimit = bytes
    }

    /// 원본 파일의 변경 스탬프 `"<mtimeSec>|<size>"`. 새 URL 인스턴스로 읽는다 — 리소스 값 캐시가 런루프 없는
    /// 스레드에서 비워지지 않아 옛 값을 돌려주기 때문(Task 0 스파이크). 읽기 실패(삭제 등)는 빈 문자열.
    static func stamp(for url: URL) -> String {
        guard let rv = try? URL(fileURLWithPath: url.path).resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
              let mtime = rv.contentModificationDate else { return "" }
        return "\(Int(mtime.timeIntervalSince1970))|\(rv.fileSize ?? 0)"
    }

    func thumbnail(for url: URL) -> NSImage? {
        validEntry(for: url)?.image
    }

    /// 긴 변이 `minPixelSize` 이상인 썸네일만 돌려준다. 작은 썸네일(스트립용 등)이 캐시돼 있으면
    /// nil을 돌려 호출자가 더 큰 크기로 다시 생성하게 한다.
    func thumbnail(for url: URL, minPixelSize: Int) -> NSImage? {
        guard let image = validEntry(for: url)?.image else { return nil }
        return Self.longestPixelSide(of: image) >= minPixelSize ? image : nil
    }

    /// 같은 URL에 더 큰 썸네일이 이미 있으면 덮어쓰지 않는다 — 브라우저(큰 것)와 스트립(작은 것)이
    /// 한 캐시를 공유하므로, 큰 쪽을 남겨야 그리드가 흐려지지 않는다. 단 스탬프가 다르면(원본이 바뀜) 덮어쓴다.
    /// - Parameter stamp: 이미지를 만든 시점의 원본 스탬프. 생략하면 지금 읽는다.
    func store(_ image: NSImage, for url: URL, stamp: String? = nil) {
        let newStamp = stamp ?? Self.stamp(for: url)
        if let existing = cache.object(forKey: url as NSURL),
           existing.stamp == newStamp,
           Self.longestPixelSide(of: existing.image) >= Self.longestPixelSide(of: image) {
            return
        }
        let cost = estimateCost(of: image)
        cache.setObject(Entry(image: image, stamp: newStamp), forKey: url as NSURL, cost: cost)
    }

    private func validEntry(for url: URL) -> Entry? {
        guard let entry = cache.object(forKey: url as NSURL) else { return nil }
        guard entry.stamp == Self.stamp(for: url) else {
            cache.removeObject(forKey: url as NSURL)  // 원본이 바뀌었거나 사라짐
            return nil
        }
        return entry
    }

    private static func longestPixelSide(of image: NSImage) -> Int {
        guard let rep = image.representations.first else { return 0 }
        return max(rep.pixelsWide, rep.pixelsHigh)
    }

    func invalidate(for url: URL) {
        cache.removeObject(forKey: url as NSURL)
    }

    func clearAll() {
        cache.removeAllObjects()
    }

    private func estimateCost(of image: NSImage) -> Int {
        guard let rep = image.representations.first else { return 0 }
        return rep.pixelsWide * rep.pixelsHigh * 4  // RGBA 4 bytes per pixel
    }
}
