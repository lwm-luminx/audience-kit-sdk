import AudienceCore
import Foundation

// The Spotify bridge (audience_kit_api doc/SPOTIFY_BRIDGE.md): songs cross from a person's own Spotify to a venue as
// requests, and a venue's set list goes back out to people's own Spotify as a public playlist. Nobody signs in to
// Spotify for any of it, and Spotify only ever plays on the person's own account. Show Spotify's name and a link back
// with anything from Spotify, and never crop its artwork.

/// A Spotify link someone shared or pasted, read without signing in to Spotify.
public struct SpotifyLink: Codable, Sendable, Hashable, Identifiable {
    public enum Kind: String, Codable, Sendable { case track, playlist, album, artist }

    public let kind: Kind
    /// Spotify's ID for it.
    public let id: String
    /// The song, playlist, album or artist name; nil when Spotify didn't answer.
    public let title: String?
    /// A song's artists, comma separated.
    public let artist: String?
    /// Spotify's artwork for it.
    public let thumbnailUrl: URL?
    /// Its Spotify URI (`spotify:track:<id>`), which the Spotify app opens.
    public let uri: String
    /// Its open.spotify.com link.
    public let url: URL
    /// Spotify's embed player, to show a playlist or album so the person can pick one song from it.
    public let embedUrl: URL

    /// Whether it's one song, which can be asked for as a request.
    public var isSong: Bool { kind == .track }

    public init(kind: Kind, id: String, title: String? = nil, artist: String? = nil, thumbnailUrl: URL? = nil,
                uri: String, url: URL, embedUrl: URL) {
        self.kind = kind
        self.id = id
        self.title = title
        self.artist = artist
        self.thumbnailUrl = thumbnailUrl
        self.uri = uri
        self.url = url
        self.embedUrl = embedUrl
    }

    /// The first Spotify link in shared text ("Listen on Spotify: https://open.spotify.com/track/…"), or nil. A quick
    /// local check before asking the API; the API reads short links and everything else.
    public static func firstLink(in text: String) -> String? {
        let pattern = #"(https?://(open\.spotify\.com|spotify\.link|spotify\.app\.link)/\S+|spotify:(track|playlist|album|artist):[A-Za-z0-9]+)"#
        guard let range = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else { return nil }
        return String(text[range])
    }
}

/// A night's set list on Spotify: a public playlist in the venue's account, for people to open in their own Spotify
/// (save it, add songs to their own playlists, or listen to rehearse). For personal listening only.
public struct EventSetList: Codable, Sendable, Hashable {
    /// Its Spotify URI (`spotify:playlist:<id>`), which the Spotify app opens.
    public let spotifyUri: String
    /// Its open.spotify.com link.
    public let spotifyUrl: URL
    /// How many songs it held at the last mirror.
    public let songCount: Int?
    public let syncedAt: Date?

    public init(spotifyUri: String, spotifyUrl: URL, songCount: Int? = nil, syncedAt: Date? = nil) {
        self.spotifyUri = spotifyUri
        self.spotifyUrl = spotifyUrl
        self.songCount = songCount
        self.syncedAt = syncedAt
    }
}

extension Queries {
    static let spotifyLink = """
    query SpotifyLink($url: String!) {
      spotifyLink(url: $url) { kind id title artist thumbnailUrl uri url embedUrl }
    }
    """

    static let eventSetList = """
    query EventSetList($id: ID!) {
      events { event(id: $id) { id setList { spotifyUri spotifyUrl songCount syncedAt } } }
    }
    """

    static let requestSongFromSpotify = """
    mutation RequestSongFromSpotify($venueId: ID!, $spotifyUrl: String!, $title: String, $note: String) {
      requestSong(input: { venueId: $venueId, kind: SONG, spotifyUrl: $spotifyUrl, title: $title, note: $note }) {
        request { \(songRequestFields) }
      }
    }
    """
}

struct SpotifyLinkResponse: Decodable, Sendable { var spotifyLink: SpotifyLink? }

struct EventSetListResponse: Decodable, Sendable {
    struct Event: Decodable, Sendable { var id: String; var setList: EventSetList? }
    struct Mixin: Decodable, Sendable { var event: Event? }
    var events: Mixin?
}

extension AudienceSession {
    /// What a shared or pasted Spotify link names, with its name and artwork; nil when it isn't a Spotify link, or on
    /// an API from before the bridge.
    public func spotifyLink(url: String) async throws -> SpotifyLink? {
        do {
            return try await graphQL(Queries.spotifyLink, variables: ["url": .string(url)],
                                     operationName: "SpotifyLink", as: SpotifyLinkResponse.self).spotifyLink
        } catch let error as AudienceKitError where error.code == "undefinedField" {
            return nil
        }
    }

    /// Asks the venue to play a song shared from Spotify: the link fills in its name and artists, and the request
    /// keeps the Spotify song. Only one song, not a playlist or album; the same rules as
    /// ``requestSong(venueID:title:artist:note:)`` otherwise. `title` replaces Spotify's name when given.
    @discardableResult
    public func requestSong(venueID: String, spotifyURL: String, title: String? = nil, note: String? = nil)
        async throws -> SongRequest {
        var variables: [String: GraphQLValue] = ["venueId": .string(venueID), "spotifyUrl": .string(spotifyURL)]
        if let title, !title.isEmpty { variables["title"] = .string(title) }
        if let note, !note.isEmpty { variables["note"] = .string(note) }
        return try await graphQL(Queries.requestSongFromSpotify, variables: variables,
                                 operationName: "RequestSongFromSpotify", as: RequestSongResponse.self)
            .requestSong.request
    }

    /// An event's set list on Spotify, for a Listen in Spotify button; nil until the venue mirrors it, or on an API
    /// from before the bridge.
    public func setList(eventID: String) async throws -> EventSetList? {
        do {
            return try await graphQL(Queries.eventSetList, variables: ["id": .string(eventID)],
                                     operationName: "EventSetList", as: EventSetListResponse.self).events?.event?.setList
        } catch let error as AudienceKitError where error.code == "undefinedField" {
            return nil
        }
    }
}
