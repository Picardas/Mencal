import AppKit
import Foundation
import Testing
@testable import Mencal

@Suite struct DisplayTextTests {
    @Test func linesAreFlattenedAndCollapsed() {
        #expect(DisplayText.line("  Board\n\n meeting\t ") == "Board meeting")
    }

    @Test func leadingSpacesDontUseUpTheCap() {
        let title = String(repeating: " ", count: 500) + "Board meeting"
        #expect(DisplayText.line(title) == "Board meeting")
    }

    @Test func bidiOverridesAreDroppedButJoinersKept() {
        #expect(DisplayText.line("abc\u{202E}def\u{202C}") == "abcdef")
        let family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}"
        #expect(DisplayText.line(family) == family)
    }

    @Test func heavyCombiningMarksAreCappedByScalar() {
        let zalgo = String(repeating: "a" + String(repeating: "\u{0301}", count: 1000), count: 50)
        let line = DisplayText.line(zalgo)
        // The cap, plus the "…" that says something was cut.
        #expect(line.unicodeScalars.count == DisplayText.maxEventTextLength + 1)
        #expect(line.hasSuffix("…"))
    }

    @Test(arguments: ["", "   ", "\n\t", "\u{200B}\u{200B}", "\u{3164}", "\u{200D}"])
    func blankLookingTextIsNotVisible(text: String) {
        #expect(!DisplayText.isVisible(DisplayText.line(text)))
    }

    @Test func realTextIsVisible() {
        #expect(DisplayText.isVisible("A"))
        #expect(DisplayText.isVisible("\u{1F600}"))
    }
}

@Suite struct DayEventsTests {
    let calendar = gregorian("Europe/London")

    @Test func allDayAndTimedEventsAreCappedSeparately() throws {
        let day = date(calendar, 2026, 11, 20)
        let next = EventLayout.nextDay(after: day, calendar: calendar)
        let spam = (0..<5).map { _ in event(day, next, allDay: true) }
        let meetings = (0..<2).map { _ in event(date(calendar, 2026, 11, 20, 9), date(calendar, 2026, 11, 20, 10)) }
        let grouped = try #require(EventLayout.group(spam + meetings, dayStarts: [day], end: next, cap: 3)[day])
        #expect(grouped.allDay.count == 3)
        #expect(grouped.timed.count == 2)
        #expect(grouped.count == 7)
        // All-day first, as displayed.
        #expect(grouped.events.prefix(3).allSatisfy { $0.isAllDay })
    }

    @Test func zeroLengthEventAtTheGridsFirstMidnightIsKept() {
        let grid = EventLayout.gridDays(for: date(calendar, 2026, 11, 15), calendar: calendar)
        let end = EventLayout.nextDay(after: grid.last!, calendar: calendar)
        let reminder = event(grid[0], grid[0])
        #expect(EventLayout.group([reminder], dayStarts: grid, end: end).keys.sorted() == [grid[0]])
    }

    @Test func displayOrderIsTheSameWhateverTheReadOrder() {
        let start = date(calendar, 2026, 11, 20, 9)
        let end = date(calendar, 2026, 11, 20, 10)
        let events = (0..<20).map { event(start, end, title: "Standup", id: "e\($0)", calendarID: "c\($0 % 3)") }
        let sorted = events.sorted(by: CalendarStore.displayOrder)
        for _ in 0..<10 {
            #expect(events.shuffled().sorted(by: CalendarStore.displayOrder) == sorted)
        }
    }
}

@Suite struct DayMathsTests {
    /// London's clocks go forward at 01:00 on 29 March 2026.
    @Test func todayAndTomorrowAroundTheUKClockChange() {
        let calendar = gregorian("Europe/London")
        for (from, to) in [(28, 29), (29, 30), (30, 31)] {
            let a = date(calendar, 2026, 3, from)
            let b = date(calendar, 2026, 3, to)
            #expect(EventLayout.dayOffset(from: a, to: b, calendar: calendar) == 1)
            #expect(EventLayout.dayOffset(from: b, to: a, calendar: calendar) == -1)
        }
    }

