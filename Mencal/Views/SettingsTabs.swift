import ServiceManagement
import SwiftUI

// The settings window's tabs, hosted by SettingsWindowController.

// MARK: - General

struct GeneralSettings: View {
    @State private var launchAtLogin = false
    @State private var loginItemNote: String?

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $launchAtLogin) {
                    Text("Open at login")
                    if let loginItemNote {
                        Text(loginItemNote)
                    }
                }
                // Can always be switched off, but only on from Applications.
                .disabled(!launchAtLogin && !Self.isInApplicationsFolder)
                .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
            }

            Section {
                LabeledContent {
                    Button("Open Calendar") { CalendarApp.open() }
                } label: {
                    Text("Calendar app")
                    Text("Mencal only reads your calendars. Add or change events in Calendar.")
                }
            }

            Section {
                LabeledContent {
                    Button("Quit Mencal") { NSApp.terminate(nil) }
                } label: {
                    Text("Mencal")
                    Text("Version \(version)")
                }
            }
        }
        .settingsPane()
        // The login item can also be changed in System Settings, including
        // while this window is open.
        .onAppear { syncLoginItem() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            syncLoginItem()
        }
    }

    /// A login item opens whichever copy registered it, so only offer it when
    /// this copy is installed in /Applications or ~/Applications (including
    /// subfolders), not in Downloads, DerivedData or a disk image.
    private static var isInApplicationsFolder: Bool {
        let path = Bundle.main.bundleURL.resolvingSymlinksInPath().path
        var folders = ["/Applications/"]
        // Inside the sandbox NSHomeDirectory() is the container, so ask for
        // the account's real home folder.
        if let account = getpwuid(getuid()) {
            folders.append(String(cString: account.pointee.pw_dir) + "/Applications/")
        }
        return folders.contains { path.hasPrefix($0) }
    }

    /// On means registered, including while waiting for the user's approval,
    /// so switching off can still withdraw a pending registration.
    private static func isRegistered(_ status: SMAppService.Status) -> Bool {
        status == .enabled || status == .requiresApproval
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        let service = SMAppService.mainApp
        guard enabled != Self.isRegistered(service.status) else { return }
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
            if service.status == .requiresApproval {
                SMAppService.openSystemSettingsLoginItems()
            }
        } catch {
            // register() can throw while leaving the item awaiting approval
            // (e.g. if it was switched off in System Settings before).
            if service.status == .requiresApproval {
                SMAppService.openSystemSettingsLoginItems()
            } else {
                loginItemNote = error.localizedDescription
                launchAtLogin = Self.isRegistered(service.status)
                return
            }
        }
        syncLoginItem()
    }

    private func syncLoginItem() {
        let status = SMAppService.mainApp.status
        launchAtLogin = Self.isRegistered(status)
        if status == .requiresApproval {
            loginItemNote = String(localized: "Waiting for approval in System Settings › General › Login Items.")
        } else if !launchAtLogin && !Self.isInApplicationsFolder {
            loginItemNote = String(localized: "Move Mencal to the Applications folder to open it at login.")
        } else {
            loginItemNote = nil
        }
    }
}

// MARK: - Menu bar

struct MenuBarSettings: View {
    @Environment(DateTicker.self) private var ticker

    @AppStorage(PrefKey.weekdayStyle) private var weekday = MenuBarFormat.standard.weekday
    @AppStorage(PrefKey.showDay) private var showDay = MenuBarFormat.standard.showDay
    @AppStorage(PrefKey.monthStyle) private var month = MenuBarFormat.standard.month
    @AppStorage(PrefKey.showYear) private var showYear = MenuBarFormat.standard.showYear
    @AppStorage(PrefKey.useCustomFormat) private var useCustomFormat = MenuBarFormat.standard.useCustomFormat
    @AppStorage(PrefKey.customFormat) private var customFormat = MenuBarFormat.standard.customFormat

