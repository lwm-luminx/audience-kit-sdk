import Foundation
import AudienceCore
import StaffKitCore

// Show control (the API's doc/SHOW_CONTROL.md), for the people working a show:
//
// - Entries are acts, intermissions or segments (a generic time block with a title, "Photos with cast"). A segment or
//   intermission can run an activity in the venue's chat: group trivia or the event's chat prompts.
// - An act can have a curtain call (`curtainCallMinutes`): places is called that many minutes before it, and advancing
//   onto it waits for its go/no-go (the places check): the venue, the talent and the required support staff ready.
//   The venue or the hosts can override a holdout or go anyway.
// - Support staff are person X in role Y on a show (Rick Mark on photography).
// - An act is a set of scenes (one per number), and the running order projects when each entry goes on, moved out
//   when the show runs late; intermissions stretch or shrink to win the time back.
// - Group trivia rounds are cards in the venue's chat the room votes on together; a host segment's host opens and
//   reveals them.
//
// It's fetched apart from the night (`night(venueID:)`) so an API without show control (older than its 2026-10-22
// release) only fails these calls, and the lineup works as before.

/// What show control knows about one lineup entry. Match it to a ``VenueAppearance`` by ``id``.
public struct ShowLineupEntry: Decodable, Sendable, Hashable, Identifiable {
    public struct Kind: RawRepresentable, Codable, Sendable, Hashable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let act = Kind(rawValue: "ACT")
        public static let intermission = Kind(rawValue: "INTERMISSION")
        public static let segment = Kind(rawValue: "SEGMENT")
    }

    public struct Activity: RawRepresentable, Codable, Sendable, Hashable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let trivia = Activity(rawValue: "TRIVIA")
        public static let prompts = Activity(rawValue: "PROMPTS")
    }

    /// One number in an act.
    public struct Scene: Decodable, Sendable, Hashable, Identifiable {
        public struct Track: Decodable, Sendable, Hashable {
            public let id: String
            public let name: String?
            public init(id: String, name: String? = nil) { self.id = id; self.name = name }
        }
        public let id: String
        public let title: String?
        public let performer: VenueEvent.Person?
        /// Its length as set, when it isn't read from its track.
        public let seconds: Int?
        /// Time after it before the next; nil for the default (2 minutes).
        public let gapSeconds: Int?
        /// How long it runs: as set, else its track's length.
        public let lengthSeconds: Int?
        /// Its track, for the back-of-house room's members.
        public let track: Track?
        /// The lineup model's (``VenueManagementClient/zoneNight(venueID:night:)``): everyone in it, where it goes
        /// when it ends, and when it ran. Nil from the running order's queries.
        public let performers: [VenueEvent.Person]?
        public let endsTo: ShowEndsTo?
        public let wentOnAt: String?
        public let cameOffAt: String?

        public init(id: String, title: String? = nil, performer: VenueEvent.Person? = nil, seconds: Int? = nil,
                    gapSeconds: Int? = nil, lengthSeconds: Int? = nil, track: Track? = nil, performers: [VenueEvent.Person]? = nil,
                    endsTo: ShowEndsTo? = nil, wentOnAt: String? = nil, cameOffAt: String? = nil) {
            self.id = id; self.title = title; self.performer = performer; self.seconds = seconds
            self.gapSeconds = gapSeconds; self.lengthSeconds = lengthSeconds; self.track = track
            self.performers = performers; self.endsTo = endsTo; self.wentOnAt = wentOnAt; self.cameOffAt = cameOffAt
        }

        /// Who's in it: its performers, else its one performer.
        public var people: [VenueEvent.Person] { performers ?? performer.map { [$0] } ?? [] }
    }

    public struct TriviaSet: Decodable, Sendable, Hashable, Identifiable {
        public let key: String
        public let title: String
        public init(key: String, title: String) { self.key = key; self.title = title }
        public var id: String { key }
    }

    public let id: String
    public let kind: Kind
    public let activity: Activity?
    public let curtainCallMinutes: Int?
    public let durationMinutes: Int?
    public let estimatedMinutes: Int?
    public let missingTracks: Int
    /// ISO 8601 instants, like ``VenueAppearance/startsAt``.
    public let projectedStartsAt: String?
    public let projectedEndsAt: String?
    /// How far its projected start is from its set time (negative: early).
    public let lateMinutes: Int?
    /// Whether it stretches or shrinks to keep the schedule (intermissions do by default).
    public let flexible: Bool
    public let minMinutes: Int?
    public let extraMinutes: Int?
    public let triviaSet: TriviaSet?
    /// ROOM or HOST.
    public let triviaDriver: String?
    /// EACH or END.
    public let triviaReveal: String?
    public let scenes: [Scene]
    /// The lineup model's: where a break, or an act's scenes, go when they end; nil follows the lineup.
    public let endsTo: ShowEndsTo?

    private enum CodingKeys: String, CodingKey {
        case id, activity, curtainCallMinutes, durationMinutes, estimatedMinutes, missingTracks, projectedStartsAt
        case projectedEndsAt, lateMinutes, flexible, minMinutes, extraMinutes, triviaSet, triviaDriver, triviaReveal, scenes
        case endsTo
        case kind = "entryKind"
    }

    public init(id: String, kind: Kind = .act, activity: Activity? = nil, curtainCallMinutes: Int? = nil,
                durationMinutes: Int? = nil, estimatedMinutes: Int? = nil, missingTracks: Int = 0,
                projectedStartsAt: String? = nil, projectedEndsAt: String? = nil, lateMinutes: Int? = nil,
                flexible: Bool = false, minMinutes: Int? = nil, extraMinutes: Int? = nil, triviaSet: TriviaSet? = nil,
                triviaDriver: String? = nil, triviaReveal: String? = nil, scenes: [Scene] = [], endsTo: ShowEndsTo? = nil) {
        self.id = id; self.kind = kind; self.activity = activity; self.curtainCallMinutes = curtainCallMinutes
        self.durationMinutes = durationMinutes; self.estimatedMinutes = estimatedMinutes; self.missingTracks = missingTracks
        self.projectedStartsAt = projectedStartsAt; self.projectedEndsAt = projectedEndsAt; self.lateMinutes = lateMinutes
        self.flexible = flexible; self.minMinutes = minMinutes; self.extraMinutes = extraMinutes; self.triviaSet = triviaSet
        self.triviaDriver = triviaDriver; self.triviaReveal = triviaReveal; self.scenes = scenes; self.endsTo = endsTo
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decode(String.self, forKey: .id),
                  kind: try c.decodeIfPresent(Kind.self, forKey: .kind) ?? .act,
                  activity: try c.decodeIfPresent(Activity.self, forKey: .activity),
                  curtainCallMinutes: try c.decodeIfPresent(Int.self, forKey: .curtainCallMinutes),
                  durationMinutes: try c.decodeIfPresent(Int.self, forKey: .durationMinutes),
                  estimatedMinutes: try c.decodeIfPresent(Int.self, forKey: .estimatedMinutes),
                  missingTracks: try c.decodeIfPresent(Int.self, forKey: .missingTracks) ?? 0,
                  projectedStartsAt: try c.decodeIfPresent(String.self, forKey: .projectedStartsAt),
                  projectedEndsAt: try c.decodeIfPresent(String.self, forKey: .projectedEndsAt),
                  lateMinutes: try c.decodeIfPresent(Int.self, forKey: .lateMinutes),
                  flexible: try c.decodeIfPresent(Bool.self, forKey: .flexible) ?? false,
                  minMinutes: try c.decodeIfPresent(Int.self, forKey: .minMinutes),
                  extraMinutes: try c.decodeIfPresent(Int.self, forKey: .extraMinutes),
                  triviaSet: try? c.decodeIfPresent(TriviaSet.self, forKey: .triviaSet),
                  triviaDriver: try c.decodeIfPresent(String.self, forKey: .triviaDriver),
                  triviaReveal: try c.decodeIfPresent(String.self, forKey: .triviaReveal),
                  scenes: try c.decodeIfPresent([Scene].self, forKey: .scenes) ?? [],
                  endsTo: try c.decodeIfPresent(ShowEndsTo.self, forKey: .endsTo))
    }

    public var isSegment: Bool { kind == .segment }
    public var runsTrivia: Bool { activity == .trivia }
    public var hasCurtainCall: Bool { curtainCallMinutes != nil }
}

