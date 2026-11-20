import AppKit
import SwiftUI

/// The settings window: an `NSTabViewController` with toolbar tabs (the
/// standard Mac layout), each tab hosting a SwiftUI form. The window title
/// follows the selected tab.
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let ticker: DateTicker
    private let store: CalendarStore
    private var window: NSWindow?

    init(ticker: DateTicker, store: CalendarStore) {
        self.ticker = ticker
        self.store = store
    }

    func show() {
        if window == nil {
            window = makeWindow()
            window?.center()
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    /// Built on demand and released on close, so nothing in it stays alive
    /// (or keeps updating) in the background.
    func windowWillClose(_ notification: Notification) {
        window = nil
    }

    private func makeWindow() -> NSWindow {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        tabs.addTabViewItem(tab(String(localized: "General"), symbol: "gearshape", GeneralSettings()))
        tabs.addTabViewItem(tab(String(localized: "Menu Bar"), symbol: "menubar.rectangle", MenuBarSettings()))
        tabs.addTabViewItem(tab(String(localized: "Calendar"), symbol: "calendar", CalendarSettings()))

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.delegate = self

        // NSTabViewController resizes the window to the selected tab's
        // `preferredContentSize` on tab switches and content changes, but not
        // when the window is first built, so fit the first tab here.
        window.contentView?.layoutSubtreeIfNeeded()
        if let size = tabs.tabView.selectedTabViewItem?.viewController?.preferredContentSize,
           size.width > 0, size.height > 0 {
            window.setContentSize(size)
        }
        return window
    }

    private func tab(_ title: String, symbol: String, _ content: some View) -> NSTabViewItem {
        let host = NSHostingController(rootView: content.environment(ticker).environment(store))
        // Report the SwiftUI content's size, which NSTabViewController uses
        // to size the window.
        host.sizingOptions = .preferredContentSize
        host.title = title

        let item = NSTabViewItem(viewController: host)
        item.label = title
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        return item
    }
}
