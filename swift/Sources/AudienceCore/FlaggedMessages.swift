import Foundation

/// What venue staff do about a message the audience's AI host flagged in their room: the API's `FlaggedMessageAction`
/// (`reviewFlaggedMessage`). Velvet's simple version of the admins' moderation decisions.
public enum FlaggedMessageAction: String, Codable, Sendable, CaseIterable, Hashable, Identifiable {
    /// Nothing to do: it leaves the list.
    case dismiss = "DISMISS"
    /// Takes the message out of the room for everyone.
    case remove = "REMOVE"
    /// A private line from the venue to the sender, which only they see, and a push.
    case warn = "WARN"
    /// Out of the room for a few minutes (``FlaggedMessages/cooldownMinutes`` unless the app says).
    case cooldown = "COOLDOWN"
    /// Files it in the audience admins' Reports queue for a closer look: the existing flow for anything bigger.
    case escalate = "ESCALATE"
    /// Bans the sender from the venue. Always confirm first (``FlaggedMessageCopy/banTitle``).
    case ban = "BAN"

    public var id: String { rawValue }

    /// The one-tap actions, in the order a row offers them. Ban sits apart, behind its own confirmation.
    public static let quick: [FlaggedMessageAction] = [.dismiss, .remove, .warn, .cooldown]

    /// The button's label.
    public var title: String {
        switch self {
        case .dismiss: "Dismiss"
        case .remove: "Remove"
        case .warn: "Warn"
        case .cooldown: "Cooldown"
        case .escalate: "Escalate"
        case .ban: "Ban"
        }
    }

    /// What it did, once done ("Removed").
    public var doneTitle: String {
        switch self {
        case .dismiss: "Dismissed"
        case .remove: "Removed"
        case .warn: "Warned"
        case .cooldown: "Cooled down"
        case .escalate: "Escalated"
        case .ban: "Banned"
        }
    }

    /// An SF Symbol for the button.
    public var systemImage: String {
        switch self {
        case .dismiss: "checkmark"
        case .remove: "trash"
        case .warn: "exclamationmark.bubble"
        case .cooldown: "timer"
        case .escalate: "arrow.up.forward.circle"
        case .ban: "nosign"
        }
    }

    /// Whether it acts on the sender or their message; only ``dismiss`` and ``escalate`` don't, and only those apply
    /// to someone who runs the room.
    public var actsOnSender: Bool { self != .dismiss && self != .escalate }

    /// Whether the app asks before doing it.
    public var needsConfirmation: Bool { self == .ban }
}

/// A message in a venue's room the AI host flagged or ruled something about, as its staff see it (`Venue.flaggedMessages`
/// on the staff endpoint): the message, why, and what the host suggests.
public struct FlaggedMessage: Decodable, Sendable, Identifiable, Hashable {
    /// For ``FlaggedMessages/reviewVariables(id:action:minutes:text:)``.
    public let id: String
    /// The venue message's ID; nil when AudienceKit has no transcript of it.
    public let messageId: String?
    public let text: String?
    public let sentAt: String?
    public let senderId: String?
    /// As the room shows them ("Aurora B.").
    public let senderName: String?
    /// The sender runs the room (staff, a manager, the venue): only ``FlaggedMessageAction/dismiss`` and
    /// ``FlaggedMessageAction/escalate`` apply.
    public let senderRunsRoom: Bool
    /// Why it was flagged, in a line.
    public let reason: String
    /// The policy category (e.g. `DRUG_SALES`), and in words.
    public let category: String?
    public let categoryTitle: String?
    /// What the host ruled, e.g. `private_nudge`, `ban_proposal`.
    public let ruling: String?
    public let confidence: Double?
    public let suggestedAction: FlaggedMessageAction
    /// What the server already did about it (the host removed it, a provider banned the sender).
    public let doneActions: [FlaggedMessageAction]
    /// Already out of the room.
    public let removed: Bool
    /// What staff did; nil while it waits.
    public let review: FlaggedMessageAction?
    public let reviewedAt: String?
    public let reviewedByName: String?
    public let analyzedAt: String

    public init(id: String, messageId: String? = nil, text: String? = nil, sentAt: String? = nil, senderId: String? = nil,
                senderName: String? = nil, senderRunsRoom: Bool = false, reason: String, category: String? = nil,
                categoryTitle: String? = nil, ruling: String? = nil, confidence: Double? = nil,
                suggestedAction: FlaggedMessageAction, doneActions: [FlaggedMessageAction] = [], removed: Bool = false,
                review: FlaggedMessageAction? = nil, reviewedAt: String? = nil, reviewedByName: String? = nil,
                analyzedAt: String) {
        self.id = id; self.messageId = messageId; self.text = text; self.sentAt = sentAt; self.senderId = senderId
        self.senderName = senderName; self.senderRunsRoom = senderRunsRoom; self.reason = reason
        self.category = category; self.categoryTitle = categoryTitle; self.ruling = ruling
        self.confidence = confidence; self.suggestedAction = suggestedAction; self.doneActions = doneActions
        self.removed = removed; self.review = review; self.reviewedAt = reviewedAt
        self.reviewedByName = reviewedByName; self.analyzedAt = analyzedAt
    }

