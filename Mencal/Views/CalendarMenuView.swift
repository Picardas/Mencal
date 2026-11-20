import SwiftUI

/// The calendar at the top of Mencal's menu: a month grid with the selected
/// day's events underneath.
struct CalendarMenuView: View {
    @Environment(DateTicker.self) private var ticker
    @Environment(CalendarStore.self) private var store
    @Environment(MenuState.self) private var menu

    @AppStorage(PrefKey.showWeekNumbers) private var showWeekNumbers = PrefDefault.showWeekNumbers
    @AppStorage(PrefKey.firstWeekday) private var firstWeekday = PrefDefault.firstWeekday
    @AppStorage(PrefKey.dimWeekends) private var dimWeekends = PrefDefault.dimWeekends
    @AppStorage(PrefKey.showAllDayEvents) private var showAllDayEvents = PrefDefault.showAllDayEvents
    @AppStorage(PrefKey.rememberPastEvents) private var rememberPastEvents = PrefDefault.rememberPastEvents
    @AppStorage(PrefKey.showPastEvents) private var savedShowPastEvents = PrefDefault.showPastEvents

    @State private var displayedMonth = Date()
    @State private var selectedDay = Calendar.autoupdatingCurrent.startOfDay(for: Date())
    @State private var eventsByDay: [Date: [CalendarEvent]] = [:]
    @State private var sizingDays: [[CalendarEvent]] = []
    @State private var monthDirection: Edge = .trailing
    @State private var showPastEvents = false
    @State private var lastFetch = FetchMemo()

    private static let monthAnimation = Animation.snappy(duration: 0.28)

