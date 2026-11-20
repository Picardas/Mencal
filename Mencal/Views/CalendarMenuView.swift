import SwiftUI

/// The calendar at the top of Mencal's menu: a month grid. The selected
/// day's events are native menu items below it, which StatusItemController
/// builds from what this view publishes. It's built fresh for each opening,
/// so its state always starts from today.
struct CalendarMenuView: View {
    @Environment(DateTicker.self) private var ticker
    @Environment(CalendarStore.self) private var store
    @Environment(\.showDayEvents) private var showDayEvents
    @Environment(CalendarGestures.self) private var gestures

    @AppStorage(PrefKey.showWeekNumbers) private var showWeekNumbers = PrefDefault.showWeekNumbers
    @AppStorage(PrefKey.firstWeekday) private var firstWeekday = PrefDefault.firstWeekday
    @AppStorage(PrefKey.dimWeekends) private var dimWeekends = PrefDefault.dimWeekends
    @AppStorage(PrefKey.showAllDayEvents) private var showAllDayEvents = PrefDefault.showAllDayEvents

    @State private var displayedMonth = Date()
    @State private var selectedDay = Calendar.autoupdatingCurrent.startOfDay(for: Date())
    @State private var eventsByDay: [Date: DayEvents] = [:]
    /// The data the shown events were read with.
    @State private var loadedKey: FetchKey?
    @State private var monthDirection: Edge = .trailing
    /// Month grid, or the month or year pickers above it.
    @State private var zoom = CalendarZoom.month
    /// The year (or decade) the pickers show, so browsing them doesn't
    /// move the month grid or fetch events.
    @State private var pickerDate = Date()
    /// The side a stepped year or decade slides in from; nil when zooming.
    @State private var periodEdge: Edge?
    /// Reads another month's events off the main thread.
    @State private var loadTask: Task<Void, Never>?

    private static let monthAnimation = Animation.snappy(duration: 0.28)

