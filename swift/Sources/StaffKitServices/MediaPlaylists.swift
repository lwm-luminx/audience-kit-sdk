import Foundation
import AudienceCore

/// A playlist the audience keeps in AudienceKit (`Audience.media.playlists`: nights' Spotify playlists and curated
/// lists), for Velvet Display to pick one and play it.
public struct MediaPlaylistSummary: Decodable, Sendable, Equatable, Identifiable, Hashable {
    public var id: String
    public var title: String
    public var kind: String
    public var itemCount: Int
    public var shuffle: Bool
    /// Its Spotify page, which Spotify plays; nil for a playlist that isn't on Spotify.
    public var spotifyUrl: String?
    public var url: String?

    public init(id: String, title: String, kind: String = "PLAYLIST", itemCount: Int = 0, shuffle: Bool = true,
                spotifyUrl: String? = nil, url: String? = nil) {
        self.id = id
        self.title = title
        self.kind = kind
        self.itemCount = itemCount
        self.shuffle = shuffle
        self.spotifyUrl = spotifyUrl
        self.url = url
    }

    /// The link Spotify plays: its Spotify page, else its own link when that's Spotify's.
    public var spotifyLink: String? {
        if let spotifyUrl, !spotifyUrl.isEmpty { return spotifyUrl }
        if let url, url.contains("open.spotify.com") || url.hasPrefix("spotify:") { return url }
        return nil
    }
}

extension VenueManagementClient {
    /// The audience's playlists and albums, by title, that Spotify can play.
    public func mediaPlaylists() async throws -> [MediaPlaylistSummary] {
        struct Media: Decodable, Sendable { let playlists: [MediaPlaylistSummary] }
        struct Response: Decodable, Sendable { let media: Media }
        let found = try await session.graphQL("""
            query VelvetMediaPlaylists { media { playlists(kinds: [PLAYLIST, ALBUM]) { \
            id title kind itemCount shuffle spotifyUrl url } } }
            """, variables: [:], as: Response.self).media.playlists
        return found.filter { $0.spotifyLink != nil }
    }
}

// MARK: - YouTube tracks and their licenses

/// Where gathering a song's license stands (`MediaItem.licenseStatus`). Many queer artists release a song only on
/// YouTube, with no ISRC for a venue's music service or PRO license to cover, so its rights are asked for directly.
public enum MediaLicenseStatus: String, Codable, Sendable, CaseIterable, Hashable {
    case needed = "NEEDED"
    case requested = "REQUESTED"
    case granted = "GRANTED"
    case declined = "DECLINED"
    case notNeeded = "NOT_NEEDED"

    public var label: String {
        switch self {
        case .needed: "License needed"
        case .requested: "License requested"
        case .granted: "Licensed"
        case .declined: "License declined"
        case .notNeeded: "No license needed"
        }
    }
}

/// A track in an audience playlist: a Spotify recording, or a YouTube video of a song, with where its license stands.
public struct MediaTrack: Decodable, Sendable, Equatable, Identifiable, Hashable {
    public var id: String
    public var kind: String
    public var title: String
    public var artists: String?
    public var spotifyUrl: String?
    public var youtubeUrl: String?
    public var youtubeChannel: String?
    /// On YouTube with no Spotify track or ISRC: its rights are gathered directly.
    public var youtubeOnly: Bool
    /// Who holds its rights, as best known (a YouTube video starts with its channel).
    public var studio: String?
    public var licenseStatus: MediaLicenseStatus?
    public var licenseNote: String?

    public init(id: String, kind: String = "MUSIC_VIDEO", title: String, artists: String? = nil,
                spotifyUrl: String? = nil, youtubeUrl: String? = nil, youtubeChannel: String? = nil,
                youtubeOnly: Bool = false, studio: String? = nil, licenseStatus: MediaLicenseStatus? = nil,
                licenseNote: String? = nil) {
        self.id = id
        self.kind = kind
        self.title = title
        self.artists = artists
        self.spotifyUrl = spotifyUrl
        self.youtubeUrl = youtubeUrl
        self.youtubeChannel = youtubeChannel
        self.youtubeOnly = youtubeOnly
        self.studio = studio
        self.licenseStatus = licenseStatus
        self.licenseNote = licenseNote
    }

