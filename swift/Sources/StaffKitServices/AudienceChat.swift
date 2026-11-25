import Foundation
import AudienceCore
import StaffKitCore

/// A venue's or a locale's chat room, as the audience's admins list them: the most recently active first.
public struct AudienceChatRoom: Decodable, Sendable, Identifiable {
    /// Which room to read, post in or clear.
    public enum Address: Sendable, Hashable {
        case venue(String)
        case locale(String)
        public var id: String { switch self { case .venue(let id), .locale(let id): id } }
        public var isVenue: Bool { if case .venue = self { true } else { false } }
    }
    public struct Place: Decodable, Sendable, Hashable {
        public let id: String
        public let name: String?
        /// Where it is, as WKT: its location's point, when the query asked for `location { point }`.
        public let point: String?
        /// How many minutes its room shows guests a message, when the query asked.
        public let chatRetentionMinutes: Int?
        public init(id: String, name: String?, point: String? = nil, chatRetentionMinutes: Int? = nil) {
            self.id = id; self.name = name; self.point = point; self.chatRetentionMinutes = chatRetentionMinutes
        }

        private enum CodingKeys: String, CodingKey { case id, name, location, chatRetentionMinutes }
        private struct Location: Decodable { let point: String? }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            name = try container.decodeIfPresent(String.self, forKey: .name)
            point = try container.decodeIfPresent(Location.self, forKey: .location)?.point
            chatRetentionMinutes = try container.decodeIfPresent(Int.self, forKey: .chatRetentionMinutes)
        }
    }
    public struct Venue: Decodable, Sendable, Hashable {
        public let id: String
        public let photoUrl: String?
        /// The time zone its nights, and its specials, are counted in.
        public let coverTimeZone: String?
        public let locale: Place?
        /// Where it is, as WKT.
        public let point: String?
        /// How many minutes its room shows guests a message, when the query asked.
        public let chatRetentionMinutes: Int?
        public init(id: String, photoUrl: String? = nil, coverTimeZone: String? = nil, locale: Place? = nil, point: String? = nil,
                    chatRetentionMinutes: Int? = nil) {
            self.id = id; self.photoUrl = photoUrl; self.coverTimeZone = coverTimeZone; self.locale = locale; self.point = point
            self.chatRetentionMinutes = chatRetentionMinutes
        }

        private enum CodingKeys: String, CodingKey { case id, photoUrl, tickets, locale, point, chatRetentionMinutes }
        private struct Tickets: Decodable { let cover: Cover? }
        private struct Cover: Decodable { let timeZone: String? }

        // The time zone comes from the venue's cover mixin, inside its tickets: `tickets { cover { timeZone } }`.
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            photoUrl = try container.decodeIfPresent(String.self, forKey: .photoUrl)
            coverTimeZone = try container.decodeIfPresent(Tickets.self, forKey: .tickets)?.cover?.timeZone
            locale = try container.decodeIfPresent(Place.self, forKey: .locale)
            point = try container.decodeIfPresent(String.self, forKey: .point)
            chatRetentionMinutes = try container.decodeIfPresent(Int.self, forKey: .chatRetentionMinutes)
        }
    }

    /// The venue's or the locale's ID.
    public let id: String
    public let name: String?
    /// The latest message, in words; nil when the room is empty.
    public let lastMessage: String?
    public let lastMessageAt: String?
    /// Who sent it, in full, as admins see them.
    public let lastMessageName: String?
    /// Messages in the last 24 hours.
    public let recentCount: Int
    /// People in the room now.
    public let onlineCount: Int
    /// Set for a venue's room.
    public let venue: Venue?
    /// Set for a locale's room.
    public let locale: Place?

    public init(id: String, name: String?, lastMessage: String? = nil, lastMessageAt: String? = nil,
                lastMessageName: String? = nil, recentCount: Int = 0, onlineCount: Int = 0,
                venue: Venue? = nil, locale: Place? = nil) {
        self.id = id; self.name = name; self.lastMessage = lastMessage; self.lastMessageAt = lastMessageAt
        self.lastMessageName = lastMessageName; self.recentCount = recentCount; self.onlineCount = onlineCount
        self.venue = venue; self.locale = locale
    }

    public var address: Address { venue == nil ? .locale(id) : .venue(id) }
    public var isVenue: Bool { venue != nil }
    /// The venue's time zone for its room; the device's for a locale's.
    public var timeZone: TimeZone { venue?.coverTimeZone.flatMap(TimeZone.init(identifier:)) ?? .current }
    public var lastMessageDate: Date? { lastMessageAt.flatMap(Self.instant) }
    /// How long the room shows its guests a message, when the rooms query asked for `chatRetentionMinutes`.
    public var guestWindow: ChatGuestWindow? { ChatGuestWindow(minutes: venue?.chatRetentionMinutes ?? locale?.chatRetentionMinutes) }
    /// Where the room is: the venue's point, or the locale's. Nil when it has none.
    public var coordinate: (latitude: Double, longitude: Double)? { wktCoordinate(venue?.point ?? locale?.point) }

    /// Metres from the point to the room, or nil when the room has no point.
    public func distance(fromLatitude latitude: Double, longitude: Double) -> Double? {
        guard let coordinate else { return nil }
        let radians = Double.pi / 180
        let dLat = (coordinate.latitude - latitude) * radians, dLon = (coordinate.longitude - longitude) * radians
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(latitude * radians) * cos(coordinate.latitude * radians) * sin(dLon / 2) * sin(dLon / 2)
        return 6_371_000 * 2 * atan2(a.squareRoot(), (1 - a).squareRoot())
    }

    /// How near a venue has to be to count as being at it.
    public static let atVenueRadius: Double = 250

    /// The room for someone standing at the point: the nearest venue when they're at one, otherwise the nearest
    /// locale's small talk, otherwise the nearest venue. Nil when no room has a point.
    public static func closest(in rooms: [AudienceChatRoom], latitude: Double, longitude: Double) -> AudienceChatRoom? {
        let measured = rooms.compactMap { room in room.distance(fromLatitude: latitude, longitude: longitude).map { (room, $0) } }
        let venue = measured.filter { $0.0.isVenue }.min { $0.1 < $1.1 }
        if let venue, venue.1 <= atVenueRadius { return venue.0 }
        return measured.filter { !$0.0.isVenue }.min { $0.1 < $1.1 }?.0 ?? venue?.0
    }

    static func instant(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}

