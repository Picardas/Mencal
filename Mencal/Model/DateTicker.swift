import AppKit
import Observation

/// The current date for the UI.
///
/// No timers: `now` is refreshed only when macOS reports the day, clock, time
/// zone or region changed, on wake, and when the menu opens (`refresh()`).
@Observable
final class DateTicker {
    private(set) var now = Date()

    @ObservationIgnored private var observations: [NotificationCenter.ObservationToken] = []

    init() {
        let center = NotificationCenter.default
        observations = [
            center.addObserver(of: Date.self, for: .systemClockDidChange) { [weak self] _ in self?.refresh() },
            center.addObserver(of: TimeZone.self, for: .systemTimeZoneDidChange) { [weak self] _ in self?.refresh() },
            center.addObserver(of: Locale.self, for: .currentLocaleDidChange) { [weak self] _ in self?.refresh() },
            NSWorkspace.shared.notificationCenter.addObserver(of: NSWorkspace.shared, for: .didWake) { [weak self] _ in
                self?.refresh()
            },
        ]
        // The day change is an asynchronous message; this task runs on the
        // main actor and lives as long as the app.
        Task { [weak self] in
            for await _ in center.messages(of: Calendar.self, for: .calendarDayChanged) { self?.refresh() }
        }
    }

    func refresh() {
        now = Date()
    }
}
