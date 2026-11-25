import Foundation
import AudienceCore

/// An entry in a lineup: someone (or several people: a duet, a group) hosting, DJing, performing or MCing, or an
/// intermission. A lineup is a venue night's own, built as the night goes, or an event's, built ahead (``event``).
/// Each runs in ``position`` order, and the venue advances it like a slide deck
/// (``VenueManagementClient/advanceLineup(venueID:eventID:back:)``).
public struct VenueAppearance: Decodable, Sendable, Identifiable, Hashable {
    /// What they're doing. Unknown roles from a newer API decode as themselves.
    public struct Role: RawRepresentable, Codable, Sendable, Hashable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let host = Role(rawValue: "HOST")
        public static let dj = Role(rawValue: "DJ")
        public static let performer = Role(rawValue: "PERFORMER")
        public static let mc = Role(rawValue: "MC")
        /// A karaoke singer: their signup put them on, so editors don't offer it.
        public static let singer = Role(rawValue: "SINGER")
        /// The roles editors offer, in order.
        public static let all: [Role] = [.host, .dj, .performer, .mc]
    }
    /// An act or an intermission.
    public enum Kind: String, Codable, Sendable, Hashable { case act = "ACT", intermission = "INTERMISSION" }
    /// How it starts: at a hard time by the clock, around a soft time when advanced to, or with no set time.
    public enum StartTiming: String, Codable, Sendable, Hashable, CaseIterable { case hard = "HARD", soft = "SOFT", none = "NONE" }
    /// How it ends: at a set time, at close, or when the venue advances past it.
    public enum EndTiming: String, Codable, Sendable, Hashable, CaseIterable { case time = "TIME", close = "CLOSE", advance = "ADVANCE" }
    /// Where it is in its night.
    public enum Status: String, Codable, Sendable, Hashable { case upcoming = "UPCOMING", on = "ON", done = "DONE" }
    /// A singer's karaoke signup: the song, who's singing it, and where it is in the queue.
    public struct SongRequest: Codable, Sendable, Hashable, Identifiable {
        /// Where a signup is: waiting, up, sung, skipped or taken back. Unknown states decode as themselves.
        public struct State: RawRepresentable, Codable, Sendable, Hashable {
            public let rawValue: String
            public init(rawValue: String) { self.rawValue = rawValue }
            public static let queued = State(rawValue: "QUEUED")
            public static let up = State(rawValue: "UP")
            public static let done = State(rawValue: "DONE")
            public static let skipped = State(rawValue: "SKIPPED")
            public static let withdrawn = State(rawValue: "WITHDRAWN")
        }
        public let id: String
        public let title: String
        public let artist: String?
        /// Who's singing: the name(s) they gave, else the requester.
        public let singer: String?
        /// A dedication or a word for the host.
        public let note: String?
        public let state: State
        /// Who signed up, as the room shows them.
        public let requesterName: String?

        public init(id: String, title: String, artist: String? = nil, singer: String? = nil, note: String? = nil,
                    state: State = .queued, requesterName: String? = nil) {
            self.id = id; self.title = title; self.artist = artist; self.singer = singer; self.note = note
            self.state = state; self.requesterName = requesterName
        }

        /// "Dancing Queen · ABBA".
        public var song: String { [title, artist ?? ""].filter { !$0.isEmpty }.joined(separator: " · ") }
    }
    /// The event whose lineup it's on.
    public struct Event: Codable, Sendable, Hashable, Identifiable {
        public let id: String
        public let name: String?
        public let startAt: String?
        public init(id: String, name: String?, startAt: String? = nil) { self.id = id; self.name = name; self.startAt = startAt }
    }

    public let id: String
    public let kind: Kind
    /// Nil for an intermission.
    public let role: Role?
    /// Its set (hard or soft) time, or when an entry with no set time went on; nil until then.
    public let startsAt: String?
    /// Its set end; nil until close or until advanced past.
    public let endsAt: String?
    /// Who, or the first of them; nil for an intermission.
    public let person: VenueEvent.Person?
    /// Everyone on it, in billing order.
    public let people: [VenueEvent.Person]
    /// An act's billing (a duet's name) or an intermission's label.
    public let title: String?
    /// Its place in its lineup's running order.
    public let position: Int
    /// The event whose lineup it's on, built ahead; nil on the venue night's own.
    public let event: Event?
    public let startTiming: StartTiming
    public let endTiming: EndTiming
    /// From an API before running orders: what its times say.
    public let status: Status?
    /// When advancing put it on, and took it off.
    public let wentOnAt: String?
    public let cameOffAt: String?
    /// A singer's signup; nil for everything else.
    public let songRequest: SongRequest?

    public init(id: String, kind: Kind = .act, role: Role?, startsAt: String?, endsAt: String?, person: VenueEvent.Person?,
                people: [VenueEvent.Person]? = nil, title: String? = nil, position: Int = 0, startTiming: StartTiming = .hard,
                endTiming: EndTiming? = nil, status: Status? = nil, wentOnAt: String? = nil, cameOffAt: String? = nil,
                event: Event? = nil, songRequest: SongRequest? = nil) {
        self.id = id; self.kind = kind; self.role = role; self.startsAt = startsAt; self.endsAt = endsAt; self.person = person
        self.people = people ?? person.map { [$0] } ?? []
        self.title = title; self.position = position; self.startTiming = startTiming
        self.endTiming = endTiming ?? (endsAt == nil ? .close : .time)
        self.status = status; self.wentOnAt = wentOnAt; self.cameOffAt = cameOffAt; self.event = event
        self.songRequest = songRequest
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, role, startsAt, endsAt, person, people, title, position, startTiming, endTiming, wentOnAt, cameOffAt, event, songRequest
        case status = "state"
    }

    /// Fields a newer API added decode with defaults, so an older one's lineup still reads.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let person = try c.decodeIfPresent(VenueEvent.Person.self, forKey: .person)
        let endsAt = try c.decodeIfPresent(String.self, forKey: .endsAt)
        self.init(id: try c.decode(String.self, forKey: .id),
                  kind: (try? c.decodeIfPresent(Kind.self, forKey: .kind)) ?? .act,
                  role: try c.decodeIfPresent(Role.self, forKey: .role),
                  startsAt: try c.decodeIfPresent(String.self, forKey: .startsAt), endsAt: endsAt, person: person,
                  people: try c.decodeIfPresent(GraphQLNodes<VenueEvent.Person>.self, forKey: .people)?.nodes,
                  title: try c.decodeIfPresent(String.self, forKey: .title),
                  position: try c.decodeIfPresent(Int.self, forKey: .position) ?? 0,
                  startTiming: (try? c.decodeIfPresent(StartTiming.self, forKey: .startTiming)) ?? .hard,
                  endTiming: try? c.decodeIfPresent(EndTiming.self, forKey: .endTiming),
                  status: try? c.decodeIfPresent(Status.self, forKey: .status),
                  wentOnAt: try c.decodeIfPresent(String.self, forKey: .wentOnAt),
                  cameOffAt: try c.decodeIfPresent(String.self, forKey: .cameOffAt),
                  event: try? c.decodeIfPresent(Event.self, forKey: .event),
                  songRequest: try? c.decodeIfPresent(SongRequest.self, forKey: .songRequest))
    }

    public var isIntermission: Bool { kind == .intermission }
    /// A karaoke singer, on the lineup by signing up and called up by advancing.
    public var isSinger: Bool { role == .singer }
    /// A host or MC: starting the show puts them on, and they cover the stage between acts.
    public var isHost: Bool { kind == .act && (role == .host || role == .mc) }
    /// "Ada & Bo", the act's billing, or "Intermission".
    public var displayName: String {
        if let title, !title.isEmpty { return title }
        if isIntermission { return "Intermission" }
        let names = people.compactMap(\.name)
        return names.isEmpty ? (person?.name ?? "Someone") : names.formatted(.list(type: .and))
    }
    /// Whether advancing steps through it: everything but what runs by the clock (a hard start and a set end or close).
    public var isAdvanceable: Bool { !(startTiming == .hard && endTiming != .advance) }
}

