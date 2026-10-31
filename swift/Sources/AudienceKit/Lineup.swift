import AudienceCore
import Foundation

// A venue's lineup tonight (its running order), its karaoke signups and its song requests. A karaoke signup is a
// singer on the lineup: an entry with role `.singer` carrying its `songRequest`, which the venue calls up by advancing
// the running order like any other act. A song request has no lineup entry: it waits in the venue's song queue until
// the host plays it (`UP`, "Now playing"), then is done or skipped. See `VenueLineup` for what an app shows from it
// and AudienceKitUI's `VenueLineupStrip`, `KaraokeQueue` and `SongRequestsSection` for the views.

/// One entry on a venue's lineup: someone (or several people) on, or an intermission. A karaoke singer is an entry
/// with role ``Role/singer`` and the signup as ``songRequest``.
public struct LineupEntry: Codable, Sendable, Hashable, Identifiable {
    /// An act or an intermission.
    public enum Kind: String, Codable, Sendable, Hashable {
        case act = "ACT", intermission = "INTERMISSION", unknown

        public init(from decoder: any Decoder) throws {
            self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
        }
    }

    /// What someone is doing.
    public enum Role: String, Codable, Sendable, Hashable {
        case host = "HOST", dj = "DJ", performer = "PERFORMER", mc = "MC", singer = "SINGER", unknown

        public init(from decoder: any Decoder) throws {
            self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
        }
    }

    /// Upcoming, on now or done.
    public enum State: String, Codable, Sendable, Hashable {
        case upcoming = "UPCOMING", on = "ON", done = "DONE", unknown

        public init(from decoder: any Decoder) throws {
            self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
        }
    }

    /// How it starts: at a set time (`hard`), around one when advanced to (`soft`), or when advanced to (`none`).
    public enum StartTiming: String, Codable, Sendable, Hashable {
        case hard = "HARD", soft = "SOFT", none = "NONE", unknown

        public init(from decoder: any Decoder) throws {
            self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
        }
    }

    /// How it ends: at a set time, at close, or when advanced past.
    public enum EndTiming: String, Codable, Sendable, Hashable {
        case time = "TIME", close = "CLOSE", advance = "ADVANCE", unknown

        public init(from decoder: any Decoder) throws {
            self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
        }
    }

    /// Someone on an entry.
    public struct Person: Codable, Sendable, Hashable, Identifiable {
        public let id: String
        public let name: String?
        public let avatarUrl: String?

        public init(id: String, name: String? = nil, avatarUrl: String? = nil) {
            self.id = id
            self.name = name
            self.avatarUrl = avatarUrl
        }
    }

    public let id: String
    public let kind: Kind
    /// Nil for an intermission.
    public let role: Role?
    /// An act's billing (a duet's name, a singer's name) or an intermission's label.
    public let title: String?
    /// Who's on it, in billing order; empty for an intermission or a singer.
    public let people: [Person]
    public let state: State
    public let startTiming: StartTiming
    public let endTiming: EndTiming
    public let startsAt: Date?
    public let endsAt: Date?
    /// A singer's karaoke signup: the song, artist and who's singing it; nil for everything else.
    public let songRequest: SongRequest?
    /// An act's scenes (its numbers, each with who's on) in order; empty for anything else, or from an API before
    /// scenes. ``VenueLineup`` lists them in turn (``inTurn(_:)``).
    public let scenes: [Scene]
    /// A break inside an act: the ID of the scene it follows; nil for anything else.
    public let afterSceneID: String?

    /// One number in an act: who's on it, and when advancing put it on and took it off.
    public struct Scene: Codable, Sendable, Hashable, Identifiable {
        public let id: String
        /// Who performs it, in billing order.
        public let performers: [Person]
        public let wentOnAt: Date?
        public let cameOffAt: Date?

        public init(id: String, performers: [Person] = [], wentOnAt: Date? = nil, cameOffAt: Date? = nil) {
            self.id = id
            self.performers = performers
            self.wentOnAt = wentOnAt
            self.cameOffAt = cameOffAt
        }
    }

    public init(id: String, kind: Kind = .act, role: Role? = nil, title: String? = nil, people: [Person] = [],
                state: State = .upcoming, startTiming: StartTiming = .none, endTiming: EndTiming = .advance,
                startsAt: Date? = nil, endsAt: Date? = nil, songRequest: SongRequest? = nil, scenes: [Scene] = [],
                afterSceneID: String? = nil) {
        self.id = id
        self.kind = kind
        self.role = role
        self.title = title
        self.people = people
        self.state = state
        self.startTiming = startTiming
        self.endTiming = endTiming
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.songRequest = songRequest
        self.scenes = scenes
        self.afterSceneID = afterSceneID
    }

