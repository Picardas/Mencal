import AppKit
import EventKit
import Observation

/// One calendar, as listed in Settings.
struct CalendarInfo: Identifiable {
    let id: String
    /// Safe to display (see `DisplayText`).
    let title: String
    let account: String
    let color: CGColor
    /// Identifies the calendar when its `id` changes (see `CalendarStore`).
    let nameKey: String
}

/// One event occurrence: plain values, safe to read off the main thread.
/// Text is already made safe to display (see `DisplayText`).
nonisolated struct CalendarEvent: Identifiable, Equatable, Sendable {
    let id: String
    let calendarItemIdentifier: String
    let calendarID: String
    let calendarTitle: String
    let title: String
    let start: Date
    /// Never before `start`.
    let end: Date
    let isAllDay: Bool
    let location: String?
    let color: CGColor

    /// All-day events, plus timed events lasting a calendar day or more
    /// ("24 hours", even across a daylight-saving change). A dinner that
    /// runs past midnight doesn't count.
    func isAllDayOrMultiDay(in calendar: Calendar) -> Bool {
        guard !isAllDay else { return true }
        guard let sameTimeNextDay = calendar.date(byAdding: .day, value: 1, to: start) else { return false }
        return end >= sameTimeNextDay
    }
}

/// Read-only access to the user's calendars.
///
/// This is the only type that touches EventKit. It never calls `save`,
/// `remove` or `commit`, and it hands out value copies (`CalendarInfo`,
/// `CalendarEvent`) rather than EventKit objects, so nothing in Mencal can
/// create, change or delete calendar data. Edits go through Calendar.app.
///
/// Data is read on demand and kept until it changes. Calendar changes only
/// bump `revision` and drop the kept events, so a sync while nothing is on
/// screen costs almost nothing, and reopening the menu on unchanged
/// calendars reads nothing.
@Observable
final class CalendarStore {
    enum Access {
        case notDetermined
        case granted
        case denied
    }

    private(set) var access: Access
    /// Bumped when calendar data, access or the set of hidden calendars changes.
    private(set) var revision = 0 {
        didSet { eventCache.removeAll() }
    }

    /// Hidden calendars, by identifier and by account and title: a full
    /// iCloud or Exchange resync (or re-adding an account) gives calendars new
    /// identifiers, and a calendar the user hid mustn't reappear.
    private var hiddenIDs: Set<String>
    private var hiddenNames: Set<String>

    @ObservationIgnored private let eventStore = EKEventStore()
    @ObservationIgnored private var storeObservation: NotificationCenter.ObservationToken?
    /// Events already read, by interval, most recently used last.
    @ObservationIgnored private var eventCache: [(interval: DateInterval, events: [CalendarEvent])] = []
    /// A few months' grids: enough for reopening and stepping back and
    /// forth, without holding a huge feed's events indefinitely.
    private static let maxCachedIntervals = 4

    init() {
        let defaults = UserDefaults.standard
        hiddenIDs = Set(defaults.stringArray(forKey: PrefKey.hiddenCalendarIDs) ?? [])
        hiddenNames = Set(defaults.stringArray(forKey: PrefKey.hiddenCalendarNames) ?? [])
        access = Self.currentAccess()
        storeObservation = NotificationCenter.default.addObserver(of: eventStore, for: .changed) { [weak self] _ in
            self?.storeChanged()
        }
    }

    /// Reading events needs "Full Access"; macOS has no read-only level.
    func requestAccess() {
        Task {
            _ = try? await eventStore.requestFullAccessToEvents()
            refreshAccess()
        }
    }

    /// Picks up changes made in System Settings › Privacy & Security.
    func refreshAccess() {
        let newAccess = Self.currentAccess()
        guard newAccess != access else { return }
        access = newAccess
        // A store created before access was granted must be reset to see data.
        if access == .granted { eventStore.reset() }
        revision += 1
    }

    private func storeChanged() {
        rememberHiddenCalendars()
        revision += 1
    }

