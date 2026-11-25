import Foundation
import AudienceCore
import StaffKitCore

// The lineup model (the API's doc/LINEUP_MODEL.md, Rick 2026-10-24): a venue has zones (Stage is the default, then
// named ones like Patio). Each zone has a night lineup that runs open to close, and each event in the zone is one
// element of it with its own lineup there. A lineup has one or more hosts that its acts share; an act has scenes,
// each with one or more performers; breaks sit between acts, or inside an act after a scene. A show runs preshow,
// then the host, then scenes (each going back to the host or on to the next scene), then postshow.
//
// This is what the console's zone board reads (`ZoneBoardQuery`) and how it cues a show (`cueLineup`). It's fetched
// apart from the running order, so an API without the lineup model (production before it) only fails these calls,
// and the apps keep the running order they had.

/// Where a scene, a break or a lineup's scenes go when they end: back to the host, or straight on to the next scene.
public struct ShowEndsTo: RawRepresentable, Codable, Sendable, Hashable, CaseIterable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let host = ShowEndsTo(rawValue: "HOST")
    public static let next = ShowEndsTo(rawValue: "NEXT")
    public static let allCases: [ShowEndsTo] = [.host, .next]
    /// "Back to the host", "On to the next scene".
    public var label: String { self == .next ? "On to the next scene" : "Back to the host" }
}

/// A venue's stage area. The default zone, Stage, needs no row: a lineup with no ``ZoneLineup/zoneID`` is in it.
public struct StageZone: Decodable, Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    /// Whether it's the default zone, renamed.
    public let isDefault: Bool
    public let position: Int

    public init(id: String, name: String, isDefault: Bool = false, position: Int = 0) {
        self.id = id; self.name = name; self.isDefault = isDefault; self.position = position
    }
}

/// An entry on a zone lineup: the running order's appearance, its show control and its editor settings (all read
/// from one selection), and where it sits in the lineup model.
public struct ZoneLineupEntry: Decodable, Sendable, Hashable, Identifiable {
    public let appearance: VenueAppearance
    public let show: ShowLineupEntry
    public let details: ShowEntryDetails
    /// A break inside an act: the scene it follows.
    public let afterSceneID: String?
    /// An activity break that runs across the whole venue, not just its zone.
    public let venueWide: Bool
    public let lineupID: String?

    public var id: String { appearance.id }

    private struct Ref: Decodable, Sendable { let id: String }
    private enum CodingKeys: String, CodingKey { case afterScene, venueWide, lineup }

    public init(appearance: VenueAppearance, show: ShowLineupEntry, details: ShowEntryDetails? = nil,
                afterSceneID: String? = nil, venueWide: Bool = false, lineupID: String? = nil) {
        self.appearance = appearance; self.show = show; self.details = details ?? ShowEntryDetails(id: appearance.id)
        self.afterSceneID = afterSceneID; self.venueWide = venueWide; self.lineupID = lineupID
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(appearance: try VenueAppearance(from: decoder), show: try ShowLineupEntry(from: decoder),
                  details: try? ShowEntryDetails(from: decoder),
                  afterSceneID: try c.decodeIfPresent(Ref.self, forKey: .afterScene)?.id,
                  venueWide: try c.decodeIfPresent(Bool.self, forKey: .venueWide) ?? false,
                  lineupID: try c.decodeIfPresent(Ref.self, forKey: .lineup)?.id)
    }

    /// A break's (or an act's scenes') own setting for where they go when they end; nil follows the lineup.
    public var endsTo: ShowEndsTo? { show.endsTo }
    public var isAct: Bool { show.kind == .act }
    /// A break: an intermission or a segment.
    public var isBreak: Bool { !isAct }
    /// A host, MC or DJ entry: on by the clock, not a step of the show.
    public var isClockRun: Bool { !appearance.isAdvanceable }
}

