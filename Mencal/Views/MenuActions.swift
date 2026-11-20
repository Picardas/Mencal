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
