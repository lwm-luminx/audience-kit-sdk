import Foundation

/// One option a piece of work offers, as the worker sees it (the API's `DecisionOption`, before anyone answered).
public struct DecisionOptionSpec: Codable, Sendable, Hashable, Identifiable {
    public let key: String
    public let label: String
    public let description: String?

    public var id: String { key }

    public init(key: String, label: String, description: String? = nil) {
        self.key = key; self.label = label; self.description = description
    }
}

/// Work claimed from the evaluation queue (Mutation.claimEvaluation), which the engine decides.
public struct DecisionWork: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let evaluationType: String
    /// The lease the claim holds; renewed while the model thinks.
    public let lease: String
    public let leaseExpiresAt: Date
    public let attempt: Int
    public let question: String?
    /// CHOICE, YES_NO or SCORE.
    public let decisionKind: String
    public let input: JSONValue
    public let options: [DecisionOptionSpec]

    public init(id: String, evaluationType: String, lease: String, leaseExpiresAt: Date, attempt: Int = 1,
                question: String?, decisionKind: String = "CHOICE", input: JSONValue, options: [DecisionOptionSpec]) {
        self.id = id; self.evaluationType = evaluationType; self.lease = lease; self.leaseExpiresAt = leaseExpiresAt
        self.attempt = attempt; self.question = question; self.decisionKind = decisionKind; self.input = input
        self.options = options
    }
}

/// How the engine got its probabilities: the options' letters' next-token probabilities, or a JSON answer.
public enum AnswerMethod: String, Codable, Sendable { case logprobs, json }

/// The engine's answer to one piece of work (Mutation.completeEvaluation's input).
public struct EngineAnswer: Codable, Sendable, Hashable {
    /// The probability per option key, summing to 1.
    public let scores: [String: Double]
    /// The options it can't rule out (adaptive prediction sets); more than one reads as unsure.
    public let conformalSet: [String]
    /// What it found besides the answer: `summary`, `evidence`, `model`, …
    public let result: JSONValue
    public let method: AnswerMethod

    public init(scores: [String: Double], conformalSet: [String], result: JSONValue = .object([:]), method: AnswerMethod) {
        self.scores = scores; self.conformalSet = conformalSet; self.result = result; self.method = method
    }

    /// The most likely option.
    public var choice: String? { scores.max { $0.value < $1.value }?.key }
    public var unsure: Bool { conformalSet.count != 1 }

    /// The answer with how it was reached under `result.trace` (how, how long, on what, which attempt, its scores), so the
    /// decision can be diagnosed later from the iPad. The API keeps a trace on any type's result.
    public func traced(durationMs: Int, engine: String, attempt: Int) -> EngineAnswer {
        let trace: JSONValue = .object([
            "method": .string(method.rawValue), "durationMs": .number(Double(durationMs)), "engine": .string(engine),
            "attempt": .number(Double(attempt)), "scores": .object(scores.mapValues(JSONValue.number)),
            "conformalSet": .array(conformalSet.map(JSONValue.string)),
        ])
        var fields: [String: JSONValue]
        if case .object(let existing) = result { fields = existing } else { fields = [:] }
        fields["trace"] = trace
        return EngineAnswer(scores: scores, conformalSet: conformalSet, result: .object(fields), method: method)
    }
}

/// Decides work with a local model (macOS: ArbiterEngine).
public protocol DecisionEngine: Sendable {
    /// What runs it, for the UI ("gemma-4-31B-it-Q4_K_M on llama.cpp").
    var label: String { get }
    func decide(_ work: DecisionWork) async throws -> EngineAnswer
}

/// The evaluation queue over the network (StaffKit implements it on the worker token's cable). The engine's worker
/// loop drives it; it never opens a socket itself.
public protocol WorkerQueue: Sendable {
    /// Fires each time the API says work is waiting (Subscription.evaluationQueue), and once on connecting.
    func workAvailable() -> AsyncStream<Void>
    /// Claims the next piece of work of these types, or nil when none waits.
    func claim(types: [String]?) async throws -> DecisionWork?
    func complete(_ work: DecisionWork, answer: EngineAnswer) async throws
    func fail(_ work: DecisionWork, error: String) async throws
    /// Extends the lease; returns its new expiry.
    func renewLease(_ work: DecisionWork) async throws -> Date
}

/// The worker loop's state, for the Worker screen.
public struct WorkerStatus: Codable, Sendable, Hashable {
    public enum State: String, Codable, Sendable { case stopped, connecting, idle, working, error }
    public struct LastDecision: Codable, Sendable, Hashable, Identifiable {
        public let id: String
        public let evaluationType: String
        public let choice: String
        public let unsure: Bool
        public var question: String?
        public var durationMs: Int?
        public var at: Date?
        public init(id: String, evaluationType: String, choice: String, unsure: Bool, question: String? = nil,
                    durationMs: Int? = nil, at: Date? = nil) {
            self.id = id; self.evaluationType = evaluationType; self.choice = choice; self.unsure = unsure
            self.question = question; self.durationMs = durationMs; self.at = at
        }
    }

    /// Keep this many of the worker's finished pieces of work, for the Worker screen.
    public static let keepDone = 50

    public var state: State
    public var message: String?
    public var handled: Int
    public var lastDecision: LastDecision?
    /// What it's deciding now.
    public var current: DecisionWork?
    /// What it finished since starting, newest first (up to ``keepDone``).
    public var done: [LastDecision]? = nil

    public init(state: State = .stopped, message: String? = nil, handled: Int = 0, lastDecision: LastDecision? = nil) {
        self.state = state; self.message = message; self.handled = handled; self.lastDecision = lastDecision
    }
}