/// A curtain call's go/no-go (the places check): who it waits on and how they stand.
public struct GoNoGo: Decodable, Sendable, Hashable {
    public struct Verdict: RawRepresentable, Codable, Sendable, Hashable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let go = Verdict(rawValue: "GO")
        public static let noGo = Verdict(rawValue: "NO_GO")
        public static let pending = Verdict(rawValue: "PENDING")
    }

    public struct Area: RawRepresentable, Codable, Sendable, Hashable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let venue = Area(rawValue: "VENUE")
        public static let talent = Area(rawValue: "TALENT")
        public static let staff = Area(rawValue: "STAFF")
    }

    public struct State: RawRepresentable, Codable, Sendable, Hashable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let ready = State(rawValue: "READY")
        public static let notReady = State(rawValue: "NOT_READY")
        /// The venue or the hosts said go without their own answer; counts as ready.
        public static let overridden = State(rawValue: "OVERRIDDEN")
        public static let pending = State(rawValue: "PENDING")
        public var isReady: Bool { self == .ready || self == .overridden }
    }

    /// One answer it waits on: the venue, a performer, or someone on the support staff.
    public struct Item: Decodable, Sendable, Hashable, Identifiable {
        public struct Staff: Decodable, Sendable, Hashable { public let id: String; public let name: String?; public let label: String?; public let mine: Bool? }
        public let id: String
        public let area: Area
        public let state: State
        public let note: String?
        public let person: VenueEvent.Person?
        public let staffAssignment: Staff?

        public init(id: String, area: Area, state: State, note: String? = nil, person: VenueEvent.Person? = nil,
                    staffAssignment: Staff? = nil) {
            self.id = id; self.area = area; self.state = state; self.note = note; self.person = person
            self.staffAssignment = staffAssignment
        }

        /// "The venue", a performer's name, or "Rick Mark · Photography".
        public var displayName: String {
            if area == .venue { return "The venue" }
            if let person { return person.name ?? "Someone" }
            if let staffAssignment {
                return [staffAssignment.name, staffAssignment.label].compactMap { $0 }.joined(separator: " · ")
            }
            return "Someone"
        }
    }

    public struct Count: Decodable, Sendable, Hashable { public let area: Area; public let ready: Int; public let total: Int }

    public struct CurtainCall: Decodable, Sendable, Hashable { public let id: String; public let title: String? }

    public let verdict: Verdict
    /// The act the curtain rises on.
    public let curtainCall: CurtainCall
    public let items: [Item]
    public let counts: [Count]

    public init(verdict: Verdict, curtainCall: CurtainCall, items: [Item], counts: [Count] = []) {
        self.verdict = verdict; self.curtainCall = curtainCall; self.items = items; self.counts = counts
    }

    /// Those not ready yet: said not ready, or haven't answered.
    public var holdouts: [Item] { items.filter { !$0.state.isReady } }
}

