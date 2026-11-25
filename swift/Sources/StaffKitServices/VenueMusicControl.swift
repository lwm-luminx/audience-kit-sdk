import Foundation
import AudienceCore
import StaffKitCore

// Music control from Velvet and Backstage (the API's VenueMusic; Rick 2026-11-22: "music skip queue control to Velvet
// iOS", "should also show in Backstage for the event hosts", on Live Activities and the lock screen too).
//
// Whoever runs the show (the venue, Velvet on its device, the hosts of the event on now) can skip, go back, pause or
// play the venue's music and move songs in tonight's queue. The music plays on the venue's Mac (Velvet Display), which
// follows `venueMusic` and does each command at once; the queue is tonight's night playlist in the lineup, which the
// Mac plays in order.
//
// When the venue plays a licensed business music service instead (Soundtrack, Rockbot: `nowPlaying.source`), the API
// sends the same commands to that service, so the card and the Live Activities work unchanged. Soundtrack has no Back
// and Rockbot only skips; on Soundtrack staff can also search and queue a song (`queueVenueMusicServiceTrack`).

/// What a staff app asks of the venue's music.
public enum VenueMusicCommand: String, Sendable, CaseIterable, Codable {
    case skip = "SKIP"
    case previous = "PREVIOUS"
    case pause = "PAUSE"
    case play = "PLAY"
}

/// One song of tonight's queue: its scene in the night playlist's lineup entry.
public struct VenueQueueSong: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let title: String?
    public let artist: String?
    public let trackUri: String?
    public let lengthSeconds: Int?

    public init(id: String, title: String?, artist: String? = nil, trackUri: String? = nil, lengthSeconds: Int? = nil) {
        self.id = id; self.title = title; self.artist = artist; self.trackUri = trackUri; self.lengthSeconds = lengthSeconds
    }

    /// The song's title, or a stand-in.
    public var name: String { title?.isEmpty == false ? title! : "Untitled" }
}

/// Tonight's songs at a venue (`Venue.music.queue`): the one on now and the ones still to play, in order.
public struct VenueMusicQueue: Codable, Sendable, Equatable {
    public let segmentId: String
    public let played: Int
    public let playing: VenueQueueSong?
    public let coming: [VenueQueueSong]

    public init(segmentId: String, played: Int = 0, playing: VenueQueueSong? = nil, coming: [VenueQueueSong] = []) {
        self.segmentId = segmentId; self.played = played; self.playing = playing; self.coming = coming
    }

    /// The queue as it reads once `song` moves to `index` among the songs still to play, so the list moves at once.
    public func moving(_ songID: String, to index: Int) -> VenueMusicQueue {
        guard let from = coming.firstIndex(where: { $0.id == songID }) else { return self }
        var order = coming
        let song = order.remove(at: from)
        order.insert(song, at: min(max(index, 0), order.count))
        return VenueMusicQueue(segmentId: segmentId, played: played, playing: playing, coming: order)
    }
}

/// The venue's music as a staff app shows it: what plays (from the Mac's report) and tonight's queue.
public struct VenueMusicState: Sendable, Equatable {
    public var nowPlaying: VenueNowPlaying?
    public var queue: VenueMusicQueue?
    /// Whether the venue's Mac is reporting what plays, so a command reaches it.
    public var playerOnline: Bool { nowPlaying != nil }

    public init(nowPlaying: VenueNowPlaying? = nil, queue: VenueMusicQueue? = nil) {
        self.nowPlaying = nowPlaying; self.queue = queue
    }

    /// The next song: the queue's first, else the player's own up next.
    public var next: (title: String, artist: String?)? {
        if let song = queue?.coming.first { return (song.name, song.artist) }
        if let song = nowPlaying?.upNext?.first { return (song.title, song.artist) }
        return nil
    }

    /// Whether the music is paused (the Mac said so); playing when it didn't say.
    public var paused: Bool { nowPlaying?.playing == false }

