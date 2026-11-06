import AudienceCore
import Foundation

/// Which events ``AudienceSession/events(window:localeID:venueID:first:)`` lists: the API's `EventWindow`.
public enum EventWindow: String, Sendable, Hashable, CaseIterable {
    /// Those still to come or under way, soonest first.
    case upcoming = "UPCOMING"
    /// Those that have ended, latest first.
    case past = "PAST"
}

/// A venue an event or series is at: the `venue { venue }` of the API's venues module.
public struct EventVenue: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String?
    public let photoUrl: String?
    /// Where it is (its point is decoded from the API's WKT); nil when it has no location.
    public let location: Location?

    public init(id: String, name: String? = nil, photoUrl: String? = nil, location: Location? = nil) {
        self.id = id
        self.name = name
        self.photoUrl = photoUrl
        self.location = location
    }
}

/// Someone on an event's bill: a host or a performer on its lineup (the API's `Person`, as far as a list shows it).
public struct EventPerson: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String?
    public let avatarUrl: String?

    public init(id: String, name: String? = nil, avatarUrl: String? = nil) {
        self.id = id
        self.name = name
        self.avatarUrl = avatarUrl
    }
}

/// The API's `venue` mixin on an event or series: a display name ("To be announced" when there is none) and the
/// venue, if any.
struct EventVenueMixin: Codable, Sendable, Hashable {
    var name: String?
    var venue: EventVenue?
}

/// An event in the audience: a night, a meetup or a conference.
///
/// The fields modules add are nil when the audience hasn't installed that module (or the query left it out):
/// ``venue`` and ``venueName`` (Venues), ``rsvp`` (RSVP), ``hosts`` and ``lineup`` (People) and ``ticketURL``
/// (Ticketing). The SDK asks for them and, if the audience's schema doesn't have one, asks again without.
public struct Event: Codable, Sendable, Hashable, Identifiable {
    /// The signed-in user's RSVP and how many are going: the API's `rsvp { mine count }`.
    public struct RSVP: Codable, Sendable, Hashable {
        public let mine: RSVPState
        public let count: Int

        public init(mine: RSVPState, count: Int) {
            self.mine = mine
            self.count = count
        }
    }

    public let id: String
    public let name: String?
    public let description: String?
    /// When it starts; nil when not scheduled yet.
    public let startAt: Date?
    public let endAt: Date?
    public let isFeatured: Bool
    public let isCanceled: Bool
    public let bannerUrl: String?
    /// Where it was listed from (its calendar or website), if it was imported.
    public let sourceUrl: String?
    /// Its venue's locale, or its own while the venue is still to be announced.
    public let locale: AudienceLocale?
    /// The audience's tags on it, by name.
    public let tags: [Tag]?
    public let rsvp: RSVP?
    private let venueMixin: EventVenueMixin?
    private let people: PeopleMixin?
    private let tickets: TicketsMixin?

    /// Where it is; nil while the venue is still to be announced, or without the Venues module.
    public var venue: EventVenue? { venueMixin?.venue }
    /// Its venue's name as the API shows it, e.g. "To be announced" when there is none.
    public var venueName: String? { venueMixin?.name }
    /// Who hosts it; nil without the People module.
    public var hosts: [EventPerson]? { people?.hosts?.nodes.compactMap { $0 } }
    /// Who performs or speaks at it; nil without the People module.
    public var lineup: [EventPerson]? { people?.lineup?.nodes.compactMap { $0 } }
    /// Where to buy tickets elsewhere, if anywhere; nil without the Ticketing module.
    public var ticketURL: URL? { tickets?.url.flatMap(URL.init(string:)) }
    /// Every way in on sale, whichever module sells it: tickets on its partner listings and its night's cover.
    /// Nil without the Ticketing module.
    public var ticketOffers: [AdmissionOffer]? { tickets?.offers?.nodes }
    /// The cover at its venue that night: nil when there's none, when it sells tickets instead, or without the
    /// Cover module. Take it with ``AudienceKitClient/buyCover(venueID:)`` when it's payable.
    public var coverCharge: CoverCharge? { tickets?.cover?.charge }

