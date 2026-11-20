import SwiftUI

/// The events for the selected day. Clicking an event opens it in Calendar.app.
struct DayEventList: View {
    let day: Date
    let today: Date
    let now: Date
    let calendar: Calendar
    let dayEvents: DayEvents
    /// A few of the month's tallest-looking days, laid out invisibly so the
    /// menu opens tall enough for them (up to the maximum).
    let sizingDays: [[CalendarEvent]]

    /// Whether today's finished events are shown. CalendarMenuView sets it
    /// each time the menu opens.
    @Binding var showPastEvents: Bool

    @Environment(\.dismissMenu) private var dismissMenu

    /// The list fits its content between these heights; about five events
    /// fit at the maximum, more scroll.
    private static let minListHeight: CGFloat = 60
    private static let maxListHeight: CGFloat = 270

    private var events: [CalendarEvent] { dayEvents.events }

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

            // When the menu opens, the list is as tall as the tallest of this
            // day and the sizing days, between the min and max. An open menu
            // can't resize, so while open it keeps that height and scrolls.
            ZStack(alignment: .top) {
                ForEach(sizingDays.indices, id: \.self) { index in
                    sizingRows(sizingDays[index])
                        // Capped and top-aligned, so a tall sizing day can't
                        // push the real list out of its frame.
                        .frame(maxHeight: Self.maxListHeight, alignment: .top)
                        .hidden()
                        .accessibilityHidden(true)
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        if !pastEvents.isEmpty {
                            pastEventsToggle
                        }

                        if visibleEvents.isEmpty {
                            Text(events.isEmpty ? "No events" : "No more events today")
                                .font(.callout)
                                .foregroundStyle(.tertiary)
                                .frame(maxWidth: .infinity, minHeight: Self.minListHeight)
                        } else {
                            rows
                        }
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
                // Each day starts scrolled to the top.
                .id(day)
            }
            .frame(minHeight: Self.minListHeight, maxHeight: Self.maxListHeight)
            .clipped()
        }
    }

    private var rows: some View {
        VStack(spacing: 2) {
            ForEach(visibleEvents) { event in
                EventRow(
                    event: event,
                    timeText: EventLayout.timeText(for: event, on: day, calendar: calendar),
                    isPast: event.end <= now
                )
            }
            let notShown = dayEvents.count - events.count
            if notShown > 0 {
                Button("\(notShown) more events in Calendar") {
                    dismissMenu()
                    CalendarApp.open()
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)
            }
        }
    }

    /// The same rows as `rows`, for measuring only. Their time text uses each
    /// event's own day, so they don't change when another day is selected.
    private func sizingRows(_ events: [CalendarEvent]) -> some View {
        VStack(spacing: 2) {
            ForEach(events.prefix(EventLayout.maxSizingRows)) { event in
                EventRow(
                    event: event,
                    timeText: EventLayout.timeText(
                        for: event, on: calendar.startOfDay(for: event.start), calendar: calendar
                    ),
                    isPast: false
                )
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
                    Text("\(pastEvents.count) earlier events")
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
        let offset = EventLayout.dayOffset(from: today, to: day, calendar: calendar)
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
}

private struct EventRow: View {
    @Environment(\.dismissMenu) private var dismissMenu
    let event: CalendarEvent
    let timeText: String
    let isPast: Bool

    @State private var isHovering = false

    var body: some View {
        Button {
            dismissMenu()
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
        .help("\(event.calendarTitle) — Open in Calendar")
    }

    private var background: AnyShapeStyle {
        if isHovering { return AnyShapeStyle(.primary.opacity(0.08)) }
        if event.isAllDay { return AnyShapeStyle(event.color.opacity(0.14)) }
        return AnyShapeStyle(.clear)
    }
}