/// A message sender's membership in the audience, for kicking or banning them from the room's transcript.
public struct AudienceChatMember: Decodable, Sendable, Hashable, Identifiable {
    /// The membership's ID (not the user's).
    public let id: String
    /// Whether the signed-in admin may kick or ban them: never themself or a platform admin, and only platform
    /// admins may kick or ban the audience's admins.
    public let canModerate: Bool
    /// When they were banned; nil when they aren't.
    public let bannedAt: String?

    public init(id: String, canModerate: Bool, bannedAt: String? = nil) {
        self.id = id; self.canModerate = canModerate; self.bannedAt = bannedAt
    }
    public var isBanned: Bool { bannedAt != nil }
}

/// Chat across the whole audience, for its admins: every venue's and locale's room, the full transcript, posting as
/// staff (or as the venue), pinning, removing, clearing, and kicking or banning a sender. The server checks
/// administrator access on every call.
public struct AudienceChatClient: Sendable {
    public let session: AudienceManagementSession
    public init(session: AudienceManagementSession) { self.session = session }

    /// What a message carries for admins: everything the room shows, and the sender's membership.
    static let messageFields = VenueManagementClient.messageFields + " member { id canModerate bannedAt }"

    /// Every room, the most recently active first.
    public func rooms() async throws -> [AudienceChatRoom] {
        struct Response: Decodable, Sendable {
            struct Chat: Decodable, Sendable { let rooms: GraphQLNodes<AudienceChatRoom> }
            let chat: Chat
        }
        return try await session.graphQL("""
            query AdminChatRooms {
              chat {
                rooms {
                  nodes {
                    id name lastMessage lastMessageAt lastMessageName recentCount onlineCount
                    venue { id photoUrl point chatRetentionMinutes tickets { cover { timeZone } } locale { id name } }
                    locale { id name chatRetentionMinutes location { point } }
                  }
                }
              }
            }
            """, as: Response.self).chat.rooms.nodes
    }

