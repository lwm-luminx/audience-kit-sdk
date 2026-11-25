import Foundation
import AudienceCore
import StaffKitCore

/// What a staff app hears in a chat room: the API's `venueChat` and `localeChat` subscriptions, over the cable. The
/// messages come back as the same `VenueChatMessage` the GraphQL reads return, so a screen can mix the two.
public enum VenueChatEvent: Sendable {
    /// The room as it stands (`ChatJoined`), sent on joining and again after a reconnect: its recent messages, newest
    /// first like a `VenueChatPage`, and the announcement pinned under its title.
    case history([VenueChatMessage], pinned: VenueChatMessage?)
    /// Someone posted.
    case message(VenueChatMessage)
    /// An announcement or special was edited.
    case updated(VenueChatMessage)
    /// A message was taken out of the room.
    case removed(id: String)
    /// Everything sent up to `before` (an ISO 8601 instant) was removed: an admin cleared the room, or (`expired`) its
    /// oldest messages passed its chat retention, which leaves the pinned announcement up.
    case cleared(before: String, expired: Bool)
    /// When the room stops showing messages to its guests (an ISO 8601 instant): staff are sent older ones, which a
    /// screen guests see (the TV) leaves out. `ChatJoined` says it right after ``history(_:pinned:)``.
    case expiry(before: String)
    /// An announcement was pinned under the room's title, replacing whichever was.
    case pinned(VenueChatMessage)
    /// The pinned announcement came down.
    case unpinned(id: String)
    /// Whether the subscriber is in the room only because they're staff (they're not at the place). `ChatJoined`
    /// says it first, right after ``history(_:pinned:)``.
    case range(outOfRange: Bool)
    /// The server took the subscriber out of the room (kicked, banned, or no longer there). The feed ends.
    case left
    /// The server turned the subscription away: no access to this room. The feed ends.
    case rejected
    /// The socket dropped; the cable is reconnecting (`nil` reason) or gave up (the session ended).
    case offline(String?)
}

extension VenueChatMessage {
    /// This message with its pinned flag changed, for a room that heard a pin or unpin.
    public func withPinned(_ pinned: Bool) -> VenueChatMessage {
        VenueChatMessage(id: id, message: message, body: body, avatarUrl: avatarUrl, presence: presence, endsAt: endsAt,
                         event: event, name: name, sentAt: sentAt, userId: userId, role: role, kind: kind, title: title,
                         photoUrl: photoUrl, pinned: pinned, postedAsVenue: postedAsVenue, automatic: automatic, member: member,
                         postedAsPerson: postedAsPerson, personId: personId, prompt: prompt, promptId: promptId,
                         postedAsAudience: postedAsAudience)
    }

    /// Whether the room's guests still see it at `date`, as Hot Mess shows the room: not sent before the room's
    /// `expiresBefore` (staff are sent older messages), and not a special past its end.
    public func showsToGuests(expiresBefore: String?, at date: Date = Date()) -> Bool {
        if let cutoff = parseInstant(expiresBefore), let sent = parseInstant(sentAt), sent < cutoff { return false }
        if kind == "SPECIAL", let end = parseInstant(endsAt), end <= date { return false }
        return true
    }

    /// Whether it was sent at or before `instant` (ISO 8601), so a clearing up to then takes it.
    public func sent(atOrBefore instant: String) -> Bool {
        guard let cutoff = parseInstant(instant), let sent = parseInstant(sentAt) else { return true }
        return sent <= cutoff
    }
}