/// Someone working a show who isn't on the lineup: person X in role Y.
public struct SupportStaff: Decodable, Sendable, Hashable, Identifiable {
    public struct Role: RawRepresentable, Codable, Sendable, Hashable, CaseIterable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let photography = Role(rawValue: "PHOTOGRAPHY")
        public static let video = Role(rawValue: "VIDEO")
        public static let sound = Role(rawValue: "SOUND")
        public static let lighting = Role(rawValue: "LIGHTING")
        public static let stageManager = Role(rawValue: "STAGE_MANAGER")
        public static let door = Role(rawValue: "DOOR")
        public static let security = Role(rawValue: "SECURITY")
        public static let bar = Role(rawValue: "BAR")
        public static let runner = Role(rawValue: "RUNNER")
        public static let other = Role(rawValue: "OTHER")
        public static let allCases: [Role] = [.photography, .video, .sound, .lighting, .stageManager, .door, .security,
                                              .bar, .runner, .other]
        /// "Photography", "Stage manager".
        public var label: String { rawValue.replacingOccurrences(of: "_", with: " ").lowercased().capitalizingFirst }
    }

    public let id: String
    public let name: String?
    /// Their role to show: their title, else the role.
    public let label: String
    public let role: Role
    public let title: String?
    /// Whether a curtain call waits for them.
    public let required: Bool
    public let callAt: String?
    /// Whether it's the signed-in user.
    public let mine: Bool
    public let person: VenueEvent.Person?
    /// The zone lineup they work (the lineup model); nil for every zone, or from an API without zones.
    public let lineup: LineupRef?
    public struct LineupRef: Decodable, Sendable, Hashable { public let id: String }

    public init(id: String, name: String?, label: String, role: Role, title: String? = nil, required: Bool = true,
                callAt: String? = nil, mine: Bool = false, person: VenueEvent.Person? = nil, lineupID: String? = nil) {
        self.id = id; self.name = name; self.label = label; self.role = role; self.title = title
        self.required = required; self.callAt = callAt; self.mine = mine; self.person = person
        self.lineup = lineupID.map(LineupRef.init(id:))
    }

    public var lineupID: String? { lineup?.id }
}

extension String {
    var capitalizingFirst: String { prefix(1).uppercased() + dropFirst() }
}

/// A round of group trivia, as the host and the venue see it.
public struct StaffTriviaRound: Decodable, Sendable, Hashable, Identifiable {
    public struct Choice: Decodable, Sendable, Hashable { public let label: String; public let count: Int }
    public let id: String
    public let statement: String
    public let choices: [Choice]
    public let voting: Bool
    public let closesAt: String?
    /// ROOM or HOST.
    public let driver: String
    public let answer: String?
    public let roomCall: String?
    public let revealsAtEnd: Bool
    public let revealedAt: String?

    public init(id: String, statement: String, choices: [Choice], voting: Bool, closesAt: String? = nil,
                driver: String = "HOST", answer: String? = nil, roomCall: String? = nil, revealsAtEnd: Bool = false,
                revealedAt: String? = nil) {
        self.id = id; self.statement = statement; self.choices = choices; self.voting = voting; self.closesAt = closesAt
        self.driver = driver; self.answer = answer; self.roomCall = roomCall; self.revealsAtEnd = revealsAtEnd
        self.revealedAt = revealedAt
    }

    public var isRevealed: Bool { revealedAt != nil }
    /// "Myth or Legend?"
    public var question: String { choices.map(\.label).joined(separator: " or ") + "?" }
    public var totalVotes: Int { choices.reduce(0) { $0 + $1.count } }
}

/// What the lineup editor sets on an entry beyond show control (the API's lineup model, 2026-10-24): an act's notes
/// (Markdown), its own preshow, a flex break's longest, and its scenes' setup and post time with short notes. It's
/// fetched apart from show control, so an API without it only leaves these settings out.
public struct ShowEntryDetails: Decodable, Sendable, Hashable, Identifiable {
    public struct Scene: Decodable, Sendable, Hashable, Identifiable {
        public let id: String
        /// Time before it to set the stage; nil for none.
        public let setupSeconds: Int?
        /// What the setup is: "Bring out the cardboard castle".
        public let setupNote: String?
        /// Time after it before the next; nil for the default (2 minutes).
        public let gapSeconds: Int?
        /// What the time after it is for: "Tear the castle down".
        public let gapNote: String?
        /// Notes for the booth: "Haze cue on the second chorus".
        public let note: String?

