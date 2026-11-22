import CryptoKit
import Foundation

/// GitHub 최신 릴리스 한 건. 설치에 쓰는 DMG 첨부와 그 검증값을 담는다.
struct AppRelease: Equatable {
    let version: String
    let notes: String
    let pageURL: URL
    let assetURL: URL
    let assetSize: Int
    let sha256: String?
}

enum AppUpdateError: LocalizedError, Equatable {
    case noRelease, rateLimited, badResponse, missingAsset, missingDigest, sizeMismatch, digestMismatch
    case invalidBundle(String), mountFailed, replaceFailed(String)

    var errorDescription: String? {
        switch self {
        case .noRelease: return "공개된 릴리스를 찾지 못했어요."
        case .rateLimited: return "GitHub 조회 한도를 넘었어요. 잠시 후 다시 확인해 주세요."
        case .badResponse: return "업데이트 정보를 읽지 못했어요. 네트워크를 확인한 뒤 다시 시도해 주세요."
        case .missingAsset: return "이 릴리스에는 설치 파일(DMG)이 없어요."
        case .missingDigest: return "설치 파일의 검증 정보가 없어 안전하게 설치할 수 없어요."
        case .sizeMismatch, .digestMismatch: return "내려받은 파일이 릴리스와 일치하지 않아요. 설치를 중단했어요."
        case .invalidBundle(let reason): return "설치 파일 안의 앱이 올바르지 않아요. \(reason)"
        case .mountFailed: return "설치 파일(DMG)을 열지 못했어요."
        case .replaceFailed(let reason): return "업데이트를 준비하지 못했어요. \(reason)"
        }
    }
}

enum AppVersion {
    /// "v2.1.0-beta" → [2, 1, 0]. 숫자가 아닌 꼬리표는 무시한다.
    static func components(_ version: String) -> [Int] {
        var text = version.trimmingCharacters(in: .whitespaces)
        if text.lowercased().hasPrefix("v") { text.removeFirst() }
        let core = text.split(separator: "-", maxSplits: 1).first.map(String.init) ?? text
        return core.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = components(candidate), b = components(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}

/// 최신 릴리스 조회와 설치 파일 내려받기·검증. 설치(교체)는 `AppUpdateInstaller`가 맡는다.
final class AppUpdateService {
    static let defaultFeedURL = URL(string: "https://api.github.com/repos/jenalab-com/jena-image/releases/latest")!
    /// 검증·시연용으로 확인 주소를 바꾼다. 화면에는 노출하지 않는다.
    static let feedOverrideKey = "updateFeedURL"

    static func configuredFeedURL(defaults: UserDefaults = .standard) -> URL {
        guard let text = defaults.string(forKey: feedOverrideKey), let url = URL(string: text) else { return defaultFeedURL }
        return url
    }

    let feedURL: URL

    init(feedURL: URL = AppUpdateService.configuredFeedURL()) {
        self.feedURL = feedURL
    }

    func latestRelease() async throws -> AppRelease {
        var request = URLRequest(url: feedURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("JenaImage", forHTTPHeaderField: "User-Agent")
        let (data, response): (Data, URLResponse)
        do { (data, response) = try await URLSession.shared.data(for: request) }
        catch { throw AppUpdateError.badResponse }
        if let http = response as? HTTPURLResponse {
            switch http.statusCode {
            case 200: break
            case 404: throw AppUpdateError.noRelease
            case 403, 429: throw AppUpdateError.rateLimited
            default: throw AppUpdateError.badResponse
            }
        }
        return try Self.parseRelease(data)
    }

    static func parseRelease(_ data: Data) throws -> AppRelease {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let page = (json["html_url"] as? String).flatMap(URL.init(string:)) else {
            throw AppUpdateError.badResponse
        }
        let assets = json["assets"] as? [[String: Any]] ?? []
        guard let dmg = assets.first(where: { ($0["name"] as? String)?.lowercased().hasSuffix(".dmg") == true }),
              let url = (dmg["browser_download_url"] as? String).flatMap(URL.init(string:)),
              let size = dmg["size"] as? Int else {
            throw AppUpdateError.missingAsset
        }
        let digest = (dmg["digest"] as? String).flatMap { value -> String? in
            guard value.lowercased().hasPrefix("sha256:") else { return nil }
            return String(value.dropFirst("sha256:".count)).lowercased()
        }
        let version = tag.lowercased().hasPrefix("v") ? String(tag.dropFirst()) : tag
        return AppRelease(version: version, notes: json["body"] as? String ?? "", pageURL: page,
                          assetURL: url, assetSize: size, sha256: digest)
    }

    /// 임시 폴더에 내려받고 크기·해시를 검증한 파일을 돌려준다. 검증에 실패하면 파일을 지운다.
    func download(_ release: AppRelease, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("JenaImage-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appendingPathComponent(release.assetURL.lastPathComponent)
        do {
            let downloaded = try await DownloadTask(progress: progress).run(release.assetURL)
            try FileManager.default.moveItem(at: downloaded, to: destination)
            try Self.verify(file: destination, release: release)
            progress(1)
            return destination
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw (error as? AppUpdateError) ?? .badResponse
        }
    }

    static func verify(file: URL, release: AppRelease) throws {
        guard let expected = release.sha256 else { throw AppUpdateError.missingDigest }
        let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1
        guard size == release.assetSize else { throw AppUpdateError.sizeMismatch }
        guard try sha256Hex(of: file) == expected else { throw AppUpdateError.digestMismatch }
    }

    static func sha256Hex(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// URLSession 내려받기를 진행률과 함께 async로 감싼다.
private final class DownloadTask: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let progress: @Sendable (Double) -> Void
    private var continuation: CheckedContinuation<URL, Error>?

    init(progress: @escaping @Sendable (Double) -> Void) { self.progress = progress }

    func run(_ url: URL) async throws -> URL {
        let session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            session.downloadTask(with: url).resume()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        progress(min(0.99, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // 콜백이 끝나면 시스템이 파일을 지우므로 먼저 옮겨 둔다.
        let kept = FileManager.default.temporaryDirectory.appendingPathComponent("JenaImage-dl-\(UUID().uuidString)")
        if let http = downloadTask.response as? HTTPURLResponse, http.statusCode != 200 {
            finish(.failure(AppUpdateError.badResponse))
        } else if (try? FileManager.default.moveItem(at: location, to: kept)) != nil {
            finish(.success(kept))
        } else {
            finish(.failure(AppUpdateError.badResponse))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(.failure(error)) }
    }

    private func finish(_ result: Result<URL, Error>) {
        continuation?.resume(with: result)
        continuation = nil
    }
}