extension VenueManagementClient {
    /// Follows a room live, as the audience's staff. The first `history` event carries the room as it stands, so a
    /// screen can start from it or from a `chat(venueID:)` page. Ending the iteration leaves the room.
    public func chatFeed(room: AudienceChatRoom.Address) async -> AsyncStream<VenueChatEvent> {
        // A venue device may only select the fields its policy lists; who posted as a listing isn't one of them.
        let (query, variables) = Self.chatSubscription(for: room, withPeople: !(await session.isVenueDevice))
        let results = await session.subscribe(query, variables: variables)
        return AsyncStream { continuation in
            let task = Task {
                for await result in results {
                    for event in Self.chatEvents(from: result) {
                        continuation.yield(event)
                        if case .rejected = event { continuation.finish(); return }
                        if case .left = event { continuation.finish(); return }
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Follows a venue's room live.
    public func chatFeed(venueID: String) async -> AsyncStream<VenueChatEvent> {
        await chatFeed(room: .venue(venueID))
    }

    /// The subscription that follows a room, and its variables. `withPeople` adds which listing posted a message.
    static func chatSubscription(for room: AudienceChatRoom.Address, withPeople: Bool) -> (String, [String: GraphQLValue]) {
        let field: String, argument: String, name: String, id: String
        switch room {
        case .venue(let venue): (field, argument, name, id) = ("venueChat", "venueId", "StaffVenueChat", venue)
        case .locale(let locale): (field, argument, name, id) = ("localeChat", "localeId", "StaffLocaleChat", locale)
        }
        let fields = messageFields + (withPeople ? " postedAsPerson person { id }" : "")
        // Inline fragments on the concrete types, which is where a device's field policy looks. `pinned` means a
        // message on ChatJoined and a flag on ChatPinChanged, so both are aliased.
        let query = """
            subscription \(name)($id: ID!) {
              \(field)(\(argument): $id) {
                __typename
                ... on ChatJoined { outOfRange expiresBefore history { message { ...StaffChatMessage } } pinnedPost: pinnedMessage { message { ...StaffChatMessage } } }
                ... on ChatMessagePosted { message { ...StaffChatMessage } }
                ... on ChatMessageUpdated { message { ...StaffChatMessage } }
                ... on ChatMessageRemoved { messageId }
                ... on ChatPinChanged { messageId isPinned: pinned announcement { ...StaffChatMessage } }
                ... on ChatRoomCleared { clearedAt expired }
                ... on ChatRangeChanged { outOfRange }
                ... on ChatLeft { reason }
              }
            }
            fragment StaffChatMessage on ChatMessage {
              ... on VenueMessage { \(fields) }
              ... on LocaleMessage { \(fields) }
            }
            """
        return (query, ["id": .string(id)])
    }

    static func chatEvents(from event: AudienceCable.Event) -> [VenueChatEvent] {
        switch event {
        case .rejected: return [.rejected]
        case .disconnected(let reason, let reconnects): return [.offline(reconnects ? nil : (reason ?? "Signed out"))]
        case .result(let data): return chatEvents(from: data)
        default: return []  // subscribed
        }
    }

    /// The chat events one subscription result means: none for an event a staff screen doesn't act on (who comes
    /// and goes, a kind this build doesn't know), `rejected` for a refusal (errors and no event).
    static func chatEvents(from data: Data) -> [VenueChatEvent] {
        struct Posted: Decodable { let message: VenueChatMessage }
        struct Event: Decodable {
            let __typename: String
            let outOfRange: Bool?
            let history: [Posted]?
            let pinnedPost: Posted?
            let message: VenueChatMessage?
            let messageId: String?
            let isPinned: Bool?
            let announcement: VenueChatMessage?
            let clearedAt: String?
            let expired: Bool?
            let expiresBefore: String?
        }
        struct Room: Decodable { let venueChat: Event?; let localeChat: Event? }
        guard let result = try? JSONDecoder().decode(GraphQLSubscriptionResult<Room>.self, from: data) else { return [] }
        guard let event = result.data?.venueChat ?? result.data?.localeChat else {
            return result.refused ? [.rejected] : []
        }
        switch event.__typename {
        case "ChatJoined":
            let recent = (event.history ?? []).reversed().map(\.message)
            return [.history(recent, pinned: event.pinnedPost?.message)]
                + (event.expiresBefore.map { [.expiry(before: $0)] } ?? [])
                + [.range(outOfRange: event.outOfRange ?? false)]
        case "ChatMessagePosted":
            return event.message.map { [.message($0)] } ?? []
        case "ChatMessageUpdated":
            return event.message.map { [.updated($0)] } ?? []
        case "ChatMessageRemoved":
            return event.messageId.map { [.removed(id: $0)] } ?? []
        case "ChatRoomCleared":
            return event.clearedAt.map { [.cleared(before: $0, expired: event.expired ?? false)] } ?? []
        case "ChatPinChanged":
            if event.isPinned == true, let announcement = event.announcement { return [.pinned(announcement)] }
            return event.messageId.map { [.unpinned(id: $0)] } ?? []
        case "ChatRangeChanged":
            return [.range(outOfRange: event.outOfRange ?? false)]
        case "ChatLeft":
            return [.left]
        default:
            return []
        }
    }
}

/// One subscription result: the event, or the errors that refused it.
struct GraphQLSubscriptionResult<Payload: Decodable>: Decodable {
    struct Failure: Decodable { let message: String? }
    let data: Payload?
    let errors: [Failure]?

    /// Whether the server refused the operation: errors and nothing to show for it.
    var refused: Bool { !(errors ?? []).isEmpty }
}
