import AppKit

/// 앱 설정 관리 (UserDefaults 래퍼)
final class AppSettings {
    static let shared = AppSettings()
    private let defaults = UserDefaults.standard

    private init() {}

    // MARK: - Keys

    private enum Key: String {
        case language = "appLanguage"
        case viewerBackground = "viewerBackground"
        case defaultExportFormat = "defaultExportFormat"
        case defaultExportQuality = "defaultExportQuality"
        case showThumbnailStrip = "showThumbnailStrip"
        case scrollWheelZoom = "scrollWheelZoom"
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
}

// MARK: - Notification

extension Notification.Name {
    static let settingsChanged = Notification.Name("com.jenalab.jenaimage.settingsChanged")
}
