import Foundation
import Vision
import ImageIO
import CryptoKit

struct SimilarImageMatch: Sendable {
    let url: URL
    let distance: Float
}

struct SimilarImageSearchResult: Sendable {
    let matches: [SimilarImageMatch]
    let analyzedCount: Int
    let cachedCount: Int
    let skippedCount: Int
    let cacheWriteFailures: Int
}

enum ImageSimilarityError: LocalizedError {
    case unavailableImage, noFeaturePrint, changedDuringAnalysis

    var errorDescription: String? {
        switch self {
        case .unavailableImage: return "이 이미지를 분석할 수 없습니다. 로컬에 다운로드된 일반 이미지 파일을 선택하세요."
        case .noFeaturePrint: return "이미지 특징을 추출하지 못했습니다."
        case .changedDuringAnalysis: return "분석 중 이미지가 변경되었습니다. 다시 검색하세요."
        }
    }
}

/// Vision과 디스크 I/O는 전용 actor에서 순차 실행한다. 한 번에 한 장만 디코딩한다.
actor ImageSimilarityService {
    static let resultLimit = 100
    private let cacheDirectory: URL
    private let modelVersion = "vision-featureprint-r2-fit-512-gray-v1-" + ProcessInfo.processInfo.operatingSystemVersionString

    init(cacheDirectory: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("com.jenalab.jenaimage/similarity-v1", isDirectory: true)) {
        self.cacheDirectory = cacheDirectory
    }

    private struct Stamp: Codable, Equatable {
        let modified: Date
        let size: Int
    }

    private struct CachedPrint: Codable {
        let version: String
        let stamp: Stamp
        let observation: Data
    }

    func search(reference: URL, candidates listedURLs: [URL],
                progress: @Sendable (String) -> Void = { _ in }) throws -> SimilarImageSearchResult {
        try Task.checkCancellation()
        progress("기준 이미지 분석 중…")
        let reference = reference.standardizedFileURL.resolvingSymlinksInPath()
        let source = try featurePrint(at: reference)
        var writeFailures = source.writeFailed ? 1 : 0
        var candidates = Set<URL>()
        // 폴더를 열거하지 않고 검색 시작 시점의 목록만 사용한다.
        for url in listedURLs {
            try Task.checkCancellation()
            guard ImageFile(url: url)?.isVideo == false else { continue }
            let normalized = url.standardizedFileURL.resolvingSymlinksInPath()
            if normalized != reference { candidates.insert(normalized) }
        }

        var matches: [SimilarImageMatch] = []
        var analyzed = 0, cached = 0, skipped = 0
        let ordered = candidates.sorted { $0.path < $1.path }
        for (index, url) in ordered.enumerated() {
            try Task.checkCancellation()
            do {
                let candidate = try autoreleasepool { try featurePrint(at: url) }
                var distance: Float = 0
                try source.print.computeDistance(&distance, to: candidate.print)
                guard distance.isFinite else { skipped += 1; continue }
                analyzed += 1
                if candidate.cached { cached += 1 }
                if candidate.writeFailed { writeFailures += 1 }
                matches.append(SimilarImageMatch(url: url, distance: distance))
                matches.sort { $0.distance == $1.distance ? $0.url.path < $1.url.path : $0.distance < $1.distance }
                if matches.count > Self.resultLimit { matches.removeLast() }
            } catch is CancellationError { throw CancellationError() }
            catch { skipped += 1 }
            if index % 8 == 0 || index + 1 == ordered.count {
                progress("이미지 확인 \(index + 1) / \(ordered.count) · 저장된 분석 \(cached)개 재사용")
            }
        }
        try Task.checkCancellation()
        return SimilarImageSearchResult(matches: matches, analyzedCount: analyzed, cachedCount: cached,
                                       skippedCount: skipped, cacheWriteFailures: writeFailures)
    }

    private func stamp(at url: URL) throws -> Stamp {
        let values = try URL(fileURLWithPath: url.path).resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        guard let modified = values.contentModificationDate, let size = values.fileSize else { throw ImageSimilarityError.unavailableImage }
        return Stamp(modified: modified, size: size)
    }

    private func featurePrint(at url: URL) throws -> (print: VNFeaturePrintObservation, cached: Bool, writeFailed: Bool) {
        try Task.checkCancellation()
        guard ImageFile(url: url)?.isVideo == false,
              !ThumbnailProvider.isEvictedICloudItem(url) else { throw ImageSimilarityError.unavailableImage }
        let before = try stamp(at: url)
        let key = SHA256.hash(data: Data(url.path.utf8)).map { String(format: "%02x", $0) }.joined()
        let cacheURL = cacheDirectory.appendingPathComponent(key + ".json")
        if let data = try? Data(contentsOf: cacheURL),
           let entry = try? JSONDecoder().decode(CachedPrint.self, from: data),
           entry.version == modelVersion, entry.stamp == before,
           let observation = try? NSKeyedUnarchiver.unarchivedObject(ofClass: VNFeaturePrintObservation.self, from: entry.observation),
           observation.requestRevision == VNGenerateImageFeaturePrintRequestRevision2 {
            return (observation, true, false)
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 512,
                kCGImageSourceShouldCacheImmediately: true,
              ] as CFDictionary),
              let context = CGContext(data: nil, width: thumbnail.width, height: thumbnail.height, bitsPerComponent: 8,
                bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { throw ImageSimilarityError.unavailableImage }
        let rect = CGRect(x: 0, y: 0, width: thumbnail.width, height: thumbnail.height)
        // 화면 체크무늬를 분석에 섞지 않고, 투명 원본은 중간 회색 위에서 분석한다.
        context.setFillColor(CGColor(gray: 0.5, alpha: 1))
        context.fill(rect)
        context.draw(thumbnail, in: rect)
        guard let image = context.makeImage() else { throw ImageSimilarityError.unavailableImage }
        let request = VNGenerateImageFeaturePrintRequest()
        request.revision = VNGenerateImageFeaturePrintRequestRevision2
        request.imageCropAndScaleOption = .scaleFit
        request.preferBackgroundProcessing = true
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        try Task.checkCancellation()
        guard let observation = request.results?.first else { throw ImageSimilarityError.noFeaturePrint }
        guard try stamp(at: url) == before else { throw ImageSimilarityError.changedDuringAnalysis }
        var writeFailed = false
        do {
            let archive = try NSKeyedArchiver.archivedData(withRootObject: observation, requiringSecureCoding: true)
            let entry = CachedPrint(version: modelVersion, stamp: before, observation: archive)
            try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            try JSONEncoder().encode(entry).write(to: cacheURL, options: .atomic)
        } catch { writeFailed = true }
        return (observation, false, writeFailed)
    }
}
