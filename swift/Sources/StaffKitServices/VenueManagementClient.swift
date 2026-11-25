import AudienceCore
import StaffKitCore
import Foundation

public struct VenueWorkspace: Decodable, Sendable, Identifiable {
    public struct Locale: Decodable, Sendable {
        /// Its UUID: its back-of-house room is the staff of every venue in it.
        public let id: String?
        public let name: String?
    }
    public typealias Event = VenueEvent
    public struct Door: Decodable, Sendable {
        public let night: String
        public let paidCount: Int
        public let checkedInCount: Int
        /// Covers paid and not refunded, before fees.
        public let gross: Money?
    }
    public struct SocialLink: Decodable, Sendable {
        public let provider: String
        public let handle: String
        public let url: String?
    }
    public let id: String
    public let name: String?
    public let description: String?
    public let point: String?
    public let photoUrl: String?
    public let locale: Locale
    /// Its events mixin, aliased: `upcomingEvents: events { upcoming { nodes } }`.
    private let upcomingEvents: UpcomingEvents?
    /// Its tickets mixin, read for the cover inside it: `tickets { cover { … } }`.
    private let tickets: Tickets?
    /// Its cover mixin: the door, and the hours its cover runs.
    public var cover: Cover? { tickets?.cover }
    /// Its ping mixin: `ping { count }`.
    private let ping: PingCount?
    /// Its listing profile mixin: `profile { address phone website socialLinks { nodes } }`.
    private let profile: Profile?
    /// The venue's own photo of the place.
    public let bannerUrl: String?
    /// Its banner images in the order the apps rotate through them: the ones an admin added, then its latest
    /// Instagram posts (InstagramSync). Nil from an older read.
    private let bannerPhotos: [BannerPhoto]?
    private struct BannerPhoto: Decodable, Sendable { let url: String }
    /// Its banner images' URLs, Instagram's included.
    public var bannerPhotoUrls: [String] { bannerPhotos?.map(\.url) ?? [] }
    /// How busy it is right now, approximately; managers only.
    public let activity: VenueActivity?

    private struct Tickets: Decodable, Sendable { let cover: Cover? }

    /// The part of a venue's `tickets { cover }` mixin Velvet reads with it.
    public struct Cover: Decodable, Sendable {
        public let canWorkDoor: Bool
        /// The time zone its nights, cover and events are counted in.
        public let timeZone: String?
        public let from: String?
        /// When the cover ends each night, as HH:MM.
        public let until: String?
        public let door: Door?
    }

    /// The part of a venue's or event's `ping` mixin Velvet reads: how many pinged to come tonight.
    struct PingCount: Decodable, Sendable { let count: Int? }

    /// People who pinged to come here tonight; managers of its listing only.
    public var pingCount: Int? { ping?.count }

    private struct Profile: Decodable, Sendable {
        let address: String?
        let phone: String?
        let website: String?
        let socialLinks: GraphQLNodes<SocialLink>?
    }

    /// Its street address, from Google or the researcher.
    public var address: String? { profile?.address }
    /// Its public phone number.
    public var phone: String? { profile?.phone }
    /// Its public website.
    public var website: String? { profile?.website }
    /// Its social media profiles.
    public var socialLinks: [SocialLink]? { profile?.socialLinks?.nodes }

    private struct UpcomingEvents: Decodable, Sendable { let upcoming: GraphQLNodes<Event> }
    /// Its upcoming events, soonest first.
    public var events: [Event] { upcomingEvents?.upcoming.nodes ?? [] }
    /// Whether this was read in full, with its events, door and activity, rather than for a venue list.
    public var isDetailed: Bool { upcomingEvents != nil }

    public var door: Door? { cover?.door }
    public var canWorkDoor: Bool { cover?.canWorkDoor ?? false }
    /// The time zone its nights, cover and events are counted in.
    public var coverTimeZone: String? { cover?.timeZone }
    public var coverFrom: String? { cover?.from }
    /// When the cover ends each night, as HH:MM.
    public var coverUntil: String? { cover?.until }

    public var instagram: String? { socialLinks?.first { $0.provider == "instagram" }?.handle }
    public var tiktok: String? { socialLinks?.first { $0.provider == "tiktok" }?.handle }
    /// The `socialLinks` to send to keep its links as they are except on the networks in `edits` (provider => handle
    /// or link; blank removes it): `venue.socialLinks(replacing: ["instagram": "velvet", "tiktok": ""])`.
    public func socialLinks(replacing edits: [String: String]) -> [SocialLinkInput] {
        SocialLinkInput.replacing((socialLinks ?? []).map { (provider: $0.provider, handle: $0.handle) },
                                  with: edits.mapValues { [$0] })
    }
}

