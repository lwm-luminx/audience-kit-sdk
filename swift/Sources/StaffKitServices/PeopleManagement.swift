import Foundation
import AudienceCore

public struct TalentEvent: Decodable, Sendable, Identifiable {
    public struct Person: Decodable, Sendable, Identifiable { public let id: String; public let name: String? }
    public struct Series: Decodable, Sendable { public let id: String; public let name: String }
    public let karaoke: StaffKaraokeNight?
    public let tags: [StaffEventTag]?
    public let id: String
    public let name: String?
    public let description: String?
    public let startAt: String?
    public let endAt: String?
    public let isCanceled: Bool
    private let venue: EventPlace?
    /// Its tickets mixin: `tickets { url }`.
    private let tickets: TicketsLink?
    public let bannerUrl: String?
    /// Its people mixin: `people { lineup { nodes } }`.
    private let lineup: Lineup?
    public let eventSeries: Series?
    public let seriesOverride: Bool
    /// Its venue's name, or "To be announced".
    public var venueName: String { venue?.name ?? "" }
    /// Its venue, for its lineup; nil when it's to be announced.
    public var venueID: String? { venue?.id }
    /// The zone its venue counts nights in.
    public var venueZone: TimeZone? { venue?.coverTimeZone.flatMap(TimeZone.init(identifier:)) }
    /// Who is hosting or playing it.
    public var people: [Person] { lineup?.lineup.nodes ?? [] }
    /// Who is hosting it: their managers may build and change its lineup.
    public var hostIDs: [String] { lineup?.hosts?.nodes.map(\.id) ?? [] }
    /// Its lineup's place, for StaffKitUI's lineup editor; nil when it has no venue yet.
    public var lineupPlace: LineupPlace? {
        guard let venueID else { return nil }
        return LineupPlace(venueID: venueID, zone: venueZone ?? .current,
                           event: VenueAppearance.Event(id: id, name: name, startAt: startAt))
    }
    /// Where to buy tickets.
    public var ticketUrl: String? { tickets?.url }

    private struct Lineup: Decodable, Sendable { let lineup: GraphQLNodes<Person>; let hosts: GraphQLNodes<Person>? }
    private enum CodingKeys: String, CodingKey {
        case karaoke, tags, id, name, description, startAt, endAt, isCanceled, venue, tickets, bannerUrl, eventSeries, seriesOverride
        case lineup = "people"
    }
}

public struct TalentSeries: Decodable, Sendable, Identifiable {
    public let karaoke: Bool?
    public let karaokeSessionCode: String?
    public let tags: [StaffEventTag]?
    public let id: String
    public let name: String
    public let description: String?
    public let rrule: String
    public let recurrenceText: String?
    public let startsOn: String
    public let startTime: String
    public let timeZone: String
    public let durationMinutes: Int?
    /// Its tickets mixin: `tickets { url }`.
    private let tickets: TicketsLink?
    public let skippedDates: [String]
    public let upcomingStarts: [String]
    public let events: [TalentEvent]
    /// Where to buy tickets, copied to each occurrence.
    public var ticketUrl: String? { tickets?.url }
}


/// A managed public listing for a non-location entity (for example, a persona or group).
/// User represents one human. Administration is many-to-many: each human can manage many
/// listings, and each listing can have many human administrators. Managing a member's listing also lets the user act
/// as the group (see `TalentListings.troupeIDs`).
public struct ManagedPerson: Decodable, Sendable, Identifiable {
    public struct Link: Decodable, Sendable, Identifiable {
        public let id: String
        public let provider: String
        public let handle: String
        public let url: String?
    }
    public let id: String
    public let name: String?
    public let avatarUrl: String?
    /// Their tipping mixin: `tipping { options }`. Nil where the tipping module is off.
    private let tipping: Tipping?
    /// Their listing profile mixin: `profile { socialLinks }`.
    private let profile: Profile?
    /// Their music mixin: `music { links }`.
    private let music: Music?
    /// Their events mixin, aliased: `talentEvents: events { involvements }`.
    private let talentEvents: TalentEvents?

    /// Their social media profiles.
    public var socialLinks: [Link] { profile?.socialLinks.nodes ?? [] }
    /// Their public website.
    public var website: String? { profile?.website }
    /// Their SoundCloud, Spotify and Apple Music profiles.
    public var musicLinks: [Link] { music?.links.nodes ?? [] }
    /// Where fans tip them by link (Cash App, Venmo), from their tipping options; providers are lowercase, like
    /// "cashapp".
    public var tipLinks: [Link] {
        (tipping?.options ?? []).compactMap { option in
            guard let handle = option.handle else { return nil }
            let provider = option.provider.lowercased()
            return Link(id: "tip-\(provider)", provider: provider, handle: handle, url: option.url)
        }
    }
    /// The `socialLinks` to send to keep their links as they are except on the networks in `edits` (provider =>
    /// handle or link; blank removes it): `person.socialLinks(replacing: ["instagram": "@dugan", "venmo": ""])`.
    public func socialLinks(replacing edits: [String: String]) -> [SocialLinkInput] {
        SocialLinkInput.replacing(socialLinks.map { (provider: $0.provider, handle: $0.handle) },
                                  with: edits.mapValues { [$0] })
    }
    /// Their upcoming events and those of the troupes they're in, soonest first, with how they're on each.
    public var involvements: [TalentEventInvolvement] { talentEvents?.involvements.edges ?? [] }
    /// Their upcoming events and those of the troupes they're in, soonest first.
    public var events: [TalentEvent] { involvements.map(\.event) }