/// One show: a zone's night (open to close), or an event's lineup in a zone.
public struct ZoneLineup: Decodable, Sendable, Hashable, Identifiable {
    /// Where the show is. Unknown phases from a newer API decode as themselves.
    public struct Phase: RawRepresentable, Codable, Sendable, Hashable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        /// An event's lineup before the event starts (its zone's night is on).
        public static let scheduled = Phase(rawValue: "SCHEDULED")
        /// From the event's start (or a zone night before it opens) until "Start the show".
        public static let preshow = Phase(rawValue: "PRESHOW")
        /// The hosts have the stage, between scenes.
        public static let host = Phase(rawValue: "HOST")
        public static let scene = Phase(rawValue: "SCENE")
        public static let onBreak = Phase(rawValue: "BREAK")
        /// A zone's night: one of its events is on.
        public static let event = Phase(rawValue: "EVENT")
        public static let postshow = Phase(rawValue: "POSTSHOW")
        public static let ended = Phase(rawValue: "ENDED")

        /// "Preshow", "Host on", "On a break".
        public var label: String {
            switch self {
            case .scheduled: "Not started"
            case .preshow: "Preshow"
            case .host: "Host on"
            case .scene: "Scene on"
            case .onBreak: "On a break"
            case .event: "Event on"
            case .postshow: "Postshow"
            case .ended: "Ended"
            default: rawValue.lowercased().capitalizingFirst
            }
        }
    }

    /// A step of a show: a scene (its performers), a break, or, on a zone's night, an event.
    public struct Step: Decodable, Sendable, Hashable {
        public struct Kind: RawRepresentable, Codable, Sendable, Hashable {
            public let rawValue: String
            public init(rawValue: String) { self.rawValue = rawValue }
            public static let scene = Kind(rawValue: "SCENE")
            public static let intermission = Kind(rawValue: "INTERMISSION")
            public static let segment = Kind(rawValue: "SEGMENT")
            public static let event = Kind(rawValue: "EVENT")
        }
        private struct Ref: Decodable, Sendable, Hashable { let id: String }

        /// Its own (`step:<kind>:<target>`), not the record's.
        public let id: String
        /// The scene's, break's or event lineup's ID.
        public let targetID: String
        public let kind: Kind
        public let title: String?
        public let performers: [VenueEvent.Person]
        public let state: VenueAppearance.Status
        public let wentOnAt: String?
        public let cameOffAt: String?
        public let endsTo: ShowEndsTo?
        /// The act a scene is in, the break's entry, or the event's lineup.
        public let actID: String?
        public let entryID: String?
        public let lineupID: String?

        private enum CodingKeys: String, CodingKey {
            case id, kind, title, performers, state, wentOnAt, cameOffAt, endsTo, act, entry, lineup
            case targetID = "targetId"
        }

        public init(id: String, targetID: String, kind: Kind, title: String? = nil, performers: [VenueEvent.Person] = [],
                    state: VenueAppearance.Status = .upcoming, wentOnAt: String? = nil, cameOffAt: String? = nil,
                    endsTo: ShowEndsTo? = nil, actID: String? = nil, entryID: String? = nil, lineupID: String? = nil) {
            self.id = id; self.targetID = targetID; self.kind = kind; self.title = title; self.performers = performers
            self.state = state; self.wentOnAt = wentOnAt; self.cameOffAt = cameOffAt; self.endsTo = endsTo
            self.actID = actID; self.entryID = entryID; self.lineupID = lineupID
        }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.init(id: try c.decode(String.self, forKey: .id), targetID: try c.decode(String.self, forKey: .targetID),
                      kind: try c.decode(Kind.self, forKey: .kind), title: try c.decodeIfPresent(String.self, forKey: .title),
                      performers: try c.decodeIfPresent([VenueEvent.Person].self, forKey: .performers) ?? [],
                      state: (try? c.decodeIfPresent(VenueAppearance.Status.self, forKey: .state)) ?? .upcoming,
                      wentOnAt: try c.decodeIfPresent(String.self, forKey: .wentOnAt),
                      cameOffAt: try c.decodeIfPresent(String.self, forKey: .cameOffAt),
                      endsTo: try c.decodeIfPresent(ShowEndsTo.self, forKey: .endsTo),
                      actID: try c.decodeIfPresent(Ref.self, forKey: .act)?.id,
                      entryID: try c.decodeIfPresent(Ref.self, forKey: .entry)?.id,
                      lineupID: try c.decodeIfPresent(Ref.self, forKey: .lineup)?.id)
        }

        /// "Juniper Blaze & Mona Lott", the step's title, or what it is.
        public var displayName: String {
            if let title, !title.isEmpty, kind != .scene { return title }
            let names = performers.compactMap(\.name)
            if !names.isEmpty { return names.formatted(.list(type: .and)) }
            if let title, !title.isEmpty { return title }
            switch kind {
            case .intermission: return "Intermission"
            case .segment: return "Segment"
            case .event: return "Event"
            default: return "Scene"
            }
        }
    }

    /// The event an event's lineup belongs to.
    public struct Event: Decodable, Sendable, Hashable, Identifiable {
        public let id: String
        public let name: String?
        public let startAt: String?
        public let endAt: String?
        public init(id: String, name: String?, startAt: String? = nil, endAt: String? = nil) {
            self.id = id; self.name = name; self.startAt = startAt; self.endAt = endAt
        }
    }

    private struct Ref: Decodable, Sendable, Hashable { let id: String }

    public let id: String
    /// "Stage", "Friday Follies".
    public let name: String
    public let zoneName: String
    /// Nil in the default zone.
    public let zoneID: String?
    public let night: String
    public let phase: Phase
    public let opensAt: String?
    public let closesAt: String?
    public let startedAt: String?
    public let endedAt: String?
    /// Where its scenes go when they end, unless a scene or its act says; nil for the host.
    public let sceneEndsTo: ShowEndsTo?
    public let title: String?
    /// The event, for an event's lineup; nil for a zone's night.
    public let event: Event?
    /// In billing order. Every act on the lineup has them.
    public let hosts: [VenueEvent.Person]
    public let current: Step?
    public let upNext: Step?
    /// In running order: on a zone's night, its own entries; on an event's, its acts and breaks.
    public let entries: [ZoneLineupEntry]
    /// A zone's night: its events' lineups in the zone, by start.
    public let children: [ZoneLineup]

    private enum CodingKeys: String, CodingKey {
        case id, name, zoneName, zone, night, phase, opensAt, closesAt, startedAt, endedAt, sceneEndsTo, title, event, hosts
        case current, upNext, entries, children
    }

    public init(id: String, name: String, zoneName: String = "Stage", zoneID: String? = nil, night: String, phase: Phase = .scheduled,
                opensAt: String? = nil, closesAt: String? = nil, startedAt: String? = nil, endedAt: String? = nil,
                sceneEndsTo: ShowEndsTo? = nil, title: String? = nil, event: Event? = nil, hosts: [VenueEvent.Person] = [],
                current: Step? = nil, upNext: Step? = nil, entries: [ZoneLineupEntry] = [], children: [ZoneLineup] = []) {
        self.id = id; self.name = name; self.zoneName = zoneName; self.zoneID = zoneID; self.night = night; self.phase = phase
        self.opensAt = opensAt; self.closesAt = closesAt; self.startedAt = startedAt; self.endedAt = endedAt
        self.sceneEndsTo = sceneEndsTo; self.title = title; self.event = event; self.hosts = hosts; self.current = current
        self.upNext = upNext; self.entries = entries; self.children = children
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decode(String.self, forKey: .id), name: try c.decodeIfPresent(String.self, forKey: .name) ?? "",
                  zoneName: try c.decodeIfPresent(String.self, forKey: .zoneName) ?? "Stage",
                  zoneID: try c.decodeIfPresent(Ref.self, forKey: .zone)?.id,
                  night: try c.decode(String.self, forKey: .night),
                  phase: try c.decodeIfPresent(Phase.self, forKey: .phase) ?? .scheduled,
                  opensAt: try c.decodeIfPresent(String.self, forKey: .opensAt),
                  closesAt: try c.decodeIfPresent(String.self, forKey: .closesAt),
                  startedAt: try c.decodeIfPresent(String.self, forKey: .startedAt),
                  endedAt: try c.decodeIfPresent(String.self, forKey: .endedAt),
                  sceneEndsTo: try c.decodeIfPresent(ShowEndsTo.self, forKey: .sceneEndsTo),
                  title: try c.decodeIfPresent(String.self, forKey: .title),
                  event: try c.decodeIfPresent(Event.self, forKey: .event),
                  hosts: try c.decodeIfPresent([VenueEvent.Person].self, forKey: .hosts) ?? [],
                  current: try c.decodeIfPresent(Step.self, forKey: .current),
                  upNext: try c.decodeIfPresent(Step.self, forKey: .upNext),
                  entries: try c.decodeIfPresent([ZoneLineupEntry].self, forKey: .entries) ?? [],
                  children: try c.decodeIfPresent([ZoneLineup].self, forKey: .children) ?? [])
    }

    /// A zone's night (rather than an event's lineup).
    public var isZoneNight: Bool { event == nil }
    /// Whether it's in the default zone (Stage).
    public var isDefaultZone: Bool { zoneID == nil }
    /// Its acts, in running order.
    public var acts: [ZoneLineupEntry] { entries.filter(\.isAct) }
    /// The breaks inside `act`, after each of its scenes, by scene ID.
    public func breaks(in act: ZoneLineupEntry) -> [String: [ZoneLineupEntry]] {
        let scenes = Set(act.show.scenes.map(\.id))
        return Dictionary(grouping: entries.filter { $0.isBreak && $0.afterSceneID.map(scenes.contains) == true }) { $0.afterSceneID ?? "" }
    }
    /// What runs at its own place in the running order: acts, and breaks between acts (not inside one).
    public var topLevel: [ZoneLineupEntry] {
        let scenes = Set(acts.flatMap { $0.show.scenes.map(\.id) })
        return entries.filter { entry in entry.isAct || !(entry.afterSceneID.map(scenes.contains) ?? false) }
    }
    /// Whether the show has begun: anything past scheduled and preshow.
    public var hasBegun: Bool { ![.scheduled, .preshow].contains(phase) }
    /// The lineup that's on in its zone now: a running event's, else itself. For a zone's night only.
    public var live: ZoneLineup {
        children.first { ![.scheduled, .ended].contains($0.phase) } ?? self
    }
}

