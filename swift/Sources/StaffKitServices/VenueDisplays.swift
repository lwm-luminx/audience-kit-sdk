import Foundation
import AudienceCore
import StaffKitCore

// A venue's screens as records anyone running the venue sets (audience_kit_api doc/VENUE_DISPLAYS.md, Rick
// 2026-11-21): each screen has a ranking of screen types and shows the first that has something to show, and the
// venue's slideshows (stills, videos and an automatic upcoming-posters slot) are what its board and slideshow screens
// play. The screen follows its record over the cable (`venueDisplay`), so nobody needs its remote.

/// One of a venue's screens.
public struct StaffVenueDisplay: Codable, Sendable, Hashable, Identifiable {
    /// The screen types a ranking orders (`DisplayScreen`).
    public enum Screen: String, Codable, Sendable, CaseIterable, Identifiable {
        /// A game or sing-along while one runs: bingo's board, tonight's trivia round, the song's lyrics.
        case liveActivity = "LIVE_ACTIVITY"
        /// Tonight's lineup with the chat beside it, playing its slideshow (and photos) between looks.
        case board = "BOARD"
        /// Tonight's lineup alone.
        case lineup = "LINEUP"
        /// The room's chat, the whole screen.
        case chat = "CHAT"
        /// A slideshow's stills and videos, fixed on one or moving through them.
        case slideshow = "SLIDESHOW"
        /// Trusted photographers' recent photos.
        case photoWall = "PHOTO_WALL"
        /// The karaoke app's own screen (KaraFun), captured live by the Mac running Velvet Display, so a screen can
        /// show KaraFun and still be managed with the rest (Rick, 2026-11-22). Only a Mac's screens can show it; it has
        /// something to show while KaraFun is open there.
        case karaoke = "KARAOKE"

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .liveActivity: "Live activity"
            case .board: "Board"
            case .lineup: "Lineup"
            case .chat: "Chat wall"
            case .slideshow: "Slideshow"
            case .photoWall: "Photo wall"
            case .karaoke: "KaraFun"
            }
        }

        /// What it shows, in a line under its title.
        public var summary: String {
            switch self {
            case .liveActivity: "Bingo, trivia or a sing-along while one runs"
            case .board: "Tonight’s lineup and chat, with posters between looks"
            case .lineup: "Tonight’s lineup alone"
            case .chat: "The room’s chat, the whole screen"
            case .slideshow: "Stills and videos, fixed on one or moving through them"
            case .photoWall: "Photographers’ recent photos"
            case .karaoke: "KaraFun’s screen, from the Mac running Velvet"
            }
        }

        /// The types a screen of this kind can show: KaraFun on a Mac's screen, where Velvet Display captures it, and on
        /// Apple TV and Google TV, which play the stream that Mac announces (`KaraFunStream`). Not on an iPad or phone.
        public static func available(onKind kind: String) -> [Screen] {
            allCases.filter { $0 != .karaoke || karaFunKinds.contains(kind) }
        }

        /// The display kinds that can show KaraFun.
        public static let karaFunKinds: Set<String> = ["MAC_SCREEN", "APPLE_TV", "ANDROID_TV"]
    }

    /// How big a board's or chat wall's chat is drawn (`ChatTextSize`), set from any app (Rick, 2026-11-21: "a font
    /// size control for it server side"). Medium is the size it always was.
    public enum ChatSize: String, Codable, Sendable, CaseIterable, Identifiable {
        case small = "SMALL"
        case medium = "MEDIUM"
        case large = "LARGE"
        case extraLarge = "EXTRA_LARGE"

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .small: "Small"
            case .medium: "Medium"
            case .large: "Large"
            case .extraLarge: "Extra large"
            }
        }

        /// What the screen multiplies its chat's drawing by.
        public var scale: Double {
            switch self {
            case .small: 0.85
            case .medium: 1
            case .large: 1.2
            case .extraLarge: 1.45
            }
        }
    }

    /// One entry in the ranking: a screen type and its options.
    public struct Entry: Codable, Sendable, Hashable {
        public var type: Screen
        /// A board's or slideshow's slideshow; nil for the venue's default poster list.
        public var slideshowId: String?
        /// A slideshow's one slide it stays on; nil to move through them.
        public var slideId: String?
        /// A slideshow's seconds per still while it moves (the server fills in 10).
        public var seconds: Int?
        /// A board's: whether the photographers' photos join its slideshow when there are any.
        public var photos: Bool
        /// A board's or chat wall's chat size (the server answers medium for the rest).
        public var chatSize: ChatSize

        public init(type: Screen, slideshowId: String? = nil, slideId: String? = nil, seconds: Int? = nil,
                    photos: Bool = false, chatSize: ChatSize = .medium) {
            self.type = type; self.slideshowId = slideshowId; self.slideId = slideId; self.seconds = seconds
            self.photos = photos; self.chatSize = chatSize
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            // A screen type this build doesn't know shows as the board rather than failing the whole display.
            let raw = try container.decode(String.self, forKey: .type)
            type = Screen(rawValue: raw) ?? .board
            slideshowId = try container.decodeIfPresent(String.self, forKey: .slideshowId)
            slideId = try container.decodeIfPresent(String.self, forKey: .slideId)
            seconds = try container.decodeIfPresent(Int.self, forKey: .seconds)
            photos = try container.decodeIfPresent(Bool.self, forKey: .photos) ?? false
            // A size this build doesn't know draws at medium.
            chatSize = (try container.decodeIfPresent(String.self, forKey: .chatSize)).flatMap(ChatSize.init) ?? .medium
        }

        /// The entry as `VenueDisplayEntryInput`, with only its type's options.
        var input: GraphQLValue {
            var fields: [String: GraphQLValue] = ["type": .string(type.rawValue)]
            switch type {
            case .board:
                fields["photos"] = .bool(photos)
                fields["chatSize"] = .string(chatSize.rawValue)
                if let slideshowId { fields["slideshowId"] = .string(slideshowId) }
            case .slideshow:
                if let slideshowId { fields["slideshowId"] = .string(slideshowId) }
                if let slideId { fields["slideId"] = .string(slideId) }
                else if let seconds { fields["seconds"] = .int(seconds) }
            case .chat:
                fields["chatSize"] = .string(chatSize.rawValue)
            default:
                break
            }
            return .object(fields)
        }
    }

    public static let defaultRanking = [Entry(type: .liveActivity), Entry(type: .board, photos: true)]

    public let id: String
    public var name: String
    /// APPLE_TV, ANDROID_TV, MAC_SCREEN, AIRPLAY or CHROMECAST.
    public let kind: String
    /// Shows only the venue's logo.
    public var off: Bool
    /// Lays the song playing over whatever it shows.
    public var nowPlaying: Bool
    public var ranking: [Entry]
    /// The slideshows its ranking plays, the venue's default poster list among them when an entry names none.
    public var slideshows: [StaffVenueSlideshow]
    /// A Mac's screen: which of its screens this is.
    public let deviceKey: String?
    public let lastSeenAt: String?

    public init(id: String, name: String, kind: String = "APPLE_TV", off: Bool = false, nowPlaying: Bool = true,
                ranking: [Entry] = StaffVenueDisplay.defaultRanking, slideshows: [StaffVenueSlideshow] = [],
                deviceKey: String? = nil, lastSeenAt: String? = nil) {
        self.id = id; self.name = name; self.kind = kind; self.off = off; self.nowPlaying = nowPlaying
        self.ranking = ranking; self.slideshows = slideshows; self.deviceKey = deviceKey; self.lastSeenAt = lastSeenAt
    }

    /// The slideshow an entry plays: the one it names, else the venue's default poster list.
    /// Its ranking with `screen` first, as Velvet's Tonight switches what a screen shows: the screen's own entry of that
    /// type keeps its options and moves up, or a new one with the defaults leads; the rest keep their order behind it.
    public func ranking(leadingWith screen: Screen) -> [Entry] {
        var rest = ranking
        let lead = rest.firstIndex { $0.type == screen }.map { rest.remove(at: $0) }
            ?? Entry(type: screen, photos: screen == .board)
        return [lead] + rest
    }

    /// What it shows while nothing ahead of it has anything: the first entry, or nil when it's off.
    public var leading: Screen? { off ? nil : ranking.first?.type }

    public func slideshow(for entry: Entry) -> StaffVenueSlideshow? {
        if let id = entry.slideshowId { return slideshows.first { $0.id == id } }
        return slideshows.first(where: \.isDefault)
    }

    public var kindTitle: String {
        switch kind {
        case "APPLE_TV": "Apple TV"
        case "ANDROID_TV": "Google TV"
        case "MAC_SCREEN": "Mac screen"
        case "AIRPLAY": "AirPlay"
        case "CHROMECAST": "Chromecast"
        default: "Screen"
        }
    }

    /// The screen types this screen can be given (`Screen.available(onKind:)`).
    public var screenTypes: [Screen] { Screen.available(onKind: kind) }

    public var lastSeen: Date? { lastSeenAt.flatMap { try? Date($0, strategy: .iso8601) } }

    /// Whether a screen is following its record now, or when it last did.
    public enum Connection: Sendable, Hashable {
        case connected
        case lastConnected(Date)
        /// Registered but never seen following (a record made before screens were marked as seen).
        case never
    }

    /// How fresh `lastSeen` must be to count as connected. A screen following its record is marked seen every minute
    /// (the API's VenueDisplaySubscriber#tick), and a mark is skipped while the last is under a minute old, so a
    /// connected screen's mark is at most about two minutes old.
    public static let connectedWithin: TimeInterval = 180

    public func connection(now: Date = Date()) -> Connection {
        guard let lastSeen else { return .never }
        return now.timeIntervalSince(lastSeen) < Self.connectedWithin ? .connected : .lastConnected(lastSeen)
    }
}

