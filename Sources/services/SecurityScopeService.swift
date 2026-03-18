import AppKit
import Foundation

/// 앱 샌드박스 환경에서 Security-Scoped Bookmark 관리
final class SecurityScopeService {
    private static let bookmarksKey = "folderBookmarks"
    private var accessingURLs: Set<URL> = []

    /// NSOpenPanel로 폴더 선택 요청
    func requestFolderAccess() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "사이드바에 추가할 폴더를 선택하세요"
        panel.prompt = "추가"

        guard panel.runModal() == .OK, let url = panel.url else {
            return nil
        }

        addBookmark(for: url)
        return url
    }

    /// 북마크 추가
    func addBookmark(for url: URL) {
        guard let bookmarkData = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else { return }

        var bookmarks = loadBookmarkDataArray()
        // 중복 방지: 같은 URL의 기존 북마크 제거
        let resolvedPath = url.standardizedFileURL.path
        bookmarks.removeAll { data in
            var isStale = false
            guard let existing = try? URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else { return true }
            return existing.standardizedFileURL.path == resolvedPath
        }
        bookmarks.append(bookmarkData)
        UserDefaults.standard.set(bookmarks, forKey: Self.bookmarksKey)
    }

    /// 북마크 제거
    func removeBookmark(for url: URL) {
        var bookmarks = loadBookmarkDataArray()
        let targetPath = url.standardizedFileURL.path
        bookmarks.removeAll { data in
            var isStale = false
            guard let existing = try? URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else { return true }
            return existing.standardizedFileURL.path == targetPath
        }
        UserDefaults.standard.set(bookmarks, forKey: Self.bookmarksKey)
    }

    /// 저장된 모든 북마크에서 URL 복원
    func restoreBookmarks() -> [URL] {
        let bookmarks = loadBookmarkDataArray()
        var urls: [URL] = []
        var updatedBookmarks: [Data] = []

        for data in bookmarks {
            var isStale = false
            guard let url = try? URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else { continue }

            if isStale {
                if let refreshed = try? url.bookmarkData(
                    options: .withSecurityScope,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                ) {
                    updatedBookmarks.append(refreshed)
                }
            } else {
                updatedBookmarks.append(data)
            }
            urls.append(url)
        }

        UserDefaults.standard.set(updatedBookmarks, forKey: Self.bookmarksKey)
        return urls
    }

    /// 보안 스코프 접근 시작
    @discardableResult
    func startAccessing(_ url: URL) -> Bool {
        guard url.startAccessingSecurityScopedResource() else { return false }
        accessingURLs.insert(url)
        return true
    }

    /// 보안 스코프 접근 종료
    func stopAccessing(_ url: URL) {
        url.stopAccessingSecurityScopedResource()
        accessingURLs.remove(url)
    }

    /// 현재 접근 중인 모든 URL 종료
    func stopAllAccessing() {
        for url in accessingURLs {
            url.stopAccessingSecurityScopedResource()
        }
        accessingURLs.removeAll()
    }

    // MARK: - Private

    private func loadBookmarkDataArray() -> [Data] {
        UserDefaults.standard.array(forKey: Self.bookmarksKey) as? [Data] ?? []
    }
}