    /// The licensed music service playing, when the music comes from one rather than the venue's Mac.
    public var service: VenueMusicService? { nowPlaying?.source.flatMap(VenueMusicService.init(rawValue:)) }
    /// Whether Back does anything: the Mac goes back a song, the services can't.
    public var canGoBack: Bool { service == nil }
    /// Whether Pause and Play do anything (Rockbot only skips).
    public var canPause: Bool { service != .rockbot }
    /// Whether staff can search for a song and queue it (Soundtrack).
    public var canQueueSongs: Bool { service == .soundtrack }
}

/// A licensed business music service a venue plays, as `nowPlaying.source` names it.
public enum VenueMusicService: String, Sendable, Codable {
    case soundtrack
    case rockbot

    public var name: String {
        switch self {
        case .soundtrack: "Soundtrack"
        case .rockbot: "Rockbot"
        }
    }
}

/// A track at the venue's Soundtrack that staff can queue (`Venue.music.serviceTracks`).
public struct VenueServiceTrack: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let title: String
    public let artists: [String]
    public let album: String?
    public let artworkUrl: String?

    public init(id: String, title: String, artists: [String] = [], album: String? = nil, artworkUrl: String? = nil) {
        self.id = id; self.title = title; self.artists = artists; self.album = album; self.artworkUrl = artworkUrl
    }

    /// "Cher, Eric Clapton", or nil without artists.
    public var artist: String? { artists.isEmpty ? nil : artists.joined(separator: ", ") }
}

/// Something that happened to the venue's music (`venueMusic`).
public struct VenueMusicChange: Sendable, Equatable {
    public enum Kind: String, Sendable, Codable {
        case ready = "READY"
        case nowPlaying = "NOW_PLAYING"
        case queueChanged = "QUEUE_CHANGED"
        case skip = "SKIP"
        case previous = "PREVIOUS"
        case pause = "PAUSE"
        case play = "PLAY"

        /// The command for the venue's Mac, when it is one.
        public var command: VenueMusicCommand? { VenueMusicCommand(rawValue: rawValue) }
    }

    public let id: String
    public let kind: Kind
    public let at: String?
    public let nowPlaying: VenueNowPlaying?
    public let queue: VenueMusicQueue?

    public init(id: String, kind: Kind, at: String? = nil, nowPlaying: VenueNowPlaying? = nil,
                queue: VenueMusicQueue? = nil) {
        self.id = id; self.kind = kind; self.at = at; self.nowPlaying = nowPlaying; self.queue = queue
    }
}

/// What following the venue's music sends.
public enum VenueMusicEvent: Sendable, Equatable {
    case change(VenueMusicChange)
    /// The API turned us away (not the venue's, or an API without music control).
    case rejected
    /// The cable dropped; nil while it reconnects by itself.
    case offline(String?)
}

extension VenueMusicChange: Decodable {
    private enum CodingKeys: String, CodingKey { case id, kind, at, nowPlaying, queue }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        // A kind from a newer API reads as a song change: reading the state again is always safe.
        kind = (try? c.decode(Kind.self, forKey: .kind)) ?? .nowPlaying
        at = try c.decodeIfPresent(String.self, forKey: .at)
        nowPlaying = try c.decodeIfPresent(VenueNowPlaying.self, forKey: .nowPlaying)
        queue = try c.decodeIfPresent(VenueMusicQueue.self, forKey: .queue)
    }
}

extension VenueManagementClient {
    static let nowPlayingFields = "title artist album artworkUrl source positionMs playing upNext { title artist }"
    static let queueSongFields = "id title artist trackUri lengthSeconds"
    static let musicQueueFields = "segmentId played playing { \(queueSongFields) } coming { \(queueSongFields) }"