/// One of a venue's slideshows: stills and videos in order.
public struct StaffVenueSlideshow: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public var name: String
    /// The venue's default poster list, which screens play when an entry names no slideshow.
    public let isDefault: Bool
    public var slides: [StaffVenueSlide]

    enum CodingKeys: String, CodingKey { case id, name, isDefault = "default", slides }

    public init(id: String, name: String, isDefault: Bool = false, slides: [StaffVenueSlide] = []) {
        self.id = id; self.name = name; self.isDefault = isDefault; self.slides = slides
    }

    /// The slides showing today (inside their dates).
    public var current: [StaffVenueSlide] { slides.filter(\.current) }
}

/// One slide: a still, a video, or the slot where the venue's upcoming event posters play.
public struct StaffVenueSlide: Codable, Sendable, Hashable, Identifiable {
    public static let still = "STILL", video = "VIDEO", upcomingPosters = "UPCOMING_POSTERS"

    public struct Event: Codable, Sendable, Hashable { public let id: String; public let name: String? }

    public let id: String
    /// STILL, VIDEO or UPCOMING_POSTERS.
    public let kind: String
    /// Inside its dates today.
    public let current: Bool
    public let imageUrl: String?
    /// A video's file through a link that lasts an hour; cache the file by the slide's id.
    public let videoUrl: String?
    public let videoContentType: String?
    public let muted: Bool
    public let startsOn: String?
    public let endsOn: String?
    /// A still that is this event's poster.
    public let event: Event?

