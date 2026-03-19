import AppKit

/// 폴더별 색상 관리 (UserDefaults 저장)
final class FolderColorService {
    static let shared = FolderColorService()
    private let defaults = UserDefaults.standard
    private let key = "folderColors"

    private init() {}

    /// 파스텔톤 색상 팔레트
    static let palette: [(name: String, color: NSColor)] = [
        ("기본",    .controlAccentColor),
        ("빨강",    NSColor(red: 0.95, green: 0.55, blue: 0.55, alpha: 1)),
        ("주황",    NSColor(red: 0.96, green: 0.73, blue: 0.47, alpha: 1)),
        ("초록",    NSColor(red: 0.56, green: 0.86, blue: 0.58, alpha: 1)),
        ("파랑",    NSColor(red: 0.55, green: 0.70, blue: 0.95, alpha: 1)),
        ("보라",    NSColor(red: 0.76, green: 0.60, blue: 0.92, alpha: 1)),
    ]

    /// 폴더 URL에 저장된 색상 인덱스 (0 = 기본)
    func colorIndex(for url: URL) -> Int {
        let dict = defaults.dictionary(forKey: key) as? [String: Int] ?? [:]
        return dict[url.path] ?? 0
    }

    func color(for url: URL) -> NSColor {
        let idx = colorIndex(for: url)
        guard idx >= 0, idx < Self.palette.count else { return .controlAccentColor }
        return Self.palette[idx].color
    }

    func setColorIndex(_ index: Int, for url: URL) {
        var dict = defaults.dictionary(forKey: key) as? [String: Int] ?? [:]
        if index == 0 {
            dict.removeValue(forKey: url.path)
        } else {
            dict[url.path] = index
        }
        defaults.set(dict, forKey: key)
        // 양쪽 뷰 동기화를 위한 알림
        NotificationCenter.default.post(name: .folderColorChanged, object: url)
    }

}

extension Notification.Name {
    static let folderColorChanged = Notification.Name("com.jenalab.jenaimage.folderColorChanged")
}

extension FolderColorService {
    /// 색상 선택 서브메뉴 생성
    static func createColorMenu(for url: URL, target: AnyObject, action: Selector) -> NSMenu {
        let menu = NSMenu(title: "폴더 색상")
        let currentIdx = shared.colorIndex(for: url)

        for (idx, item) in palette.enumerated() {
            let menuItem = NSMenuItem(title: item.name, action: action, keyEquivalent: "")
            menuItem.target = target
            menuItem.tag = idx
            menuItem.representedObject = url
            menuItem.state = idx == currentIdx ? .on : .off

            // 색상 원 아이콘
            let size = NSSize(width: 12, height: 12)
            let image = NSImage(size: size, flipped: false) { rect in
                item.color.setFill()
                NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
                return true
            }
            menuItem.image = image

            menu.addItem(menuItem)
        }
        return menu
    }
}
