import Foundation

/// How `syncSpotifyQueue` treats the Mac's Spotify. Spotify's queue can only be added to (no reorder, no clear), so
/// the API matches it by starting the lineup's songs as a list, which replaces everything after the current song.
public enum SpotifyQueueMode: String, Sendable {
    /// Compare Spotify's queue with the lineup; change nothing.
    case check = "CHECK"
    /// Match now, keeping the current song where it is (Spotify restarts it at the same spot: a small hiccup).
    case now = "NOW"
    /// Start the lineup's next song with the rest after it: for the end of a song, so a lineup change lands cleanly.
    case nextSong = "NEXT_SONG"
}

/// What the API found of the Mac's Spotify against tonight's playlist in the lineup (`syncSpotifyQueue`).
public struct SpotifyQueueStatus: Decodable, Sendable, Equatable {
    /// OK, or why not: NO_LINEUP, NO_SONGS, NOT_CONNECTED, NEEDS_RECONNECT, PREMIUM_REQUIRED, NO_DEVICE, SPOTIFY_ERROR.
    public let state: String
    public let inSync: Bool
    public let changed: Bool
    public let deviceName: String?
    public let playingUri: String?
    /// The lineup's songs Spotify should play next, in order.
    public let coming: [PlaylistTrack]
    public let message: String?

    public init(state: String, inSync: Bool = false, changed: Bool = false, deviceName: String? = nil,
                playingUri: String? = nil, coming: [PlaylistTrack] = [], message: String? = nil) {
        self.state = state; self.inSync = inSync; self.changed = changed; self.deviceName = deviceName
        self.playingUri = playingUri; self.coming = coming; self.message = message
    }

    public var ok: Bool { state == "OK" }

    /// Whether trying again later can't help until someone does something (connect Spotify, sign in on the Mac).
    public var needsSomeone: Bool { ["NOT_CONNECTED", "NEEDS_RECONNECT", "PREMIUM_REQUIRED"].contains(state) }
}

extension VenueManagementClient {
    /// Compares or matches this Mac's Spotify queue with the songs not yet played in tonight's playlist segment of the
    /// lineup, through the venue's connected Spotify account. `deviceName` is this Mac's Spotify device (the
    /// computer's name); the API never plays on any other. Only a venue device with the music permission.
    public func syncSpotifyQueue(deviceName: String, mode: SpotifyQueueMode) async throws -> SpotifyQueueStatus {
        struct Response: Decodable, Sendable { let syncSpotifyQueue: SpotifyQueueStatus }
        return try await session.graphQL("""
            mutation VelvetSyncSpotifyQueue($device: String!, $mode: SpotifyQueueMode) {
              syncSpotifyQueue(input: { deviceName: $device, mode: $mode }) {
                state inSync changed deviceName playingUri message coming { uri title artist durationMs }
              }
            }
            """, variables: ["device": .string(deviceName), "mode": .string(mode.rawValue)],
            as: Response.self).syncSpotifyQueue
    }
}

/// When Velvet Display asks the API to bring Spotify's queue back in step with the lineup. A check every so often (and
/// after each new song) says whether they differ; a difference waits for the end of the current song and is fixed
/// then (`.nextSong`), once per song, so a lineup edit never cuts a song short by more than a moment or restarts it.
public struct SpotifyQueueKeeper: Sendable, Equatable {
    /// How long before a song's end the next one is asked for: the API and Spotify take about this long to answer.
    public static let lead: TimeInterval = 1.5
    /// How often Spotify's queue is compared with the lineup while a night plays.
    public static let checkEvery: TimeInterval = 20

    /// Whether the last check found Spotify's queue out of step with the lineup.
    public private(set) var outOfStep = false
    public private(set) var checkedAt: Date?
    /// The song whose end already asked for the next one, so it's asked once.
    public private(set) var switchedAfter: String?

    public init() {}

    /// Keeps a check's answer: a difference to fix at the end of this song, or none.
    public mutating func checked(_ status: SpotifyQueueStatus, at now: Date = Date()) {
        checkedAt = now
        outOfStep = status.ok && !status.inSync
    }

    /// Whether a check is due: none yet, or the last one is `checkEvery` old.
    public func checkDue(at now: Date = Date()) -> Bool {
        guard let checkedAt else { return true }
        return now.timeIntervalSince(checkedAt) >= Self.checkEvery
    }

    /// Whether to ask for the lineup's next song now: out of step, this song (`track`) within `lead` of its end, and not
    /// asked for this song yet. Marks it asked.
    public mutating func switchNow(track: String, position: TimeInterval, duration: TimeInterval) -> Bool {
        guard outOfStep, switchedAfter != track, duration > Self.lead * 2, position >= duration - Self.lead else { return false }
        switchedAfter = track
        outOfStep = false
        return true
    }
}