/// A venue night by zone: its zones, each zone's night lineup with its events' lineups there, and its support staff.
public struct ZoneNight: Sendable, Hashable {
    /// The venue's named zones, in order. The default zone is listed only once it's renamed.
    public let zones: [StageZone]
    /// One per zone, the default zone first.
    public let lineups: [ZoneLineup]
    /// The night's support staff; ``SupportStaff/lineupID`` nil works every zone.
    public let supportStaff: [SupportStaff]

    public init(zones: [StageZone] = [], lineups: [ZoneLineup] = [], supportStaff: [SupportStaff] = []) {
        self.zones = zones; self.lineups = lineups; self.supportStaff = supportStaff
    }

    /// A zone's night lineup; nil for the default zone.
    public func lineup(zoneID: String?) -> ZoneLineup? { lineups.first { $0.zoneID == zoneID } }
    /// Every event on the night, from every zone, once each, by start.
    public var events: [ZoneLineup.Event] {
        var seen = Set<String>()
        return lineups.flatMap(\.children).compactMap(\.event).filter { seen.insert($0.id).inserted }
            .sorted { ($0.startAt ?? "") < ($1.startAt ?? "") }
    }
    /// The support staff working a zone's lineups (its night and its events'), and those working every zone.
    public func supportStaff(in lineup: ZoneLineup) -> [SupportStaff] {
        let ids = Set([lineup.id] + lineup.children.map(\.id))
        return supportStaff.filter { $0.lineupID.map(ids.contains) ?? true }
    }
}

