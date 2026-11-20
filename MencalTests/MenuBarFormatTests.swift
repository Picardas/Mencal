import Foundation
import Testing
@testable import Mencal

@Suite struct MenuBarFormatTests {
    private let london = TimeZone(identifier: "Europe/London")!
    /// Pinned, so the tests don't depend on this Mac's calendar system.
    private let gregorian = Calendar(identifier: .gregorian)
    /// Thursday 19 November 2026, 12:00 in London.
    private let thursday = Date(timeIntervalSince1970: 1_795_089_600)

    @Test(arguments: [
        ("en_GB", "Thu 19 Nov"),
        ("en_US", "Thu, Nov 19"),
    ])
    func standardFormatFollowsTheRegion(locale: String, expected: String) {
        let text = MenuBarFormat().string(for: thursday, locale: Locale(identifier: locale), calendar: gregorian, timeZone: london)
        #expect(text == expected)
    }

    @Test func everythingSwitchedOffIsEmpty() {
        var format = MenuBarFormat()
        format.weekday = .none
        format.showDay = false
        format.month = .none
        #expect(format.string(for: thursday, locale: Locale(identifier: "en_GB"), calendar: gregorian, timeZone: london).isEmpty)
    }

    @Test func customPatternIsUsedAsTyped() {
        var format = MenuBarFormat()
        format.useCustomFormat = true
        format.customFormat = "d MMMM y"
        #expect(format.string(for: thursday, locale: Locale(identifier: "en_GB"), calendar: gregorian, timeZone: london) == "19 November 2026")
    }

    @Test func sanitisingRemovesInvisibleFormattingCharacters() {
        #expect(MenuBarFormat.sanitized("EEE \u{202E}d\u{202C} MMM\u{0}") == "EEE d MMM")
    }

    @Test func sanitisingKeepsEmojiJoiners() {
        let family = "'\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}'"
        #expect(MenuBarFormat.sanitized(family) == family)
    }

    @Test func sanitisingCapsUnicodeScalarsNotCharacters() {
        // Each "á" here is two scalars: a plus a combining accent.
        let stacked = String(repeating: "a\u{0301}", count: 100)
        #expect(MenuBarFormat.sanitized(stacked).unicodeScalars.count == MenuBarFormat.maxCustomFormatLength)
    }

    @Test func blankPatternGivesNoText() {
        var format = MenuBarFormat()
        format.useCustomFormat = true
        format.customFormat = "   "
        #expect(format.string(for: thursday).isEmpty)
    }
}