    /// A page of the room's transcript, newest first: the whole history, not just the last day. Pass the page's
    /// `endCursor` as `after` for older messages.
    public func messages(in room: AudienceChatRoom.Address, after: String? = nil, first: Int = 50) async throws -> VenueChatPage {
        struct Response: Decodable, Sendable {
            struct Chat: Decodable, Sendable { let venueMessages: VenueChatPage?; let localeMessages: VenueChatPage? }
            let chat: Chat
        }
        let field = room.isVenue ? "venueMessages(venueId: $id" : "localeMessages(localeId: $id"
        let response = try await session.graphQL("""
            query AdminChatMessages($id: ID!, $first: Int, $after: String) {
              chat {
                \(field), first: $first, after: $after) {
                  edges { node { \(Self.messageFields) } }
                  pageInfo { hasNextPage endCursor }
                }
              }
            }
            """, variables: ["id": .string(room.id), "first": .int(min(max(first, 1), 100)),
                             "after": after.map(GraphQLValue.string) ?? .null], as: Response.self)
        guard let page = response.chat.venueMessages ?? response.chat.localeMessages else {
            throw AudienceKitError.decoding("The chat transcript was missing")
        }
        return page
    }

    /// The announcement pinned under a venue room's title, however old. Locales don't say which is pinned, so
    /// this is nil for them; look for `pinned` in the transcript instead.
    public func pinnedMessage(in room: AudienceChatRoom.Address) async throws -> VenueChatMessage? {
        guard case .venue(let id) = room else { return nil }
        struct Response: Decodable, Sendable {
            struct Chat: Decodable, Sendable { let pinnedMessage: VenueChatMessage? }
            struct Venue: Decodable, Sendable { let chat: Chat }
            struct Venues: Decodable, Sendable { let venue: Venue? }
            let venues: Venues
        }
        return try await session.graphQL("query AdminPinnedMessage($id: ID!) { venues { venue(id: $id) { chat { pinnedMessage { \(Self.messageFields) } } } } }",
                                       variables: ["id": .string(id)], as: Response.self).venues.venue?.chat.pinnedMessage
    }

    /// Posts to the room as the signed-in admin, tagged STAFF, or with `asVenue` as the venue (venue rooms only).
    /// Returns the message as the room shows it. A SPECIAL's `endsAt` must be after now and within 24 hours; `pinned`
    /// pins an ANNOUNCEMENT in place of the pinned one.
    @discardableResult
    public func send(in room: AudienceChatRoom.Address, message: String, asVenue: Bool = false, kind: String = "TEXT",
                     title: String? = nil, photo: String? = nil, eventID: String? = nil, endsAt: String? = nil,
                     pinned: Bool = false) async throws -> VenueChatMessage? {
        struct Response: Decodable, Sendable {
            struct Payload: Decodable, Sendable { let venueMessage: VenueChatMessage?; let localeMessage: VenueChatMessage? }
            let sendChatMessage: Payload?
        }
        var input: [String: GraphQLValue] = [room.isVenue ? "venueId" : "localeId": .string(room.id),
                                            "message": .string(message), "kind": .string(kind)]
        if asVenue { input["asVenue"] = .bool(true) }
        if pinned { input["pinned"] = .bool(true) }
        if let title { input["title"] = .string(title) }
        if let photo { input["photo"] = .string(photo) }
        if let eventID { input["eventId"] = .string(eventID) }
        if let endsAt { input["endsAt"] = .string(endsAt) }
        let payload = try await session.graphQL("""
            mutation AdminSendMessage($input: ChatMessageSendInput!) {
              sendChatMessage(input: $input) { venueMessage { \(Self.messageFields) } localeMessage { \(Self.messageFields) } }
            }
            """, variables: ["input": .object(input)], as: Response.self).sendChatMessage
        return payload?.venueMessage ?? payload?.localeMessage
    }

