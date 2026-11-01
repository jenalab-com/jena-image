import AppKit

extension ThumbnailProvider {
    /// 워커 수: 코어 - 1, 최소 2, 최대 8.
    static var defaultWorkerCount: Int {
        min(8, max(2, ProcessInfo.processInfo.activeProcessorCount - 1))
    }

    static let shared: ThumbnailProvider = {
        let service = ImageService()
        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.jenalab.jenaimage/thumbs", isDirectory: true)
        let disk = ThumbnailDiskStore(directory: cachesDir,
                                      limitBytes: AppSettings.shared.thumbnailDiskCacheMB * 1024 * 1024)
        let provider = ThumbnailProvider(
            workerCount: defaultWorkerCount,
            memoryCache: .shared,
            diskStore: disk.isAvailable ? disk : nil
        ) { url, size in
            if case .success(let img) = service.generateThumbnailSync(at: url, size: size) { return img }
            return nil
        }
        // 비워진 iCloud 파일: QuickLook은 원본을 내려받지 않고 썸네일을 주지만 ImageIO는 다운로드를 유발한다.
        provider.useQuickLookForEvicted = true
        provider.scheduleDiskRecount()
        return provider
    }()
}