    public init(id: String, kind: String, current: Bool = true, imageUrl: String? = nil, videoUrl: String? = nil,
                videoContentType: String? = nil, muted: Bool = true, startsOn: String? = nil, endsOn: String? = nil,
                event: Event? = nil) {
        self.id = id; self.kind = kind; self.current = current; self.imageUrl = imageUrl; self.videoUrl = videoUrl
        self.videoContentType = videoContentType; self.muted = muted; self.startsOn = startsOn; self.endsOn = endsOn
        self.event = event
    }

    public var isVideo: Bool { kind == Self.video }
    public var isUpcomingPosters: Bool { kind == Self.upcomingPosters }

    public var title: String {
        switch kind {
        case Self.video: "Video"
        case Self.upcomingPosters: "Upcoming event posters"
        default: event?.name.map { "Poster: \($0)" } ?? "Picture"
        }
    }
}

/// What a screen hears following its display.
public enum VenueDisplayEvent: Sendable {
    /// The display as it is now: on subscribing, and whenever it or a slideshow at its venue changes.
    case display(StaffVenueDisplay)
    /// The server turned the subscription away (the display is gone or not this sign-in's). The feed ends.
    case rejected
    /// The socket dropped; the cable is reconnecting (`nil` reason) or gave up.
    case offline(String?)
}

extension VenueManagementClient {
    static let venueSlideFields = "id kind current imageUrl videoUrl videoContentType muted startsOn endsOn event { id name }"
    static let venueSlideshowFields = "id name default slides { \(venueSlideFields) }"
    static let venueDisplayFields = """
        id name kind off nowPlaying deviceKey lastSeenAt ranking { type slideshowId slideId seconds photos chatSize } \
        slideshows { \(venueSlideshowFields) }
        """

