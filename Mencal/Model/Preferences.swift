import Foundation

/// UserDefaults keys.
enum PrefKey {
    static let weekdayStyle = "menuBar.weekdayStyle"
    static let showDay = "menuBar.showDay"
    static let monthStyle = "menuBar.monthStyle"
    static let showYear = "menuBar.showYear"
    static let useCustomFormat = "menuBar.useCustomFormat"
    static let customFormat = "menuBar.customFormat"

    static let showWeekNumbers = "calendar.showWeekNumbers"
    static let firstWeekday = "calendar.firstWeekday"
    static let dimWeekends = "calendar.dimWeekends"
    static let showAllDayEvents = "calendar.showAllDayEvents"
    /// Restore the last earlier-events choice on open, instead of hiding them.
    static let rememberPastEvents = "calendar.rememberPastEvents"
    /// The last earlier-events choice.
    static let showPastEvents = "calendar.showPastEvents"
    static let hiddenCalendarIDs = "calendar.hiddenCalendarIDs"
}

/// Defaults for the calendar settings, shared by every `@AppStorage` that
/// reads them. Menu bar defaults are `MenuBarFormat.standard`.
enum PrefDefault {
    static let showWeekNumbers = false
    /// 0 follows the region; 1–7 is Sunday–Saturday.
    static let firstWeekday = 0
    static let dimWeekends = true
    static let showAllDayEvents = true
    static let rememberPastEvents = false
    static let showPastEvents = false
}

extension Calendar {
    /// The user's calendar, with the first weekday overridden if set (1–7).
    static func mencal(firstWeekday: Int) -> Calendar {
        var calendar = Calendar.autoupdatingCurrent
        if (1...7).contains(firstWeekday) {
            calendar.firstWeekday = firstWeekday
        }
        return calendar
    }
}