    /// The API's `events { involvements }` connection, of which the client reads the edges.
    private struct Involvements: Decodable, Sendable { let edges: [TalentEventInvolvement] }
    private struct TalentEvents: Decodable, Sendable { let involvements: Involvements }
    private struct Music: Decodable, Sendable { let links: GraphQLNodes<Link> }
    private struct Profile: Decodable, Sendable { let website: String?; let socialLinks: GraphQLNodes<Link> }
    /// One of the API's `TipOption`s: a link (with a handle) or in the app (without).
    private struct TipOption: Decodable, Sendable { let provider: String; let handle: String?; let url: String? }
    private struct Tipping: Decodable, Sendable { let options: [TipOption] }
}

/// How a person is on one of their events: themselves, or through a troupe they're in (`via`).
public struct TalentEventInvolvement: Decodable, Sendable, Identifiable {
    public let event: TalentEvent
    /// Their role on it, like host or performer: the troupe's when it's through one.
    public let role: String?
    /// The troupe it comes through, for showing "with <troupe>"; nil when it's their own.
    public let via: TalentEvent.Person?
    public var id: String { event.id }

    private enum CodingKeys: String, CodingKey { case event = "node", role, via }
}

/// The people a user can manage. Troupes are reached through a member listing the user manages rather than the
/// troupe's own Page: the user acts as the troupe, but its tip links stay with the troupe's own managers.
public struct TalentListings: Sendable {
    public let people: [ManagedPerson]
    public let troupeIDs: Set<String>
    public init(people: [ManagedPerson], troupeIDs: Set<String>) {
        self.people = people
        self.troupeIDs = troupeIDs
    }
}

extension TalentManagementClient {
    static let personFields = """
        id name avatarUrl profile { website socialLinks { nodes { id provider handle url } } }
        music { links { nodes { id provider handle url } } } tipping { options { provider handle url } }
        talentEvents: events { involvements { edges { role via { id name } node { \(eventFields) } } } }
        """
    /// Uses the backend's listing IDs, never display names, to select editable people.
    public func people(isAdministrator: Bool) async throws -> [ManagedPerson] {
        try await listings(isAdministrator: isAdministrator).people
    }
    /// The editable people plus which of them are troupes the user acts as through a member listing they manage.
    public func listings(isAdministrator: Bool) async throws -> TalentListings {
        // The audience is the endpoint's query root; the listings the viewer manages are theirs, under `me`.
        struct Audience: Decodable, Sendable {
            struct People: Decodable, Sendable { let list: GraphQLNodes<ManagedPerson> }
            struct Me: Decodable, Sendable { let listings: Listings }
            struct Listings: Decodable, Sendable {
                let people: [GraphQLRef]
                let troupes: [GraphQLRef]
            }
            let me: Me?
            let people: People
        }
        let audience = try await session.graphQL("query BackstagePeople { me { listings { people { id } troupes { id } } } people { list { nodes { \(Self.personFields) } } } }",
                                                 as: Audience.self)
        let allowed = Set(audience.me?.listings.people.map(\.id) ?? [])
        return TalentListings(people: audience.people.list.nodes.filter { isAdministrator || allowed.contains($0.id) },
                              troupeIDs: isAdministrator ? [] : Set(audience.me?.listings.troupes.map(\.id) ?? []))
    }
    /// Changes their name, social links and, when given, website; `socialLinks` replaces every link they have, so
    /// build it with `ManagedPerson.socialLinks(replacing:)` to leave the others alone.
    public func updateProfile(id: String, name: String, website: String? = nil, socialLinks: [SocialLinkInput]) async throws -> ManagedPerson {
        struct Response: Decodable, Sendable {
            struct Payload: Decodable, Sendable { let person: ManagedPerson }
            let updatePerson: Payload
        }
        var person: [String: GraphQLValue] = ["name": .string(name), "socialLinks": .array(socialLinks.map(\.graphQLValue))]
        if let website { person["website"] = .string(website) }
        return try await session.graphQL("""
            mutation BackstageProfile($input: PersonUpdateInput!) {
              updatePerson(input: $input) { person { \(Self.personFields) } }
            }
            """, variables: ["input": .object(["id": .string(id), "person": .object(person)])], as: Response.self).updatePerson.person
    }
    static let eventFields = """
        id name description startAt endAt isCanceled tags { id name color }
        karaoke { providerName sessionCode ownSessionCode joinUrl } venue { name venue { id tickets { cover { timeZone } } } } tickets { url } bannerUrl
        people { lineup { nodes { id name } } hosts { nodes { id name } } } eventSeries { id name } seriesOverride
        """
    static let seriesFields = """
        id name description karaoke karaokeSessionCode tags { id name color } rrule recurrenceText startsOn startTime timeZone durationMinutes tickets { url }
        skippedDates upcomingStarts events { \(eventFields) }
        """
    public func event(id: String) async throws -> TalentEvent? {
        struct Response: Decodable, Sendable {
            struct Events: Decodable, Sendable { let event: TalentEvent? }
            let events: Events
        }
        return try await session.graphQL("query TalentEvent($id: ID!) { events { event(id: $id) { \(Self.eventFields) } } }",
                                       variables: ["id": .string(id)], as: Response.self).events.event
    }
    public func series(personID: String) async throws -> [TalentSeries] {
        struct Response: Decodable, Sendable {
            struct Events: Decodable, Sendable { let series: GraphQLNodes<TalentSeries> }
            let events: Events?
        }
        return try await session.graphQL("""
            query TalentSeries($id: ID!) { events { series(personId: $id) { nodes { \(Self.seriesFields) } } } }
            """, variables: ["id": .string(personID)], as: Response.self).events?.series.nodes ?? []
    }
    public func saveSeries(id: String?, personID: String, fields: [String: GraphQLValue]) async throws {
        var input: [String: GraphQLValue] = ["eventSeries": .object(fields)]
        if let id { input["id"] = .string(id) }
        else {
            var creating = fields
            creating["ownerPersonId"] = .string(personID)
            input["eventSeries"] = .object(creating)
        }
        let action = id == nil ? "createEventSeries" : "updateEventSeries"
        let type = id == nil ? "EventSeriesCreateInput" : "EventSeriesUpdateInput"
        try await operation(action, inputType: type, input: input, selection: "eventSeries { id }")
    }
    /// Adds a one-off event of this listing's own, which they host. It's at their home venue unless `fields` names a
    /// `venueId` (one of theirs, or "" for to be announced, in `localeId` when given).
    @discardableResult
    public func createEvent(personID: String, fields: [String: GraphQLValue]) async throws -> String {
        var event = fields
        event["ownerPersonId"] = .string(personID)
        struct Response: Decodable, Sendable {
            struct Payload: Decodable, Sendable { struct Event: Decodable, Sendable { let id: String }; let event: Event }
            let createEvent: Payload
        }
        return try await session.graphQL("mutation TalentEventCreate($input: EventCreateInput!) { createEvent(input: $input) { event { id } } }",
            variables: ["input": .object(["event": .object(event)])], as: Response.self).createEvent.event.id
    }