    /// The venue's screens.
    public func venueDisplays(venueID: String) async throws -> [StaffVenueDisplay] {
        struct Venue: Decodable, Sendable { let displays: [StaffVenueDisplay] }
        struct Venues: Decodable, Sendable { let venue: Venue? }
        struct Response: Decodable, Sendable { let venues: Venues }
        let response = try await session.graphQL("""
            query StaffVenueDisplays($id: ID!) { venues { venue(id: $id) { displays { \(Self.venueDisplayFields) } } } }
            """, variables: ["id": .string(venueID)], as: Response.self)
        return response.venues.venue?.displays ?? []
    }

    /// The venue's slideshows, its default poster list first.
    public func venueSlideshows(venueID: String) async throws -> [StaffVenueSlideshow] {
        struct Venue: Decodable, Sendable { let slideshows: [StaffVenueSlideshow] }
        struct Venues: Decodable, Sendable { let venue: Venue? }
        struct Response: Decodable, Sendable { let venues: Venues }
        let response = try await session.graphQL("""
            query StaffVenueSlideshows($id: ID!) { venues { venue(id: $id) { slideshows { \(Self.venueSlideshowFields) } } } }
            """, variables: ["id": .string(venueID)], as: Response.self)
        return response.venues.venue?.slideshows ?? []
    }

    /// A venue device's own display (or one of a Mac's screens, by `deviceKey`), made the first time with the
    /// default ranking. Only a venue device's sign-in may call it.
    public func registerVenueDisplay(name: String? = nil, kind: String = "APPLE_TV",
                                     deviceKey: String? = nil) async throws -> StaffVenueDisplay {
        struct Payload: Decodable, Sendable { let display: StaffVenueDisplay }
        struct Response: Decodable, Sendable { let registerVenueDisplay: Payload }
        let response = try await session.graphQL("""
            mutation StaffVenueDisplayRegister($name: String, $kind: VenueDisplayKind, $deviceKey: String) {
              registerVenueDisplay(input: { name: $name, kind: $kind, deviceKey: $deviceKey }) { display { \(Self.venueDisplayFields) } }
            }
            """, variables: ["name": name.map(GraphQLValue.string) ?? .null, "kind": .string(kind),
                             "deviceKey": deviceKey.map(GraphQLValue.string) ?? .null], as: Response.self)
        return response.registerVenueDisplay.display
    }

    /// Changes a screen: its name, off, the now-playing overlay or its ranking (nil leaves each as it is).
    @discardableResult
    public func updateVenueDisplay(id: String, name: String? = nil, off: Bool? = nil, nowPlaying: Bool? = nil,
                                   ranking: [StaffVenueDisplay.Entry]? = nil) async throws -> StaffVenueDisplay {
        struct Payload: Decodable, Sendable { let display: StaffVenueDisplay }
        struct Response: Decodable, Sendable { let updateVenueDisplay: Payload }
        var input: [String: GraphQLValue] = ["id": .string(id)]
        if let name { input["name"] = .string(name) }
        if let off { input["off"] = .bool(off) }
        if let nowPlaying { input["nowPlaying"] = .bool(nowPlaying) }
        if let ranking { input["ranking"] = .array(ranking.map(\.input)) }
        let response = try await session.graphQL("""
            mutation StaffVenueDisplayUpdate($input: VenueDisplayUpdateInput!) {
              updateVenueDisplay(input: $input) { display { \(Self.venueDisplayFields) } }
            }
            """, variables: ["input": .object(input)], as: Response.self)
        return response.updateVenueDisplay.display
    }

    /// Forgets a screen; a device that still drives it makes a new one with the default ranking.
    public func deleteVenueDisplay(id: String) async throws {
        struct Payload: Decodable, Sendable { let id: String }
        struct Response: Decodable, Sendable { let deleteVenueDisplay: Payload }
        _ = try await session.graphQL("""
            mutation StaffVenueDisplayDelete($id: ID!) { deleteVenueDisplay(input: { id: $id }) { id } }
            """, variables: ["id": .string(id)], as: Response.self)
    }

