import Foundation
import AudienceCore
import StaffKitCore
import ArbiterModels

/// One answer a decision offers, with the worker's probability for it once it answered (the API's `DecisionOption`).
public struct StaffDecisionOption: Decodable, Sendable, Hashable, Identifiable {
    /// Its key, as workers and `decideEvaluation` name it.
    public let key: String
    public let label: String
    /// What choosing it means.
    public let description: String?
    /// The worker's probability for it, 0 to 1; nil before it answered.
    public let score: Double?
    /// Whether the worker couldn't rule it out. More than one option in the set reads as unsure.
    public let inConformalSet: Bool

    public var id: String { key }

    public init(key: String, label: String, description: String? = nil, score: Double? = nil, inConformalSet: Bool = false) {
        self.key = key; self.label = label; self.description = description; self.score = score
        self.inConformalSet = inConformalSet
    }
}

/// The suggestion a `submission_research` decision is about: what it proposes and the listing as it is now.
public struct StaffDecisionSubmission: Decodable, Sendable, Hashable {
    public struct Listing: Decodable, Sendable, Hashable {
        public let id: String
        public let name: String?

        public init(id: String, name: String? = nil) { self.id = id; self.name = name }
    }

    public let id: String
    /// CORRECTION, MISSING_VENUE, CLOSED, … (the API's `SubmissionKind`).
    public let kind: String
    public let status: String
    /// The fields it proposes.
    public let proposed: GraphQLValue
    /// The listing as it is now, for the fields it proposes.
    public let current: GraphQLValue
    public let venue: Listing?
    public let event: Listing?

    public init(id: String, kind: String, status: String = "PENDING", proposed: GraphQLValue = .object([:]),
                current: GraphQLValue = .object([:]), venue: Listing? = nil, event: Listing? = nil) {
        self.id = id; self.kind = kind; self.status = status; self.proposed = proposed; self.current = current
        self.venue = venue; self.event = event
    }

    /// "Correction", "Missing venue".
    public var kindTitle: String {
        switch kind {
        case "LOCAL_RULES_CORRECTION": "Local rules correction"
        case "TALENT_LINK": "Performer on an event"
        default: kind.replacingOccurrences(of: "_", with: " ").lowercased().capitalizingFirstLetter()
        }
    }

    /// What it would change: each proposed field beside its value now, in the order the fields sort.
    public var changes: [DecisionFieldChange] {
        guard case .object(let proposed) = proposed else { return [] }
        let now: [String: GraphQLValue]
        if case .object(let fields) = current { now = fields } else { now = [:] }
        return proposed.keys.sorted().map { key in
            DecisionFieldChange(field: key, now: now[key].flatMap { $0 == .null ? nil : $0.displayText },
                                proposed: proposed[key]?.displayText ?? "")
        }
    }
}

/// One field a suggestion would change.
public struct DecisionFieldChange: Sendable, Hashable, Identifiable {
    /// The field's key, e.g. `phone_number`.
    public let field: String
    /// What the listing says now; nil when it says nothing.
    public let now: String?
    public let proposed: String

    public var id: String { field }
    /// "Phone number".
    public var title: String { field.replacingOccurrences(of: "_", with: " ").capitalizingFirstLetter() }
    /// Whether it would change anything: the listing doesn't already say it.
    public var changes: Bool { now != proposed }
}

/// The Soapbox article an `article_national_feature` decision weighs for national news (api doc/SOAPBOX.md
/// "National news"), read from what the worker was given (`input`), so Arbiter shows it against any API that queues it.
public struct StaffDecisionArticle: Sendable, Hashable {
    public static let evaluationType = "article_national_feature"

    public let id: String?
    public let title: String
    public let summary: String?
    public let byline: String?
    public let publication: String?
    /// The publication's locale: where the story comes from.
    public let locale: String?
    /// The piece on the publication's site (a teaser links readers there).
    public let url: URL?

