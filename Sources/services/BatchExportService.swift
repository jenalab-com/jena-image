import AppKit
import ImageIO
import UniformTypeIdentifiers

/// 일괄 내보내기 옵션. 리사이즈는 "긴 변 기준·축소만" 규칙 하나뿐이라 장마다 결과 크기가 달라지는 게 정상이다.
struct BatchExportOptions {
    var format: ImageFormat
    /// 1~100. 무손실 포맷에선 무시.
    var quality: Float
    /// nil이면 리사이즈 없음. 값이 있으면 긴 변이 이보다 큰 이미지만 그 길이로 줄인다(작은 이미지는 그대로).
    var maxLongEdge: Int?
    var destination: URL
}

struct BatchExportReport {
    var succeeded: [URL] = []
    var failed: [(source: URL, reason: String)] = []
    var cancelled = false
}

/// 여러 이미지를 같은 규칙으로 변환·저장한다. ImageIO로 바로 디코딩해 EXIF 방향을 적용하고,
/// 축소가 필요하면 디코딩 단계에서 줄여 원본 전체를 메모리에 올리지 않는다.
final class BatchExportService {

    /// 순서대로 처리하며 장마다 progress(완료 수, 현재 파일)를 호출한다. `isCancelled`가 true를 돌려주면 멈춘다.
    func export(_ sources: [URL], options: BatchExportOptions,
                isCancelled: @escaping () -> Bool,
                progress: @escaping @MainActor (Int, URL) -> Void) async -> BatchExportReport {
        await Task.detached(priority: .userInitiated) { [self] in
            var report = BatchExportReport()
            for (index, source) in sources.enumerated() {
                if isCancelled() { report.cancelled = true; break }
                await progress(index, source)
                switch exportOne(source, options: options) {
                case .success(let url): report.succeeded.append(url)
                case .failure(let error): report.failed.append((source, error.localizedDescription))
                }
            }
            return report
        }.value
    }

    /// 결과 파일명: 원본 이름 + 새 확장자. 겹치면 " 2", " 3"…을 붙인다(원본 자리에 같은 포맷으로 내보내도 덮어쓰지 않음).
    static func outputURL(for source: URL, format: ImageFormat, in folder: URL) -> URL {
        let base = source.deletingPathExtension().lastPathComponent
        let ext = format.fileExtensions[0]
        var candidate = folder.appendingPathComponent("\(base).\(ext)")
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(base) \(counter).\(ext)")
            counter += 1
        }
        return candidate
    }

    private func exportOne(_ source: URL, options: BatchExportOptions) -> Result<URL, ImageServiceError> {
        guard let cgImage = decode(source, maxLongEdge: options.maxLongEdge) else {
            return .failure(.loadFailed(source))
        }
        let output = Self.outputURL(for: source, format: options.format, in: options.destination)
        guard let destination = CGImageDestinationCreateWithURL(
            output as CFURL, options.format.utType.identifier as CFString, 1, nil
        ) else {
            return .failure(.exportFailed("대상 파일을 생성할 수 없습니다"))
        }
        var properties: [CFString: Any] = [:]
        if options.format.isLossy {
            properties[kCGImageDestinationLossyCompressionQuality] = options.quality / 100.0
        }
        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            return .failure(.exportFailed("이미지 변환에 실패했습니다"))
        }
        return .success(output)
    }

    /// EXIF 방향이 적용된 CGImage. 긴 변 상한이 있고 원본이 그보다 크면 그 길이로 줄여 디코딩한다.
    private func decode(_ source: URL, maxLongEdge: Int?) -> CGImage? {
        if let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
           CGImageSourceGetCount(imageSource) > 0 {
            let props = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any]
            let width = props?[kCGImagePropertyPixelWidth] as? Int ?? 0
            let height = props?[kCGImagePropertyPixelHeight] as? Int ?? 0
            let longEdge = max(width, height)
            var target = longEdge
            if let limit = maxLongEdge, limit > 0, longEdge > limit { target = limit }
            if target > 0 {
                // Thumbnail API는 방향 보정(WithTransform)과 축소를 한 번에 해 준다. 상한을 원본 크기로 주면 전체 해상도.
                let thumbOptions: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: target,
                    kCGImageSourceShouldCache: false,
                ]
                if let image = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, thumbOptions as CFDictionary) {
                    return image
                }
            }
        }
        // SVG·AI·EPS 등 ImageIO가 못 여는 형식은 NSImage로 렌더링한 뒤 필요하면 줄인다.
        guard let nsImage = NSImage(contentsOf: source), nsImage.isValid,
              let full = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let longEdge = max(full.width, full.height)
        guard let limit = maxLongEdge, limit > 0, longEdge > limit else { return full }
        let scale = CGFloat(limit) / CGFloat(longEdge)
        let size = CGSize(width: max(1, (CGFloat(full.width) * scale).rounded()),
                          height: max(1, (CGFloat(full.height) * scale).rounded()))
        guard let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height),
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(full, in: CGRect(origin: .zero, size: size))
        return context.makeImage()
    }
}
