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

        guard imageFormat != nil || isVideoFile else { return nil }

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

    /// 지원하는 모든 미디어 확장자 (이미지 + 영상)
    static let allSupportedExtensions: Set<String> = {
        ImageFormat.supportedExtensions.union(videoExtensions)
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