    /// Who to ask for its rights: the rights holder, else the channel that posted it.
    public var rightsHolder: String? { studio ?? youtubeChannel }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        kind = try c.decode(String.self, forKey: .kind)
        title = try c.decode(String.self, forKey: .title)
        artists = try c.decodeIfPresent(String.self, forKey: .artists)
        spotifyUrl = try c.decodeIfPresent(String.self, forKey: .spotifyUrl)
        youtubeUrl = try c.decodeIfPresent(String.self, forKey: .youtubeUrl)
        youtubeChannel = try c.decodeIfPresent(String.self, forKey: .youtubeChannel)
        youtubeOnly = try c.decodeIfPresent(Bool.self, forKey: .youtubeOnly) ?? false
        studio = try c.decodeIfPresent(String.self, forKey: .studio)
        // A status this build doesn't know yet reads as untracked rather than failing the list.
        licenseStatus = (try? c.decodeIfPresent(String.self, forKey: .licenseStatus)).flatMap { $0 }
            .flatMap(MediaLicenseStatus.init(rawValue:))
        licenseNote = try c.decodeIfPresent(String.self, forKey: .licenseNote)
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, title, artists, spotifyUrl, youtubeUrl, youtubeChannel, youtubeOnly, studio, licenseStatus,
             licenseNote
    }

    static let fields = "id kind title artists spotifyUrl youtubeUrl youtubeChannel youtubeOnly studio licenseStatus licenseNote"
}

/// What adding links to a playlist did.
public struct MediaPlaylistLinksResult: Decodable, Sendable, Equatable {
    /// How many tracks went in that it didn't have.
    public var added: Int
    /// The tracks the links name, in order.
    public var items: [MediaTrack]
}

extension VenueManagementClient {
    /// A playlist's tracks in order, with their YouTube links and license status.
    public func mediaPlaylistTracks(playlistID: String) async throws -> [MediaTrack] {
        struct Media: Decodable, Sendable { let items: [MediaTrack] }
        struct Response: Decodable, Sendable { let media: Media }
        return try await session.graphQL("""
            query MediaPlaylistTracks($id: ID!) { media { items(playlistId: $id, includeHidden: true) { \
            \(MediaTrack.fields) } } }
            """, variables: ["id": .string(playlistID)], as: Response.self).media.items
    }

    /// Adds YouTube videos or Spotify tracks to a playlist of the audience's own from their links, at the end or at
    /// `position` (1 is first). A video goes in as a music video of its song, named from YouTube's title and channel;
    /// one released only on YouTube starts with its license needed. `title` names a single video YouTube can't
    /// describe (private or removed). A playlist that syncs from Spotify is refused: its next sync would take them out.
    @discardableResult
    public func addMediaPlaylistLinks(playlistID: String, links: [String], position: Int? = nil,
                                      title: String? = nil) async throws -> MediaPlaylistLinksResult {
        struct Response: Decodable, Sendable { let addMediaPlaylistLinks: MediaPlaylistLinksResult }
        var variables: [String: GraphQLValue] = ["playlistId": .string(playlistID), "links": .array(links.map { .string($0) })]
        if let position { variables["position"] = .int(position) }
        if let title { variables["title"] = .string(title) }
        return try await session.graphQL("""
            mutation AddMediaPlaylistLinks($playlistId: ID!, $links: [String!]!, $position: Int, $title: String) { \
            addMediaPlaylistLinks(input: { playlistId: $playlistId, links: $links, position: $position, \
            title: $title }) { added items { \(MediaTrack.fields) } } }
            """, variables: variables, as: Response.self).addMediaPlaylistLinks
    }

    /// The audience's tracks whose license stands so (default: needed and requested), to gather.
    public func mediaLicenses(_ statuses: [MediaLicenseStatus] = [.needed, .requested]) async throws -> [MediaTrack] {
        struct Media: Decodable, Sendable { let items: [MediaTrack] }
        struct Response: Decodable, Sendable { let media: Media }
        return try await session.graphQL("""
            query MediaLicenses($statuses: [MediaLicenseStatus!]) { media { \
            items(licenseStatuses: $statuses, includeHidden: true, first: 2000) { \(MediaTrack.fields) } } }
            """, variables: ["statuses": .array(statuses.map { .string($0.rawValue) })], as: Response.self).media.items
    }

    /// Records where gathering a track's license stands (nil stops tracking it), who holds its rights and a note.
    @discardableResult
    public func setMediaLicense(itemID: String, status: MediaLicenseStatus?, rightsHolder: String? = nil,
                                note: String? = nil) async throws -> MediaTrack {
        struct Saved: Decodable, Sendable { let item: MediaTrack }
        struct Response: Decodable, Sendable { let saveMediaItem: Saved }
        var item: [String: GraphQLValue] = ["licenseStatus": status.map { .string($0.rawValue) } ?? .null]
        if let rightsHolder { item["studio"] = .string(rightsHolder) }
        if let note { item["licenseNote"] = .string(note) }
        return try await session.graphQL("""
            mutation SetMediaLicense($id: ID!, $item: MediaItemInput!) { saveMediaItem(input: { id: $id, item: $item }) \
            { item { \(MediaTrack.fields) } } }
            """, variables: ["id": .string(itemID), "item": .object(item)], as: Response.self).saveMediaItem.item
    }
}