        public init(id: String, setupSeconds: Int? = nil, setupNote: String? = nil, gapSeconds: Int? = nil,
                    gapNote: String? = nil, note: String? = nil) {
            self.id = id; self.setupSeconds = setupSeconds; self.setupNote = setupNote; self.gapSeconds = gapSeconds
            self.gapNote = gapNote; self.note = note
        }
    }

    public let id: String
    public let notes: String?
    /// An act: its own preshow before it, from doors to the host, in minutes.
    public let preshowMinutes: Int?
    /// A flexing entry: the longest it stretches to, in minutes; nil for no limit.
    public let maxMinutes: Int?
    public let scenes: [Scene]

    public init(id: String, notes: String? = nil, preshowMinutes: Int? = nil, maxMinutes: Int? = nil, scenes: [Scene] = []) {
        self.id = id; self.notes = notes; self.preshowMinutes = preshowMinutes; self.maxMinutes = maxMinutes; self.scenes = scenes
    }

    public func scene(_ id: String) -> Scene? { scenes.first { $0.id == id } }
}

/// A venue night's show control: its entries, the next curtain call's places check, its support staff, and its trivia.
public struct VenueShowControl: Sendable, Hashable {
    /// In running order, like ``VenueNight/runningOrder``.
    public let entries: [ShowLineupEntry]
    /// The next curtain call's places check, for people working the show; nil when none is coming.
    public let goNoGo: GoNoGo?
    public let supportStaff: [SupportStaff]
    /// Tonight's latest trivia round.
    public let trivia: StaffTriviaRound?
    /// The entry running trivia now, if any.
    public let triviaSegmentID: String?
    /// The trivia sets a segment can run, those suiting the venue first.
    public let triviaSets: [ShowLineupEntry.TriviaSet]
    /// The editor's settings on each entry, by ID; nil on an API without them.
    public var details: [String: ShowEntryDetails]?
    /// Whether the API has the editor's settings, so the entry editors show and send them.
    public var hasDetails: Bool { details != nil }

    public init(entries: [ShowLineupEntry] = [], goNoGo: GoNoGo? = nil, supportStaff: [SupportStaff] = [],
                trivia: StaffTriviaRound? = nil, triviaSegmentID: String? = nil, triviaSets: [ShowLineupEntry.TriviaSet] = [],
                details: [String: ShowEntryDetails]? = nil) {
        self.entries = entries; self.goNoGo = goNoGo; self.supportStaff = supportStaff; self.trivia = trivia
        self.triviaSegmentID = triviaSegmentID; self.triviaSets = triviaSets; self.details = details
    }

    public func entry(_ id: String) -> ShowLineupEntry? { entries.first { $0.id == id } }
}

/// Whether advancing failed because a curtain call's places check isn't GO: the venue can go anyway (`force`).
public func isNotEveryoneReady(_ error: any Error) -> Bool {
    guard let error = error as? AudienceKitError else { return false }
    return error.errors.contains { $0.extensions?["verdict"] != nil }
}

extension VenueManagementClient {
    static let showEntryFields = "id entryKind activity curtainCallMinutes durationMinutes estimatedMinutes missingTracks projectedStartsAt projectedEndsAt lateMinutes flexible minMinutes extraMinutes triviaSet { key title } triviaDriver triviaReveal scenes { id title seconds gapSeconds lengthSeconds performer { id name avatarUrl } track { id name } }"
    static let goNoGoFields = "verdict curtainCall { id title } items { id area state note person { id name avatarUrl } staffAssignment { id name label mine } } counts { area ready total }"
    static let supportStaffFields = "id name label role title required callAt mine person { id name avatarUrl }"
    static let showDetailsFields = "id notes preshowMinutes maxMinutes scenes { id setupSeconds setupNote gapSeconds gapNote note }"
    static let triviaRoundFields = "id statement choices { label count } voting closesAt driver answer roomCall revealsAtEnd revealedAt"

    /// A venue night's show control (tonight when nil, as "yyyy-MM-dd" otherwise).
    public func showControl(venueID: String, night: String? = nil) async throws -> VenueShowControl {
        struct People: Decodable, Sendable {
            let runningOrder: GraphQLNodes<ShowLineupEntry>
            let goNoGo: GoNoGo?
            let supportStaff: [SupportStaff]?
        }
        struct Ref: Decodable, Sendable { let id: String }
        struct Trivia: Decodable, Sendable {
            let current: StaffTriviaRound?
            let segment: Ref?
            let sets: [ShowLineupEntry.TriviaSet]?
        }
        struct Venue: Decodable, Sendable { let people: People; let trivia: Trivia? }
        struct Venues: Decodable, Sendable { let venue: Venue? }
        struct Response: Decodable, Sendable { let venues: Venues }
        let response = try await session.graphQL("""
            query StaffShowControl($id: ID!, $night: ISO8601Date) {
              venues {
                venue(id: $id) {
                  people {
                    runningOrder(night: $night) { nodes { \(Self.showEntryFields) } }
                    goNoGo { \(Self.goNoGoFields) }
                    supportStaff(night: $night) { \(Self.supportStaffFields) }
                  }
                  trivia { current { \(Self.triviaRoundFields) } segment { id } sets { key title } }
                }
              }
            }
            """, variables: ["id": .string(venueID), "night": night.map(GraphQLValue.string) ?? .null], as: Response.self)
        guard let venue = response.venues.venue else { throw AudienceKitError.notFound }
        return VenueShowControl(entries: venue.people.runningOrder.nodes, goNoGo: venue.people.goNoGo,
                                supportStaff: venue.people.supportStaff ?? [], trivia: venue.trivia?.current,
                                triviaSegmentID: venue.trivia?.segment?.id, triviaSets: venue.trivia?.sets ?? [],
                                details: try? await showDetails(venueID: venueID, night: night))
    }

