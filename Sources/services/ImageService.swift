import AppKit
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Error

enum ImageServiceError: Error, LocalizedError {
    case loadFailed(URL)
    case thumbnailFailed(URL)
    case exportFailed(String)
    case unsupportedFormat(String)

    var errorDescription: String? {
        switch self {
        case .loadFailed(let url):
            return "이미지를 표시할 수 없습니다: \(url.lastPathComponent)"
        case .thumbnailFailed(let url):
            return "썸네일을 생성할 수 없습니다: \(url.lastPathComponent)"
        case .exportFailed(let reason):
            return "파일을 저장할 수 없습니다: \(reason)"
        case .unsupportedFormat(let ext):
            return "지원하지 않는 포맷입니다: \(ext)"
        }
    }
}

// MARK: - Protocol

protocol ImageServiceProtocol {
    func loadImage(at url: URL) async -> Result<NSImage, ImageServiceError>
    func generateThumbnail(at url: URL, size: CGSize) async -> Result<NSImage, ImageServiceError>
    func exportImage(_ image: NSImage, to url: URL, format: ImageFormat, quality: Float) -> Result<Void, ImageServiceError>
}

// MARK: - Implementation

final class ImageService: ImageServiceProtocol {

    /// NSImage 폴백이 필요한 확장자 (SVG, AI, EPS 등 CGImageSource 미지원)
    private static let nsImageFallbackExtensions: Set<String> = ["svg", "ai", "eps"]

    func loadImage(at url: URL) async -> Result<NSImage, ImageServiceError> {
        let ext = url.pathExtension.lowercased()

        // SVG, AI, EPS: NSImage로 직접 로드 (PDF 기반 벡터 렌더링)
        if Self.nsImageFallbackExtensions.contains(ext) {
            return loadWithNSImage(at: url)
        }

        // PSD 및 기타 래스터: CGImageSource (EXIF orientation 적용)
        if let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
           let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) {
            let orientedImage = applyEXIFOrientation(cgImage: cgImage, source: imageSource)
            return .success(orientedImage)
        }

        // CGImageSource 실패 시 NSImage 폴백
        return loadWithNSImage(at: url)
    }

    /// EXIF orientation 메타데이터를 적용하여 올바른 방향의 NSImage 반환
    private func applyEXIFOrientation(cgImage: CGImage, source: CGImageSource) -> NSImage {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let orientationValue = properties?[kCGImagePropertyOrientation] as? UInt32 ?? 1

        guard let orientation = CGImagePropertyOrientation(rawValue: orientationValue),
              orientation != .up else {
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        }

        let ciImage = CIImage(cgImage: cgImage).oriented(forExifOrientation: Int32(orientationValue))
        let rep = NSCIImageRep(ciImage: ciImage)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }

    private func loadWithNSImage(at url: URL) -> Result<NSImage, ImageServiceError> {
        guard let image = NSImage(contentsOf: url), image.isValid else {
            return .failure(.loadFailed(url))
        }
        // 벡터 이미지를 고해상도 비트맵으로 변환
        let size = image.size
        guard size.width > 0, size.height > 0 else {
            return .failure(.loadFailed(url))
        }
        return .success(image)
    }

    func generateThumbnail(at url: URL, size: CGSize) async -> Result<NSImage, ImageServiceError> {
        let ext = url.pathExtension.lowercased()

        // 영상 파일은 AVAssetImageGenerator 사용
        if ImageFile.videoExtensions.contains(ext) {
            return await generateVideoThumbnail(at: url, size: size)
        }

        // SVG, AI, EPS: NSImage로 로드 후 리사이즈
        if Self.nsImageFallbackExtensions.contains(ext) {
            return generateNSImageThumbnail(at: url, size: size)
        }

        let maxDimension = max(size.width, size.height) * 2  // Retina 대응

        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]

        // CGImageSource 시도, 실패 시 NSImage 폴백 (PSD 일부 버전 등)
        if let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
           let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) {
            let pixelWidth = CGFloat(cgImage.width)
            let pixelHeight = CGFloat(cgImage.height)
            let thumbnail = NSImage(cgImage: cgImage, size: NSSize(width: pixelWidth, height: pixelHeight))
            return .success(thumbnail)
        }

        return generateNSImageThumbnail(at: url, size: size)
    }

    private func generateNSImageThumbnail(at url: URL, size: CGSize) -> Result<NSImage, ImageServiceError> {
        guard let image = NSImage(contentsOf: url), image.isValid else {
            return .failure(.thumbnailFailed(url))
        }
        let imgSize = image.size
        guard imgSize.width > 0, imgSize.height > 0 else {
            return .failure(.thumbnailFailed(url))
        }
        let maxDim = max(size.width, size.height) * 2
        let scale = min(maxDim / imgSize.width, maxDim / imgSize.height, 1.0)
        let thumbSize = NSSize(width: imgSize.width * scale, height: imgSize.height * scale)
        let thumbnail = NSImage(size: thumbSize)
        thumbnail.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: thumbSize),
                   from: NSRect(origin: .zero, size: imgSize),
                   operation: .copy, fraction: 1.0)
        thumbnail.unlockFocus()
        return .success(thumbnail)
    }

    private func generateVideoThumbnail(at url: URL, size: CGSize) async -> Result<NSImage, ImageServiceError> {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: size.width * 2, height: size.height * 2)

        let time = CMTime(seconds: 1, preferredTimescale: 600)
        do {
            let (cgImage, _) = try await generator.image(at: time)
            let thumbnail = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            return .success(thumbnail)
        } catch {
            return .failure(.thumbnailFailed(url))
        }
    }

    func exportImage(_ image: NSImage, to url: URL, format: ImageFormat, quality: Float) -> Result<Void, ImageServiceError> {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return .failure(.exportFailed("이미지 데이터를 읽을 수 없습니다"))
        }

        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            format.utType.identifier as CFString,
            1,
            nil
        ) else {
            return .failure(.exportFailed("대상 파일을 생성할 수 없습니다"))
        }

        var properties: [CFString: Any] = [:]
        if format.isLossy {
            properties[kCGImageDestinationLossyCompressionQuality] = quality / 100.0
        }

        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            return .failure(.exportFailed("이미지 변환에 실패했습니다"))
        }

        return .success(())
    }
}
