import EventKit
import Foundation

// calendar.swift — Read macOS Calendar events via EventKit
// Usage: swift calendar.swift [start_date] [end_date] [--calendars "Cal1,Cal2"] [--json]
//   No args: today's events from all calendars
//   One date: that day's events
//   Two dates: range (start inclusive, end exclusive)
//   --calendars: filter to named calendars (comma-separated)
//   --json: output as JSON instead of text
//   --list: list all available calendars and exit

let args = CommandLine.arguments
let store = EKEventStore()
let sem = DispatchSemaphore(value: 0)
store.requestFullAccessToEvents { granted, error in
    if !granted {
        print("ERROR: Calendar access denied. Grant Full Access in System Settings > Privacy > Calendars.")
    }
    sem.signal()
}
sem.wait()

let df = DateFormatter()
df.dateFormat = "yyyy-MM-dd"
df.timeZone = TimeZone.current

let tf = DateFormatter()
tf.dateFormat = "HH:mm"
tf.timeZone = TimeZone.current

let dayf = DateFormatter()
dayf.dateFormat = "EEE yyyy-MM-dd"
dayf.timeZone = TimeZone.current

// Parse flags
var positional: [String] = []
var calendarFilter: [String] = []
var jsonOutput = false
var listMode = false

var i = 1
while i < args.count {
    if args[i] == "--calendars" && i + 1 < args.count {
        calendarFilter = args[i + 1].components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        i += 2
    } else if args[i] == "--json" {
        jsonOutput = true
        i += 1
    } else if args[i] == "--list" {
        listMode = true
        i += 1
    } else {
        positional.append(args[i])
        i += 1
    }
}

// List mode
if listMode {
    let cals = store.calendars(for: .event).sorted { $0.source.title < $1.source.title }
    for c in cals {
        print("\(c.source.title) / \(c.title)")
    }
    exit(0)
}

// Date range
let cal = Calendar.current
let start: Date
let end: Date

if positional.count >= 2 {
    guard let s = df.date(from: positional[0]), let e = df.date(from: positional[1]) else {
        print("ERROR: Invalid date format. Use YYYY-MM-DD.")
        exit(1)
    }
    start = cal.startOfDay(for: s)
    end = cal.startOfDay(for: e)
} else if positional.count == 1 {
    if positional[0] == "tomorrow" {
        let tom = cal.date(byAdding: .day, value: 1, to: Date())!
        start = cal.startOfDay(for: tom)
        end = cal.date(byAdding: .day, value: 1, to: start)!
    } else if positional[0] == "week" {
        start = cal.startOfDay(for: Date())
        end = cal.date(byAdding: .day, value: 7, to: start)!
    } else {
        guard let s = df.date(from: positional[0]) else {
            print("ERROR: Invalid date format. Use YYYY-MM-DD, 'tomorrow', or 'week'.")
            exit(1)
        }
        start = cal.startOfDay(for: s)
        end = cal.date(byAdding: .day, value: 1, to: start)!
    }
} else {
    start = cal.startOfDay(for: Date())
    end = cal.date(byAdding: .day, value: 1, to: start)!
}

// Filter calendars
var ekCalendars: [EKCalendar]? = nil
if !calendarFilter.isEmpty {
    let all = store.calendars(for: .event)
    let filtered = all.filter { c in calendarFilter.contains(c.title) }
    ekCalendars = filtered.isEmpty ? nil : filtered
}

let pred = store.predicateForEvents(withStart: start, end: end, calendars: ekCalendars)
let events = store.events(matching: pred).sorted { $0.startDate < $1.startDate }

if events.isEmpty {
    print("No events found.")
    exit(0)
}

if jsonOutput {
    var items: [[String: String]] = []
    for e in events {
        var item: [String: String] = [
            "title": e.title ?? "(no title)",
            "start": df.string(from: e.startDate) + "T" + tf.string(from: e.startDate),
            "end": df.string(from: e.endDate) + "T" + tf.string(from: e.endDate),
            "calendar": e.calendar.title,
            "all_day": e.isAllDay ? "true" : "false"
        ]
        if let loc = e.location, !loc.isEmpty { item["location"] = loc }
        if let notes = e.notes, !notes.isEmpty { item["notes"] = String(notes.prefix(200)) }
        items.append(item)
    }
    // Manual JSON output (no JSONSerialization for simple cases)
    print("[")
    for (idx, item) in items.enumerated() {
        let pairs = item.sorted(by: { $0.key < $1.key }).map { k, v in
            "    \"\(k)\": \"\(v.replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: "\\n"))\""
        }.joined(separator: ",\n")
        print("  {\n\(pairs)\n  }\(idx < items.count - 1 ? "," : "")")
    }
    print("]")
} else {
    var currentDay = ""
    for e in events {
        let day = dayf.string(from: e.startDate)
        if day != currentDay {
            if !currentDay.isEmpty { print("") }
            print("## \(day)")
            currentDay = day
        }
        let time: String
        if e.isAllDay {
            time = "all-day"
        } else {
            time = "\(tf.string(from: e.startDate))-\(tf.string(from: e.endDate))"
        }
        var line = "\(time)  \(e.title ?? "(no title)")"
        if let loc = e.location, !loc.isEmpty { line += "  [\(loc)]" }
        line += "  (\(e.calendar.title))"
        print(line)
    }
}
