import AppKit
import Observation

/// The current date for the UI.
///
/// No timers: `now` is refreshed only when macOS reports the day, clock, time
/// zone or region changed, on wake, and when the menu opens (`refresh()`).
@Observable
final class DateTicker {
    private(set) var now = Date()

    init() {
        let names: [Notification.Name] = [
            .NSCalendarDayChanged,
            .NSSystemClockDidChange,
            .NSSystemTimeZoneDidChange,
            NSLocale.currentLocaleDidChangeNotification,
        ]
        for name in names {
            observe(name, on: .default)
        }
        observe(NSWorkspace.didWakeNotification, on: NSWorkspace.shared.notificationCenter)
    }

    func refresh() {
        now = Date()
    }

    private func observe(_ name: Notification.Name, on center: NotificationCenter) {
        _ = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }
}
