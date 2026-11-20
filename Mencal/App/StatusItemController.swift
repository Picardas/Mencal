import AppKit
import Observation
import SwiftUI

/// Shared between the status item and the SwiftUI calendar in its menu.
@Observable
final class MenuState {
    /// True from preparing the menu until it closes. The calendar resets to
    /// today when built and only fetches events while this is true.
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
    private let calendarItem = NSMenuItem()
    /// True from menuWillOpen to menuDidClose.
    private var isTracking = false
    /// When the calendar was last built, so back-to-back `menuNeedsUpdate`
    /// calls for one opening don't build (and fetch) it twice.
    private var preparedAt = Date.distantPast

    init(ticker: DateTicker, store: CalendarStore) {
        self.ticker = ticker
        self.store = store
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

    /// NSMenu calls this before it measures its items, so the calendar is
    /// built here. It can also be called without the menu opening; a later
    /// opening then simply rebuilds.
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard !isTracking, Date().timeIntervalSince(preparedAt) > 1 else { return }
        prepareCalendar()
    }

    func menuWillOpen(_ menu: NSMenu) {
        isTracking = true
        if calendarItem.view == nil { prepareCalendar() }
    }

    /// Builds the calendar view fresh for each opening. A SwiftUI view that
    /// was taken out of a window (as NSMenu does on close) defers its
    /// updates, so a reused one would be measured showing the previous
    /// opening. A new view renders today's state on its first layout, so its
    /// size is exact; NSMenu then holds that size while open.
    private func prepareCalendar() {
        store.refreshAccess()
        ticker.refresh()
        menuState.isOpen = true
        let view = NSHostingView(rootView: CalendarMenuView()
            .environment(ticker).environment(store).environment(menuState))
        // Lay out first so the initial onChange (reset, fetch) has run, then
        // measure. Only then stop the view from resizing itself: with no
        // sizing options, fittingSize would be zero.
        view.layoutSubtreeIfNeeded()
        let size = view.fittingSize
        view.sizingOptions = []
        view.setFrameSize(size)
        calendarItem.view = view
        preparedAt = Date()
    }

    /// The menu has no key equivalents, so key presses never need to search
    /// it (or prepare it via `menuNeedsUpdate`).
    func menuHasKeyEquivalent(
        _ menu: NSMenu, for event: NSEvent,
        target: AutoreleasingUnsafeMutablePointer<AnyObject?>,
        action: UnsafeMutablePointer<Selector?>
    ) -> Bool {
        false
    }

    func menuDidClose(_ menu: NSMenu) {
        isTracking = false
        preparedAt = .distantPast
        menuState.isOpen = false
        // Release the view while closed, but not mid-action: closing can be
        // triggered by one of its own buttons.
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isTracking else { return }
            self.calendarItem.view = nil
        }
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