extension VenueAppearance.Kind: Identifiable { public var id: String { rawValue } }

/// Tonight's running order after advancing it.
public struct LineupAdvance: Decodable, Sendable {
    /// What's on stage now: what the next advance takes off.
    public let onStage: VenueAppearance?
    /// What the next advance puts on.
    public let upNext: VenueAppearance?
    public let runningOrder: [VenueAppearance]
}

/// Whether a venue's chat takes karaoke signups right now (AudienceKit karaoke): open while a host is on, unless the
/// venue paused them for the night.
public struct KaraokeSignups: Decodable, Sendable, Hashable {
    /// Whether the venue runs karaoke with AudienceKit at all.
    public let permitted: Bool
    public let open: Bool
    /// Whether the venue paused signups for tonight.
    public let paused: Bool
    /// Why they're closed, as guests see it ("Signups are paused"); nil while open.
    public let closedReason: String?
    /// The host on now, who takes them.
    public let host: VenueAppearance?
    /// Whether tonight's cutoff closed them (near the end of the event or night), unless reopened. False from an API
    /// before cutoffs.
    public let cutOff: Bool
    /// Whether the venue reopened them for tonight past the cutoff.
    public let reopened: Bool
    /// When they close by themselves tonight, ISO 8601; nil without a cutoff (or from an older API).
    public let closesAt: String?

