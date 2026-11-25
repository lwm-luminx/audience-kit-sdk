import AudienceCore
import StaffKitCore
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A venue's TV slogan settings: whether its marquee (AirPlay, Chromecast and the web sign) rotates standard posters
/// (slogan slides) in between looks at tonight's lineup, whether it's flagged for adult content, which lets the
/// adult-venue posters in, which of the posters it turned off one by one, and the posters themselves: its audience's
/// own set plus AudienceKit's (`Venue.marqueePosters`), never another audience's. Slides are on unless the venue turns
/// them off, and a new poster shows until the venue turns it off.
public struct VenueMarqueeSettings: Decodable, Sendable, Equatable {
    public var marqueeSlogans: Bool
    public var adultVenue: Bool
    /// The posters (by `MarqueeSlide.id`) the venue turned off (`Venue.marqueeHiddenSlogans`); empty from a server
    /// from before the choice.
    public var hiddenSlogans: [String]
    /// The posters its TV may show, the turned-off ones included (for the picker); empty from a server from before
    /// posters were kept per audience, so a TV then shows none rather than another audience's.
    public var posters: [MarqueeSlide]

    public init(marqueeSlogans: Bool, adultVenue: Bool, hiddenSlogans: [String] = [], posters: [MarqueeSlide] = []) {
        self.marqueeSlogans = marqueeSlogans; self.adultVenue = adultVenue; self.hiddenSlogans = hiddenSlogans
        self.posters = posters
    }

    private enum CodingKeys: String, CodingKey { case marqueeSlogans, adultVenue, marqueeHiddenSlogans, marqueePosters }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        marqueeSlogans = try container.decode(Bool.self, forKey: .marqueeSlogans)
        adultVenue = try container.decode(Bool.self, forKey: .adultVenue)
        hiddenSlogans = try container.decodeIfPresent([String].self, forKey: .marqueeHiddenSlogans) ?? []
        posters = try container.decodeIfPresent([MarqueeSlide].self, forKey: .marqueePosters) ?? []
    }

    /// The posters its TV shows now (`MarqueeSlide.showing`).
    public var showing: [MarqueeSlide] { MarqueeSlide.showing(posters, for: self) }
}

/// One standard poster (slogan slide): a 16:9 picture with its own code, from the venue's audience's set or
/// AudienceKit's (`Venue.marqueePosters`, MarqueePoster in the API).
public struct MarqueeSlide: Decodable, Sendable, Equatable, Identifiable {
    public let id: String
    /// An adult-venue line: shown only where the venue is flagged for adult content.
    public let adult: Bool
    /// Its picture's path on hotmess.social.
    public let image: String

    public init(id: String, adult: Bool, image: String) {
        self.id = id; self.adult = adult; self.image = image
    }

    /// Its picture's address (the API gives it whole; a path is read on hotmess.social, as older slides had).
    public var url: URL? { URL(string: image, relativeTo: MarqueeSlide.site)?.absoluteURL }

    static let site = URL(string: "https://hotmess.social/")!
    /// How long the TV shows the lineup before a slide, and how long the slide stays up, as the web sign does.
    public static let boardSeconds: Double = 45
    public static let slideSeconds: Double = 12

    /// The slides a venue's TV shows: none with them off, the adult-venue ones only where the venue is flagged, and
    /// none it turned off.
    public static func showing(_ slides: [MarqueeSlide], for settings: VenueMarqueeSettings?) -> [MarqueeSlide] {
        guard let settings, settings.marqueeSlogans else { return [] }
        let hidden = Set(settings.hiddenSlogans)
        return choices(slides, adultVenue: settings.adultVenue).filter { !hidden.contains($0.id) }
    }

    /// The slides a venue picks from: every one, the adult-venue ones only where the venue is flagged.
    public static func choices(_ slides: [MarqueeSlide], adultVenue: Bool) -> [MarqueeSlide] {
        slides.filter { adultVenue || !$0.adult }
    }
}