/// What ``VenueManagementClient/cueLineup(id:cue:force:)`` does to a show.
/// One event's lineups by zone (``VenueManagementClient/eventZoneLineups(eventID:)``).
public struct EventZoneLineups: Sendable, Hashable {
    /// One per zone it uses, the default zone's first.
    public let lineups: [ZoneLineup]
    public let supportStaff: [SupportStaff]
    /// Its venue's zones. The default zone is listed only when the venue named it.
    public let zones: [StageZone]

    public init(lineups: [ZoneLineup], supportStaff: [SupportStaff], zones: [StageZone]) {
        self.lineups = lineups; self.supportStaff = supportStaff; self.zones = zones
    }

    public func lineup(zoneID: String?) -> ZoneLineup? { lineups.first { $0.zoneID == zoneID } }

    /// The default zone's name: the venue's, else "Stage".
    public var defaultZoneName: String { zones.first(where: \.isDefault)?.name ?? "Stage" }

    /// A zone to put it in: nil ID for the default zone.
    public struct ZoneChoice: Sendable, Hashable, Identifiable {
        public let id: String?
        public let name: String
        public init(id: String?, name: String) { self.id = id; self.name = name }
    }

    /// Zones it isn't in yet.
    public var otherZones: [ZoneChoice] {
        let all = [ZoneChoice(id: nil, name: defaultZoneName)] + zones.filter { !$0.isDefault }.map { ZoneChoice(id: $0.id, name: $0.name) }
        return all.filter { zone in !lineups.contains { $0.zoneID == zone.id } }
    }
}

