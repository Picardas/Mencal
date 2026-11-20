import AppKit
import Observation
import SwiftUI

/// The menu bar item: the date as its title, and a standard `NSMenu` whose
/// first item hosts the SwiftUI calendar, followed by the selected day's
/// events as ordinary menu items. Being a real menu, macOS draws, positions
/// and tracks it like its own menu bar menus.
final class StatusItemController: NSObject, NSMenuDelegate {
    private let ticker: DateTicker
    private let store: CalendarStore

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let calendarItem = NSMenuItem()
    /// The selected day's items, between the calendar and the separator
    /// above Open Calendar.
    private var eventItems: [NSMenuItem] = []
    private let eventsEndSeparator = NSMenuItem.separator()
    /// The day the event items show, kept so they can be refitted.
    private var selection: DaySelection?
    /// True from menuWillOpen to menuDidClose.
    private var isTracking = false
    /// When the calendar was last built, so back-to-back `menuNeedsUpdate`
    /// calls for one opening don't build (and fetch) it twice.
    private var preparedAt = Date.distantPast

    init(ticker: DateTicker, store: CalendarStore) {
        self.ticker = ticker
        self.store = store
        super.init()

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
        menu.addItem(eventsEndSeparator)

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
        let dismiss = DismissMenuAction { [weak self] in self?.menu.cancelTracking() }
        let showDay = ShowDayEventsAction { [weak self] in self?.showEvents(for: $0) }
        let view = NSHostingView(rootView: CalendarMenuView()
            .environment(ticker).environment(store)
            .environment(\.dismissMenu, dismiss).environment(\.showDayEvents, showDay))
        // Lay out first so the initial onChange (the fetch, which also
        // builds the event items) has run, then measure. Only then stop the view from resizing itself: with no
        // sizing options, fittingSize would be zero.
        view.layoutSubtreeIfNeeded()
        let size = view.fittingSize
        view.sizingOptions = []
        view.setFrameSize(size)
        calendarItem.view = view
        // The items were built before the calendar was in the menu; check
        // again now that the menu's full height is known.
        fitEventItems()
        preparedAt = Date()
        // If this preparation isn't followed by an opening (an accessibility
        // client reading the menu, say), drop the view. Default run-loop mode
        // doesn't run while a menu is tracking, so an opening goes first.
        perform(#selector(discardIfNotOpened), with: nil, afterDelay: 0, inModes: [.default])
    }

    @objc private func discardIfNotOpened() {
        guard !isTracking else { return }
        calendarItem.view = nil
        preparedAt = .distantPast
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

    // MARK: - Event items

    /// Replaces the event items with the selected day's. Runs while the menu
    /// is being prepared and again whenever another day is picked in the
    /// open menu; NSMenu lays itself out again for the new items.
    private func showEvents(for selection: DaySelection) {
        self.selection = selection
        fitEventItems()
    }

    /// Lists up to `maxShownEvents` events, fewer if the menu would be taller
    /// than the screen, so Open Calendar and Settings never scroll out of
    /// sight. The rest go in a "more events" submenu.
    private func fitEventItems() {
        guard let selection else { return }
        var limit = DayEventMenuItems.maxShownEvents
        setEventItems(for: selection, limit: limit)
        // Only once the calendar is in the menu is its height meaningful.
        guard calendarItem.view != nil,
              let available = statusItem.button?.window?.screen?.visibleFrame.height
        else { return }
        while limit > 0, menu.size.height > available - Self.screenMargin {
            limit -= 1
            setEventItems(for: selection, limit: limit)
        }
    }

    /// Room kept between the menu and the bottom of the screen.
    private static let screenMargin: CGFloat = 24

    private func setEventItems(for selection: DaySelection, limit: Int) {
        let items = DayEventMenuItems.items(
            for: selection,
            limit: limit,
            target: self,
            openEvent: #selector(openEvent(_:)),
            openCalendar: #selector(openCalendar)
        )
        eventItems.forEach(menu.removeItem)
        var index = menu.index(of: eventsEndSeparator)
        for item in items {
            menu.insertItem(item, at: index)
            index += 1
        }
        eventItems = items
        // With no items (no access), one separator is enough.
        eventsEndSeparator.isHidden = items.isEmpty
    }

    @objc private func openEvent(_ sender: NSMenuItem) {
        guard let event = sender.representedObject as? CalendarEvent else { return }
        CalendarApp.show(event)
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