/// Venue operations built on the same StaffKitCore session used by the other management apps.
public struct VenueManagementClient: Sendable {
    public let session: AudienceManagementSession
    public init(session: AudienceManagementSession) { self.session = session }

    /// The venues the signed-in device or person works. `detailed: false` reads only what a venue list shows (no
    /// events, door or activity): an admin works every venue in the audience, hundreds of them, and reading each one's
    /// upcoming events took the API past its 30 s limit. Load the open one in full with `venue(id:)`.
    public func venues(detailed: Bool = true) async throws -> [VenueWorkspace] {
        // The doors the signed-in device or person works are their viewer state: `me { cover { doorVenues } }`.
        struct Response: Decodable, Sendable {
            struct Cover: Decodable, Sendable { let doorVenues: GraphQLNodes<VenueWorkspace> }
            struct Me: Decodable, Sendable { let cover: Cover }
            let me: Me?
        }
        let query = detailed ? "query VelvetVenues { me { cover { doorVenues { nodes { \(Self.fields) } } } } }"
                             : "query VelvetVenueList { me { cover { doorVenues { nodes { \(Self.listFields) } } } } }"
        return try await session.graphQL(query, as: Response.self).me?.cover.doorVenues.nodes ?? []
    }

    /// One venue in full, with its upcoming events: what `venues(detailed: true)` reads for each.
    public func venue(id: String) async throws -> VenueWorkspace? {
        struct Response: Decodable, Sendable {
            struct Venues: Decodable, Sendable { let venue: VenueWorkspace? }
            let venues: Venues
        }
        return try await session.graphQL("query VelvetVenue($id: ID!) { venues { venue(id: $id) { \(Self.fields) } } }",
                                         variables: ["id": .string(id)], as: Response.self).venues.venue
    }

    /// The playlists of the venue's upcoming events (`Event.playlist`), by event ID, for the Mac to play in Spotify
    /// while each runs, each marked sing-along when its event is (`karaoke.singAlong`, or the sing_along facet's
    /// tag). Its own query, so the venue still loads from an API that doesn't have playlists yet.
    /// The songs of the venue's upcoming events' playlists (`Event.playlist.tracks`, from Spotify's catalog through the
    /// API), by event ID, for the Mac to shuffle a night itself. Its own query, since an API without Spotify's catalog
    /// (or before `tracks`) fails it: the Mac then leaves the shuffle to Spotify.
    public func playlistTracks(venueID: String) async throws -> [String: [PlaylistTrack]] {
        struct Response: Decodable, Sendable {
            struct Playlist: Decodable, Sendable { let tracks: [PlaylistTrack]? }
            struct Node: Decodable, Sendable { let id: String; let playlist: Playlist? }
            struct Upcoming: Decodable, Sendable { let upcoming: GraphQLNodes<Node> }
            struct Venue: Decodable, Sendable { let events: Upcoming }
            struct Venues: Decodable, Sendable { let venue: Venue? }
            let venues: Venues
        }
        let nodes = try await session.graphQL("""
            query VelvetPlaylistTracks($id: ID!) {
              venues { venue(id: $id) { events { upcoming { nodes { id playlist { tracks { uri title artist durationMs } } } } } } }
            }
            """, variables: ["id": .string(venueID)], as: Response.self).venues.venue?.events.upcoming.nodes ?? []
        return Dictionary(nodes.compactMap { node in
            node.playlist?.tracks.flatMap { $0.isEmpty ? nil : (node.id, $0) }
        }, uniquingKeysWith: { first, _ in first })
    }

    /// The pictures Velvet's screens may show behind the board, in the API's order (`Venue.screenBackdrops`): banners
    /// without text (an admin's, then Instagram's), Google's photos of the place, then flyers and other pictures that
    /// are mostly text (Rick, 2026-11-21), each with where its faces are. Its own query, so the venue still loads from
    /// an API without it; the board then falls back to the banners it reads with the venue.
    public func screenBackdrops(venueID: String) async throws -> [ScreenBackdrop] {
        struct Response: Decodable, Sendable {
            struct Venue: Decodable, Sendable { let screenBackdrops: [ScreenBackdrop] }
            struct Venues: Decodable, Sendable { let venue: Venue? }
            let venues: Venues
        }
        return try await session.graphQL("""
            query VelvetScreenBackdrops($id: ID!) {
              venues { venue(id: $id) { screenBackdrops { url source hasText focalPoint { x y } faces { x y width height } } } }
            }
            """, variables: ["id": .string(venueID)], as: Response.self).venues.venue?.screenBackdrops ?? []
    }

