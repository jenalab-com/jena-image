import Foundation

extension Notification.Name {
    static let categoriesChanged = Notification.Name("categoriesChanged")
}

enum CategoryStoreError: LocalizedError {
    case emptyName, duplicateName, missingCategory, unreadableData

    var errorDescription: String? {
        switch self {
        case .emptyName: return "카테고리 이름을 입력하세요."
        case .duplicateName: return "같은 이름의 카테고리가 있습니다."
        case .missingCategory: return "카테고리를 찾을 수 없습니다."
        case .unreadableData: return "카테고리 데이터를 읽을 수 없습니다. 기존 데이터는 그대로 보존됩니다."
        }
    }
}

/// 북마크와 독립적인 다중 카테고리 저장소. 모든 변경은 읽기에 성공한 경우에만 저장한다.
final class CategoryStore {
    static let storageKey = "imageCategories.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func categories() throws -> [ImageCategory] {
        guard defaults.object(forKey: Self.storageKey) != nil else { return [] }
        guard let data = defaults.data(forKey: Self.storageKey),
              let categories = try? JSONDecoder().decode([ImageCategory].self, from: data) else {
            throw CategoryStoreError.unreadableData
        }
        return categories
    }

    @discardableResult
    func create(name: String, urls: [URL] = []) throws -> ImageCategory {
        var categories = try categories()
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CategoryStoreError.emptyName }
        guard !categories.contains(where: { $0.name.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }) else {
            throw CategoryStoreError.duplicateName
        }
        let category = ImageCategory(id: UUID(), name: trimmed, paths: uniquePaths(urls))
        categories.append(category)
        try save(categories)
        return category
    }

    func rename(categoryID: UUID, name: String) throws {
        var categories = try categories()
        guard let index = categories.firstIndex(where: { $0.id == categoryID }) else {
            throw CategoryStoreError.missingCategory
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CategoryStoreError.emptyName }
        guard !categories.contains(where: {
            $0.id != categoryID && $0.name.localizedCaseInsensitiveCompare(trimmed) == .orderedSame
        }) else { throw CategoryStoreError.duplicateName }
        guard categories[index].name != trimmed else { return }
        categories[index].name = trimmed
        try save(categories)
    }

    func setMembership(_ urls: [URL], categoryID: UUID, included: Bool) throws {
        var categories = try categories()
        guard let index = categories.firstIndex(where: { $0.id == categoryID }) else {
            throw CategoryStoreError.missingCategory
        }
        let paths = uniquePaths(urls)
        let previous = categories[index].paths
        if included {
            let existing = Set(previous)
            categories[index].paths += paths.filter { !existing.contains($0) }
        } else {
            let removed = Set(paths)
            categories[index].paths.removeAll { removed.contains($0) }
        }
        guard previous != categories[index].paths else { return }
        try save(categories)
    }

    /// 앱 안에서 파일/폴더 이름변경·이동 시 하위 이미지 경로도 함께 갱신한다.
    func relocate(from oldURL: URL, to newURL: URL) throws {
        let oldPath = oldURL.standardizedFileURL.path
        let newPath = newURL.standardizedFileURL.path
        let previous = try categories()
        var updated = previous
        for index in updated.indices {
            let urls = updated[index].paths.map { path -> URL in
                let relocated: String
                if path == oldPath { relocated = newPath }
                else if path.hasPrefix(oldPath + "/") { relocated = newPath + path.dropFirst(oldPath.count) }
                else { relocated = path }
                return URL(fileURLWithPath: relocated)
            }
            updated[index].paths = uniquePaths(urls)
        }
        if updated != previous { try save(updated) }
    }

    /// 사용자가 앱에서 원본을 휴지통으로 보낸 경우에만 분류에서도 제거한다.
    func removeDeletedFile(at url: URL) throws {
        let path = url.standardizedFileURL.path
        let previous = try categories()
        var updated = previous
        for index in updated.indices {
            updated[index].paths.removeAll { $0 == path || $0.hasPrefix(path + "/") }
        }
        if updated != previous { try save(updated) }
    }

    private func uniquePaths(_ urls: [URL]) -> [String] {
        var seen = Set<String>()
        return urls.map { $0.standardizedFileURL.path }.filter { seen.insert($0).inserted }
    }

    private func save(_ categories: [ImageCategory]) throws {
        let data = try JSONEncoder().encode(categories)
        defaults.set(data, forKey: Self.storageKey)
        NotificationCenter.default.post(name: .categoriesChanged, object: self)
    }
}
