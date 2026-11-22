import AppKit
import WebKit

enum WebImageSaveError: LocalizedError {
    case unsupportedAddress, notAnImage, folderMissing, download(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedAddress: return "저장할 수 없는 주소입니다."
        case .notAnImage: return "이미지가 아닙니다."
        case .folderMissing: return "저장할 폴더가 없습니다."
        case .download(let detail): return detail
        }
    }
}

/// 웹 이미지를 고른 폴더에 저장한다. http(s)는 고른 탭의 웹 뷰로 내려받기를 시작해 쿠키가 실리고 `Referer`를 페이지 주소로 넣는다.
/// 저장은 그 탭에 묶이지 않는다 — 시작한 뒤 탭을 닫아도 끝까지 간다.
/// `data:`는 직접 풀어 쓴다. 기존 파일은 덮어쓰지 않고, 이미지가 아니면 이번 저장이 만든 파일만 지운다.
/// `save` 한 번에 `onFinish`는 정확히 한 번 불린다.
@MainActor
final class WebImageSaver: NSObject, WKDownloadDelegate {
    var onFinish: ((Result<URL, WebImageSaveError>, _ folder: URL) -> Void)?

    private struct Job {
        let download: WKDownload
        let folder: URL
        let source: URL
        var destination: URL?
    }
    private let engine: WebPageEngine
    private var jobs: [ObjectIdentifier: Job] = [:]
    /// 진행 중인 저장이 고른 경로(`reservationKey`). 동시 저장이 같은 이름을 고르지 않게 `exists`에 포함한다.
    private var reserved: Set<String> = []

    init(engine: WebPageEngine) {
        self.engine = engine
    }

    func save(_ report: WebImageReport, to folder: URL) {
        guard let url = WebImageCandidate.bestURL(for: report) else { finish(.failure(.unsupportedAddress), folder); return }
        guard Self.folderExists(folder) else { finish(.failure(.folderMissing), folder); return }
        if url.scheme?.lowercased() == "data" { saveDataURL(url, to: folder); return }

        var request = URLRequest(url: url)
        if let page = URL(string: report.pageURL), ["http", "https"].contains(page.scheme?.lowercased() ?? "") {
            request.setValue(report.pageURL, forHTTPHeaderField: "Referer")
        }
        // 고른 탭의 웹 뷰로 시작만 한다. 내려받기는 시작한 웹 뷰가 닫혀 풀려도 끝까지 간다(테스트로 고정).
        // 페이지 없는 전용 웹 뷰로 받으면 WebKit이 Referer를 출처(`https://호스트/`)로 줄여 쓰지 않는다(2026-11-22 확인).
        engine.webView.startDownload(using: request) { [weak self] download in
            guard let self else { return }
            self.jobs[ObjectIdentifier(download)] = Job(download: download, folder: folder, source: url)
            download.delegate = self
        }
    }

    /// 진행 중인 저장을 모두 멈춘다(창을 닫아 앱이 끝날 때). 받은 바이트가 있는 대상, 곧 이번 저장이 만든 파일은 지운다.
    /// WebKit은 취소한 내려받기의 조각을 이어받기용으로 남겨 두므로 지금 한 번, 취소가 끝난 뒤 한 번 더 지운다.
    /// 저장마다 실패 결과를 한 번 알린다.
    func cancelAll() {
        let pending = jobs
        jobs.removeAll()
        for job in pending.values {
            let progress = job.download.progress
            let destination = job.destination
            if let destination {
                reserved.remove(Self.reservationKey(destination))
                if progress.completedUnitCount > 0 { try? FileManager.default.removeItem(at: destination) }
            }
            job.download.cancel { _ in
                guard let destination, progress.completedUnitCount > 0 else { return }
                try? FileManager.default.removeItem(at: destination)
            }
            finish(.failure(.download("저장을 취소했습니다.")), job.folder)
        }
    }

    // MARK: data:

    private func saveDataURL(_ url: URL, to folder: URL) {
        guard let (data, mimeType) = WebImageCandidate.decodeDataURL(url), mimeType.hasPrefix("image/") else {
            finish(.failure(.notAnImage), folder); return
        }
        let name = WebImageCandidate.fileName(suggested: nil, url: url, mimeType: mimeType, now: Date())
        guard Self.hasImageExtension(name) else { finish(.failure(.notAnImage), folder); return }
        let destination = uniqueDestination(for: name, in: folder)
        do {
            try data.write(to: destination, options: .withoutOverwriting)
        } catch {
            reserved.remove(Self.reservationKey(destination))
            finish(.failure(.download(error.localizedDescription)), folder); return
        }
        finish(verify(destination), folder)
    }