    /// What the venue plays now and tonight's queue. An API without the queue (before music control) gives the song
    /// alone.
    public func venueMusic(venueID: String) async throws -> VenueMusicState {
        struct Music: Decodable, Sendable { let nowPlaying: VenueNowPlaying?; let queue: VenueMusicQueue? }
        struct Venue: Decodable, Sendable { let music: Music? }
        struct Venues: Decodable, Sendable { let venue: Venue? }
        struct Response: Decodable, Sendable { let venues: Venues }
        if let response = try? await session.graphQL("""
            query StaffVenueMusic($id: ID!) { venues { venue(id: $id) { music { nowPlaying { \(Self.nowPlayingFields) } queue { \(Self.musicQueueFields) } } } } }
            """, variables: ["id": .string(venueID)], as: Response.self) {
            let music = response.venues.venue?.music
            return VenueMusicState(nowPlaying: music?.nowPlaying, queue: music?.queue)
        }
        let response = try await session.graphQL("""
            query StaffVenueNowPlaying($id: ID!) { venues { venue(id: $id) { music { nowPlaying { \(Self.nowPlayingFields) } } } } }
            """, variables: ["id": .string(venueID)], as: Response.self)
        return VenueMusicState(nowPlaying: response.venues.venue?.music?.nowPlaying)
    }

    /// Skips, goes back, pauses or plays the venue's music: its Mac does it at once. Says what plays and whether the
    /// Mac is there to hear it.
    @discardableResult
    public func controlVenueMusic(venueID: String, command: VenueMusicCommand) async throws -> VenueMusicState {
        struct Payload: Decodable, Sendable { let nowPlaying: VenueNowPlaying?; let queue: VenueMusicQueue? }
        struct Response: Decodable, Sendable { let controlVenueMusic: Payload }
        let response = try await session.graphQL("""
            mutation StaffVenueMusicControl($venueId: ID!, $command: VenueMusicCommand!) {
              controlVenueMusic(input: { venueId: $venueId, command: $command }) { nowPlaying { \(Self.nowPlayingFields) } queue { \(Self.musicQueueFields) } }
            }
            """, variables: ["venueId": .string(venueID), "command": .string(command.rawValue)], as: Response.self)
        return VenueMusicState(nowPlaying: response.controlVenueMusic.nowPlaying, queue: response.controlVenueMusic.queue)
    }

    /// Moves a song still to play to `index` among them (0 plays next); the Mac plays the new order.
    @discardableResult
    public func moveVenueSong(venueID: String, songID: String, to index: Int) async throws -> VenueMusicQueue? {
        struct Payload: Decodable, Sendable { let queue: VenueMusicQueue? }
        struct Response: Decodable, Sendable { let moveVenueSong: Payload }
        let response = try await session.graphQL("""
            mutation StaffVenueSongMove($venueId: ID!, $sceneId: ID!, $toIndex: Int!) {
              moveVenueSong(input: { venueId: $venueId, sceneId: $sceneId, toIndex: $toIndex }) { queue { \(Self.musicQueueFields) } }
            }
            """, variables: ["venueId": .string(venueID), "sceneId": .string(songID), "toIndex": .int(index)],
            as: Response.self)
        return response.moveVenueSong.queue
    }

    /// Tracks at the venue's Soundtrack matching `query` (a title, an artist or both), to queue one.
    public func searchVenueServiceTracks(venueID: String, query: String) async throws -> [VenueServiceTrack] {
        struct Music: Decodable, Sendable { let serviceTracks: [VenueServiceTrack] }
        struct Venue: Decodable, Sendable { let music: Music? }
        struct Venues: Decodable, Sendable { let venue: Venue? }
        struct Response: Decodable, Sendable { let venues: Venues }
        let response = try await session.graphQL("""
            query StaffVenueServiceTracks($id: ID!, $query: String!) { venues { venue(id: $id) { music { serviceTracks(query: $query) { id title artists album artworkUrl } } } } }
            """, variables: ["id": .string(venueID), "query": .string(query)], as: Response.self)
        return response.venues.venue?.music?.serviceTracks ?? []
    }