    @Test func tomorrowAcrossAJapaneseEraChange() {
        var japanese = Calendar(identifier: .japanese)
        japanese.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = japanese.timeZone
        let lastHeiseiDay = gregorian.date(from: DateComponents(year: 2019, month: 4, day: 30))!
        let firstReiwaDay = gregorian.date(from: DateComponents(year: 2019, month: 5, day: 1))!
        #expect(EventLayout.dayOffset(from: lastHeiseiDay, to: firstReiwaDay, calendar: japanese) == 1)
    }

    /// Every calendar's month grid is 42 consecutive days, each 23 to 25
    /// hours long, covering the 1st of the month.
    @Test(arguments: [
        Calendar.Identifier.gregorian, .buddhist, .chinese, .coptic, .ethiopicAmeteMihret, .hebrew,
        .indian, .islamicUmmAlQura, .japanese, .persian, .republicOfChina,
        .gujarati, .kannada, .marathi, .telugu, .vikram,
    ])
    func monthGridsAreConsecutiveDays(identifier: Calendar.Identifier) {
        var calendar = Calendar(identifier: identifier)
        calendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        var month = gregorian.date(from: DateComponents(year: 2028, month: 1, day: 15))!
        for _ in 0..<30 {
            let days = EventLayout.gridDays(for: month, calendar: calendar)
            #expect(days.count == 42)
            for (day, next) in zip(days, days.dropFirst()) {
                let hours = next.timeIntervalSince(day) / 3600
                #expect(hours >= 23 && hours <= 25)
            }
            month = gregorian.date(byAdding: .month, value: 1, to: month)!
        }
    }
}

@Suite struct TimeTextTests {
    let calendar = gregorian("Europe/London")
    let locale = Locale(identifier: "en_GB")

    private func time(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar, timeZone: calendar.timeZone))
    }

    @Test func eventFromAnEarlierDayShowsUntil() {
        let day = date(calendar, 2026, 11, 20)
        let flight = event(date(calendar, 2026, 11, 19, 22), date(calendar, 2026, 11, 20, 6))
        let text = EventLayout.timeText(for: flight, on: day, calendar: calendar, locale: locale)
        #expect(text == String(localized: "Until \(time(flight.end))"))
    }

    @Test func eventFromAnEarlierDayEndingAtMidnightIsAllDay() {
        let day = date(calendar, 2026, 11, 20)
        let conference = event(date(calendar, 2026, 11, 19, 9), date(calendar, 2026, 11, 21))
        #expect(EventLayout.timeText(for: conference, on: day, calendar: calendar, locale: locale) == String(localized: "All-day"))
    }

    @Test func eventRunningIntoALaterDayShowsItsEndDate() {
        let day = date(calendar, 2026, 11, 20)
        let trip = event(date(calendar, 2026, 11, 20, 18), date(calendar, 2026, 11, 22, 9))
        let text = EventLayout.timeText(for: trip, on: day, calendar: calendar, locale: locale)
        #expect(text.hasPrefix(time(trip.start)))
        #expect(text.contains("22"))
    }

    @Test func multiDayAllDayEventShowsItsDates() {
        let day = date(calendar, 2026, 11, 20)
        // EventKit ends all-day events at 23:59:59 on their last day.
        let holiday = event(date(calendar, 2026, 11, 16), date(calendar, 2026, 11, 22, 23, 59), allDay: true)
        let text = EventLayout.timeText(for: holiday, on: day, calendar: calendar, locale: locale)
        #expect(text.contains("16"))
        #expect(text.contains("22"))
        #expect(!text.contains("23"))
    }

    @Test func aDayOrMoreCountsAsMultiDayEvenAcrossAClockChange() {
        // 25 October 2026 is 25 hours long in London.
        let start = date(calendar, 2026, 10, 25)
        let wholeDay = event(start, date(calendar, 2026, 10, 26))
        #expect(wholeDay.isAllDayOrMultiDay(in: calendar))
        let almost = event(start, date(calendar, 2026, 10, 25, 23, 59))
        #expect(!almost.isAllDayOrMultiDay(in: calendar))
        let overnight = event(date(calendar, 2026, 11, 20, 20), date(calendar, 2026, 11, 21, 2))
        #expect(!overnight.isAllDayOrMultiDay(in: calendar))
    }
}