    private static let horizontalPadding: CGFloat = 14
    private var width: CGFloat {
        MonthGrid.width(showWeekNumbers: showWeekNumbers) + Self.horizontalPadding * 2
    }
    private var calendar: Calendar { .mencal(firstWeekday: firstWeekday) }
    private var today: Date { calendar.startOfDay(for: ticker.now) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonthHeader(
                title: title,
                zoom: zoom,
                isShowingToday: zoom == .month
                    && calendar.isDate(displayedMonth, equalTo: today, toGranularity: .month)
                    && selectedDay == today,
                onZoomOut: zoomOut,
                onPrevious: { step(by: -1) },
                onToday: { jumpToToday(animated: true) },
                onNext: { step(by: 1) }
            )

            // The ZStack keeps the outgoing and incoming grids in one slot
            // during the push. The month grid stays laid out under the
            // pickers, so it sets their size and the menu's height holds.
            ZStack {
                MonthGrid(
                    calendar: calendar,
                    month: displayedMonth,
                    today: today,
                    selectedDay: $selectedDay,
                    eventsByDay: eventsByDay,
                    showWeekNumbers: showWeekNumbers,
                    dimWeekends: dimWeekends,
                    isInteractive: zoom == .month
                )
                .id(calendar.dateInterval(of: .month, for: displayedMonth)?.start)
                .transition(.push(from: monthDirection))
                .opacity(zoom == .month ? 1 : 0)
                .allowsHitTesting(zoom == .month)
                .accessibilityHidden(zoom != .month)

                if zoom != .month {
                    PeriodGrid(items: periodItems, onSelect: choose)
                        .id(periodID)
                        .transition(periodEdge.map { AnyTransition.push(from: $0) }
                            ?? .scale(scale: 0.92).combined(with: .opacity))
                }
            }
            .clipped()

            if store.access != .granted {
                Divider()
                AccessPrompt()
            }
        }
        .padding(.horizontal, Self.horizontalPadding)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .frame(width: width)
        // While the menu is open its height is held; keep the content pinned
        // to the top rather than centred if it would be shorter.
        .frame(maxHeight: .infinity, alignment: .top)
        .clipped()
        .onChange(of: today) { jumpToToday(animated: false) }
        // Runs on the first layout, before the menu measures its items.
        .onChange(of: fetchKey, initial: true) { reloadEvents() }
        // A new day in the same grid needs no fetch. When a fetch is due
        // (the day left the grid, or the month changed with it), the reload
        // publishes instead, so the items aren't built from stale events.
        .onChange(of: selectedDay) {
            if fetchKey == loadedKey { publishSelectedDay() }
        }
        // Which of today's events are finished.
        .onChange(of: ticker.now) {
            if fetchKey == loadedKey { publishSelectedDay() }
        }
        // Swipes and scroll-wheel clicks over the calendar (see
        // CalendarHostingView).
        .onChange(of: gestures.serial) {
            let steps = gestures.takeSteps()
            if steps != 0 { step(by: steps) }
        }
    }

    // MARK: - Navigation

    private var title: String {
        let style = Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone)
        switch zoom {
        case .month:
            return displayedMonth.formatted(style.month(.wide).year())
        case .year:
            return pickerDate.formatted(style.year())
        case .decade:
            // "2020 – 2029", in the region's own range format.
            let start = PeriodGrid.decadeStart(of: pickerDate, calendar: calendar)
            let last = PeriodGrid.year(9, from: start, calendar: calendar)
            return (start..<last).formatted(
                Date.IntervalFormatStyle(calendar: calendar, timeZone: calendar.timeZone).year()
            )
        }
    }

    private var periodItems: [PeriodGrid.Item] {
        zoom == .decade
            ? PeriodGrid.years(around: pickerDate, calendar: calendar, today: today, displayedMonth: displayedMonth)
            : PeriodGrid.months(of: pickerDate, calendar: calendar, today: today, displayedMonth: displayedMonth)
    }

    /// Changes with the shown year or decade, so stepping animates.
    private var periodID: String {
        zoom == .decade
            ? "decade \(PeriodGrid.decadeStart(of: pickerDate, calendar: calendar).timeIntervalSinceReferenceDate)"
            : "year \(PeriodGrid.yearStart(of: pickerDate, calendar: calendar).timeIntervalSinceReferenceDate)"
    }

    private func zoomOut() {
        guard let next = zoom.zoomedOut else { return }
        if zoom == .month { pickerDate = displayedMonth }
        periodEdge = nil
        withAnimation(Self.monthAnimation) { zoom = next }
    }

    private func showPickedMonth(_ date: Date) {
        monthDirection = date < displayedMonth ? .leading : .trailing
        periodEdge = nil
        withAnimation(Self.monthAnimation) {
            displayedMonth = date
            zoom = .month
        }
    }

    /// The arrows move by a month, a year or a decade.
    private func step(by offset: Int) {
        switch zoom {
        case .month:
            showMonth(offset: offset)
        case .year, .decade:
            let years = zoom == .year ? offset : offset * 10
            let date = PeriodGrid.year(years, from: pickerDate, calendar: calendar)
            periodEdge = offset > 0 ? .trailing : .leading
            withAnimation(Self.monthAnimation) { pickerDate = date }
        }
    }

    /// Picking a month opens it; picking a year shows its months.
    private func choose(_ item: PeriodGrid.Item) {
        if zoom == .decade {
            periodEdge = nil
            withAnimation(Self.monthAnimation) {
                pickerDate = item.date
                zoom = .year
            }
        } else {
            showPickedMonth(item.date)
        }
    }

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
        periodEdge = nil
        withAnimation(animated ? (isNewMonth || zoom != .month ? Self.monthAnimation : .smooth) : nil) {
            displayedMonth = today
            selectedDay = today
            zoom = .month
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

    /// Reads the grid's events and groups them by day. The first layout is
    /// measured straight after, so it (and anything already read) is read
    /// now; other months are read off the main thread, and a read that's
    /// overtaken by further navigation is dropped.
    private func reloadEvents() {
        guard let key = fetchKey else { return }
        // A selected day outside the grid keeps the events already read for
        // it, unless the data or filter changed since.
        let isSameData = loadedKey?.revision == key.revision
            && loadedKey?.showAllDayEvents == key.showAllDayEvents
        let keptExtraDay = key.extraDay.flatMap { isSameData ? eventsByDay[$0] : nil }
        let extraInterval = key.extraDay.flatMap { day in
            keptExtraDay == nil ? DateInterval(start: day, end: EventLayout.nextDay(after: day, calendar: calendar)) : nil
        }
        let isRead = store.cachedEvents(in: key.grid) != nil
            && (extraInterval.map { store.cachedEvents(in: $0) != nil } ?? true)

        loadTask?.cancel()
        if loadedKey == nil || isRead {
            show(key, grid: store.events(in: key.grid), extraDay: keptExtraDay, extraEvents: extraInterval.map(store.events))
            return
        }
        loadTask = Task {
            let grid = await store.loadEvents(in: key.grid)
            var extraEvents: [CalendarEvent]?
            if let extraInterval { extraEvents = await store.loadEvents(in: extraInterval) }
            guard !Task.isCancelled, key == fetchKey else { return }
            show(key, grid: grid, extraDay: keptExtraDay, extraEvents: extraEvents)
        }
    }

    private func show(_ key: FetchKey, grid: [CalendarEvent], extraDay kept: DayEvents?, extraEvents: [CalendarEvent]?) {
        let days = EventLayout.gridDays(for: displayedMonth, calendar: calendar)
        var buckets = EventLayout.group(shown(grid), dayStarts: days, end: key.grid.end)
        if let extraDay = key.extraDay {
            if let kept {
                buckets[extraDay] = kept
            } else if let extraEvents {
                let next = EventLayout.nextDay(after: extraDay, calendar: calendar)
                buckets.merge(EventLayout.group(shown(extraEvents), dayStarts: [extraDay], end: next)) { $1 }
            }
        }
        eventsByDay = buckets
        loadedKey = key
        publishSelectedDay(from: buckets)
    }

    /// Hands the selected day's events to the menu. `buckets` is passed
    /// right after a reload, rather than read back from state.
    private func publishSelectedDay(from buckets: [Date: DayEvents]? = nil) {
        showDayEvents(DaySelection(
            day: selectedDay,
            today: today,
            now: ticker.now,
            calendar: calendar,
            events: store.access == .granted ? (buckets ?? eventsByDay)[selectedDay] ?? DayEvents() : nil,
            width: width
        ))
    }

    private func shown(_ events: [CalendarEvent]) -> [CalendarEvent] {
        showAllDayEvents ? events : events.filter { !$0.isAllDayOrMultiDay(in: calendar) }
    }
}

