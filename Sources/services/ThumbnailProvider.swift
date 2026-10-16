import AppKit
import QuickLookThumbnailing

enum ThumbnailResult {
    case image(NSImage)
    case failed
    case notDownloaded
}

struct ThumbnailRequestToken: Hashable {
    fileprivate let id: UInt64
    fileprivate let key: ThumbnailProvider.Key
}

/// 썸네일 공급자. 메모리 캐시 → (디스크 캐시) → 생성 순으로 찾고, 같은 (url, 크기)의 동시 요청은 생성 한 번으로 합친다.
/// 모든 공개 메서드는 메인 스레드에서 부른다. 워커 완료는 메인으로 돌아와 테이블을 갱신한다.
@MainActor
final class ThumbnailProvider {
    /// 워커 스레드(nonisolated)에서도 읽으므로 격리에서 뺀다.
    nonisolated static let levels = [220, 330, 440]

    struct Key: Hashable {
        let url: URL
        let level: Int
    }

    private struct Waiter {
        let id: UInt64
        let completion: (ThumbnailResult) -> Void
    }

    private final class InFlight {
        var schedulerToken: ThumbnailScheduler.Token?
        var waiters: [Waiter] = []
        var priority: ThumbnailPriority
        init(priority: ThumbnailPriority) { self.priority = priority }
    }

    private let memoryCache: ThumbnailCache
    private let scheduler: ThumbnailScheduler
    private let generate: (URL, CGSize) -> NSImage?
    private var inFlight: [Key: InFlight] = [:]
    private var nextWaiterID: UInt64 = 0
    /// (경로, mtime) 별 실패 기억 — 같은 세션에서 깨진 파일을 다시 디코딩하지 않는다.
    private var failedKeys: Set<String> = []

    /// Task 0 스파이크 결과. true면 iCloud 비워진 파일의 visible 요청에 QuickLook 썸네일을 시도한다.
    var useQuickLookForEvicted = false

    init(workerCount: Int, memoryCache: ThumbnailCache, generate: @escaping (URL, CGSize) -> NSImage?) {
        self.memoryCache = memoryCache
        self.scheduler = ThumbnailScheduler(workerCount: workerCount)
        self.generate = generate
    }

    nonisolated static func level(forMinPixel minPixel: Int) -> Int {
        levels.first { $0 >= minPixel } ?? levels.last!
    }

    // MARK: - Public

    func cachedThumbnail(for url: URL, minPixel: Int) -> NSImage? {
        memoryCache.thumbnail(for: url, minPixelSize: minPixel)
    }

    @discardableResult
    func request(_ url: URL, minPixel: Int, priority: ThumbnailPriority,
                 completion: @escaping (ThumbnailResult) -> Void) -> ThumbnailRequestToken? {
        if let hit = memoryCache.thumbnail(for: url, minPixelSize: minPixel) {
            completion(.image(hit))
            return nil
        }
        let level = Self.level(forMinPixel: minPixel)
        let key = Key(url: url, level: level)
        nextWaiterID += 1
        let waiter = Waiter(id: nextWaiterID, completion: completion)
        let token = ThumbnailRequestToken(id: waiter.id, key: key)

        if let existing = inFlight[key] {
            existing.waiters.append(waiter)
            // 선로드로 들어가 있던 항목이 보이게 되면 우선순위만 올린다. 이미 워커가 디코딩 중이면(reprioritize가 false)
            // 그대로 기다린다 — 취소·재등록은 한 디코딩을 버리고 두 번 하는 셈이다.
            if priority > existing.priority {
                existing.priority = priority
                if let t = existing.schedulerToken { scheduler.reprioritize(t, to: priority) }
            }
            return token
        }

        let entry = InFlight(priority: priority)
        entry.waiters = [waiter]
        inFlight[key] = entry
        entry.schedulerToken = schedule(key: key, priority: priority)
        return token
    }

    func cancel(_ token: ThumbnailRequestToken) {
        guard let entry = inFlight[token.key] else { return }
        entry.waiters.removeAll { $0.id == token.id }
        if entry.waiters.isEmpty {
            if let t = entry.schedulerToken { scheduler.cancel(t) }
            inFlight.removeValue(forKey: token.key)
        }
    }

    func cancelAllPending() {
        scheduler.cancelAll()
        inFlight.removeAll()
    }

    func invalidate(for url: URL) {
        memoryCache.invalidate(for: url)
        failedKeys = failedKeys.filter { !$0.hasPrefix(url.path + "|") }
    }

    func clearMemory() {
        memoryCache.clearAll()
        failedKeys.removeAll()
    }

