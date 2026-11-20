#!/usr/bin/env python3
"""Generate .ics files for testing Mencal in Calendar.app.

Every date is relative to today, so you can re-run this later and the events
still land around the current date:

    python3 TestData/generate_test_calendars.py            # dates around today
    python3 TestData/generate_test_calendars.py 2026-12-01 # around another day

Import each file into its own new calendar so each gets its own colour.
"""

from __future__ import annotations

import sys
import uuid
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

OUT = Path(__file__).resolve().parent
STAMP = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")


def fold(line: str) -> str:
    """RFC 5545 line folding at 75 octets."""
    data = line.encode("utf-8")
    if len(data) <= 75:
        return line
    parts, current = [], b""
    for char in line:
        encoded = char.encode("utf-8")
        limit = 75 if not parts else 74
        if len(current) + len(encoded) > limit:
            parts.append(current.decode("utf-8"))
            current = b""
        current += encoded
    parts.append(current.decode("utf-8"))
    return "\r\n ".join(parts)


def escape(text: str) -> str:
    return text.replace("\\", "\\\\").replace(";", "\\;").replace(",", "\\,").replace("\n", "\\n")


def local(dt: datetime) -> str:
    """Floating local time: imports at that wall-clock time on the Mac."""
    return dt.strftime("%Y%m%dT%H%M%S")


class Calendar:
    def __init__(self, filename: str, name: str, colour: str):
        self.filename = filename
        self.name = name
        self.colour = colour
        self.events: list[list[str]] = []

    def timed(self, title, day, start, end, *, location=None, rrule=None, notes=None, end_day=None):
        """`start`/`end` are "HH:MM"; `end_day` defaults to `day`."""
        sh, sm = map(int, start.split(":"))
        eh, em = map(int, end.split(":"))
        begin = datetime(day.year, day.month, day.day, sh, sm)
        finish_day = end_day or day
        finish = datetime(finish_day.year, finish_day.month, finish_day.day, eh, em)
        self._add(title, [f"DTSTART:{local(begin)}", f"DTEND:{local(finish)}"], location, rrule, notes)

    def utc(self, title, start: datetime, end: datetime, *, location=None, notes=None):
        fmt = "%Y%m%dT%H%M%SZ"
        self._add(title, [f"DTSTART:{start.strftime(fmt)}", f"DTEND:{end.strftime(fmt)}"], location, None, notes)

    def all_day(self, title, first: date, last: date | None = None, *, location=None, rrule=None, notes=None):
        """Inclusive `first`..`last`; iCalendar's DTEND is exclusive."""
        last = last or first
        self._add(
            title,
            [
                f"DTSTART;VALUE=DATE:{first.strftime('%Y%m%d')}",
                f"DTEND;VALUE=DATE:{(last + timedelta(days=1)).strftime('%Y%m%d')}",
            ],
            location,
            rrule,
            notes,
        )

    def _add(self, title, times, location, rrule, notes):
        lines = ["BEGIN:VEVENT", f"UID:{uuid.uuid4()}@mencal.test", f"DTSTAMP:{STAMP}"]
        if title is not None:
            lines.append(f"SUMMARY:{escape(title)}")
        lines += times
        if rrule:
            lines.append(f"RRULE:{rrule}")
        if location:
            lines.append(f"LOCATION:{escape(location)}")
        if notes:
            lines.append(f"DESCRIPTION:{escape(notes)}")
        lines.append("END:VEVENT")
        self.events.append(lines)

    def write(self):
        lines = [
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "PRODID:-//Mencal//Test Data//EN",
            "CALSCALE:GREGORIAN",
            "METHOD:PUBLISH",
            f"X-WR-CALNAME:{escape(self.name)}",
            f"X-APPLE-CALENDAR-COLOR:{self.colour}",
        ]
        for event in self.events:
            lines += event
        lines.append("END:VCALENDAR")
        path = OUT / self.filename
        path.write_bytes(("\r\n".join(fold(l) for l in lines) + "\r\n").encode("utf-8"))
        return path, len(self.events)