    public init(id: String, name: String? = nil, description: String? = nil, startAt: Date? = nil,
                endAt: Date? = nil, isFeatured: Bool = false, isCanceled: Bool = false, bannerUrl: String? = nil,
                sourceUrl: String? = nil, locale: AudienceLocale? = nil, tags: [Tag]? = nil,
                venue: EventVenue? = nil, venueName: String? = nil, rsvp: RSVP? = nil, hosts: [EventPerson]? = nil,
                lineup: [EventPerson]? = nil, ticketURL: URL? = nil, ticketOffers: [AdmissionOffer]? = nil,
                coverCharge: CoverCharge? = nil)
    {
        self.id = id
        self.name = name
        self.description = description
        self.startAt = startAt
        self.endAt = endAt
        self.isFeatured = isFeatured
        self.isCanceled = isCanceled
        self.bannerUrl = bannerUrl
        self.sourceUrl = sourceUrl
        self.locale = locale
        self.tags = tags
        self.rsvp = rsvp
        venueMixin = venue == nil && venueName == nil ? nil : EventVenueMixin(name: venueName, venue: venue)
        people = hosts == nil && lineup == nil ? nil
            : PeopleMixin(hosts: hosts.map { Nodes(nodes: $0) }, lineup: lineup.map { Nodes(nodes: $0) })
        tickets = ticketURL == nil && ticketOffers == nil && coverCharge == nil ? nil
            : TicketsMixin(url: ticketURL?.absoluteString, offers: ticketOffers.map { OfferNodes(nodes: $0) },
                           cover: coverCharge.map { CoverMixin(charge: $0) })
    }

    private struct Nodes: Codable, Sendable, Hashable { var nodes: [EventPerson?] }
    private struct PeopleMixin: Codable, Sendable, Hashable {
        var hosts: Nodes?
        var lineup: Nodes?
    }

    private struct OfferNodes: Codable, Sendable, Hashable { var nodes: [AdmissionOffer] }
    private struct CoverMixin: Codable, Sendable, Hashable { var charge: CoverCharge? }
    private struct TicketsMixin: Codable, Sendable, Hashable {
        var url: String?
        var offers: OfferNodes?
        var cover: CoverMixin?
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, description, startAt, endAt, isFeatured, isCanceled, bannerUrl, sourceUrl, locale, tags, rsvp
        case people, tickets
        case venueMixin = "venue"
    }

    /// Reads the dates as the ISO 8601 strings the API sends, whatever the decoder's date strategy.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        startAt = try container.decodeISO8601IfPresent(forKey: .startAt)
        endAt = try container.decodeISO8601IfPresent(forKey: .endAt)
        isFeatured = try container.decodeIfPresent(Bool.self, forKey: .isFeatured) ?? false
        isCanceled = try container.decodeIfPresent(Bool.self, forKey: .isCanceled) ?? false
        bannerUrl = try container.decodeIfPresent(String.self, forKey: .bannerUrl)
        sourceUrl = try container.decodeIfPresent(String.self, forKey: .sourceUrl)
        locale = try container.decodeIfPresent(AudienceLocale.self, forKey: .locale)
        tags = try container.decodeIfPresent([Tag].self, forKey: .tags)
        rsvp = try container.decodeIfPresent(RSVP.self, forKey: .rsvp)
        venueMixin = try container.decodeIfPresent(EventVenueMixin.self, forKey: .venueMixin)
        people = try container.decodeIfPresent(PeopleMixin.self, forKey: .people)
        tickets = try container.decodeIfPresent(TicketsMixin.self, forKey: .tickets)
    }

    /// Writes the API's shape, so an encoded event decodes back the same.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(startAt.map(ISO8601.string(from:)), forKey: .startAt)
        try container.encodeIfPresent(endAt.map(ISO8601.string(from:)), forKey: .endAt)
        try container.encode(isFeatured, forKey: .isFeatured)
        try container.encode(isCanceled, forKey: .isCanceled)
        try container.encodeIfPresent(bannerUrl, forKey: .bannerUrl)
        try container.encodeIfPresent(sourceUrl, forKey: .sourceUrl)
        try container.encodeIfPresent(locale, forKey: .locale)
        try container.encodeIfPresent(tags, forKey: .tags)
        try container.encodeIfPresent(rsvp, forKey: .rsvp)
        try container.encodeIfPresent(venueMixin, forKey: .venueMixin)
        try container.encodeIfPresent(people, forKey: .people)
        try container.encodeIfPresent(tickets, forKey: .tickets)
    }
}