    public init(id: String? = nil, title: String, summary: String? = nil, byline: String? = nil,
                publication: String? = nil, locale: String? = nil, url: URL? = nil) {
        self.id = id; self.title = title; self.summary = summary; self.byline = byline
        self.publication = publication; self.locale = locale; self.url = url
    }

    /// The article in a decision's input, or nil when it isn't about one.
    public init?(input: GraphQLValue?) {
        guard case .object(let fields)? = input, case .string(let title)? = fields["title"] else { return nil }
        func text(_ value: GraphQLValue?) -> String? {
            guard case .string(let string)? = value else { return nil }
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        var publication: [String: GraphQLValue] = [:]
        if case .object(let found)? = fields["publication"] { publication = found }
        let url = text(fields["canonical_url"]).flatMap(URL.init(string:)).flatMap { link in
            link.scheme == "https" || link.scheme == "http" ? link : nil
        }
        self.init(id: text(fields["article_id"]), title: title, summary: text(fields["summary"]),
                  byline: text(fields["byline"]), publication: text(publication["name"]),
                  locale: text(publication["locale"]), url: url)
    }
}

/// A decision on the evaluation queue, as a person sees it (the API's `Decision`, doc/DECISION_QUEUE.md): a question
/// with fixed options, the worker's probability for each, and, once it's settled, who settled it. One the worker was
/// sure of and its type applied on its own was decided by the AI (`decidedBy` nil).
public struct StaffDecision: Decodable, Sendable, Hashable, Identifiable {
    public let id: String
    /// What kind of work, e.g. `submission_research`.
    public let evaluationType: String
    /// CHOICE, YES_NO or SCORE.
    public let decisionKind: String
    public let question: String?
    /// pending, running, completed or failed.
    public let state: String
    /// The worker's answer, its most likely option; nil before it answered.
    public let choice: String?
    /// The worker's probability for its choice, 0 to 1.
    public let confidence: Double?
    /// Whether the worker couldn't settle on one option.
    public let unsure: Bool
    public let options: [StaffDecisionOption]
    /// Why the worker failed, when it did.
    public let error: String?
    /// What the worker was given.
    public let input: GraphQLValue?
    /// What the worker found besides its answer: `summary`, `evidence`, `model`, …
    public let result: GraphQLValue?
    public let createdAt: String
    public let completedAt: String?
    /// When it went to a person; nil while a worker has it, it waits on someone else, or it's decided.
    public let needsPersonAt: String?
    public let decidedAt: String?
    /// The option it was decided with.
    public let decidedOption: String?
    /// Who decided it; nil when the AI did (its type applied the worker's answer on its own).
    public let decidedBy: Profile?
    public let submission: StaffDecisionSubmission?

    public init(id: String, evaluationType: String = "submission_research", decisionKind: String = "CHOICE",
                question: String? = nil, state: String = "completed", choice: String? = nil, confidence: Double? = nil,
                unsure: Bool = false, options: [StaffDecisionOption] = [], error: String? = nil,
                input: GraphQLValue? = nil, result: GraphQLValue? = nil, createdAt: String = "",
                completedAt: String? = nil, needsPersonAt: String? = nil, decidedAt: String? = nil,
                decidedOption: String? = nil, decidedBy: Profile? = nil, submission: StaffDecisionSubmission? = nil) {
        self.id = id; self.evaluationType = evaluationType; self.decisionKind = decisionKind; self.question = question
        self.state = state; self.choice = choice; self.confidence = confidence; self.unsure = unsure
        self.options = options; self.error = error; self.input = input; self.result = result
        self.createdAt = createdAt; self.completedAt = completedAt; self.needsPersonAt = needsPersonAt
        self.decidedAt = decidedAt; self.decidedOption = decidedOption; self.decidedBy = decidedBy
        self.submission = submission
    }

    /// Who settled it.
    public enum Decider: Sendable, Hashable {
        /// Nobody yet.
        case nobody
        /// The worker was sure and its type applied the answer on its own.
        case ai
        /// A person, in the decision queue (or the suggestions queue, which writes the same label).
        case person(Profile)
    }

