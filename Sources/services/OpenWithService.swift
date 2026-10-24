import AppKit

/// "다른 앱으로 열기" — 시스템에 등록된 호환 앱 조회와 실행을 담당한다.
enum OpenWithService {
    struct Application {
        let url: URL
        let name: String
        let icon: NSImage
    }

    /// 해당 파일을 열 수 있는 앱 목록. 이 앱 자신은 제외하고 이름순으로 정렬한다.
    static func applications(for fileURL: URL) -> [Application] {
        let ownBundleID = Bundle.main.bundleIdentifier
        let ownBundlePath = Bundle.main.bundleURL.standardizedFileURL.path

        var seen = Set<String>()
        let apps: [Application] = NSWorkspace.shared.urlsForApplications(toOpen: fileURL).compactMap { appURL in
            let standardized = appURL.standardizedFileURL
            if standardized.path == ownBundlePath { return nil }

            let bundle = Bundle(url: standardized)
            let bundleID = bundle?.bundleIdentifier

            // 같은 앱의 복사본이 여러 개 등록된 경우 첫 번째만 남긴다.
            let key = bundleID ?? standardized.path
            guard seen.insert(key).inserted else { return nil }
            if let bundleID, bundleID == ownBundleID { return nil }

            let icon = NSWorkspace.shared.icon(forFile: standardized.path)
            icon.size = NSSize(width: 16, height: 16)

            return Application(
                url: standardized,
                name: displayName(for: standardized, bundle: bundle),
                icon: icon
            )
        }

        return apps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// 메뉴에 표시할 앱 이름. 번들 표시 이름을 우선하고, 없으면 파일명에서 `.app`을 뗀다.
    private static func displayName(for appURL: URL, bundle: Bundle?) -> String {
        if let name = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, !name.isEmpty {
            return name
        }
        if let name = bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String, !name.isEmpty {
            return name
        }
        return appURL.deletingPathExtension().lastPathComponent
    }

    /// 시스템 기본 앱으로 연다.
    @discardableResult
    static func openWithDefault(_ fileURL: URL) -> Bool {
        NSWorkspace.shared.open(fileURL)
    }

    /// 지정한 앱으로 연다.
    static func open(_ fileURL: URL, withApplicationAt appURL: URL) {
        NSWorkspace.shared.open(
            [fileURL],
            withApplicationAt: appURL,
            configuration: NSWorkspace.OpenConfiguration()
        ) { _, error in
            if let error {
                NSLog("다른 앱으로 열기 실패: %@", error.localizedDescription)
            }
        }
    }
}