    // MARK: WKDownloadDelegate

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                  suggestedFilename: String) async -> URL? {
        let id = ObjectIdentifier(download)
        guard var job = jobs[id] else { return nil }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            return abandon(id, .download("서버 응답 \(http.statusCode)"))
        }
        // 이름을 정하기 전에 거른다. MIME이 이미지가 아니거나(모르는 경우 제외) 이미지 확장자를 못 붙이면 디스크에 닿지 않는다.
        let mimeType = response.mimeType?.lowercased() ?? ""
        let genericMIME = mimeType.isEmpty || mimeType == "application/octet-stream" || mimeType == "binary/octet-stream"
        let name = WebImageCandidate.fileName(suggested: suggestedFilename, url: response.url ?? job.source,
                                              mimeType: response.mimeType, now: Date())
        guard mimeType.hasPrefix("image/") || genericMIME, Self.hasImageExtension(name) else {
            return abandon(id, .notAnImage)
        }
        guard Self.folderExists(job.folder) else { return abandon(id, .folderMissing) }
        let destination = uniqueDestination(for: name, in: job.folder)
        job.destination = destination
        jobs[id] = job
        return destination
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let job = jobs.removeValue(forKey: ObjectIdentifier(download)) else { return }
        guard let destination = job.destination else { finish(.failure(.notAnImage), job.folder); return }
        finish(verify(destination), job.folder)
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        guard let job = jobs.removeValue(forKey: ObjectIdentifier(download)) else { return }
        if let destination = job.destination {
            reserved.remove(Self.reservationKey(destination))
            // 받은 바이트가 있어야 남은 조각이 이번 저장의 것이다. 대상이 이미 있으면 WebKit은 아무것도 쓰지 않고
            // 취소(-999)나 "Cannot create file"로 끝나므로, 그때의 파일은 다른 저장이나 사용자의 것이다.
            if download.progress.completedUnitCount > 0 { try? FileManager.default.removeItem(at: destination) }
        }
        finish(.failure(.download(error.localizedDescription)), job.folder)
    }

    // MARK: 도우미

    /// 내려받기를 취소(nil 반환)하고 결과를 지금 알린다. 뒤따르는 실패 콜백은 작업이 없어 무시된다.
    private func abandon(_ id: ObjectIdentifier, _ error: WebImageSaveError) -> URL? {
        if let job = jobs.removeValue(forKey: id) { finish(.failure(error), job.folder) }
        return nil
    }

    private func uniqueDestination(for name: String, in folder: URL) -> URL {
        let unique = UniqueFileName.make(for: name, in: folder) { url in
            FileManager.default.fileExists(atPath: url.path) || reserved.contains(Self.reservationKey(url))
        }
        let destination = folder.appendingPathComponent(unique)
        reserved.insert(Self.reservationKey(destination))
        return destination
    }

    /// 앱이 여는 이미지이고 실제로 읽히는지. 아니면 이번 저장이 만든 그 파일만 지운다.
    private func verify(_ file: URL) -> Result<URL, WebImageSaveError> {
        reserved.remove(Self.reservationKey(file))
        if ImageFile(url: file)?.isImage == true, NSImage(contentsOf: file) != nil { return .success(file) }
        try? FileManager.default.removeItem(at: file)
        return .failure(.notAnImage)
    }

    private func finish(_ result: Result<URL, WebImageSaveError>, _ folder: URL) {
        onFinish?(result, folder)
    }

    /// 기본 APFS는 대소문자와 유니코드 정규화를 가리지 않는다. 예약도 같은 기준으로 비교한다
    /// (구분하는 볼륨에서는 조금 더 많이 피할 뿐이다).
    /// 정규화는 늘 있는 폴더 쪽에만 한다. `standardizedFileURL`은 파일이 있을 때만 `/private`를 떼어 내
    /// 예약할 때(파일 없음)와 풀 때(파일 있음)의 키가 달라지기 때문이다.
    private static func reservationKey(_ url: URL) -> String {
        let folder = url.deletingLastPathComponent().standardizedFileURL.path
        return (folder as NSString).appendingPathComponent(url.lastPathComponent).precomposedStringWithCanonicalMapping.lowercased()
    }

    private static func hasImageExtension(_ name: String) -> Bool {
        WebImageCandidate.imageExtensions.contains((name as NSString).pathExtension.lowercased())
    }

    private static func folderExists(_ folder: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