    public var decider: Decider {
        guard decidedAt != nil else { return .nobody }
        return decidedBy.map(Decider.person) ?? .ai
    }

    public var isDecided: Bool { decidedAt != nil }
    /// Waiting for a person.
    public var needsPerson: Bool { decidedAt == nil && needsPersonAt != nil }

    /// The article it weighs for national news, if that's what it is.
    public var article: StaffDecisionArticle? {
        evaluationType == StaffDecisionArticle.evaluationType ? StaffDecisionArticle(input: input) : nil
    }

    /// What the eyebrow over it says: the suggestion's kind, "National news", or the type.
    public var kindTitle: String {
        if let submission { return submission.kindTitle }
        if evaluationType == StaffDecisionArticle.evaluationType { return "National news" }
        return evaluationType.replacingOccurrences(of: "_", with: " ")
    }

    public func option(_ key: String?) -> StaffDecisionOption? { options.first { $0.key == key } }
    /// The worker's answer as a person reads it: "Approve".
    public var choiceLabel: String? { choice.map { option($0)?.label ?? $0 } }
    public var decidedLabel: String? { decidedOption.map { option($0)?.label ?? $0 } }
    /// Whether a person's decision went the way the worker answered; nil until a person decided one the worker
    /// answered.
    public var personAgreedWithAI: Bool? {
        guard case .person = decider, let choice, let decidedOption else { return nil }
        return choice == decidedOption
    }

    /// The worker's one-line reason (`result.summary`), when it gave one.
    public var reason: String? {
        guard case .object(let fields) = result, case .string(let summary)? = fields["summary"] else { return nil }
        let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// How far an article's story reaches (`result.reach`: national, regional or local), when the worker said.
    public var reach: String? {
        guard case .object(let fields) = result, case .string(let reach)? = fields["reach"], !reach.isEmpty else {
            return nil
        }
        return reach
    }

    /// The model that answered (`result.model`), when the worker said.
    public var model: String? {
        guard case .object(let fields) = result, case .string(let model)? = fields["model"] else { return nil }
        return model.isEmpty ? nil : model
    }

    /// The links the worker cited (`result.evidence`: strings, or objects with a `url`).
    public var evidence: [URL] {
        guard case .object(let fields) = result, case .array(let items)? = fields["evidence"] else { return [] }
        return items.compactMap { item in
            switch item {
            case .string(let link): URL(string: link)
            case .object(let entry): if case .string(let link)? = entry["url"] { URL(string: link) } else { nil }
            default: nil
            }
        }.filter { $0.scheme == "https" || $0.scheme == "http" }
    }

    /// What a row says it's about: "Correction · The Eagle", or the question.
    public var title: String {
        if let submission {
            let listing = submission.venue?.name ?? submission.event?.name
            return [submission.kindTitle, listing].compactMap { $0 }.joined(separator: " · ")
        }
        if let article { return "National news · \(article.title)" }
        return question ?? evaluationType.replacingOccurrences(of: "_", with: " ").capitalizingFirstLetter()
    }

    /// The options a person picks from, the worker's likeliest first; unscored options keep their order.
    public var optionsByScore: [StaffDecisionOption] {
        options.enumerated().sorted { a, b in
            let left = a.element.score ?? -1, right = b.element.score ?? -1
            return left == right ? a.offset < b.offset : left > right
        }.map(\.element)
    }
}

/// A page of decisions.
public struct StaffDecisionPage: Decodable, Sendable {
    public struct Info: Decodable, Sendable {
        public let hasNextPage: Bool
        public let endCursor: String?
        public init(hasNextPage: Bool, endCursor: String?) { self.hasNextPage = hasNextPage; self.endCursor = endCursor }
    }
    public let totalCount: Int
    public let nodes: [StaffDecision]
    public let pageInfo: Info

