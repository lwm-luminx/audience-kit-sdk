import Foundation

/// When a coming event starts, as the board says it (Rick, 2026-11-23: "8pm on Tuesday", "8pm Next Tuesday" or "8pm
/// on Tuesday the 12th"): the time first, then the weekday alone for the next six days, when it can only mean one
/// night; "Next" and the weekday for the week after; and the weekday with the day of the month from two weeks out, so
/// Tuesdays a week apart read as different nights. More than four weeks out it names the month too. Every screen's
/// board uses it (Mac, Apple TV, iPad; keep the Android board in step).
public enum MarqueeWhen {
    /// - Parameters:
    ///   - date: when the event starts.
    ///   - now: the moment the board is drawn.
    ///   - zone: the venue's time zone; days are counted and times read there.
    public static func label(_ date: Date, now: Date = Date(), zone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = calendar.dateComponents([.hour, .minute, .weekday, .day, .month], from: date)
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                           to: calendar.startOfDay(for: date)).day ?? 0
        let weekday = weekdays[((parts.weekday ?? 1) - 1) % 7]
        let clock = time(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
        if (0...6).contains(days) { return "\(clock) on \(weekday)" }
        if (7...13).contains(days) { return "\(clock) Next \(weekday)" }
        var text = "\(clock) on \(weekday) the \(ordinal(parts.day ?? 1))"
        if days < 0 || days > 28 { text += " of \(months[((parts.month ?? 1) - 1) % 12])" }
        return text
    }

    /// "8pm", "8:30pm", "12am".
    static func time(hour: Int, minute: Int) -> String {
        let twelve = hour % 12 == 0 ? 12 : hour % 12
        let suffix = hour < 12 ? "am" : "pm"
        return minute == 0 ? "\(twelve)\(suffix)" : "\(twelve):" + (minute < 10 ? "0" : "") + "\(minute)\(suffix)"
    }

    /// "1st", "2nd", "3rd", "4th", "11th", "22nd".
    static func ordinal(_ day: Int) -> String {
        let suffix: String
        switch (day % 100, day % 10) {
        case (11...13, _): suffix = "th"
        case (_, 1): suffix = "st"
        case (_, 2): suffix = "nd"
        case (_, 3): suffix = "rd"
        default: suffix = "th"
        }
        return "\(day)\(suffix)"
    }

    private static let weekdays = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    private static let months = ["January", "February", "March", "April", "May", "June", "July", "August", "September",
                                 "October", "November", "December"]
}

/// Which sets the board's lineup lists: what's on and what's next first, then the last few finished sets only while
/// there's room, so a long night never pushes whoever is on off the bottom. The finished ones are drawn faded, the
/// "just happened" row (Rick, 2026-11-23: "bring the faded row to tvOS and macOS"). The same rule as the Google TV
/// board's `tvLineup`.
public enum MarqueeLineup {
    /// How many sets the board has room for.
    public static let rows = 8
    /// How many coming events go under a lineup of this many sets: up to three under a short one, none once the
    /// lineup needs the room (the Google TV board's rule).
    public static func comingUpCount(under sets: Int) -> Int { min(Swift.max(5 - sets, 0), 3) }

    public static func window<Entry>(_ order: [Entry], max: Int = rows, isDone: (Entry) -> Bool) -> [Entry] {
        let done = order.filter(isDone)
        let live = order.filter { !isDone($0) }
        return Array((done.suffix(Swift.max(max - live.count, 0)) + live).prefix(max))
    }
}