    /// Whether it's a karaoke singer.
    public var isSinger: Bool { role == .singer }

    /// How to bill it: its title, else its people ("Ada & Bo"), else "Intermission" or "Someone". A singer is
    /// billed by the name(s) they gave.
    public var displayName: String {
        if isSinger, let singer = songRequest?.singer ?? songRequest?.requesterName, !singer.isEmpty { return singer }
        if let title, !title.isEmpty { return title }
        let names = people.compactMap(\.name).filter { !$0.isEmpty }
        if !names.isEmpty { return names.formatted(.list(type: .and, width: .short)) }
        return kind == .intermission ? "Intermission" : "Someone"
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, role, title, people, state, startTiming, endTiming, startsAt, endsAt, songRequest, scenes
        case afterScene
    }

    private struct Ref: Codable, Hashable { var id: String }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        kind = try container.decodeIfPresent(Kind.self, forKey: .kind) ?? .act
        role = try container.decodeIfPresent(Role.self, forKey: .role)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        people = try container.decodeIfPresent(Connection<Person>.self, forKey: .people)?.nodes ?? []
        state = try container.decodeIfPresent(State.self, forKey: .state) ?? .unknown
        startTiming = try container.decodeIfPresent(StartTiming.self, forKey: .startTiming) ?? .unknown
        endTiming = try container.decodeIfPresent(EndTiming.self, forKey: .endTiming) ?? .unknown
        startsAt = try container.decodeIfPresent(Date.self, forKey: .startsAt)
        endsAt = try container.decodeIfPresent(Date.self, forKey: .endsAt)
        songRequest = try container.decodeIfPresent(SongRequest.self, forKey: .songRequest)
        scenes = (try? container.decodeIfPresent([Scene].self, forKey: .scenes)) ?? []
        afterSceneID = (try? container.decodeIfPresent(Ref.self, forKey: .afterScene))?.id
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(role, forKey: .role)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encode(Connection(nodes: people), forKey: .people)
        try container.encode(state, forKey: .state)
        try container.encode(startTiming, forKey: .startTiming)
        try container.encode(endTiming, forKey: .endTiming)
        try container.encodeIfPresent(startsAt, forKey: .startsAt)
        try container.encodeIfPresent(endsAt, forKey: .endsAt)
        try container.encodeIfPresent(songRequest, forKey: .songRequest)
        try container.encode(scenes, forKey: .scenes)
        try container.encodeIfPresent(afterSceneID.map(Ref.init), forKey: .afterScene)
    }
}

extension LineupEntry.Scene {
    private enum CodingKeys: String, CodingKey { case id, performers, wentOnAt, cameOffAt }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        performers = (try? container.decodeIfPresent([LineupEntry.Person].self, forKey: .performers)) ?? []
        wentOnAt = try? container.decodeIfPresent(Date.self, forKey: .wentOnAt)
        cameOffAt = try? container.decodeIfPresent(Date.self, forKey: .cameOffAt)
    }
}

extension LineupEntry {
    /// A running order as it runs: an act with scenes is each of its scenes in turn (who's on, not the act's billing
    /// like "First Set"), each followed by the breaks after it. Each scene's entry has the scene's ID, its performers
    /// (else the act's people), no title, and its own state.
    public static func inTurn(_ entries: [LineupEntry]) -> [LineupEntry] {
        let sceneIDs = Set(entries.filter { $0.kind == .act }.flatMap { $0.scenes.map(\.id) })
        let after = Dictionary(grouping: entries.filter { $0.afterSceneID.map(sceneIDs.contains) ?? false },
                               by: { $0.afterSceneID ?? "" })
        return entries.filter { !($0.afterSceneID.map(sceneIDs.contains) ?? false) }.flatMap { entry in
            guard entry.kind == .act, !entry.scenes.isEmpty else { return [entry] }
            return entry.scenes.enumerated().flatMap { index, scene in
                [entry.turn(scene, at: index)] + (after[scene.id] ?? [])
            }
        }
    }

