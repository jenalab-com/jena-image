import Foundation

extension Notification.Name {
    /// 북마크 목록이 바뀌면 발행(사이드바·그리드·뷰어 버튼 갱신용).
    static let bookmarksChanged = Notification.Name("bookmarksChanged")
}

/// 이미지 북마크(즐겨찾기) 영속 저장소. 파일 경로만 저장(비샌드박스).
/// 최근 추가가 앞(index 0).
final class BookmarkStore {
    private let defaults = UserDefaults.standard
    private let key = "imageBookmarks"

    private(set) var bookmarks: [URL] {
        get {
            let paths = defaults.stringArray(forKey: key) ?? []
            return paths.map { URL(fileURLWithPath: $0) }
        }
        set {
            defaults.set(newValue.map { $0.path }, forKey: key)
        }
    }

    /// 같은 파일이 이미 있으면 무시. 새 항목을 맨 앞에 추가.
    func add(_ url: URL) {
        let std = url.standardizedFileURL
        guard !contains(std) else { return }
        bookmarks = [std] + bookmarks
        NotificationCenter.default.post(name: .bookmarksChanged, object: nil)
    }

    /// 목록에서만 제거(파일은 그대로).
    func remove(_ url: URL) {
        let std = url.standardizedFileURL
        let next = bookmarks.filter { $0.standardizedFileURL != std }
        guard next.count != bookmarks.count else { return }
        bookmarks = next
        NotificationCenter.default.post(name: .bookmarksChanged, object: nil)
    }

    func contains(_ url: URL) -> Bool {
        let std = url.standardizedFileURL
        return bookmarks.contains { $0.standardizedFileURL == std }
    }

    /// 이름변경/이동 시 경로 교체(순서 유지). 없으면 무시.
    func rename(from oldURL: URL, to newURL: URL) {
        let oldStd = oldURL.standardizedFileURL
        guard let idx = bookmarks.firstIndex(where: { $0.standardizedFileURL == oldStd }) else { return }
        var next = bookmarks
        next[idx] = newURL.standardizedFileURL
        bookmarks = next
        NotificationCenter.default.post(name: .bookmarksChanged, object: nil)
    }
}
