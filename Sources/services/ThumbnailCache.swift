import AppKit

/// LRU 기반 썸네일 메모리 캐시 (NSCache 래핑)
final class ThumbnailCache {
    static let shared = ThumbnailCache()

    private let cache = NSCache<NSURL, NSImage>()

    private static let defaultMemoryLimit = 500 * 1024 * 1024  // 500MB

    init(memoryLimit: Int = ThumbnailCache.defaultMemoryLimit) {
        cache.totalCostLimit = memoryLimit
    }

    /// 설정 "적용" 시 호출. 한도를 넘는 항목은 NSCache가 알아서 밀어낸다.
    func setMemoryLimit(bytes: Int) {
        cache.totalCostLimit = bytes
    }

    func thumbnail(for url: URL) -> NSImage? {
        cache.object(forKey: url as NSURL)
    }

    /// 긴 변이 `minPixelSize` 이상인 썸네일만 돌려준다. 작은 썸네일(스트립용 등)이 캐시돼 있으면
    /// nil을 돌려 호출자가 더 큰 크기로 다시 생성하게 한다.
    func thumbnail(for url: URL, minPixelSize: Int) -> NSImage? {
        guard let image = cache.object(forKey: url as NSURL) else { return nil }
        return Self.longestPixelSide(of: image) >= minPixelSize ? image : nil
    }

    /// 같은 URL에 더 큰 썸네일이 이미 있으면 덮어쓰지 않는다 — 브라우저(큰 것)와 스트립(작은 것)이
    /// 한 캐시를 공유하므로, 큰 쪽을 남겨야 그리드가 흐려지지 않는다.
    func store(_ image: NSImage, for url: URL) {
        if let existing = cache.object(forKey: url as NSURL),
           Self.longestPixelSide(of: existing) >= Self.longestPixelSide(of: image) {
            return
        }
        let cost = estimateCost(of: image)
        cache.setObject(image, forKey: url as NSURL, cost: cost)
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
