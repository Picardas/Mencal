import AppKit
import Observation
import SwiftUI

/// Shared between the status item and the SwiftUI calendar in its menu.
@Observable
final class MenuState {
    /// True while the menu is open. The calendar resets to today on opening
    /// and only fetches events while open.
    fileprivate(set) var isOpen = false

    @ObservationIgnored fileprivate var close: () -> Void = {}

    /// Closes the menu, e.g. before handing off to Calendar.app.
    func dismiss() { close() }
}

/// The menu bar item: the date as its title, and a standard `NSMenu` whose
/// first item hosts the SwiftUI calendar. Being a real menu, macOS draws,
/// positions and tracks it like its own menu bar menus.
final class StatusItemController: NSObject, NSMenuDelegate {
    private let ticker: DateTicker
    private let store: CalendarStore
    private let menuState = MenuState()

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let calendarView: MenuHostingView

    init(ticker: DateTicker, store: CalendarStore) {
        self.ticker = ticker
        self.store = store
        calendarView = MenuHostingView(rootView: AnyView(
            CalendarMenuView()
                .environment(ticker)
                .environment(store)
                .environment(menuState)
        ))
        super.init()

        menuState.close = { [weak self] in self?.menu.cancelTracking() }
        buildMenu()
        statusItem.autosaveName = "MencalDate"
        statusItem.menu = menu

        // The title depends on the date and the menu bar settings.
        Task { [weak self, ticker] in
            for await _ in Observations({ ticker.now }) { self?.updateLabel() }
        }
        _ = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateLabel() }
        }
    }

    // MARK: - Menu

    private func buildMenu() {
        menu.delegate = self
        menu.autoenablesItems = false

        let calendarItem = NSMenuItem()
        calendarItem.view = calendarView
        menu.addItem(calendarItem)
        menu.addItem(.separator())

        let open = NSMenuItem(title: String(localized: "Open Calendar"), action: #selector(openCalendar), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        // No target: the responder chain delivers it to the app delegate.
        menu.addItem(NSMenuItem(
            title: String(localized: "Settings…"),
            action: #selector(AppDelegate.showSettings(_:)),
            keyEquivalent: ""
        ))
    }

    func menuWillOpen(_ menu: NSMenu) {
        store.refreshAccess()
        ticker.refresh()
        menuState.isOpen = true
        // Settle the size before the menu measures its items; it's then held.
        calendarView.layoutSubtreeIfNeeded()
        calendarView.fitToContent()
        calendarView.isMenuOpen = true
    }

    func menuDidClose(_ menu: NSMenu) {
        menuState.isOpen = false
        calendarView.isMenuOpen = false
    }

    @objc private func openCalendar() {
        CalendarApp.open()
    }

    // MARK: - Menu bar text

    private func updateLabel() {
        guard let button = statusItem.button else { return }
        let text = MenuBarFormat(defaults: .standard).string(for: ticker.now)
        // Only touch the button when something changed: every assignment
        // re-lays out the item, and this runs on every UserDefaults write.
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Nothing visible to show: a symbol keeps the item clickable.
            guard button.image == nil else { return }
            button.title = ""
            button.image = NSImage(systemSymbolName: "calendar", accessibilityDescription: "Mencal")
        } else {
            if button.image != nil { button.image = nil }
            if button.title != text { button.title = text }
        }
    }
}

/// Hosts SwiftUI in a menu item, sized to its content.
///
/// An open NSMenu doesn't relayout when an item's view resizes; it scrolls
/// instead, hiding the top of the calendar. So resizing waits until the menu
/// is closed. The calendar keeps a constant height while open anyway.
private final class MenuHostingView: NSHostingView<AnyView> {
    var isMenuOpen = false {
        didSet { if !isMenuOpen { fitToContent() } }
    }

    required init(rootView: AnyView) {
        super.init(rootView: rootView)
        fitToContent()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        // After SwiftUI finishes this update pass.
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isMenuOpen else { return }
            self.fitToContent()
        }
    }

    func fitToContent() {
        let size = fittingSize
        guard size.width > 0, size.height > 0, size != frame.size else { return }
        setFrameSize(size)
    }
}