public struct LineupCue: RawRepresentable, Codable, Sendable, Hashable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    /// Starts the show (the host comes on), puts on the next scene, ends a scene, ends the show when nothing is left,
    /// leaves postshow.
    public static let advance = LineupCue(rawValue: "ADVANCE")
    /// Undoes the latest change in the zone.
    public static let back = LineupCue(rawValue: "BACK")
    /// Ends the show now.
    public static let end = LineupCue(rawValue: "END")
}

extension VenueManagementClient {
    static let lineupStepFields = "id targetId kind title performers { id name avatarUrl } state wentOnAt cameOffAt endsTo act { id } entry { id } lineup { id }"
    static let zoneEntryFields = "\(appearanceFields) \(showEntryFields) \(showDetailsFields) endsTo venueWide lineup { id } afterScene { id } scenes { performers { id name avatarUrl } endsTo wentOnAt cameOffAt }"
    static let zoneLineupFields = "id name zoneName zone { id } night phase opensAt closesAt startedAt endedAt sceneEndsTo title event { id name startAt endAt } hosts { id name avatarUrl } current { \(lineupStepFields) } upNext { \(lineupStepFields) } entries { \(zoneEntryFields) }"
    static let stageZoneFields = "id name isDefault position"

    /// A venue night by zone (tonight when nil, as "yyyy-MM-dd" otherwise): the zones, each zone's night with its
    /// events' lineups, and the support staff. Throws on an API without the lineup model.
    public func zoneNight(venueID: String, night: String? = nil) async throws -> ZoneNight {
        struct People: Decodable, Sendable { let stageZones: [StageZone]; let lineups: [ZoneLineup]; let supportStaff: [SupportStaff]? }
        struct Venue: Decodable, Sendable { let people: People }
        struct Venues: Decodable, Sendable { let venue: Venue? }
        struct Response: Decodable, Sendable { let venues: Venues }
        let response = try await session.graphQL("""
            query StaffZoneNight($id: ID!, $night: ISO8601Date) {
              venues {
                venue(id: $id) {
                  people {
                    stageZones { \(Self.stageZoneFields) }
                    lineups(night: $night) { \(Self.zoneLineupFields) children { \(Self.zoneLineupFields) } }
                    supportStaff(night: $night) { \(Self.supportStaffFields) lineup { id } }
                  }
                }
              }
            }
            """, variables: ["id": .string(venueID), "night": night.map(GraphQLValue.string) ?? .null], as: Response.self)
        guard let venue = response.venues.venue else { throw AudienceKitError.notFound }
        return ZoneNight(zones: venue.people.stageZones, lineups: venue.people.lineups, supportStaff: venue.people.supportStaff ?? [])
    }