    /// The entry ``inTurn(_:)`` lists for `id` (an act's, as `onStage` and `upNext` give it): the act's scene in that
    /// `state`, else its first; `id` itself for anything without scenes.
    public static func turnID(of id: String?, in entries: [LineupEntry], state: State) -> String? {
        guard let act = entries.first(where: { $0.id == id }), act.kind == .act, !act.scenes.isEmpty else { return id }
        let turns = act.scenes.indices.map { act.turn(act.scenes[$0], at: $0) }
        return (turns.first { $0.state == state } ?? turns.first)?.id
    }

    /// One of its scenes as an entry of its own. Its state is the act's, and in an act on now, as advancing marked
    /// it; in an act on now with no scene put on yet (run as one act), its first scene is on.
    private func turn(_ scene: Scene, at index: Int) -> LineupEntry {
        let sceneState: State
        if state != .on { sceneState = state }
        else if scene.cameOffAt != nil { sceneState = .done }
        else if scene.wentOnAt != nil { sceneState = .on }
        else { sceneState = scenes.allSatisfy({ $0.wentOnAt == nil }) && index == 0 ? .on : .upcoming }
        return LineupEntry(id: scene.id, kind: .act, role: role, title: nil,
                           people: scene.performers.isEmpty ? people : scene.performers, state: sceneState,
                           startTiming: index == 0 ? startTiming : .none, endTiming: .advance,
                           startsAt: index == 0 ? startsAt : nil)
    }
}

/// A song request or karaoke signup made from a venue's chat.
public struct SongRequest: Codable, Sendable, Hashable, Identifiable {
    /// A song to play, or a karaoke signup.
    public enum Kind: String, Codable, Sendable, Hashable {
        case song = "SONG", karaoke = "KARAOKE", unknown

        public init(from decoder: any Decoder) throws {
            self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
        }
    }

    /// Where it is: waiting, up (playing, or the singer is on), or finished.
    public enum State: String, Codable, Sendable, Hashable {
        case queued = "QUEUED", up = "UP", done = "DONE", skipped = "SKIPPED", withdrawn = "WITHDRAWN", unknown

        public init(from decoder: any Decoder) throws {
            self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
        }

        /// Still waiting or up.
        public var isOpen: Bool { self == .queued || self == .up }
    }

    public let id: String
    public let kind: Kind
    public let title: String
    public let artist: String?
    /// Who's singing a karaoke signup, as they gave it ("Ada & Bo").
    public let singer: String?
    /// Who asked, as the room shows them.
    public let requesterName: String?
    /// A dedication or a word for the host.
    public let note: String?
    /// Whether the signed-in user asked.
    public let mine: Bool
    public let state: State
    /// The request in words: "Ada to sing Waterloo by ABBA", "Dancing Queen by ABBA".
    public let summary: String?
    /// Its place in the night's queue of its kind, from 0.
    public let position: Int?
    /// When it was asked.
    public let createdAt: Date?
    /// When the host called it up (played it, or put the singer on).
    public let calledAt: Date?
    /// When it was played or sung, skipped or withdrawn.
    public let finishedAt: Date?

    public init(id: String, kind: Kind = .karaoke, title: String, artist: String? = nil, singer: String? = nil,
                requesterName: String? = nil, note: String? = nil, mine: Bool = false, state: State = .queued,
                summary: String? = nil, position: Int? = nil, createdAt: Date? = nil, calledAt: Date? = nil,
                finishedAt: Date? = nil) {
        self.id = id
        self.kind = kind
        self.title = title
        self.artist = artist
        self.singer = singer
        self.requesterName = requesterName
        self.note = note
        self.mine = mine
        self.state = state
        self.summary = summary
        self.position = position
        self.createdAt = createdAt
        self.calledAt = calledAt
        self.finishedAt = finishedAt
    }

    /// Whether it's a song to play, not a karaoke signup.
    public var isSong: Bool { kind == .song }

