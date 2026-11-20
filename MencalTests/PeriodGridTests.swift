import Foundation
import Testing
@testable import Mencal

@Suite struct PeriodGridTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        calendar.locale = Locale(identifier: "en_GB")
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int = 1) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func year(_ date: Date) -> Int { calendar.component(.year, from: date) }

    @Test(arguments: [(2026, 2020), (2020, 2020), (2029, 2020), (2030, 2030)])
    func decadeStartsOnAYearEndingInZero(year: Int, start: Int) {
        #expect(self.year(PeriodGrid.decadeStart(of: date(year, 6), calendar: calendar)) == start)
    }

    @Test func decadeShowsTwelveYearsWithTheOuterTwoDimmed() {
        let today = date(2026, 11, 20)
        let items = PeriodGrid.years(around: date(2027, 3), calendar: calendar, today: today, displayedMonth: date(2028, 5))
        #expect(items.map { year($0.date) } == Array(2019...2030))
        #expect(items.filter(\.isDimmed).map { year($0.date) } == [2019, 2030])
        #expect(items.filter(\.isCurrent).map { year($0.date) } == [2026])
        #expect(items.filter(\.isSelected).map { year($0.date) } == [2028])
    }

    @Test func yearShowsTwelveMonthsMarkingTodayAndTheShownMonth() {
        let today = date(2026, 11, 20)
        let items = PeriodGrid.months(of: date(2026, 1), calendar: calendar, today: today, displayedMonth: date(2026, 3))
        #expect(items.count == 12)
        #expect(items.first?.title == "Jan")
        #expect(items.filter(\.isCurrent).map(\.id) == [10])
        #expect(items.filter(\.isSelected).map(\.id) == [2])
    }

    @Test func anotherYearHasNoCurrentMonth() {
        let items = PeriodGrid.months(of: date(2025, 1), calendar: calendar, today: date(2026, 11, 20), displayedMonth: date(2026, 11))
        #expect(items.allSatisfy { !$0.isCurrent && !$0.isSelected })
    }

    /// Japanese era years: years must follow each other, never jumping to
    /// the wrong era (Foundation counts 2019 as Heisei 31 throughout).
    @Test func japaneseDecadesAreConsecutiveYears() {
        var japanese = Calendar(identifier: .japanese)
        japanese.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = japanese.timeZone
        let reiwa8 = japanese.date(from: DateComponents(era: 236, year: 8, month: 11, day: 20))!
        let items = PeriodGrid.years(around: reiwa8, calendar: japanese, today: reiwa8, displayedMonth: reiwa8)
        #expect(items.map { gregorian.component(.year, from: $0.date) } == Array(2017...2028))
        // The previous decade is the one before, not one in another era.
        let previous = PeriodGrid.year(-10, from: PeriodGrid.decadeStart(of: reiwa8, calendar: japanese), calendar: japanese)
        let earlier = PeriodGrid.years(around: previous, calendar: japanese, today: reiwa8, displayedMonth: reiwa8)
        #expect(earlier.map { gregorian.component(.year, from: $0.date) } == Array(2007...2018))
    }

    @Test func steppingBackAYearAcrossTheEraChange() {
        var japanese = Calendar(identifier: .japanese)
        japanese.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let reiwa2 = japanese.date(from: DateComponents(era: 236, year: 2, month: 6, day: 1))!
        let previous = PeriodGrid.year(-1, from: reiwa2, calendar: japanese)
        // 2019: Heisei 31 until 30 April, Reiwa 1 after.
        #expect(japanese.component(.era, from: previous) == 235)
        #expect(japanese.component(.year, from: previous) == 31)
    }

    @Test func hebrewLeapYearShowsThirteenMonths() {
        var hebrew = Calendar(identifier: .hebrew)
        hebrew.timeZone = TimeZone(identifier: "Asia/Jerusalem")!
        // 5784 (2023–24) is a leap year.
        let leapYear = hebrew.date(from: DateComponents(year: 5784, month: 1, day: 1))!
        let items = PeriodGrid.months(of: leapYear, calendar: hebrew, today: Date.distantPast, displayedMonth: leapYear)
        #expect(items.count == 13)
        #expect(Set(items.map(\.date)).count == 13)
    }
}
