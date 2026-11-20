import Foundation

/// What the menu bar shows.
///
/// Date only. Standard formats follow the Mac's region (field order,
/// punctuation, numerals), so the same settings read "Thu 19 Nov" in the UK
/// and "Thu, Nov 19" in the US. A custom format is used as typed, after
/// `sanitized(_:)`.
struct MenuBarFormat {
    var weekday: WeekdayStyle = .short
    var showDay = true
    var month: MonthStyle = .short
    var showYear = false
    var useCustomFormat = false
    /// A Unicode date pattern, e.g. "EEE d MMM".
    var customFormat = "EEE d MMM"

    /// The defaults, also used by the settings' `@AppStorage` properties.
    static let standard = MenuBarFormat()

    /// Longer custom patterns are cut off; a menu bar title has no use for them.
    static let maxCustomFormatLength = 64

    /// `locale`, `calendar` and `timeZone` are parameters so tests can pin them.
    func string(
        for date: Date,
        locale: Locale = .autoupdatingCurrent,
        calendar: Calendar = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        if useCustomFormat {
            let pattern = Self.sanitized(customFormat)
            guard !pattern.isEmpty else { return "" }
            let formatter = Self.customFormatter
            formatter.locale = locale
            formatter.calendar = calendar
            formatter.timeZone = timeZone
            formatter.dateFormat = pattern
            return formatter.string(from: date)
        }
        guard weekday != .none || showDay || month != .none || showYear else { return "" }
        var style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: timeZone)
        switch weekday {
        case .none: break
        case .short: style = style.weekday(.abbreviated)
        case .full: style = style.weekday(.wide)
        }
        if showDay { style = style.day() }
        switch month {
        case .none: break
        case .numeric: style = style.month(.defaultDigits)
        case .short: style = style.month(.abbreviated)
        case .full: style = style.month(.wide)
        }
        if showYear { style = style.year() }
        return date.formatted(style)
    }

    /// Reused: this runs on every UserDefaults write and Settings preview.
    private static let customFormatter = DateFormatter()

    /// A custom pattern without control, line-break or invisible formatting
    /// characters (such as a right-to-left override), capped by Unicode scalar so
    /// stacked combining marks can't get past the limit, then trimmed.
    static func sanitized(_ pattern: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in pattern.unicodeScalars where scalars.count < maxCustomFormatLength {
            // Keep the zero-width joiner, which holds emoji sequences together.
            switch scalar.properties.generalCategory {
            case .control, .lineSeparator, .paragraphSeparator: continue
            case .format where scalar != "\u{200D}": continue
            default: scalars.append(scalar)
            }
        }
        return String(scalars).trimmingCharacters(in: .whitespaces)
    }
}

extension MenuBarFormat {
    /// The saved settings; unset keys keep the defaults.
    init(defaults: UserDefaults) {
        self.init()
        func bool(_ key: String, _ fallback: Bool) -> Bool {
            defaults.object(forKey: key) as? Bool ?? fallback
        }
        weekday = defaults.string(forKey: PrefKey.weekdayStyle).flatMap(WeekdayStyle.init) ?? weekday
        showDay = bool(PrefKey.showDay, showDay)
        month = defaults.string(forKey: PrefKey.monthStyle).flatMap(MonthStyle.init) ?? month
        showYear = bool(PrefKey.showYear, showYear)
        useCustomFormat = bool(PrefKey.useCustomFormat, useCustomFormat)
        customFormat = defaults.string(forKey: PrefKey.customFormat) ?? customFormat
    }
}

enum WeekdayStyle: String, CaseIterable, Identifiable {
    case none, short, full
    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .none: "Hidden"
        case .short: "Short"
        case .full: "Full"
        }
    }
}

enum MonthStyle: String, CaseIterable, Identifiable {
    case none, numeric, short, full
    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .none: "Hidden"
        case .numeric: "Number"
        case .short: "Short"
        case .full: "Full"
        }
    }
}
