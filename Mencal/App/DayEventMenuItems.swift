import AppKit
import SwiftUI

/// Builds the selected day's events as standard menu items: a section
/// header, one item per event (title, a time and location subtitle, and a
/// dot in the calendar's colour). Today's finished events, and events that
/// don't fit, are in submenus, which scroll on their own if they need to.
@MainActor
enum DayEventMenuItems {
    /// Upcoming events listed in the menu itself; the rest are in a submenu.
    static let maxShownEvents = 8

    /// Every event item sends `openEvent`; its `representedObject` is the
    /// `CalendarEvent`. At most `limit` upcoming events are listed.
    static func items(
        for selection: DaySelection,
        limit: Int = maxShownEvents,
        target: AnyObject,
        openEvent: Selector,
        openCalendar: Selector
    ) -> [NSMenuItem] {
        guard let dayEvents = selection.events else { return [] }
        let isToday = selection.day == selection.today
        let events = dayEvents.events
        let past = isToday ? events.filter { $0.end <= selection.now } : []
        let upcoming = isToday ? events.filter { $0.end > selection.now } : events
        let shown = upcoming.prefix(max(limit, 0))
        let overflow = upcoming.dropFirst(shown.count)
        // Past the per-day cap, so never read; only Calendar has them.
        let beyondCap = dayEvents.count - events.count

        let fitter = TextFitter(width: selection.width)
        var dots: [String: NSImage] = [:]
        func eventItem(_ event: CalendarEvent) -> NSMenuItem {
            let item = NSMenuItem(title: fitter.title(event.title), action: openEvent, keyEquivalent: "")
            item.target = target
            item.representedObject = event
            let time = EventLayout.timeText(for: event, on: selection.day, calendar: selection.calendar)
            item.subtitle = fitter.subtitle([time, event.location].compactMap(\.self).joined(separator: " · "))
            item.image = dots[event.calendarID] ?? {
                let dot = dotImage(NSColor(event.color), description: event.calendarTitle)
                dots[event.calendarID] = dot
                return dot
            }()
            // From macOS 27, menus hide item images unless asked; the dot
            // carries the calendar's colour, so it's always shown.
            if #available(macOS 27, *) {
                item.preferredImageVisibility = .visible
            }
            item.toolTip = event.calendarTitle
            return item
        }

        var items = [NSMenuItem.sectionHeader(title: headerTitle(for: selection))]

        func submenuItem(_ title: String, _ submenuItems: [NSMenuItem]) -> NSMenuItem {
            let submenu = NSMenu()
            submenu.autoenablesItems = false
            submenu.items = submenuItems
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.submenu = submenu
            return item
        }

        func calendarLinkItem() -> NSMenuItem {
            let item = NSMenuItem(title: String(localized: "\(beyondCap) more events in Calendar"), action: openCalendar, keyEquivalent: "")
            item.target = target
            return item
        }

        if !past.isEmpty {
            items.append(submenuItem(String(localized: "\(past.count) earlier events"), past.map(eventItem)))
        }

        if upcoming.isEmpty {
            let empty = NSMenuItem(
                title: events.isEmpty ? String(localized: "No events") : String(localized: "No more events today"),
                action: nil,
                keyEquivalent: ""
            )
            empty.isEnabled = false
            items.append(empty)
        } else {
            items += shown.map(eventItem)
        }

        if !overflow.isEmpty {
            var more = overflow.map(eventItem)
            if beyondCap > 0 { more += [.separator(), calendarLinkItem()] }
            items.append(submenuItem(String(localized: "\(overflow.count + beyondCap) more events"), more))
        } else if beyondCap > 0 {
            items.append(calendarLinkItem())
        }
        return items
    }

    /// "Today · Friday 20 November", or just the date beyond tomorrow.
    private static func headerTitle(for selection: DaySelection) -> String {
        let date = selection.day.formatted(
            Date.FormatStyle(calendar: selection.calendar, timeZone: selection.calendar.timeZone)
                .weekday(.wide).day().month(.wide)
        )
        let offset = EventLayout.dayOffset(from: selection.today, to: selection.day, calendar: selection.calendar)
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

    /// A small filled circle, like Calendar.app's, in a standard image slot.
    private static func dotImage(_ color: NSColor, description: String) -> NSImage {
        let image = NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 2, dy: 2)).fill()
            return true
        }
        image.accessibilityDescription = description
        return image
    }
}

/// Shortens event text to the calendar's width, so a long title can't widen
/// the menu past the calendar. Text is set as a plain string, never parsed.
private struct TextFitter {
    /// Room left after the menu's image column and insets.
    private let titleWidth: CGFloat
    private let titleFont = NSFont.menuFont(ofSize: 0)
    private let subtitleFont = NSFont.menuFont(ofSize: NSFont.smallSystemFontSize)

    /// Hostile feeds can carry huge titles; nothing longer is measured.
    private static let maxCharacters = 200

    init(width: CGFloat) {
        titleWidth = max(width - 64, 80)
    }

    func title(_ text: String) -> String { fit(text, font: titleFont) }
    func subtitle(_ text: String) -> String { fit(text, font: subtitleFont) }

    private func fit(_ text: String, font: NSFont) -> String {
        // One line: newlines and other control characters become spaces.
        let flat = String(String.UnicodeScalarView(text.prefix(Self.maxCharacters).unicodeScalars.map {
            $0.properties.generalCategory == .control || $0.properties.isWhitespace ? " " : $0
        }))
        .trimmingCharacters(in: .whitespaces)
        guard width(of: flat, font: font) > titleWidth else { return flat }

        // The longest prefix (in characters) that fits with an ellipsis.
        let characters = Array(flat)
        var low = 0
        var high = characters.count
        while low < high {
            let mid = (low + high + 1) / 2
            if width(of: String(characters[..<mid]) + "…", font: font) <= titleWidth {
                low = mid
            } else {
                high = mid - 1
            }
        }
        return String(characters[..<low]).trimmingCharacters(in: .whitespaces) + "…"
    }

    private func width(of text: String, font: NSFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width
    }
}