    /// "Title · Artist", or the title alone.
    public var songLine: String { [title, artist].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · ") }
}

/// Whether a venue's room takes requests of one kind now (`Venue.requests.karaoke` or `Venue.requests.song`), the
/// signed-in user's own tonight and, for songs, the queue.
public struct SongRequestWindow: Codable, Sendable, Hashable {
    /// Whether the venue takes them at all: karaoke run with AudienceKit, or song requests switched on.
    public let permitted: Bool
    /// Whether it does right now: a host (or, for songs, a DJ) is on and the venue hasn't paused them.
    public let open: Bool
    /// Whether the venue paused them for tonight; the singers already on the lineup still sing, the songs already
    /// asked for still play.
    public let paused: Bool
    /// Why it doesn't, worded for the room ("Karaoke signups open when a host is on"); nil while open.
    public let closedReason: String?
    /// Whether tonight's cutoff closed them: near the end of the event or the night, unless the venue reopened them.
    /// False from an API before cutoffs.
    public let cutOff: Bool
    /// Whether the venue reopened them for tonight past the cutoff.
    public let reopened: Bool
    /// When they close by themselves tonight; nil without a cutoff (or from an older API).
    public let closesAt: Date?
    /// The lineup entry taking them: the host (or DJ) on now.
    public let host: LineupEntry?
    /// The signed-in user's requests of this kind tonight, oldest first.
    public let mine: [SongRequest]
    /// Tonight's queue of this kind: what's waiting or up, in order. Fetched for songs only (karaoke singers are on
    /// the lineup); empty for karaoke.
    public let queue: [SongRequest]

    public init(permitted: Bool, open: Bool, paused: Bool = false, closedReason: String? = nil,
                host: LineupEntry? = nil, mine: [SongRequest] = [], queue: [SongRequest] = [], cutOff: Bool = false,
                reopened: Bool = false, closesAt: Date? = nil) {
        self.permitted = permitted
        self.open = open
        self.paused = paused
        self.closedReason = closedReason
        self.cutOff = cutOff
        self.reopened = reopened
        self.closesAt = closesAt
        self.host = host
        self.mine = mine
        self.queue = queue
    }

    /// Whether they're closed for the night: closed early by the venue (``paused``) or past the cutoff (``cutOff``).
    /// The apps show "Signups closed" in place of the lineup's "+" then, rather than a greyed "+".
    public var closed: Bool { paused || cutOff }

    /// What's playing now: the request the host called up, if any.
    public var playing: SongRequest? { queue.first { $0.state == .up } }

    /// How many requests are ahead of one still waiting: the one up and those before it; nil once it's called or
    /// when it isn't in the queue.
    public func requestsBefore(_ request: SongRequest) -> Int? {
        guard request.state == .queued, let index = queue.firstIndex(where: { $0.id == request.id }) else { return nil }
        return index
    }

    private enum CodingKeys: String, CodingKey {
        case permitted, open, paused, closedReason, host, mine, queue, cutOff, reopened, closesAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        permitted = try container.decode(Bool.self, forKey: .permitted)
        open = try container.decode(Bool.self, forKey: .open)
        paused = try container.decodeIfPresent(Bool.self, forKey: .paused) ?? false
        closedReason = try container.decodeIfPresent(String.self, forKey: .closedReason)
        host = try container.decodeIfPresent(LineupEntry.self, forKey: .host)
        mine = try container.decodeIfPresent(Connection<SongRequest>.self, forKey: .mine)?.nodes ?? []
        queue = try container.decodeIfPresent(Connection<SongRequest>.self, forKey: .queue)?.nodes ?? []
        cutOff = try container.decodeIfPresent(Bool.self, forKey: .cutOff) ?? false
        reopened = try container.decodeIfPresent(Bool.self, forKey: .reopened) ?? false
        closesAt = try container.decodeIfPresent(Date.self, forKey: .closesAt)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(permitted, forKey: .permitted)
        try container.encode(open, forKey: .open)
        try container.encode(paused, forKey: .paused)
        try container.encodeIfPresent(closedReason, forKey: .closedReason)
        try container.encodeIfPresent(host, forKey: .host)
        try container.encode(Connection(nodes: mine), forKey: .mine)
        try container.encode(Connection(nodes: queue), forKey: .queue)
        try container.encode(cutOff, forKey: .cutOff)
        try container.encode(reopened, forKey: .reopened)
        try container.encodeIfPresent(closesAt, forKey: .closesAt)
    }
}

/// Karaoke signups' window (`Venue.requests.karaoke`): the same shape as song requests'.
public typealias KaraokeWindow = SongRequestWindow

/// Who runs a venue's karaoke (`Venue.karaoke`): AudienceKit's own signups (``isAudienceKit``), or a partner such as
/// KaraFun with a session people join by link or QR code.
public struct VenueKaraoke: Codable, Sendable, Hashable {
    /// The provider's key: "audiencekit", "karafun", "custom_url"...; nil when the venue has none.
    public let provider: String?
    /// Its name to show ("KaraFun").
    public let providerName: String?
    /// The partner session's join link, when it has one.
    public let joinUrl: String?
    /// The partner session's code, to type in or show under the QR code.
    public let sessionCode: String?
    /// Whether tonight is one of the venue's karaoke nights; nil from an API that doesn't say. Its karaoke shows
    /// only then, not on its other nights.
    public let tonight: Bool?

