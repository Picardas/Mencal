import SwiftUI

/// The calendar at the top of Mencal's menu: a month grid with the selected
/// day's events underneath. StatusItemController builds it fresh for each
/// opening, so its state always starts from today.
struct CalendarMenuView: View {
    @Environment(DateTicker.self) private var ticker
    @Environment(CalendarStore.self) private var store

    @AppStorage(PrefKey.showWeekNumbers) private var showWeekNumbers = PrefDefault.showWeekNumbers
    @AppStorage(PrefKey.firstWeekday) private var firstWeekday = PrefDefault.firstWeekday
    @AppStorage(PrefKey.dimWeekends) private var dimWeekends = PrefDefault.dimWeekends
    @AppStorage(PrefKey.showAllDayEvents) private var showAllDayEvents = PrefDefault.showAllDayEvents
    @AppStorage(PrefKey.showPastEvents) private var savedShowPastEvents = PrefDefault.showPastEvents

    @State private var displayedMonth = Date()
    @State private var selectedDay = Calendar.autoupdatingCurrent.startOfDay(for: Date())
    @State private var eventsByDay: [Date: DayEvents] = [:]
    /// The data the shown events were read with.
    @State private var loadedKey: FetchKey?
    /// Chosen once per opening, because the menu's height is fixed while
    /// it's open.
    @State private var sizingDays: [[CalendarEvent]]?
    @State private var monthDirection: Edge = .trailing
    @State private var showPastEvents: Bool

    private static let monthAnimation = Animation.snappy(duration: 0.28)

    init() {
        // Earlier events start hidden unless the user chose to remember.
        let defaults = UserDefaults.standard
        let remember = defaults.object(forKey: PrefKey.rememberPastEvents) as? Bool ?? PrefDefault.rememberPastEvents
        let saved = defaults.object(forKey: PrefKey.showPastEvents) as? Bool ?? PrefDefault.showPastEvents
        _showPastEvents = State(initialValue: remember && saved)
    }

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
                    dayEvents: eventsByDay[selectedDay] ?? DayEvents(),
                    sizingDays: sizingDays ?? [],
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
        .onChange(of: today) { jumpToToday(animated: false) }
        .onChange(of: showPastEvents) { savedShowPastEvents = showPastEvents }
        // Runs on the first layout, before the menu measures the view.
        .onChange(of: fetchKey, initial: true) { reloadEvents() }
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

    private var fetchKey: FetchKey? {
        let days = EventLayout.gridDays(for: displayedMonth, calendar: calendar)
        guard let first = days.first, let last = days.last else { return nil }
        let end = EventLayout.nextDay(after: last, calendar: calendar)
        let isInGrid = selectedDay >= first && selectedDay < end
        return FetchKey(
            grid: DateInterval(start: first, end: end),
            extraDay: isInGrid ? nil : selectedDay,
            revision: store.revision,
            showAllDayEvents: showAllDayEvents
        )
    }

    /// Reads the grid's events and groups them by day.
    private func reloadEvents() {
        guard let key = fetchKey else { return }
        let days = EventLayout.gridDays(for: displayedMonth, calendar: calendar)
        var buckets = EventLayout.group(shownEvents(in: key.grid), dayStarts: days, end: key.grid.end)

        // A selected day outside the grid keeps the events already read for
        // it, unless the data or filter changed since.
        if let extraDay = key.extraDay {
            let isSameData = loadedKey?.revision == key.revision
                && loadedKey?.showAllDayEvents == key.showAllDayEvents
            if isSameData, let kept = eventsByDay[extraDay] {
                buckets[extraDay] = kept
            } else {
                let next = EventLayout.nextDay(after: extraDay, calendar: calendar)
                let day = DateInterval(start: extraDay, end: next)
                buckets.merge(EventLayout.group(shownEvents(in: day), dayStarts: [extraDay], end: next)) { $1 }
            }
        }

        eventsByDay = buckets
        loadedKey = key
        if sizingDays == nil {
            sizingDays = tallestDays(in: buckets)
        }
    }

    private func shownEvents(in interval: DateInterval) -> [CalendarEvent] {
        store.events(in: interval).filter { showAllDayEvents || !$0.isAllDayOrMultiDay }
    }

    /// The shown month's tallest-looking days. Rows differ in height (a
    /// location line, two-line titles), so a rough estimate shortlists a few
    /// and the list measures them exactly. Ties go to the earliest day, so
    /// the choice (and the menu's height) is the same every time.
    private func tallestDays(in buckets: [Date: DayEvents]) -> [[CalendarEvent]] {
        buckets
            .filter { calendar.isDate($0.key, equalTo: displayedMonth, toGranularity: .month) }
            .map { (day: $0.key, events: $0.value.events) }
            .sorted { a, b in
                let heightA = EventLayout.estimatedHeight(of: a.events)
                let heightB = EventLayout.estimatedHeight(of: b.events)
                return heightA != heightB ? heightA > heightB : a.day < b.day
            }
            .prefix(3)
            .map(\.events)
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
    @Environment(\.dismissMenu) private var dismissMenu

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
                        dismissMenu()
                        SystemSettings.openCalendarPrivacy()
                    }
                } else {
                    Button("Allow Calendar Access") {
                        // Close the menu first so the permission prompt isn't behind it.
                        dismissMenu()
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
