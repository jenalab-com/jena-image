import Foundation

/// 폴더 트리 노드 — 사이드바 NSOutlineView의 데이터 소스 항목
final class FolderNode {
    let url: URL
    let name: String
    let isTemporary: Bool
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

    init(url: URL, isTemporary: Bool = false) {
        self.url = url
        self.name = url.lastPathComponent
        self.isTemporary = isTemporary
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

    /// 디스크를 다시 읽어 자식 목록을 갱신한다.
    ///
    /// 단순 `invalidateChildren()` + `loadChildren()`과 달리, URL이 그대로인 하위 폴더는
    /// **기존 노드 인스턴스를 재사용**한다. NSOutlineView는 아이템을 객체 동일성으로 추적하므로
    /// 이렇게 해야 새로고침 후에도 펼쳐둔 하위 폴더가 접히지 않는다.
    ///
    /// - Parameter recursive: true면 이미 로드된(= 펼쳐본 적 있는) 하위 폴더까지 함께 갱신한다.
    ///   로드되지 않은 폴더는 건드리지 않으므로 트리 전체를 훑는 비용은 발생하지 않는다.
    func refresh(recursive: Bool = true, using fileManager: FileManager = .default) {
        let previous = children ?? []
        // 사용자가 이름 입력 중인 임시 노드는 디스크에 없으므로 갱신 후 되살려 준다.
        let temporaryNodes = previous.filter { $0.isTemporary }
        var reusable: [URL: FolderNode] = [:]
        for child in previous where !child.isTemporary {
            reusable[child.url] = child
        }

        invalidateChildren()
        loadChildren(using: fileManager)

        children = (children ?? []).map { fresh -> FolderNode in
            guard let existing = reusable[fresh.url] else { return fresh }
            if recursive && existing.isLoaded {
                existing.refresh(recursive: true, using: fileManager)
            }
            return existing
        }
        children?.insert(contentsOf: temporaryNodes, at: 0)
    }

    /// 임시 자식 노드 추가 (새 폴더 생성 UI용)
    func insertTemporaryChild(_ node: FolderNode) {
        loadChildren()
        children?.insert(node, at: 0)
    }

    /// 임시 자식 노드 제거
    func removeTemporaryChild() {
        children?.removeAll { $0.isTemporary }
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
