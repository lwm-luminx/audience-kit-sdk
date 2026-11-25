import Foundation

/// An upcoming event's full-screen poster on the venue's TV, in the loop between looks at the lineup with the slogan
/// slides and the safety screen: its picture, what, when, who, cover, and a code to the event. Velvet's marquee
/// (displays and AirPlay) draws it, and `VenueCastBoard` sends it to the cast receiver, which draws the same poster.
public struct MarqueeEventPoster: Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    /// "Tonight · 9 PM", "Tomorrow · 9:30 PM" or "Fri, Dec 5 · 9 PM", at the venue.
    public var when: String
    /// "with Anya · Darcy", or "" with nobody billed.
    public var billing: String
    /// "Free" or "$10 cover"; nil for the venue's usual cover.
    public var cover: String?
    /// The event's banner (https only), or nil to draw the poster from its words alone.
    public var image: String?
    /// Its page on hotmess.social, which opens the event in Hot Mess.
    public var link: String

    public init(id: String, name: String, when: String, billing: String = "", cover: String? = nil, image: String? = nil,
                link: String? = nil) {
        self.id = id; self.name = name; self.when = when; self.billing = billing; self.cover = cover
        self.image = image.flatMap { $0.hasPrefix("https://") ? $0 : nil }
        self.link = link ?? "https://hotmess.social/events/\(id)"
    }

    /// How far ahead the loop looks, and how many posters it takes turns with.
    public static let days = 14
    public static let limit = 6

    /// The venue's posters: events from tonight's (not yet over) through the next `days` days, soonest first, at most
    /// `limit`, leaving out canceled ones.
    public static func upcoming(_ events: [VenueEvent], tonight: DateInterval, zone: TimeZone,
                                at now: Date = Date()) -> [MarqueeEventPoster] {
        let horizon = tonight.end.addingTimeInterval(Double(days - 1) * 24 * 3600)
        return events
            .filter { event in
                guard !event.isCanceled, let start = event.start, start < horizon else { return false }
                let end = parseInstant(event.endAt) ?? start.addingTimeInterval(4 * 3600)
                return end > now && end > tonight.start
            }
            .sorted { ($0.start ?? .distantFuture) < ($1.start ?? .distantFuture) }
            .prefix(limit)
            .map { poster(for: $0, tonight: tonight, zone: zone) }
    }

    static func poster(for event: VenueEvent, tonight: DateInterval, zone: TimeZone) -> MarqueeEventPoster {
        // Its lineup as billed ("KJ Dalton"); with nobody on it, who hosts it ("Hosted by KJ Dalton": a lone KJ hosts).
        let names = event.people.compactMap { event.billedName($0) }
        let cover: String? = event.coverCents.map { cents in
            if cents == 0 { return "Free" }
            // A sliding scale shows its range: "$5–$30 cover, pay what you can".
            if let min = event.coverMinCents, let max = event.coverMaxCents {
                return "\(dollars(min))–\(dollars(max)) cover, pay what you can"
            }
            return "\(dollars(cents)) cover"
        }
        return MarqueeEventPoster(id: event.id, name: event.name ?? "Event", when: when(event.start, tonight: tonight, zone: zone),
                                  billing: names.isEmpty ? event.billing ?? "" : "with " + names.prefix(4).joined(separator: " · "),
                                  cover: cover, image: event.bannerUrl)
    }

    /// "Tonight · 9 PM", "Tomorrow · 9 PM", else "Fri, Dec 5 · 9 PM".
    static func when(_ start: Date?, tonight: DateInterval, zone: TimeZone) -> String {
        guard let start else { return "" }
        let time = DateFormatter()
        time.locale = Locale(identifier: "en_US_POSIX")
        time.timeZone = zone
        time.dateFormat = venueCalendar(zone).component(.minute, from: start) == 0 ? "h a" : "h:mm a"
        let day: String
        if start < tonight.end {
            day = "Tonight"
        } else if start < tonight.end.addingTimeInterval(24 * 3600) {
            day = "Tomorrow"
        } else {
            let format = DateFormatter()
            format.locale = time.locale
            format.timeZone = zone
            format.dateFormat = "EEE, MMM d"
            day = format.string(from: start)
        }
        return "\(day) · \(time.string(from: start))"
    }

    private static func dollars(_ cents: Int) -> String {
        cents % 100 == 0 ? "$\(cents / 100)" : String(format: "$%d.%02d", cents / 100, cents % 100)
    }

    /// What the cast receiver reads for it.
    public var castMessage: [String: Any] {
        var poster: [String: Any] = ["id": id, "name": name, "when": when, "billing": billing, "link": link]
        if let cover { poster["cover"] = cover }
        if let image { poster["image"] = image }
        return poster
    }
}

extension VenueWorkspace {
    /// Its upcoming events' TV posters (`MarqueeEventPoster.upcoming`).
    public func eventPosters(at now: Date = Date()) -> [MarqueeEventPoster] {
        MarqueeEventPoster.upcoming(events, tonight: tonight, zone: zone, at: now)
    }
}