    /// A venue night's entries' editor settings, by ID. Throws on an API without them (older than the lineup model).
    public func showDetails(venueID: String, night: String? = nil) async throws -> [String: ShowEntryDetails] {
        struct People: Decodable, Sendable { let runningOrder: GraphQLNodes<ShowEntryDetails> }
        struct Venue: Decodable, Sendable { let people: People }
        struct Venues: Decodable, Sendable { let venue: Venue? }
        struct Response: Decodable, Sendable { let venues: Venues }
        let response = try await session.graphQL("""
            query StaffShowDetails($id: ID!, $night: ISO8601Date) {
              venues { venue(id: $id) { people { runningOrder(night: $night) { nodes { \(Self.showDetailsFields) } } } } }
            }
            """, variables: ["id": .string(venueID), "night": night.map(GraphQLValue.string) ?? .null], as: Response.self)
        guard let venue = response.venues.venue else { throw AudienceKitError.notFound }
        return Dictionary(venue.people.runningOrder.nodes.map { ($0.id, $0) }) { first, _ in first }
    }

    /// An event's lineup's entries' editor settings, by ID; throws on an API without them.
    public func eventShowDetails(eventID: String) async throws -> [String: ShowEntryDetails] {
        struct People: Decodable, Sendable { let runningOrder: GraphQLNodes<ShowEntryDetails> }
        struct Event: Decodable, Sendable { let people: People }
        struct Events: Decodable, Sendable { let event: Event? }
        struct Response: Decodable, Sendable { let events: Events }
        let response = try await session.graphQL("""
            query StaffEventShowDetails($id: ID!) {
              events { event(id: $id) { people { runningOrder { nodes { \(Self.showDetailsFields) } } } } }
            }
            """, variables: ["id": .string(eventID)], as: Response.self)
        guard let event = response.events.event else { throw AudienceKitError.notFound }
        return Dictionary(event.people.runningOrder.nodes.map { ($0.id, $0) }) { first, _ in first }
    }

    /// An event's lineup's show control, built ahead: its entries and its support staff.
    public func eventShowControl(eventID: String) async throws -> VenueShowControl {
        struct People: Decodable, Sendable { let runningOrder: GraphQLNodes<ShowLineupEntry>; let supportStaff: [SupportStaff]? }
        struct Event: Decodable, Sendable { let people: People }
        struct Events: Decodable, Sendable { let event: Event? }
        struct Response: Decodable, Sendable { let events: Events }
        let response = try await session.graphQL("""
            query StaffEventShowControl($id: ID!) {
              events {
                event(id: $id) {
                  people { runningOrder { nodes { \(Self.showEntryFields) } } supportStaff { \(Self.supportStaffFields) } }
                }
              }
            }
            """, variables: ["id": .string(eventID)], as: Response.self)
        guard let event = response.events.event else { throw AudienceKitError.notFound }
        return VenueShowControl(entries: event.people.runningOrder.nodes, supportStaff: event.people.supportStaff ?? [],
                                details: try? await eventShowDetails(eventID: eventID))
    }

    /// Answers a curtain call's places check: the venue (no one named), a performer (`personID`) or someone on the
    /// support staff (`staffAssignmentID`). OVERRIDDEN, for the venue and the hosts only, says go for a holdout.
    @discardableResult
    public func setReadiness(curtainCallID: String, area: GoNoGo.Area, personID: String? = nil,
                             staffAssignmentID: String? = nil, state: GoNoGo.State, note: String? = nil) async throws -> GoNoGo {
        struct Payload: Decodable, Sendable { let goNoGo: GoNoGo }
        struct Response: Decodable, Sendable { let setReadiness: Payload }
        var input: [String: GraphQLValue] = ["curtainCallId": .string(curtainCallID), "area": .string(area.rawValue),
                                             "state": .string(state.rawValue)]
        if let personID { input["personId"] = .string(personID) }
        if let staffAssignmentID { input["staffAssignmentId"] = .string(staffAssignmentID) }
        if let note, !note.isEmpty { input["note"] = .string(note) }
        let response = try await session.graphQL("""
            mutation StaffReadinessSet($input: ReadinessSetInput!) { setReadiness(input: $input) { goNoGo { \(Self.goNoGoFields) } } }
            """, variables: ["input": .object(input)], as: Response.self)
        return response.setReadiness.goNoGo
    }