    /// Queues a track on the venue's Soundtrack zone playing now: after the song on now, or at once with `immediate`.
    @discardableResult
    public func queueVenueServiceTrack(venueID: String, trackID: String, immediate: Bool = false) async throws -> VenueMusicState {
        struct Payload: Decodable, Sendable { let nowPlaying: VenueNowPlaying?; let queue: VenueMusicQueue? }
        struct Response: Decodable, Sendable { let queueVenueMusicServiceTrack: Payload }
        let response = try await session.graphQL("""
            mutation StaffVenueServiceTrackQueue($venueId: ID!, $trackId: ID!, $immediate: Boolean!) {
              queueVenueMusicServiceTrack(input: { venueId: $venueId, trackId: $trackId, immediate: $immediate }) { nowPlaying { \(Self.nowPlayingFields) } queue { \(Self.musicQueueFields) } }
            }
            """, variables: ["venueId": .string(venueID), "trackId": .string(trackID), "immediate": .bool(immediate)],
            as: Response.self)
        let payload = response.queueVenueMusicServiceTrack
        return VenueMusicState(nowPlaying: payload.nowPlaying, queue: payload.queue)
    }

    /// Blocks the song on now at the venue's Soundtrack, so the zone never plays it again, and skips it
    /// (`controlVenueMusicService` action block). The venue's managers and its Velvet devices with the music permission.
    public func blockVenueServiceSong(venueID: String) async throws {
        struct Song: Decodable, Sendable { let title: String? }
        struct Zone: Decodable, Sendable { let song: Song? }
        struct Payload: Decodable, Sendable { let nowPlaying: [Zone] }
        struct Response: Decodable, Sendable { let controlVenueMusicService: Payload }
        _ = try await session.graphQL("""
            mutation StaffVenueServiceBlock($venueId: ID!) {
              controlVenueMusicService(input: { venueId: $venueId, provider: "soundtrack", action: "block" }) { nowPlaying { song { title } } }
            }
            """, variables: ["venueId": .string(venueID)], as: Response.self)
    }

    /// Hands the API a staff Live Activity's own push token, so it keeps the activity up to date while the app is
    /// closed (a new song, a moved queue, a bingo number drawn on another phone). `kind` is "music" or "bingo";
    /// `appID` the app's bundle ID; `sandbox` true for a development build's token.
    public func registerStaffLiveActivity(venueID: String, kind: String, pushToken: String, appID: String,
                                          sandbox: Bool) async throws {
        struct Payload: Decodable, Sendable { let registered: Bool }
        struct Response: Decodable, Sendable { let registerStaffLiveActivity: Payload }
        _ = try await session.graphQL("""
            mutation StaffLiveActivityRegister($venueId: ID!, $kind: StaffLiveActivityKind!, $pushToken: String!, $appId: String!, $sandbox: Boolean!) {
              registerStaffLiveActivity(input: { venueId: $venueId, kind: $kind, pushToken: $pushToken, appId: $appId, sandbox: $sandbox }) { registered }
            }
            """, variables: ["venueId": .string(venueID), "kind": .string(kind.uppercased()),
                             "pushToken": .string(pushToken), "appId": .string(appID), "sandbox": .bool(sandbox)],
            as: Response.self)
    }

    /// Stops the API pushing a staff Live Activity (it ended, or someone swiped it away).
    public func endStaffLiveActivity(pushToken: String) async throws {
        struct Payload: Decodable, Sendable { let ended: Bool }
        struct Response: Decodable, Sendable { let endStaffLiveActivity: Payload }
        _ = try await session.graphQL("""
            mutation StaffLiveActivityEnd($pushToken: String!) {
              endStaffLiveActivity(input: { pushToken: $pushToken }) { ended }
            }
            """, variables: ["pushToken": .string(pushToken)], as: Response.self)
    }

    static let venueMusicSubscription = """
        subscription StaffVenueMusic($venueId: ID!) { venueMusic(venueId: $venueId) { id kind at nowPlaying { \(nowPlayingFields) } queue { \(musicQueueFields) } } }
        """
    /// What the venue's Mac asks: only the commands and the queue's changes, without reading the song again.
    static let venueMusicCommandsSubscription = """
        subscription VelvetVenueMusicCommands($venueId: ID!) { venueMusic(venueId: $venueId) { id kind at } }
        """

