import Foundation

/// 사이드바 폴더 옆 숫자 — 그 폴더와 **모든 하위 폴더**의 미디어 파일 총계.
///
/// 트리 전체를 훑어야 하므로 백그라운드에서 계산하고 결과를 캐시한다. 한 번의 재귀로 하위 폴더 값까지
/// 모두 채우므로, 펼쳐서 드러난 하위 폴더는 보통 캐시에서 바로 나온다. 폴더가 바뀌면 그 폴더 아래와
/// 조상(총계가 바뀌므로)을 지우고 다시 센다. 상태는 메인 스레드에서만 만진다.
final class FolderMediaCountService {
    static let shared = FolderMediaCountService()

    private var cache: [String: Int] = [:]
    private var pending: [String: Operation] = [:]
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.jenalab.jenaimage.folder-count"
        queue.qualityOfService = .utility
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    private let scan: (URL, () -> Bool) -> [String: Int]

    init(scan: ((URL, () -> Bool) -> [String: Int])? = nil) {
        self.scan = scan ?? { root, isCancelled in
            var results: [String: Int] = [:]
            _ = Self.countSubtree(at: root, into: &results, isCancelled: isCancelled)
            return results
        }
    }
    private var generation = 0

    /// 계산이 끝났을 때(메인 스레드). 보이는 행의 숫자를 다시 그리면 된다.
    var onUpdate: (() -> Void)?

    /// 캐시된 총계. 없으면 nil이고, 이때 계산을 예약한다.
    func count(for url: URL) -> Int? {
        let key = url.standardizedFileURL.path
        if let cached = cache[key] { return cached }
        request(key: key)
        return nil
    }

    /// 폴더 내용이 바뀌었을 때 — 그 폴더 아래 전부와 조상의 캐시를 지운다.
    func invalidate(_ url: URL) {
        let key = url.standardizedFileURL.path
        let prefix = key.hasSuffix("/") ? key : key + "/"
        cache = cache.filter { entry in
            let path = entry.key
            if path == key || path.hasPrefix(prefix) { return false }   // 자신과 하위
            if key.hasPrefix(path.hasSuffix("/") ? path : path + "/") { return false }   // 조상
            return true
        }
        // 진행 중인 계산 결과는 더 이상 믿을 수 없으니 세대를 올려 버린다.
        generation += 1
        queue.cancelAllOperations()
        pending.removeAll()
    }

    func invalidateAll() {
        cache.removeAll()
        generation += 1
        queue.cancelAllOperations()
        pending.removeAll()
    }

    private func request(key: String) {
        // 상위 탐색이 하위 폴더의 값까지 채운다. 경로 구분자로 형제 이름의 접두사 충돌을 피한다.
        guard !pending.keys.contains(where: { key == $0 || key.hasPrefix($0.hasSuffix("/") ? $0 : $0 + "/") }) else { return }
        let prefix = key.hasSuffix("/") ? key : key + "/"
        for child in Array(pending.keys) where child.hasPrefix(prefix) {
            pending.removeValue(forKey: child)?.cancel()
        }
        let currentGeneration = generation
        let root = URL(fileURLWithPath: key, isDirectory: true)
        let scanner = scan
        let operation = BlockOperation()
        operation.addExecutionBlock { [weak self, weak operation] in
            guard let operation, !operation.isCancelled else { return }
            let results = scanner(root) { operation.isCancelled }
            guard !operation.isCancelled else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == currentGeneration,
                      self.pending[key] === operation else { return }
                self.pending.removeValue(forKey: key)
                self.cache.merge(results) { _, new in new }
                self.onUpdate?()
            }
        }
        pending[key] = operation
        queue.addOperation(operation)
    }

    /// 폴더 하나의 총계를 돌려주면서, 하위 폴더 각각의 총계도 `results`에 적는다.
    /// `FolderNode.loadChildren`과 같은 규칙: 숨김 파일 제외, 패키지는 내려가지 않음, 미디어 확장자만.
    private static func countSubtree(at url: URL, into results: inout [String: Int],
                                     isCancelled: () -> Bool) -> Int {
        guard !isCancelled() else { return 0 }
        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            results[url.standardizedFileURL.path] = 0
            return 0
        }
        var total = 0
        for item in contents {
            guard !isCancelled() else { return 0 }
            let values = try? item.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
            if values?.isDirectory == true {
                if values?.isPackage == true { continue }
                total += countSubtree(at: item, into: &results, isCancelled: isCancelled)
            } else if ImageFile.allSupportedExtensions.contains(item.pathExtension.lowercased()) {
                total += 1
            }
        }
        results[url.standardizedFileURL.path] = total
        return total
    }
}
