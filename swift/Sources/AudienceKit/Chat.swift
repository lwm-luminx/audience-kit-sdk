import AudienceCore
import Foundation

/// A chat room: a venue's, or a locale's (out in the city, away from its venues).
public enum ChatRoom: Hashable, Sendable {
    case venue(id: String)
    case locale(id: String)

    /// The venue's or locale's ID.
    public var id: String {
        switch self {
        case let .venue(id), let .locale(id): id
        }
    }

    /// Its subscription field (`venueChat`, `localeChat`).
    var subscriptionField: String {
        switch self {
        case .venue: "venueChat"
        case .locale: "localeChat"
        }
    }

    /// The argument naming it, on its subscription and on `sendMyChatMessage`'s input.
    var argumentName: String {
        switch self {
        case .venue: "venueId"
        case .locale: "localeId"
        }
    }
}

/// One message in a chat room: the API's `ChatMessage` (or `VenueMessage`, its stored form).
public struct ChatMessage: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    /// What it says, rendered for display (a photo or event message's caption, say).
    public let body: String
    /// The text as sent.
    public let message: String
    /// Who sent it, as the room shows them (non-friends as "First L."), or the venue's name.
    public let name: String?
    public let userId: String?
    public let avatarUrl: String?
    /// A photo message's photo.
    public let photoUrl: String?
    public let sentAt: Date?
    /// The API's `ChatRole` (`HOST`, `STAFF`, `VENUE`); nil for a member.
    public let role: String?
    /// The API's `ChatKind`: `TEXT`, `ANNOUNCEMENT`, `PHOTO`, `EVENT`, `SPECIAL`, `PROMPT`, `REQUEST`.
    public let kind: String
    /// An announcement or special's title.
    public let title: String?
    /// Whether it's the room's pinned message.
    public let pinned: Bool

    public init(id: String, body: String, message: String? = nil, name: String? = nil, userId: String? = nil,
                avatarUrl: String? = nil, photoUrl: String? = nil, sentAt: Date? = nil, role: String? = nil,
                kind: String = "TEXT", title: String? = nil, pinned: Bool = false)
    {
        self.id = id
        self.body = body
        self.message = message ?? body
        self.name = name
        self.userId = userId
        self.avatarUrl = avatarUrl
        self.photoUrl = photoUrl
        self.sentAt = sentAt
        self.role = role
        self.kind = kind
        self.title = title
        self.pinned = pinned
    }

    private enum CodingKeys: String, CodingKey {
        case id, body, message, name, userId, avatarUrl, photoUrl, sentAt, role, kind, title, pinned
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        let message = try container.decodeIfPresent(String.self, forKey: .message)
        body = try container.decodeIfPresent(String.self, forKey: .body) ?? message ?? ""
        self.message = message ?? body
        name = try container.decodeIfPresent(String.self, forKey: .name)
        userId = try container.decodeIfPresent(String.self, forKey: .userId)
        avatarUrl = try container.decodeIfPresent(String.self, forKey: .avatarUrl)
        photoUrl = try container.decodeIfPresent(String.self, forKey: .photoUrl)
        sentAt = try container.decodeISO8601IfPresent(forKey: .sentAt)
        role = try container.decodeIfPresent(String.self, forKey: .role)
        kind = try container.decodeIfPresent(String.self, forKey: .kind) ?? "TEXT"
        title = try container.decodeIfPresent(String.self, forKey: .title)
        pinned = try container.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(body, forKey: .body)
        try container.encode(message, forKey: .message)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(userId, forKey: .userId)
        try container.encodeIfPresent(avatarUrl, forKey: .avatarUrl)
        try container.encodeIfPresent(photoUrl, forKey: .photoUrl)
        try container.encodeIfPresent(sentAt.map(ISO8601.string(from:)), forKey: .sentAt)
        try container.encodeIfPresent(role, forKey: .role)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encode(pinned, forKey: .pinned)
    }
}

/// Someone in a chat room when you join it: the API's `ChatRosterPerson`.
public struct ChatRosterPerson: Codable, Sendable, Hashable, Identifiable {
    public let userId: String
    public let name: String?
    public let avatarUrl: String?
    /// Whether they're the signed-in user's friend.
    public let friend: Bool

    public var id: String { userId }

