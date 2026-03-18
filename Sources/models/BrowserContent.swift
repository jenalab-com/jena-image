import Foundation

/// 브라우저 그리드에 표시되는 항목 (폴더 또는 이미지)
enum BrowserContent {
    case folder(FolderNode)
    case image(ImageFile)

    var url: URL {
        switch self {
        case .folder(let node): return node.url
        case .image(let file):  return file.url
        }
    }

    var name: String {
        switch self {
        case .folder(let node): return node.name
        case .image(let file):  return file.name
        }
    }

    var isFolder: Bool {
        if case .folder = self { return true }
        return false
    }

    var isImage: Bool {
        if case .image = self { return true }
        return false
    }
}
