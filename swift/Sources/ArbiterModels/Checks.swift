import Foundation

/// The raw read-out at a yes/no answer's position, taken from the model's logits before any grammar forces the answer:
/// `coverage` is how much of the model's belief true and false really hold.
public struct RawBoolean: Codable, Sendable, Hashable {
    public let pTrue: Double
    public let pFalse: Double
    public let coverage: Double
    /// Mass on other spellings (" true", "True"), logged apart.
    public let variantMass: Double
    /// pTrue over pTrue + pFalse.
    public let score: Double

    public init(pTrue: Double, pFalse: Double, coverage: Double, variantMass: Double, score: Double) {
        self.pTrue = pTrue; self.pFalse = pFalse; self.coverage = coverage; self.variantMass = variantMass
        self.score = score
    }
}

/// One check on one message: a guard policy (security and integrity) or a moderation rule.
public struct PolicyCheck: Codable, Sendable, Hashable, Identifiable {
    public enum Status: String, Codable, Sendable { case clear, flagged, unscored }

    /// The policy or rule's key, e.g. `instructions_at_bot`, `body_shaming`.
    public let policy: String
    /// What judged it: a model's label, or "counted in code".
    public let model: String
    public let decision: Bool?
    public let rationale: String
    public let raw: RawBoolean?
    public let status: Status
    /// Why it's unscored.
    public let reason: String?
    /// A moderation rule's code pre-signals found in the message (a phone number, a payment handle).
    public let signals: [String]?

    public var id: String { policy }

    public init(policy: String, model: String, decision: Bool?, rationale: String = "", raw: RawBoolean?,
                status: Status, reason: String? = nil, signals: [String]? = nil) {
        self.policy = policy; self.model = model; self.decision = decision; self.rationale = rationale; self.raw = raw
        self.status = status; self.reason = reason; self.signals = signals
    }
}

/// Which of the two groups a check belongs to, as Arbiter shows them side by side.
public enum CheckGroup: String, Codable, Sendable, CaseIterable {
    /// The moderation rules: is the message harmful to people in the room?
    case moderation
    /// The guard: is the message trying to steer, override or misuse the host?
    case securityAndIntegrity

    public var title: String {
        switch self {
        case .moderation: "Moderation"
        case .securityAndIntegrity: "Security and integrity"
        }
    }
}

/// What a flagged moderation rule would do: put the message in front of staff, the venue, or offer the sender support.
public struct RuleActionProposal: Codable, Sendable, Hashable {
    public enum Action: String, Codable, Sendable { case escalate, notifyVenue = "notify_venue", crisisResources = "crisis_resources" }
    public enum Severity: String, Codable, Sendable { case critical, high, medium, low, info }

    public let action: Action
    public let rule: String
    /// The API's moderation category it's filed under.
    public let category: String
    public let severity: Severity
    public let score: Double?
    /// For staff: names nobody, never repeats a disclosed fact.
    public let reason: String

    public init(action: Action, rule: String, category: String, severity: Severity, score: Double?, reason: String) {
        self.action = action; self.rule = rule; self.category = category; self.severity = severity; self.score = score
        self.reason = reason
    }
}

/// The venue's rating, which moves the moderation rules' thresholds (adult rooms allow consensual sex talk).
public enum VenueRating: String, Codable, CodingKeyRepresentable, Sendable, CaseIterable { case general, adult }

/// The guard (ShieldGemma): every security and integrity policy on one message.
public protocol PolicyGuard: Sendable {
    var label: String { get }
    /// Checks the model's tokenizer can be scored; throws why not.
    func selfTest() async throws
    func check(_ text: String) async throws -> [PolicyCheck]
}

/// The moderation rules on the newest of some chat lines, the earlier ones as context only.
public protocol ModerationRules: Sendable {
    var label: String { get }
    func check(_ lines: [ChatLine]) async throws -> [PolicyCheck]
}
