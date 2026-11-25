import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import AudienceCore
import StaffKitCore

// Back of house: the private room every venue and event has beside its public chat, where the venue's staff and the
// night's hosts and performers talk, post, share tracks, posters and documents, follow the running order's tracks and
// tick off the checklist (api doc/ROOMS.md). A locale has one too, where the staff of every venue in the city talk.
// Membership is the server's: a room that answers is one the viewer is in.

/// Where a back-of-house room is: a venue's own, an event's, or a locale's (every venue's staff there).
public enum RoomPlace: Sendable, Hashable {
    case venue(String)
    case event(String)
    case locale(String)

    public var id: String {
        switch self {
        case .venue(let id), .event(let id), .locale(let id): id
        }
    }
    public var isEvent: Bool { if case .event = self { true } else { false } }
    public var isLocale: Bool { if case .locale = self { true } else { false } }
}

/// A listing named in a room: the talent someone posts as, or the people on an act.
public struct RoomListing: Decodable, Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String?
    public let avatarUrl: String?

    public init(id: String, name: String?, avatarUrl: String? = nil) { self.id = id; self.name = name; self.avatarUrl = avatarUrl }
}

/// A record named by its ID only (`appearance { id }`).
public struct RoomRef: Decodable, Sendable, Hashable { public let id: String }

