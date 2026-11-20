import AudienceCore
import Foundation

// Sing-along nights (audience_kit_api #760): a karaoke night whose provider is `sing_along`. There's no singer queue;
// the whole room sings along to the night's playlist (Spotify, shuffled by default) with the lyrics on the venue's
// screens. Velvet Display plays it and reports what's on and what's next (`Venue.music.nowPlaying`). Apps show the
// rotation (now playing, up next) and let people ask for a song from the playlist through the venue's song requests
// (``AudienceSession/requestSong(venueID:title:artist:note:)``). Lyrics are never shown in the apps: the licence
// covers the venue's screens only.

/// One song of a night's playlist.
public struct SingAlongTrack: Codable, Sendable, Hashable, Identifiable {
    public let title: String
    /// Its artists, comma separated.
    public let artist: String?
    public let durationMs: Int?
    /// Its Spotify URI (`spotify:track:<id>`).
    public let uri: String

    public var id: String { uri }

    public init(title: String, artist: String? = nil, durationMs: Int? = nil, uri: String) {
        self.title = title
        self.artist = artist
        self.durationMs = durationMs
        self.uri = uri
    }

    /// Whether it's the song a request or a rotation entry names: the same title (and artist, when both have one),
    /// ignoring case, accents and punctuation.
    public func matches(title other: String, artist otherArtist: String?) -> Bool {
        guard SingAlongText.key(title) == SingAlongText.key(other) else { return false }
        guard let artist, let otherArtist, !SingAlongText.key(otherArtist).isEmpty else { return true }
        let mine = SingAlongText.key(artist), theirs = SingAlongText.key(otherArtist)
        return mine.contains(theirs) || theirs.contains(mine)
    }

    /// Whether a search typed in the picker finds it: every word in the title or the artist.
    public func matches(search: String) -> Bool {
        let words = SingAlongText.key(search).split(separator: " ")
        guard !words.isEmpty else { return true }
        let haystack = SingAlongText.key([title, artist ?? ""].joined(separator: " "))
        return words.allSatisfy { haystack.contains($0) }
    }
}

/// A night's playlist.
public struct SingAlongPlaylist: Codable, Sendable, Hashable {
    /// Where it plays: `spotify`, else `other`.
    public let provider: String
    public let shuffle: Bool
    /// Its web link, e.g. `https://open.spotify.com/playlist/<id>`.
    public let url: String
    /// Its Spotify URI, which the Spotify app opens; nil for other links.
    public let uri: String?
    /// Its songs in the playlist's order; nil when the API can't read Spotify's catalog for it.
    public let tracks: [SingAlongTrack]?

    public init(provider: String = "spotify", shuffle: Bool = true, url: String, uri: String? = nil,
                tracks: [SingAlongTrack]? = nil) {
        self.provider = provider
        self.shuffle = shuffle
        self.url = url
        self.uri = uri
        self.tracks = tracks
    }

    /// The songs a search finds, in the playlist's order.
    public func tracks(matching search: String) -> [SingAlongTrack] {
        (tracks ?? []).filter { $0.matches(search: search) }
    }

    /// The playlist's song a request or rotation entry names, if it's on the playlist.
    public func track(title: String, artist: String?) -> SingAlongTrack? {
        tracks?.first { $0.matches(title: title, artist: artist) }
    }
}

/// A song the venue plays next.
public struct UpNextSong: Codable, Sendable, Hashable {
    public let title: String
    public let artist: String?

    public init(title: String, artist: String? = nil) {
        self.title = title
        self.artist = artist
    }
}

/// What the venue's player says is on (Velvet Display on a sing-along night), and what it plays next.
public struct NowPlaying: Codable, Sendable, Hashable {
    public let title: String
    public let artist: String?
    public let album: String?
    public let artworkUrl: String?
    public let reportedAt: Date?
    /// When the report goes stale: after it, nothing is known to be playing.
    public let expiresAt: Date?
    /// In order; empty when the player doesn't know.
    public let upNext: [UpNextSong]

    public init(title: String, artist: String? = nil, album: String? = nil, artworkUrl: String? = nil,
                reportedAt: Date? = nil, expiresAt: Date? = nil, upNext: [UpNextSong] = []) {
        self.title = title
        self.artist = artist
        self.album = album
        self.artworkUrl = artworkUrl
        self.reportedAt = reportedAt
        self.expiresAt = expiresAt
        self.upNext = upNext
    }