    public init(totalCount: Int, nodes: [StaffDecision], pageInfo: Info) {
        self.totalCount = totalCount; self.nodes = nodes; self.pageInfo = pageInfo
    }
}

/// What the `decisionQueue` subscription says changed.
public enum DecisionQueueEvent: Sendable, Hashable {
    /// It now waits for a person.
    case added(StaffDecision)
    /// A person or the AI decided it: it left the queue.
    case decided(StaffDecision)
    /// It left the queue to wait on someone else (the venue was asked to confirm a suggestion).
    case waiting(StaffDecision)
    /// The cable is up again after a drop: changes may have been missed, so reload.
    case resubscribed
    /// The server turned the subscription away: no `audience:moderate:*` here. The feed ends.
    case rejected
    /// The socket dropped; the cable is reconnecting (nil reason) or gave up (the session ended).
    case offline(String?)
}

/// The decisions waiting for a person and the ones already decided, kept current from the queue's changes.
public struct DecisionQueueState: Sendable, Hashable {
    /// Waiting for a person: unsure ones first, then the longest waiting, as the API orders them.
    public var open: [StaffDecision]
    /// Decided, newest first.
    public var decided: [StaffDecision]

    public init(open: [StaffDecision] = [], decided: [StaffDecision] = []) { self.open = open; self.decided = decided }

    /// The ones the AI decided on its own.
    public var decidedByAI: [StaffDecision] { decided.filter { $0.decider == .ai } }
    /// The ones a person decided.
    public var decidedByPeople: [StaffDecision] {
        decided.filter { if case .person = $0.decider { true } else { false } }
    }

    public func decision(_ id: String?) -> StaffDecision? {
        guard let id else { return nil }
        return open.first { $0.id == id } ?? decided.first { $0.id == id }
    }

    /// The queue after one change.
    public func applying(_ event: DecisionQueueEvent) -> DecisionQueueState {
        var next = self
        switch event {
        case .added(let decision):
            next.decided.removeAll { $0.id == decision.id }
            if let index = next.open.firstIndex(where: { $0.id == decision.id }) { next.open[index] = decision }
            else { next.open.append(decision) }
            next.open = Self.ordered(next.open)
        case .decided(let decision):
            next.open.removeAll { $0.id == decision.id }
            next.decided.removeAll { $0.id == decision.id }
            next.decided.insert(decision, at: 0)
        case .waiting(let decision):
            next.open.removeAll { $0.id == decision.id }
        case .resubscribed, .rejected, .offline:
            break
        }
        return next
    }

    /// The API's order: unsure first, then the longest waiting.
    static func ordered(_ decisions: [StaffDecision]) -> [StaffDecision] {
        decisions.enumerated().sorted { a, b in
            if a.element.unsure != b.element.unsure { return a.element.unsure }
            let left = a.element.needsPersonAt ?? "", right = b.element.needsPersonAt ?? ""
            return left == right ? a.offset < b.offset : left < right
        }.map(\.element)
    }
}

/// Where Arbiter reads and settles decisions. ``DecisionQueueClient`` is the audience's queue on the API; a Mac that
/// runs its own model can wrap it to add what it decided locally.
public protocol DecisionSource: Sendable {
    func decisions(open: Bool, after: String?) async throws -> StaffDecisionPage
    func decide(_ id: String, option: String, note: String?) async throws -> StaffDecision
    func queueFeed() async -> AsyncStream<DecisionQueueEvent>
}

/// The audience's decision queue on its staff endpoint (doc/DECISION_QUEUE.md), for audience admins
/// (`audience:moderate:*`): what waits for a person, what was decided and by whom, deciding one, and the queue live.
/// Anyone else reads an empty queue and the feed is refused.
public struct DecisionQueueClient: DecisionSource {
    public let session: AudienceManagementSession

    public init(session: AudienceManagementSession) { self.session = session }

    /// Small enough for the staff endpoint's complexity budget with the suggestion attached.
    public static let pageSize = 25

    static let decisionFields = """
        id evaluationType decisionKind question state choice confidence unsure error input result
        createdAt completedAt needsPersonAt decidedAt decidedOption decidedBy { id name avatarUrl }
        options { key label description score inConformalSet }
        submission { id kind status proposed current venue { id name } event { id name } }
        """