/// A file shared in a room. Its `url` is a signed download link that works for an hour, so a screen reads it fresh
/// before opening it rather than keeping it.
public struct RoomFile: Decodable, Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    /// AUDIO, IMAGE, VIDEO or DOCUMENT.
    public let kind: String
    /// What a document is: RUN_OF_SHOW, TECH_RIDER, LOAD_IN or OTHER.
    public let label: String?
    public let byteSize: Int64
    public let contentType: String
    public let url: String?
    public let uploaderName: String?
    public let createdAt: String
    /// When it was posted to the venue's public chat; images only.
    public let promotedAt: String?
    public let viewerCanPromote: Bool
    public let viewerCanRemove: Bool
    /// The lineup slot it's for, such as a performer's track.
    public let appearance: RoomRef?
    /// A sound file's length in seconds: the server's once it has checked it (`audioStatus` READY), the uploading
    /// app's before; nil when neither knows, or it was rejected.
    public let durationSeconds: Int?
    /// Where the server's check of a sound file has got to: PENDING, READY or REJECTED; nil for other files.
    public let audioStatus: String?
    /// Why the server rejected a sound file, to show.
    public let audioError: String?
    /// The server's waveform for a sound file: 120 peaks evenly over it, each 0–100; empty until it's READY.
    public let waveform: [Int]

    public var isAudio: Bool { kind == "AUDIO" }
    public var isImage: Bool { kind == "IMAGE" }
    public var isVideo: Bool { kind == "VIDEO" }
    public var isDocument: Bool { kind == "DOCUMENT" }
    public var promoted: Bool { promotedAt != nil }
    /// The server found it isn't sound that plays.
    public var audioRejected: Bool { audioStatus == "REJECTED" }

    /// The waveform as `count` bars from 0 to 1, each the loudest of its run of the server's peaks; empty until the
    /// server has checked it.
    public func waveformBars(_ count: Int) -> [Double] {
        guard count > 0, !waveform.isEmpty else { return [] }
        return (0..<count).map { i in
            let from = i * waveform.count / count
            let to = max((i + 1) * waveform.count / count, from + 1)
            return Double(waveform[from..<to].max() ?? 0) / 100
        }
    }

    /// "4:03", or "1:02:03" past an hour; nil when its length isn't known.
    public var durationText: String? {
        guard let seconds = durationSeconds else { return nil }
        let (h, m, s) = (seconds / 3600, seconds % 3600 / 60, seconds % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    enum CodingKeys: String, CodingKey {
        case id, name, kind, label, byteSize, contentType, url, uploaderName, createdAt, promotedAt, viewerCanPromote,
             viewerCanRemove, appearance, durationSeconds, audioStatus, audioError, waveform
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        kind = try c.decode(String.self, forKey: .kind)
        label = try c.decodeIfPresent(String.self, forKey: .label)
        // BigInt is a string in GraphQL Ruby's JSON; a number is taken too.
        if let text = try? c.decode(String.self, forKey: .byteSize) { byteSize = Int64(text) ?? 0 }
        else { byteSize = try c.decodeIfPresent(Int64.self, forKey: .byteSize) ?? 0 }
        contentType = try c.decodeIfPresent(String.self, forKey: .contentType) ?? "application/octet-stream"
        url = try c.decodeIfPresent(String.self, forKey: .url)
        uploaderName = try c.decodeIfPresent(String.self, forKey: .uploaderName)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        promotedAt = try c.decodeIfPresent(String.self, forKey: .promotedAt)
        viewerCanPromote = try c.decodeIfPresent(Bool.self, forKey: .viewerCanPromote) ?? false
        viewerCanRemove = try c.decodeIfPresent(Bool.self, forKey: .viewerCanRemove) ?? false
        appearance = try c.decodeIfPresent(RoomRef.self, forKey: .appearance)
        durationSeconds = try c.decodeIfPresent(Int.self, forKey: .durationSeconds)
        audioStatus = try c.decodeIfPresent(String.self, forKey: .audioStatus)
        audioError = try c.decodeIfPresent(String.self, forKey: .audioError)
        waveform = try c.decodeIfPresent([Int].self, forKey: .waveform) ?? []
    }

    /// The labels a document can carry, with what the apps call them.
    public static let labels: [(value: String, title: String)] = [
        ("RUN_OF_SHOW", "Run of show"), ("TECH_RIDER", "Tech rider"), ("LOAD_IN", "Load-in notes"), ("OTHER", "Other"),
    ]
    public var labelTitle: String? { label.flatMap { value in Self.labels.first { $0.value == value }?.title } }

    /// "6.2 MB", "140 KB": one decimal under 10 MB.
    public static func size(_ bytes: Int64) -> String {
        let kb = Double(bytes) / 1024, mb = kb / 1024
        if mb >= 10 { return "\(Int(mb.rounded())) MB" }
        if mb >= 1 { return String(format: "%.1f MB", mb) }
        return "\(max(1, Int(kb.rounded()))) KB"
    }
    public var sizeText: String { Self.size(byteSize) }
}

/// A reply under a post.
public struct RoomReply: Decodable, Sendable, Hashable, Identifiable {
    public let id: String
    public let body: String
    public let authorName: String?
    public let avatarUrl: String?
    public let createdAt: String
    public let mine: Bool
    public let viewerCanManage: Bool
    public let postedAsVenue: Bool
    public let files: [RoomFile]
}

/// Something said or posted in a room: a MESSAGE (a line in the conversation), a POST (kept, with a title, that can be
/// pinned and has replies) or a TRACK_NEEDED card (a nudge for an act's track).
public struct RoomMessage: Decodable, Sendable, Hashable, Identifiable {
    public let id: String
    public let kind: String
    public let title: String?
    public let body: String
    /// The sender's full name, or the listing it was posted as.
    public let authorName: String?
    public let avatarUrl: String?
    public let createdAt: String
    public let editedAt: String?
    public let pinned: Bool
    public let replyCount: Int
    public let mine: Bool
    public let viewerCanManage: Bool
    public let postedAsVenue: Bool
    /// The talent listing it was posted as.
    public let person: RoomListing?
    /// The lineup slot a TRACK_NEEDED card is about.
    public let appearance: RoomRef?
    /// The post it replies to, on a reply heard from the room's feed.
    public let parentId: String?
    public let files: [RoomFile]
    public let replies: [RoomReply]

    public var isPost: Bool { kind == "POST" }
    public var isTrackNeeded: Bool { kind == "TRACK_NEEDED" }
    /// What Copy puts on the clipboard: a post's title and its words, or the line; nil when it says nothing.
    public var copyText: String? {
        let words = [title, body].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return words.isEmpty ? nil : words.joined(separator: "\n\n")
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, title, body, authorName, avatarUrl, createdAt, editedAt, pinned, replyCount, mine, viewerCanManage,
             postedAsVenue, person, appearance, parentId, files, replies
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "MESSAGE"
        title = try c.decodeIfPresent(String.self, forKey: .title)
        body = try c.decodeIfPresent(String.self, forKey: .body) ?? ""
        authorName = try c.decodeIfPresent(String.self, forKey: .authorName)
        avatarUrl = try c.decodeIfPresent(String.self, forKey: .avatarUrl)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        editedAt = try c.decodeIfPresent(String.self, forKey: .editedAt)
        pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
        replyCount = try c.decodeIfPresent(Int.self, forKey: .replyCount) ?? 0
        mine = try c.decodeIfPresent(Bool.self, forKey: .mine) ?? false
        viewerCanManage = try c.decodeIfPresent(Bool.self, forKey: .viewerCanManage) ?? false
        postedAsVenue = try c.decodeIfPresent(Bool.self, forKey: .postedAsVenue) ?? false
        person = try c.decodeIfPresent(RoomListing.self, forKey: .person)
        appearance = try c.decodeIfPresent(RoomRef.self, forKey: .appearance)
        parentId = try c.decodeIfPresent(String.self, forKey: .parentId)
        files = try c.decodeIfPresent([RoomFile].self, forKey: .files) ?? []
        replies = try c.decodeIfPresent([RoomReply].self, forKey: .replies) ?? []
    }
}

/// Someone in a room, as everyone in it sees them: full names, it's a work room.
public struct RoomMember: Decodable, Sendable, Hashable, Identifiable {
    public let userId: String
    public let name: String?
    /// ADMIN, VENUE, STAFF, HOST or PERFORMER.
    public let role: String
    public let avatarUrl: String?
    /// The talent listings they're in the room through.
    public let people: [RoomListing]
    /// In a locale's room, the venues there they work at.
    public let venues: [BackOfHouseRoom.Venue]?
    public var id: String { userId }

    public var roleTitle: String {
        switch role {
        case "ADMIN": "Admin"
        case "LOCALE": "City"
        case "VENUE": "Venue"
        case "STAFF": "Staff"
        case "HOST": "Host"
        case "PERFORMER": "Performer"
        default: role.capitalized
        }
    }
}

/// An entry on the event's lineup, with its track: whether one is needed, and whether it's in.
public struct RoomSlot: Decodable, Sendable, Hashable, Identifiable {
    public struct Act: Decodable, Sendable, Hashable {
        public let id: String
        /// ACT or INTERMISSION.
        public let kind: String
        public let role: String?
        public let title: String?
        public let startsAt: String?
        /// HARD, SOFT or NONE.
        public let startTiming: String
        /// UPCOMING, ON or DONE.
        public let state: String
        public let people: GraphQLNodes<RoomListing>

        public static func == (lhs: Act, rhs: Act) -> Bool {
            lhs.id == rhs.id && lhs.state == rhs.state && lhs.startsAt == rhs.startsAt && lhs.title == rhs.title
        }
        public func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }
    public let appearance: Act
    public let needsTrack: Bool
    /// MISSING, RECEIVED, PLAYING or NONE.
    public let trackStatus: String
    public let tracks: [RoomRef]
    public let viewerCanNudge: Bool
    public let viewerCanSetNeedsTrack: Bool
    public let viewerCanAttachTrack: Bool
    public var id: String { appearance.id }

    public var isIntermission: Bool { appearance.kind == "INTERMISSION" }
    /// Its billing: the act's title, else who's on it ("The Sisters Grimm", "Lady Bunny Hop & Miss Conduct").
    public var name: String {
        if let title = appearance.title, !title.isEmpty { return title }
        if isIntermission { return "Intermission" }
        let names = appearance.people.nodes.compactMap(\.name)
        return names.isEmpty ? "Act" : names.joined(separator: " & ")
    }

    /// "11:30" for a set time, "around 10:10" for a soft one, "Next" for an entry with no time.
    public func time(in zone: TimeZone) -> String {
        guard appearance.startTiming != "NONE", let date = roomInstant(appearance.startsAt) else { return "Next" }
        var style = Date.FormatStyle.dateTime.hour().minute()
        style.timeZone = zone
        let time = date.formatted(style)
        return appearance.startTiming == "SOFT" ? "around \(time)" : time
    }

    /// The badge its track status shows: "Received", "No track yet", "Playing", "No track".
    public var trackTitle: String {
        switch trackStatus {
        case "RECEIVED": "Received"
        case "MISSING": "No track yet"
        case "PLAYING": "Playing"
        default: "No track"
        }
    }
}

/// An item on an event room's checklist. Items with `auto` tick themselves (run of show shared, poster promoted, all
/// tracks in); anyone in the room ticks the rest.
public struct RoomChecklistItem: Decodable, Sendable, Hashable, Identifiable {
    public let id: String
    public let title: String
    public let note: String?
    public let done: Bool
    public let doneAt: String?
    public let doneByName: String?
    public let auto: String?
    public let viewerCanChange: Bool
}

/// A room as its screen opens it: who's in it, what the viewer may post as, and an event's lineup, files and
/// checklist. The conversation is read on its own (``RoomsClient/messages(in:)``), as the console does, so each
/// stays within the API's query budget.
public struct BackOfHouseRoom: Decodable, Sendable, Identifiable {
    public struct Event: Decodable, Sendable, Hashable {
        public let id: String
        public let name: String?
        public let startAt: String?
        public let endAt: String?
    }
    public struct Venue: Decodable, Sendable, Hashable, Identifiable {
        public let id: String
        public let name: String?
        public let photoUrl: String?
    }
    public struct Locale: Decodable, Sendable, Hashable {
        public let id: String
        public let name: String?
    }
    public let id: String
    public let name: String?
    /// When an event's room closes (24 hours after the event ends); nil for a venue's.
    public let expiresAt: String?
    /// Whether the viewer may post as the venue: its managers and the audience's admins.
    public let viewerCanPostAsVenue: Bool
    /// The viewer's talent in the room, whom they can post as.
    public let viewerPeople: [RoomListing]
    /// The venues the viewer may post as: the room's, or in a locale's room the venues there they manage.
    public let viewerVenues: [Venue]?
    public let event: Event?
    public let venue: Venue?
    /// The locale a locale's room is on.
    public let locale: Locale?
    public let members: [RoomMember]
    public let files: GraphQLNodes<RoomFile>
    public let lineup: [RoomSlot]
    public let checklist: [RoomChecklistItem]

    public var isEvent: Bool { event != nil }
    public var isLocale: Bool { locale != nil }
    /// The venues the viewer may post as here.
    public var postingVenues: [Venue] { viewerVenues ?? [] }
    /// "The Wildrose staff and the night's lineup" on an event; "The Wildrose staff" on a venue; "Staff across
    /// Seattle" on a locale.
    public var who: String {
        if let locale { return "Staff across \(locale.name ?? "the city")" }
        let venueName = venue?.name ?? "The venue"
        return isEvent ? "\(venueName) staff and the night’s lineup" : "\(venueName) staff"
    }
}

/// A room as the rooms list shows it.
public struct RoomSummary: Decodable, Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String?
    public let lastMessageAt: String?
    public let expiresAt: String?
    public let event: BackOfHouseRoom.Event?
    public let venue: BackOfHouseRoom.Venue?
    public let locale: BackOfHouseRoom.Locale?

    /// Where it is, to open it with.
    public var place: RoomPlace? {
        if let event { return .event(event.id) }
        if let venue { return .venue(venue.id) }
        if let locale { return .locale(locale.id) }
        return nil
    }
}