    public init(permitted: Bool, open: Bool, paused: Bool, closedReason: String? = nil, host: VenueAppearance? = nil,
                cutOff: Bool = false, reopened: Bool = false, closesAt: String? = nil) {
        self.permitted = permitted; self.open = open; self.paused = paused; self.closedReason = closedReason; self.host = host
        self.cutOff = cutOff; self.reopened = reopened; self.closesAt = closesAt
    }

    private enum CodingKeys: String, CodingKey { case permitted, open, paused, closedReason, host, cutOff, reopened, closesAt }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(permitted: try c.decode(Bool.self, forKey: .permitted), open: try c.decode(Bool.self, forKey: .open),
                  paused: try c.decode(Bool.self, forKey: .paused), closedReason: try c.decodeIfPresent(String.self, forKey: .closedReason),
                  host: try c.decodeIfPresent(VenueAppearance.self, forKey: .host),
                  cutOff: try c.decodeIfPresent(Bool.self, forKey: .cutOff) ?? false,
                  reopened: try c.decodeIfPresent(Bool.self, forKey: .reopened) ?? false,
                  closesAt: try c.decodeIfPresent(String.self, forKey: .closesAt))
    }

    /// Whether they're closed for the night: closed early (paused) or past the cutoff.
    public var closed: Bool { paused || cutOff }
}

/// A count rounded down into a bucket ("A few", "10+"), never exact.
public struct ApproximateCount: Decodable, Sendable, Hashable {
    /// The bucket's floor: 0, 1, 5, 10, 25, 50 or 100.
    public let atLeast: Int
    public let label: String
}

/// How busy a venue is right now, approximately. Managers only.
public struct VenueActivity: Decodable, Sendable, Hashable {
    /// Active pings heading there or to its events.
    public let pinging: ApproximateCount
    /// People the app placed there in the last hour.
    public let hereLastHour: ApproximateCount
}

/// One night's change to a venue's cover. Nil fields keep the usual.
public struct VenueCoverNight: Decodable, Sendable, Hashable {
    /// "yyyy-MM-dd"; a night runs 6 AM to 6 AM.
    public let night: String
    /// 0 for no cover, nil for the usual price. On a sliding scale, the suggested amount.
    public let coverCents: Int?
    /// That night's sliding scale's least and most, in cents; nil for a fixed price. Nil from servers that predate it.
    public let coverMinCents: Int?
    public let coverMaxCents: Int?
    /// HH:MM, or nil for the usual.
    public let from: String?
    public let until: String?
}