    /// Advances like ``advanceLineup(venueID:eventID:back:)``, raising the curtain even though its places check isn't
    /// GO (go anyway).
    public func advanceLineupAnyway(venueID: String, eventID: String? = nil) async throws -> LineupAdvance {
        struct Response: Decodable, Sendable { let advanceLineup: LineupAdvance? }
        let response = try await session.graphQL("""
            mutation StaffLineupGoAnyway($input: LineupAdvanceInput!) {
              advanceLineup(input: $input) {
                onStage { \(Self.appearanceFields) } upNext { \(Self.appearanceFields) } runningOrder { \(Self.appearanceFields) }
              }
            }
            """, variables: ["input": .object(["venueId": .string(venueID), "eventId": eventID.map(GraphQLValue.string) ?? .null,
                                               "force": .bool(true)])], as: Response.self)
        guard let advance = response.advanceLineup else { throw AudienceKitError.decoding("The advance was missing") }
        return advance
    }

    /// Puts someone on a show's support staff: a listing (`personID`), a member (`userID`) or just a `name`. On the
    /// venue night's own show, or with `eventID` the event's.
    @discardableResult
    public func addSupportStaff(venueID: String, night: String? = nil, eventID: String? = nil, personID: String? = nil,
                                userID: String? = nil, name: String? = nil, role: SupportStaff.Role, title: String? = nil,
                                required: Bool = true, lineupID: String? = nil) async throws -> SupportStaff {
        struct Payload: Decodable, Sendable { let staffAssignment: SupportStaff }
        struct Response: Decodable, Sendable { let createStaffAssignment: Payload }
        var staff: [String: GraphQLValue] = ["role": .string(role.rawValue), "required": .bool(required)]
        if let night { staff["night"] = .string(night) }
        if let eventID { staff["eventId"] = .string(eventID) }
        if let personID { staff["personId"] = .string(personID) }
        if let userID { staff["userId"] = .string(userID) }
        if let name, !name.isEmpty { staff["name"] = .string(name) }
        if let title, !title.isEmpty { staff["title"] = .string(title) }
        if let lineupID { staff["lineupId"] = .string(lineupID) }
        let response = try await session.graphQL("""
            mutation StaffSupportStaffAdd($venueId: ID!, $staff: StaffAssignmentInput!) {
              createStaffAssignment(input: { venueId: $venueId, staff: $staff }) { staffAssignment { \(Self.supportStaffFields) } }
            }
            """, variables: ["venueId": .string(venueID), "staff": .object(staff)], as: Response.self)
        return response.createStaffAssignment.staffAssignment
    }

    public func removeSupportStaff(id: String) async throws {
        struct Response: Decodable, Sendable { let deleteStaffAssignment: GraphQLValue? }
        _ = try await session.graphQL("""
            mutation StaffSupportStaffRemove($id: ID!) { deleteStaffAssignment(input: { id: $id }) { clientMutationId } }
            """, variables: ["id": .string(id)], as: Response.self)
    }

    /// Puts the trivia segment's next item to the room, as a card in the venue's chat.
    @discardableResult
    public func openTriviaRound(venueID: String) async throws -> StaffTriviaRound {
        struct Payload: Decodable, Sendable { let round: StaffTriviaRound }
        struct Response: Decodable, Sendable { let openTriviaRound: Payload }
        let response = try await session.graphQL("""
            mutation StaffTriviaOpen($venueId: ID!) { openTriviaRound(input: { venueId: $venueId }) { round { \(Self.triviaRoundFields) } } }
            """, variables: ["venueId": .string(venueID)], as: Response.self)
        return response.openTriviaRound.round
    }

    /// Takes the room's call and shows the answer; on a segment that holds answers to its end, closes voting instead.
    @discardableResult
    public func revealTriviaRound(id: String) async throws -> StaffTriviaRound {
        struct Payload: Decodable, Sendable { let round: StaffTriviaRound }
        struct Response: Decodable, Sendable { let revealTriviaRound: Payload }
        let response = try await session.graphQL("""
            mutation StaffTriviaReveal($id: ID!) { revealTriviaRound(input: { id: $id }) { round { \(Self.triviaRoundFields) } } }
            """, variables: ["id": .string(id)], as: Response.self)
        return response.revealTriviaRound.round
    }
}

extension ShowLineupEntry {
    public var projectedStart: Date? { parseInstant(projectedStartsAt) }
    public var projectedEnd: Date? { parseInstant(projectedEndsAt) }
    /// How long it's expected to run: as set, else estimated from its scenes.
    public var expectedMinutes: Int? { durationMinutes ?? estimatedMinutes }
}

/// The show settings on a lineup entry, as its editor changes them: what kind it is, its curtain call, how long it
/// runs, its activity and trivia, whether it flexes, and its scenes. ``fields(from:)`` gives the appearance input that
/// makes the change, for ``VenueManagementClient/addLineupEntry(venueID:fields:)`` or
/// ``VenueManagementClient/updateAppearance(id:fields:)``.
public struct ShowEntryDraft: Sendable, Hashable {
    /// One number in an act. A scene keeps its performer and track (set in the back-of-house room) as they were.
    public struct Scene: Sendable, Hashable, Identifiable {
        public let id: String
        /// Whether it's one of the act's saved scenes (rather than one added here), so it's changed in place.
        public let saved: Bool
        public var title: String
        /// Its length as set; nil reads it from its track.
        public var seconds: Int?
        public var performerID: String?
        public var trackID: String?
        /// Its track's length, when it has one, for showing beside an unset length.
        public var trackSeconds: Int?
        /// Setup time before it, its note, post time after it, its note, and notes for the booth (``ShowEntryDetails``).
        public var setupSeconds: Int?
        public var setupNote: String
        public var gapSeconds: Int?
        public var gapNote: String
        public var note: String
        /// The lineup model's (``ShowEntryDraft/zoned``): everyone in it (none: the act's people), and where it goes
        /// when it ends (nil: the act's or lineup's setting).
        public var performers: [VenueEvent.Person]
        public var endsTo: ShowEndsTo?

