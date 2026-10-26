import AppKit

/// 앱 설정 관리 (UserDefaults 래퍼)
final class AppSettings {
    static let shared = AppSettings()
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    // MARK: - Keys

    private enum Key: String {
        case language = "appLanguage"
        case viewerBackground = "viewerBackground"
        case defaultExportFormat = "defaultExportFormat"
        case defaultExportQuality = "defaultExportQuality"
        case showThumbnailStrip = "showThumbnailStrip"
        case scrollWheelZoom = "scrollWheelZoom"
        case sortKey = "browserSortKey"
        case sortAscending = "browserSortAscending"
        case slideshowInterval = "slideshowInterval"
        case recursiveBrowsing = "browserRecursive"
        case thumbnailMaxPixel = "thumbnailMaxPixel"
        case thumbnailCacheMB = "thumbnailCacheMB"
        case thumbnailDiskCacheMB = "thumbnailDiskCacheMB"
        case viewerFitMode = "viewerFitMode"
        case browserLayout = "browserLayout"
        case recentFolders = "recentFolderPaths"
    }

    // MARK: - Language

    var language: Language {
        get {
            let raw = defaults.string(forKey: Key.language.rawValue) ?? "ko"
            return Language(rawValue: raw) ?? .korean
        }
        set {
            defaults.set(newValue.rawValue, forKey: Key.language.rawValue)
            L10n.language = newValue
        }
    }

    // MARK: - Viewer Background

    enum ViewerBackground: String, CaseIterable {
        case system = "system"
        case dark = "dark"
        case light = "light"

        var color: NSColor {
            switch self {
            case .system: return .controlBackgroundColor
            case .dark: return NSColor(white: 0.15, alpha: 1)
            case .light: return NSColor(white: 0.95, alpha: 1)
            }
        }

        func displayName() -> String {
            switch self {
            case .system: return L10n.string(.bgColorSystem)
            case .dark: return L10n.string(.bgColorDark)
            case .light: return L10n.string(.bgColorLight)
            }
        }
    }