    /// An event's lineups, one per zone it uses (the default zone's when it has none), its support staff, and its
    /// venue's zones (to put it in another). Throws on an API without the lineup model.
    public func eventZoneLineups(eventID: String) async throws -> EventZoneLineups {
        struct People: Decodable, Sendable { let lineups: [ZoneLineup]; let supportStaff: [SupportStaff]? }
        struct VenuePeople: Decodable, Sendable { let stageZones: [StageZone] }
        struct Venue: Decodable, Sendable { let people: VenuePeople }
        struct EventVenue: Decodable, Sendable { let venue: Venue? }
        struct Event: Decodable, Sendable { let people: People; let venue: EventVenue }
        struct Events: Decodable, Sendable { let event: Event? }
        struct Response: Decodable, Sendable { let events: Events }
        let response = try await session.graphQL("""
            query StaffEventZoneLineups($id: ID!) {
              events {
                event(id: $id) {
                  people { lineups { \(Self.zoneLineupFields) } supportStaff { \(Self.supportStaffFields) lineup { id } } }
                  venue { venue { people { stageZones { \(Self.stageZoneFields) } } } }
                }
              }
            }
            """, variables: ["id": .string(eventID)], as: Response.self)
        guard let event = response.events.event else { throw AudienceKitError.notFound }
        return EventZoneLineups(lineups: event.people.lineups, supportStaff: event.people.supportStaff ?? [],
                                zones: event.venue.venue?.people.stageZones ?? [])
    }

    /// Moves a show along. On a zone's night it moves whichever show is on in the zone (an event's while it's on).
    /// Returns the show on in the zone now. A curtain call that isn't clear throws (``isNotEveryoneReady(_:)``) unless
    /// `force` (go anyway).
    @discardableResult
    public func cueLineup(id: String, cue: LineupCue = .advance, force: Bool = false) async throws -> ZoneLineup {
        struct Payload: Decodable, Sendable { let stage: ZoneLineup }
        struct Response: Decodable, Sendable { let cueLineup: Payload? }
        let response = try await session.graphQL("""
            mutation StaffLineupCue($input: LineupCueInput!) { cueLineup(input: $input) { stage { \(Self.zoneLineupFields) } } }
            """, variables: ["input": .object(["lineupId": .string(id), "cue": .string(cue.rawValue), "force": .bool(force)])],
            as: Response.self)
        guard let payload = response.cueLineup else { throw AudienceKitError.decoding("The cue was missing") }
        return payload.stage
    }

    /// Puts someone on as the host right now, in one step (`putHostOn`): they join the lineup's hosts and go on stage,
    /// an event not started yet starts now, the show starts, and the venue's chat lists them at once. Name the lineup
    /// (`lineupID`), or the venue and optionally its event for that default-zone lineup. `replace` takes the hosts on
    /// now off. Returns the lineup.
    @discardableResult
    public func putHostOn(personID: String, lineupID: String? = nil, venueID: String? = nil, eventID: String? = nil,
                          replace: Bool = false) async throws -> ZoneLineup {
        struct Payload: Decodable, Sendable { let lineup: ZoneLineup }
        struct Response: Decodable, Sendable { let putHostOn: Payload? }
        var input: [String: GraphQLValue] = ["personId": .string(personID), "replace": .bool(replace)]
        if let lineupID { input["lineupId"] = .string(lineupID) }
        if let venueID { input["venueId"] = .string(venueID) }
        if let eventID { input["eventId"] = .string(eventID) }
        let response = try await session.graphQL("""
            mutation StaffPutHostOn($input: LineupHostPutOnInput!) { putHostOn(input: $input) { lineup { \(Self.zoneLineupFields) } } }
            """, variables: ["input": .object(input)], as: Response.self)
        guard let payload = response.putHostOn else { throw AudienceKitError.decoding("The lineup was missing") }
        return payload.lineup
    }

    /// Puts an event in a zone (nil: the default zone), returning its lineup's ID there.
    @discardableResult
    public func createEventLineup(eventID: String, zoneID: String?) async throws -> String {
        struct Lineup: Decodable, Sendable { let id: String }
        struct Payload: Decodable, Sendable { let lineup: Lineup }
        struct Response: Decodable, Sendable { let createLineup: Payload }
        let response = try await session.graphQL("""
            mutation StaffLineupCreate($input: LineupCreateInput!) { createLineup(input: $input) { lineup { id } } }
            """, variables: ["input": .object(["eventId": .string(eventID), "zoneId": zoneID.map(GraphQLValue.string) ?? .null])],
            as: Response.self)
        return response.createLineup.lineup.id
    }

    /// Takes an event out of a zone: its lineup there goes, and its entries fall back to the default zone's.
    public func deleteLineup(id: String) async throws {
        _ = try await session.graphQL("""
            mutation StaffLineupDelete($input: LineupDeleteInput!) { deleteLineup(input: $input) { clientMutationId } }
            """, variables: ["input": .object(["id": .string(id)])], as: GraphQLValue.self)
    }

