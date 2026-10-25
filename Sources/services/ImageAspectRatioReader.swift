import Foundation
import ImageIO

enum ImageAspectRatioReader {
    /// 원본 디코딩 없이 크기와 EXIF 방향만 읽는다. iCloud 미다운로드 파일은 열지 않는다.
    static func aspectRatio(at url: URL) -> CGFloat? {
        guard !ThumbnailProvider.isEvictedICloudItem(url),
              !ImageFile.videoExtensions.contains(url.pathExtension.lowercased()) else { return nil }
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, options) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
              width.doubleValue > 0, height.doubleValue > 0 else { return nil }
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        let rotated = (5...8).contains(orientation)
        let ratio = rotated ? height.doubleValue / width.doubleValue : width.doubleValue / height.doubleValue
        return ratio.isFinite && ratio > 0 ? CGFloat(ratio) : nil
    }
}