    /// A person's banner for a tip poster to lay type over (`Person.screenBannerUrl`): their latest Instagram post,
    /// as the API's copy with its text painted out where there is one, or nil when there's none or it's mostly text
    /// (Rick, 2026-11-23: "lets work on imported instagram photos for the tip and posters"). Its own query, so an API
    /// without the field only costs the poster its picture.
    public func screenBanner(personID: String) async throws -> String? {
        struct Response: Decodable, Sendable {
            struct Person: Decodable, Sendable { let screenBannerUrl: String? }
            let node: Person?
        }
        let url = try await session.graphQL("""
            query VelvetTipBanner($id: ID!) { node(id: $id) { ... on Person { screenBannerUrl } } }
            """, variables: ["id": .string(personID)], as: Response.self).node?.screenBannerUrl
        return url.flatMap { $0.hasPrefix("https://") ? $0 : nil }
    }

    public func eventPlaylists(venueID: String) async throws -> [String: EventPlaylist] {
        struct Response: Decodable, Sendable {
            struct Karaoke: Decodable, Sendable { let singAlong: Bool? }
            struct Tag: Decodable, Sendable { let facet: String? }
            struct Node: Decodable, Sendable { let id: String; let playlist: EventPlaylist?; let karaoke: Karaoke?; let tags: [Tag]? }
            struct Upcoming: Decodable, Sendable { let upcoming: GraphQLNodes<Node> }
            struct Venue: Decodable, Sendable { let events: Upcoming }
            struct Venues: Decodable, Sendable { let venue: Venue? }
            let venues: Venues
        }
        let nodes = try await session.graphQL("""
            query VelvetEventPlaylists($id: ID!) {
              venues { venue(id: $id) { events { upcoming { nodes { id playlist { url uri provider shuffle } karaoke { singAlong } tags { facet } } } } } }
            }
            """, variables: ["id": .string(venueID)], as: Response.self).venues.venue?.events.upcoming.nodes ?? []
        return Dictionary(nodes.compactMap { node in
            node.playlist.map { playlist in
                var playlist = playlist
                playlist.singAlong = node.karaoke?.singAlong == true || (node.tags ?? []).contains { $0.facet == "sing_along" }
                return (node.id, playlist)
            }
        }, uniquingKeysWith: { first, _ in first })
    }

    /// Sends only listing-manager editable fields; the server checks ownership on every mutation.
    /// Social links, phone and photo are left as they are when nil. `socialLinks` replaces every link the venue has,
    /// so build it with `VenueWorkspace.socialLinks(replacing:)`. A blank photo removes it, and a blank phone puts
    /// it back to Google's. `photo` is an image URL or a data: URI.
    public func updateVenue(id: String, name: String, description: String, website: String,
                            socialLinks: [SocialLinkInput]? = nil,
                            phone: String? = nil, photo: String? = nil) async throws -> VenueWorkspace {
        struct Response: Decodable, Sendable {
            struct Payload: Decodable, Sendable { let venue: VenueWorkspace }
            let updateVenue: Payload
        }
        var fields: [String: GraphQLValue] = ["name": .string(name), "description": .string(description), "website": .string(website)]
        if let socialLinks { fields["socialLinks"] = .array(socialLinks.map(\.graphQLValue)) }
        if let phone { fields["phone"] = .string(phone) }
        if let photo { fields["photo"] = .string(photo) }
        return try await session.graphQL("""
            mutation VelvetUpdateVenue($input: VenueUpdateInput!) {
              updateVenue(input: $input) { venue { \(Self.fields) } }
            }
            """, variables: ["input": .object(["id": .string(id), "venue": .object(fields)])], as: Response.self).updateVenue.venue
    }

    /// What a venue list shows: its name, photo, place and address.
    private static let listFields = "id name description point photoUrl bannerUrl locale { id name } profile { address }"

    static let fields = """
        id name description point photoUrl locale { id name }
        tickets { cover { canWorkDoor timeZone from until door { night paidCount checkedInCount gross { cents currency } } } }
        ping { count } bannerUrl bannerPhotos { url } profile { address phone website socialLinks { nodes { provider handle url } } }
        activity { pinging { atLeast label } hereLastHour { atLeast label } }
        upcomingEvents: events { upcoming { nodes { \(eventFields) } } }
        """
}
