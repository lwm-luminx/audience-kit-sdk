import AudienceCore
import Foundation

// Show control (the API's doc/SHOW_CONTROL.md): the parts of a venue's show its guests see. Entries are acts,
// intermissions or segments (a generic time block, e.g. "Photos with cast"); a segment or intermission can run an
// activity in the venue's chat, such as group trivia. An act is a set of scenes (one per number), and the running order
// projects when each entry is on, moved out when the show runs late. An act can have a curtain call; guests see only how
// many are ready, never who.
//
// It's fetched apart from ``AudienceSession/lineup(venueID:)`` so an API without show control (older than its
// 2026-10-22 release) only fails this call: apps show the lineup as before and leave these parts out.

/// One number in an act: drag sets are an act of several performances, each maybe by one of its performers.
public struct ShowScene: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    /// The number, e.g. a song name.
    public let title: String?
    /// Who performs it, if one of the set (and shown to the viewer).
    public let performer: LineupEntry.Person?
    /// How long it runs, if known.
    public let lengthSeconds: Int?

    public init(id: String, title: String? = nil, performer: LineupEntry.Person? = nil, lengthSeconds: Int? = nil) {
        self.id = id
        self.title = title
        self.performer = performer
        self.lengthSeconds = lengthSeconds
    }
}

/// What show control knows about one lineup entry: its kind, its activity, its scenes and its projected times. Match it
/// to a ``LineupEntry`` by ``id``.
public struct ShowEntry: Decodable, Sendable, Hashable, Identifiable {
    /// An act, an intermission, or a segment (a generic time block with a title).
    public enum Kind: String, Codable, Sendable, Hashable {
        case act = "ACT", intermission = "INTERMISSION", segment = "SEGMENT", unknown

        public init(from decoder: any Decoder) throws {
            self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
        }
    }

    /// What runs in the venue's chat while a segment or intermission is on.
    public enum Activity: String, Codable, Sendable, Hashable {
        case trivia = "TRIVIA", prompts = "PROMPTS", unknown

        public init(from decoder: any Decoder) throws {
            self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
        }
    }

    public let id: String
    public let kind: Kind
    /// Nil for nothing.
    public let activity: Activity?
    /// An act the curtain rises on: places is called this many minutes before it.
    public let curtainCallMinutes: Int?
    /// How long it's expected to run, if anything says.
    public let estimatedMinutes: Int?
    /// When it's expected on: when it went on, its hard time, else moved out behind what ran late.
    public let projectedStartsAt: Date?
    /// When it's expected off.
    public let projectedEndsAt: Date?
    /// How many minutes after its set time it's projected to start (negative: early); nil without a set time.
    public let lateMinutes: Int?
    /// An act's numbers, in order.
    public let scenes: [ShowScene]

    public init(id: String, kind: Kind = .act, activity: Activity? = nil, curtainCallMinutes: Int? = nil,
                estimatedMinutes: Int? = nil, projectedStartsAt: Date? = nil, projectedEndsAt: Date? = nil,
                lateMinutes: Int? = nil, scenes: [ShowScene] = []) {
        self.id = id
        self.kind = kind
        self.activity = activity
        self.curtainCallMinutes = curtainCallMinutes
        self.estimatedMinutes = estimatedMinutes
        self.projectedStartsAt = projectedStartsAt
        self.projectedEndsAt = projectedEndsAt
        self.lateMinutes = lateMinutes
        self.scenes = scenes
    }

    private enum CodingKeys: String, CodingKey {
        case id, activity, curtainCallMinutes, estimatedMinutes, projectedStartsAt, projectedEndsAt, lateMinutes, scenes
        case kind = "entryKind"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        kind = try container.decodeIfPresent(Kind.self, forKey: .kind) ?? .act
        activity = try container.decodeIfPresent(Activity.self, forKey: .activity)
        curtainCallMinutes = try container.decodeIfPresent(Int.self, forKey: .curtainCallMinutes)
        estimatedMinutes = try container.decodeIfPresent(Int.self, forKey: .estimatedMinutes)
        projectedStartsAt = try container.decodeIfPresent(Date.self, forKey: .projectedStartsAt)
        projectedEndsAt = try container.decodeIfPresent(Date.self, forKey: .projectedEndsAt)
        lateMinutes = try container.decodeIfPresent(Int.self, forKey: .lateMinutes)
        scenes = try container.decodeIfPresent([ShowScene].self, forKey: .scenes) ?? []
    }

    /// Whether trivia runs in the chat while it's on.
    public var runsTrivia: Bool { activity == .trivia }
}

/// How a curtain call's go/no-go stands.
public enum GoNoGoVerdict: String, Codable, Sendable, Hashable {
    case go = "GO", noGo = "NO_GO", pending = "PENDING", unknown