    public init(provider: String? = nil, providerName: String? = nil, joinUrl: String? = nil,
                sessionCode: String? = nil, tonight: Bool? = nil) {
        self.provider = provider
        self.providerName = providerName
        self.joinUrl = joinUrl
        self.sessionCode = sessionCode
        self.tonight = tonight
    }

    /// Whether it's AudienceKit's own karaoke: signups in chat, singers on the lineup.
    public var isAudienceKit: Bool { provider == "audiencekit" }

    /// A partner's session (KaraFun and the like) to show tonight: the venue has one and tonight is a karaoke night.
    public var isPartnerSessionTonight: Bool { provider != nil && !isAudienceKit && tonight != false }

    /// The join link, when the partner session has one.
    public var joinURL: URL? { joinUrl.flatMap(URL.init(string:)) }
}

/// What a karaoke signup asks for: the song, and optionally its artist, who's singing (the signed-in user when left
/// out) and a note for the host.
public struct KaraokeSignup: Sendable, Hashable {
    public var title: String
    public var artist: String?
    public var singer: String?
    public var note: String?

    public init(title: String, artist: String? = nil, singer: String? = nil, note: String? = nil) {
        self.title = title
        self.artist = artist
        self.singer = singer
        self.note = note
    }
}

/// What a song request asks for: the song, and optionally its artist and a dedication or word for the host.
public struct SongRequestDraft: Sendable, Hashable {
    public var title: String
    public var artist: String?
    public var note: String?

    public init(title: String, artist: String? = nil, note: String? = nil) {
        self.title = title
        self.artist = artist
        self.note = note
    }
}

/// A venue's lineup tonight, in running order, its karaoke signups and its song requests: what
/// ``AudienceSession/lineup(venueID:)`` returns. The non-singers are ``acts`` and the karaoke singers ``singers``,
/// each in running order.
public struct VenueLineup: Sendable, Hashable {
    public let venueID: String
    public let venueName: String
    /// Everything on tonight, in running order: the venue's own lineup, then its events' as they start.
    public let entries: [LineupEntry]
    /// What's on stage now (advanced to), if anything.
    public let onStageID: String?
    /// What advancing puts on next, if anything.
    public let upNextID: String?
    /// Karaoke signups; nil when the API leaves them out.
    public let karaoke: KaraokeWindow?
    /// Who runs the venue's karaoke; nil when it has none.
    public let karaokeSession: VenueKaraoke?
    /// Song requests: whether they're taken, the user's own and the queue; nil when the API leaves them out.
    public let songRequests: SongRequestWindow?

    public init(venueID: String, venueName: String, entries: [LineupEntry], onStageID: String? = nil,
                upNextID: String? = nil, karaoke: KaraokeWindow? = nil, karaokeSession: VenueKaraoke? = nil,
                songRequests: SongRequestWindow? = nil) {
        self.venueID = venueID
        self.venueName = venueName
        self.entries = entries
        self.onStageID = onStageID
        self.upNextID = upNextID
        self.karaoke = karaoke
        self.karaokeSession = karaokeSession
        self.songRequests = songRequests
    }

    /// Everyone who isn't a karaoke singer: hosts, DJs, performers, MCs and intermissions.
    public var acts: [LineupEntry] { entries.filter { !$0.isSinger } }

    /// The karaoke singers, in running order.
    public var singers: [LineupEntry] { entries.filter(\.isSinger) }

    /// What the karaoke list shows, in running order: the singers, and the breaks among them (an intermission after
    /// the first singer, or one on now).
    public var karaokeEntries: [LineupEntry] {
        guard let first = entries.firstIndex(where: \.isSinger) else { return [] }
        return entries.enumerated().compactMap { index, entry in
            if entry.isSinger { return entry }
            guard entry.kind == .intermission, index > first || entry.state == .on else { return nil }
            return entry
        }
    }

    /// The intermission on now, if any: nobody is called up until the venue advances past it.
    public var breakOnNow: LineupEntry? { entries.first { $0.kind == .intermission && $0.state == .on } }