    private var format: MenuBarFormat {
        MenuBarFormat(
            weekday: weekday,
            showDay: showDay,
            month: month,
            showYear: showYear,
            useCustomFormat: useCustomFormat,
            customFormat: customFormat
        )
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Preview") {
                    let preview = format.string(for: ticker.now).trimmingCharacters(in: .whitespacesAndNewlines)
                    Text(verbatim: preview.isEmpty ? "—" : preview)
                        .font(Font(NSFont.menuBarFont(ofSize: 0) as CTFont))
                }
            }

            Section {
                Picker("Format", selection: $useCustomFormat) {
                    Text("Standard").tag(false)
                    Text("Custom").tag(true)
                }
                .pickerStyle(.segmented)

                if useCustomFormat {
                    TextField("Pattern", text: $customFormat, prompt: Text(verbatim: MenuBarFormat.standard.customFormat))
                        .font(.body.monospaced())
                        .autocorrectionDisabled()
                } else {
                    Picker("Weekday", selection: $weekday) {
                        ForEach(WeekdayStyle.allCases) { Text($0.title).tag($0) }
                    }
                    Toggle("Day of month", isOn: $showDay)
                    Picker("Month", selection: $month) {
                        ForEach(MonthStyle.allCases) { Text($0.title).tag($0) }
                    }
                    Toggle("Year", isOn: $showYear)
                }
            } footer: {
                Group {
                    if useCustomFormat {
                        Text("Uses Unicode date symbols, e.g. EEE (weekday), d (day), MMM (month), y (year). Names use your language; the order is as typed. Time symbols aren't kept up to date, and patterns are limited to \(MenuBarFormat.maxCustomFormatLength) characters.")
                    } else {
                        Text("Order and punctuation follow your region in System Settings › General › Language & Region.")
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .settingsPane()
    }
}

// MARK: - Calendar

struct CalendarSettings: View {
    @Environment(CalendarStore.self) private var store

    @AppStorage(PrefKey.showWeekNumbers) private var showWeekNumbers = PrefDefault.showWeekNumbers
    @AppStorage(PrefKey.firstWeekday) private var firstWeekday = PrefDefault.firstWeekday
    @AppStorage(PrefKey.dimWeekends) private var dimWeekends = PrefDefault.dimWeekends
    @AppStorage(PrefKey.showAllDayEvents) private var showAllDayEvents = PrefDefault.showAllDayEvents

    var body: some View {
        Form {
            Section("Display") {
                Picker("Week starts on", selection: $firstWeekday) {
                    Text("Region Default (\(regionWeekdayName))").tag(PrefDefault.firstWeekday)
                    Divider()
                    ForEach(1...7, id: \.self) { weekday in
                        Text(Calendar.autoupdatingCurrent.standaloneWeekdaySymbols[weekday - 1]).tag(weekday)
                    }
                }
                Toggle("Show week numbers", isOn: $showWeekNumbers)
                Toggle("Dim weekends", isOn: $dimWeekends)
                Toggle(isOn: $showAllDayEvents) {
                    Text("Show all-day events")
                    Text("Includes events lasting 24 hours or more.")
                }
            }

            calendarsSections
        }
        .formStyle(.grouped)
        // Fixed height: the calendar list can be long, so it scrolls.
        .frame(width: SettingsPane.width, height: 480)
        .onAppear { store.refreshAccess() }
    }

    @ViewBuilder
    private var calendarsSections: some View {
        switch store.access {
        case .granted:
            let groups = calendarsByAccount
            if groups.isEmpty {
                Section("Calendars") {
                    Text("No calendars found.").foregroundStyle(.secondary)
                }
            }
            // One section per account, like Calendar's sidebar.
            ForEach(groups, id: \.account) { group in
                Section(group.account) {
                    ForEach(group.calendars) { calendar in
                        Toggle(isOn: isVisible(calendar)) {
                            Label {
                                Text(calendar.title)
                            } icon: {
                                Circle()
                                    .fill(Color(cgColor: calendar.color))
                                    .frame(width: 10, height: 10)
                            }
                        }
                    }
                }
            }
        case .notDetermined:
            Section("Calendars") {
                LabeledContent("Calendar access") {
                    Button("Allow Access") {
                        NSApp.activate()
                        store.requestAccess()
                    }
                }
            }
        case .denied:
            Section("Calendars") {
                LabeledContent("Calendar access is turned off") {
                    Button("Open Privacy Settings") { SystemSettings.openCalendarPrivacy() }
                }
            }
        }
    }

    private var regionWeekdayName: String {
        let calendar = Calendar.autoupdatingCurrent
        return calendar.standaloneWeekdaySymbols[calendar.firstWeekday - 1]
    }

    /// Calendars grouped by account, in the store's (already sorted) order.
    private var calendarsByAccount: [(account: String, calendars: [CalendarInfo])] {
        var groups: [(account: String, calendars: [CalendarInfo])] = []
        for calendar in store.calendars {
            if groups.last?.account == calendar.account {
                groups[groups.count - 1].calendars.append(calendar)
            } else {
                groups.append((calendar.account, [calendar]))
            }
        }
        return groups
    }

    private func isVisible(_ calendar: CalendarInfo) -> Binding<Bool> {
        Binding(
            get: { !store.isHidden(calendar) },
            set: { store.setHidden(!$0, for: calendar) }
        )
    }
}

// MARK: - Shared

private enum SettingsPane {
    static let width: CGFloat = 480
}

private extension View {
    /// A grouped form that fits its content, for the shorter tabs.
    func settingsPane() -> some View {
        formStyle(.grouped)
            .scrollDisabled(true)
            .frame(width: SettingsPane.width)
            .fixedSize(horizontal: false, vertical: true)
    }
}
