import AppKit

/// AppKit entry point for a menu-bar-only (LSUIElement) app. The menu bar
/// item lives in StatusItemController; the settings window in
/// SettingsWindowController.
@main
enum MencalMain {
    private static let delegate = AppDelegate()

    static func main() {
        let app = NSApplication.shared
        app.delegate = delegate
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let ticker = DateTicker()
    private let store = CalendarStore()

    private var statusController: StatusItemController?
    private lazy var settingsController = SettingsWindowController(ticker: ticker, store: store)

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Unit tests run inside the app: give them no menu bar item and no
        // calendar access.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        // Nothing to save, so logout and restart needn't wait for Mencal.
        // (Xcode doesn't emit the Info.plist key for this, so it's set here.)
        ProcessInfo.processInfo.enableSuddenTermination()
        NSApp.mainMenu = MainMenu.make()
        statusController = StatusItemController(ticker: ticker, store: store)
    }

    @objc func showSettings(_ sender: Any?) {
        settingsController.show()
    }

    /// Opening Mencal again (Finder, Spotlight, the Dock) shows Settings, so
    /// it's reachable even if the menu bar item is hidden (by the notch, or
    /// the System Settings › Menu Bar switch).
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showSettings(nil) }
        return true
    }
}

/// Menu-bar-only apps never show a main menu, but its key equivalents still
/// work while the Settings window is key: copy/paste in the pattern field,
/// ⌘W to close, ⌘Q to quit.
private enum MainMenu {
    static func make() -> NSMenu {
        let main = NSMenu()

        let appMenu = NSMenu(title: "Mencal")
        appMenu.addItem(withTitle: String(localized: "Settings…"), action: #selector(AppDelegate.showSettings(_:)), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: String(localized: "Quit Mencal"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(submenuItem(appMenu))

        let editMenu = NSMenu(title: String(localized: "Edit"))
        editMenu.addItem(withTitle: String(localized: "Undo"), action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: String(localized: "Redo"), action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: String(localized: "Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: String(localized: "Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: String(localized: "Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: String(localized: "Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        main.addItem(submenuItem(editMenu))

        let windowMenu = NSMenu(title: String(localized: "Window"))
        windowMenu.addItem(withTitle: String(localized: "Close"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        main.addItem(submenuItem(windowMenu))

        return main
    }

    private static func submenuItem(_ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }
}
