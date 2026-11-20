import Foundation
import SwiftUI
import Testing
@testable import Mencal

private func gregorian(_ timeZone: String, firstWeekday: Int = 2) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: timeZone)!
    calendar.firstWeekday = firstWeekday
    return calendar
}

private func date(_ calendar: Calendar, _ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

private func event(_ start: Date, _ end: Date, allDay: Bool = false) -> CalendarEvent {
    CalendarEvent(
        id: UUID().uuidString, calendarItemIdentifier: "id", calendarID: "calendar",
        calendarTitle: "Calendar", title: "Event", start: start, end: end,
        isAllDay: allDay, location: nil, color: .blue
    )
}

/// The first day from 2024 on where midnight doesn't exist (clocks jump
/// from 23:59 to 01:00), in the calendar's time zone.
private func skippedMidnightDay(_ calendar: Calendar) -> Date? {
    var day = date(calendar, 2024, 1, 1)
    for _ in 0..<(366 * 3) {
        let start = calendar.startOfDay(for: day)
        if calendar.component(.hour, from: start) != 0 { return start }
        day = EventLayout.nextDay(after: start, calendar: calendar)
    }
    return nil
}

@Suite struct GridDaysTests {
    @Test func monthGridStartsOnTheFirstWeekdayAndCoversTheMonth() {
        let calendar = gregorian("Europe/London", firstWeekday: 2) // Monday
        let days = EventLayout.gridDays(for: date(calendar, 2026, 11, 15), calendar: calendar)
        #expect(days.count == 42)
        #expect(days.first == date(calendar, 2026, 10, 26)) // a Monday
        #expect(days.contains(date(calendar, 2026, 11, 1)))
        #expect(days.contains(date(calendar, 2026, 11, 30)))
    }

    @Test func daysAreConsecutiveStartsOfDayAcrossASkippedMidnight() throws {
        let calendar = gregorian("America/Santiago")
        let skipped = try #require(skippedMidnightDay(calendar))
        let days = EventLayout.gridDays(for: skipped, calendar: calendar)
        #expect(days.count == 42)
        #expect(days.contains(skipped))
        for (day, next) in zip(days, days.dropFirst()) {
            #expect(day == calendar.startOfDay(for: day))
            #expect(next == EventLayout.nextDay(after: day, calendar: calendar))
        }
    }
}

@Suite struct WeekNumberTests {
    /// A US-style region: weeks start on Sunday, week 1 contains 1 January.
    private var usRegion: Calendar {
        var calendar = gregorian("America/New_York", firstWeekday: 1)
        calendar.minimumDaysInFirstWeek = 1
        return calendar
    }

    /// An ISO-style region: weeks start on Monday, week 1 has 4+ days.
    private var isoRegion: Calendar {
        var calendar = gregorian("Europe/London", firstWeekday: 2)
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    @Test func rowsFollowTheRegionsWeeksWhenTheStartDayIsOverridden() {
        let region = usRegion
        var overridden = region
        overridden.firstWeekday = 2 // "Week starts on" Monday
        let rows = EventLayout.gridDays(for: date(region, 2027, 1, 15), calendar: overridden)
        // First row: Mon 28 Dec 2026 – Sun 3 Jan 2027. Its region-start day
        // is Sunday 3 Jan, which the US region counts as week 2 of 2027.
        let first = EventLayout.weekNumber(ofRow: rows[0..<7], regionCalendar: region)
        #expect(first == region.component(.weekOfYear, from: date(region, 2027, 1, 3)))
        #expect(first == 2)
    }

    @Test func rowsMatchTheRegionWhenNotOverridden() {
        let region = isoRegion
        let rows = EventLayout.gridDays(for: date(region, 2027, 1, 15), calendar: region)
        for start in stride(from: 0, to: 42, by: 7) {
            let expected = region.component(.weekOfYear, from: rows[start])
            #expect(EventLayout.weekNumber(ofRow: rows[start..<start + 7], regionCalendar: region) == expected)
        }
        // 28 Dec 2026 is in ISO week 53 of 2026.
        #expect(EventLayout.weekNumber(ofRow: rows[0..<7], regionCalendar: region) == 53)
    }
}

@Suite struct GroupingTests {
    let calendar = gregorian("Europe/London")

    private func days(from start: Date, count: Int) -> [Date] {
        var result = [start]
        while result.count < count {
            result.append(EventLayout.nextDay(after: result.last!, calendar: calendar))
        }
        return result
    }

    @Test func multiDayEventAppearsOnEachDayItOverlaps() {
        let grid = days(from: date(calendar, 2026, 11, 16), count: 7)
        let end = EventLayout.nextDay(after: grid.last!, calendar: calendar)
        let hackathon = event(date(calendar, 2026, 11, 17, 15), date(calendar, 2026, 11, 19, 11))
        let grouped = EventLayout.group([hackathon], dayStarts: grid, end: end)
        #expect(grouped.keys.sorted() == [grid[1], grid[2], grid[3]])
    }

    @Test func eventEndingAtMidnightStaysOnItsDay() {
        let grid = days(from: date(calendar, 2026, 11, 16), count: 3)
        let end = EventLayout.nextDay(after: grid.last!, calendar: calendar)
        let late = event(date(calendar, 2026, 11, 16, 22), date(calendar, 2026, 11, 17))
        let grouped = EventLayout.group([late], dayStarts: grid, end: end)
        #expect(grouped.keys.sorted() == [grid[0]])
    }

    @Test func zeroLengthEventAtMidnightBelongsToThatDay() {
        let grid = days(from: date(calendar, 2026, 11, 16), count: 3)
        let end = EventLayout.nextDay(after: grid.last!, calendar: calendar)
        let reminder = event(grid[1], grid[1])
        let grouped = EventLayout.group([reminder], dayStarts: grid, end: end)
        #expect(grouped.keys.sorted() == [grid[1]])
    }

    @Test func eventsOutsideTheGridAreIgnored() {
        let grid = days(from: date(calendar, 2026, 11, 16), count: 3)
        let end = EventLayout.nextDay(after: grid.last!, calendar: calendar)
        let before = event(date(calendar, 2026, 11, 10, 9), date(calendar, 2026, 11, 10, 10))
        let after = event(end, end.addingTimeInterval(3600))
        #expect(EventLayout.group([before, after], dayStarts: grid, end: end).isEmpty)
    }

    @Test func eachDayIsCappedButKeepsItsFullCount() throws {
        let grid = days(from: date(calendar, 2026, 11, 16), count: 1)
        let end = EventLayout.nextDay(after: grid[0], calendar: calendar)
        let events = (0..<5).map { _ in event(date(calendar, 2026, 11, 16, 9), date(calendar, 2026, 11, 16, 10)) }
        let day = try #require(EventLayout.group(events, dayStarts: grid, end: end, cap: 3)[grid[0]])
        #expect(day.events.count == 3)
        #expect(day.count == 5)
    }

    @Test func spanningEventsOnASkippedMidnightLandOnGridDays() throws {
        let santiago = gregorian("America/Santiago")
        let skipped = try #require(skippedMidnightDay(santiago))
        let grid = EventLayout.gridDays(for: skipped, calendar: santiago)
        let end = EventLayout.nextDay(after: grid.last!, calendar: santiago)
        let trip = event(grid[0], grid[41], allDay: true)
        let grouped = EventLayout.group([trip], dayStarts: grid, end: end)
        #expect(Set(grouped.keys).isSubset(of: Set(grid)))
        #expect(grouped.count == 41)
    }
}

@Suite struct DayTextTests {
    @Test func tomorrowIsOneDayAwayEvenAfterASkippedMidnight() throws {
        let calendar = gregorian("America/Santiago")
        let before = try #require(calendar.date(byAdding: .day, value: -1, to: skippedMidnightDay(calendar)!))
        let today = calendar.startOfDay(for: before)
        let tomorrow = EventLayout.nextDay(after: today, calendar: calendar)
        #expect(EventLayout.dayOffset(from: today, to: tomorrow, calendar: calendar) == 1)
        // The skipped-midnight day itself is only 23 hours long.
        let after = EventLayout.nextDay(after: tomorrow, calendar: calendar)
        #expect(EventLayout.dayOffset(from: tomorrow, to: after, calendar: calendar) == 1)
    }

    @Test func eventEndingAtMidnightShowsJustTimes() {
        let calendar = gregorian("Europe/London")
        let day = date(calendar, 2026, 11, 20)
        let late = event(date(calendar, 2026, 11, 20, 22), date(calendar, 2026, 11, 21))
        let locale = Locale(identifier: "en_GB")
        let text = EventLayout.timeText(for: late, on: day, calendar: calendar, locale: locale)
        let time = Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        // Just the two times, no dates (the locale decides "0:00" vs "00:00").
        #expect(text == "\(late.start.formatted(time)) – \(late.end.formatted(time))")
    }

    @Test func timedEventFillingTheDaySaysAllDay() {
        let calendar = gregorian("Europe/London")
        let day = date(calendar, 2026, 11, 20)
        let wholeDay = event(day, date(calendar, 2026, 11, 21))
        #expect(EventLayout.timeText(for: wholeDay, on: day, calendar: calendar) == String(localized: "All-day"))
    }

    @Test func singleAllDayEventSaysAllDay() {
        let calendar = gregorian("Europe/London")
        let day = date(calendar, 2026, 11, 20)
        let birthday = event(day, date(calendar, 2026, 11, 20, 23, 59), allDay: true)
        #expect(EventLayout.timeText(for: birthday, on: day, calendar: calendar) == String(localized: "All-day"))
    }
}
