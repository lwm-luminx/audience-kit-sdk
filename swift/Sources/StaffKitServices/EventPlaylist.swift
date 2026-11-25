import Foundation

/// A Spotify link a host pastes, as the `spotify:` URI the Spotify app plays: a share link
/// (`https://open.spotify.com/playlist/…?si=…`, with or without `intl-xx/`) or a URI already (`spotify:track:…`).
/// Tracks, playlists, albums and artists; nil for anything else, so only a plain URI ever reaches Apple Events.
public enum SpotifyLink {
    public static let kinds: Set<String> = ["track", "playlist", "album", "artist"]

    public static func uri(_ text: String) -> String? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var parts: [String]
        if text.lowercased().hasPrefix("spotify:") {
            parts = text.split(separator: ":").map(String.init)
            parts.removeFirst()
        } else if let url = URL(string: text), let host = url.host?.lowercased(),
                  host == "open.spotify.com" || host == "play.spotify.com" {
            parts = url.pathComponents.filter { $0 != "/" }
            if let first = parts.first, first.lowercased().hasPrefix("intl-") { parts.removeFirst() }
        } else {
            return nil
        }
        guard parts.count >= 2 else { return nil }
        let kind = parts[0].lowercased(), id = parts[1]
        guard kinds.contains(kind), (10...40).contains(id.count),
              id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return nil }
        return "spotify:\(kind):\(id)"
    }
}

/// An event's playlist (`Event.playlist`, copied from its series): what the venue's Mac plays in Spotify while the
/// event runs, shuffled by default so the night doesn't sound the same every week, and whether the screens show the
/// lyrics meanwhile, which comes from the event (a sing-along night is karaoke with the sing_along provider).
public struct EventPlaylist: Codable, Sendable, Equatable, Hashable {
    public var url: String
    public var uri: String?
    public var provider: String
    public var shuffle: Bool
    /// Set from the event's karaoke, not the playlist; false until then.
    public var singAlong: Bool

    private enum CodingKeys: String, CodingKey { case url, uri, provider, shuffle, singAlong }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        url = try container.decode(String.self, forKey: .url)
        uri = try container.decodeIfPresent(String.self, forKey: .uri)
        provider = try container.decodeIfPresent(String.self, forKey: .provider) ?? "spotify"
        shuffle = try container.decodeIfPresent(Bool.self, forKey: .shuffle) ?? true
        singAlong = try container.decodeIfPresent(Bool.self, forKey: .singAlong) ?? false
    }

    public init(url: String, uri: String? = nil, provider: String = "spotify", shuffle: Bool = true, singAlong: Bool = true) {
        self.url = url; self.uri = uri; self.provider = provider; self.shuffle = shuffle; self.singAlong = singAlong
    }

    /// What Spotify plays: the API's URI, else one made from the link; nil when it isn't Spotify's.
    public var playable: String? { uri.flatMap(SpotifyLink.uri) ?? SpotifyLink.uri(url) }
}

extension EventPlaylist {
    /// The event under way now that has a playlist the Mac can play: started, not canceled and not over (four hours
    /// from its start when it has no end); the one that started last when they overlap.
    public static func running(_ events: [VenueEvent], playlists: [String: EventPlaylist],
                               at now: Date = Date()) -> (event: VenueEvent, playlist: EventPlaylist)? {
        events
            .compactMap { event -> (event: VenueEvent, playlist: EventPlaylist, start: Date)? in
                guard !event.isCanceled, let start = event.start, start <= now,
                      let playlist = playlists[event.id], playlist.playable != nil else { return nil }
                let end = parseInstant(event.endAt) ?? start.addingTimeInterval(4 * 3600)
                return now < end ? (event, playlist, start) : nil
            }
            .max { $0.start < $1.start }
            .map { ($0.event, $0.playlist) }
    }
}
