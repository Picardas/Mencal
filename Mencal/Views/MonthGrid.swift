import SwiftUI

/// A six-week month grid. Weekday symbols, numerals and week numbers come
/// from the region; the first weekday can be overridden in Settings.
struct MonthGrid: View {
    let calendar: Calendar
    let month: Date
    let today: Date
    @Binding var selectedDay: Date
    let eventsByDay: [Date: [CalendarEvent]]
    let showWeekNumbers: Bool
    let dimWeekends: Bool

    @Namespace private var glassNamespace

    /// The 42 days shown for `month`, each at the start of its day.
    static func days(for month: Date, calendar: Calendar) -> [Date] {
        guard let monthStart = calendar.dateInterval(of: .month, for: month)?.start,
              let gridStart = calendar.dateInterval(of: .weekOfYear, for: monthStart)?.start
        else { return [] }
        // startOfDay: where midnight is skipped for daylight saving, adding
        // days would otherwise land on 01:00.
        return (0..<42).compactMap {
            calendar.date(byAdding: .day, value: $0, to: gridStart).map(calendar.startOfDay)
        }
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    var body: some View {
        let days = Self.days(for: month, calendar: calendar)
        let weeks = days.count / 7
        // Weekend days come from the region (e.g. Fri/Sat in some locales).
        let weekendColumns = (0..<7).map { days.indices.contains($0) && calendar.isDateInWeekend(days[$0]) }

        GlassEffectContainer(spacing: 2) {
            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    if showWeekNumbers {
                        Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    }
                    ForEach(0..<weekdaySymbols.count, id: \.self) { column in
                        Text(weekdaySymbols[column])
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(dimWeekends && weekendColumns[column]
                                             ? HierarchicalShapeStyle.secondary : .primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                }

                ForEach(0..<weeks, id: \.self) { week in
                    GridRow {
                        if showWeekNumbers {
                            Text(calendar.component(.weekOfYear, from: days[week * 7]), format: .number)
                                .font(.caption2)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 20)
                        }
                        ForEach(0..<7, id: \.self) { column in
                            let day = days[week * 7 + column]
                            DayCell(
                                day: day,
                                isInMonth: calendar.isDate(day, equalTo: month, toGranularity: .month),
                                isToday: day == today,
                                isSelected: day == selectedDay,
                                isDimmedWeekend: dimWeekends && weekendColumns[column],
                                dotColors: dotColors(for: day),
                                glassNamespace: glassNamespace,
                                onSelect: {
                                    withAnimation(.bouncy(duration: 0.3)) { selectedDay = day }
                                }
                            )
                        }
                    }
                }
            }
        }
    }

    /// Up to three dots, one per calendar with events that day, in Calendar.app's colours.
    private func dotColors(for day: Date) -> [Color] {
        var seen = Set<String>()
        var colors: [Color] = []
        for event in eventsByDay[day] ?? [] where seen.insert(event.calendarID).inserted {
            colors.append(event.color)
            if colors.count == 3 { break }
        }
        return colors
    }
}

private struct DayCell: View {
    @Environment(MenuState.self) private var menu
    let day: Date
    let isInMonth: Bool
    let isToday: Bool
    let isSelected: Bool
    let isDimmedWeekend: Bool
    let dotColors: [Color]
    let glassNamespace: Namespace.ID
    let onSelect: () -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 2) {
            Text(day, format: .dateTime.day())
                .font(.system(size: 12, weight: isToday ? .bold : .regular))
                .monospacedDigit()
                .foregroundStyle(foreground)
                .frame(width: 26, height: 26)
                .background {
                    if isToday {
                        Circle().fill(Color.accentColor)
                    } else if isHovering && !isSelected {
                        Circle().fill(.primary.opacity(0.08))
                    }
                }
                .modifier(SelectionGlass(isActive: isSelected && !isToday, namespace: glassNamespace))

            HStack(spacing: 2) {
                ForEach(Array(dotColors.enumerated()), id: \.offset) { _, color in
                    Circle().fill(color).frame(width: 4, height: 4)
                }
            }
            .frame(height: 4)
            .opacity(isInMonth ? 1 : 0.4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
        .contentShape(.rect)
        .onHover { isHovering = $0 }
        // A closing menu sends no hover-exit, so clear it explicitly.
        .onChange(of: menu.isOpen) { isHovering = false }
        .simultaneousGesture(TapGesture().onEnded(onSelect))
        .gesture(TapGesture(count: 2).onEnded {
            menu.dismiss()
            CalendarApp.open()
        })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(day, format: .dateTime.weekday(.wide).day().month(.wide).year()))
        .accessibilityValue(dotColors.isEmpty ? Text(verbatim: "") : Text("Has events"))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(.default, onSelect)
    }

    private var foreground: AnyShapeStyle {
        if isToday { return AnyShapeStyle(.white) }
        if !isInMonth { return AnyShapeStyle(.tertiary) }
        if isDimmedWeekend { return AnyShapeStyle(.secondary) }
        return AnyShapeStyle(.primary)
    }
}

/// The Liquid Glass bubble behind the selected day. Sharing one glass ID lets
/// the bubble morph from day to day as the selection moves.
private struct SelectionGlass: ViewModifier {
    let isActive: Bool
    let namespace: Namespace.ID

    func body(content: Content) -> some View {
        if isActive {
            content
                .glassEffect(.regular.interactive(), in: .circle)
                .glassEffectID("selection", in: namespace)
        } else {
            content
        }
    }
}