    static let decisionsQuery = """
        query ArbiterDecisions($open: Boolean!, $first: Int, $after: String) {
          decisions(open: $open, first: $first, after: $after) {
            totalCount nodes { \(decisionFields) } pageInfo { hasNextPage endCursor }
          }
        }
        """

    static let decideMutation = """
        mutation ArbiterDecide($input: DecisionDecideInput!) {
          decideEvaluation(input: $input) { decision { \(decisionFields) } }
        }
        """

    static let queueSubscription = """
        subscription ArbiterDecisionQueue {
          decisionQueue { change decision { \(decisionFields) } }
        }
        """

    /// One page: waiting for a person (unsure first, then the longest waiting), or decided (newest first).
    public func decisions(open: Bool, after: String? = nil) async throws -> StaffDecisionPage {
        let page = try await session.graphQL(Self.decisionsQuery, variables: [
            "open": .bool(open), "first": .int(Self.pageSize), "after": after.map(GraphQLValue.string) ?? .null,
        ], as: [String: StaffDecisionPage].self)["decisions"]
        guard let page else { throw AudienceKitError.decoding("The decision queue was missing") }
        return page
    }

    /// Decides it with one of its options. `note` is the reason, which rejecting a suggestion needs (the person who
    /// sent it sees it).
    public func decide(_ id: String, option: String, note: String? = nil) async throws -> StaffDecision {
        var input: [String: GraphQLValue] = ["id": .string(id), "option": .string(option)]
        if let note = note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty { input["note"] = .string(note) }
        struct Payload: Decodable, Sendable { let decision: StaffDecision }
        let result = try await session.graphQL(Self.decideMutation, variables: ["input": .object(input)],
                                               as: [String: Payload].self)
        guard let decision = result["decideEvaluation"]?.decision else {
            throw AudienceKitError.decoding("The decided decision was missing")
        }
        return decision
    }

