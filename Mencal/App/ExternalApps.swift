import AppKit

/// Hands everything that isn't read-only to Calendar.app.
enum CalendarApp {
    private static var appURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal")
    }

    static func open() {
        guard let appURL else { return }
        NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
    }

    /// Shows one occurrence using Calendar.app's `ical://ekevent/` URL
    /// (undocumented but long-standing). The UTC start date picks the right
    /// occurrence of a repeating event. The URL goes to Calendar.app
    /// explicitly, never to another app that might claim `ical://`.
    static func show(_ event: CalendarEvent) {
        let occurrence = event.start.formatted(
            Date.ISO8601FormatStyle(dateSeparator: .omitted, timeSeparator: .omitted, timeZone: .gmt)
        )
        let identifierCharacters = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))
        guard let appURL,
              let identifier = event.calendarItemIdentifier.addingPercentEncoding(withAllowedCharacters: identifierCharacters),
              let url = URL(string: "ical://ekevent/\(occurrence)/\(identifier)?method=show&options=more")
        else { return open() }
        NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
    }
}

enum SystemSettings {
    /// Privacy & Security › Calendars.
    static func openCalendarPrivacy() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }
}
