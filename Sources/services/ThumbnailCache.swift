import AppKit

/// LRU 기반 썸네일 메모리 캐시 (NSCache 래핑)
final class ThumbnailCache {
    static let shared = ThumbnailCache()

    private let cache = NSCache<NSURL, NSImage>()

    private static let defaultMemoryLimit = 500 * 1024 * 1024  // 500MB

    init(memoryLimit: Int = ThumbnailCache.defaultMemoryLimit) {
        cache.totalCostLimit = memoryLimit
    }

    func thumbnail(for url: URL) -> NSImage? {
        cache.object(forKey: url as NSURL)
    }

    func store(_ image: NSImage, for url: URL) {
        let cost = estimateCost(of: image)
        cache.setObject(image, forKey: url as NSURL, cost: cost)
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