    /// A singer's number tonight, from 1, in running order; it stays the same once they've sung.
    public func singerNumber(of entry: LineupEntry) -> Int? {
        singers.firstIndex { $0.id == entry.id }.map { $0 + 1 }
    }

    /// The singer entry for a signup.
    public func entry(for request: SongRequest) -> LineupEntry? {
        singers.first { $0.songRequest?.id == request.id }
    }

    /// How many singers are ahead of a signup that hasn't been called: the one on stage and those still to sing.
    public func singersBefore(_ request: SongRequest) -> Int? {
        guard request.state == .queued, let index = singers.firstIndex(where: { $0.songRequest?.id == request.id })
        else { return nil }
        return singers[..<index].filter { $0.state != .done }.count
    }

    /// The signup to show the signed-in user: their earliest one still open, else their latest finished one.
    public var featuredSignup: SongRequest? {
        let mine = karaoke?.mine ?? []
        return mine.first { $0.state.isOpen } ?? mine.last
    }

    /// The signed-in user's song requests tonight, newest first.
    public var mySongRequests: [SongRequest] { (songRequests?.mine ?? []).reversed() }
}

// MARK: - Operations

extension Queries {
    static let personSummaryFields = "id name avatarUrl"
    static let songRequestFields = "id kind title artist singer requesterName note mine state summary position "
        + "createdAt calledAt finishedAt"
    static let lineupEntryFields = """
    id kind role title state startTiming endTiming startsAt endsAt
    people { nodes { \(personSummaryFields) } }
    songRequest { \(songRequestFields) }
    scenes { id performers { \(personSummaryFields) } wentOnAt cameOffAt } afterScene { id }
    """

    static let requestWindowFields = "permitted open paused closedReason"
    /// The signup cutoff (an API from 2026-10-26 on).
    static let requestCutoffFields = "cutOff reopened closesAt"

    static let venueLineup = """
    query VenueLineup($id: ID!) {
      venues {
        venue(id: $id) {
          id name
          people {
            runningOrder { nodes { \(lineupEntryFields) } }
            onStage { id }
            upNext { id }
          }
          karaoke { provider providerName joinUrl sessionCode tonight }
          requests {
            karaoke {
              \(requestWindowFields) \(requestCutoffFields)
              host { \(lineupEntryFields) }
              mine { nodes { \(songRequestFields) } }
            }
            song {
              \(requestWindowFields) \(requestCutoffFields)
              host { \(lineupEntryFields) }
              mine { nodes { \(songRequestFields) } }
              queue { nodes { \(songRequestFields) } }
            }
          }
        }
      }
    }
    """

    /// ``venueLineup`` for an API before the cutoff.
    static let venueLineupWithoutCutoff = """
    query VenueLineup($id: ID!) {
      venues {
        venue(id: $id) {
          id name
          people {
            runningOrder { nodes { \(lineupEntryFields) } }
            onStage { id }
            upNext { id }
          }
          karaoke { provider providerName joinUrl sessionCode tonight }
          requests {
            karaoke {
              \(requestWindowFields)
              host { \(lineupEntryFields) }
              mine { nodes { \(songRequestFields) } }
            }
            song {
              \(requestWindowFields)
              host { \(lineupEntryFields) }
              mine { nodes { \(songRequestFields) } }
              queue { nodes { \(songRequestFields) } }
            }
          }
        }
      }
    }
    """

    static let requestSong = """
    mutation RequestSong($venueId: ID!, $kind: SongRequestKind!, $title: String!, $artist: String, $singer: String,
                         $note: String) {
      requestSong(input: { venueId: $venueId, kind: $kind, title: $title, artist: $artist, singer: $singer,
                           note: $note }) {
        request { \(songRequestFields) }
      }
    }
    """

    static let withdrawSongRequest = """
    mutation WithdrawSongRequest($id: ID!) {
      withdrawSongRequest(input: { id: $id }) { request { \(songRequestFields) } }
    }
    """
}

struct VenueLineupResponse: Decodable, Sendable {
    struct Venue: Decodable, Sendable {
        struct People: Decodable, Sendable {
            struct Ref: Decodable, Sendable { var id: String }
            var runningOrder: Nodes<LineupEntry>
            var onStage: Ref?
            var upNext: Ref?
        }
        struct Requests: Decodable, Sendable {
            var karaoke: KaraokeWindow?
            var song: SongRequestWindow?
        }
        var id: String
        var name: String?
        var people: People
        var karaoke: VenueKaraoke?
        var requests: Requests?
    }
    struct Venues: Decodable, Sendable { var venue: Venue? }
    var venues: Venues

