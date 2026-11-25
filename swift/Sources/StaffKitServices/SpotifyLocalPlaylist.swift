import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A Spotify playlist's or album's songs read by the venue's own Mac (Rick, 2026-11-22: "read in the playlist from
/// spotify locally to pre-cache the songs"), for a playlist AudienceKit's Spotify account can't read: one someone else
/// owns, which Spotify refuses to every app in development mode. The Mac reads Spotify's public player page for it,
/// the one Spotify's own embeds show, which lists its songs in order (the first hundred), then hands them to the API
/// (`reportEventPlaylistTracks`) so the lineup has them and their lyric timing is fetched before the night.
public enum SpotifyLocalPlaylist {
    /// Spotify's public player page for a playlist or album URI; nil for anything else.
    public static func pageURL(for uri: String) -> URL? {
        guard let uri = SpotifyLink.uri(uri) else { return nil }
        let parts = uri.split(separator: ":")
        guard parts.count == 3, parts[1] == "playlist" || parts[1] == "album" else { return nil }
        return URL(string: "https://open.spotify.com/embed/\(parts[1])/\(parts[2])")
    }

    /// The songs the page lists, in order, each once; nil when the page doesn't hold a list (Spotify changed it, or it
    /// isn't a player page).
    public static func tracks(fromPage html: String) -> [PlaylistTrack]? {
        let opening = "<script id=\"__NEXT_DATA__\" type=\"application/json\">"
        guard let start = html.range(of: opening),
              let end = html.range(of: "</script>", range: start.upperBound..<html.endIndex),
              let data = String(html[start.upperBound..<end.lowerBound]).data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let props = root["props"] as? [String: Any], let page = props["pageProps"] as? [String: Any],
              let state = page["state"] as? [String: Any], let found = state["data"] as? [String: Any],
              let entity = found["entity"] as? [String: Any], let list = entity["trackList"] as? [[String: Any]]
        else { return nil }
        var seen = Set<String>()
        return list.compactMap { item -> PlaylistTrack? in
            guard let uri = item["uri"] as? String, uri.hasPrefix("spotify:track:"), seen.insert(uri).inserted,
                  let title = item["title"] as? String, !title.isEmpty else { return nil }
            let artist = (item["subtitle"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            return PlaylistTrack(uri: uri, title: title, artist: artist, durationMs: item["duration"] as? Int)
        }
    }

    /// Reads the playlist's songs from Spotify on this device; nil when it can't (offline, refused, or no list).
    public static func tracks(uri: String, transport: HTTPTransport? = nil) async -> [PlaylistTrack]? {
        guard let url = pageURL(for: uri) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await (transport ?? { try await URLSession.shared.data(for: $0) })(request)
            guard (response as? HTTPURLResponse)?.statusCode == 200, let html = String(data: data, encoding: .utf8)
            else { return nil }
            return tracks(fromPage: html).flatMap { $0.isEmpty ? nil : $0 }
        } catch {
            return nil
        }
    }
}

extension VenueManagementClient {
    /// Hands an event's playlist songs, as this Mac read them from Spotify, to the API (`reportEventPlaylistTracks`):
    /// they become the event's lineup songs and their lyric timing is fetched ahead. Returns how many the event holds.
    /// Only a venue device with the music permission, for an event at its venue.
    @discardableResult
    public func reportEventPlaylistTracks(eventID: String, tracks: [PlaylistTrack]) async throws -> Int {
        struct Payload: Decodable, Sendable { let songs: Int }
        struct Response: Decodable, Sendable { let reportEventPlaylistTracks: Payload }
        let songs: [GraphQLValue] = tracks.prefix(500).map { track in
            var fields: [String: GraphQLValue] = ["uri": .string(track.uri), "title": .string(track.title)]
            if let artist = track.artist { fields["artist"] = .string(artist) }
            if let duration = track.durationMs { fields["durationMs"] = .int(duration) }
            return .object(fields)
        }
        return try await session.graphQL("""
            mutation VelvetEventPlaylistTracks($eventId: ID!, $tracks: [PlaylistTrackInput!]!) {
              reportEventPlaylistTracks(input: { eventId: $eventId, tracks: $tracks }) { songs }
            }
            """, variables: ["eventId": .string(eventID), "tracks": .array(songs)],
            as: Response.self).reportEventPlaylistTracks.songs
    }
}
