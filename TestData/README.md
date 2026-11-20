# Test calendars

Four `.ics` files with events placed around **today**, for testing Mencal in Calendar.app.

| File | Calendar | What it tests |
|---|---|---|
| `01-mencal-work.ics` | Work (blue) | A normal weekday: recurring stand-up, overlapping meetings, locations, an evening event, past and future days |
| `02-mencal-personal.ics` | Personal (pink) | All-day and multi-day all-day events, a yearly birthday, an event that crosses midnight, a finished morning event (dimmed) |
| `03-mencal-busy-day.ics` | Busy Day (green) | 12 events tomorrow, so the list scrolls. Includes a very long title, emoji, Greek text, a zero-length event and an untitled event |
| `04-mencal-edge-cases.ics` | Edge Cases (purple) | A timed event spanning 3 days, midnight and 23:30 events, UTC-stored events (New York, Tokyo), events on the grid's leading and trailing days, an all-day event across the month boundary, New Year's Day |

## Importing

1. In Calendar.app choose **File › Import…** and pick one file.
2. When asked where to add the events, choose **New Calendar**, so each file gets its own calendar and colour. Make sure it's created under **On My Mac**, not iCloud, so the test events don't sync to your other devices.
3. Repeat for each file.

The quickest way to remove everything afterwards is to delete the four *Mencal Test – …* calendars.

## Regenerating

The dates are relative to the day you generate them. To refresh them later, or to centre them on another date:

```bash
python3 TestData/generate_test_calendars.py
```

```bash
python3 TestData/generate_test_calendars.py 2027-01-15
```
