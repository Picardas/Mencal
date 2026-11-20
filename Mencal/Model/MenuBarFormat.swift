import Foundation

/// What the menu bar shows.
///
/// Date only. Standard formats follow the Mac's region (field order,
/// punctuation, numerals), so the same settings read "Thu 19 Nov" in the UK
/// and "Thu, Nov 19" in the US. A custom format is used as typed (trimmed, up
/// to `maxCustomFormatLength` characters).
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

    func string(for date: Date) -> String {
        if useCustomFormat {
            let pattern = customFormat.prefix(Self.maxCustomFormatLength).trimmingCharacters(in: .whitespaces)
            guard !pattern.isEmpty else { return "" }
            Self.customFormatter.dateFormat = pattern
            return Self.customFormatter.string(from: date)
        }
        guard weekday != .none || showDay || month != .none || showYear else { return "" }
        var style = Date.FormatStyle.dateTime
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

    private static let customFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.calendar = .autoupdatingCurrent
        formatter.timeZone = .autoupdatingCurrent
        return formatter
    }()
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
