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

    func loadImage(at url: URL) async -> Result<NSImage, ImageServiceError> {
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            return .failure(.loadFailed(url))
        }

        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        return .success(image)
    }

    func generateThumbnail(at url: URL, size: CGSize) async -> Result<NSImage, ImageServiceError> {
        // 영상 파일은 AVAssetImageGenerator 사용
        if ImageFile.videoExtensions.contains(url.pathExtension.lowercased()) {
            return await generateVideoThumbnail(at: url, size: size)
        }

        let maxDimension = max(size.width, size.height) * 2  // Retina 대응

        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]

        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
            return .failure(.thumbnailFailed(url))
        }

        let pixelWidth = CGFloat(cgImage.width)
        let pixelHeight = CGFloat(cgImage.height)
        let thumbnail = NSImage(cgImage: cgImage, size: NSSize(width: pixelWidth, height: pixelHeight))
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