    /// Follows the venue's music: READY with the state now, then each command, song and queue change. `commandsOnly`
    /// (the venue's Mac) leaves out the song and queue. Ending the iteration stops following.
    public func venueMusicFeed(venueID: String, commandsOnly: Bool = false) async -> AsyncStream<VenueMusicEvent> {
        let query = commandsOnly ? Self.venueMusicCommandsSubscription : Self.venueMusicSubscription
        let results = await session.subscribe(query, variables: ["venueId": .string(venueID)])
        return AsyncStream { continuation in
            let task = Task {
                for await result in results {
                    guard let event = Self.venueMusicEvent(from: result) else { continue }
                    continuation.yield(event)
                    if case .rejected = event { break }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static func venueMusicEvent(from event: AudienceCable.Event) -> VenueMusicEvent? {
        switch event {
        case .rejected: return .rejected
        case .disconnected(let reason, let reconnects): return .offline(reconnects ? nil : (reason ?? "Signed out"))
        case .result(let data): return venueMusicEvent(from: data)
        default: return nil
        }
    }

    static func venueMusicEvent(from data: Data) -> VenueMusicEvent? {
        struct Payload: Decodable { let venueMusic: VenueMusicChange? }
        guard let result = try? JSONDecoder().decode(GraphQLSubscriptionResult<Payload>.self, from: data) else {
            return nil
        }
        if let change = result.data?.venueMusic { return .change(change) }
        return result.refused ? .rejected : nil
    }
}

/// Where the venue's song is, as the API last heard (`Venue.music.nowPlaying`): with a Soundtrack zone, how far in it
/// was at `reportedAt`, its length and its ISRC, so a sing-along screen finds the recording's lyrics and keeps them in
/// time without the audio.
public struct VenueTrackTiming: Sendable, Equatable {
    public let title: String
    public let artist: String?
    public let positionMs: Int?
    public let playing: Bool?
    public let reportedAt: Date?
    public let durationMs: Int?
    public let isrc: String?

    public init(title: String, artist: String? = nil, positionMs: Int? = nil, playing: Bool? = nil,
                reportedAt: Date? = nil, durationMs: Int? = nil, isrc: String? = nil) {
        self.title = title; self.artist = artist; self.positionMs = positionMs; self.playing = playing
        self.reportedAt = reportedAt; self.durationMs = durationMs; self.isrc = isrc
    }

    /// The clock for the song's lyrics, when the API said where it was.
    public func clock(trackID: String? = nil) -> PlaybackClock? {
        guard let positionMs, let reportedAt else { return nil }
        return PlaybackClock(trackID: trackID, position: Double(positionMs) / 1000, readAt: reportedAt,
                             playing: playing ?? true, duration: durationMs.map { Double($0) / 1000 })
    }
}

extension VenueManagementClient {
    /// Where the venue's song is, its length and ISRC (an API before those gives the position alone). Nil with nothing
    /// playing.
    public func venueTrackTiming(venueID: String) async throws -> VenueTrackTiming? {
        struct Track: Decodable, Sendable {
            let title: String; let artist: String?; let positionMs: Int?; let playing: Bool?
            let reportedAt: String?; let durationMs: Int?; let isrc: String?
        }
        struct Music: Decodable, Sendable { let nowPlaying: Track? }
        struct Venue: Decodable, Sendable { let music: Music? }
        struct Venues: Decodable, Sendable { let venue: Venue? }
        struct Response: Decodable, Sendable { let venues: Venues }
        let full = "title artist positionMs playing reportedAt durationMs isrc"
        let older = "title artist positionMs playing reportedAt"
        func read(_ fields: String) async throws -> Track? {
            try await session.graphQL("""
                query VelvetTrackTiming($id: ID!) { venues { venue(id: $id) { music { nowPlaying { \(fields) } } } } }
                """, variables: ["id": .string(venueID)], as: Response.self).venues.venue?.music?.nowPlaying
        }
        let track: Track?
        do { track = try await read(full) } catch { track = try await read(older) }
        guard let track else { return nil }
        let reported = track.reportedAt.flatMap { ISO8601DateFormatter().date(from: $0) }
        return VenueTrackTiming(title: track.title, artist: track.artist, positionMs: track.positionMs,
                                playing: track.playing, reportedAt: reported, durationMs: track.durationMs,
                                isrc: track.isrc)
    }
}