    private enum CodingKeys: String, CodingKey { case title, artist, album, artworkUrl, reportedAt, expiresAt, upNext }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        artist = try container.decodeIfPresent(String.self, forKey: .artist)
        album = try container.decodeIfPresent(String.self, forKey: .album)
        artworkUrl = try container.decodeIfPresent(String.self, forKey: .artworkUrl)
        reportedAt = try container.decodeIfPresent(String.self, forKey: .reportedAt).flatMap(ISO8601.date(from:))
        expiresAt = try container.decodeIfPresent(String.self, forKey: .expiresAt).flatMap(ISO8601.date(from:))
        upNext = try container.decodeIfPresent([UpNextSong].self, forKey: .upNext) ?? []
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(artist, forKey: .artist)
        try container.encodeIfPresent(album, forKey: .album)
        try container.encodeIfPresent(artworkUrl, forKey: .artworkUrl)
        try container.encodeIfPresent(reportedAt.map(ISO8601.string(from:)), forKey: .reportedAt)
        try container.encodeIfPresent(expiresAt.map(ISO8601.string(from:)), forKey: .expiresAt)
        try container.encode(upNext, forKey: .upNext)
    }

    /// Whether the report still holds at `date`.
    public func isFresh(at date: Date = Date()) -> Bool {
        guard let expiresAt else { return true }
        return expiresAt > date
    }
}

/// An event's sing-along: whether it is one, its playlist, and its venue's rotation right now.
public struct SingAlongNight: Sendable, Hashable {
    public let eventID: String
    /// Whether the night is a sing-along (its karaoke provider is `sing_along`).
    public let isSingAlong: Bool
    /// "Sing-along".
    public let providerName: String?
    public let playlist: SingAlongPlaylist?
    public let venueID: String?
    public let venueName: String?
    /// The venue's player's latest report, nil when it has none or it went stale (``NowPlaying/isFresh(at:)``).
    public let nowPlaying: NowPlaying?

    public init(eventID: String, isSingAlong: Bool, providerName: String? = nil, playlist: SingAlongPlaylist? = nil,
                venueID: String? = nil, venueName: String? = nil, nowPlaying: NowPlaying? = nil) {
        self.eventID = eventID
        self.isSingAlong = isSingAlong
        self.providerName = providerName
        self.playlist = playlist
        self.venueID = venueID
        self.venueName = venueName
        self.nowPlaying = nowPlaying
    }

    /// The same night with a newer rotation (``AudienceSession/nowPlaying(venueID:)``).
    public func with(nowPlaying: NowPlaying?) -> SingAlongNight {
        SingAlongNight(eventID: eventID, isSingAlong: isSingAlong, providerName: providerName, playlist: playlist,
                       venueID: venueID, venueName: venueName, nowPlaying: nowPlaying)
    }
}

/// Where a playlist song stands tonight, for the request picker: a song that is on, coming up or already asked for
/// can't be asked for again.
public enum SingAlongTrackStatus: String, Sendable, Hashable {
    case playingNow, upNext, requested, inQueue
}

extension SingAlongNight {
    /// Where `track` stands: playing now, up next, asked for by the signed-in user, or in the night's song queue.
    /// Nil when it can be asked for. Songs the shuffle already played aren't known, so they stay pickable.
    public func status(of track: SingAlongTrack, requests: SongRequestWindow?) -> SingAlongTrackStatus? {
        if let nowPlaying, track.matches(title: nowPlaying.title, artist: nowPlaying.artist) { return .playingNow }
        if let nowPlaying, nowPlaying.upNext.contains(where: { track.matches(title: $0.title, artist: $0.artist) }) {
            return .upNext
        }
        guard let requests else { return nil }
        let open = { (request: SongRequest) in
            request.kind == .song && request.state.isOpen && track.matches(title: request.title, artist: request.artist)
        }
        if requests.mine.contains(where: open) { return .requested }
        if requests.queue.contains(where: open) { return .inQueue }
        return nil
    }

