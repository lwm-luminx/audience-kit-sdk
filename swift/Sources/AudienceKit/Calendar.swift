import AudienceCore
import Foundation

/// A calendar subscription's links (API doc/CALENDAR_SYNC.md): an iCalendar feed that Apple Calendar, Google Calendar
/// and Outlook poll, so new, moved and canceled events follow on their own.
public struct CalendarLinks: Decodable, Sendable, Hashable {
    /// The https feed, to copy or share.
    public let url: String
    /// The same link as webcal://, which Calendar (and Outlook) open as a subscription.
    public let webcalUrl: String
    /// Google Calendar's page that adds the subscription, for Android and the web.
    public let googleUrl: String

    public init(url: String, webcalUrl: String, googleUrl: String) {
        self.url = url
        self.webcalUrl = webcalUrl
        self.googleUrl = googleUrl
    }

    /// The links for a feed at `feed`: its webcal:// form and Google Calendar's add-by-URL page, as the API makes them.
    public init(feed: URL) {
        let url = feed.absoluteString
        let webcal = url.replacingOccurrences(of: #"^https?://"#, with: "webcal://", options: .regularExpression)
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let cid = webcal.addingPercentEncoding(withAllowedCharacters: allowed) ?? webcal
        self.init(url: url, webcalUrl: webcal, googleUrl: "https://calendar.google.com/calendar/render?cid=\(cid)")
    }

    public var feedURL: URL? { URL(string: url) }
    public var webcalURL: URL? { URL(string: webcalUrl) }
    public var googleURL: URL? { URL(string: googleUrl) }
}

/// The signed-in person's one calendar subscription in the audience (API doc/CALENDAR_SYNC.md): the events they're
/// going to, their talent's slots, their shifts, and every event at the venues they follow. Following a venue adds
/// to this same feed rather than making another calendar.
public struct CalendarFeed: Decodable, Sendable, Hashable {
    public let links: CalendarLinks
    /// The venues it follows (the ones they may still see).
    public let venueIDs: [String]

    public init(links: CalendarLinks, venueIDs: [String] = []) {
        self.links = links
        self.venueIDs = venueIDs
    }

    /// Whether every event at the venue is in it.
    public func follows(venueID: String) -> Bool { venueIDs.contains(venueID) }

    private enum CodingKeys: String, CodingKey { case venues }
    private struct VenueRef: Decodable { let id: String }

    public init(from decoder: any Decoder) throws {
        links = try CalendarLinks(from: decoder)
        venueIDs = try decoder.container(keyedBy: CodingKeys.self)
            .decodeIfPresent([VenueRef].self, forKey: .venues)?.map(\.id) ?? []
    }
}

extension Queries {
    static let calendarFeedFields = "url webcalUrl googleUrl venues { id }"

    static let calendarFeed = "query CalendarFeed { me { calendarFeed { \(calendarFeedFields) } } }"

    static let createCalendarFeed = """
    mutation CreateCalendarFeed($reset: Boolean) {
      createCalendarFeed(input: { reset: $reset }) { calendarFeed { \(calendarFeedFields) } }
    }
    """

    static let setCalendarFeedVenue = """
    mutation SetCalendarFeedVenue($venueId: ID!, $following: Boolean) {
      setCalendarFeedVenue(input: { venueId: $venueId, following: $following }) {
        calendarFeed { \(calendarFeedFields) }
      }
    }
    """

    static let deleteCalendarFeed = "mutation DeleteCalendarFeed { deleteCalendarFeed(input: {}) { deleted } }"
}

extension AudienceSession {
    /// The signed-in person's calendar subscription, or nil before they made one.
    public func calendarFeed() async throws -> CalendarFeed? {
        struct Response: Decodable, Sendable {
            struct Me: Decodable, Sendable { let calendarFeed: CalendarFeed? }
            let me: Me?
        }
        return try await graphQL(Queries.calendarFeed, operationName: "CalendarFeed", as: Response.self).me?
            .calendarFeed
    }

    /// Their subscription, made on first ask; `reset` gives it a new link, so the old one stops working.
    public func createCalendarFeed(reset: Bool = false) async throws -> CalendarFeed {
        struct Response: Decodable, Sendable {
            struct Payload: Decodable, Sendable { let calendarFeed: CalendarFeed }
            let createCalendarFeed: Payload
        }
        return try await graphQL(Queries.createCalendarFeed, variables: ["reset": .bool(reset)],
                                 operationName: "CreateCalendarFeed", as: Response.self).createCalendarFeed
            .calendarFeed
    }

    /// Follows a venue in their subscription, so every event there shows up in their calendar (or, with
    /// `following: false`, stops). Makes the subscription on first ask; subscribe to ``CalendarFeed/links`` once.
    /// The API refuses a venue they may not see ("Venue not found").
    public func followVenueInCalendar(venueID: String, following: Bool = true) async throws -> CalendarFeed {
        struct Response: Decodable, Sendable {
            struct Payload: Decodable, Sendable { let calendarFeed: CalendarFeed }
            let setCalendarFeedVenue: Payload
        }
        return try await graphQL(Queries.setCalendarFeedVenue,
                                 variables: ["venueId": .string(venueID), "following": .bool(following)],
                                 operationName: "SetCalendarFeedVenue", as: Response.self).setCalendarFeedVenue
            .calendarFeed
    }

    /// Ends their subscription: calendars subscribed to it stop updating.
    @discardableResult
    public func deleteCalendarFeed() async throws -> Bool {
        struct Response: Decodable, Sendable {
            struct Payload: Decodable, Sendable { let deleted: Bool }
            let deleteCalendarFeed: Payload?
        }
        return try await graphQL(Queries.deleteCalendarFeed, operationName: "DeleteCalendarFeed", as: Response.self)
            .deleteCalendarFeed?.deleted ?? false
    }
}
