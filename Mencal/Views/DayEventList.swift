import SwiftUI

/// The events for the selected day. Clicking an event opens it in Calendar.app.
struct DayEventList: View {
    let day: Date
    let today: Date
    let now: Date
    let calendar: Calendar
    let events: [CalendarEvent]
    /// The shown month's tallest-looking days. Laid out invisibly so the
    /// menu opens tall enough for any day that month (up to the maximum).
    let sizingDays: [[CalendarEvent]]

    /// Whether today's finished events are shown. CalendarMenuView sets it
    /// each time the menu opens.
    @Binding var showPastEvents: Bool

    @Environment(MenuState.self) private var menu

    /// The list fits its content between these heights; about five events
    /// fit at the maximum, more scroll.
    private static let minListHeight: CGFloat = 60
    private static let maxListHeight: CGFloat = 270

    /// A huge feed can't make the menu lay out thousands of rows; the rest
    /// are a click away in Calendar.app.
    private static let maxRows = 100

    /// Enough rows to pass `maxListHeight`; more would be laid out for nothing.
    private static let maxSizingRows = 8

    /// Only today hides finished events; other days show everything.
    private var pastEvents: [CalendarEvent] {
        guard day == today else { return [] }
        return events.filter { $0.end <= now }
    }

    private var visibleEvents: [CalendarEvent] {
        guard !showPastEvents, day == today else { return events }
        return events.filter { $0.end > now }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(day, format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let relative = relativeDayName {
                    Text(relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 4)

            // When the menu opens, the list is as tall as the taller of this
            // day and the month's busiest day, between the min and max. An
            // open menu can't resize, so while open it keeps that height and
            // scrolls if needed.
            ZStack(alignment: .top) {
                // The ZStack takes the tallest of these.
                ForEach(sizingDays.indices, id: \.self) { index in
                    eventRows(Array(sizingDays[index].prefix(Self.maxSizingRows)))
                        .hidden()
                        .accessibilityHidden(true)
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        if !pastEvents.isEmpty {
                            pastEventsToggle
                        }

                        if visibleEvents.isEmpty {
                            Text(events.isEmpty ? "No Events" : "No More Events Today")
                                .font(.callout)
                                .foregroundStyle(.tertiary)
                                .frame(maxWidth: .infinity, minHeight: Self.minListHeight)
                        } else {
                            rows
                        }
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .frame(minHeight: Self.minListHeight, maxHeight: Self.maxListHeight)
            .clipped()
            // Each day starts scrolled to the top.
            .id(day)
        }
    }

    private var rows: some View {
        VStack(spacing: 2) {
            eventRows(Array(visibleEvents.prefix(Self.maxRows)))
            if visibleEvents.count > Self.maxRows {
                Button("^[\(visibleEvents.count - Self.maxRows) more event](inflect: true) in Calendar") {
                    menu.dismiss()
                    CalendarApp.open()
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)
            }
        }
    }

    private func eventRows(_ events: [CalendarEvent]) -> some View {
        VStack(spacing: 2) {
            ForEach(events) { event in
                EventRow(event: event, timeText: timeText(for: event), isPast: event.end <= now)
            }
        }
    }

    /// A small disclosure row: "3 earlier events" / "Hide earlier events".
    private var pastEventsToggle: some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { showPastEvents.toggle() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .rotationEffect(.degrees(showPastEvents ? 90 : 0))
                if showPastEvents {
                    Text("Hide earlier events")
                } else {
                    Text("^[\(pastEvents.count) earlier event](inflect: true)")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    /// "Yesterday", "Today" or "Tomorrow", in the user's language.
    private var relativeDayName: String? {
        let offset = calendar.dateComponents([.day], from: today, to: day).day ?? 0
        guard abs(offset) <= 1 else { return nil }
        return Self.relativeFormatter.localizedString(from: DateComponents(day: offset))
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateTimeStyle = .named
        formatter.formattingContext = .beginningOfSentence
        return formatter
    }()

    private func timeText(for event: CalendarEvent) -> String {
        // startOfDay: on a day where midnight is skipped, +1 day lands on 01:00.
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: day).map(calendar.startOfDay) ?? day

        if event.isAllDay {
            // EventKit ends all-day events at 23:59:59 on their last day.
            let lastDay = calendar.startOfDay(for: event.end.addingTimeInterval(-1))
            guard lastDay > calendar.startOfDay(for: event.start) else { return String(localized: "All-day") }
            let range = (event.start..<lastDay).formatted(.interval.day().month(.abbreviated))
            return String(localized: "All-day · \(range)")
        }

        let startsBefore = event.start < day
        let endsAfter = event.end > dayEnd
        let time = Date.FormatStyle(date: .omitted, time: .shortened)

        switch (startsBefore, endsAfter) {
        case (true, true):
            return String(localized: "All-day")
        case (true, false):
            return String(localized: "Until \(event.end.formatted(time))")
        case (false, true):
            let ends = event.end.formatted(.dateTime.day().month(.abbreviated).hour().minute())
            return String(localized: "\(event.start.formatted(time)) – \(ends)")
        case (false, false):
            if event.start == event.end { return event.start.formatted(time) }
            return (event.start..<event.end).formatted(Date.IntervalFormatStyle(date: .omitted, time: .shortened))
        }
    }
}

private struct EventRow: View {
    @Environment(MenuState.self) private var menu
    let event: CalendarEvent
    let timeText: String
    let isPast: Bool

    @State private var isHovering = false

    var body: some View {
        Button {
            menu.dismiss()
            CalendarApp.show(event)
        } label: {
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(event.color)
                    .frame(width: 3)

                VStack(alignment: .leading, spacing: 1) {
                    Text(event.title)
                        .font(.callout.weight(.medium))
                        .lineLimit(2)
                    Text(timeText)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    if let location = event.location {
                        Text(location)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 5)
            .padding(.horizontal, 6)
            .background(background, in: .rect(cornerRadius: 8, style: .continuous))
            .contentShape(.rect(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .opacity(isPast ? 0.5 : 1)
        .onHover { isHovering = $0 }
        // A closing menu sends no hover-exit, so clear it explicitly.
        .onChange(of: menu.isOpen) { isHovering = false }
        .help("\(event.calendarTitle) — Open in Calendar")
    }

    private var background: AnyShapeStyle {
        if isHovering { return AnyShapeStyle(.primary.opacity(0.08)) }
        if event.isAllDay { return AnyShapeStyle(event.color.opacity(0.14)) }
        return AnyShapeStyle(.clear)
    }
}