/// A venue's night: who's on, what the cover is, and how it differs from the usual.
public struct VenueNight: Decodable, Sendable {
    /// Its tickets mixin, read for the cover inside it.
    private struct Tickets: Decodable, Sendable { let cover: Cover? }
    /// The part of a venue's `tickets { cover }` mixin a night reads.
    public struct Cover: Decodable, Sendable {
        public let charge: VenueCoverSettings.Charge?
        public let nights: [VenueCoverNight]
    }
    /// The part of a venue's `people` mixin a night reads.
    private struct People: Decodable, Sendable {
        let lineup: GraphQLNodes<VenueAppearance>
        let onNow: GraphQLNodes<VenueAppearance>
        let runningOrder: GraphQLNodes<VenueAppearance>?
        let onStage: VenueAppearance?
        let upNext: VenueAppearance?
    }
    private let tickets: Tickets?
    /// Its cover that night, from the venue's cover mixin: `tickets { cover }`.
    public var cover: Cover? { tickets?.cover }
    /// Who's on, from the venue's people mixin.
    private let people: People?

    /// Who's on that night, by start.
    public var lineup: [VenueAppearance] { people?.lineup.nodes ?? [] }
    /// Who's on right now, whichever night was asked for.
    public var onNow: [VenueAppearance] { people?.onNow.nodes ?? [] }
    /// Everything on that night's lineup in order: intermissions and entries with no set time too. An API before
    /// running orders gives its lineup.
    public var runningOrder: [VenueAppearance] { people?.runningOrder?.nodes ?? lineup }
    /// What tonight's running order has on stage, whichever night was asked for: what advancing takes off.
    public var onStage: VenueAppearance? { people?.onStage }
    /// What advancing tonight's running order puts on next.
    public var upNext: VenueAppearance? { people?.upNext }

    /// What getting in costs that night; nil when there's no cover (or an event sells tickets instead).
    public var coverCharge: VenueCoverSettings.Charge? { cover?.charge }
    /// Changes to the cover from tonight on; ``coverNight`` picks this night's.
    public var coverNights: [VenueCoverNight] { cover?.nights ?? [] }

    /// This night's change to the cover, if it has one.
    public var coverNight: VenueCoverNight? {
        guard let night = coverCharge?.night else { return nil }
        return coverNights.first { $0.night == night }
    }
    /// The change for `night` ("yyyy-MM-dd"), if it has one.
    public func coverNight(on night: String) -> VenueCoverNight? { coverNights.first { $0.night == night } }
}

extension VenueManagementClient {
    static let appearanceFields = "id kind role title position startTiming endTiming state startsAt endsAt wentOnAt cameOffAt person { id name avatarUrl } people { nodes { id name avatarUrl } } event { id name startAt } songRequest { id title artist singer note state requesterName }"
    static let karaokeSignupFields = "permitted open paused closedReason host { \(appearanceFields) }"
    /// With the cutoff (an API from 2026-10-26 on); the older query is the fallback.
    static let karaokeCutoffFields = "\(karaokeSignupFields) cutOff reopened closesAt"
    static let chargeFields = "amount { \(moneyFields) } total { \(moneyFields) } payable night from until override " +
        "scale { min { \(moneyFields) } max { \(moneyFields) } }"