    /// Pins an announcement under its room's title, in place of the pinned one, or unpins it.
    public func pin(messageID: String, pinned: Bool) async throws {
        try await operation("pinChatMessage", inputType: "ChatMessagePinInput",
                            input: ["id": .string(messageID), "pinned": .bool(pinned)],
                            selection: "venueMessage { id pinned } localeMessage { id pinned }")
    }

    /// Takes a message out of its room for everyone, and out of the transcript.
    public func remove(messageID: String) async throws {
        try await operation("removeChatMessage", inputType: "ChatMessageRemoveInput", input: ["id": .string(messageID)],
                            selection: "deletedId")
    }

    /// Removes every message in the room, for everyone; returns how many.
    @discardableResult
    public func clear(_ room: AudienceChatRoom.Address) async throws -> Int {
        struct Response: Decodable, Sendable {
            struct Payload: Decodable, Sendable { let removedCount: Int }
            let clearChatRoom: Payload
        }
        return try await session.graphQL("""
            mutation AdminClearRoom($input: ChatRoomClearInput!) { clearChatRoom(input: $input) { removedCount } }
            """, variables: ["input": .object([room.isVenue ? "venueId" : "localeId": .string(room.id)])],
            as: Response.self).clearChatRoom.removedCount
    }

    /// Signs the member out of the audience everywhere and drops them from any chat they have open. They can sign in
    /// again.
    @discardableResult
    public func kick(memberID: String) async throws -> AudienceChatMember {
        try await membership("kickAudienceMember", inputType: "AudienceMemberKickInput", input: ["id": .string(memberID)])
    }

    /// Kicks the member and keeps them out: they can't sign in on the audience or chat in its rooms until unbanned.
    /// `reason` is for the audience's admins; the member isn't shown it.
    @discardableResult
    public func ban(memberID: String, reason: String? = nil) async throws -> AudienceChatMember {
        var input: [String: GraphQLValue] = ["id": .string(memberID)]
        if let reason = reason?.trimmingCharacters(in: .whitespacesAndNewlines), !reason.isEmpty { input["reason"] = .string(reason) }
        return try await membership("banAudienceMember", inputType: "AudienceMemberBanInput", input: input)
    }

    /// Lifts a ban: they can sign in and chat again.
    @discardableResult
    public func unban(memberID: String) async throws -> AudienceChatMember {
        try await membership("unbanAudienceMember", inputType: "AudienceMemberUnbanInput", input: ["id": .string(memberID)])
    }

    private func membership(_ name: String, inputType: String, input: [String: GraphQLValue]) async throws -> AudienceChatMember {
        struct Payload: Decodable, Sendable { let member: AudienceChatMember }
        let response = try await session.graphQL("""
            mutation AdminMembership($input: \(inputType)!) { \(name)(input: $input) { member { id canModerate bannedAt } } }
            """, variables: ["input": .object(input)], as: [String: Payload].self)
        guard let member = response[name]?.member else { throw AudienceKitError.decoding("The member was missing") }
        return member
    }

    private func operation(_ name: String, inputType: String, input: [String: GraphQLValue], selection: String) async throws {
        _ = try await session.graphQL("mutation AdminChatOperation($input: \(inputType)!) { \(name)(input: $input) { \(selection) } }",
                                   variables: ["input": .object(input)], as: GraphQLValue.self)
    }
}
