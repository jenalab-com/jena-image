import AppKit

/// 메뉴바 구성
enum MainMenu {
    static func create() -> NSMenu {
        let mainMenu = NSMenu()

        mainMenu.addItem(createAppMenu())
        mainMenu.addItem(createFileMenu())
        mainMenu.addItem(createEditMenu())
        mainMenu.addItem(createImageMenu())
        mainMenu.addItem(createViewMenu())
        mainMenu.addItem(createWindowMenu())
        mainMenu.addItem(createHelpMenu())

        return mainMenu
    }

    // MARK: - App Menu

    private static func createAppMenu() -> NSMenuItem {
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: L10n.string(.about), action: #selector(AppDelegate.showAbout(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())

        let prefs = NSMenuItem(title: L10n.string(.preferences), action: #selector(AppDelegate.showPreferences(_:)), keyEquivalent: ",")
        appMenu.addItem(prefs)

        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: L10n.string(.hideApp), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")

        let hideOthers = NSMenuItem(title: L10n.string(.hideOthers), action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)

        appMenu.addItem(withTitle: L10n.string(.showAll), action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: L10n.string(.quit), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let item = NSMenuItem()
        item.submenu = appMenu
        return item
    }

    // MARK: - File Menu

    private static func createFileMenu() -> NSMenuItem {
        let fileMenu = NSMenu(title: L10n.string(.file))

        fileMenu.addItem(withTitle: L10n.string(.addFolder), action: #selector(MainWindowController.addFolder(_:)), keyEquivalent: "o")
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(withTitle: L10n.string(.revealInFinder), action: #selector(MainWindowController.revealInFinder(_:)), keyEquivalent: "r")
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(withTitle: L10n.string(.rename), action: #selector(MainWindowController.renameSelected(_:)), keyEquivalent: "")
        fileMenu.addItem(withTitle: L10n.string(.moveTo), action: #selector(MainWindowController.moveSelected(_:)), keyEquivalent: "")
        fileMenu.addItem(withTitle: L10n.string(.copyTo), action: #selector(MainWindowController.copySelected(_:)), keyEquivalent: "")
        fileMenu.addItem(NSMenuItem.separator())

        let saveAs = NSMenuItem(title: L10n.string(.saveAs), action: #selector(MainWindowController.exportCurrentImage(_:)), keyEquivalent: "S")
        saveAs.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(saveAs)

        fileMenu.addItem(NSMenuItem.separator())

        let delete = NSMenuItem(title: L10n.string(.delete), action: #selector(MainWindowController.deleteSelected(_:)), keyEquivalent: "\u{08}")
        delete.keyEquivalentModifierMask = []
        fileMenu.addItem(delete)

        let item = NSMenuItem()
        item.submenu = fileMenu
        return item
    }

    // MARK: - Edit Menu

    private static func createEditMenu() -> NSMenuItem {
        let editMenu = NSMenu(title: L10n.string(.edit))

        editMenu.addItem(withTitle: L10n.string(.copy), action: #selector(MainWindowController.copyFiles(_:)), keyEquivalent: "c")

        let paste = NSMenuItem(title: L10n.string(.paste), action: #selector(MainWindowController.pasteFiles(_:)), keyEquivalent: "v")
        editMenu.addItem(paste)

        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: L10n.string(.selectAll), action: #selector(MainWindowController.selectAllItems(_:)), keyEquivalent: "a")

        let item = NSMenuItem()
        item.submenu = editMenu
        return item
    }

    // MARK: - Image Menu

    private static func createImageMenu() -> NSMenuItem {
        let imageMenu = NSMenu(title: L10n.string(.image))
        imageMenu.addItem(withTitle: L10n.string(.imageEdit), action: #selector(MainWindowController.openImageEditor(_:)), keyEquivalent: "e")

        let item = NSMenuItem()
        item.submenu = imageMenu
        return item
    }

    // MARK: - View Menu

    private static func createViewMenu() -> NSMenuItem {
        let viewMenu = NSMenu(title: L10n.string(.view))

        let toggleSidebar = NSMenuItem(title: L10n.string(.toggleSidebar), action: #selector(MainWindowController.toggleSidebar(_:)), keyEquivalent: "s")
        toggleSidebar.keyEquivalentModifierMask = [.command, .option]
        viewMenu.addItem(toggleSidebar)
        viewMenu.addItem(NSMenuItem.separator())
        viewMenu.addItem(withTitle: L10n.string(.goBack), action: #selector(MainWindowController.goBack(_:)), keyEquivalent: "[")
        viewMenu.addItem(NSMenuItem.separator())

        let prevImage = NSMenuItem(title: L10n.string(.prevImage), action: #selector(MainWindowController.navigatePreviousImage(_:)), keyEquivalent: "\u{F700}")
        prevImage.keyEquivalentModifierMask = []
        viewMenu.addItem(prevImage)

        let nextImage = NSMenuItem(title: L10n.string(.nextImage), action: #selector(MainWindowController.navigateNextImage(_:)), keyEquivalent: "\u{F701}")
        nextImage.keyEquivalentModifierMask = []
        viewMenu.addItem(nextImage)

        viewMenu.addItem(NSMenuItem.separator())
        viewMenu.addItem(withTitle: L10n.string(.zoomIn), action: #selector(MainWindowController.zoomIn(_:)), keyEquivalent: "+")
        viewMenu.addItem(withTitle: L10n.string(.zoomOut), action: #selector(MainWindowController.zoomOut(_:)), keyEquivalent: "-")
        viewMenu.addItem(NSMenuItem.separator())
        viewMenu.addItem(withTitle: L10n.string(.actualSize), action: #selector(MainWindowController.zoomActualSize(_:)), keyEquivalent: "0")
        viewMenu.addItem(withTitle: L10n.string(.fitToWindow), action: #selector(MainWindowController.zoomFit(_:)), keyEquivalent: "9")

        let item = NSMenuItem()
        item.submenu = viewMenu
        return item
    }

    // MARK: - Window Menu

    private static func createWindowMenu() -> NSMenuItem {
        let windowMenu = NSMenu(title: L10n.string(.window))
        windowMenu.addItem(withTitle: L10n.string(.minimize), action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: L10n.string(.zoom), action: #selector(NSWindow.zoom(_:)), keyEquivalent: "")

        let fullScreen = NSMenuItem(title: L10n.string(.fullScreen), action: #selector(MainWindowController.toggleFullScreen(_:)), keyEquivalent: "f")
        fullScreen.keyEquivalentModifierMask = [.command, .control]
        windowMenu.addItem(fullScreen)

        let item = NSMenuItem()
        item.submenu = windowMenu
        NSApp.windowsMenu = windowMenu
        return item
    }

    // MARK: - Help Menu

    private static func createHelpMenu() -> NSMenuItem {
        let helpMenu = NSMenu(title: L10n.string(.help))
        helpMenu.addItem(withTitle: L10n.string(.appHelp), action: #selector(AppDelegate.showHelpWindow(_:)), keyEquivalent: "?")

        let item = NSMenuItem()
        item.submenu = helpMenu
        return item
    }
}
