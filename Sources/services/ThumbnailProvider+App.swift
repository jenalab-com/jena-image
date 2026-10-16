import AppKit

extension ThumbnailProvider {
    /// 워커 수: 코어 - 1, 최소 2, 최대 8.
    static var defaultWorkerCount: Int {
        min(8, max(2, ProcessInfo.processInfo.activeProcessorCount - 1))
    }

    static let shared: ThumbnailProvider = {
        let service = ImageService()
        let provider = ThumbnailProvider(
            workerCount: defaultWorkerCount,
            memoryCache: .shared
        ) { url, size in
            if case .success(let img) = service.generateThumbnailSync(at: url, size: size) { return img }
            return nil
        }
        provider.useQuickLookForEvicted = true  // Task 0 스파이크 결과(docs/devlog/2026-10-16-spike-icloud.md)
        return provider
    }()
}