    private var calendar: Calendar { .mencal(firstWeekday: firstWeekday) }
    private var today: Date { calendar.startOfDay(for: ticker.now) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonthHeader(
                month: displayedMonth,
                isShowingToday: calendar.isDate(displayedMonth, equalTo: today, toGranularity: .month)
                    && selectedDay == today,
                onPrevious: { showMonth(offset: -1) },
                onToday: { jumpToToday(animated: true) },
                onNext: { showMonth(offset: 1) }
            )

            // The ZStack keeps the outgoing and incoming grids in one slot
            // during the push, so the list below doesn't move.
            ZStack {
                MonthGrid(
                    calendar: calendar,
                    month: displayedMonth,
                    today: today,
                    selectedDay: $selectedDay,
                    eventsByDay: eventsByDay,
                    showWeekNumbers: showWeekNumbers,
                    dimWeekends: dimWeekends
                )
                .id(calendar.dateInterval(of: .month, for: displayedMonth)?.start)
                .transition(.push(from: monthDirection))
            }
            .clipped()

            Divider()

            if store.access == .granted {
                DayEventList(
                    day: selectedDay,
                    today: today,
                    now: ticker.now,
                    calendar: calendar,
                    events: eventsByDay[selectedDay] ?? [],
                    sizingDays: sizingDays,
                    showPastEvents: $showPastEvents
                )
            } else {
                AccessPrompt()
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .frame(width: showWeekNumbers ? 316 : 296)
        // While the menu is open its height is held; keep the content pinned
        // to the top rather than centred if it would be shorter.
        .frame(maxHeight: .infinity, alignment: .top)
        .clipped()
        .onChange(of: menu.isOpen, initial: true) { _, isOpen in
            if isOpen {
                showPastEvents = rememberPastEvents && savedShowPastEvents
                jumpToToday(animated: false)
                reloadEvents()
            } else {
                // The next opening always reads fresh data.
                lastFetch.key = nil
            }
        }
        .onChange(of: today) { jumpToToday(animated: false) }
        .onChange(of: showPastEvents) { savedShowPastEvents = showPastEvents }
        .onChange(of: fetchKey) { reloadEvents() }
    }

    // MARK: - Navigation

    private func showMonth(offset: Int) {
        guard let month = calendar.date(byAdding: .month, value: offset, to: displayedMonth) else { return }
        monthDirection = offset > 0 ? .trailing : .leading
        withAnimation(Self.monthAnimation) {
            displayedMonth = month
        }
    }

    private func jumpToToday(animated: Bool) {
        let isNewMonth = !calendar.isDate(displayedMonth, equalTo: today, toGranularity: .month)
        monthDirection = displayedMonth < today ? .trailing : .leading
        withAnimation(animated ? (isNewMonth ? Self.monthAnimation : .smooth) : nil) {
            displayedMonth = today
            selectedDay = today
        }
    }

    // MARK: - Events

    /// What the shown events depend on.
    private struct FetchKey: Equatable {
        var grid: DateInterval
        /// The selected day, when navigation has left it outside the grid.
        var extraDay: Date?
        var revision: Int
        var showAllDayEvents: Bool
    }

    /// The last fetch, kept out of SwiftUI's observation so updating it
    /// doesn't re-render.
    private final class FetchMemo {
        var key: FetchKey?
    }

    private var fetchKey: FetchKey? {
        let days = MonthGrid.days(for: displayedMonth, calendar: calendar)
        guard let first = days.first,
              let last = days.last,
              let end = calendar.date(byAdding: .day, value: 1, to: last).map(calendar.startOfDay)
        else { return nil }
        let isInGrid = selectedDay >= first && selectedDay < end
        return FetchKey(
            grid: DateInterval(start: first, end: end),
            extraDay: isInGrid ? nil : selectedDay,
            // Depend on calendar changes only while open, so a sync doesn't
            // re-render the closed menu.
            revision: menu.isOpen ? store.revision : 0,
            showAllDayEvents: showAllDayEvents
        )
    }

    private struct SizingCandidate {
        let day: Date
        let events: [CalendarEvent]
        let estimate: Double
    }

    /// A rough relative height for a day's list: one per row, plus extra
    /// for a location line or a title likely to wrap. Only used to pick
    /// candidates; the real height is measured.
    private static func estimatedHeight(of events: [CalendarEvent]) -> Double {
        events.prefix(8).reduce(0) { total, event in
            total + 1 + (event.location == nil ? 0 : 0.35) + (event.title.count > 32 ? 0.4 : 0)
        }
    }

    /// Groups the shown events by day. Runs only while the menu is open, and
    /// only queries EventKit when something the events depend on changed.
    private func reloadEvents() {
        guard menu.isOpen, let key = fetchKey, key != lastFetch.key else { return }
        lastFetch.key = key

        var intervals = [key.grid]
        if let extraDay = key.extraDay,
           let next = calendar.date(byAdding: .day, value: 1, to: extraDay).map(calendar.startOfDay) {
            intervals.append(DateInterval(start: extraDay, end: next))
        }

        var buckets: [Date: [CalendarEvent]] = [:]
        for interval in intervals {
            for event in store.events(in: interval) where showAllDayEvents || !event.isAllDayOrMultiDay {
                var day = calendar.startOfDay(for: max(event.start, interval.start))
                let limit = min(event.end, interval.end)
                repeat {
                    buckets[day, default: []].append(event)
                    guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                    // startOfDay: after a skipped midnight, +1 day keeps 01:00.
                    day = calendar.startOfDay(for: next)
                } while day < limit
            }
        }
        eventsByDay = buckets
        // The shown month's tallest-looking days. Rows differ in height (a
        // location line, two-line titles), so a rough estimate shortlists a
        // few and the list measures them exactly. Ties go to the earliest
        // day, so the choice (and the menu's height) is the same every time.
        var candidates: [SizingCandidate] = []
        for (day, events) in buckets where calendar.isDate(day, equalTo: displayedMonth, toGranularity: .month) {
            candidates.append(SizingCandidate(day: day, events: events, estimate: Self.estimatedHeight(of: events)))
        }
        candidates.sort { $0.estimate != $1.estimate ? $0.estimate > $1.estimate : $0.day < $1.day }
        sizingDays = candidates.prefix(3).map(\.events)
    }
}

// MARK: - Header

private struct MonthHeader: View {
    let month: Date
    let isShowingToday: Bool
    let onPrevious: () -> Void
    let onToday: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack {
            Text(month, format: .dateTime.month(.wide).year())
                .font(.headline)
                .contentTransition(.numericText())
                .lineLimit(1)

            Spacer(minLength: 8)

            HStack(spacing: 2) {
                Button(action: onPrevious) {
                    Label("Previous Month", systemImage: "chevron.left")
                        .frame(width: 22, height: 22)
                        .contentShape(.rect)
                }
                .help("Previous Month")

                Button("Today", action: onToday)
                    .disabled(isShowingToday)

                Button(action: onNext) {
                    Label("Next Month", systemImage: "chevron.right")
                        .frame(width: 22, height: 22)
                        .contentShape(.rect)
                }
                .help("Next Month")
            }
            .buttonStyle(.borderless)
            .labelStyle(.iconOnly)
            .font(.body.weight(.medium))
        }
    }
}

// MARK: - Access

private struct AccessPrompt: View {
    @Environment(CalendarStore.self) private var store
    @Environment(MenuState.self) private var menu

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "calendar.badge.lock")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
                .symbolRenderingMode(.hierarchical)

            Text("See Your Events Here")
                .font(.headline)

            Text(store.access == .denied
                 ? "Mencal needs access to your calendars. Turn it on in Privacy & Security, then reopen this menu."
                 : "Mencal only reads your calendars. Changes are always made in the Calendar app.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Group {
                if store.access == .denied {
                    Button("Open Privacy Settings") {
                        menu.dismiss()
                        SystemSettings.openCalendarPrivacy()
                    }
                } else {
                    Button("Allow Calendar Access") {
                        // Close the menu first so the permission prompt isn't behind it.
                        menu.dismiss()
                        NSApp.activate()
                        store.requestAccess()
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}
