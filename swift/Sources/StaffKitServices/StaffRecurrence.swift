import Foundation

/// The schedules the editor offers, read from and written to an RFC 5545 rule. Managers never see the rule.
public struct StaffRecurrence: Equatable, Sendable {
    public enum Frequency: Hashable, Sendable { case daily, weekly, biweekly, monthly }
    public static let weekdays = ["MO", "TU", "WE", "TH", "FR", "SA", "SU"]
    public static let ordinals = [(1, "First"), (2, "Second"), (3, "Third"), (4, "Fourth"), (-1, "Last")]

    public var frequency: Frequency = .weekly
    /// For weekly schedules, e.g. ["FR", "SA"].
    public var days: Set<String> = ["FR"]
    /// For monthly schedules: 1 through 4, or -1 for the last.
    public var ordinal = 1
    public var monthlyDay = "SA"
    /// The last date it can fall on (the venue's), or nil to repeat forever.
    public var until: Date?

    public init() {}
    /// Nil for rules the editor doesn't offer, e.g. daily or by month day.
    public init?(rrule: String, zone: TimeZone) {
        let parts = Dictionary(rrule.uppercased().split(separator: ";").compactMap { part -> (String, String)? in
            let pair = part.split(separator: "=", maxSplits: 1).map(String.init)
            return pair.count == 2 ? (pair[0], pair[1]) : nil
        }, uniquingKeysWith: { $1 })
        let known: Set<String> = ["FREQ", "INTERVAL", "BYDAY", "UNTIL", "WKST"]
        guard Set(parts.keys).isSubset(of: known) else { return nil }
        let byDay = parts["BYDAY"] ?? ""
        let interval = Int(parts["INTERVAL"] ?? "1") ?? 0
        switch (parts["FREQ"], interval) {
        case ("DAILY", 1): frequency = .daily
        case ("WEEKLY", 1), ("WEEKLY", 2):
            let days = byDay.split(separator: ",").map(String.init)
            guard !days.isEmpty, days.allSatisfy(Self.weekdays.contains) else { return nil }
            frequency = interval == 2 ? .biweekly : .weekly
            self.days = Set(days)
        case ("MONTHLY", 1):
            let day = String(byDay.suffix(2))
            guard let ordinal = Int(byDay.dropLast(2)), Self.weekdays.contains(day), [1, 2, 3, 4, -1].contains(ordinal) else { return nil }
            frequency = .monthly; self.ordinal = ordinal; monthlyDay = day
        default: return nil
        }
        if let value = parts["UNTIL"] {
            guard let date = Self.untilDate(value, zone: zone) else { return nil }
            until = date
        }
    }

    public func rrule(zone: TimeZone) -> String {
        var rule: String
        switch frequency {
        case .daily: rule = "FREQ=DAILY"
        case .weekly, .biweekly:
            rule = "FREQ=WEEKLY" + (frequency == .biweekly ? ";INTERVAL=2" : "")
            rule += ";BYDAY=" + Self.weekdays.filter(days.contains).joined(separator: ",")
        case .monthly: rule = "FREQ=MONTHLY;BYDAY=\(ordinal)\(monthlyDay)"
        }
        if let until { rule += ";UNTIL=" + Self.untilValue(until, zone: zone) }
        return rule
    }
    public var isValid: Bool { frequency == .daily || frequency == .monthly || !days.isEmpty }

    /// The end of the last date at the venue, in UTC, so a late start that night still counts.
    public static func untilValue(_ date: Date, zone: TimeZone) -> String {
        let parts = Calendar(identifier: .gregorian).dateComponents(in: CivilDate.utc, from: date)
        let local = venueCalendar(zone).date(from: DateComponents(year: parts.year, month: parts.month, day: parts.day, hour: 23, minute: 59, second: 59)) ?? date
        let formatter = CivilDate.formatter("yyyyMMdd'T'HHmmss'Z'")
        return formatter.string(from: local)
    }
    public static func untilDate(_ value: String, zone: TimeZone) -> Date? {
        if value.count == 8 { return CivilDate.formatter("yyyyMMdd").date(from: value) }
        guard let instant = CivilDate.formatter("yyyyMMdd'T'HHmmss'Z'").date(from: value) else { return nil }
        return CivilDate.date(CivilDate.string(from: instant, in: zone))
    }

    public static func shortSymbol(_ code: String) -> String {
        Calendar.current.shortWeekdaySymbols[((weekdays.firstIndex(of: code) ?? 0) + 1) % 7]
    }
    public static func longSymbol(_ code: String) -> String {
        Calendar.current.weekdaySymbols[((weekdays.firstIndex(of: code) ?? 0) + 1) % 7]
    }

    /// "Every Friday", "Every other Tuesday and Thursday", "The last Saturday of every month".
    public var sentence: String {
        switch frequency {
        case .daily: return "Every day"
        case .weekly, .biweekly:
            let names = Self.weekdays.filter(days.contains).map(Self.longSymbol)
            let list = names.count > 1 ? names.dropLast().joined(separator: ", ") + " and " + names.last! : names.first ?? "week"
            return (frequency == .biweekly ? "Every other " : "Every ") + list
        case .monthly:
            let word = Self.ordinals.first { $0.0 == ordinal }?.1.lowercased() ?? "first"
            return "The \(word) \(Self.longSymbol(monthlyDay)) of every month"
        }
    }

    /// The next dates it falls on from `from`, as UTC-midnight civil dates, leaving out skipped ones.
    public func dates(startsOn: Date, from: Date, skipped: Set<String>, count: Int) -> [Date] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = CivilDate.utc
        calendar.firstWeekday = 2
        var results: [Date] = []
        var day = max(startsOn, from)
        let anchorWeek = calendar.dateInterval(of: .weekOfYear, for: startsOn)?.start ?? startsOn
        var guardCount = 0
        while results.count < count && guardCount < 800 {
            guardCount += 1
            if let until, day > until { break }
            if matches(day, calendar: calendar, anchorWeek: anchorWeek) && !skipped.contains(CivilDate.string(day)) { results.append(day) }
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? day
        }
        return results
    }
    private func matches(_ day: Date, calendar: Calendar, anchorWeek: Date) -> Bool {
        let code = Self.weekdays[(calendar.component(.weekday, from: day) + 5) % 7]
        switch frequency {
        case .daily: return true
        case .weekly: return days.contains(code)
        case .biweekly:
            guard days.contains(code), let week = calendar.dateInterval(of: .weekOfYear, for: day)?.start else { return false }
            let weeks = (calendar.dateComponents([.day], from: anchorWeek, to: week).day ?? 0) / 7
            return weeks % 2 == 0
        case .monthly:
            guard code == monthlyDay else { return false }
            let dayOfMonth = calendar.component(.day, from: day)
            if ordinal == -1 {
                let range = calendar.range(of: .day, in: .month, for: day) ?? 1..<32
                return dayOfMonth + 7 > range.upperBound - 1
            }
            return (dayOfMonth - 1) / 7 + 1 == ordinal
        }
    }
}
