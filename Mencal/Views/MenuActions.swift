import SwiftUI

/// Closes Mencal's menu, e.g. before handing off to Calendar.app.
/// StatusItemController supplies it through the environment.
struct DismissMenuAction {
    let run: () -> Void

    func callAsFunction() { run() }
}

/// The selected day and its events, which StatusItemController shows as
/// native menu items below the calendar.
struct DaySelection {
    let day: Date
    let today: Date
    let now: Date
    let calendar: Calendar
    /// Nil when calendar access isn't granted.
    let events: DayEvents?
    /// The calendar view's width, which event titles are shortened to fit.
    let width: CGFloat

    /// Today's finished events are "earlier"; other days show everything as
    /// upcoming.
    var split: (past: [CalendarEvent], upcoming: [CalendarEvent]) {
        let events = events?.events ?? []
        guard day == today else { return ([], events) }
        return (events.filter { $0.end <= now }, events.filter { $0.end > now })
    }

    /// Whether this shows exactly the same menu items as `other`, so the
    /// menu needn't rebuild them (and reset the highlight, close an open
    /// submenu or shift rows under the pointer) after a sync that changed
    /// nothing visible here.
    func showsSameItems(as other: DaySelection) -> Bool {
        day == other.day && today == other.today && width == other.width
            && calendar == other.calendar && events == other.events
            && split.past.count == other.split.past.count
    }
}

/// Hands the selected day to StatusItemController, which supplies it
/// through the environment.
struct ShowDayEventsAction {
    let run: (DaySelection) -> Void

    func callAsFunction(_ selection: DaySelection) { run(selection) }
}

extension EnvironmentValues {
    @Entry var dismissMenu = DismissMenuAction(run: {})
    @Entry var showDayEvents = ShowDayEventsAction(run: { _ in })
}