def main(today: date):
    d = lambda n: today + timedelta(days=n)  # noqa: E731
    weekday = today.weekday()  # Monday = 0
    monday = d(-weekday)

    # 1. Work: a normal weekday with overlaps, plus recurring meetings.
    work = Calendar("01-mencal-work.ics", "Mencal Test – Work", "#1BADF8")
    work.timed("Daily stand-up", monday - timedelta(days=14), "09:00", "09:15",
               rrule="FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR;COUNT=60", location="Huddle room")
    work.timed("Weekly planning", monday, "11:00", "12:00", rrule="FREQ=WEEKLY;BYDAY=MO;COUNT=12",
               location="Room 4.02")
    work.timed("1:1 with manager", today, "10:00", "10:30")
    work.timed("Design review", today, "13:00", "14:30", location="Studio, 3rd floor",
               notes="Overlaps with the next event on purpose.")
    work.timed("Customer call", today, "13:30", "14:00", location="https://example.com/meet/abc")
    work.timed("Write release notes", today, "16:00", "17:15")
    work.timed("Team drinks", today, "18:00", "20:00", location="The Corner Pub")
    work.timed("Sprint demo", d(2), "15:00", "16:00")
    work.timed("Quarterly review", d(9), "09:30", "12:00", location="Board room")
    work.all_day("Company offsite", d(14), d(15), location="Lisbon")
    work.timed("Retro", d(-3), "16:00", "17:00")

    # 2. Personal: all-day, multi-day, overnight and yearly events.
    personal = Calendar("02-mencal-personal.ics", "Mencal Test – Personal", "#FF2968")
    personal.all_day("Alex’s birthday", today, rrule="FREQ=YEARLY;COUNT=3")
    personal.all_day("Weekend away", d(3), d(6), location="Lake District")
    personal.timed("Gym", monday - timedelta(days=7), "07:00", "08:00",
                   rrule="FREQ=WEEKLY;BYDAY=MO,WE,FR;COUNT=30", location="Gym")
    personal.timed("Late dinner (crosses midnight)", today, "21:30", "01:00", end_day=d(1),
                   location="Bistro Nord")
    personal.timed("Dentist", d(1), "08:30", "09:00", location="Smile Dental, 12 High St")
    personal.timed("Morning run (finished)", today, "06:30", "07:15")
    personal.all_day("Bin day", d(1), rrule="FREQ=WEEKLY;COUNT=10")

    # 3. Busy day: more than six events tomorrow, to make the list scroll.
    busy = Calendar("03-mencal-busy-day.ics", "Mencal Test – Busy Day", "#63DA38")
    slots = [
        ("08:00", "08:30", "Coffee with Sam", None),
        ("08:45", "09:30", "Interview #1", "Zoom"),
        ("09:30", "10:15", "Interview #2", "Zoom"),
        ("10:30", "11:00", "Budget sync", None),
        ("11:00", "11:45", "Vendor demo", "Room 2.10"),
        ("12:00", "12:00", "Reminder: submit expenses (zero length)", None),
        ("12:30", "13:30", "Lunch", "Canteen"),
        ("14:00", "15:00", "Architecture deep-dive on the calendar sync engine "
                           "and offline caching strategy for the next release", None),
        ("15:15", "15:45", "🎉 Launch party prep", None),
        ("16:00", "16:30", "Συνάντηση ομάδας", "Αθήνα"),
        ("17:00", "17:30", "Wrap-up", None),
    ]
    for start, end, title, location in slots:
        busy.timed(title, d(1), start, end, location=location)
    busy.timed(None, d(1), "18:00", "18:30")  # no title → shown as "Untitled"

    # 4. Edge cases: boundaries, multi-day timed events, other time zones,
    #    and days at the edges of the month grid.
    edge = Calendar("04-mencal-edge-cases.ics", "Mencal Test – Edge Cases", "#CC73E1")
    edge.timed("Hackathon (3 days, timed)", d(-1), "15:00", "11:00", end_day=d(1),
               notes="Today shows All-day; tomorrow shows Until 11:00.")
    edge.timed("Midnight release", d(2), "00:00", "00:30")
    edge.timed("Last call", d(2), "23:30", "23:59")
    edge.utc("New York sync (09:00 EST)",
             datetime(d(4).year, d(4).month, d(4).day, 14, 0, tzinfo=timezone.utc),
             datetime(d(4).year, d(4).month, d(4).day, 15, 0, tzinfo=timezone.utc),
             notes="Stored in UTC; should appear in your local time.")
    edge.utc("Tokyo call (09:00 JST)",
             datetime(d(5).year, d(5).month, d(5).day, 0, 0, tzinfo=timezone.utc),
             datetime(d(5).year, d(5).month, d(5).day, 1, 0, tzinfo=timezone.utc))

    first_of_month = today.replace(day=1)
    next_month = (first_of_month + timedelta(days=32)).replace(day=1)
    last_of_month = next_month - timedelta(days=1)
    edge.all_day("Last day of previous month", first_of_month - timedelta(days=1))
    edge.timed("First of next month", next_month, "10:00", "11:00")
    edge.all_day("Spans the month boundary", last_of_month - timedelta(days=2), next_month + timedelta(days=2))
    edge.all_day("Two-week project", d(-10), d(3))
    edge.all_day("New Year's Day", date(today.year + 1, 1, 1))

    for calendar in (work, personal, busy, edge):
        path, count = calendar.write()
        print(f"{path.name}: {count} events")


if __name__ == "__main__":
    base = date.fromisoformat(sys.argv[1]) if len(sys.argv) > 1 else date.today()
    main(base)
