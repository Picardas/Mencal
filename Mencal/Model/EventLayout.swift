import Foundation

/// One day's events, capped so a huge feed can't make the menu lay out
/// thousands of rows. `count` is the full number.
struct DayEvents {
    private(set) var events: [CalendarEvent] = []
    private(set) var count = 0

    mutating func append(_ event: CalendarEvent, cap: Int) {
        count += 1
        if events.count < cap { events.append(event) }
    }
}

/// The calendar's date logic, kept free of views so it can be tested.
enum EventLayout {
    /// Rows shown per day; the rest are a click away in Calendar.app.
    static let maxEventsPerDay = 100

    /// The 42 days shown for `month`, each at the start of its day.
    static func gridDays(for month: Date, calendar: Calendar) -> [Date] {
        guard let monthStart = calendar.dateInterval(of: .month, for: month)?.start,
              let gridStart = calendar.dateInterval(of: .weekOfYear, for: monthStart)?.start
        else { return [] }
        var days: [Date] = []
        var day = calendar.startOfDay(for: gridStart)
        for _ in 0..<42 {
            days.append(day)
            // A day's interval ends at the next day's start, even where
            // midnight is skipped for daylight saving.
            guard let next = calendar.dateInterval(of: .day, for: day)?.end else { break }
            day = next
        }
        return days
    }

    /// The week number shown beside a grid row: the region's official week
    /// number of the row's region-start day (the day the region begins its
    /// weeks on). Every row of 7 days contains exactly one such day, so this
    /// matches Calendar.app even when "Week starts on" is overridden.
    static func weekNumber(ofRow row: some Collection<Date>, regionCalendar: Calendar) -> Int? {
        guard let anchor = row.first(where: {
            regionCalendar.component(.weekday, from: $0) == regionCalendar.firstWeekday
        }) ?? row.first else { return nil }
        return regionCalendar.component(.weekOfYear, from: anchor)
    }

    /// The start of the day after `day`.
    static func nextDay(after day: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: .day, for: day)?.end ?? day.addingTimeInterval(24 * 60 * 60)
    }

    /// Groups `events` into the days they overlap. `dayStarts` must be
    /// consecutive day starts; the last day ends at `end`. Each event's first
    /// and last day are found by binary search rather than by stepping
    /// through the calendar, which is what made huge feeds slow.
    static func group(_ events: [CalendarEvent], dayStarts: [Date], end: Date, cap: Int = maxEventsPerDay) -> [Date: DayEvents] {
        guard let firstStart = dayStarts.first else { return [:] }
        var days = [DayEvents](repeating: DayEvents(), count: dayStarts.count)
        for event in events where event.start < end && (event.end > firstStart || event.start >= firstStart) {
            let first = max(0, countOf(dayStarts) { $0 <= max(event.start, firstStart) } - 1)
            // A zero-length event still belongs to its start day.
            let last = max(first, countOf(dayStarts) { $0 < event.end } - 1)
            for index in first...last {
                days[index].append(event, cap: cap)
            }
        }
        var result: [Date: DayEvents] = [:]
        for (day, dayEvents) in zip(dayStarts, days) where dayEvents.count > 0 {
            result[day] = dayEvents
        }
        return result
    }

    /// How many leading elements of the sorted `dates` satisfy `predicate`.
    private static func countOf(_ dates: [Date], where predicate: (Date) -> Bool) -> Int {
        var low = 0
        var high = dates.count
        while low < high {
            let mid = (low + high) / 2
            if predicate(dates[mid]) { low = mid + 1 } else { high = mid }
        }
        return low
    }

    /// Whole days from `from` to `to`, by calendar day rather than elapsed
    /// time, so a 23-hour day (skipped midnight) still counts as one.
    static func dayOffset(from: Date, to: Date, calendar: Calendar) -> Int {
        guard let a = calendar.ordinality(of: .day, in: .era, for: from),
              let b = calendar.ordinality(of: .day, in: .era, for: to)
        else { return 0 }
        return b - a
    }

    /// The time line under an event's title, for the given day. Times use the
    /// calendar's time zone; `locale` is a parameter so tests can pin it.
    static func timeText(
        for event: CalendarEvent,
        on day: Date,
        calendar: Calendar,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        let dayEnd = nextDay(after: day, calendar: calendar)
        let zone = calendar.timeZone
        let time = Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar, timeZone: zone)

        if event.isAllDay {
            // EventKit ends all-day events at 23:59:59 on their last day.
            let lastDay = calendar.startOfDay(for: event.end.addingTimeInterval(-1))
            guard lastDay > calendar.startOfDay(for: event.start) else { return String(localized: "All-day") }
            let range = (event.start..<lastDay).formatted(
                Date.IntervalFormatStyle(locale: locale, calendar: calendar, timeZone: zone).day().month(.abbreviated)
            )
            return String(localized: "All-day · \(range)")
        }

        switch (event.start < day, event.end > dayEnd) {
        case (true, true):
            return String(localized: "All-day")
        case (true, false):
            return String(localized: "Until \(event.end.formatted(time))")
        case (false, true):
            let ends = event.end.formatted(
                Date.FormatStyle(locale: locale, calendar: calendar, timeZone: zone)
                    .day().month(.abbreviated).hour().minute()
            )
            return String(localized: "\(event.start.formatted(time)) – \(ends)")
        case (false, false):
            if event.start == event.end { return event.start.formatted(time) }
            // A timed event filling exactly this day.
            if event.start == day && event.end == dayEnd { return String(localized: "All-day") }
            // Ending exactly at midnight spans two dates, which the interval
            // style would spell out in full; show just the times.
            if event.end == dayEnd {
                return String(localized: "\(event.start.formatted(time)) – \(event.end.formatted(time))")
            }
            return (event.start..<event.end).formatted(
                Date.IntervalFormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar, timeZone: zone)
            )
        }
    }
}
