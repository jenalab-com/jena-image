import AppKit
import ImageIO
import UniformTypeIdentifiers

/// 이미지 정보 패널에 표시할 메타데이터.
struct ImageMetadata: Sendable {
    struct Field: Sendable {
        let label: String
        let value: String
    }

    let fileURL: URL
    let fileName: String
    let kind: String
    let fileSize: Int64?
    let createdAt: Date?
    let modifiedAt: Date?
    let format: String
    let pixelWidth: Int?
    let pixelHeight: Int?
    let dpi: String?
    let colorModel: String?
    let colorProfile: String?
    let exif: [Field]
    let gps: [Field]

    var dimension: String? {
        guard let pixelWidth, let pixelHeight else { return nil }
        return "\(pixelWidth) × \(pixelHeight) px"
    }
}

/// 파일 기본 정보 + ImageIO 기반 이미지/EXIF 메타데이터 조회.
enum ImageMetadataService {
    static func load(for url: URL) -> ImageMetadata {
        let values = try? url.resourceValues(forKeys: [
            .fileSizeKey,
            .creationDateKey,
            .contentModificationDateKey,
        ])

        let imageFile = ImageFile(url: url)
        let isVideo = imageFile?.isVideo ?? false
        let isPreviewOnly = imageFile?.isPreviewOnly ?? false
        let kind = isVideo ? "동영상" : (isPreviewOnly ? "미리보기 문서" : "이미지")

        var pixelWidth: Int?
        var pixelHeight: Int?
        var dpi: String?
        var colorModel: String?
        var colorProfile: String?
        var exif: [ImageMetadata.Field] = []
        var gps: [ImageMetadata.Field] = []

        if !isVideo,
           let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            pixelWidth = intValue(properties[kCGImagePropertyPixelWidth])
            pixelHeight = intValue(properties[kCGImagePropertyPixelHeight])
            dpi = dpiDescription(
                width: doubleValue(properties[kCGImagePropertyDPIWidth]),
                height: doubleValue(properties[kCGImagePropertyDPIHeight])
            )
            colorModel = (properties[kCGImagePropertyColorModel] as? String).map(colorModelName)
            colorProfile = properties[kCGImagePropertyProfileName] as? String

            let exifDictionary = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
            let tiffDictionary = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
            exif = exifFields(exif: exifDictionary, tiff: tiffDictionary)
            gps = gpsFields(properties[kCGImagePropertyGPSDictionary] as? [CFString: Any])
        }