        public init(id: String = UUID().uuidString, saved: Bool = false, title: String = "", seconds: Int? = nil,
                    performerID: String? = nil, trackID: String? = nil, trackSeconds: Int? = nil, setupSeconds: Int? = nil,
                    setupNote: String = "", gapSeconds: Int? = nil, gapNote: String = "", note: String = "",
                    performers: [VenueEvent.Person] = [], endsTo: ShowEndsTo? = nil) {
            self.id = id; self.saved = saved; self.title = title; self.seconds = seconds; self.performerID = performerID
            self.trackID = trackID; self.trackSeconds = trackSeconds; self.setupSeconds = setupSeconds
            self.setupNote = setupNote; self.gapSeconds = gapSeconds; self.gapNote = gapNote; self.note = note
            self.performers = performers; self.endsTo = endsTo
        }

        init(_ scene: ShowLineupEntry.Scene, details: ShowEntryDetails.Scene?) {
            let length = scene.seconds == nil ? scene.lengthSeconds : nil
            self.init(id: scene.id, saved: true, title: scene.title ?? "", seconds: scene.seconds, performerID: scene.performer?.id,
                      trackID: scene.track?.id, trackSeconds: length, setupSeconds: details?.setupSeconds,
                      setupNote: details?.setupNote ?? "", gapSeconds: details?.gapSeconds ?? scene.gapSeconds,
                      gapNote: details?.gapNote ?? "", note: details?.note ?? "", performers: scene.people, endsTo: scene.endsTo)
        }

        /// Its scene input. With `detailed` (an API with the lineup model) a saved scene names its ID, so it's
        /// changed in place, and every setting goes (null clears it); otherwise the act's scenes are replaced. With
        /// `zoned` (read from the zone lineups) its performers and where it ends go too.
        func input(detailed: Bool, zoned: Bool = false) -> GraphQLValue {
            var input: [String: GraphQLValue] = [:]
            let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty { input["title"] = .string(title) }
            if let seconds { input["seconds"] = .int(seconds) }
            if zoned {
                input["performerIds"] = .array(performers.map { .string($0.id) })
                input["performerId"] = performers.first.map { .string($0.id) } ?? .null
                input["endsTo"] = endsTo.map { .string($0.rawValue) } ?? .null
            } else if let performerID { input["performerId"] = .string(performerID) }
            if let trackID { input["trackId"] = .string(trackID) }
            guard detailed else { return .object(input) }
            if saved { input["id"] = .string(id) }
            if title.isEmpty { input["title"] = .null }
            if seconds == nil { input["seconds"] = .null }
            input["setupSeconds"] = setupSeconds.map(GraphQLValue.int) ?? .null
            input["gapSeconds"] = gapSeconds.map(GraphQLValue.int) ?? .null
            for (key, text) in [("setupNote", setupNote), ("gapNote", gapNote), ("note", note)] {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                input[key] = trimmed.isEmpty ? .null : .string(trimmed)
            }
            return .object(input)
        }
    }

    public var kind: ShowLineupEntry.Kind
    /// Minutes before an act that places is called; nil for no curtain call.
    public var curtainCallMinutes: Int?
    /// How long it runs as set; nil estimates it (an act from its scenes).
    public var durationMinutes: Int?
    public var activity: ShowLineupEntry.Activity?
    /// The trivia set's key; nil picks one by the event's or venue's tags.
    public var triviaSet: String?
    /// Whether trivia answers wait for the segment's end (END) rather than show after each round (EACH).
    public var revealAtEnd: Bool
    /// Whether it stretches or shrinks to keep the schedule.
    public var flexible: Bool
    public var scenes: [Scene]
    /// Whether the API takes the editor's settings below (``VenueShowControl/hasDetails``).
    public var detailed: Bool
    /// Notes for the crew, in Markdown.
    public var notes: String
    /// An act's own preshow before it, in minutes; nil for none.
    public var preshowMinutes: Int?
    /// A flexing entry's shortest and longest, in minutes; nil for the default (5) and no limit.
    public var minMinutes: Int?
    public var maxMinutes: Int?
    /// Minutes an act takes beyond its scenes (hosting, changes); nil for the venue's default.
    public var extraMinutes: Int?
    /// Whether it was read from the zone lineups (the lineup model), so scenes' performers and where scenes and breaks
    /// go when they end are shown and sent.
    public var zoned: Bool
    /// Where a break, or an act's scenes, go when they end; nil follows the lineup (``zoned`` only).
    public var endsTo: ShowEndsTo?

