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
        appMenu.addItem(withTitle: "JenaImage에 대하여", action: #selector(AppDelegate.showAbout(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "JenaImage 숨기기", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")

        let hideOthers = NSMenuItem(title: "기타 숨기기", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)

        appMenu.addItem(withTitle: "모두 보기", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "JenaImage 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let item = NSMenuItem()
        item.submenu = appMenu
        return item
    }

    // MARK: - File Menu

    private static func createFileMenu() -> NSMenuItem {
        let fileMenu = NSMenu(title: "파일")

        let addFolder = NSMenuItem(title: "폴더 추가…", action: #selector(MainWindowController.addFolder(_:)), keyEquivalent: "o")
        fileMenu.addItem(addFolder)

        fileMenu.addItem(NSMenuItem.separator())

        let revealInFinder = NSMenuItem(title: "Finder에서 보기", action: #selector(MainWindowController.revealInFinder(_:)), keyEquivalent: "r")
        fileMenu.addItem(revealInFinder)

        fileMenu.addItem(NSMenuItem.separator())

        let rename = NSMenuItem(title: "이름 변경", action: #selector(MainWindowController.renameSelected(_:)), keyEquivalent: "")
        fileMenu.addItem(rename)

        let moveTo = NSMenuItem(title: "이동…", action: #selector(MainWindowController.moveSelected(_:)), keyEquivalent: "")
        fileMenu.addItem(moveTo)

        let copyTo = NSMenuItem(title: "복사…", action: #selector(MainWindowController.copySelected(_:)), keyEquivalent: "")
        fileMenu.addItem(copyTo)

        fileMenu.addItem(NSMenuItem.separator())

        let saveAs = NSMenuItem(title: "다른 이름으로 저장…", action: #selector(MainWindowController.exportCurrentImage(_:)), keyEquivalent: "S")
        saveAs.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(saveAs)

        fileMenu.addItem(NSMenuItem.separator())

        let delete = NSMenuItem(title: "삭제", action: #selector(MainWindowController.deleteSelected(_:)), keyEquivalent: "\u{08}")
        delete.keyEquivalentModifierMask = []
        fileMenu.addItem(delete)

        let item = NSMenuItem()
        item.submenu = fileMenu
        return item
    }

    // MARK: - Edit Menu

    private static func createEditMenu() -> NSMenuItem {
        let editMenu = NSMenu(title: "편집")

        let copy = NSMenuItem(title: "복사", action: #selector(MainWindowController.copyImageToClipboard(_:)), keyEquivalent: "c")
        editMenu.addItem(copy)

        editMenu.addItem(NSMenuItem.separator())

        let selectAll = NSMenuItem(title: "모두 선택", action: #selector(MainWindowController.selectAllItems(_:)), keyEquivalent: "a")
        editMenu.addItem(selectAll)

        let item = NSMenuItem()
        item.submenu = editMenu
        return item
    }

    // MARK: - Image Menu

    private static func createImageMenu() -> NSMenuItem {
        let imageMenu = NSMenu(title: "이미지")

        let editImage = NSMenuItem(title: "이미지 편집…", action: #selector(MainWindowController.openImageEditor(_:)), keyEquivalent: "e")
        imageMenu.addItem(editImage)

        let item = NSMenuItem()
        item.submenu = imageMenu
        return item
    }

    // MARK: - View Menu

    private static func createViewMenu() -> NSMenuItem {
        let viewMenu = NSMenu(title: "보기")

        let toggleSidebar = NSMenuItem(title: "사이드바 보기/숨기기", action: #selector(MainWindowController.toggleSidebar(_:)), keyEquivalent: "s")
        toggleSidebar.keyEquivalentModifierMask = [.command, .option]
        viewMenu.addItem(toggleSidebar)

        viewMenu.addItem(NSMenuItem.separator())

        let goBack = NSMenuItem(title: "뒤로", action: #selector(MainWindowController.goBack(_:)), keyEquivalent: "[")
        viewMenu.addItem(goBack)

        viewMenu.addItem(NSMenuItem.separator())

        let prevImage = NSMenuItem(title: "이전 이미지", action: #selector(MainWindowController.navigatePreviousImage(_:)), keyEquivalent: "\u{F700}")  // Up arrow
        prevImage.keyEquivalentModifierMask = []
        viewMenu.addItem(prevImage)

        let nextImage = NSMenuItem(title: "다음 이미지", action: #selector(MainWindowController.navigateNextImage(_:)), keyEquivalent: "\u{F701}")  // Down arrow
        nextImage.keyEquivalentModifierMask = []
        viewMenu.addItem(nextImage)

        viewMenu.addItem(NSMenuItem.separator())

        let zoomIn = NSMenuItem(title: "확대", action: #selector(MainWindowController.zoomIn(_:)), keyEquivalent: "+")
        viewMenu.addItem(zoomIn)

        let zoomOut = NSMenuItem(title: "축소", action: #selector(MainWindowController.zoomOut(_:)), keyEquivalent: "-")
        viewMenu.addItem(zoomOut)

        viewMenu.addItem(NSMenuItem.separator())

        let actualSize = NSMenuItem(title: "원본 크기", action: #selector(MainWindowController.zoomActualSize(_:)), keyEquivalent: "0")
        viewMenu.addItem(actualSize)

        let fitToWindow = NSMenuItem(title: "화면에 맞춤", action: #selector(MainWindowController.zoomFit(_:)), keyEquivalent: "9")
        viewMenu.addItem(fitToWindow)

        let item = NSMenuItem()
        item.submenu = viewMenu
        return item
    }

    // MARK: - Window Menu

    private static func createWindowMenu() -> NSMenuItem {
        let windowMenu = NSMenu(title: "윈도우")
        windowMenu.addItem(withTitle: "최소화", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "확대/축소", action: #selector(NSWindow.zoom(_:)), keyEquivalent: "")

        let fullScreen = NSMenuItem(title: "전체 화면 시작/종료", action: #selector(MainWindowController.toggleFullScreen(_:)), keyEquivalent: "f")
        fullScreen.keyEquivalentModifierMask = [.command, .control]
        windowMenu.addItem(fullScreen)

        let item = NSMenuItem()
        item.submenu = windowMenu
        NSApp.windowsMenu = windowMenu
        return item
    }

    // MARK: - Help Menu

    private static func createHelpMenu() -> NSMenuItem {
        let helpMenu = NSMenu(title: "도움말")
        helpMenu.addItem(withTitle: "JenaImage 도움말", action: #selector(AppDelegate.showHelpWindow(_:)), keyEquivalent: "?")

        let item = NSMenuItem()
        item.submenu = helpMenu
        return item
    }
}
