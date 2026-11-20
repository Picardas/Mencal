# Backlog

Known fixes and improvements not yet made, with where they came from.

## To do

- **Try AppKit's own swipe tracking** (`NSEvent.trackSwipeEvent`, direction-locked, finger-tracked) in the VM. It runs its own tracking loop, which may not work inside an open menu; the hand-built swipe handling now covers the same fixes (state reset on end or cancel, direction locked at the start, the "Swipe between pages" setting honoured, mouse wheel and trackpad agreeing, right-to-left mirrored).
- **Sync the string catalog** by building once in the Xcode app, then commit `Localizable.xcstrings` (new strings such as "Today, %@" and "Week %lld" are only extracted there).
- **Retake `docs/images/settings-calendar.png`**: it still shows the removed "Remember earlier events choice" setting.

## Done

From the team reviews (November 2026):

- **Hostile text**: one shared sanitiser (`DisplayText`) for event titles and locations, calendar and account names and custom patterns: one line, no bidi overrides or invisible padding, capped by Unicode scalar, "Untitled" for blank-looking titles, "…" when cut. Fitted text is remembered per opening. A hundred heavy titles now build in well under half a second (previously about 10 s).
- **Publishing the event items**: built once per opening, rebuilt only when what they show changes (a sync no longer resets the highlight, closes submenus or shifts rows), and cleared on close. The "earlier" and "more" submenus fill when opened. The menu's screen falls back to the one under the pointer.
- **Data**: all-day and timed events capped separately; declined and cancelled events hidden; deterministic order; other months read off the main thread, overtaken reads dropped; the cache keeps cleaned text, evicts the least recently used month but never today's, and clears on any change or loss of access; hidden calendars remembered by name too, so a resync can't reveal them.
- **Dates**: "Today"/"Tomorrow" right around clock changes and era changes; "All-day" for events running into midnight; "multi-day" by calendar day; year and decade pickers step through real years (no wrong-era jumps) and show 13-month years; Gregorian days as a fallback where Foundation reports broken day lengths (Indic lunisolar calendars); the day heading shows the year when it isn't this year; the decade uses the region's range format.
- **Input**: swipe and wheel fixes as above; wheel clicks between updates add up instead of being lost.
- **Accessibility and polish**: real buttons for days, months and years with one shared look; "Today", full weekday names and "Week N" for VoiceOver; the menu bar item reads the full date; no stale hover highlights; a non-clickable title at the decade; backward/forward chevrons; an SF Symbol event dot.
- **Small fixes**: invisible custom patterns fall back to the calendar symbol; stricter encoding in the `ical://` hand-off; Calendar.app only trusted from `/System/`; login-item status re-checked when the app becomes active; typed notifications for EventKit and UserDefaults; Settings forms share one modifier; sandbox and calendar access also expressed as build settings; a copyright string.
- **Tests and data**: tests no longer start the menu bar item or read calendars when run in the app; 51 tests (up from 25) cover the cases above; the hostile test calendar adds a hostile calendar name, stacked accents, a huge location, blank and leading-space titles, and cancelled and declined events.


Design changes approved by the owner (November 2026):

- **Plain selection circle instead of the Liquid Glass bubble** for the selected day, month and year, as Calendar.app does.
- **Declined invitations and cancelled events are hidden**, as Calendar.app does by default (still to add to the test data, item 23).
- **Events are cached between openings** until calendar data, hidden calendars or access change; the calendar view is still built fresh for each opening.

## Considered and declined

- **Pinch to zoom.** Not possible in a real `NSMenu`: AppKit's menu tracking loop discards pinch (and other gesture) events and only forwards scrolling. Every workaround needs a system-wide input permission, private API, or replacing the menu with a panel.
- **⌘-scroll or vertical swipe to zoom.** Declined; clicking the month name zooms out.
- **Plain vertical trackpad scroll changing the month.** Declined: easy to trigger by accident.
- **Smoothing fast mouse-wheel spins.** Would need a timer; the cost is small and only while spinning.
- **Keyboard navigation of the calendar grid inside the menu.** The open menu takes the arrow keys itself; VoiceOver actions cover the need.
- **Letting the menu bar item be ⌘-dragged out** (`NSStatusItem.behavior = .removalAllowed`). Tried and removed: once removed, the item couldn't be brought back from System Settings › Menu Bar without quitting Mencal. Without it, macOS's own Menu Bar settings hide and show the item, and ⌘-dragging just moves it.
- **Updating "earlier events" while the menu stays open.** Declined by the owner: Mencal is a quick-glance menu, so a meeting ending while it's open doesn't matter and doesn't warrant a re-render or a timer.
- **Background refresh when opening the menu, a midnight safety-net timer, and stepping days with the Gregorian calendar.** No team agreement; revisit only with evidence (a slow or stalled EventKit, a late date change after sleep in the VM, or Indic-calendar users).