    /// Who's on, the cover and its changes for a night (tonight when nil, as "yyyy-MM-dd" otherwise).
    public func night(venueID: String, night: String? = nil) async throws -> VenueNight {
        struct Venues: Decodable, Sendable { let venue: VenueNight? }
        struct Response: Decodable, Sendable { let venues: Venues }
        let response = try await session.graphQL("""
            query VelvetNight($id: ID!, $night: ISO8601Date) {
              venues {
                venue(id: $id) {
                  tickets { cover { charge(night: $night) { \(Self.chargeFields) } nights { night coverCents coverMinCents coverMaxCents from until } } }
                  people {
                    lineup(night: $night) { nodes { \(Self.appearanceFields) } }
                    onNow { nodes { \(Self.appearanceFields) } }
                    runningOrder(night: $night) { nodes { \(Self.appearanceFields) } }
                    onStage { \(Self.appearanceFields) }
                    upNext { \(Self.appearanceFields) }
                  }
                }
              }
            }
            """, variables: ["id": .string(venueID), "night": night.map(GraphQLValue.string) ?? .null], as: Response.self)
        guard let venue = response.venues.venue else { throw AudienceKitError.notFound }
        return venue
    }

    /// Puts someone on: `startsAt` and `endsAt` are ISO 8601 instants, `endsAt` nil for until close. Starting someone
    /// now posts "On now" to the venue's chat.
    public func addAppearance(venueID: String, personID: String, role: VenueAppearance.Role, startsAt: String,
                              endsAt: String?) async throws -> VenueAppearance {
        struct Payload: Decodable, Sendable { let appearance: VenueAppearance? }
        struct Response: Decodable, Sendable { let createAppearance: Payload }
        let appearance: [String: GraphQLValue] = [
            "personId": .string(personID), "role": .string(role.rawValue), "startsAt": .string(startsAt),
            "endsAt": endsAt.map(GraphQLValue.string) ?? .null
        ]
        let response = try await session.graphQL("""
            mutation VelvetAppearanceAdd($input: AppearanceCreateInput!) {
              createAppearance(input: $input) { appearance { \(Self.appearanceFields) } }
            }
            """, variables: ["input": .object(["venueId": .string(venueID), "appearance": .object(appearance)])],
            as: Response.self)
        guard let saved = response.createAppearance.appearance else { throw AudienceKitError.decoding("The appearance was missing") }
        return saved
    }

    /// Adds an entry to a lineup: `personIds` (several for a duet) and `role` for an act, or `kind` INTERMISSION;
    /// `startTiming` HARD, SOFT or NONE with `startsAt`, or `night` ("yyyy-MM-dd") for no set time; `endTiming` TIME
    /// with `endsAt`, CLOSE or ADVANCE; `title` for an act's billing or an intermission's label; `eventId` for an
    /// event's lineup built ahead (its night is then the event's), else it's on the venue night's own.
    public func addLineupEntry(venueID: String, fields: [String: GraphQLValue]) async throws -> VenueAppearance {
        struct Payload: Decodable, Sendable { let appearance: VenueAppearance? }
        struct Response: Decodable, Sendable { let createAppearance: Payload }
        let response = try await session.graphQL("""
            mutation VelvetLineupEntryAdd($input: AppearanceCreateInput!) {
              createAppearance(input: $input) { appearance { \(Self.appearanceFields) } }
            }
            """, variables: ["input": .object(["venueId": .string(venueID), "appearance": .object(fields)])],
            as: Response.self)
        guard let saved = response.createAppearance.appearance else { throw AudienceKitError.decoding("The appearance was missing") }
        return saved
    }

    /// Advances a lineup like a slide deck: takes off what's on stage and puts on what's up next, telling chat who's
    /// on. `back` undoes the last advance. Without `eventID` it advances the lineup on tonight (the venue's own, or the
    /// event's that has started); with it, that event's.
    public func advanceLineup(venueID: String, eventID: String? = nil, back: Bool = false) async throws -> LineupAdvance {
        // Optional: a refusal (a curtain call holding, see isNotEveryoneReady) comes as a null payload with its error,
        // and the error is what's thrown.
        struct Response: Decodable, Sendable { let advanceLineup: LineupAdvance? }
        let response = try await session.graphQL("""
            mutation VelvetLineupAdvance($input: LineupAdvanceInput!) {
              advanceLineup(input: $input) {
                onStage { \(Self.appearanceFields) } upNext { \(Self.appearanceFields) } runningOrder { \(Self.appearanceFields) }
              }
            }
            """, variables: ["input": .object(["venueId": .string(venueID), "eventId": eventID.map(GraphQLValue.string) ?? .null,
                                               "back": .bool(back)])], as: Response.self)
        guard let advance = response.advanceLineup else { throw AudienceKitError.decoding("The advance was missing") }
        return advance
    }

