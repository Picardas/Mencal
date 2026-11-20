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
    /// Fitted event text, kept for one opening.
    private var textFitter: TextFitter?
    /// True from menuWillOpen to menuDidClose.
    private var isTracking = false
    /// True once the calendar is built for the coming opening, so repeated
    /// `menuNeedsUpdate` calls don't build (and fetch) it again.
    private var isPrepared = false
    /// While the calendar view is first laid out; the event items are built
    /// once afterwards rather than as the view publishes.
    private var isPreparing = false

    init(ticker: DateTicker, store: CalendarStore) {
        self.ticker = ticker
        self.store = store
        super.init()

        buildMenu()
        statusItem.autosaveName = "MencalDate"
        statusItem.menu = menu

        // The title depends on the date and the menu bar settings. Both
        // tasks run on the main actor and last as long as the app.
        Task { [weak self, ticker] in
            for await _ in Observations({ ticker.now }) { self?.updateLabel() }
        }
        Task { [weak self] in
            for await _ in NotificationCenter.default.messages(of: UserDefaults.self, for: .didChange) {
                self?.updateLabel()
            }
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
        guard !isTracking, !isPrepared else { return }
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
        let gestures = CalendarGestures()
        let view = CalendarHostingView(rootView: CalendarMenuView()
            .environment(ticker).environment(store).environment(gestures)
            .environment(\.dismissMenu, dismiss).environment(\.showDayEvents, showDay))
        view.gestures = gestures
        // Lay out first, so the initial onChange (the fetch, which publishes
        // the selected day) has run, then measure. Only then stop the view
        // resizing itself: with no sizing options, fittingSize would be zero.
        isPreparing = true
        view.layoutSubtreeIfNeeded()
        isPreparing = false
        let size = view.fittingSize
        view.sizingOptions = []
        view.setFrameSize(size)
        calendarItem.view = view
        // Built once, now that the calendar is in the menu and the menu's
        // full height is known.
        textFitter = nil
        fitEventItems()
        isPrepared = true
        // If this preparation isn't followed by an opening (an accessibility
        // client reading the menu, say), drop the view. Default run-loop mode
        // doesn't run while a menu is tracking, so an opening goes first.
        perform(#selector(discardIfNotOpened), with: nil, afterDelay: 0, inModes: [.default])
    }

    @objc private func discardIfNotOpened() {
        guard !isTracking else { return }
        calendarItem.view = nil
        isPrepared = false
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
        isPrepared = false
        // Release the view and this opening's items while closed, but not
        // mid-action: closing can be triggered by one of the view's buttons.
        // The next opening can then never show this one's events.
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isTracking else { return }
            self.calendarItem.view = nil
            self.selection = nil
            self.textFitter = nil
            self.replaceEventItems(with: [])
        }
    }

    @objc private func openCalendar() {
        CalendarApp.open()
    }

    // MARK: - Event items

    /// Takes the day the calendar publishes. While the menu is open, NSMenu
    /// lays itself out again for new items; items that would come out the
    /// same aren't rebuilt.
    private func showEvents(for selection: DaySelection) {
        if let current = self.selection, current.showsSameItems(as: selection) { return }
        self.selection = selection
        guard !isPreparing else { return }
        fitEventItems()
    }

    /// Lists up to `maxShownEvents` events, fewer if the menu would be taller
    /// than the screen, so Open Calendar and Settings never scroll out of
    /// sight. The rest go in a "more events" submenu.
    private func fitEventItems() {
        guard let selection else { return replaceEventItems(with: []) }
        var limit = DayEventMenuItems.maxShownEvents
        setEventItems(for: selection, limit: limit)
        // Only once the calendar is in the menu is its height meaningful.
        guard calendarItem.view != nil, let available = screen?.visibleFrame.height else { return }
        while limit > 0, menu.size.height > available - Self.screenMargin {
            limit -= 1
            setEventItems(for: selection, limit: limit)
        }
    }

    /// The menu's screen: the status item's, or (while displays are being
    /// rearranged) the one under the pointer.
    private var screen: NSScreen? {
        statusItem.button?.window?.screen
            ?? NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
            ?? NSScreen.main
    }

    /// Room kept between the menu and the bottom of the screen.
    private static let screenMargin: CGFloat = 24

    private func setEventItems(for selection: DaySelection, limit: Int) {
        let fitter = textFitter ?? TextFitter(menuWidth: selection.width)
        textFitter = fitter
        replaceEventItems(with: DayEventMenuItems.items(
            for: selection,
            limit: limit,
            fitter: fitter,
            target: self,
            openEvent: #selector(openEvent(_:)),
            openCalendar: #selector(openCalendar)
        ))
    }

    private func replaceEventItems(with items: [NSMenuItem]) {
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
        // VoiceOver reads the full date, whatever the title shows.
        let spoken = ticker.now.formatted(date: .complete, time: .omitted)
        if button.accessibilityLabel() != spoken { button.setAccessibilityLabel(spoken) }
        // Only touch the button when something changed: every assignment
        // re-lays out the item, and this runs on every UserDefaults write.
        if !DisplayText.isVisible(text) {
            // Nothing visible to show (an empty or blank-looking custom
            // pattern): a symbol keeps the item clickable.
            guard button.image == nil else { return }
            button.title = ""
            button.image = NSImage(systemSymbolName: "calendar", accessibilityDescription: "Mencal")
        } else {
            if button.image != nil { button.image = nil }
            if button.title != text { button.title = text }
        }
    }
}
