import AppKit

/// Builds the selected day's events as standard menu items: a section
/// header, one item per event (title, a time and location subtitle, and a
/// bar in the calendar's colour beside them, as Calendar.app marks events). Today's finished events, and events that
/// don't fit, are in submenus, which are filled when opened and scroll on
/// their own if they need to.
@MainActor
enum DayEventMenuItems {
    /// Upcoming events listed in the menu itself; the rest are in a submenu.
    static let maxShownEvents = 8

    /// Every event item sends `openEvent`; its `representedObject` is the
    /// `CalendarEvent`. At most `limit` upcoming events are listed.
    static func items(
        for selection: DaySelection,
        limit: Int = maxShownEvents,
        fitter: TextFitter,
        target: AnyObject,
        openEvent: Selector,
        openCalendar: Selector
    ) -> [NSMenuItem] {
        guard let dayEvents = selection.events else { return [] }
        let split = selection.split
        let shown = split.upcoming.prefix(max(limit, 0))
        let overflow = Array(split.upcoming.dropFirst(shown.count))
        // Past the per-day cap, so never read; only Calendar has them.
        let beyondCap = dayEvents.count - dayEvents.events.count

        func eventItem(_ event: CalendarEvent) -> NSMenuItem {
            let item = NSMenuItem(title: fitter.title(event.title), action: openEvent, keyEquivalent: "")
            item.target = target
            item.representedObject = event
            let time = EventLayout.timeText(for: event, on: selection.day, calendar: selection.calendar)
            item.subtitle = fitter.subtitle([time, event.location].compactMap(\.self).joined(separator: " · "))
            item.image = barImage(event.color, description: event.calendarTitle)
            // From macOS 27, menus hide item images unless asked; the bar
            // carries the calendar's colour, so it's always shown.
            if #available(macOS 27, *) {
                item.preferredImageVisibility = .visible
            }
            item.toolTip = event.calendarTitle
            return item
        }

        func calendarLinkItem() -> NSMenuItem {
            let item = NSMenuItem(title: String(localized: "\(beyondCap) more events in Calendar"), action: openCalendar, keyEquivalent: "")
            item.target = target
            return item
        }

        var items = [NSMenuItem.sectionHeader(title: headerTitle(for: selection))]

        if !split.past.isEmpty {
            items.append(LazySubmenu.item(title: String(localized: "\(split.past.count) earlier events")) {
                split.past.map(eventItem)
            })
        }

        if split.upcoming.isEmpty {
            let empty = NSMenuItem(
                title: dayEvents.events.isEmpty ? String(localized: "No events") : String(localized: "No more events today"),
                action: nil,
                keyEquivalent: ""
            )
            empty.isEnabled = false
            items.append(empty)
        } else {
            items += shown.map(eventItem)
        }

        if !overflow.isEmpty {
            items.append(LazySubmenu.item(title: String(localized: "\(overflow.count + beyondCap) more events")) {
                var more = overflow.map(eventItem)
                if beyondCap > 0 { more += [.separator(), calendarLinkItem()] }
                return more
            })
        } else if beyondCap > 0 {
            items.append(calendarLinkItem())
        }
        return items
    }

    /// "Today · Friday 20 November", or just the date beyond tomorrow, with
    /// the year when it isn't this year.
    private static func headerTitle(for selection: DaySelection) -> String {
        let calendar = selection.calendar
        var style = Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone).weekday(.wide).day().month(.wide)
        if !calendar.isDate(selection.day, equalTo: selection.today, toGranularity: .year) {
            style = style.year()
        }
        let date = selection.day.formatted(style)
        let offset = EventLayout.dayOffset(from: selection.today, to: selection.day, calendar: calendar)
        guard abs(offset) <= 1 else { return date }
        let relative = relativeFormatter.localizedString(from: DateComponents(day: offset))
        return String(localized: "\(relative) · \(date)")
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateTimeStyle = .named
        formatter.formattingContext = .beginningOfSentence
        return formatter
    }()

    /// A small filled circle in the calendar's colour, like Calendar.app's.
    /// A rounded bar in the calendar's colour, as tall as an item's title
    /// and subtitle, so it runs the length of the event like Calendar.app's.
    private static func barImage(_ color: CGColor, description: String) -> NSImage {
        let image = NSImage(size: barSize, flipped: false) { rect in
            (NSColor(cgColor: color) ?? .controlAccentColor).setFill()
            NSBezierPath(roundedRect: rect, xRadius: rect.width / 2, yRadius: rect.width / 2).fill()
            return true
        }
        image.accessibilityDescription = description
        return image
    }

    /// The two text lines' height, so the bar doesn't make items taller.
    private static let barSize: NSSize = {
        func lineHeight(_ font: NSFont) -> CGFloat { ceil(font.ascender - font.descender + font.leading) }
        let height = lineHeight(.menuFont(ofSize: 0)) + lineHeight(.menuFont(ofSize: NSFont.smallSystemFontSize))
        return NSSize(width: 3, height: height - 2)
    }()
}

/// A submenu whose items are built when it's about to open, so a day with a
/// hundred events doesn't build items nobody looks at. The item keeps it
/// (as its `representedObject`), since a menu's delegate is weak.
private final class LazySubmenu: NSObject, NSMenuDelegate {
    private let build: () -> [NSMenuItem]

    private init(build: @escaping () -> [NSMenuItem]) {
        self.build = build
    }

    static func item(title: String, build: @escaping () -> [NSMenuItem]) -> NSMenuItem {
        let lazy = LazySubmenu(build: build)
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        submenu.delegate = lazy
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        item.representedObject = lazy
        return item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu.items.isEmpty else { return }
        menu.items = build()
    }
}

/// Shortens event text to the calendar's width, so a long title can't widen
/// the menu past the calendar. Text arrives already on one line and capped
/// (see `DisplayText`); it's set as a plain string, never parsed. Results
/// are kept for the menu's opening, since the same text is fitted again
/// whenever the items are rebuilt.
@MainActor
final class TextFitter {
    /// Room left after the menu's image column and insets.
    private let width: CGFloat
    private let titleFont = NSFont.menuFont(ofSize: 0)
    private let subtitleFont = NSFont.menuFont(ofSize: NSFont.smallSystemFontSize)
    private var fitted: [String: String] = [:]

    init(menuWidth: CGFloat) {
        width = max(menuWidth - 64, 80)
    }

    func title(_ text: String) -> String { fit(text, font: titleFont, key: "t" + text) }
    func subtitle(_ text: String) -> String { fit(text, font: subtitleFont, key: "s" + text) }

    private func fit(_ text: String, font: NSFont, key: String) -> String {
        if let result = fitted[key] { return result }
        let result = shortened(text, font: font)
        fitted[key] = result
        return result
    }

    private func shortened(_ text: String, font: NSFont) -> String {
        guard measure(text, font: font) > width else { return text }
        // The longest prefix (in characters) that fits with an ellipsis.
        let characters = Array(text.hasSuffix("…") ? String(text.dropLast()) : text)
        var low = 0
        var high = characters.count
        while low < high {
            let mid = (low + high + 1) / 2
            if measure(String(characters[..<mid]) + "…", font: font) <= width {
                low = mid
            } else {
                high = mid - 1
            }
        }
        return String(characters[..<low]).trimmingCharacters(in: .whitespaces) + "…"
    }

    private func measure(_ text: String, font: NSFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width
    }
}
