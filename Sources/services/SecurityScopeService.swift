import AppKit
import Foundation

/// 사이드바에 등록한 루트 폴더 목록의 저장소.
///
/// 이 앱은 샌드박스가 아니다. 그래서 폴더는 `folderColors`·`imageBookmarks`와 같은 방식으로 **경로 문자열**로 저장한다.
/// 예전엔 security-scoped 북마크로 저장했는데, 그 북마크는 앱의 코드 서명 정체성에 묶여 서명 방식이 바뀌면
/// 전부 복원에 실패하고, 복원 코드가 실패 항목을 지운 채 다시 저장해 목록이 통째로 사라졌다(2026-10-17).
/// 외장 디스크가 안 꽂힌 채 켜도 그 폴더가 영구히 지워지는 결함도 같은 뿌리였다.
///
/// 원칙: **복원 실패로 항목을 지우지 않는다.** 지우는 건 사용자의 명시적 제거만.
final class SecurityScopeService {
    private static let pathsKey = "rootFolderPaths"
    /// 예전 저장 키(security-scoped 북마크 Data 배열). 한 번 읽어 경로로 옮긴 뒤엔 건드리지 않는다.
    private static let legacyBookmarksKey = "folderBookmarks"
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

    /// 폴더 등록(이름은 호환을 위해 유지). 같은 경로가 있으면 자리 유지.
    func addBookmark(for url: URL) {
        var paths = loadPaths()
        let path = url.standardizedFileURL.path
        if !paths.contains(path) { paths.append(path) }
        savePaths(paths)
    }

    /// 폴더 등록 해제 — 사용자의 명시적 제거만 여기로 온다.
    func removeBookmark(for url: URL) {
        let path = url.standardizedFileURL.path
        savePaths(loadPaths().filter { $0 != path })
    }

    /// 저장된 폴더 목록. 존재하지 않는 경로(외장 디스크 미연결 등)도 그대로 돌려준다 — 지우지 않는다.
    func restoreBookmarks() -> [URL] {
        var paths = loadPaths()
        if paths.isEmpty, let migrated = migrateLegacyBookmarks(), !migrated.isEmpty {
            paths = migrated
            savePaths(paths)
        }
        return paths.map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    /// 보안 스코프 접근 시작. 샌드박스가 아니라 실질 효과는 없지만 호출부 호환을 위해 둔다.
    @discardableResult
    func startAccessing(_ url: URL) -> Bool {
        guard url.startAccessingSecurityScopedResource() else { return false }
        accessingURLs.insert(url)
        return true
    }

    /// 보안 스코프 접근 종료
    func stopAccessing(_ url: URL) {
        guard accessingURLs.contains(url) else { return }
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

    private func loadPaths() -> [String] {
        UserDefaults.standard.stringArray(forKey: Self.pathsKey) ?? []
    }

    private func savePaths(_ paths: [String]) {
        UserDefaults.standard.set(paths, forKey: Self.pathsKey)
    }

    /// 예전 security-scoped 북마크를 경로로 옮긴다. 서명이 바뀐 뒤면 복원이 안 돼 비어 있을 수 있다.
    /// 옛 데이터는 지우지 않고 남겨 둔다(혹시 모를 재시도용).
    private func migrateLegacyBookmarks() -> [String]? {
        guard let datas = UserDefaults.standard.array(forKey: Self.legacyBookmarksKey) as? [Data], !datas.isEmpty else {
            return nil
        }
        var paths: [String] = []
        for data in datas {
            var isStale = false
            let url = (try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale))
                ?? (try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale))
            if let url { paths.append(url.standardizedFileURL.path) }
        }
        return paths
    }
}