    public init(userId: String, name: String? = nil, avatarUrl: String? = nil, friend: Bool = false) {
        self.userId = userId
        self.name = name
        self.avatarUrl = avatarUrl
        self.friend = friend
    }
}

/// What a chat room's subscription sends (the API's `ChatRoomEvent` union), decoded.
public enum ChatRoomEvent: Sendable, Hashable {
    /// Joined: who's here, the recent history (oldest first) and the pinned message. `outOfRange` is true when the
    /// signed-in user isn't at the venue, so they can read but not post.
    case joined(people: [ChatRosterPerson], history: [ChatMessage], pinned: ChatMessage?, outOfRange: Bool)
    case posted(ChatMessage)
    case updated(ChatMessage)
    case removed(messageID: String)
    /// A message was pinned or unpinned; `announcement` is the message now pinned, if any.
    case pinChanged(messageID: String, pinned: Bool, announcement: ChatMessage?)
    /// The room was cleared (`expired` when its retention ran out rather than a host clearing it).
    case cleared(at: Date?, expired: Bool)
    case presenceChanged(userID: String, name: String?, avatarUrl: String?, presence: String)
    case rangeChanged(outOfRange: Bool)
    /// The server took the user out of the room: the API's `ChatLeftReason` (`AWAY`, `BANNED`, `MOVED`, `REMOVED`).
    case left(reason: String)
    /// An event this SDK doesn't know yet, by its `__typename`.
    case unknown(String)
}

/// A chat room subscription's progress (``AudienceCable/chat(_:watch:audienceID:)``).
public enum ChatRoomUpdate: Sendable {
    /// The subscription is running: events arrive from now on. Sent again after every reconnect.
    case subscribed
    case event(ChatRoomEvent)
    /// The server refused the subscription (not at the venue, say), with its errors. The stream ends after this.
    case refused([GraphQLError])
    /// The socket dropped; the cable reconnects unless `reconnects` is false.
    case disconnected(reason: String?, reconnects: Bool)
}

/// A venue's page: the venue and what the modules its audience has add to it. A module the audience hasn't
/// installed leaves its part nil.
public struct VenueDetail: Sendable, Hashable {
    public let venue: Venue
    public let description: String?
    /// Its street address, phone, website and social links (Listings).
    public let address: String?
    public let phone: String?
    public let website: String?
    public let socialLinks: [SocialLink]?
    /// Whether its chat room is open, and its latest messages (Chat).
    public let chatOpen: Bool?
    public let recentMessages: [ChatMessage]?
    /// Its upcoming events, soonest first (Events).
    public let upcomingEvents: [Event]?
}

/// One of a venue's or person's social media profiles: the API's `SocialLink`.
public struct SocialLink: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let handle: String
    /// `instagram`, `tiktok`, `x`, `discord`…
    public let provider: String
    public let url: String?

    public init(id: String, handle: String, provider: String, url: String? = nil) {
        self.id = id
        self.handle = handle
        self.provider = provider
        self.url = url
    }
}

extension Queries {
    static let chatMessageFields = "id body message name userId avatarUrl photoUrl sentAt role kind title pinned"

    static let venueDetailTypes = listingTypes + ["EventSeries"]

    static func venueDetail(_ shape: SchemaShape) -> String {
        var fields = venueFields(shape) + " description"
        if shape.has("Venue", "profile") {
            fields += " profile { address phone website socialLinks { nodes { id handle provider url } } }"
        }
        if shape.has("Venue", "chat") {
            fields += " chat { open recentMessages(limit: 20) { nodes { \(chatMessageFields) } } }"
        }
        if shape.has("Venue", "events") {
            fields += " events { upcoming(first: 20) { nodes { \(eventFields(shape)) } } }"
        }
        return """
        query VenueDetail($id: ID!) {
          venues { venue(id: $id) { \(fields) } }
        }
        """
    }

    static let sendChatMessage = """
    mutation SendMyChatMessage($input: ChatMessageSendOwnInput!) {
      sendMyChatMessage(input: $input) { message { \(chatMessageFields) } }
    }
    """

    static let removeChatMessage = """
    mutation RemoveMyChatMessage($messageId: ID!) {
      removeMyChatMessage(input: { messageId: $messageId }) { deletedId }
    }
    """

