import Foundation

// The venue's own clock: times and nights read at the venue, whatever zone the device is in. Shared by Velvet's
// screens and the marquee that the iPad, the Mac (Velvet Display) and a TV show.

/// "Fri, Oct 10 · 9:00 PM" at the venue.
public func venueDate(_ value: String?, in zone: TimeZone) -> String {
    guard let date = parseInstant(value) else { return value ?? "Time to be announced" }
    return venueDate(date, in: zone)
}

public func venueDate(_ date: Date, in zone: TimeZone) -> String {
    var style = Date.FormatStyle.dateTime.weekday(.abbreviated).month(.abbreviated).day()
    style.timeZone = zone
    var time = Date.FormatStyle.dateTime.hour().minute()
    time.timeZone = zone
    return "\(date.formatted(style)) · \(date.formatted(time))"
}

/// "9:00 PM" at the venue.
public func venueTime(_ date: Date, in zone: TimeZone) -> String {
    var style = Date.FormatStyle.dateTime.hour().minute()
    style.timeZone = zone
    return date.formatted(style)
}

extension VenueWorkspace {
    /// The zone its nights, cover and events are counted in.
    public var zone: TimeZone { coverTimeZone.flatMap(TimeZone.init(identifier:)) ?? .current }

    /// Tonight, as the door counts it: from 6 AM on the door's night to 6 AM the next morning.
    public var tonight: DateInterval {
        let calendar = venueCalendar(zone)
        let start: Date
        if let night = door?.night, let day = CivilDate.date(night) {
            let parts = Calendar(identifier: .gregorian).dateComponents(in: CivilDate.utc, from: day)
            start = calendar.date(from: DateComponents(year: parts.year, month: parts.month, day: parts.day, hour: 6)) ?? Date()
        } else {
            let shifted = Date().addingTimeInterval(-6 * 3600)
            start = calendar.date(byAdding: .hour, value: 6, to: calendar.startOfDay(for: shifted)) ?? Date()
        }
        return DateInterval(start: start, duration: 24 * 3600)
    }

    /// Whether an event is tonight's: it starts in tonight's window, or started earlier and hasn't ended.
    public func isTonight(_ event: VenueEvent) -> Bool {
        guard let start = parseInstant(event.startAt) else { return false }
        return tonight.contains(start) || (start < Date() && (parseInstant(event.endAt).map { $0 > Date() } ?? false))
    }
}

extension VenueEvent {
    public var start: Date? { parseInstant(startAt) }
}
