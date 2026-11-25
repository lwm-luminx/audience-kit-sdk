import Foundation

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