    var lineup: VenueLineup? {
        venues.venue.map { venue in
            let order = venue.people.runningOrder.nodes
            return VenueLineup(venueID: venue.id, venueName: venue.name ?? "", entries: LineupEntry.inTurn(order),
                               onStageID: LineupEntry.turnID(of: venue.people.onStage?.id, in: order, state: .on),
                               upNextID: LineupEntry.turnID(of: venue.people.upNext?.id, in: order, state: .upcoming),
                               karaoke: venue.requests?.karaoke, karaokeSession: venue.karaoke,
                               songRequests: venue.requests?.song)
        }
    }
}

struct SongRequestPayload: Decodable, Sendable { var request: SongRequest }
struct RequestSongResponse: Decodable, Sendable { var requestSong: SongRequestPayload }
struct WithdrawSongRequestResponse: Decodable, Sendable { var withdrawSongRequest: SongRequestPayload }

extension AudienceSession {
    /// A venue's lineup tonight with its karaoke singers and signups and its song requests, or `nil` when the venue
    /// doesn't exist.
    public func lineup(venueID: String) async throws -> VenueLineup? {
        do {
            return try await graphQL(Queries.venueLineup, variables: ["id": .string(venueID)],
                                     operationName: "VenueLineup", as: VenueLineupResponse.self).lineup
        } catch let error as AudienceKitError
                    where error.code == "undefinedField" || error.code == AudienceKitError.Code.graphQL {
            // An API before signup cutoffs (production until next is promoted) refuses their fields as invalid.
            return try await graphQL(Queries.venueLineupWithoutCutoff, variables: ["id": .string(venueID)],
                                     operationName: "VenueLineup", as: VenueLineupResponse.self).lineup
        }
    }

    /// Signs the signed-in user up to sing at a venue: they go last on its lineup as a singer, and the room sees the
    /// signup in chat. They must be at the venue, and the venue must be taking signups (``KaraokeWindow/open``);
    /// otherwise this throws with the server's reason.
    @discardableResult
    public func signUpToSing(venueID: String, _ signup: KaraokeSignup) async throws -> SongRequest {
        try await requestSong(venueID: venueID, kind: "KARAOKE", title: signup.title, artist: signup.artist,
                              singer: signup.singer, note: signup.note)
    }

    /// Asks the venue to play a song: it joins the night's song queue, and the room sees the request in chat. The
    /// host plays it (it goes ``SongRequest/State/up``, and the user is pushed: `kind: song_request_playing`), then
    /// marks it done or skips it. They must be at the venue, and the venue must be taking requests
    /// (``SongRequestWindow/open`` on ``VenueLineup/songRequests``); otherwise this throws with the server's reason.
    @discardableResult
    public func requestSong(venueID: String, title: String, artist: String? = nil, note: String? = nil) async throws
        -> SongRequest {
        try await requestSong(venueID: venueID, kind: "SONG", title: title, artist: artist, singer: nil, note: note)
    }

    private func requestSong(venueID: String, kind: String, title: String, artist: String?, singer: String?,
                             note: String?) async throws -> SongRequest {
        var variables: [String: GraphQLValue] = ["venueId": .string(venueID), "kind": .string(kind),
                                                 "title": .string(title)]
        if let artist, !artist.isEmpty { variables["artist"] = .string(artist) }
        if let singer, !singer.isEmpty { variables["singer"] = .string(singer) }
        if let note, !note.isEmpty { variables["note"] = .string(note) }
        return try await graphQL(Queries.requestSong, variables: variables, operationName: "RequestSong",
                                 as: RequestSongResponse.self).requestSong.request
    }

    /// Takes back one of the signed-in user's signups or song requests that hasn't been called up yet.
    @discardableResult
    public func withdrawSongRequest(id: String) async throws -> SongRequest {
        try await graphQL(Queries.withdrawSongRequest, variables: ["id": .string(id)],
                          operationName: "WithdrawSongRequest", as: WithdrawSongRequestResponse.self)
            .withdrawSongRequest.request
    }
}

/// A connection's `nodes`, both ways, so the models that carry one (`LineupEntry.people`) stay `Codable`.
private struct Connection<Element: Codable & Sendable>: Codable, Sendable { var nodes: [Element] }