/// A way into an event or a venue night (GraphQL's `IAdmissionOffer`): tickets on a ticketing partner, or the cover
/// AudienceKit takes.
public struct AdmissionOffer: Codable, Sendable, Hashable {
    /// Who sells it (GraphQL's `IProvider`): a ticketing partner, or AudienceKit itself.
    public struct Seller: Codable, Sendable, Hashable {
        /// Its key, e.g. `karafun`.
        public let key: String
        /// Its name, e.g. KaraFun.
        public let name: String

        public init(key: String, name: String) {
            self.key = key
            self.name = name
        }
    }

    /// What it costs the buyer, all in (the lowest price for tickets); nil when the seller doesn't say.
    public let price: Money?
    /// Where to buy it on the web; nil when it's bought in the app (the cover) or at the door.
    public let url: String?
    public let seller: Seller

    public init(price: Money? = nil, url: String? = nil, seller: Seller) {
        self.price = price
        self.url = url
        self.seller = seller
    }
}

/// A recurring event: a weekly meetup or a monthly night. Its nights are ``Event``s of their own once generated.
public struct EventSeries: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let description: String?
    /// How it repeats, in words, e.g. "Every Tuesday".
    public let recurrenceText: String?
    /// The first night, as the API's `ISO8601Date` (`yyyy-MM-dd`).
    public let startsOn: String
    /// When each night starts, as the API's `TimeOfDay` (`HH:mm`), in ``timeZone``.
    public let startTime: String
    /// Its IANA time zone, e.g. `America/Denver`.
    public let timeZone: String
    public let durationMinutes: Int?
    public let bannerUrl: String?
    public let locale: AudienceLocale?
    public let tags: [Tag]?
    private let venueMixin: EventVenueMixin?

    /// Where it's held; nil when it moves around, or without the Venues module.
    public var venue: EventVenue? { venueMixin?.venue }
    /// Its venue's name as the API shows it.
    public var venueName: String? { venueMixin?.name }

    public init(id: String, name: String, description: String? = nil, recurrenceText: String? = nil,
                startsOn: String, startTime: String, timeZone: String, durationMinutes: Int? = nil,
                bannerUrl: String? = nil, locale: AudienceLocale? = nil, tags: [Tag]? = nil,
                venue: EventVenue? = nil, venueName: String? = nil)
    {
        self.id = id
        self.name = name
        self.description = description
        self.recurrenceText = recurrenceText
        self.startsOn = startsOn
        self.startTime = startTime
        self.timeZone = timeZone
        self.durationMinutes = durationMinutes
        self.bannerUrl = bannerUrl
        self.locale = locale
        self.tags = tags
        venueMixin = venue == nil && venueName == nil ? nil : EventVenueMixin(name: venueName, venue: venue)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, description, recurrenceText, startsOn, startTime, timeZone, durationMinutes, bannerUrl
        case locale, tags
        case venueMixin = "venue"
    }
}

extension Queries {
    /// The types whose fields the event documents depend on.
    static let eventTypes = listingTypes + ["EventSeries", "EventTickets"]

    /// An ``AdmissionOffer``.
    static let admissionOfferFields = "price { \(moneyFields) } url seller { key name }"

    /// The Ticketing module's part of an event, with the Cover module's charge when the audience has it.
    static func eventTicketsFields(_ shape: SchemaShape) -> String {
        let cover = shape.has("EventTickets", "cover") ? " cover { charge { \(coverChargeFields) } }" : ""
        return "tickets { url offers { nodes { \(admissionOfferFields) } }\(cover) }"
    }

    /// An event: its own fields, then those of the Venues, RSVP, People and Ticketing modules the audience has.
    static func eventFields(_ shape: SchemaShape) -> String {
        var fields = """
        id name description startAt endAt isFeatured isCanceled bannerUrl sourceUrl
        locale { \(localeFields(shape)) } tags { \(tagFields) }
        """
        if shape.has("Event", "venue") { fields += " " + eventVenueFields(shape) }
        if shape.has("Event", "rsvp") { fields += " rsvp { mine count }" }
        if shape.has("Event", "people") {
            fields += " people { hosts { nodes { id name avatarUrl } } lineup { nodes { id name avatarUrl } } }"
        }
        if shape.has("Event", "tickets") { fields += " " + eventTicketsFields(shape) }
        return fields
    }

