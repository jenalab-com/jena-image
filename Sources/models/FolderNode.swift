import Foundation

/// 폴더 트리 노드 — 사이드바 NSOutlineView의 데이터 소스 항목
final class FolderNode {
    let url: URL
    let name: String
    private(set) var children: [FolderNode]?
    private(set) var imageFiles: [ImageFile]?
    private(set) var isLoaded: Bool = false

    /// 전체 자식 수 (폴더 + 이미지)
    var totalChildCount: Int {
        (children?.count ?? 0) + (imageFiles?.count ?? 0)
    }

    /// 폴더만 자식 수
    var folderChildCount: Int {
        children?.count ?? 0
    }

    init(url: URL) {
        self.url = url
        self.name = url.lastPathComponent
    }

    /// 하위 폴더 + 이미지 로드 (지연 로딩 — 펼침 시점에 호출)
    func loadChildren(using fileManager: FileManager = .default) {
        guard !isLoaded else { return }

        let options: FileManager.DirectoryEnumerationOptions = [
            .skipsHiddenFiles,
            .skipsPackageDescendants,
        ]

        guard let contents = try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: options
        ) else {
            children = []
            imageFiles = []
            isLoaded = true
            return
        }

        var folders: [URL] = []
        var media: [URL] = []

        for item in contents {
            let isDirectory = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            if isDirectory {
                folders.append(item)
            } else if ImageFile.allSupportedExtensions.contains(item.pathExtension.lowercased()) {
                media.append(item)
            }
        }

        children = folders
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .map { FolderNode(url: $0) }

        imageFiles = media
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .compactMap { ImageFile(url: $0) }

        isLoaded = true
    }

    /// 해당 폴더 안 미디어 파일 수 (폴더 로드 후 사용)
    var mediaFileCount: Int {
        imageFiles?.count ?? 0
    }

    /// 하위 항목 존재 여부 (disclosure triangle 표시 판단용)
    var hasChildren: Bool {
        if isLoaded {
            return totalChildCount > 0
        }
        // 아직 로드 전이면 true로 가정 (펼침 시 실제 로드)
        return true
    }

    /// 인덱스로 자식 항목 반환 (폴더 먼저, 이미지 뒤)
    func child(at index: Int, includeFiles: Bool = true) -> Any? {
        let folderCount = children?.count ?? 0
        if index < folderCount {
            return children?[index]
        }
        guard includeFiles else { return nil }
        let imageIndex = index - folderCount
        return imageFiles?[safe: imageIndex]
    }

    /// 자식 목록 초기화 (폴더 내용 변경 시 갱신용)
    func invalidateChildren() {
        children = nil
        imageFiles = nil
        isLoaded = false
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

extension FolderNode: Equatable {
    static func == (lhs: FolderNode, rhs: FolderNode) -> Bool {
        lhs.url == rhs.url
    }
}

extension FolderNode: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }
}