    /// Makes a slideshow at the venue (`id` nil) or renames one.
    @discardableResult
    public func saveVenueSlideshow(id: String? = nil, venueID: String? = nil,
                                   name: String) async throws -> StaffVenueSlideshow {
        struct Payload: Decodable, Sendable { let slideshow: StaffVenueSlideshow }
        struct Response: Decodable, Sendable { let saveVenueSlideshow: Payload }
        let response = try await session.graphQL("""
            mutation StaffVenueSlideshowSave($id: ID, $venueId: ID, $name: String!) {
              saveVenueSlideshow(input: { id: $id, venueId: $venueId, name: $name }) { slideshow { \(Self.venueSlideshowFields) } }
            }
            """, variables: ["id": id.map(GraphQLValue.string) ?? .null,
                             "venueId": venueID.map(GraphQLValue.string) ?? .null, "name": .string(name)],
            as: Response.self)
        return response.saveVenueSlideshow.slideshow
    }

    /// Deletes a slideshow (never the default poster list); screens that played it play the default.
    public func deleteVenueSlideshow(id: String) async throws {
        struct Payload: Decodable, Sendable { let id: String }
        struct Response: Decodable, Sendable { let deleteVenueSlideshow: Payload }
        _ = try await session.graphQL("""
            mutation StaffVenueSlideshowDelete($id: ID!) { deleteVenueSlideshow(input: { id: $id }) { id } }
            """, variables: ["id": .string(id)], as: Response.self)
    }

    /// What a slide holds, for ``saveVenueSlide(_:)``.
    public struct VenueSlideDraft: Sendable {
        public var id: String?
        public var slideshowID: String?
        public var kind: String?
        /// A still's picture: an upload's data URL or an https link.
        public var photo: String?
        /// A still that is this event's poster.
        public var eventID: String?
        /// A video: a file uploaded to the venue's room.
        public var roomFileID: String?
        public var muted: Bool?
        /// yyyy-MM-dd, or nil for no limit.
        public var startsOn: String?
        public var endsOn: String?

        public init(id: String? = nil, slideshowID: String? = nil, kind: String? = nil, photo: String? = nil,
                    eventID: String? = nil, roomFileID: String? = nil, muted: Bool? = nil, startsOn: String? = nil,
                    endsOn: String? = nil) {
            self.id = id; self.slideshowID = slideshowID; self.kind = kind; self.photo = photo; self.eventID = eventID
            self.roomFileID = roomFileID; self.muted = muted; self.startsOn = startsOn; self.endsOn = endsOn
        }

        var input: [String: GraphQLValue] {
            var input: [String: GraphQLValue] = [:]
            let strings: [(String, String?)] = [("id", id), ("slideshowId", slideshowID), ("kind", kind),
                                                ("photo", photo), ("eventId", eventID), ("roomFileId", roomFileID)]
            for (key, value) in strings { if let value { input[key] = .string(value) } }
            if let muted { input["muted"] = .bool(muted) }
            // Dates are always sent on an edit, so clearing one clears it.
            input["startsOn"] = startsOn.map(GraphQLValue.string) ?? .null
            input["endsOn"] = endsOn.map(GraphQLValue.string) ?? .null
            return input
        }
    }

    /// Adds a slide to the end of a slideshow, or edits one; returns the slideshow as it now stands.
    @discardableResult
    public func saveVenueSlide(_ draft: VenueSlideDraft) async throws -> StaffVenueSlideshow {
        struct Payload: Decodable, Sendable { let slideshow: StaffVenueSlideshow }
        struct Response: Decodable, Sendable { let saveVenueSlide: Payload }
        let response = try await session.graphQL("""
            mutation StaffVenueSlideSave($input: VenueSlideSaveInput!) {
              saveVenueSlide(input: $input) { slideshow { \(Self.venueSlideshowFields) } }
            }
            """, variables: ["input": .object(draft.input)], as: Response.self)
        return response.saveVenueSlide.slideshow
    }

    /// Takes a slide out of its slideshow.
    @discardableResult
    public func removeVenueSlide(id: String) async throws -> StaffVenueSlideshow {
        struct Payload: Decodable, Sendable { let slideshow: StaffVenueSlideshow }
        struct Response: Decodable, Sendable { let removeVenueSlide: Payload }
        let response = try await session.graphQL("""
            mutation StaffVenueSlideRemove($id: ID!) { removeVenueSlide(input: { id: $id }) { slideshow { \(Self.venueSlideshowFields) } } }
            """, variables: ["id": .string(id)], as: Response.self)
        return response.removeVenueSlide.slideshow
    }