/// Who a room message goes out as: the signed-in person, the room's venue, one of their venues in a locale's room, or
/// one of their talent in the room.
public enum RoomIdentity: Sendable, Hashable {
    case me
    case venue
    case venueID(String)
    case person(id: String)
}

/// What a room's subscription says: a message added, changed (edited, pinned, a reply or file added) or removed.
public enum RoomFeedEvent: Sendable {
    case added(RoomMessage)
    case updated(RoomMessage)
    case removed(id: String)
    /// The socket dropped; the cable is reconnecting (`nil` reason) or gave up.
    case offline(String?)
    /// The server turned the subscription away: the viewer isn't in the room, or it closed.
    case rejected
}

/// A file started in a room (``RoomsClient/startUpload(in:filename:contentType:byteSize:appearanceID:label:)``):
/// where its bytes go.
public struct RoomUpload: Sendable {
    public let file: RoomFile
    /// The signed S3 PUT link, for 30 minutes.
    public let uploadURL: URL
}

/// Back-of-house rooms for the staff apps, on StaffKitCore's session.
public struct RoomsClient: Sendable {
    public let session: AudienceManagementSession
    /// What carries the bytes straight to storage.
    private let transfer: TransferSession

    public init(session: AudienceManagementSession, transfer: URLSession = .shared) {
        self.session = session; self.transfer = TransferSession(transfer)
    }