    /// A chat room's subscription, aliased to `room` whichever field it is.
    static func chatRoom(_ room: ChatRoom, watch: Bool) -> String {
        """
        subscription ChatRoom($id: ID!) {
          room: \(room.subscriptionField)(\(room.argumentName): $id\(watch ? ", watch: true" : "")) {
            __typename
            ... on ChatJoined {
              outOfRange
              roster { people { userId name avatarUrl friend } }
              history { message { ...Line } }
              pinnedMessage { message { ...Line } }
            }
            ... on ChatMessagePosted { message { ...Line } }
            ... on ChatMessageUpdated { message { ...Line } }
            ... on ChatMessageRemoved { messageId }
            ... on ChatPinChanged { messageId pinned announcement { ...Line } }
            ... on ChatRoomCleared { clearedAt expired }
            ... on ChatPresenceChanged { userId name avatarUrl presence }
            ... on ChatRangeChanged { outOfRange }
            ... on ChatLeft { reason }
          }
        }
        fragment Line on ChatMessage { \(chatMessageFields) }
        """
    }
}

/// `venues { venue(id:) }` with the venue page's fields.
struct VenueDetailResponse: Decodable, Sendable {
    struct Wire: Decodable, Sendable {
        struct Profile: Decodable, Sendable {
            var address: String?
            var phone: String?
            var website: String?
            var socialLinks: Nodes<SocialLink>?
        }

        struct Chat: Decodable, Sendable {
            var open: Bool?
            var recentMessages: Nodes<ChatMessage>?
        }

        struct Events: Decodable, Sendable { var upcoming: Nodes<Event>? }

        var venue: Venue
        var description: String?
        var profile: Profile?
        var chat: Chat?
        var events: Events?

        private enum CodingKeys: String, CodingKey { case description, profile, chat, events }

        init(from decoder: any Decoder) throws {
            venue = try Venue(from: decoder)
            let container = try decoder.container(keyedBy: CodingKeys.self)
            description = try container.decodeIfPresent(String.self, forKey: .description)
            profile = try container.decodeIfPresent(Profile.self, forKey: .profile)
            chat = try container.decodeIfPresent(Chat.self, forKey: .chat)
            events = try container.decodeIfPresent(Events.self, forKey: .events)
        }
    }

    struct Mixin: Decodable, Sendable { var venue: Wire? }

    var venues: Mixin?
}

struct SendChatMessageResponse: Decodable, Sendable {
    struct Payload: Decodable, Sendable { var message: ChatMessage }
    var sendMyChatMessage: Payload
}

struct RemoveChatMessageResponse: Decodable, Sendable {
    struct Payload: Decodable, Sendable { var deletedId: String? }
    var removeMyChatMessage: Payload?
}

extension AudienceSession {
    /// A venue's page, or `nil` when it doesn't exist or belongs to another audience.
    public func venueDetail(id: String) async throws -> VenueDetail? {
        let wire = try await graphQL(types: Queries.venueDetailTypes, variables: ["id": .string(id)],
                                     operationName: "VenueDetail", as: VenueDetailResponse.self,
                                     document: Queries.venueDetail).venues?.venue
        return wire.map { wire in
            VenueDetail(venue: wire.venue, description: wire.description, address: wire.profile?.address,
                        phone: wire.profile?.phone, website: wire.profile?.website,
                        socialLinks: wire.profile?.socialLinks?.nodes, chatOpen: wire.chat?.open,
                        recentMessages: wire.chat?.recentMessages?.nodes, upcomingEvents: wire.events?.upcoming?.nodes)
        }
    }

    /// Posts the signed-in user's message to a chat room, as a reply to a chat prompt when `promptID` is given.
    @discardableResult
    public func sendChatMessage(_ text: String, in room: ChatRoom, promptID: String? = nil) async throws
        -> ChatMessage
    {
        var input: [String: GraphQLValue] = [room.argumentName: .string(room.id), "message": .string(text)]
        if let promptID { input["promptId"] = .string(promptID) }
        return try await graphQL(Queries.sendChatMessage, variables: ["input": .object(input)],
                                 operationName: "SendMyChatMessage", as: SendChatMessageResponse.self)
            .sendMyChatMessage.message
    }

