---
name: calendar
description: "Read events from the macOS system calendar (all accounts synced to Apple Calendar — Google, iCloud, Exchange). Use when the user asks about their schedule, meetings, or what's on today/this week."
---

# /calendar — Read calendar events

Read events from the system calendar (macOS EventKit). Reads all calendars synced to Apple Calendar, regardless of source (Google, iCloud, Exchange).

## Usage

```
/calendar              — today's events
/calendar tomorrow     — tomorrow's events
/calendar week         — next 7 days
/calendar <YYYY-MM-DD> — events on a specific date
```

## Implementation

```bash
swift ~/.claude/skills/calendar/calendar.swift [start] [end] [--calendars "Cal1,Cal2"] [--json] [--list]
```

- No args = today. One date = that day. Two dates = range.
- `--calendars` filters to named calendars (comma-separated).
- `--json` outputs structured JSON for programmatic use.
- `--list` shows all available calendars and sources.

**Requires sandbox bypass** — EventKit needs system calendar access. On first run macOS will prompt to grant calendar permission to the terminal.

## When to use

- User asks about schedule, meetings, or "what's on today"
- Checking for conflicts before scheduling
- Meeting preparation

## Not for

- Creating or modifying events (read-only). To create events, use the `google-workspace` MCP (`manage_event`) if available.

## Backends

| Backend | Status | Implementation |
|:--------|:-------|:---------------|
| macOS EventKit | ✅ active | `calendar.swift` — reads all calendars synced to Apple Calendar |
| Google Calendar API | alternative | `google-workspace` MCP `get_events` (headless / non-Mac) |