    /// An event's lineup built ahead, in running order.
    public func eventLineup(eventID: String) async throws -> [VenueAppearance] {
        struct People: Decodable, Sendable { let runningOrder: GraphQLNodes<VenueAppearance> }
        struct Event: Decodable, Sendable { let people: People }
        struct Events: Decodable, Sendable { let event: Event? }
        struct Response: Decodable, Sendable { let events: Events }
        let response = try await session.graphQL("""
            query VelvetEventLineup($id: ID!) {
              events { event(id: $id) { people { runningOrder { nodes { \(Self.appearanceFields) } } } } }
            }
            """, variables: ["id": .string(eventID)], as: Response.self)
        guard let event = response.events.event else { throw AudienceKitError.notFound }
        return event.people.runningOrder.nodes
    }

    /// Puts a night's ("yyyy-MM-dd", tonight when nil) lineups in the order of `ids`; any left out follow. Each entry
    /// stays on its own lineup (the venue's or an event's), so an event's lineup can be reordered on its own. With
    /// `eventID`, only that event's lineup changes, and `ids` are its entries: what an event's hosts may reorder.
    public func reorderLineup(venueID: String, night: String?, eventID: String? = nil, ids: [String]) async throws -> [VenueAppearance] {
        struct Payload: Decodable, Sendable { let runningOrder: [VenueAppearance] }
        struct Response: Decodable, Sendable { let reorderLineup: Payload }
        var input: [String: GraphQLValue] = [
            "venueId": .string(venueID), "night": night.map(GraphQLValue.string) ?? .null, "ids": .array(ids.map(GraphQLValue.string))
        ]
        if let eventID { input["eventId"] = .string(eventID) }
        let response = try await session.graphQL("""
            mutation VelvetLineupReorder($input: LineupReorderInput!) {
              reorderLineup(input: $input) { runningOrder { \(Self.appearanceFields) } }
            }
            """, variables: ["input": .object(input)], as: Response.self)
        return response.reorderLineup.runningOrder
    }

    /// Changes an appearance. Send only what changed: `personId` or `personIds`, `role`, `title`, `startTiming`,
    /// `startsAt`, `endTiming`, `endsAt` (null for until close).
    public func updateAppearance(id: String, fields: [String: GraphQLValue]) async throws -> VenueAppearance {
        struct Payload: Decodable, Sendable { let appearance: VenueAppearance? }
        struct Response: Decodable, Sendable { let updateAppearance: Payload }
        let response = try await session.graphQL("""
            mutation VelvetAppearanceUpdate($input: AppearanceUpdateInput!) {
              updateAppearance(input: $input) { appearance { \(Self.appearanceFields) } }
            }
            """, variables: ["input": .object(["id": .string(id), "appearance": .object(fields)])], as: Response.self)
        guard let saved = response.updateAppearance.appearance else { throw AudienceKitError.decoding("The appearance was missing") }
        return saved
    }

    /// Takes someone off the lineup.
    public func deleteAppearance(id: String) async throws {
        _ = try await session.graphQL("mutation VelvetAppearanceDelete($input: AppearanceDeleteInput!) { deleteAppearance(input: $input) { appearance { id } } }",
                                    variables: ["input": .object(["id": .string(id)])], as: GraphQLValue.self)
    }