    /// Still waiting for staff.
    public var isOpen: Bool { review == nil }

    /// The actions that apply to it, quick ones first: someone who runs the room is only dismissed or escalated, and
    /// a message already out of the room isn't removed again.
    public var availableActions: [FlaggedMessageAction] {
        FlaggedMessageAction.allCases.filter { action in
            if senderRunsRoom && action.actsOnSender { return false }
            if action == .remove && removed { return false }
            if action == .escalate && messageId == nil { return false }
            if action.actsOnSender && senderId == nil { return false }
            return true
        }
    }

    /// One line under the message: what the host suggests, and what it already did ("Suggested: Warn · Glam removed
    /// it").
    public var suggestionLine: String {
        var parts = ["\(FlaggedMessageCopy.suggested): \(suggestedAction.title)"]
        if !doneActions.isEmpty {
            parts.append("Already " + doneActions.map { $0.doneTitle.lowercased() }.joined(separator: ", "))
        }
        return parts.joined(separator: " · ")
    }
}

/// The GraphQL for Velvet's flagged messages, shared by every staff app (and Android, word for word) so none writes its
/// own. They run on the staff endpoint, which this SDK doesn't call (``GraphQLEndpoint``): StaffKit's session sends
/// them, with these variables, and decodes ``ListResponse`` and ``ReviewResponse``.
public enum FlaggedMessages {
    /// A cooldown's length when the app doesn't ask, as the API's default.
    public static let cooldownMinutes = 10
    /// The longest cooldown the API takes.
    public static let cooldownMaxMinutes = 30

    public static let flaggedMessageFields = """
        id messageId text sentAt senderId senderName senderRunsRoom reason category categoryTitle ruling confidence \
        suggestedAction doneActions removed review reviewedAt reviewedByName analyzedAt
        """

    public static let query = """
        # endpoint: staff
        query VelvetFlaggedMessages($id: ID!, $includeReviewed: Boolean) { venues { venue(id: $id) { \
        flaggedMessages(first: 50, includeReviewed: $includeReviewed) { totalCount nodes { \(flaggedMessageFields) } } } } }
        """

    public static let reviewMutation = """
        # endpoint: staff
        mutation VelvetReviewFlaggedMessage($input: FlaggedMessageReviewInput!) { \
        reviewFlaggedMessage(input: $input) { flaggedMessage { \(flaggedMessageFields) } } }
        """

    /// The variables for ``query``.
    public static func queryVariables(venueID: String, includeReviewed: Bool = false) -> [String: GraphQLValue] {
        ["id": .string(venueID), "includeReviewed": .bool(includeReviewed)]
    }

    /// The variables for ``reviewMutation``.
    public static func reviewVariables(id: String, action: FlaggedMessageAction, minutes: Int? = nil,
                                       text: String? = nil) -> [String: GraphQLValue] {
        var input: [String: GraphQLValue] = ["id": .string(id), "action": .string(action.rawValue)]
        if let minutes { input["minutes"] = .int(minutes) }
        if let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty { input["text"] = .string(text) }
        return ["input": .object(input)]
    }

    /// ``query``'s answer.
    public struct ListResponse: Decodable, Sendable {
        struct Connection: Decodable, Sendable { let nodes: [FlaggedMessage] }
        struct Venue: Decodable, Sendable { let flaggedMessages: Connection? }
        struct Venues: Decodable, Sendable { let venue: Venue? }
        let venues: Venues?

        public var messages: [FlaggedMessage] { venues?.venue?.flaggedMessages?.nodes ?? [] }
    }

    /// ``reviewMutation``'s answer.
    public struct ReviewResponse: Decodable, Sendable {
        struct Payload: Decodable, Sendable { let flaggedMessage: FlaggedMessage }
        let reviewFlaggedMessage: Payload?

        public var message: FlaggedMessage? { reviewFlaggedMessage?.flaggedMessage }
    }
}

/// The words around flagged messages, the same on Android.
public enum FlaggedMessageCopy {
    public static let title = "Flagged messages"
    public static let empty = "Nothing flagged in the chat. The AI host will put anything that needs a look here."
    public static let suggested = "Suggested"
    public static let more = "More"
    public static let banTitle = "Ban them from the venue?"
    public static let banDetail = "They'll be taken out of the chat and stop seeing the venue, its events and lineups. "
        + "You can lift a ban from Bans."
    public static let warnTitle = "Warn privately"
    public static let warnDetail = "Only they see it, in the chat and as a notification."
    public static let escalateTitle = "Escalate to the admins"
    public static let escalateDetail = "It goes to the audience's admins to look at. Add a note if it helps."
    public static let escalateNotePlaceholder = "What should they know? (optional)"
    public static let cooldownTitle = "Cool them down"
    public static let cooldownOptions = [5, 10, 30]
    public static let runsRoom = "From the venue's own people: dismiss it or escalate it."

    /// "10 min", for a cooldown choice.
    public static func minutes(_ minutes: Int) -> String { "\(minutes) min" }

    /// The suggested words for a warning at a venue, which staff can change.
    public static func defaultWarning(venueName: String) -> String {
        "A note from the staff at \(venueName): please keep the chat friendly and within the house rules."
    }
}
