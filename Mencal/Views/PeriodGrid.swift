import SwiftUI

/// How far the calendar is zoomed out. Clicking the title steps out a level,
/// as in Windows' clock calendar: month → year (pick a month) → decade (pick
/// a year).
enum CalendarZoom {
    case month, year, decade

    var zoomedOut: CalendarZoom? {
        switch self {
        case .month: .year
        case .year: .decade
        case .decade: nil
        }
    }
}

/// A grid of months or years, four to a row, filling the space the month
/// grid uses so the menu's height doesn't change.
struct PeriodGrid: View {
    struct Item: Identifiable {
        /// The position in the grid.
        let id: Int
        /// The start of the month or year.
        let date: Date
        let title: String
        /// Contains today: shown in the accent colour, like today's date.
        let isCurrent: Bool
        /// The month or year the calendar is on.
        let isSelected: Bool
        /// Just outside the decade, like the grid's days outside the month.
        let isDimmed: Bool
        let accessibilityLabel: String
    }

    let items: [Item]
    let onSelect: (Item) -> Void

    @Namespace private var selectionNamespace

    var body: some View {
        // Rows of four: 12 months make three rows; 13-month years (Hebrew,
        // Coptic, Ethiopic) make four.
        Grid(horizontalSpacing: 0, verticalSpacing: 0) {
            ForEach(Array(stride(from: 0, to: items.count, by: 4)), id: \.self) { rowStart in
                GridRow {
                    ForEach(items[rowStart..<min(rowStart + 4, items.count)]) { item in
                        PeriodCell(item: item, selectionNamespace: selectionNamespace) { onSelect(item) }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Years

    /// The start of `date`'s year. In the Japanese calendar a year can be
    /// part of one (when a new era begins mid-year).
    static func yearStart(of date: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: .year, for: date)?.start ?? date
    }

    /// The year `offset` years from `date`'s, stepping from one year's start
    /// to the next so no year is skipped, even across an era change.
    static func year(_ offset: Int, from date: Date, calendar: Calendar) -> Date {
        var year = yearStart(of: date, calendar: calendar)
        for _ in 0..<abs(offset) {
            let next = offset > 0
                ? calendar.dateInterval(of: .year, for: year)?.end
                : calendar.dateInterval(of: .year, for: year.addingTimeInterval(-1))?.start
            guard let next else { break }
            year = next
        }
        return year
    }

    /// The first year of `date`'s decade: the closest year at or before it
    /// whose number ends in 0 (in its era).
    static func decadeStart(of date: Date, calendar: Calendar) -> Date {
        var year = yearStart(of: date, calendar: calendar)
        for _ in 0..<9 where calendar.component(.year, from: year) % 10 != 0 {
            year = self.year(-1, from: year, calendar: calendar)
        }
        return year
    }

    /// The decade containing `date`, with the year either side of it.
    static func years(
        around date: Date, calendar: Calendar, today: Date, displayedMonth: Date
    ) -> [Item] {
        let first = year(-1, from: decadeStart(of: date, calendar: calendar), calendar: calendar)
        let style = Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone).year()
        return (0..<12).map { index in
            let start = year(index, from: first, calendar: calendar)
            let title = start.formatted(style)
            return Item(
                id: index,
                date: start,
                title: title,
                isCurrent: calendar.isDate(start, equalTo: today, toGranularity: .year),
                isSelected: calendar.isDate(start, equalTo: displayedMonth, toGranularity: .year),
                isDimmed: index == 0 || index == 11,
                accessibilityLabel: title
            )
        }
    }

    // MARK: - Months

    /// The months of `date`'s year, short names from the region. Most years
    /// have 12; some calendars' have 13, and a year cut short by a new era
    /// has fewer.
    static func months(
        of date: Date, calendar: Calendar, today: Date, displayedMonth: Date
    ) -> [Item] {
        let start = yearStart(of: date, calendar: calendar)
        let count = calendar.range(of: .month, in: .year, for: start)?.count ?? 12
        let shortName = DateFormatter()
        shortName.calendar = calendar
        shortName.locale = calendar.locale ?? .autoupdatingCurrent
        shortName.timeZone = calendar.timeZone
        shortName.setLocalizedDateFormatFromTemplate("LLL")
        let fullName = Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone).month(.wide).year()
        return (0..<count).compactMap { index in
            guard let month = calendar.date(byAdding: .month, value: index, to: start) else { return nil }
            return Item(
                id: index,
                date: month,
                title: shortName.string(from: month),
                isCurrent: calendar.isDate(month, equalTo: today, toGranularity: .month),
                isSelected: calendar.isDate(month, equalTo: displayedMonth, toGranularity: .month),
                isDimmed: false,
                accessibilityLabel: month.formatted(fullName)
            )
        }
    }
}

private struct PeriodCell: View {
    let item: PeriodGrid.Item
    let selectionNamespace: Namespace.ID
    let onSelect: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            Text(item.title)
                .font(.system(size: 13, weight: item.isCurrent ? .semibold : .regular))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(foreground)
                .frame(width: 58, height: 30)
                .background {
                    CalendarCellMark(
                        shape: Capsule(),
                        isCurrent: item.isCurrent,
                        isSelected: item.isSelected,
                        isHovering: isHovering,
                        namespace: selectionNamespace
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel(Text(verbatim: item.accessibilityLabel))
        .accessibilityAddTraits(item.isSelected ? .isSelected : [])
    }

    private var foreground: AnyShapeStyle {
        if item.isCurrent { return AnyShapeStyle(.white) }
        if item.isDimmed { return AnyShapeStyle(.tertiary) }
        return AnyShapeStyle(.primary)
    }
}
