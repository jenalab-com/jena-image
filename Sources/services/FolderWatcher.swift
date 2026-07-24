import Foundation

/// 폴더의 파일시스템 변경을 감시하여 콜백으로 알림
final class FolderWatcher {
    private var sources: [URL: DispatchSourceFileSystemObject] = [:]
    private var descriptors: [URL: Int32] = [:]
    private let queue = DispatchQueue(label: "com.jenalab.folderwatcher", qos: .utility)
    var onChange: ((URL) -> Void)?

    /// 열린 파일 디스크립터가 무한정 늘지 않도록 동시 감시 폴더 수를 제한
    private static let maxWatchedFolders = 256

    /// 현재 감시 중인 폴더 목록
    var watchedURLs: [URL] {
        Array(sources.keys)
    }

    /// 지정 폴더 감시 시작 (이미 감시 중이면 무시)
    func watch(_ url: URL) {
        guard sources[url] == nil else { return }
        guard sources.count < Self.maxWatchedFolders else { return }

        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: queue
        )

        source.setEventHandler { [weak self] in
            DispatchQueue.main.async {
                self?.onChange?(url)
            }
        }

        source.setCancelHandler {
            close(fd)
        }

        sources[url] = source
        descriptors[url] = fd
        source.resume()
    }

    /// 지정 폴더 감시 중지
    func unwatch(_ url: URL) {
        sources[url]?.cancel()
        sources.removeValue(forKey: url)
        descriptors.removeValue(forKey: url)
    }

    /// 모든 감시 중지
    func unwatchAll() {
        for (_, source) in sources {
            source.cancel()
        }
        sources.removeAll()
        descriptors.removeAll()
    }

    deinit {
        unwatchAll()
    }
}