    // MARK: - Calendars

    /// All calendars, sorted by account then title.
    var calendars: [CalendarInfo] {
        _ = revision // Observed, so views re-read after changes.
        guard access == .granted else { return [] }
        return eventStore.calendars(for: .event)
            .map { calendar in
                CalendarInfo(
                    id: calendar.calendarIdentifier,
                    title: DisplayText.line(calendar.title),
                    account: DisplayText.line(calendar.source?.title ?? ""),
                    color: Self.color(of: calendar),
                    nameKey: Self.nameKey(of: calendar)
                )
            }
            .sorted { a, b in
                let byAccount = a.account.localizedStandardCompare(b.account)
                if byAccount != .orderedSame { return byAccount == .orderedAscending }
                return a.title.localizedStandardCompare(b.title) == .orderedAscending
            }
    }

    func isHidden(_ calendar: CalendarInfo) -> Bool {
        hiddenIDs.contains(calendar.id) || hiddenNames.contains(calendar.nameKey)
    }

    func setHidden(_ hidden: Bool, for calendar: CalendarInfo) {
        if hidden {
            hiddenIDs.insert(calendar.id)
            hiddenNames.insert(calendar.nameKey)
        } else {
            hiddenIDs.remove(calendar.id)
            hiddenNames.remove(calendar.nameKey)
        }
        saveHiddenCalendars()
        revision += 1
    }

    /// After a sync: hidden calendars that came back with new identifiers
    /// are recognised by name, and identifiers of calendars that no longer
    /// exist are forgotten (their names are kept in case they return).
    private func rememberHiddenCalendars() {
        guard access == .granted else { return }
        let calendars = eventStore.calendars(for: .event)
        guard !calendars.isEmpty else { return }
        var ids = hiddenIDs.intersection(calendars.map(\.calendarIdentifier))
        for calendar in calendars where hiddenNames.contains(Self.nameKey(of: calendar)) {
            ids.insert(calendar.calendarIdentifier)
        }
        guard ids != hiddenIDs else { return }
        hiddenIDs = ids
        saveHiddenCalendars()
    }

    private func saveHiddenCalendars() {
        UserDefaults.standard.set(hiddenIDs.sorted(), forKey: PrefKey.hiddenCalendarIDs)
        UserDefaults.standard.set(hiddenNames.sorted(), forKey: PrefKey.hiddenCalendarNames)
    }

    private func visibleCalendars() -> [EKCalendar] {
        eventStore.calendars(for: .event).filter {
            !hiddenIDs.contains($0.calendarIdentifier) && !hiddenNames.contains(Self.nameKey(of: $0))
        }
    }

    private static func nameKey(of calendar: EKCalendar) -> String {
        "\(calendar.source?.title ?? "")\u{1F}\(calendar.title)"
    }

    nonisolated private static func color(of calendar: EKCalendar) -> CGColor {
        (calendar.color ?? .controlAccentColor).cgColor
    }

    // MARK: - Events

    /// Events overlapping `interval` that have already been read, if any.
    func cachedEvents(in interval: DateInterval) -> [CalendarEvent]? {
        guard let index = eventCache.firstIndex(where: { $0.interval == interval }) else { return nil }
        let entry = eventCache.remove(at: index)
        eventCache.append(entry)
        return entry.events
    }

    /// Visible event occurrences overlapping `interval`, in display order,
    /// read now if they haven't been read since the data last changed. For
    /// the menu's first layout, which is measured straight after.
    func events(in interval: DateInterval) -> [CalendarEvent] {
        guard access == .granted else { return [] }
        if let cached = cachedEvents(in: interval) { return cached }
        let events = Self.read(eventStore, calendars: visibleCalendars(), in: interval)
        remember(events, for: interval)
        return events
    }