    /// The Venues module's part of an event or series: a display name and the venue.
    static func eventVenueFields(_ shape: SchemaShape) -> String {
        let place = shape.has("Location", "places") ? " places { placeId }" : ""
        return "venue { name venue { id name photoUrl location { id point address\(place) } } }"
    }

    static func eventSeriesFields(_ shape: SchemaShape) -> String {
        """
        id name description recurrenceText startsOn startTime timeZone durationMinutes bannerUrl
        locale { \(localeFields(shape)) } tags { \(tagFields) }
        """ + (shape.has("EventSeries", "venue") ? " " + eventVenueFields(shape) : "")
    }

    static func events(_ shape: SchemaShape) -> String {
        """
        query Events($window: EventWindow, $localeId: ID, $venueId: ID, $first: Int) {
          events {
            list(window: $window, localeId: $localeId, venueId: $venueId, first: $first) {
              nodes { \(eventFields(shape)) }
            }
          }
        }
        """
    }

    static func event(_ shape: SchemaShape) -> String {
        """
        query Event($id: ID!) {
          events { event(id: $id) { \(eventFields(shape)) } }
        }
        """
    }

    static func eventSeries(_ shape: SchemaShape) -> String {
        """
        query EventSeries($localeId: ID, $venueId: ID, $first: Int) {
          events {
            series(localeId: $localeId, venueId: $venueId, first: $first) { nodes { \(eventSeriesFields(shape)) } }
          }
        }
        """
    }
}

/// `events { list { nodes } }`, `events { series { nodes } }` and `events { event(id:) }`.
struct EventsResponse: Decodable, Sendable {
    struct Mixin: Decodable, Sendable {
        var list: Nodes<Event>?
        var series: Nodes<EventSeries>?
        var event: Event?
    }

    var events: Mixin?
}

extension AudienceSession {
    /// The audience's events, soonest first for ``EventWindow/upcoming`` (latest first for ``EventWindow/past``),
    /// in a locale or at a venue when given: every one of them, or up to `first`. A page costs `first` times an event
    /// in the API's complexity budget (1000), so leave it nil unless you page: `first: 100` alone is over budget.
    public func events(window: EventWindow = .upcoming, localeID: String? = nil, venueID: String? = nil,
                       first: Int? = nil) async throws -> [Event]
    {
        var variables: [String: GraphQLValue] = ["window": .string(window.rawValue)]
        if let first { variables["first"] = .int(first) }
        if let localeID { variables["localeId"] = .string(localeID) }
        if let venueID { variables["venueId"] = .string(venueID) }
        return try await graphQL(types: Queries.eventTypes, variables: variables, operationName: "Events",
                                 as: EventsResponse.self, document: Queries.events).events?.list?.nodes ?? []
    }

    /// One event, or `nil` when it doesn't exist or belongs to another audience.
    public func event(id: String) async throws -> Event? {
        try await graphQL(types: Queries.eventTypes, variables: ["id": .string(id)], operationName: "Event",
                          as: EventsResponse.self, document: Queries.event).events?.event
    }

    /// The audience's recurring events by name, in a locale or at a venue when given: all of them, or up to `first`
    /// (which multiplies its cost in the API's complexity budget, as in ``events(window:localeID:venueID:first:)``).
    public func eventSeries(localeID: String? = nil, venueID: String? = nil, first: Int? = nil) async throws
        -> [EventSeries]
    {
        var variables: [String: GraphQLValue] = [:]
        if let first { variables["first"] = .int(first) }
        if let localeID { variables["localeId"] = .string(localeID) }
        if let venueID { variables["venueId"] = .string(venueID) }
        return try await graphQL(types: Queries.eventTypes, variables: variables, operationName: "EventSeries",
                                 as: EventsResponse.self, document: Queries.eventSeries).events?.series?.nodes ?? []
    }
}
