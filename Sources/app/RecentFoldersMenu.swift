import AppKit

/// 파일 메뉴 "최근 폴더" 하위 메뉴. 열릴 때마다 `AppSettings.recentFolders`로 다시 채운다.
///
/// 항목의 action은 target 없이 responder chain으로 보내 `MainWindowController.openRecentFolder(_:)`가 받는다.
final class RecentFoldersMenu: NSObject, NSMenuDelegate {
    static let shared = RecentFoldersMenu()

    func makeMenu() -> NSMenu {
        let menu = NSMenu(title: L10n.string(.recentFolders))
        menu.delegate = self
        return menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let folders = AppSettings.shared.recentFolders

        guard !folders.isEmpty else {
            let empty = NSMenuItem(title: L10n.string(.noRecentFolders), action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
            return
        }

        for url in folders {
            let item = NSMenuItem(title: url.lastPathComponent,
                                  action: #selector(MainWindowController.openRecentFolder(_:)),
                                  keyEquivalent: "")
            item.representedObject = url
            item.toolTip = url.path
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 16, height: 16)
            item.image = icon
            menu.addItem(item)
        }

        menu.addItem(.separator())
        menu.addItem(withTitle: L10n.string(.clearRecentFolders),
                     action: #selector(MainWindowController.clearRecentFolders(_:)),
                     keyEquivalent: "")
    }
}