    public init(from decoder: any Decoder) throws {
        self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
    }
}

/// How many of one area (the venue, the talent, the support staff) are ready for a curtain call. Counts only.
public struct ReadinessCount: Codable, Sendable, Hashable {
    /// Who the count is about.
    public enum Area: String, Codable, Sendable, Hashable {
        case venue = "VENUE", talent = "TALENT", staff = "STAFF", unknown

        public init(from decoder: any Decoder) throws {
            self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
        }
    }

    public let area: Area
    public let ready: Int
    public let total: Int

    public init(area: Area, ready: Int, total: Int) {
        self.area = area
        self.ready = ready
        self.total = total
    }
}

/// Tonight's next curtain call, as guests see it: which act it's for and how many are ready, by area.
public struct CurtainReadiness: Decodable, Sendable, Hashable {
    private struct Ref: Decodable, Sendable, Hashable { var id: String }

    /// The act the curtain rises on.
    public let actID: String
    public let verdict: GoNoGoVerdict
    public let counts: [ReadinessCount]

    public init(actID: String, verdict: GoNoGoVerdict, counts: [ReadinessCount]) {
        self.actID = actID
        self.verdict = verdict
        self.counts = counts
    }

    private enum CodingKeys: String, CodingKey { case act, verdict, counts }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        actID = try container.decode(Ref.self, forKey: .act).id
        verdict = try container.decodeIfPresent(GoNoGoVerdict.self, forKey: .verdict) ?? .unknown
        counts = try container.decodeIfPresent([ReadinessCount].self, forKey: .counts) ?? []
    }
}

/// One round of a venue's group trivia (Myth or Legend so far), posted as a card in its chat. The whole room talks it
/// over and votes together: there are only counts, never names, scores or winners. Once revealed it carries the answer
/// and the room's call; a segment can hold every answer until it ends (``revealsAtEnd``).
public struct TriviaRound: Decodable, Sendable, Hashable, Identifiable {
    /// A choice and how many picked it.
    public struct Choice: Codable, Sendable, Hashable, Identifiable {
        public let label: String
        public let count: Int
        public var id: String { label }

        public init(label: String, count: Int) {
            self.label = label
            self.count = count
        }
    }

    private struct Ref: Decodable, Sendable, Hashable { var id: String }

    public let id: String
    /// The statement to call, e.g. "RuPaul once fronted a punk band."
    public let statement: String
    public let choices: [Choice]
    /// The signed-in user's vote, if any.
    public let myChoice: String?
    /// Whether votes are taken now (they can change their vote until it closes).
    public let voting: Bool
    public let closesAt: Date?
    /// The right choice, once revealed.
    public let answer: String?
    /// The choice the room picked most, once revealed; nil when the room was split.
    public let roomCall: String?
    /// The story behind the answer, once revealed.
    public let reveal: String?
    /// Whether its answer waits for the end of the segment.
    public let revealsAtEnd: Bool
    public let revealedAt: Date?
    /// Its card in the venue's chat.
    public let messageID: String?

    public init(id: String, statement: String, choices: [Choice], myChoice: String? = nil, voting: Bool = true,
                closesAt: Date? = nil, answer: String? = nil, roomCall: String? = nil, reveal: String? = nil,
                revealsAtEnd: Bool = false, revealedAt: Date? = nil, messageID: String? = nil) {
        self.id = id
        self.statement = statement
        self.choices = choices
        self.myChoice = myChoice
        self.voting = voting
        self.closesAt = closesAt
        self.answer = answer
        self.roomCall = roomCall
        self.reveal = reveal
        self.revealsAtEnd = revealsAtEnd
        self.revealedAt = revealedAt
        self.messageID = messageID
    }

    private enum CodingKeys: String, CodingKey {
        case id, statement, choices, myChoice, voting, closesAt, answer, roomCall, reveal, revealsAtEnd, revealedAt
        case message
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        statement = try container.decode(String.self, forKey: .statement)
        choices = try container.decodeIfPresent([Choice].self, forKey: .choices) ?? []
        myChoice = try container.decodeIfPresent(String.self, forKey: .myChoice)
        voting = try container.decodeIfPresent(Bool.self, forKey: .voting) ?? false
        closesAt = try container.decodeIfPresent(Date.self, forKey: .closesAt)
        answer = try container.decodeIfPresent(String.self, forKey: .answer)
        roomCall = try container.decodeIfPresent(String.self, forKey: .roomCall)
        reveal = try container.decodeIfPresent(String.self, forKey: .reveal)
        revealsAtEnd = try container.decodeIfPresent(Bool.self, forKey: .revealsAtEnd) ?? false
        revealedAt = try container.decodeIfPresent(Date.self, forKey: .revealedAt)
        messageID = try container.decodeIfPresent(Ref.self, forKey: .message)?.id
    }