    /// Follows the queue live. It sends nothing on subscribing: read ``decisions(open:after:)`` first, then apply
    /// each change, and read again on `resubscribed`. Ending the iteration stops following.
    public func queueFeed() async -> AsyncStream<DecisionQueueEvent> {
        let results = await session.subscribe(Self.queueSubscription)
        return AsyncStream { continuation in
            let task = Task {
                var connectedOnce = false
                for await result in results {
                    if case .subscribed = result {
                        if connectedOnce { continuation.yield(.resubscribed) }
                        connectedOnce = true
                        continue
                    }
                    guard let event = Self.queueEvent(from: result) else { continue }
                    continuation.yield(event)
                    if case .rejected = event { break }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static func queueEvent(from event: AudienceCable.Event) -> DecisionQueueEvent? {
        switch event {
        case .rejected: return .rejected
        case .disconnected(let reason, let reconnects): return .offline(reconnects ? nil : (reason ?? "Signed out"))
        case .result(let data): return queueEvent(from: data)
        default: return nil  // subscribed
        }
    }

    /// The change one subscription result means, `rejected` for a refusal, or nil for a change this build doesn't know.
    static func queueEvent(from data: Data) -> DecisionQueueEvent? {
        struct Change: Decodable { let change: String; let decision: StaffDecision }
        struct Queue: Decodable { let decisionQueue: Change? }
        guard let result = try? JSONDecoder().decode(GraphQLSubscriptionResult<Queue>.self, from: data) else { return nil }
        guard let change = result.data?.decisionQueue else { return result.refused ? .rejected : nil }
        switch change.change {
        case "ADDED": return .added(change.decision)
        case "DECIDED": return .decided(change.decision)
        case "WAITING": return .waiting(change.decision)
        default: return nil
        }
    }
}

extension GraphQLValue {
    /// The value as a line of text: strings as they are, numbers without a trailing ".0", lists joined with commas,
    /// objects as `key: value` pairs, and null as "—".
    public var displayText: String {
        switch self {
        case .bool(let value): return value ? "Yes" : "No"
        case .int(let value): return String(value)
        case .double(let value):
            return value.rounded() == value && abs(value) < 1e15 ? String(Int(value)) : String(value)
        case .string(let value): return value
        case .array(let values): return values.map(\.displayText).joined(separator: ", ")
        case .object(let fields):
            return fields.keys.sorted().map { "\($0): \(fields[$0]!.displayText)" }.joined(separator: "; ")
        default: return "—"  // null
        }
    }
}

private extension String {
    func capitalizingFirstLetter() -> String { prefix(1).uppercased() + dropFirst() }
}

// MARK: - The queue as the server sees it

/// The decision queue counted on the server (Audience.decisionQueueStatus): what waits for a worker, what workers have,
/// what waits for a person, what was decided or given up on today, per type; the audience's worker devices; and the AI
/// host's uploaded calls today. Admins only.
public struct DecisionQueueStatus: Decodable, Sendable, Hashable {
    public struct TypeCounts: Decodable, Sendable, Hashable, Identifiable {
        public let evaluationType: String
        public let pending: Int
        public let running: Int
        public let needsPerson: Int
        public let decidedToday: Int
        public let failedToday: Int
        public var id: String { evaluationType }
    }

    public struct Worker: Decodable, Sendable, Hashable, Identifiable {
        public let id: String
        public let name: String
        public let running: Int
        public let lastUsedAt: Date?
        public let scopes: [String]

        enum CodingKeys: String, CodingKey { case id, name, running, lastUsedAt, scopes }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            name = try container.decode(String.self, forKey: .name)
            running = try container.decode(Int.self, forKey: .running)
            lastUsedAt = try container.decodeIfPresent(String.self, forKey: .lastUsedAt).flatMap(ArbiterJSON.parseDate)
            scopes = try container.decode([String].self, forKey: .scopes)
        }
    }

    public let at: Date
    public let evaluationTypes: [TypeCounts]
    public let workers: [Worker]
    public let hostDecisionsToday: Int

    enum CodingKeys: String, CodingKey { case at, evaluationTypes, workers, hostDecisionsToday }

    /// Dates come as the API writes them (ISO 8601 text), whatever the session's decoder does with dates.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        at = ArbiterJSON.parseDate(try container.decode(String.self, forKey: .at)) ?? Date()
        evaluationTypes = try container.decode([TypeCounts].self, forKey: .evaluationTypes)
        workers = try container.decode([Worker].self, forKey: .workers)
        hostDecisionsToday = try container.decode(Int.self, forKey: .hostDecisionsToday)
    }

    public var pending: Int { evaluationTypes.reduce(0) { $0 + $1.pending } }
    public var running: Int { evaluationTypes.reduce(0) { $0 + $1.running } }

    static let query = """
        query ArbiterQueueStatus {
          decisionQueueStatus {
            at hostDecisionsToday
            evaluationTypes { evaluationType pending running needsPerson decidedToday failedToday }
            workers { id name running lastUsedAt scopes }
          }
        }
        """
}

extension DecisionQueueClient {
    /// The queue as the server counts it; nil when this sign-in can't decide for the audience.
    public func status() async throws -> DecisionQueueStatus? {
        try await session.graphQL(DecisionQueueStatus.query, variables: [:],
                                  as: [String: DecisionQueueStatus?].self)["decisionQueueStatus"] ?? nil
    }
}

// MARK: - The AI host's calls, as its Mac uploaded them

/// One call the audience's AI host (Glam) made, as its Mac uploaded it (Audience.hostDecisions): the summary the API
/// keeps, and the whole proposal as Glam recorded it (`trace`), for diagnosing it anywhere.
public struct HostDecisionRecord: Decodable, Sendable, Identifiable {
    public let id: String
    public let decidedAt: Date?
    /// live (the feed), replay or try (a made-up conversation).
    public let source: String
    public let tool: String?
    public let flagged: Bool
    public let executionState: String?
    public let roomName: String?
    public let trace: GraphQLValue

    enum CodingKeys: String, CodingKey { case id, decidedAt, source, tool, flagged, executionState, roomName, trace }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        decidedAt = try container.decodeIfPresent(String.self, forKey: .decidedAt).flatMap(ArbiterJSON.parseDate)
        source = try container.decode(String.self, forKey: .source)
        tool = try container.decodeIfPresent(String.self, forKey: .tool)
        flagged = try container.decode(Bool.self, forKey: .flagged)
        executionState = try container.decodeIfPresent(String.self, forKey: .executionState)
        roomName = try container.decodeIfPresent(String.self, forKey: .roomName)
        trace = try container.decode(GraphQLValue.self, forKey: .trace)
    }

    /// The proposal as Glam recorded it; nil when the trace doesn't read as one (a newer Mac's, say).
    public var proposal: GlamProposal? {
        guard let data = try? ArbiterJSON.encoder.encode(JSONValue(trace)) else { return nil }
        return try? ArbiterJSON.decoder.decode(GlamProposal.self, from: data)
    }

    /// The trace as indented JSON, for when it doesn't read as a proposal.
    public var traceText: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? encoder.encode(JSONValue(trace))).map { String(decoding: $0, as: UTF8.self) } ?? ""
    }
}

public struct HostDecisionPage: Decodable, Sendable {
    public let totalCount: Int
    public let nodes: [HostDecisionRecord]
    public let pageInfo: StaffDecisionPage.Info
}

extension DecisionQueueClient {
    static let hostDecisionsQuery = """
        query ArbiterHostDecisions($first: Int, $after: String, $flagged: Boolean) {
          hostDecisions(first: $first, after: $after, flagged: $flagged) {
            totalCount nodes { id decidedAt source tool flagged executionState roomName trace }
            pageInfo { hasNextPage endCursor }
          }
        }
        """