    func setMemoryLimit(bytes: Int) {
        memoryCache.setMemoryLimit(bytes: bytes)
    }

    // MARK: - Pipeline

    private func schedule(key: Key, priority: ThumbnailPriority) -> ThumbnailScheduler.Token {
        let generate = self.generate
        let useQL = useQuickLookForEvicted
        let failedSnapshot = failedKeys
        return scheduler.enqueue(priority: priority) { [weak self] isCancelled in
            let outcome = Self.produce(key: key, priority: priority, useQuickLook: useQL,
                                       failedKeys: failedSnapshot, generate: generate)
            if isCancelled() { return }
            Task { @MainActor [weak self] in
                self?.finish(key: key, outcome: outcome)
            }
        }
    }

    private enum Outcome {
        case image(NSImage, store: Bool)
        case failed(fileStamp: String)
        case notDownloaded
    }

    /// 워커 스레드에서 실행. 디스크 조회는 Task 7에서 이 안에 끼운다.
    nonisolated private static func produce(key: Key, priority: ThumbnailPriority, useQuickLook: Bool,
                                            failedKeys: Set<String>,
                                            generate: (URL, CGSize) -> NSImage?) -> Outcome {
        let url = key.url
        let stamp = fileStamp(url)
        if failedKeys.contains(stamp) { return .failed(fileStamp: stamp) }

        if isEvictedICloudItem(url) {
            if priority == .visible, useQuickLook, let img = quickLookThumbnail(url: url, level: key.level) {
                return .image(img, store: false)
            }
            return .notDownloaded
        }

        let pt = CGFloat(key.level) / 2  // 생성 시 레티나 2배
        if let img = generate(url, CGSize(width: pt, height: pt)) {
            return .image(img, store: true)
        }
        return .failed(fileStamp: stamp)
    }

    private func finish(key: Key, outcome: Outcome) {
        // 캐시·실패 기억은 대기자가 남아 있든 없든 반영한다. cancelAllPending()으로 entry가 사라진 뒤 도착한
        // 결과도 이미 디코딩을 마친 것이라, 버리면 폴더를 다시 열 때 같은 비용을 두 번 낸다.
        let result: ThumbnailResult
        switch outcome {
        case .image(let img, let store):
            if store { memoryCache.store(img, for: key.url) }
            result = .image(img)
        case .failed(let stamp):
            failedKeys.insert(stamp)
            result = .failed
        case .notDownloaded:
            result = .notDownloaded
        }
        guard let entry = inFlight.removeValue(forKey: key) else { return }
        for w in entry.waiters { w.completion(result) }
    }

    // MARK: - File helpers (워커 스레드)

    /// `URL.resourceValues`는 같은 인스턴스에 캐시되고, 그 캐시는 런루프 끝에서만 비워진다. 워커 스레드엔 런루프가
    /// 없어 영원히 옛 값이 돌아온다(Task 0 스파이크에서 확인). 그래서 읽을 때마다 새 인스턴스를 만든다.
    nonisolated private static func freshURL(_ url: URL) -> URL {
        URL(fileURLWithPath: url.path)
    }

    nonisolated private static func fileStamp(_ url: URL) -> String {
        let rv = try? freshURL(url).resourceValues(forKeys: [.contentModificationDateKey])
        let mtime = Int(rv?.contentModificationDate?.timeIntervalSince1970 ?? 0)
        return url.path + "|" + String(mtime)
    }

    /// iCloud Drive가 관리하고 아직 로컬에 없는 파일인지. 메타데이터 조회만 하며 다운로드를 유발하지 않는다.
    /// macOS 26에선 비워진 파일도 원래 이름의 dataless 파일로 보이므로(`.icloud` 자리표시 없음) 파일명으로 판별하면 안 된다.
    nonisolated static func isEvictedICloudItem(_ url: URL) -> Bool {
        guard let rv = try? freshURL(url).resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]),
              rv.isUbiquitousItem == true else { return false }
        return rv.ubiquitousItemDownloadingStatus == .notDownloaded
    }

    nonisolated private static func quickLookThumbnail(url: URL, level: Int) -> NSImage? {
        let pt = CGFloat(level) / 2
        let req = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: pt, height: pt),
                                               scale: 2, representationTypes: .thumbnail)
        let sem = DispatchSemaphore(value: 0)
        var image: NSImage?
        QLThumbnailGenerator.shared.generateBestRepresentation(for: req) { rep, _ in
            if let cg = rep?.cgImage {
                image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            }
            sem.signal()
        }
        sem.wait()
        return image
    }
}
