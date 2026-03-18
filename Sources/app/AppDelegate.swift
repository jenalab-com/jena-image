import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindowController: MainWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.create()

        mainWindowController = MainWindowController()
        mainWindowController?.showWindow(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    @objc func showHelpWindow(_ sender: Any?) {
        HelpWindowController.shared.show()
    }

    @objc func showAbout(_ sender: Any?) {
        let credits = NSMutableAttributedString()

        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        let linkAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.linkColor,
            .link: URL(string: "https://www.jenalab.com")!,
        ]

        credits.append(NSAttributedString(string: "@jenalab\n", attributes: labelAttrs))
        credits.append(NSAttributedString(string: "https://www.jenalab.com", attributes: linkAttrs))

        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: credits,
        ])
    }
}
