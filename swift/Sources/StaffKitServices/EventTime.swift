import Foundation

/// Parses the API's ISO 8601 timestamps, with or without fractional seconds.
public func parseInstant(_ value: String?) -> Date? {
    guard let value else { return nil }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
}

public func isoInstant(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }

/// A calendar in `zone`, for reading and building wall-clock times at the venue.
public func venueCalendar(_ zone: TimeZone) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    calendar.locale = .current
    return calendar
}

/// Reads "yyyy-MM-dd" and "HH:mm" values as dates in UTC, for date-only and time-only pickers.
public enum CivilDate {
    public static let utc = TimeZone(secondsFromGMT: 0)!
    public static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = utc
        formatter.dateFormat = format
        return formatter
    }
    public static func date(_ value: String) -> Date? { formatter("yyyy-MM-dd").date(from: value) }
    public static func string(_ date: Date) -> String { formatter("yyyy-MM-dd").string(from: date) }
    public static func time(_ value: String) -> Date? { formatter("HH:mm").date(from: value) }
    public static func timeString(_ date: Date) -> String { formatter("HH:mm").string(from: date) }
    /// Today's date at the venue, as a UTC-midnight civil date.
    public static func today(in zone: TimeZone) -> Date {
        date(string(from: Date(), in: zone)) ?? Date()
    }
    public static func string(from instant: Date, in zone: TimeZone) -> String {
        let formatter = formatter("yyyy-MM-dd")
        formatter.timeZone = zone
        return formatter.string(from: instant)
    }
    public static func timeString(from instant: Date, in zone: TimeZone) -> String {
        let formatter = formatter("HH:mm"); formatter.timeZone = zone
        return formatter.string(from: instant)
    }
    /// The instant a series' first date and local time ("yyyy-MM-dd", "HH:mm") fall on in `zone`.
    public static func instant(on day: String, at time: String, in zone: TimeZone) -> Date? {
        let formatter = formatter("yyyy-MM-dd HH:mm"); formatter.timeZone = zone
        return formatter.date(from: "\(day) \(time)")
    }
    /// "Oct 10" or "Fri, Oct 10" for a civil date.
    public static func label(_ date: Date, weekday: Bool = false) -> String {
        var style = weekday ? Date.FormatStyle.dateTime.weekday(.abbreviated).month(.abbreviated).day()
                            : Date.FormatStyle.dateTime.month(.abbreviated).day()
        style.timeZone = utc
        return date.formatted(style)
    }
    /// "9 PM" or "9:30 PM" for "21:00" or "21:30".
    public static func clock(_ value: String) -> String {
        guard let date = time(value) else { return value }
        var style = value.hasSuffix(":00") ? Date.FormatStyle.dateTime.hour() : Date.FormatStyle.dateTime.hour().minute()
        style.timeZone = utc
        return date.formatted(style)
    }
}

/// US zones, plus the device's and the series' own.
public func zoneChoices(including extra: [String]) -> [String] {
    let curated = ["America/Los_Angeles", "America/Denver", "America/Phoenix", "America/Chicago", "America/New_York", "America/Anchorage", "Pacific/Honolulu"]
    var zones = curated
    for zone in extra where !zones.contains(zone) && TimeZone(identifier: zone) != nil { zones.append(zone) }
    return zones
}

public func zoneName(_ identifier: String) -> String {
    guard let zone = TimeZone(identifier: identifier) else { return identifier }
    let name = zone.localizedName(for: .generic, locale: .current) ?? identifier
    let city = identifier.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") } ?? identifier
    return "\(name) (\(city))"
}