    var viewerBackground: ViewerBackground {
        get {
            let raw = defaults.string(forKey: Key.viewerBackground.rawValue) ?? "system"
            return ViewerBackground(rawValue: raw) ?? .system
        }
        set {
            defaults.set(newValue.rawValue, forKey: Key.viewerBackground.rawValue)
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
    }

    // MARK: - Export Defaults

    var defaultExportFormat: String {
        get { defaults.string(forKey: Key.defaultExportFormat.rawValue) ?? "jpeg" }
        set { defaults.set(newValue, forKey: Key.defaultExportFormat.rawValue) }
    }

    var defaultExportQuality: Int {
        get {
            let val = defaults.integer(forKey: Key.defaultExportQuality.rawValue)
            return val > 0 ? val : 85
        }
        set { defaults.set(newValue, forKey: Key.defaultExportQuality.rawValue) }
    }

    // MARK: - Viewer

    /// 뷰어에서 이미지를 열 때 적용하는 맞춤 기준. 셋 중 하나만 켜지는 토글이며 기본은 전체 맞춤.
    enum ViewerFitMode: String, CaseIterable {
        case window = "window"
        case height = "height"
        case width = "width"
    }

    var viewerFitMode: ViewerFitMode {
        get {
            let raw = defaults.string(forKey: Key.viewerFitMode.rawValue) ?? ""
            return ViewerFitMode(rawValue: raw) ?? .window
        }
        set { defaults.set(newValue.rawValue, forKey: Key.viewerFitMode.rawValue) }
    }

    var showThumbnailStrip: Bool {
        get {
            if defaults.object(forKey: Key.showThumbnailStrip.rawValue) == nil { return true }
            return defaults.bool(forKey: Key.showThumbnailStrip.rawValue)
        }
        set { defaults.set(newValue, forKey: Key.showThumbnailStrip.rawValue) }
    }

    var scrollWheelZoom: Bool {
        get {
            if defaults.object(forKey: Key.scrollWheelZoom.rawValue) == nil { return true }
            return defaults.bool(forKey: Key.scrollWheelZoom.rawValue)
        }
        set {
            defaults.set(newValue, forKey: Key.scrollWheelZoom.rawValue)
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
    }

    // MARK: - Browser Sort

    var browserLayoutMode: BrowserLayoutMode {
        get { BrowserLayoutMode(rawValue: defaults.string(forKey: Key.browserLayout.rawValue) ?? "") ?? .masonry }
        set { defaults.set(newValue.rawValue, forKey: Key.browserLayout.rawValue) }
    }

    var sortKey: SortKey {
        get {
            let raw = defaults.string(forKey: Key.sortKey.rawValue) ?? SortKey.name.rawValue
            return SortKey(rawValue: raw) ?? .name
        }
        set { defaults.set(newValue.rawValue, forKey: Key.sortKey.rawValue) }
    }

    var sortAscending: Bool {
        get {
            if defaults.object(forKey: Key.sortAscending.rawValue) == nil { return true }
            return defaults.bool(forKey: Key.sortAscending.rawValue)
        }
        set { defaults.set(newValue, forKey: Key.sortAscending.rawValue) }
    }

    // MARK: - Browser Recursive

    /// 하위 폴더 이미지 포함 보기. 켜면 선택한 폴더를 루트로 모든 하위 폴더의 이미지를 평면 목록으로 보여준다.
    var recursiveBrowsing: Bool {
        get { defaults.bool(forKey: Key.recursiveBrowsing.rawValue) }
        set { defaults.set(newValue, forKey: Key.recursiveBrowsing.rawValue) }
    }

    // MARK: - Thumbnails

    /// 그리드 썸네일 긴 변 픽셀 상한. 셀 최대 220pt × 레티나 2배 = 440이 쓸모 있는 상한이라 그 이하 단계만 둔다.
    enum ThumbnailMaxPixel: Int, CaseIterable {
        case small = 220
        case medium = 330
        case large = 440

        var displayName: String {
            switch self {
            case .small:  return "220px (저해상도 · 메모리 절약)"
            case .medium: return "330px (중간)"
            case .large:  return "440px (레티나 선명 · 기본)"
            }
        }

        /// 한 장당 대략 메모리(RGBA 4바이트, 정방형 가정)
        var approxBytesPerImage: Int { rawValue * rawValue * 4 }
    }

    var thumbnailMaxPixel: ThumbnailMaxPixel {
        get {
            let raw = defaults.integer(forKey: Key.thumbnailMaxPixel.rawValue)
            return ThumbnailMaxPixel(rawValue: raw) ?? .large
        }
        set { defaults.set(newValue.rawValue, forKey: Key.thumbnailMaxPixel.rawValue) }
    }

    static let thumbnailCacheMBDefault = 500
    static let thumbnailCacheMBRange = 100...2048

    /// 썸네일 메모리 캐시 한도(MB). 기본 500, 100~2048.
    var thumbnailCacheMB: Int {
        get {
            if defaults.object(forKey: Key.thumbnailCacheMB.rawValue) == nil { return Self.thumbnailCacheMBDefault }
            let v = defaults.integer(forKey: Key.thumbnailCacheMB.rawValue)
            return min(max(v, Self.thumbnailCacheMBRange.lowerBound), Self.thumbnailCacheMBRange.upperBound)
        }
        set { defaults.set(newValue, forKey: Key.thumbnailCacheMB.rawValue) }
    }

    static let thumbnailDiskCacheMBDefault = 2048
    static let thumbnailDiskCacheMBRange = 500...8192

    /// 썸네일 디스크 캐시 한도(MB). 기본 2048, 500~8192. "적용" 없이 즉시 반영.
    var thumbnailDiskCacheMB: Int {
        get {
            if defaults.object(forKey: Key.thumbnailDiskCacheMB.rawValue) == nil { return Self.thumbnailDiskCacheMBDefault }
            let v = defaults.integer(forKey: Key.thumbnailDiskCacheMB.rawValue)
            return min(max(v, Self.thumbnailDiskCacheMBRange.lowerBound), Self.thumbnailDiskCacheMBRange.upperBound)
        }
        set { defaults.set(newValue, forKey: Key.thumbnailDiskCacheMB.rawValue) }
    }

    // MARK: - Recent Folders

    static let recentFoldersLimit = 10

    /// 최근 연 폴더. 최신이 앞. 샌드박스가 아니라 루트 폴더와 같은 방식으로 경로 문자열로 저장한다.
    var recentFolders: [URL] {
        get {
            let paths = defaults.stringArray(forKey: Key.recentFolders.rawValue) ?? []
            return paths.map { URL(fileURLWithPath: $0, isDirectory: true) }
        }
        set {
            let paths = newValue.map { $0.standardizedFileURL.path }
            defaults.set(Array(paths.prefix(Self.recentFoldersLimit)), forKey: Key.recentFolders.rawValue)
        }
    }

    /// 폴더를 최근 목록 맨 앞으로 올린다(이미 있으면 자리만 옮김).
    func addRecentFolder(_ url: URL) {
        let path = url.standardizedFileURL.path
        var list = recentFolders.filter { $0.standardizedFileURL.path != path }
        list.insert(URL(fileURLWithPath: path, isDirectory: true), at: 0)
        recentFolders = list
    }

    func removeRecentFolder(_ url: URL) {
        let path = url.standardizedFileURL.path
        recentFolders = recentFolders.filter { $0.standardizedFileURL.path != path }
    }

    func clearRecentFolders() {
        recentFolders = []
    }

    // MARK: - Slideshow

    /// 슬라이드쇼 자동 넘김 간격(초). 기본 3초.
    var slideshowInterval: TimeInterval {
        get {
            let v = defaults.double(forKey: Key.slideshowInterval.rawValue)
            return v > 0 ? v : 3.0
        }
        set { defaults.set(newValue, forKey: Key.slideshowInterval.rawValue) }
    }
}

// MARK: - Notification

extension Notification.Name {
    static let settingsChanged = Notification.Name("com.jenalab.jenaimage.settingsChanged")
    /// 썸네일 크기·캐시 한도가 "적용"된 시점 — 캐시 비우고 현재 폴더를 다시 읽을 신호
    static let thumbnailSettingsApplied = Notification.Name("com.jenalab.jenaimage.thumbnailSettingsApplied")
}
