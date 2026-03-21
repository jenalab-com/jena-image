import Foundation

/// 미디어 파일 모델 (이미지 + 영상)
struct ImageFile {
    let url: URL
    let name: String
    let fileExtension: String
    let format: ImageFormat?
    let isVideo: Bool

    init?(url: URL) {
        let ext = url.pathExtension.lowercased()
        let imageFormat = ImageFormat.from(extension: ext)
        let isVideoFile = Self.videoExtensions.contains(ext)

        let isPreviewOnly = Self.previewOnlyExtensions.contains(ext)
        guard imageFormat != nil || isVideoFile || isPreviewOnly else { return nil }

        self.url = url
        self.name = url.lastPathComponent
        self.fileExtension = ext
        self.format = imageFormat
        self.isVideo = isVideoFile
    }

    var isImage: Bool { !isVideo }

    /// 확장자를 제외한 파일 이름
    var nameWithoutExtension: String {
        url.deletingPathExtension().lastPathComponent
    }

    /// 지원하는 영상 확장자
    static let videoExtensions: Set<String> = ["mp4", "mov", "m4v", "avi", "mkv"]

    /// 미리보기 전용 확장자 (내보내기 불가, 뷰어에서만 표시)
    static let previewOnlyExtensions: Set<String> = ["psd", "ai", "svg", "eps"]

    /// 미리보기 전용 파일 여부
    var isPreviewOnly: Bool {
        Self.previewOnlyExtensions.contains(fileExtension)
    }

    /// 지원하는 모든 미디어 확장자 (이미지 + 영상 + 미리보기 전용)
    static let allSupportedExtensions: Set<String> = {
        ImageFormat.supportedExtensions.union(videoExtensions).union(previewOnlyExtensions)
    }()
}

extension ImageFile: Equatable {
    static func == (lhs: ImageFile, rhs: ImageFile) -> Bool {
        lhs.url == rhs.url
    }
}

extension ImageFile: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }
}