    /// The question to show above the statement: "Myth or Legend?"
    public var question: String {
        choices.map(\.label).joined(separator: " or ") + "?"
    }

    /// Whether the answer is out.
    public var isRevealed: Bool { revealedAt != nil || answer != nil }

    /// Votes cast so far.
    public var totalVotes: Int { choices.reduce(0) { $0 + $1.count } }

    /// A choice's share of the votes, from 0 to 1.
    public func share(of choice: Choice) -> Double {
        totalVotes == 0 ? 0 : Double(choice.count) / Double(totalVotes)
    }
}

/// A venue's show tonight, as guests see it: what ``ShowEntry`` knows about each lineup entry, the next curtain call's
/// readiness counts, and the latest trivia round.
public struct VenueShow: Sendable, Hashable {
    public let venueID: String
    /// In running order, like ``VenueLineup/entries``.
    public let entries: [ShowEntry]
    /// The next curtain call, while one is coming.
    public let curtain: CurtainReadiness?
    /// Tonight's latest trivia round: open, or the last revealed.
    public let trivia: TriviaRound?

    public init(venueID: String, entries: [ShowEntry] = [], curtain: CurtainReadiness? = nil, trivia: TriviaRound? = nil) {
        self.venueID = venueID
        self.entries = entries
        self.curtain = curtain
        self.trivia = trivia
    }

    /// What show control knows about a lineup entry.
    public func entry(for lineupEntry: LineupEntry) -> ShowEntry? { entries.first { $0.id == lineupEntry.id } }

    /// The entry running trivia now, if any.
    public func triviaEntry(in lineup: VenueLineup) -> ShowEntry? {
        let onNow = Set(lineup.entries.filter { $0.state == .on }.map(\.id))
        return entries.last { $0.runsTrivia && onNow.contains($0.id) }
    }
}

// MARK: - Operations

extension Queries {
    static let showEntryFields = """
    id entryKind activity curtainCallMinutes estimatedMinutes projectedStartsAt projectedEndsAt lateMinutes
    scenes { id title lengthSeconds performer { id name avatarUrl } }
    """
    static let triviaRoundFields = """
    id statement choices { label count } myChoice voting closesAt answer roomCall reveal revealsAtEnd revealedAt
    message { id }
    """

    static let venueShow = """
    query VenueShow($id: ID!) {
      venues {
        venue(id: $id) {
          id
          people {
            runningOrder { nodes { \(showEntryFields) } }
            curtainReadiness { act { id } verdict counts { area ready total } }
          }
          trivia { current { \(triviaRoundFields) } }
        }
      }
    }
    """

    static let voteTrivia = """
    mutation VoteTrivia($roundId: ID!, $choice: String!) {
      voteTrivia(input: { roundId: $roundId, choice: $choice }) { round { \(triviaRoundFields) } }
    }
    """
}

struct VenueShowResponse: Decodable, Sendable {
    struct Venue: Decodable, Sendable {
        struct People: Decodable, Sendable {
            var runningOrder: Nodes<ShowEntry>
            var curtainReadiness: CurtainReadiness?
        }
        struct Trivia: Decodable, Sendable { var current: TriviaRound? }
        var id: String
        var people: People
        var trivia: Trivia?
    }
    struct Venues: Decodable, Sendable { var venue: Venue? }
    var venues: Venues

    var show: VenueShow? {
        venues.venue.map { venue in
            VenueShow(venueID: venue.id, entries: venue.people.runningOrder.nodes,
                      curtain: venue.people.curtainReadiness, trivia: venue.trivia?.current)
        }
    }
}

struct VoteTriviaResponse: Decodable, Sendable {
    struct Payload: Decodable, Sendable { var round: TriviaRound }
    var voteTrivia: Payload
}

extension AudienceSession {
    /// A venue's show tonight: segments and activities, scenes, projected times, the next curtain call's readiness
    /// counts and the latest trivia round. `nil` when the venue doesn't exist; throws on an API without show control,
    /// so show the lineup without these parts then.
    public func show(venueID: String) async throws -> VenueShow? {
        try await graphQL(Queries.venueShow, variables: ["id": .string(venueID)], operationName: "VenueShow",
                          as: VenueShowResponse.self).show
    }

    /// Votes in a trivia round, or changes the vote, while it's open. They must be at the venue; otherwise this throws
    /// with the server's reason. Returns the round with its new counts.
    @discardableResult
    public func voteTrivia(roundID: String, choice: String) async throws -> TriviaRound {
        try await graphQL(Queries.voteTrivia, variables: ["roundId": .string(roundID), "choice": .string(choice)],
                          operationName: "VoteTrivia", as: VoteTriviaResponse.self).voteTrivia.round
    }
}
