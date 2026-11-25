import Foundation

/// Something Glam's fast lane did on the backend (api doc/GLAM_FAST_LANE.md), as the feed's `glam.output` event
/// (`ChatModerationGlamOutput`) brings it. When an audience has the fast lane on, the backend hosts its rooms and this
/// Mac reviews each output with `reviewGlamOutput` instead of hosting them itself.
public struct GlamOutputEvent: Sendable, Hashable {
    /// What Glam did.
    public enum Kind: String, Sendable, Hashable { case doNotReply = "DO_NOT_REPLY", reply = "REPLY", flag = "FLAG",
                                                        privateNudge = "PRIVATE_NUDGE", safetyResponse = "SAFETY_RESPONSE" }

    /// A handle Glam's words mention ("7CE8") and who it is in this Mac's feed.
    public struct Handle: Sendable, Hashable {
        public let handle: String
        public let subject: String
        public init(handle: String, subject: String) { self.handle = handle; self.subject = subject }
    }

    public let cursor: String
    public let at: Date
    public let room: ChatRoom
    /// What `reviewGlamOutput` takes.
    public let outputID: String
    public let kind: Kind
    /// For a flag: targeting, body_shaming, harassment, doxxing or other.
    public let category: String?
    /// For a flag: Glam's suggestion.
    public let suggestedAction: GlamAction?
    /// For a safety response: self_harm, medical, drink_spiking, threat or harassment_report.
    public let safetyKind: String?
    public let reason: String?
    /// What it said, for a reply or a nudge.
    public let text: String?
    /// Whether it posted a line a review can take down.
    public let posted: Bool
    /// The line that woke it.
    public let message: ChatLine?
    /// The line it is about: replied to or flagged.
    public let target: ChatLine?
    /// Who it is about, as this Mac's feed knows them.
    public let subject: String?
    public let handles: [Handle]

    public init(cursor: String, at: Date, room: ChatRoom, outputID: String, kind: Kind, category: String? = nil,
                suggestedAction: GlamAction? = nil, safetyKind: String? = nil, reason: String? = nil,
                text: String? = nil, posted: Bool = false, message: ChatLine? = nil, target: ChatLine? = nil,
                subject: String? = nil, handles: [Handle] = []) {
        self.cursor = cursor; self.at = at; self.room = room; self.outputID = outputID; self.kind = kind
        self.category = category; self.suggestedAction = suggestedAction; self.safetyKind = safetyKind
        self.reason = reason; self.text = text; self.posted = posted; self.message = message; self.target = target
        self.subject = subject; self.handles = handles
    }
}

/// An action on a person, least to most severe (the API's GlamAction; `nothing` is its NONE, named apart from
/// Optional's `none`).
public enum GlamAction: String, Sendable, Hashable, Comparable, CaseIterable {
    case nothing = "NONE", cooldown = "COOLDOWN", remove = "REMOVE", block = "BLOCK"

    public static func < (lhs: GlamAction, rhs: GlamAction) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }
}

/// Arbiter's verdict on one output, as `reviewGlamOutput` takes it.
public struct GlamOutputReview: Sendable, Hashable {
    public enum Outcome: String, Sendable, Hashable { case confirm = "CONFIRM", downgrade = "DOWNGRADE",
                                                           overturn = "OVERTURN", escalate = "ESCALATE" }

    public let outputID: String
    public let outcome: Outcome
    /// The action to take instead of the suggested one (required for a downgrade).
    public let action: GlamAction?
    /// Why, in a line, for the disagreement log.
    public let reason: String?
    /// With overturn: take down the reply Glam posted.
    public let retract: Bool

    public init(outputID: String, outcome: Outcome, action: GlamAction? = nil, reason: String? = nil,
                retract: Bool = false) {
        self.outputID = outputID; self.outcome = outcome; self.action = action; self.reason = reason
        self.retract = retract
    }
}

/// How this Mac reviews the fast lane's outputs until a model-backed reviewer does (api doc/GLAM_FAST_LANE.md, "Arbiter's
/// review"). It is deliberately conservative: nothing heavier than taking a line down happens without a person.
///
/// - Saying nothing, replies, nudges and safety responses are confirmed: none of them acts on anyone.
/// - A flag suggesting nothing is confirmed.
/// - A flag suggesting removal is confirmed when the moderation rules flag the line too, overturned when they clear
///   it, and escalated to a person when they couldn't say (off, unscored or failed).
/// - A flag suggesting a cooldown is downgraded to removing the line when the rules flag it (a person can still go
///   further), overturned when they clear it, escalated otherwise.
/// - A flag suggesting a block always goes to a person.
public enum GlamReviewPolicy {
    /// - Parameter rulesFlagged: whether the moderation rules flagged the line Glam flagged; nil when they didn't say.
    public static func review(_ event: GlamOutputEvent, rulesFlagged: Bool?) -> GlamOutputReview {
        let id = event.outputID
        guard event.kind == .flag else { return GlamOutputReview(outputID: id, outcome: .confirm) }
        switch event.suggestedAction ?? .nothing {
        case .nothing:
            return GlamOutputReview(outputID: id, outcome: .confirm)
        case .remove:
            switch rulesFlagged {
            case true?: return GlamOutputReview(outputID: id, outcome: .confirm, reason: "The rules flag it too")
            case false?: return GlamOutputReview(outputID: id, outcome: .overturn, reason: "The rules found nothing")
            case nil: return GlamOutputReview(outputID: id, outcome: .escalate, reason: "The rules couldn't say")
            }
        case .cooldown:
            switch rulesFlagged {
            case true?: return GlamOutputReview(outputID: id, outcome: .downgrade, action: .remove,
                                                reason: "Removing the line; a person can go further")
            case false?: return GlamOutputReview(outputID: id, outcome: .overturn, reason: "The rules found nothing")
            case nil: return GlamOutputReview(outputID: id, outcome: .escalate, reason: "The rules couldn't say")
            }
        case .block:
            return GlamOutputReview(outputID: id, outcome: .escalate, reason: "A block is for a person to decide")
        }
    }
}