@MainActor
@Suite struct DayEventMenuItemsTests {
    let calendar = gregorian("Europe/London")

    private final class Target: NSObject {
        @objc func open(_ sender: Any?) {}
    }

    private func items(
        _ events: [CalendarEvent], count: Int? = nil, now: Date, limit: Int = DayEventMenuItems.maxShownEvents
    ) -> [NSMenuItem] {
        let day = calendar.startOfDay(for: now)
        var dayEvents = DayEvents()
        for event in events { dayEvents.append(event, cap: EventLayout.maxEventsPerDay) }
        let selection = DaySelection(day: day, today: day, now: now, calendar: calendar, events: dayEvents, width: 296)
        return DayEventMenuItems.items(
            for: selection, limit: limit, fitter: TextFitter(menuWidth: 296),
            target: Target(), openEvent: #selector(Target.open(_:)), openCalendar: #selector(Target.open(_:))
        )
    }

    private func meeting(_ hour: Int, title: String = "Meeting") -> CalendarEvent {
        event(date(calendar, 2026, 11, 20, hour), date(calendar, 2026, 11, 20, hour + 1), title: title)
    }

    @Test func finishedEventsGoInTheEarlierSubmenu() {
        let menu = items([meeting(9), meeting(14)], now: date(calendar, 2026, 11, 20, 12))
        #expect(menu.count == 3) // header, "1 earlier events", the 14:00 meeting
        #expect(menu[1].hasSubmenu)
        #expect((menu[2].representedObject as? CalendarEvent)?.start == date(calendar, 2026, 11, 20, 14))
    }

    @Test func anEventEndingNowIsEarlier() {
        let menu = items([meeting(9)], now: date(calendar, 2026, 11, 20, 10))
        #expect(menu[1].hasSubmenu)
        #expect(menu[2].title == String(localized: "No more events today"))
    }

    @Test func eventsBeyondTheLimitGoInTheMoreSubmenu() {
        let menu = items((8..<20).map { meeting($0) }, now: date(calendar, 2026, 11, 20, 7), limit: 3)
        let eventRows = menu.filter { $0.representedObject is CalendarEvent }
        #expect(eventRows.count == 3)
        #expect(menu.last?.hasSubmenu == true)
    }

    @Test func eventsBeyondTheCapLinkToCalendar() {
        var dayEvents = DayEvents()
        for _ in 0..<(EventLayout.maxEventsPerDay + 5) { dayEvents.append(meeting(15), cap: EventLayout.maxEventsPerDay) }
        let now = date(calendar, 2026, 11, 20, 7)
        let day = calendar.startOfDay(for: now)
        let selection = DaySelection(day: day, today: day, now: now, calendar: calendar, events: dayEvents, width: 296)
        let menu = DayEventMenuItems.items(
            for: selection, fitter: TextFitter(menuWidth: 296),
            target: Target(), openEvent: #selector(Target.open(_:)), openCalendar: #selector(Target.open(_:))
        )
        // The overflow submenu counts the uncapped events too.
        #expect(menu.last?.title == String(localized: "\(EventLayout.maxEventsPerDay - DayEventMenuItems.maxShownEvents + 5) more events"))
    }

    @Test func longTitlesAreShortenedToTheCalendarsWidth() {
        let long = String(repeating: "Quarterly planning ", count: 10)
        let title = items([meeting(15, title: DisplayText.line(long))], now: date(calendar, 2026, 11, 20, 7))[1].title
        #expect(title.hasSuffix("…"))
        #expect(title.count < long.count)
    }

    @Test func aHundredHostileTitlesBuildQuickly() {
        let zalgo = DisplayText.line(String(repeating: "Z" + String(repeating: "\u{0336}", count: 40), count: 300))
        let events = (0..<100).map { _ in meeting(15, title: zalgo) }
        let clock = ContinuousClock()
        let elapsed = clock.measure { _ = items(events, now: date(calendar, 2026, 11, 20, 7)) }
        #expect(elapsed < .milliseconds(500))
    }
}