    public init(kind: ShowLineupEntry.Kind = .act, curtainCallMinutes: Int? = nil, durationMinutes: Int? = nil,
                activity: ShowLineupEntry.Activity? = nil, triviaSet: String? = nil, revealAtEnd: Bool = false,
                flexible: Bool? = nil, scenes: [Scene] = [], detailed: Bool = false, notes: String = "",
                preshowMinutes: Int? = nil, minMinutes: Int? = nil, maxMinutes: Int? = nil, extraMinutes: Int? = nil,
                zoned: Bool = false, endsTo: ShowEndsTo? = nil) {
        self.kind = kind; self.curtainCallMinutes = curtainCallMinutes; self.durationMinutes = durationMinutes
        self.activity = activity; self.triviaSet = triviaSet; self.revealAtEnd = revealAtEnd
        self.flexible = flexible ?? Self.flexes(kind); self.scenes = scenes; self.detailed = detailed || zoned
        self.notes = notes; self.preshowMinutes = preshowMinutes; self.minMinutes = minMinutes; self.maxMinutes = maxMinutes
        self.extraMinutes = extraMinutes; self.zoned = zoned; self.endsTo = endsTo
    }

    /// `details`: the entry's editor settings, when the API has them (``VenueShowControl/details``).
    public init(_ entry: ShowLineupEntry, details: ShowEntryDetails? = nil, detailed: Bool = false, zoned: Bool = false) {
        self.init(kind: entry.kind, curtainCallMinutes: entry.curtainCallMinutes, durationMinutes: entry.durationMinutes,
                  activity: entry.activity, triviaSet: entry.triviaSet?.key, revealAtEnd: entry.triviaReveal == "END",
                  flexible: entry.flexible, scenes: entry.scenes.map { Scene($0, details: details?.scene($0.id)) },
                  detailed: detailed || details != nil, notes: details?.notes ?? "", preshowMinutes: details?.preshowMinutes,
                  minMinutes: entry.minMinutes, maxMinutes: details?.maxMinutes, extraMinutes: entry.extraMinutes, zoned: zoned,
                  endsTo: entry.endsTo)
    }

    /// Intermissions flex by default; acts and segments keep their time.
    public static func flexes(_ kind: ShowLineupEntry.Kind) -> Bool { kind == .intermission }

    public var isAct: Bool { kind == .act }
    /// Whether it can run an activity in the chat: segments and intermissions.
    public var hasActivity: Bool { kind != .act }

    /// The scenes' set lengths (or their tracks'), in minutes, rounded up; nil when none has a length.
    public var scenesMinutes: Int? {
        let seconds = scenes.compactMap { $0.seconds ?? $0.trackSeconds }
        guard !seconds.isEmpty else { return nil }
        return (seconds.reduce(0, +) + 59) / 60
    }

    /// The appearance input fields that turn `original` into this draft; every setting that isn't the default when
    /// `original` is nil (a new entry).
    public func fields(from original: ShowLineupEntry?, details: ShowEntryDetails? = nil) -> [String: GraphQLValue] {
        let before = original.map { ShowEntryDraft($0, details: details, detailed: detailed, zoned: zoned) }
            ?? ShowEntryDraft(detailed: detailed, zoned: zoned)
        var fields: [String: GraphQLValue] = [:]
        if kind != (original?.kind ?? .act) { fields["kind"] = .string(kind.rawValue) }
        let curtain = isAct ? curtainCallMinutes : nil
        if curtain != before.curtainCallMinutes { fields["curtainCallMinutes"] = curtain.map(GraphQLValue.int) ?? .null }
        if durationMinutes != before.durationMinutes { fields["durationMinutes"] = durationMinutes.map(GraphQLValue.int) ?? .null }
        let activity = hasActivity ? activity : nil
        if activity != before.activity { fields["activity"] = activity.map { .string($0.rawValue) } ?? .null }
        if activity == .trivia {
            if triviaSet != before.triviaSet { fields["triviaSet"] = triviaSet.map(GraphQLValue.string) ?? .null }
            if revealAtEnd != before.revealAtEnd || original == nil { fields["triviaReveal"] = .string(revealAtEnd ? "END" : "EACH") }
        }
        if original == nil ? flexible != Self.flexes(kind) : flexible != before.flexible { fields["flexible"] = .bool(flexible) }
        let scenes = isAct ? scenes : []
        let inputs = scenes.map { $0.input(detailed: detailed, zoned: zoned) }
        if inputs != before.scenes.map({ $0.input(detailed: detailed, zoned: zoned) }) { fields["scenes"] = .array(inputs) }
        if zoned && endsTo != before.endsTo { fields["endsTo"] = endsTo.map { .string($0.rawValue) } ?? .null }
        guard detailed else { return fields }
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed != before.notes.trimmingCharacters(in: .whitespacesAndNewlines) { fields["notes"] = trimmed.isEmpty ? .null : .string(trimmed) }
        let preshow = isAct ? preshowMinutes : nil
        if preshow != before.preshowMinutes { fields["preshowMinutes"] = preshow.map(GraphQLValue.int) ?? .null }
        let (least, most) = flexible ? (minMinutes, maxMinutes) : (before.minMinutes, before.maxMinutes)
        if least != before.minMinutes { fields["minMinutes"] = least.map(GraphQLValue.int) ?? .null }
        if most != before.maxMinutes { fields["maxMinutes"] = most.map(GraphQLValue.int) ?? .null }
        let extra = isAct ? extraMinutes : before.extraMinutes
        if extra != before.extraMinutes { fields["extraMinutes"] = extra.map(GraphQLValue.int) ?? .null }
        return fields
    }
}