        return ImageMetadata(
            fileURL: url,
            fileName: url.lastPathComponent,
            kind: kind,
            fileSize: values?.fileSize.map(Int64.init),
            createdAt: values?.creationDate,
            modifiedAt: values?.contentModificationDate,
            format: formatDescription(for: url),
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            dpi: dpi,
            colorModel: colorModel,
            colorProfile: colorProfile,
            exif: exif,
            gps: gps
        )
    }

    // MARK: - Fields

    private static func exifFields(exif: [CFString: Any]?, tiff: [CFString: Any]?) -> [ImageMetadata.Field] {
        var fields: [ImageMetadata.Field] = []

        func append(_ label: String, _ value: String?) {
            guard let value, !value.isEmpty else { return }
            fields.append(ImageMetadata.Field(label: label, value: value))
        }

        append("카메라 제조사", tiff?[kCGImagePropertyTIFFMake] as? String)
        append("카메라 모델", tiff?[kCGImagePropertyTIFFModel] as? String)

        if let lensModel = exif?[kCGImagePropertyExifLensModel] as? String {
            append("렌즈", lensModel)
        } else if let lensMake = exif?[kCGImagePropertyExifLensMake] as? String {
            append("렌즈", lensMake)
        }

        if let iso = intValue(exif?[kCGImagePropertyExifISOSpeedRatings]) {
            append("ISO", "\(iso)")
        }
        if let exposure = doubleValue(exif?[kCGImagePropertyExifExposureTime]) {
            append("셔터 속도", exposureDescription(exposure))
        }
        if let fNumber = doubleValue(exif?[kCGImagePropertyExifFNumber]) {
            append("조리개", String(format: "f/%.1f", fNumber))
        }
        if let focal = doubleValue(exif?[kCGImagePropertyExifFocalLength]) {
            var text = String(format: "%.0f mm", focal)
            if let equivalent = intValue(exif?[kCGImagePropertyExifFocalLenIn35mmFilm]) {
                text += " (35mm 환산 \(equivalent) mm)"
            }
            append("초점 거리", text)
        }
        if let dateText = exif?[kCGImagePropertyExifDateTimeOriginal] as? String {
            append("촬영일", formattedExifDate(dateText))
        }

        return fields
    }

    private static func gpsFields(_ gps: [CFString: Any]?) -> [ImageMetadata.Field] {
        guard let gps else { return [] }
        var fields: [ImageMetadata.Field] = []

        if let latitude = doubleValue(gps[kCGImagePropertyGPSLatitude]),
           let longitude = doubleValue(gps[kCGImagePropertyGPSLongitude]) {
            let latRef = (gps[kCGImagePropertyGPSLatitudeRef] as? String)?.uppercased() ?? "N"
            let lonRef = (gps[kCGImagePropertyGPSLongitudeRef] as? String)?.uppercased() ?? "E"
            let signedLat = latRef == "S" ? -latitude : latitude
            let signedLon = lonRef == "W" ? -longitude : longitude
            fields.append(ImageMetadata.Field(
                label: "좌표",
                value: String(format: "%.6f, %.6f", signedLat, signedLon)
            ))
        }

        if let altitude = doubleValue(gps[kCGImagePropertyGPSAltitude]) {
            let belowSeaLevel = intValue(gps[kCGImagePropertyGPSAltitudeRef]) == 1
            fields.append(ImageMetadata.Field(
                label: "고도",
                value: String(format: "%.0f m%@", altitude, belowSeaLevel ? " (해수면 아래)" : "")
            ))
        }

        return fields
    }

    // MARK: - Formatting

    private static func formatDescription(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        if let imageFormat = ImageFormat.from(extension: ext) {
            return imageFormat.displayName
        }
        // 미리보기 전용·동영상은 앱이 아는 짧은 이름을 그대로 쓴다.
        let knownExtensions: Set<String> = ["psd", "ai", "svg", "eps", "mp4", "mov", "m4v", "avi", "mkv"]
        if knownExtensions.contains(ext) {
            return ext.uppercased()
        }
        if let type = UTType(filenameExtension: ext),
           let description = type.localizedDescription, !description.isEmpty {
            return description
        }
        return ext.isEmpty ? "알 수 없음" : ext.uppercased()
    }

    private static func colorModelName(_ raw: String) -> String {
        switch raw {
        case "RGB": return "RGB"
        case "Gray": return "회색조 (Gray)"
        case "CMYK": return "CMYK"
        case "Lab": return "Lab"
        default: return raw
        }
    }

    private static func dpiDescription(width: Double?, height: Double?) -> String? {
        guard let width else { return nil }
        if let height, abs(width - height) >= 0.5 {
            return "\(Int(width.rounded())) × \(Int(height.rounded())) dpi"
        }
        return "\(Int(width.rounded())) dpi"
    }

    private static func exposureDescription(_ seconds: Double) -> String {
        guard seconds > 0 else { return "0초" }
        if seconds < 1 {
            return "1/\(Int((1 / seconds).rounded()))초"
        }
        return String(format: "%.1f초", seconds)
    }

    private static func formattedExifDate(_ text: String) -> String {
        let parser = DateFormatter()
        parser.dateFormat = "yyyy:MM:dd HH:mm:ss"
        guard let date = parser.date(from: text) else { return text }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private static func intValue(_ value: Any?) -> Int? {
        switch value {
        case let number as NSNumber: return number.intValue
        case let array as [NSNumber]: return array.first?.intValue
        case let array as [Any]: return (array.first as? NSNumber)?.intValue
        default: return nil
        }
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber: return number.doubleValue
        case let array as [NSNumber]: return array.first?.doubleValue
        case let array as [Any]: return (array.first as? NSNumber)?.doubleValue
        default: return nil
        }
    }
}