    /// Puts a slideshow's slides in this order.
    @discardableResult
    public func reorderVenueSlides(slideshowID: String, ids: [String]) async throws -> StaffVenueSlideshow {
        struct Payload: Decodable, Sendable { let slideshow: StaffVenueSlideshow }
        struct Response: Decodable, Sendable { let reorderVenueSlides: Payload }
        let response = try await session.graphQL("""
            mutation StaffVenueSlidesReorder($slideshowId: ID!, $ids: [ID!]!) {
              reorderVenueSlides(input: { slideshowId: $slideshowId, ids: $ids }) { slideshow { \(Self.venueSlideshowFields) } }
            }
            """, variables: ["slideshowId": .string(slideshowID), "ids": .array(ids.map(GraphQLValue.string))],
            as: Response.self)
        return response.reorderVenueSlides.slideshow
    }

    static let venueDisplaySubscription = """
        subscription StaffVenueDisplay($id: ID!) { venueDisplay(id: $id) { \(venueDisplayFields) } }
        """

    /// Follows a screen's display: as it is now, then again on every change. Ending the iteration stops following.
    public func venueDisplayFeed(id: String) async -> AsyncStream<VenueDisplayEvent> {
        let results = await session.subscribe(Self.venueDisplaySubscription, variables: ["id": .string(id)])
        return AsyncStream { continuation in
            let task = Task {
                for await result in results {
                    guard let event = Self.venueDisplayEvent(from: result) else { continue }
                    continuation.yield(event)
                    if case .rejected = event { break }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static func venueDisplayEvent(from event: AudienceCable.Event) -> VenueDisplayEvent? {
        switch event {
        case .rejected: return .rejected
        case .disconnected(let reason, let reconnects): return .offline(reconnects ? nil : (reason ?? "Signed out"))
        case .result(let data): return venueDisplayEvent(from: data)
        default: return nil
        }
    }

    static func venueDisplayEvent(from data: Data) -> VenueDisplayEvent? {
        struct Payload: Decodable { let venueDisplay: StaffVenueDisplay? }
        guard let result = try? JSONDecoder().decode(GraphQLSubscriptionResult<Payload>.self, from: data) else {
            return nil
        }
        if let display = result.data?.venueDisplay { return .display(display) }
        return result.refused ? .rejected : nil
    }
}

/// A venue as the API sent it, kept as JSON so a screen can show its last board at launch before the network answers
/// (VenueWorkspace itself only decodes).
public struct VenueSnapshot: Codable, Sendable {
    /// The venue's JSON exactly as it came.
    public let json: Data

    public init(json: Data) { self.json = json }

    public var venue: VenueWorkspace? { try? JSONDecoder().decode(VenueWorkspace.self, from: json) }
}

/// Any JSON value, decoded only to be written back out (VenueSnapshot).
enum PassthroughJSON: Codable, Sendable {
    case null, bool(Bool), number(Double), string(String), array([PassthroughJSON]), object([String: PassthroughJSON])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([PassthroughJSON].self) { self = .array(value) }
        else { self = .object(try container.decode([String: PassthroughJSON].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value):
            // Whole numbers back out as integers, so Int fields decode again.
            if value.rounded() == value, abs(value) < 1e15 { try container.encode(Int64(value)) }
            else { try container.encode(value) }
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

extension VenueManagementClient {
    /// The venues the signed-in device works, in full, each with its JSON to keep (a screen's last board).
    public func venueSnapshots() async throws -> [VenueSnapshot] {
        struct Response: Decodable, Sendable {
            struct Nodes: Decodable, Sendable { let nodes: [PassthroughJSON] }
            struct Cover: Decodable, Sendable { let doorVenues: Nodes }
            struct Me: Decodable, Sendable { let cover: Cover }
            let me: Me?
        }
        let query = "query VelvetVenueSnapshots { me { cover { doorVenues { nodes { \(Self.fields) } } } } }"
        let nodes = try await session.graphQL(query, as: Response.self).me?.cover.doorVenues.nodes ?? []
        let encoder = JSONEncoder()
        return nodes.compactMap { node in (try? encoder.encode(node)).map(VenueSnapshot.init(json:)) }
    }
}
