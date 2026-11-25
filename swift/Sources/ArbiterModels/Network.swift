import Foundation

/// One frame of the audience's chat moderation feed (Subscription.chatModeration), as the host reads it.
public enum ModerationFeedFrame: Sendable, Hashable {
    /// A new message: the room's earlier lines, then the message itself, last.
    case message(cursor: String, at: Date, room: ChatRoom, lines: [ChatLine])
    /// Every kept event after the cursor asked for has been sent; what follows is live.
    case caughtUp(cursor: String?)
    /// Events were dropped (kept for seven days): the host starts again from now.
    case gap
    /// Something Glam's fast lane did on the backend, for this Mac to review (only while the fast lane is on).
    case glamOutput(GlamOutputEvent)
}

public extension ModerationFeedFrame {
    /// The feed cursor of an event frame (a message or a fast-lane output); nil for the feed's own markers.
    var feedCursor: String? {
        switch self {
        case let .message(cursor, _, _, _): cursor
        case let .glamOutput(event): event.cursor
        case .caughtUp, .gap: nil
        }
    }
}

/// The chat moderation feed over the network, on this device's token with the chat feed (StaffKit implements it).
/// Messages the host posted itself are left out.
public protocol ModerationFeed: Sendable {
    /// Every kept event after `after` (all seven days without it), then `.caughtUp`, then each new event, until the
    /// stream is cancelled. Throws (finishes with an error) when the API refuses the token.
    func follow(after: String?) -> AsyncThrowingStream<ModerationFeedFrame, Error>
}

/// The host's actions on the moderation contract (Mutation.chat.moderation.*, api doc/CHAT_MODERATION.md "Hosting"),
/// and the room info its read tools fetch (Query.chat.moderation.room). StaffKit implements it.
public protocol HostActions: Sendable {
    /// Runs one step (its `field` names the mutation, its `input` the mutation's input); throws the API's message.
    func perform(_ step: HostStep) async throws
    /// What the host may tell the room of a feed event about where it is: a venue's details and tonight, or a locale's
    /// events tonight, plus `days` more days of events. The API leaves out performers the sender has a block with.
    func roomInfo(cursor: String, days: Int) async throws -> JSONValue?
    /// Private, minimal safety context for the newest sender; never room-facing content.
    func referenceData(cursor: String) async throws -> JSONValue?
    func userSafetyContext(cursor: String) async throws -> JSONValue?
    /// Sends Arbiter's verdict on one of the fast lane's outputs (Mutation.chat.moderation.reviewGlamOutput).
    func reviewGlamOutput(_ review: GlamOutputReview) async throws
}

public extension HostActions {
    func referenceData(cursor: String) async throws -> JSONValue? { throw CocoaError(.featureUnsupported) }
    func userSafetyContext(cursor: String) async throws -> JSONValue? {
        throw CocoaError(.featureUnsupported)
    }
    func reviewGlamOutput(_ review: GlamOutputReview) async throws { throw CocoaError(.featureUnsupported) }
}