    // MARK: Reading

    static let fileFields = "id name kind label byteSize contentType url uploaderName createdAt promotedAt viewerCanPromote viewerCanRemove appearance { id } durationSeconds audioStatus audioError waveform"
    static let messageFields = """
        id kind title body authorName avatarUrl createdAt editedAt pinned replyCount mine viewerCanManage postedAsVenue parentId
        person { id name } appearance { id } files { \(fileFields) }
        replies { id body authorName avatarUrl createdAt mine viewerCanManage postedAsVenue files { \(fileFields) } }
        """
    static let slotFields = """
        needsTrack trackStatus viewerCanNudge viewerCanSetNeedsTrack viewerCanAttachTrack tracks { id }
        appearance { id kind role title startsAt startTiming state people(first: 4) { nodes { id name } } }
        """
    static let checklistFields = "id title note done doneAt doneByName auto viewerCanChange"
    static let roomFields = """
        id name expiresAt viewerCanPostAsVenue viewerPeople { id name avatarUrl } viewerVenues { id name photoUrl }
        event { id name startAt endAt } venue { id name photoUrl } locale { id name }
        members { userId name role avatarUrl people { id name } venues { id name photoUrl } }
        files(first: 30) { nodes { \(fileFields) } }
        lineup { \(slotFields) }
        checklist { \(checklistFields) }
        """

    private struct Rooms<Room: Decodable & Sendable>: Decodable, Sendable { let backOfHouse: Room }
    private struct Holder<Room: Decodable & Sendable>: Decodable, Sendable { let rooms: Rooms<Room>? }
    private struct EventLookup<Room: Decodable & Sendable>: Decodable, Sendable { let event: Holder<Room>? }
    private struct VenueLookup<Room: Decodable & Sendable>: Decodable, Sendable { let venue: Holder<Room>? }
    private struct ByPlace<Room: Decodable & Sendable>: Decodable, Sendable {
        let events: EventLookup<Room>?
        let venues: VenueLookup<Room>?
        let locale: Holder<Room>?
        var room: Room? { (events?.event ?? venues?.venue ?? locale)?.rooms?.backOfHouse }
    }