    /// Whether the venue's chat takes karaoke signups tonight: `Venue.requests.karaoke`.
    public func karaokeSignups(venueID: String) async throws -> KaraokeSignups {
        struct Requests: Decodable, Sendable { let karaoke: KaraokeSignups }
        struct Venue: Decodable, Sendable { let requests: Requests }
        struct Venues: Decodable, Sendable { let venue: Venue? }
        struct Response: Decodable, Sendable { let venues: Venues }
        func load(_ fields: String) async throws -> KaraokeSignups {
            let response = try await session.graphQL("""
                query VelvetKaraokeSignups($id: ID!) {
                  venues { venue(id: $id) { requests { karaoke { \(fields) } } } }
                }
                """, variables: ["id": .string(venueID)], as: Response.self)
            guard let venue = response.venues.venue else { throw AudienceKitError.notFound }
            return venue.requests.karaoke
        }
        do { return try await load(Self.karaokeCutoffFields) }
        catch let error as AudienceKitError where error.code == AudienceKitError.Code.notFound { throw error }
        catch { return try await load(Self.karaokeSignupFields) }
    }

    /// Reopens karaoke signups for tonight past their cutoff (and unpauses them), or lets the cutoff close them again:
    /// the KJ's override. It lifts by itself when the night ends.
    public func setKaraokeReopened(venueID: String, _ reopened: Bool) async throws -> KaraokeSignups {
        try await updateKaraoke(venueID: venueID, ["karaokeReopened": .bool(reopened)], fields: Self.karaokeCutoffFields)
    }

    private func updateKaraoke(venueID: String, _ venue: [String: GraphQLValue], fields: String) async throws -> KaraokeSignups {
        struct Requests: Decodable, Sendable { let karaoke: KaraokeSignups }
        struct Venue: Decodable, Sendable { let requests: Requests }
        struct Payload: Decodable, Sendable { let venue: Venue }
        struct Response: Decodable, Sendable { let updateVenue: Payload }
        let response = try await session.graphQL("""
            mutation VelvetKaraokeSignupsUpdate($input: VenueUpdateInput!) {
              updateVenue(input: $input) { venue { requests { karaoke { \(fields) } } } }
            }
            """, variables: ["input": .object(["id": .string(venueID), "venue": .object(venue)])], as: Response.self)
        return response.updateVenue.venue.requests.karaoke
    }

    /// Pauses karaoke signups for tonight, or takes them again: the singers already on the lineup still sing. It lifts
    /// by itself when the night ends.
    public func setKaraokePaused(venueID: String, _ paused: Bool) async throws -> KaraokeSignups {
        struct Requests: Decodable, Sendable { let karaoke: KaraokeSignups }
        struct Venue: Decodable, Sendable { let requests: Requests }
        struct Payload: Decodable, Sendable { let venue: Venue }
        struct Response: Decodable, Sendable { let updateVenue: Payload }
        let response = try await session.graphQL("""
            mutation VelvetKaraokePause($input: VenueUpdateInput!) {
              updateVenue(input: $input) { venue { requests { karaoke { \(Self.karaokeSignupFields) } } } }
            }
            """, variables: ["input": .object(["id": .string(venueID), "venue": .object(["karaokePaused": .bool(paused)])])],
            as: Response.self)
        return response.updateVenue.venue.requests.karaoke
    }

    /// Finishes a singer early (`.done`) or skips them (`.skipped`, which takes them off the lineup). Advancing calls
    /// singers up, so the API refuses `.up` and `.queued` for them.
    public func setSongRequestState(id: String, _ state: VenueAppearance.SongRequest.State) async throws {
        _ = try await session.graphQL("""
            mutation VelvetSongRequestState($input: SongRequestSetStateInput!) {
              setSongRequestState(input: $input) { request { id state } }
            }
            """, variables: ["input": .object(["id": .string(id), "state": .string(state.rawValue)])], as: GraphQLValue.self)
    }