    /// The AI host's calls, newest first, as its Mac uploaded them; with `flagged`, only those a check flagged.
    public func hostDecisions(after: String? = nil, flagged: Bool = false) async throws -> HostDecisionPage {
        var variables: [String: GraphQLValue] = ["first": .int(Self.pageSize), "after": after.map(GraphQLValue.string) ?? .null]
        if flagged { variables["flagged"] = .bool(true) }
        guard let page = try await session.graphQL(Self.hostDecisionsQuery, variables: variables,
                                                   as: [String: HostDecisionPage].self)["hostDecisions"] else {
            throw AudienceKitError.decoding("The AI host's calls were missing")
        }
        return page
    }
}

// MARK: - What Glam made of each message

/// What the audience's AI host made of one chat message (Audience.messageAnalyses): its ruling, what was done about
/// it, and the deep analysis as a numbered JSON shape, on whichever chat provider the message is (AudienceKit's rooms,
/// Discord, an XMPP server). The Mac's Glam writes them; Arbiter anywhere reads them without running a model.
public struct MessageAnalysisRecord: Decodable, Sendable, Identifiable {
    /// One thing done or proposed about the message: `by` is host (what Glam sent) or server (what the API did).
    public struct Action: Decodable, Sendable, Hashable {
        public let action: String
        public let label: String?
        public let state: String?
        public let category: String?
        public let error: String?
        public let punitive: Bool?
        public let by: String?
    }

    public let id: String
    public let chatProvider: String
    public let messageId: String
    public let roomName: String?
    /// The message's words, when AudienceKit has its transcript (not for a Discord message, say).
    public let text: String?
    public let sentAt: Date?
    public let ruling: String?
    public let category: String?
    public let confidence: Double?
    public let flagged: Bool
    public let executionState: String?
    public let actions: [Action]
    /// The settings Glam ran with: nil for the default, or a named variant.
    public let configuration: String?
    /// Which run of its configuration on the message this is, from 1; the newest (`current`) wins.
    public let version: Int
    public let current: Bool
    /// The shape `analysis` is in (the API's doc/MESSAGE_ANALYSIS.md).
    public let shapeVersion: Int
    public let analysis: GraphQLValue
    public let analyzedAt: Date?
    /// The live call behind it, with everything Glam read; nil when the host sent the analysis on its own.
    public let decision: HostDecisionRecord?

