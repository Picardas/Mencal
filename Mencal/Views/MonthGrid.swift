import SwiftUI

/// A six-week month grid. Weekday symbols, numerals and week numbers come
/// from the region; the first weekday can be overridden in Settings, and week
/// numbers still follow the region's own weeks.
struct MonthGrid: View {
    let calendar: Calendar
    let month: Date
    let today: Date
    @Binding var selectedDay: Date
    let eventsByDay: [Date: DayEvents]
    let showWeekNumbers: Bool
    let dimWeekends: Bool
    /// False while the month and year pickers cover the grid.
    let isInteractive: Bool

    @Namespace private var selectionNamespace

    /// Fixed column widths, so the day columns are the same with or without
    /// week numbers (which add their own column) and the parent sizes to the
    /// grid, with even margins either side.
    static let dayColumnWidth: CGFloat = 38
    static let weekColumnWidth: CGFloat = 22

    static func width(showWeekNumbers: Bool) -> CGFloat {
        dayColumnWidth * 7 + (showWeekNumbers ? weekColumnWidth : 0)
    }

    /// The columns' weekdays (1–7), starting from the first weekday.
    private var weekdays: [Int] {
        (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
    }

    var body: some View {
        let days = EventLayout.gridDays(for: month, calendar: calendar)
        let weeks = days.count / 7
        // Weekend days come from the region (e.g. Fri/Sat in some locales).
        let weekendColumns = (0..<7).map { days.indices.contains($0) && calendar.isDateInWeekend(days[$0]) }

        Grid(horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                if showWeekNumbers {
                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                }
                ForEach(Array(weekdays.enumerated()), id: \.offset) { column, weekday in
                    Text(calendar.veryShortStandaloneWeekdaySymbols[weekday - 1])
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(dimWeekends && weekendColumns[column]
                                         ? HierarchicalShapeStyle.secondary : .primary)
                        .frame(width: Self.dayColumnWidth)
                        .padding(.vertical, 4)
                        .accessibilityLabel(calendar.standaloneWeekdaySymbols[weekday - 1])
                }
            }

            ForEach(0..<weeks, id: \.self) { week in
                GridRow {
                    if showWeekNumbers {
                        let number = EventLayout.weekNumber(
                            ofRow: days[(week * 7)..<(week * 7 + 7)],
                            regionCalendar: .autoupdatingCurrent
                        ) ?? 0
                        Text(number, format: .number)
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: Self.weekColumnWidth, alignment: .leading)
                            .accessibilityLabel(Text("Week \(number)"))
                    }
                    ForEach(0..<7, id: \.self) { column in
                        let day = days[week * 7 + column]
                        DayCell(
                            day: day,
                            calendar: calendar,
                            isInMonth: calendar.isDate(day, equalTo: month, toGranularity: .month),
                            isToday: day == today,
                            isSelected: day == selectedDay,
                            isDimmedWeekend: dimWeekends && weekendColumns[column],
                            dotColors: dotColors(for: day),
                            selectionNamespace: selectionNamespace,
                            allowsHover: isInteractive,
                            onSelect: {
                                withAnimation(.bouncy(duration: 0.3)) { selectedDay = day }
                            }
                        )
                    }
                }
            }
        }
    }

    /// Up to three dots, one per calendar with events that day, in Calendar.app's colours.
    private func dotColors(for day: Date) -> [CGColor] {
        var seen = Set<String>()
        var colors: [CGColor] = []
        for event in eventsByDay[day]?.events ?? [] where seen.insert(event.calendarID).inserted {
            colors.append(event.color)
            if colors.count == 3 { break }
        }
        return colors
    }
}

private struct DayCell: View {
    @Environment(\.dismissMenu) private var dismissMenu
    let day: Date
    let calendar: Calendar
    let isInMonth: Bool
    let isToday: Bool
    let isSelected: Bool
    let isDimmedWeekend: Bool
    let dotColors: [CGColor]
    let selectionNamespace: Namespace.ID
    let allowsHover: Bool
    let onSelect: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 2) {
                Text(day, format: Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone).day())
                    .font(.system(size: 12, weight: isToday ? .bold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(foreground)
                    .frame(width: 26, height: 26)
                    .background {
                        CalendarCellMark(
                            shape: Circle(),
                            isCurrent: isToday,
                            isSelected: isSelected,
                            isHovering: isHovering && allowsHover,
                            namespace: selectionNamespace
                        )
                    }

                HStack(spacing: 2) {
                    ForEach(Array(dotColors.enumerated()), id: \.offset) { _, color in
                        Circle().fill(Color(cgColor: color)).frame(width: 4, height: 4)
                    }
                }
                .frame(height: 4)
                .opacity(isInMonth ? 1 : 0.4)
            }
            .frame(width: MonthGrid.dayColumnWidth)
            .padding(.vertical, 2)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        // Hover isn't tracked while the pickers cover the grid; don't come
        // back to a stale highlight.
        .onChange(of: allowsHover) { isHovering = false }
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            dismissMenu()
            CalendarApp.open()
        })
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(dotColors.isEmpty ? Text(verbatim: "") : Text("Has events"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var accessibilityLabel: Text {
        let date = day.formatted(
            Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone).weekday(.wide).day().month(.wide).year()
        )
        return isToday ? Text("Today, \(date)") : Text(verbatim: date)
    }

    private var foreground: AnyShapeStyle {
        if isToday { return AnyShapeStyle(.white) }
        if !isInMonth { return AnyShapeStyle(.tertiary) }
        if isDimmedWeekend { return AnyShapeStyle(.secondary) }
        return AnyShapeStyle(.primary)
    }
}

/// The mark behind a day, month or year: the accent colour for today (or
/// this month or year), a plain mark for the selection, as Calendar.app
/// draws them, and a lighter one on hover. The selection mark slides from
/// cell to cell as the selection moves.
struct CalendarCellMark<S: Shape>: View {
    let shape: S
    let isCurrent: Bool
    let isSelected: Bool
    let isHovering: Bool
    let namespace: Namespace.ID

    var body: some View {
        if isCurrent {
            shape.fill(Color.accentColor)
        } else if isSelected {
            shape.fill(.primary.opacity(0.15))
                .matchedGeometryEffect(id: "selection", in: namespace)
        } else if isHovering {
            shape.fill(.primary.opacity(0.08))
        }
    }
}