extension VenueManagementClient {
    /// The venue's TV slogan settings, with its audience's posters and the ones it turned off where the server keeps
    /// them (an older one answers without, and the TV then shows no posters).
    public func marqueeSettings(venueID: String) async throws -> VenueMarqueeSettings {
        struct Venues: Decodable, Sendable { let venue: VenueMarqueeSettings? }
        struct Response: Decodable, Sendable { let venues: Venues }
        let variables: [String: GraphQLValue] = ["id": .string(venueID)]
        let response: Response
        do {
            response = try await session.graphQL("""
                query VelvetMarqueePosters($id: ID!) { venues { venue(id: $id) { marqueeSlogans adultVenue marqueeHiddenSlogans marqueePosters { id image adult } } } }
                """, variables: variables, as: Response.self)
        } catch {
            response = try await session.graphQL("""
                query VelvetMarqueeSettings($id: ID!) { venues { venue(id: $id) { marqueeSlogans adultVenue } } }
                """, variables: variables, as: Response.self)
        }
        guard let settings = response.venues.venue else { throw AudienceKitError.notFound }
        return settings
    }

    /// The venue's safety poster link (`<web app>/help/<code>`), which lets anyone there tell its staff on shift they
    /// feel unsafe, with or without the app; nil until a manager prints the poster, which is how a venue opts in. Its
    /// managers and every Velvet device of the venue may read it.
    public func safetyPosterLink(venueID: String) async throws -> URL? {
        struct Poster: Decodable, Sendable { let url: String }
        struct Venue: Decodable, Sendable { let safetyPoster: Poster? }
        struct Venues: Decodable, Sendable { let venue: Venue? }
        struct Response: Decodable, Sendable { let venues: Venues }
        let response = try await session.graphQL("""
            query VelvetSafetyPoster($id: ID!) { venues { venue(id: $id) { safetyPoster { url } } } }
            """, variables: ["id": .string(venueID)], as: Response.self)
        return response.venues.venue?.safetyPoster.flatMap { URL(string: $0.url) }
    }

    /// Changes the venue's TV slogan settings; nil leaves one as it is. `hiddenSlogans` replaces the slides the venue
    /// turned off (empty shows them all). Venue managers may.
    public func setMarqueeSettings(venueID: String, marqueeSlogans: Bool? = nil, adultVenue: Bool? = nil,
                                   hiddenSlogans: [String]? = nil) async throws -> VenueMarqueeSettings {
        struct Payload: Decodable, Sendable { let venue: VenueMarqueeSettings }
        struct Response: Decodable, Sendable { let updateVenue: Payload }
        var fields: [String: GraphQLValue] = [:]
        if let marqueeSlogans { fields["marqueeSlogans"] = .bool(marqueeSlogans) }
        if let adultVenue { fields["adultVenue"] = .bool(adultVenue) }
        if let hiddenSlogans { fields["marqueeHiddenSlogans"] = .array(hiddenSlogans.map { .string($0) }) }
        let variables: [String: GraphQLValue] = ["input": .object(["id": .string(venueID), "venue": .object(fields)])]
        // The hidden slides only when changing them, so a server from before the choice still takes the rest.
        guard hiddenSlogans != nil else {
            return try await session.graphQL("""
                mutation VelvetMarqueeSettings($input: VenueUpdateInput!) {
                  updateVenue(input: $input) { venue { marqueeSlogans adultVenue } }
                }
                """, variables: variables, as: Response.self).updateVenue.venue
        }
        return try await session.graphQL("""
            mutation VelvetMarqueeChoices($input: VenueUpdateInput!) {
              updateVenue(input: $input) { venue { marqueeSlogans adultVenue marqueeHiddenSlogans } }
            }
            """, variables: variables,
            as: Response.self).updateVenue.venue
    }
}

/// The song playing at a venue, as the API keeps it (`Venue.music.nowPlaying`): reported by a Velvet device whose code
/// has the music permission (Velvet Display reading Spotify on the Mac) or by music equipment, for a couple of minutes
/// per report.
public struct VenueNowPlaying: Decodable, Sendable, Equatable {
    public let title: String
    public let artist: String?
    public let album: String?
    public let artworkUrl: String?
    public let source: String?
    /// The songs coming next, when the player knows them (Velvet Display shuffling a night itself).
    public let upNext: [UpNextSong]?
    /// The song's Spotify URI (`spotify:track:…`), so the lineup and the sing-along know exactly which song it is.
    public var trackUri: String?
    /// How far into the song the player is, in milliseconds, and whether it's playing (false: paused there): the
    /// venue's other screens run the sing-along's lyrics from it.
    public var positionMs: Int?
    public var playing: Bool?

    public init(title: String, artist: String? = nil, album: String? = nil, artworkUrl: String? = nil,
                source: String? = nil, upNext: [UpNextSong]? = nil, trackUri: String? = nil, positionMs: Int? = nil,
                playing: Bool? = nil) {
        self.title = title; self.artist = artist; self.album = album; self.artworkUrl = artworkUrl; self.source = source
        self.upNext = upNext; self.trackUri = trackUri; self.positionMs = positionMs; self.playing = playing
    }
}

