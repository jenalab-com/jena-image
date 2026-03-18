import UniformTypeIdentifiers

/// 지원하는 이미지 포맷 정의
enum ImageFormat: String, CaseIterable {
    case jpeg
    case png
    case gif
    case bmp
    case tiff
    case webp
    case heic
    case heif
    case avif

    var displayName: String {
        switch self {
        case .jpeg: return "JPEG"
        case .png:  return "PNG"
        case .gif:  return "GIF"
        case .bmp:  return "BMP"
        case .tiff: return "TIFF"
        case .webp: return "WebP"
        case .heic: return "HEIC"
        case .heif: return "HEIF"
        case .avif: return "AVIF"
        }
    }

    var utType: UTType {
        switch self {
        case .jpeg: return .jpeg
        case .png:  return .png
        case .gif:  return .gif
        case .bmp:  return .bmp
        case .tiff: return .tiff
        case .webp: return .webP
        case .heic: return .heic
        case .heif: return UTType("public.heif") ?? .heic
        case .avif: return UTType("public.avif") ?? .heic
        }
    }

    var fileExtensions: [String] {
        switch self {
        case .jpeg: return ["jpg", "jpeg"]
        case .png:  return ["png"]
        case .gif:  return ["gif"]
        case .bmp:  return ["bmp"]
        case .tiff: return ["tiff", "tif"]
        case .webp: return ["webp"]
        case .heic: return ["heic"]
        case .heif: return ["heif"]
        case .avif: return ["avif"]
        }
    }

    /// 손실 압축 포맷 여부 (품질 슬라이더 표시 판단용)
    var isLossy: Bool {
        switch self {
        case .jpeg, .webp, .heic, .heif, .avif:
            return true
        case .png, .gif, .bmp, .tiff:
            return false
        }
    }

    /// 파일 확장자로 포맷 판별
    static func from(extension ext: String) -> ImageFormat? {
        let lowered = ext.lowercased()
        return allCases.first { $0.fileExtensions.contains(lowered) }
    }

    /// 지원하는 모든 확장자 집합
    static let supportedExtensions: Set<String> = {
        Set(allCases.flatMap { $0.fileExtensions })
    }()
}