    /// Changes one of their events, or one date of their series (which then no longer follows it, unless `fields`
    /// is `seriesOverride: false`, which puts the date back in step).
    @discardableResult
    public func updateEvent(id: String, fields: [String: GraphQLValue]) async throws -> TalentEvent {
        struct Response: Decodable, Sendable {
            struct Payload: Decodable, Sendable { let event: TalentEvent }
            let updateEvent: Payload
        }
        return try await session.graphQL("mutation TalentEventUpdate($input: EventUpdateInput!) { updateEvent(input: $input) { event { \(Self.eventFields) } } }",
            variables: ["input": .object(["id": .string(id), "event": .object(fields)])], as: Response.self).updateEvent.event
    }

    private func operation(_ name: String, inputType: String, input: [String: GraphQLValue], selection: String) async throws {
        _ = try await session.graphQL("mutation BackstageOperation($input: \(inputType)!) { \(name)(input: $input) { \(selection) } }",
                                   variables: ["input": .object(input)], as: GraphQLValue.self)
    }
}

public struct TalentLocation: Decodable, Sendable, Identifiable {
    public let id: String
    public let name: String?
}
public struct TalentLocations: Sendable {
    public let venues: [TalentLocation]
    public let locales: [TalentLocation]
}
extension TalentManagementClient {
    public func locations(isAdministrator: Bool) async throws -> TalentLocations {
        // The audience is the endpoint's query root; the venues the viewer manages are theirs, under `me`.
        struct Audience: Decodable, Sendable {
            struct Venues: Decodable, Sendable { let list: GraphQLNodes<TalentLocation> }
            struct Me: Decodable, Sendable { let listings: Listings }
            struct Listings: Decodable, Sendable { let venues: [GraphQLRef] }
            let me: Me?
            let venues: Venues?
            let locales: [TalentLocation]
        }
        let audience = try await session.graphQL("""
            query TalentLocations { me { listings { venues { id } } } venues { list { nodes { id name } } } locales { id name } }
            """, as: Audience.self)
        let allowed = Set(audience.me?.listings.venues.map(\.id) ?? [])
        return TalentLocations(venues: (audience.venues?.list.nodes ?? []).filter { isAdministrator || allowed.contains($0.id) }, locales: audience.locales)
    }
}