// MARK: - Header

private struct MonthHeader: View {
    let title: String
    let zoom: CalendarZoom
    let isShowingToday: Bool
    let onZoomOut: () -> Void
    let onPrevious: () -> Void
    let onToday: () -> Void
    let onNext: () -> Void

    @State private var isHoveringTitle = false

    var body: some View {
        HStack {
            // Clicking the title zooms out: month → year → decade. At the
            // decade there's nothing further out, so it's plain text.
            Group {
                if zoom.zoomedOut != nil {
                    Button(action: onZoomOut) {
                        titleText
                            .background {
                                if isHoveringTitle { Capsule().fill(.primary.opacity(0.08)) }
                            }
                            .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                    .onHover { isHoveringTitle = $0 }
                    .help(zoom == .month ? Text("Show Months") : Text("Show Years"))
                } else {
                    titleText
                }
            }
            .onChange(of: zoom) { isHoveringTitle = false }
            // Keeps the text where it was, aligned with the grid.
            .padding(.leading, -6)

            Spacer(minLength: 8)

            HStack(spacing: 2) {
                // Backward and forward flip for right-to-left languages.
                Button(action: onPrevious) {
                    Label(previousTitle, systemImage: "chevron.backward")
                        .frame(width: 22, height: 22)
                        .contentShape(.rect)
                }
                .help(previousTitle)

                Button("Today", action: onToday)
                    .disabled(isShowingToday)

                Button(action: onNext) {
                    Label(nextTitle, systemImage: "chevron.forward")
                        .frame(width: 22, height: 22)
                        .contentShape(.rect)
                }
                .help(nextTitle)
            }
            .buttonStyle(.borderless)
            .labelStyle(.iconOnly)
            .font(.body.weight(.medium))
        }
    }

    private var titleText: some View {
        Text(title)
            .font(.headline)
            .contentTransition(.numericText())
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
    }

    private var previousTitle: LocalizedStringKey {
        switch zoom {
        case .month: "Previous Month"
        case .year: "Previous Year"
        case .decade: "Previous Decade"
        }
    }

    private var nextTitle: LocalizedStringKey {
        switch zoom {
        case .month: "Next Month"
        case .year: "Next Year"
        case .decade: "Next Decade"
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