    /// Changes a lineup: `hostIds`, `title`, `sceneEndsTo` (HOST or NEXT, null for the host), a zone night's `opensAt`
    /// and `closesAt`. Send only what changed.
    public func updateLineup(id: String, fields: [String: GraphQLValue]) async throws {
        _ = try await session.graphQL("""
            mutation StaffLineupUpdate($input: LineupUpdateInput!) { updateLineup(input: $input) { lineup { id } } }
            """, variables: ["input": .object(["id": .string(id), "lineup": .object(fields)])], as: GraphQLValue.self)
    }

    /// The venue's guests: people put on its lineups by name, like a one-off host, who have no People page. Empty for
    /// anyone not working its shows, and from an API without guests (production until next is promoted).
    public func guests(venueID: String) async throws -> [VenueEvent.Person] {
        struct People: Decodable, Sendable { let guests: [VenueEvent.Person] }
        struct Venue: Decodable, Sendable { let people: People }
        struct Venues: Decodable, Sendable { let venue: Venue? }
        struct Response: Decodable, Sendable { let venues: Venues }
        do {
            return try await session.graphQL("""
                query StaffVenueGuests($id: ID!) { venues { venue(id: $id) { people { guests { id name avatarUrl } } } } }
                """, variables: ["id": .string(venueID)], as: Response.self).venues.venue?.people.guests ?? []
        } catch let error where error.isCancellation { throw error } catch { return [] }
    }

    /// Adds someone to the venue's lineups by name, without a People page: a guest. A guest of the venue with that name
    /// already comes back instead, so they keep one history. With `eventID`, the event's people may add one too.
    public func createGuestPerson(venueID: String, eventID: String?, name: String) async throws -> VenueEvent.Person {
        struct Payload: Decodable, Sendable { let person: VenueEvent.Person }
        struct Response: Decodable, Sendable { let createGuestPerson: Payload? }
        let response = try await session.graphQL("""
            mutation StaffGuestCreate($input: PersonGuestCreateInput!) { createGuestPerson(input: $input) { person { id name avatarUrl } } }
            """, variables: ["input": .object(["venueId": .string(venueID), "eventId": eventID.map(GraphQLValue.string) ?? .null,
                                               "name": .string(name)])],
            as: Response.self)
        guard let payload = response.createGuestPerson else { throw AudienceKitError.decoding("The guest was missing") }
        return payload.person
    }

    /// Adds a zone to a venue ("+ Add zone"), after its others.
    @discardableResult
    public func createStageZone(venueID: String, name: String) async throws -> StageZone {
        struct Payload: Decodable, Sendable { let zone: StageZone? }
        struct Response: Decodable, Sendable { let createStageZone: Payload }
        let response = try await session.graphQL("""
            mutation StaffStageZoneCreate($input: StageZoneCreateInput!) { createStageZone(input: $input) { zone { \(Self.stageZoneFields) } } }
            """, variables: ["input": .object(["venueId": .string(venueID), "zone": .object(["name": .string(name)])])],
            as: Response.self)
        guard let zone = response.createStageZone.zone else { throw AudienceKitError.decoding("The zone was missing") }
        return zone
    }

    /// Renames a zone, moves it (`position`) or makes it the default (`isDefault`).
    public func updateStageZone(id: String, fields: [String: GraphQLValue]) async throws {
        _ = try await session.graphQL("""
            mutation StaffStageZoneUpdate($input: StageZoneUpdateInput!) { updateStageZone(input: $input) { zone { id } } }
            """, variables: ["input": .object(["id": .string(id), "zone": .object(fields)])], as: GraphQLValue.self)
    }

    /// Removes a zone: its lineups go, their entries fall back to the default zone, and its support staff then work
    /// every zone.
    public func deleteStageZone(id: String) async throws {
        _ = try await session.graphQL("""
            mutation StaffStageZoneDelete($input: StageZoneDeleteInput!) { deleteStageZone(input: $input) { clientMutationId } }
            """, variables: ["input": .object(["id": .string(id)])], as: GraphQLValue.self)
    }
}