    /// Takes back one of the signed-in user's own messages.
    public func removeChatMessage(id: String) async throws {
        _ = try await graphQL(Queries.removeChatMessage, variables: ["messageId": .string(id)],
                              operationName: "RemoveMyChatMessage", as: RemoveChatMessageResponse.self)
    }
}

extension AudienceCable {
    /// Joins a chat room (or, with `watch`, follows it without being in it: no presence, so nobody sees the user in
    /// chat) and streams what happens in it. Ending the iteration leaves the room.
    public func chat(_ room: ChatRoom, watch: Bool = false, audienceID: String) -> AsyncStream<ChatRoomUpdate> {
        let events = subscribe(query: Queries.chatRoom(room, watch: watch), variables: ["id": .string(room.id)],
                               operationName: "ChatRoom", audienceID: audienceID)
        return AsyncStream { continuation in
            let task = Task {
                for await event in events {
                    switch event {
                    case .subscribed:
                        continuation.yield(.subscribed)
                    case let .result(data):
                        switch ChatRoomEvent.decode(result: data) {
                        case let .success(event)?: continuation.yield(.event(event))
                        case let .failure(errors)?:
                            continuation.yield(.refused(errors))
                            continuation.finish()
                            return
                        case nil: break
                        }
                    case .rejected:
                        continuation.yield(.refused([]))
                        continuation.finish()
                        return
                    case let .disconnected(reason, reconnects):
                        continuation.yield(.disconnected(reason: reason, reconnects: reconnects))
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

extension ChatRoomEvent {
    enum Decoded {
        case success(ChatRoomEvent)
        case failure([GraphQLError])
    }

    /// One subscription result (`{ "data": { "room": … }, "errors": … }`): the event, the server's refusal (errors
    /// and no data), or nil when it carries neither (the subscription's empty first result).
    static func decode(result data: Data) -> Decoded? {
        guard let envelope = try? JSONDecoder.audienceKit.decode(ChatRoomResult.self, from: data) else { return nil }
        if let wire = envelope.data?.room { return .success(wire.event) }
        if let errors = envelope.errors, !errors.isEmpty { return .failure(errors) }
        return nil
    }

    /// Every `ChatRoomEvent` member's fields, flattened.
    struct Wire: Decodable {
        struct Posted: Decodable { var message: ChatMessage }
        struct Roster: Decodable { var people: [ChatRosterPerson]? }

        var __typename: String
        var outOfRange: Bool?
        var roster: Roster?
        var history: [Posted]?
        var pinnedMessage: Posted?
        var message: ChatMessage?
        var messageId: String?
        var pinned: Bool?
        var announcement: ChatMessage?
        var clearedAt: String?
        var expired: Bool?
        var userId: String?
        var name: String?
        var avatarUrl: String?
        var presence: String?
        var reason: String?

        var event: ChatRoomEvent {
            switch __typename {
            case "ChatJoined":
                return .joined(people: roster?.people ?? [], history: history?.map(\.message) ?? [],
                               pinned: pinnedMessage?.message, outOfRange: outOfRange ?? false)
            case "ChatMessagePosted":
                return message.map(ChatRoomEvent.posted) ?? .unknown(__typename)
            case "ChatMessageUpdated":
                return message.map(ChatRoomEvent.updated) ?? .unknown(__typename)
            case "ChatMessageRemoved":
                return messageId.map { .removed(messageID: $0) } ?? .unknown(__typename)
            case "ChatPinChanged":
                return messageId.map { .pinChanged(messageID: $0, pinned: pinned ?? false, announcement: announcement) }
                    ?? .unknown(__typename)
            case "ChatRoomCleared":
                return .cleared(at: clearedAt.flatMap(ISO8601.date(from:)), expired: expired ?? false)
            case "ChatPresenceChanged":
                return userId.map {
                    .presenceChanged(userID: $0, name: name, avatarUrl: avatarUrl, presence: presence ?? "OFFLINE")
                } ?? .unknown(__typename)
            case "ChatRangeChanged":
                return .rangeChanged(outOfRange: outOfRange ?? false)
            case "ChatLeft":
                return .left(reason: reason ?? "REMOVED")
            default:
                return .unknown(__typename)
            }
        }
    }
}

/// One result of a chat room's subscription.
private struct ChatRoomResult: Decodable {
    struct Room: Decodable { var room: ChatRoomEvent.Wire? }
    var data: Room?
    var errors: [GraphQLError]?
}