    static let eventRoomQuery = """
        query StaffEventBackOfHouse($id: ID!) { events { event(id: $id) { id rooms { backOfHouse { \(roomFields) } } } } }
        """
    static let venueRoomQuery = """
        query StaffVenueBackOfHouse($id: ID!) { venues { venue(id: $id) { id rooms { backOfHouse { \(roomFields) } } } } }
        """
    static let localeRoomQuery = """
        query StaffLocaleBackOfHouse($id: ID!) { locale(id: $id) { id rooms { backOfHouse { \(roomFields) } } } }
        """
    static let eventThreadQuery = """
        query StaffEventBackOfHouseThread($id: ID!) {
          events { event(id: $id) { id rooms { backOfHouse { id messages(first: 15) { nodes { \(messageFields) } } } } } }
        }
        """
    static let venueThreadQuery = """
        query StaffVenueBackOfHouseThread($id: ID!) {
          venues { venue(id: $id) { id rooms { backOfHouse { id messages(first: 15) { nodes { \(messageFields) } } } } } }
        }
        """

    static let localeThreadQuery = """
        query StaffLocaleBackOfHouseThread($id: ID!) {
          locale(id: $id) { id rooms { backOfHouse { id messages(first: 15) { nodes { \(messageFields) } } } } }
        }
        """

    /// The room at `place`, with its members, lineup, files and checklist; nil when it has closed or the viewer
    /// isn't in it.
    public func room(_ place: RoomPlace) async throws -> BackOfHouseRoom? {
        let query = switch place { case .event: Self.eventRoomQuery; case .venue: Self.venueRoomQuery; case .locale: Self.localeRoomQuery }
        return try await session.graphQL(query, variables: ["id": .string(place.id)], as: ByPlace<BackOfHouseRoom>.self).room
    }

    /// The room's latest 15 messages, newest first: posts with their replies and files.
    public func messages(in place: RoomPlace) async throws -> [RoomMessage] {
        struct Thread: Decodable, Sendable { let messages: GraphQLNodes<RoomMessage> }
        let query = switch place { case .event: Self.eventThreadQuery; case .venue: Self.venueThreadQuery; case .locale: Self.localeThreadQuery }
        return try await session.graphQL(query, variables: ["id": .string(place.id)], as: ByPlace<Thread>.self).room?.messages.nodes ?? []
    }

    /// The rooms the viewer is in, the most recently active first: their venues', their venues' locales', those
    /// venues' open events in the next 30 days, and the events their talent works.
    public func mine() async throws -> [RoomSummary] {
        struct Mine: Decodable, Sendable { let mine: [RoomSummary] }
        struct Response: Decodable, Sendable { let rooms: Mine }
        return try await session.graphQL("""
            query StaffMyRooms { rooms { mine { id name lastMessageAt expiresAt event { id name startAt endAt } venue { id name photoUrl } locale { id name } } } }
            """, as: Response.self).rooms.mine
    }

    // MARK: Following

    static let feedSubscription = """
        subscription StaffRoomFeed($id: ID!) { room(id: $id) { change messageId message { \(messageFields) } } }
        """