    /// Changes one night's cover: `amount` of zero cents for no cover or nil for the usual price; `from` and `until`
    /// as HH:MM, or nil for the usual hours. It wins over the usual cover and over an event that night. `scale` makes
    /// that night's price a sliding scale, with `amount` as the suggested amount.
    public func setCoverNight(venueID: String, night: String, amount: Money?, from: String?, until: String?,
                              scale: VenueCoverScale? = nil) async throws {
        var input: [String: GraphQLValue] = [
            "venueId": .string(venueID), "night": .string(night),
            "amount": amount.map(\.graphQLValue) ?? .null,
            "from": from.map(GraphQLValue.string) ?? .null, "until": until.map(GraphQLValue.string) ?? .null
        ]
        if let scale {
            input["min"] = Money.usd(scale.min).graphQLValue
            input["max"] = Money.usd(scale.max).graphQLValue
        }
        _ = try await session.graphQL("mutation VelvetCoverNightSet($input: CoverNightSetInput!) { setCoverNight(input: $input) { coverNight { night } } }",
                                    variables: ["input": .object(input)], as: GraphQLValue.self)
    }

    /// Puts a night back to the usual cover.
    public func clearCoverNight(venueID: String, night: String) async throws {
        _ = try await session.graphQL("mutation VelvetCoverNightClear($input: CoverNightClearInput!) { clearCoverNight(input: $input) { venue { id } } }",
                                    variables: ["input": .object(["venueId": .string(venueID), "night": .string(night)])], as: GraphQLValue.self)
    }
}

/// Where a lineup is: a venue's night (its own lineup, then its events'), or one event's, built ahead. The staff apps'
/// lineup editor (StaffKitUI's `StaffLineupView`) reads its times in ``zone``, the venue's.
public struct LineupPlace: Sendable, Hashable {
    public let venueID: String
    /// The venue's zone: its nights and times are counted in it.
    public let zone: TimeZone
    /// The night, "yyyy-MM-dd": the event's for an event's lineup.
    public let night: String
    /// Tonight's night, "yyyy-MM-dd", as the venue counts it (Velvet's door), for what only tonight can do.
    public let tonight: String
    /// Just this event's lineup; nil for the whole night's.
    public let event: VenueAppearance.Event?

    public init(venueID: String, zone: TimeZone, night: String, tonight: String? = nil, event: VenueAppearance.Event? = nil) {
        self.venueID = venueID; self.zone = zone; self.night = night; self.event = event
        self.tonight = tonight ?? Self.night(of: Date(), in: zone)
    }

    /// An event's lineup, on the event's night (tonight's when it has no start).
    public init(venueID: String, zone: TimeZone, event: VenueAppearance.Event, tonight: String? = nil) {
        let night = parseInstant(event.startAt).map { Self.night(of: $0, in: zone) }
        self.init(venueID: venueID, zone: zone, night: night ?? tonight ?? Self.night(of: Date(), in: zone), tonight: tonight, event: event)
    }

    public var isTonight: Bool { night == tonight }
    /// When the night starts: 6 AM that day at the venue.
    public var nightStart: Date? { Self.start(of: night, in: zone) }
    /// When the event starts, for an event's lineup.
    public var eventStart: Date? { parseInstant(event?.startAt) }

    /// The night an instant belongs to: nights run 6 AM to 6 AM at the venue, so 1 AM Saturday is Friday night.
    public static func night(of instant: Date, in zone: TimeZone) -> String {
        CivilDate.string(from: instant.addingTimeInterval(-6 * 3600), in: zone)
    }

    /// When a night ("yyyy-MM-dd") starts: 6 AM that day in `zone`.
    public static func start(of night: String, in zone: TimeZone) -> Date? {
        guard let day = CivilDate.date(night) else { return nil }
        let parts = Calendar(identifier: .gregorian).dateComponents(in: CivilDate.utc, from: day)
        return venueCalendar(zone).date(from: DateComponents(year: parts.year, month: parts.month, day: parts.day, hour: 6))
    }
}