    enum CodingKeys: String, CodingKey {
        case id, chatProvider, messageId, roomName, text, sentAt, ruling, category, confidence, flagged, executionState
        case actions, configuration, version, current, shapeVersion, analysis, analyzedAt, decision
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        chatProvider = try container.decode(String.self, forKey: .chatProvider)
        messageId = try container.decode(String.self, forKey: .messageId)
        roomName = try container.decodeIfPresent(String.self, forKey: .roomName)
        text = try container.decodeIfPresent(String.self, forKey: .text)
        sentAt = try container.decodeIfPresent(String.self, forKey: .sentAt).flatMap(ArbiterJSON.parseDate)
        ruling = try container.decodeIfPresent(String.self, forKey: .ruling)
        category = try container.decodeIfPresent(String.self, forKey: .category)
        confidence = try container.decodeIfPresent(Double.self, forKey: .confidence)
        flagged = try container.decode(Bool.self, forKey: .flagged)
        executionState = try container.decodeIfPresent(String.self, forKey: .executionState)
        // Kept as JSON on the server, so an action of a newer shape is skipped rather than failing the page.
        actions = (try? container.decode([FailableAction].self, forKey: .actions))?.compactMap(\.value) ?? []
        configuration = try container.decodeIfPresent(String.self, forKey: .configuration)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        current = try container.decodeIfPresent(Bool.self, forKey: .current) ?? true
        shapeVersion = try container.decodeIfPresent(Int.self, forKey: .shapeVersion) ?? 1
        analysis = try container.decode(GraphQLValue.self, forKey: .analysis)
        analyzedAt = try container.decodeIfPresent(String.self, forKey: .analyzedAt).flatMap(ArbiterJSON.parseDate)
        decision = try container.decodeIfPresent(HostDecisionRecord.self, forKey: .decision)
    }

    private struct FailableAction: Decodable {
        let value: Action?
        init(from decoder: Decoder) throws { value = try? Action(from: decoder) }
    }

    /// The deep analysis as indented JSON.
    public var analysisText: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? encoder.encode(JSONValue(analysis))).map { String(decoding: $0, as: UTF8.self) } ?? ""
    }
}

public struct MessageAnalysisPage: Decodable, Sendable {
    public let totalCount: Int
    public let nodes: [MessageAnalysisRecord]
    public let pageInfo: StaffDecisionPage.Info
}

extension DecisionQueueClient {
    static let messageAnalysesQuery = """
        query ArbiterMessageAnalyses($first: Int, $after: String, $actedOn: Boolean, $flagged: Boolean) {
          messageAnalyses(first: $first, after: $after, actedOn: $actedOn, flagged: $flagged) {
            totalCount
            nodes {
              id chatProvider messageId roomName text sentAt ruling category confidence flagged executionState
              actions configuration version current shapeVersion analysis analyzedAt
              decision { id decidedAt source tool flagged executionState roomName trace }
            }
            pageInfo { hasNextPage endCursor }
          }
        }
        """

    /// What Glam made of each message, newest first; with `actedOn`, only rulings other than no action, with
    /// `flagged`, only messages a check flagged.
    public func messageAnalyses(after: String? = nil, actedOn: Bool = false,
                                flagged: Bool = false) async throws -> MessageAnalysisPage {
        var variables: [String: GraphQLValue] = ["first": .int(Self.pageSize), "after": after.map(GraphQLValue.string) ?? .null]
        if actedOn { variables["actedOn"] = .bool(true) }
        if flagged { variables["flagged"] = .bool(true) }
        guard let page = try await session.graphQL(Self.messageAnalysesQuery, variables: variables,
                                                   as: [String: MessageAnalysisPage].self)["messageAnalyses"] else {
            throw AudienceKitError.decoding("Glam's rulings were missing")
        }
        return page
    }
}