    /// Follows a room live: every message added, changed or removed. Ending the iteration stops following it.
    public func feed(roomID: String) async -> AsyncStream<RoomFeedEvent> {
        let results = await session.subscribe(Self.feedSubscription, variables: ["id": .string(roomID)])
        return AsyncStream { continuation in
            let task = Task {
                for await result in results {
                    for event in Self.feedEvents(from: result) {
                        continuation.yield(event)
                        if case .rejected = event { continuation.finish(); return }
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static func feedEvents(from event: AudienceCable.Event) -> [RoomFeedEvent] {
        switch event {
        case .rejected: return [.rejected]
        case .disconnected(let reason, let reconnects): return [.offline(reconnects ? nil : (reason ?? "Signed out"))]
        case .result(let data): return feedEvents(from: data)
        default: return []  // subscribed
        }
    }

    static func feedEvents(from data: Data) -> [RoomFeedEvent] {
        struct Event: Decodable { let change: String; let messageId: String; let message: RoomMessage? }
        struct Payload: Decodable { let room: Event? }
        guard let result = try? JSONDecoder().decode(GraphQLSubscriptionResult<Payload>.self, from: data) else { return [] }
        guard let event = result.data?.room else { return result.refused ? [.rejected] : [] }
        switch event.change {
        case "ADDED": return event.message.map { [.added($0)] } ?? []
        case "UPDATED": return event.message.map { [.updated($0)] } ?? []
        case "REMOVED": return [.removed(id: event.messageId)]
        default: return []
        }
    }

    // MARK: Saying and posting

    /// Says something in the room (`kind` MESSAGE) or posts there (POST, with a title, optionally pinned), or replies
    /// to a post (`replyTo`). A message may be only files, shared once uploaded.
    @discardableResult
    public func send(roomID: String, body: String, kind: String = "MESSAGE", title: String? = nil, pinned: Bool = false,
                     replyTo: String? = nil, fileIDs: [String] = [], as identity: RoomIdentity = .me) async throws -> RoomMessage {
        struct Payload: Decodable, Sendable { let message: RoomMessage }
        struct Response: Decodable, Sendable { let sendRoomMessage: Payload }
        var input: [String: GraphQLValue] = ["roomId": .string(roomID), "body": .string(body), "kind": .string(kind)]
        if let title, !title.isEmpty { input["title"] = .string(title) }
        if pinned { input["pinned"] = .bool(true) }
        if let replyTo { input["replyToId"] = .string(replyTo) }
        if !fileIDs.isEmpty { input["fileIds"] = .array(fileIDs.map(GraphQLValue.string)) }
        switch identity {
        case .me: break
        case .venue: input["asVenue"] = .bool(true)
        case .venueID(let id): input["asVenueId"] = .string(id)
        case .person(let id): input["asPersonId"] = .string(id)
        }
        return try await session.graphQL("""
            mutation StaffSendRoomMessage($input: RoomMessageSendInput!) { sendRoomMessage(input: $input) { message { \(Self.messageFields) } } }
            """, variables: ["input": .object(input)], as: Response.self).sendRoomMessage.message
    }

    /// Edits, pins or unpins a message; nil leaves a field as it is.
    @discardableResult
    public func update(messageID: String, body: String? = nil, title: String? = nil, pinned: Bool? = nil) async throws -> RoomMessage {
        struct Payload: Decodable, Sendable { let message: RoomMessage }
        struct Response: Decodable, Sendable { let updateRoomMessage: Payload }
        var input: [String: GraphQLValue] = ["id": .string(messageID)]
        if let body { input["body"] = .string(body) }
        if let title { input["title"] = .string(title) }
        if let pinned { input["pinned"] = .bool(pinned) }
        return try await session.graphQL("""
            mutation StaffUpdateRoomMessage($input: RoomMessageUpdateInput!) { updateRoomMessage(input: $input) { message { \(Self.messageFields) } } }
            """, variables: ["input": .object(input)], as: Response.self).updateRoomMessage.message
    }

    /// Removes a message, with its replies and the files it shared.
    public func remove(messageID: String) async throws {
        _ = try await session.graphQL("""
            mutation StaffRemoveRoomMessage($input: RoomMessageRemoveInput!) { removeRoomMessage(input: $input) { id } }
            """, variables: ["input": .object(["id": .string(messageID)])], as: GraphQLValue.self)
    }

    // MARK: Sharing files

    /// The largest file a room takes.
    public static let maxFileSize: Int64 = 200 * 1024 * 1024

    /// Starts a file in the room: where to PUT its bytes. `appearanceID` ties it to a lineup slot (a performer's
    /// track); `label` says what a document is.
    public func startUpload(in roomID: String, filename: String, contentType: String, byteSize: Int64,
                            appearanceID: String? = nil, label: String? = nil) async throws -> RoomUpload {
        struct Payload: Decodable, Sendable { let file: RoomFile; let uploadUrl: String }
        struct Response: Decodable, Sendable { let startRoomUpload: Payload }
        var input: [String: GraphQLValue] = ["roomId": .string(roomID), "filename": .string(filename),
                                            "contentType": .string(contentType), "byteSize": .string(String(byteSize))]
        if let appearanceID { input["appearanceId"] = .string(appearanceID) }
        if let label { input["label"] = .string(label) }
        let payload = try await session.graphQL("""
            mutation StaffStartRoomUpload($input: RoomUploadStartInput!) { startRoomUpload(input: $input) { file { \(Self.fileFields) } uploadUrl } }
            """, variables: ["input": .object(input)], as: Response.self).startRoomUpload
        guard let url = URL(string: payload.uploadUrl) else { throw AudienceKitError.decoding("The upload link was missing") }
        return RoomUpload(file: payload.file, uploadURL: url)
    }

    /// PUTs a file's bytes straight to storage, with the Content-Type the upload was started with, reporting the
    /// bytes sent as they go. Cancelling the task cancels the transfer.
    public func put(_ fileURL: URL, to upload: RoomUpload, progress: @escaping @Sendable (Int64) -> Void = { _ in }) async throws {
        var request = URLRequest(url: upload.uploadURL)
        request.httpMethod = "PUT"
        request.setValue(upload.file.contentType, forHTTPHeaderField: "Content-Type")
        let box = TransferBox()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let task = transfer.session.uploadTask(with: request, fromFile: fileURL) { _, response, error in
                    if let error { continuation.resume(throwing: error); return }
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    if (200..<300).contains(status) { continuation.resume() }
                    else { continuation.resume(throwing: RoomUploadError.storageRefused(status: status)) }
                }
                box.task = task
                task.resume()
                // The completion handler gets no progress; read the bytes sent off the task until it's done.
                Task {
                    while let task = box.task, task.state == .running {
                        progress(task.countOfBytesSent)
                        try? await Task.sleep(nanoseconds: 200_000_000)
                    }
                    if let task = box.task { progress(task.countOfBytesSent) }
                }
            }
        } onCancel: { box.task?.cancel() }
    }

    /// Checks an upload reached storage whole, so it can be shared.
    @discardableResult
    public func finishUpload(id: String) async throws -> RoomFile {
        struct Payload: Decodable, Sendable { let file: RoomFile }
        struct Response: Decodable, Sendable { let finishRoomUpload: Payload }
        return try await session.graphQL("""
            mutation StaffFinishRoomUpload($input: RoomUploadFinishInput!) { finishRoomUpload(input: $input) { file { \(Self.fileFields) } } }
            """, variables: ["input": .object(["id": .string(id)])], as: Response.self).finishRoomUpload.file
    }

    /// Starts, PUTs and finishes a file on disk: what to pass `send(fileIDs:)` once it's back.
    public func upload(_ fileURL: URL, name: String, contentType: String, in roomID: String, appearanceID: String? = nil,
                       label: String? = nil, progress: @escaping @Sendable (Int64) -> Void = { _ in }) async throws -> RoomFile {
        let size = Int64(try fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
        guard size <= Self.maxFileSize else { throw RoomUploadError.tooBig }
        let upload = try await startUpload(in: roomID, filename: name, contentType: contentType, byteSize: size,
                                           appearanceID: appearanceID, label: label)
        try await put(fileURL, to: upload, progress: progress)
        return try await finishUpload(id: upload.file.id)
    }

    /// Deletes a shared file and its stored copy.
    public func removeFile(id: String) async throws {
        _ = try await session.graphQL("""
            mutation StaffRemoveRoomFile($input: RoomFileRemoveInput!) { removeRoomFile(input: $input) { id } }
            """, variables: ["input": .object(["id": .string(id)])], as: GraphQLValue.self)
    }

    /// Posts a picture from the room to the venue's public chat, with a caption and alt text. The venue posts as
    /// itself; talent post their own picture as one of their listings in the room (`asPersonID`).
    @discardableResult
    public func promote(fileID: String, altText: String, caption: String = "", asPersonID: String? = nil) async throws -> RoomFile {
        struct Payload: Decodable, Sendable { let file: RoomFile }
        struct Response: Decodable, Sendable { let promoteRoomFile: Payload }
        var input: [String: GraphQLValue] = ["id": .string(fileID), "altText": .string(altText), "caption": .string(caption)]
        if let asPersonID { input["asPersonId"] = .string(asPersonID) }
        return try await session.graphQL("""
            mutation StaffPromoteRoomFile($input: RoomFilePromoteInput!) { promoteRoomFile(input: $input) { file { \(Self.fileFields) } } }
            """, variables: ["input": .object(input)], as: Response.self).promoteRoomFile.file
    }

    // MARK: Lineup and checklist

    /// Asks an act for its track: a "Track needed" card in the room, and a push to whoever manages the act.
    @discardableResult
    public func nudge(appearanceID: String) async throws -> RoomSlot {
        struct Payload: Decodable, Sendable { let slot: RoomSlot }
        struct Response: Decodable, Sendable { let nudgeRoomTrack: Payload }
        return try await session.graphQL("""
            mutation StaffNudgeRoomTrack($input: RoomTrackNudgeInput!) { nudgeRoomTrack(input: $input) { slot { \(Self.slotFields) } } }
            """, variables: ["input": .object(["appearanceId": .string(appearanceID)])], as: Response.self).nudgeRoomTrack.slot
    }

    /// Marks whether an act needs a track.
    @discardableResult
    public func setNeedsTrack(appearanceID: String, needed: Bool) async throws -> RoomSlot {
        struct Payload: Decodable, Sendable { let slot: RoomSlot }
        struct Response: Decodable, Sendable { let setRoomTrackNeeded: Payload }
        return try await session.graphQL("""
            mutation StaffSetRoomTrackNeeded($input: RoomTrackNeededSetInput!) { setRoomTrackNeeded(input: $input) { slot { \(Self.slotFields) } } }
            """, variables: ["input": .object(["appearanceId": .string(appearanceID), "needed": .bool(needed)])],
            as: Response.self).setRoomTrackNeeded.slot
    }

    /// Adds an item to the end of the room's checklist.
    @discardableResult
    public func addChecklistItem(roomID: String, title: String, note: String? = nil) async throws -> RoomChecklistItem {
        struct Payload: Decodable, Sendable { let item: RoomChecklistItem }
        struct Response: Decodable, Sendable { let addRoomChecklistItem: Payload }
        var input: [String: GraphQLValue] = ["roomId": .string(roomID), "title": .string(title)]
        if let note, !note.isEmpty { input["note"] = .string(note) }
        return try await session.graphQL("""
            mutation StaffAddRoomChecklistItem($input: RoomChecklistItemAddInput!) { addRoomChecklistItem(input: $input) { item { \(Self.checklistFields) } } }
            """, variables: ["input": .object(input)], as: Response.self).addRoomChecklistItem.item
    }

    /// Ticks, unticks or renames a checklist item; nil leaves a field as it is.
    @discardableResult
    public func updateChecklistItem(id: String, done: Bool? = nil, title: String? = nil, note: String? = nil) async throws -> RoomChecklistItem {
        struct Payload: Decodable, Sendable { let item: RoomChecklistItem }
        struct Response: Decodable, Sendable { let updateRoomChecklistItem: Payload }
        var input: [String: GraphQLValue] = ["id": .string(id)]
        if let done { input["done"] = .bool(done) }
        if let title { input["title"] = .string(title) }
        if let note { input["note"] = .string(note) }
        return try await session.graphQL("""
            mutation StaffUpdateRoomChecklistItem($input: RoomChecklistItemUpdateInput!) { updateRoomChecklistItem(input: $input) { item { \(Self.checklistFields) } } }
            """, variables: ["input": .object(input)], as: Response.self).updateRoomChecklistItem.item
    }

    /// Takes an item off the checklist.
    public func removeChecklistItem(id: String) async throws {
        _ = try await session.graphQL("""
            mutation StaffRemoveRoomChecklistItem($input: RoomChecklistItemRemoveInput!) { removeRoomChecklistItem(input: $input) { id } }
            """, variables: ["input": .object(["id": .string(id)])], as: GraphQLValue.self)
    }

    // MARK: Pushes

    static let registerDeviceMutation = """
        mutation StaffRegisterDevice($input: DeviceRegisterInput!) { registerDevice(input: $input) { registered } }
        """

    /// Stores this device's APNs token on the session, so messages in the rooms the signed-in person is in push this
    /// app (the API's RoomMessagePush). `appID` is the app's bundle ID, which the push is addressed to.
    public func registerDevice(token: String, appID: String, sandbox: Bool) async throws {
        _ = try await session.graphQL(Self.registerDeviceMutation, variables: ["input": .object([
            "notificationToken": .string(token), "appId": .string(appID), "sandbox": .bool(sandbox)
        ])], as: GraphQLValue.self)
    }
}

/// A push about a new message in a back-of-house room: which room, and the event or venue it's for, so the app can
/// open it. Anything else the app hears (an event reminder, a report) isn't one.
public struct RoomPush: Sendable, Hashable, Identifiable {
    public let roomID: String
    public let messageID: String?
    public let audienceID: String?
    public let place: RoomPlace
    public var id: String { roomID + (messageID ?? "") }

    public init?(userInfo: [AnyHashable: Any]) {
        func string(_ key: String) -> String? {
            if let value = userInfo[key] as? String, !value.isEmpty { return value }
            return (userInfo[key] as? Int).map(String.init)
        }
        guard string("kind") == "room_message", let roomID = string("room_id") else { return nil }
        if let event = string("event_id") { place = .event(event) }
        else if let venue = string("venue_id") { place = .venue(venue) }
        else if let locale = string("locale_id") { place = .locale(locale) }
        else { return nil }
        self.roomID = roomID
        messageID = string("message_id")
        audienceID = string("audience_id")
    }
}

/// Why a file didn't get to storage.
public enum RoomUploadError: Error, LocalizedError, Equatable {
    case tooBig
    case storageRefused(status: Int)

    public var errorDescription: String? {
        switch self {
        case .tooBig: "That file is over 200 MB, the most a room takes."
        case .storageRefused(let status): "Storage didn’t take the file (\(status)). Try again."
        }
    }
}

/// The upload task, for cancelling it from outside the continuation and reading its progress.
private final class TransferBox: @unchecked Sendable {
    var task: URLSessionUploadTask?
}

/// The URL session uploads go through; URLSession is thread-safe, but not marked Sendable everywhere.
private final class TransferSession: @unchecked Sendable {
    let session: URLSession
    init(_ session: URLSession) { self.session = session }
}

/// An ISO 8601 instant from the API, with or without fractional seconds.
public func roomInstant(_ value: String?) -> Date? {
    guard let value else { return nil }
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
}
