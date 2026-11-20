import AppKit
import EventKit
import Observation
import SwiftUI

/// One calendar, as listed in Settings.
struct CalendarInfo: Identifiable {
    let id: String
    let title: String
    let account: String
    let color: Color
}

/// One event occurrence.
struct CalendarEvent: Identifiable {
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
    let color: Color

    /// All-day events, plus timed events of 24 hours or more. A dinner that
    /// runs past midnight doesn't count.
    var isAllDayOrMultiDay: Bool {
        isAllDay || end.timeIntervalSince(start) >= 24 * 60 * 60
    }
}

/// Read-only access to the user's calendars.
///
/// This is the only type that touches EventKit. It never calls `save`,
/// `remove` or `commit`, and it hands out value copies (`CalendarInfo`,
/// `CalendarEvent`) rather than EventKit objects, so nothing in Mencal can
/// create, change or delete calendar data. Edits go through Calendar.app.
///
/// Data is read on demand. Calendar changes only bump `revision`, so a sync
/// while nothing is on screen costs almost nothing.
@Observable
final class CalendarStore {
    enum Access {
        case notDetermined
        case granted
        case denied
    }

    private(set) var access: Access
    /// Bumped when calendar data, access or the set of hidden calendars changes.
    private(set) var revision = 0

    var hiddenCalendarIDs: Set<String> {
        didSet {
            UserDefaults.standard.set(hiddenCalendarIDs.sorted(), forKey: PrefKey.hiddenCalendarIDs)
            revision += 1
        }
    }

    private let store = EKEventStore()

    init() {
        hiddenCalendarIDs = Set(UserDefaults.standard.stringArray(forKey: PrefKey.hiddenCalendarIDs) ?? [])
        access = Self.currentAccess()
        _ = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.revision += 1 }
        }
    }

    /// Reading events needs "Full Access"; macOS has no read-only level.
    func requestAccess() {
        store.requestFullAccessToEvents { [weak self] _, _ in
            Task { @MainActor in self?.refreshAccess() }
        }
    }

    /// Picks up changes made in System Settings › Privacy & Security.
    func refreshAccess() {
        let newAccess = Self.currentAccess()
        guard newAccess != access else { return }
        access = newAccess
        // A store created before access was granted must be reset to see data.
        if access == .granted { store.reset() }
        revision += 1
    }

    /// All calendars, sorted by account then title.
    var calendars: [CalendarInfo] {
        _ = revision // Observed, so views re-read after changes.
        guard access == .granted else { return [] }
        return store.calendars(for: .event)
            .map { CalendarInfo(
                id: $0.calendarIdentifier,
                title: $0.title,
                account: $0.source?.title ?? "",
                color: Color(nsColor: $0.color ?? .controlAccentColor)
            ) }
            .sorted {
                $0.account == $1.account
                    ? $0.title.localizedStandardCompare($1.title) == .orderedAscending
                    : $0.account.localizedStandardCompare($1.account) == .orderedAscending
            }
    }

    /// Visible event occurrences overlapping `interval`, in display order.
    func events(in interval: DateInterval) -> [CalendarEvent] {
        guard access == .granted else { return [] }
        let visible = store.calendars(for: .event).filter { !hiddenCalendarIDs.contains($0.calendarIdentifier) }
        guard !visible.isEmpty else { return [] }

        let predicate = store.predicateForEvents(withStart: interval.start, end: interval.end, calendars: visible)
        return store.events(matching: predicate)
            .compactMap { event in
                // EventKit's properties are implicitly unwrapped; skip items
                // caught mid-sync rather than crash.
                guard let calendar = event.calendar, let start = event.startDate, let end = event.endDate
                else { return nil }
                let title = event.title ?? ""
                return CalendarEvent(
                    id: "\(event.calendarItemIdentifier)|\(start.timeIntervalSinceReferenceDate)",
                    calendarItemIdentifier: event.calendarItemIdentifier,
                    calendarID: calendar.calendarIdentifier,
                    calendarTitle: calendar.title,
                    title: title.isEmpty ? String(localized: "Untitled") : title,
                    start: start,
                    // A feed can carry an end before its start.
                    end: max(end, start),
                    isAllDay: event.isAllDay,
                    location: event.location.flatMap { $0.isEmpty ? nil : $0 },
                    color: Color(nsColor: calendar.color ?? .controlAccentColor)
                )
            }
            .sorted(by: Self.displayOrder)
    }

    private static func currentAccess() -> Access {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: .granted
        case .notDetermined: .notDetermined
        // Write-only access can't read events, so it's as good as denied.
        default: .denied
        }
    }

    /// All-day first, then by start, end and title.
    private static func displayOrder(_ a: CalendarEvent, _ b: CalendarEvent) -> Bool {
        if a.isAllDay != b.isAllDay { return a.isAllDay }
        if a.start != b.start { return a.start < b.start }
        if a.end != b.end { return a.end < b.end }
        return a.title.localizedStandardCompare(b.title) == .orderedAscending
    }
}