    /// The playlist's songs a search finds, A to Z by title (a shuffled night has no order worth keeping).
    public func pickableTracks(matching search: String = "") -> [SingAlongTrack] {
        (playlist?.tracks(matching: search) ?? []).sorted {
            $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }
}

/// How sing-along compares song names: lowercased, without accents, apostrophes or punctuation.
public enum SingAlongText {
    public static func key(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "\u{2019}", with: "")
        let parts = folded.unicodeScalars.split { !CharacterSet.alphanumerics.contains($0) }
        return parts.map { String(String.UnicodeScalarView($0)) }.joined(separator: " ")
    }
}

extension Queries {
    static let singAlongTypes = ["Event", "IKaraokeNight", "Venue", "IVenueMusic", "EquipmentTrack"]

    static let nowPlayingFields = "title artist album artworkUrl reportedAt expiresAt upNext { title artist }"

    static func singAlong(_ shape: SchemaShape) -> String {
        let karaoke = shape.has("IKaraokeNight", "singAlong") ? " karaoke { singAlong providerName }" : ""
        let playlist = shape.has("Event", "playlist")
            ? " playlist { provider shuffle url uri tracks { title artist durationMs uri } }" : ""
        let music = shape.has("IVenueMusic", "nowPlaying") ? " music { nowPlaying { \(nowPlayingFields) } }" : ""
        return """
        query SingAlong($id: ID!) {
          events { event(id: $id) { id\(karaoke)\(playlist) venue { venue { id name\(music) } } } }
        }
        """
    }

    static func nowPlaying(_ shape: SchemaShape) -> String {
        guard shape.has("IVenueMusic", "nowPlaying") else { return "query NowPlaying($id: ID!) { node(id: $id) { id } }" }
        return """
        query NowPlaying($id: ID!) {
          node(id: $id) { ... on Venue { music { nowPlaying { \(nowPlayingFields) } } } }
        }
        """
    }
}

struct SingAlongResponse: Decodable, Sendable {
    struct Karaoke: Decodable, Sendable { var singAlong: Bool?; var providerName: String? }
    struct Music: Decodable, Sendable { var nowPlaying: Lenient<NowPlaying>? }
    struct Venue: Decodable, Sendable { var id: String; var name: String?; var music: Music? }
    struct Where: Decodable, Sendable { var venue: Venue? }
    struct Event: Decodable, Sendable {
        var id: String
        var karaoke: Karaoke?
        var playlist: Lenient<SingAlongPlaylist>?
        var venue: Where?
    }
    struct Mixin: Decodable, Sendable { var event: Event? }
    var events: Mixin?

    func night(now: Date) -> SingAlongNight? {
        guard let event = events?.event else { return nil }
        let venue = event.venue?.venue
        return SingAlongNight(eventID: event.id, isSingAlong: event.karaoke?.singAlong ?? false,
                              providerName: event.karaoke?.providerName, playlist: event.playlist?.value,
                              venueID: venue?.id, venueName: venue?.name,
                              nowPlaying: venue?.music?.nowPlaying?.value.flatMap { $0.isFresh(at: now) ? $0 : nil })
    }
}

struct NowPlayingResponse: Decodable, Sendable {
    struct Music: Decodable, Sendable { var nowPlaying: Lenient<NowPlaying>? }
    struct Venue: Decodable, Sendable { var music: Music? }
    var node: Venue?
}

extension AudienceSession {
    /// An event's sing-along: whether it is one, its playlist and its venue's rotation. Nil for an unknown event. On
    /// an API without sing-along it reads as not a sing-along.
    public func singAlong(eventID: String, now: Date = Date()) async throws -> SingAlongNight? {
        try await graphQL(types: Queries.singAlongTypes, variables: ["id": .string(eventID)],
                          operationName: "SingAlong", as: SingAlongResponse.self,
                          document: Queries.singAlong).night(now: now)
    }

    /// A venue's rotation right now, for refreshing a sing-along card while it's on screen: nil when its player
    /// hasn't reported or the report went stale.
    public func nowPlaying(venueID: String, now: Date = Date()) async throws -> NowPlaying? {
        let response = try await graphQL(types: Queries.singAlongTypes, variables: ["id": .string(venueID)],
                                         operationName: "NowPlaying", as: NowPlayingResponse.self,
                                         document: Queries.nowPlaying)
        return response.node?.music?.nowPlaying?.value.flatMap { $0.isFresh(at: now) ? $0 : nil }
    }
}