extension VenueManagementClient {
    /// How often a device reports the same song again while it plays: well inside the two minutes a report lasts.
    public static let nowPlayingInterval: Double = 60

    /// Reports the song playing at this device's venue (`reportNowPlaying`), or nil for nothing playing. Only a venue
    /// device whose code has the music permission may; the report lasts two minutes, so send it again while the song
    /// plays (`nowPlayingInterval`).
    @discardableResult
    public func reportNowPlaying(_ song: VenueNowPlaying?) async throws -> VenueNowPlaying? {
        struct Payload: Decodable, Sendable { let nowPlaying: VenueNowPlaying? }
        struct Response: Decodable, Sendable { let reportNowPlaying: Payload }
        // With where the song is, on an API that takes it; an API from before positionMs refuses the whole report, so
        // it goes again without.
        if let song, let positionMs = song.positionMs {
            var variables: [String: GraphQLValue] = [
                "title": .string(song.title), "positionMs": .int(positionMs), "playing": .bool(song.playing ?? true),
                "upNext": .array((song.upNext ?? []).prefix(10).map { next in
                    var fields: [String: GraphQLValue] = ["title": .string(next.title)]
                    if let artist = next.artist { fields["artist"] = .string(artist) }
                    return .object(fields)
                }),
            ]
            if let artist = song.artist { variables["artist"] = .string(artist) }
            if let album = song.album { variables["album"] = .string(album) }
            if let artwork = song.artworkUrl { variables["artworkUrl"] = .string(artwork) }
            if let source = song.source { variables["source"] = .string(source) }
            if let uri = song.trackUri { variables["trackUri"] = .string(uri) }
            if let reply = try? await session.graphQL("""
                mutation VelvetNowPlayingAt($title: String, $artist: String, $album: String, $artworkUrl: String, \
                $source: String, $upNext: [UpNextTrackInput!], $trackUri: String, $positionMs: Int, $playing: Boolean) {
                  reportNowPlaying(input: { title: $title, artist: $artist, album: $album, artworkUrl: $artworkUrl, \
                source: $source, upNext: $upNext, trackUri: $trackUri, positionMs: $positionMs, playing: $playing }) { \
                nowPlaying { title artist album artworkUrl source } }
                }
                """, variables: variables, as: Response.self) {
                return reply.reportNowPlaying.nowPlaying
            }
        }
        var variables: [String: GraphQLValue] = ["stopped": .bool(song == nil)]
        if let song {
            variables["title"] = .string(song.title)
            if let artist = song.artist { variables["artist"] = .string(artist) }
            if let album = song.album { variables["album"] = .string(album) }
            if let artwork = song.artworkUrl { variables["artworkUrl"] = .string(artwork) }
            if let source = song.source { variables["source"] = .string(source) }
        }
        // Up next only when there is some, so an API from before upNext still takes the report.
        if let upNext = song?.upNext, !upNext.isEmpty {
            variables["upNext"] = .array(upNext.prefix(10).map { next in
                var fields: [String: GraphQLValue] = ["title": .string(next.title)]
                if let artist = next.artist { fields["artist"] = .string(artist) }
                return .object(fields)
            })
            return try await session.graphQL("""
                mutation VelvetNowPlayingNext($title: String, $artist: String, $album: String, $artworkUrl: String, \
                $source: String, $stopped: Boolean, $upNext: [UpNextTrackInput!]) {
                  reportNowPlaying(input: { title: $title, artist: $artist, album: $album, artworkUrl: $artworkUrl, \
                source: $source, stopped: $stopped, upNext: $upNext }) { nowPlaying { title artist album artworkUrl source } }
                }
                """, variables: variables, as: Response.self).reportNowPlaying.nowPlaying
        }
        return try await session.graphQL("""
            mutation VelvetNowPlaying($title: String, $artist: String, $album: String, $artworkUrl: String, \
            $source: String, $stopped: Boolean) {
              reportNowPlaying(input: { title: $title, artist: $artist, album: $album, artworkUrl: $artworkUrl, \
            source: $source, stopped: $stopped }) { nowPlaying { title artist album artworkUrl source } }
            }
            """, variables: variables, as: Response.self).reportNowPlaying.nowPlaying
    }
}