    /// The same as `events(in:)`, but reading EventKit off the main thread,
    /// so moving between months never blocks the open menu.
    func loadEvents(in interval: DateInterval) async -> [CalendarEvent] {
        guard access == .granted else { return [] }
        if let cached = cachedEvents(in: interval) { return cached }
        let revisionAtStart = revision
        // EventKit's store and calendars can be read from another thread;
        // they're only read there, and only value copies come back.
        nonisolated(unsafe) let store = eventStore
        nonisolated(unsafe) let calendars = visibleCalendars()
        let events = await Task.detached(priority: .userInitiated) {
            Self.read(store, calendars: calendars, in: interval)
        }.value
        if revision == revisionAtStart { remember(events, for: interval) }
        return events
    }

    /// Keeps the most recently used intervals, and always the one containing
    /// today, which the next opening shows.
    private func remember(_ events: [CalendarEvent], for interval: DateInterval) {
        if eventCache.count >= Self.maxCachedIntervals,
           let oldest = eventCache.firstIndex(where: { !$0.interval.contains(Date()) }) {
            eventCache.remove(at: oldest)
        }
        eventCache.append((interval, events))
    }

    nonisolated private static func read(
        _ store: EKEventStore,
        calendars: [EKCalendar],
        in interval: DateInterval
    ) -> [CalendarEvent] {
        guard !calendars.isEmpty else { return [] }
        // Per-calendar values once, not once per event.
        let calendarDetails = Dictionary(
            calendars.map { ($0.calendarIdentifier, (title: DisplayText.line($0.title), color: color(of: $0))) },
            uniquingKeysWith: { first, _ in first }
        )
        let predicate = store.predicateForEvents(withStart: interval.start, end: interval.end, calendars: calendars)
        return store.events(matching: predicate)
            .compactMap { event -> CalendarEvent? in
                // EventKit's properties are implicitly unwrapped; skip items
                // caught mid-sync rather than crash.
                guard let calendar = event.calendar, let start = event.startDate, let end = event.endDate,
                      let details = calendarDetails[calendar.calendarIdentifier],
                      !isHiddenLikeCalendarApp(event)
                else { return nil }
                let title = DisplayText.line(event.title ?? "")
                let location = DisplayText.line(event.location ?? "")
                return CalendarEvent(
                    id: "\(event.calendarItemIdentifier)|\(start.timeIntervalSinceReferenceDate)",
                    calendarItemIdentifier: event.calendarItemIdentifier,
                    calendarID: calendar.calendarIdentifier,
                    calendarTitle: details.title,
                    title: DisplayText.isVisible(title) ? title : String(localized: "Untitled"),
                    start: start,
                    // A feed can carry an end before its start.
                    end: max(end, start),
                    isAllDay: event.isAllDay,
                    location: DisplayText.isVisible(location) ? location : nil,
                    color: details.color
                )
            }
            .sorted(by: displayOrder)
    }

    /// Cancelled events and invitations the user declined, which Calendar.app
    /// hides by default. Only the user's own response is read.
    nonisolated private static func isHiddenLikeCalendarApp(_ event: EKEvent) -> Bool {
        if event.status == .canceled { return true }
        guard event.hasAttendees else { return false }
        return event.attendees?.contains { $0.isCurrentUser && $0.participantStatus == .declined } ?? false
    }

    private static func currentAccess() -> Access {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: .granted
        case .notDetermined: .notDetermined
        // Write-only access can't read events, so it's as good as denied.
        default: .denied
        }
    }

    /// All-day first, then by start, end and title; the calendar and the
    /// occurrence break remaining ties, so equal events never swap places
    /// between reads.
    nonisolated static func displayOrder(_ a: CalendarEvent, _ b: CalendarEvent) -> Bool {
        if a.isAllDay != b.isAllDay { return a.isAllDay }
        if a.start != b.start { return a.start < b.start }
        if a.end != b.end { return a.end < b.end }
        let byTitle = a.title.localizedStandardCompare(b.title)
        if byTitle != .orderedSame { return byTitle == .orderedAscending }
        if a.calendarID != b.calendarID { return a.calendarID < b.calendarID }
        return a.id < b.id
    }
}
