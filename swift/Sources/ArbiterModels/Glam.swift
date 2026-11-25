import Foundation

/// A chat line as the host sees it: an opaque handle, never a name. `role` is set for the room's own people.
public struct ChatLine: Codable, Sendable, Hashable {
    public enum Role: String, Codable, Sendable { case staff, venue, host }

    public let handle: String
    public let role: Role?
    /// The message's own words; a rich message's title is apart, in `title`.
    public let text: String
    public let sentAt: Date?
    /// What it is (text, announcement, event, special, request, photo, prompt); nil when the feed didn't say.
    public let kind: String?
    /// A rich message's name: an announcement's or special's title, the shared event's, the song request.
    public let title: String?

    public init(handle: String, role: Role? = nil, text: String, sentAt: Date? = nil, kind: String? = nil,
                title: String? = nil) {
        self.handle = handle; self.role = role; self.text = text; self.sentAt = sentAt; self.kind = kind; self.title = title
    }
}

public struct ChatRoom: Codable, Sendable, Hashable {
    public let id: String
    public let name: String?
    /// venue, event, direct, …
    public let kind: String

    public init(id: String, name: String?, kind: String) { self.id = id; self.name = name; self.kind = kind }
}

/// Which tool Glam picked, and how sure it was (nil confidence when the engine gave no probabilities).
public struct GlamChoice: Codable, Sendable, Hashable {
    public let tool: String
    public let method: AnswerMethod
    public let scores: [String: Double]?
    public let conformalSet: [String]
    public let confidence: Double?

    public init(tool: String, method: AnswerMethod, scores: [String: Double]?, conformalSet: [String], confidence: Double?) {
        self.tool = tool; self.method = method; self.scores = scores; self.conformalSet = conformalSet
        self.confidence = confidence
    }
}

public struct GlamCall: Codable, Sendable, Hashable {
    /// no_action, private_nudge, public_reminder, room_message, welcome_newcomer, pin_message, set_room_prompt,
    /// cooldown, ban_proposal, move_to_private_thread, read_venue_info, read_event_info, read_set_list,
    /// reshow_guidelines.
    public let tool: String
    public let arguments: [String: JSONValue]
    public let rationale: String

    public init(tool: String, arguments: [String: JSONValue] = [:], rationale: String = "") {
        self.tool = tool; self.arguments = arguments; self.rationale = rationale
    }
}

/// What the code-side gate says about a call.
public struct GateResult: Codable, Sendable, Hashable {
    public let allowed: Bool
    /// Punitive calls always wait for a person.
    public let needsApproval: Bool
    public let blocked: [String]

    public init(allowed: Bool, needsApproval: Bool, blocked: [String] = []) {
        self.allowed = allowed; self.needsApproval = needsApproval; self.blocked = blocked
    }
}

public struct ProposalLabel: Codable, Sendable, Hashable {
    public enum Verdict: String, Codable, Sendable, CaseIterable {
        case right, wrong, wrongTool = "wrong_tool", tooHarsh = "too_harsh", tooSoft = "too_soft"
    }

    public let verdict: Verdict
    public let note: String?
    public let at: Date

    public init(verdict: Verdict, note: String? = nil, at: Date = Date()) {
        self.verdict = verdict; self.note = note; self.at = at
    }
}

/// One API call that carries out part of a proposal (Mutation.chat.moderation.*).
public struct HostStep: Codable, Sendable, Hashable {
    public enum Result: String, Codable, Sendable { case done, failed }

    /// say, warnUser, pinMessage, cooldownUser, banUser, escalate, notifyVenue, crisisResources.
    public let field: String
    /// What it does, for the observer.
    public let label: String
    public let input: [String: JSONValue]
    /// Punitive steps wait for a person even in live mode.
    public let punitive: Bool
    public var result: Result?
    public var error: String?

    public init(field: String, label: String, input: [String: JSONValue], punitive: Bool, result: Result? = nil,
                error: String? = nil) {
        self.field = field; self.label = label; self.input = input; self.punitive = punitive; self.result = result
        self.error = error
    }
}

/// How far a proposal got.
public struct Execution: Codable, Sendable, Hashable {
    public enum State: String, Codable, Sendable {
        /// Shadow mode: nothing is ever carried out.
        case shadow
        /// Blocked, nothing to do, or not from the live feed.
        case notRun = "not_run"
        /// A person must approve.
        case awaiting
        case done, partial, failed, dismissed
    }

    public var state: State
    public var steps: [HostStep]
    public var note: String?
    public var at: Date?

    public init(state: State, steps: [HostStep] = [], note: String? = nil, at: Date? = nil) {
        self.state = state; self.steps = steps; self.note = note; self.at = at
    }
}

/// shadow carries nothing out; approve waits for a person on every call; live carries out what the gate allows and
/// waits on punitive calls.
public enum GlamMode: String, Codable, Sendable, CaseIterable { case shadow, approve, live }

/// What a read tool fetched and the answer Glam drafted from it, on proposals from before Glam looked things up first
/// (`GlamLookup`).
public struct GlamRead: Codable, Sendable, Hashable {
    public let info: JSONValue?
    public let answer: String?
    public let error: String?

    public init(info: JSONValue?, answer: String?, error: String? = nil) {
        self.info = info; self.answer = answer; self.error = error
    }
}

/// One read tool Glam called before choosing what to do, and what it fetched: the room's facts from the API
/// (Query.chat.moderation.room), shown to the model as data. `info` is nil when there was nothing to fetch.
public struct GlamLookup: Codable, Sendable, Hashable {
    public let tool: String
    public let info: JSONValue?
    public let error: String?

    public init(tool: String, info: JSONValue?, error: String? = nil) {
        self.tool = tool; self.info = info; self.error = error
    }
}

/// The settings a run of Glam used, kept with it so two runs of a message can be told apart.
public struct RunSettings: Codable, Sendable, Hashable {
    public let hostName: String?
    public let glamModel: String?
    public let guardModel: String?
    public let rulesEnabled: Bool
    public let rulesModel: EngineSettings.RulesModel
    public let alpha: Double
    public let coverageThreshold: Double
    public let venueRating: VenueRating
    public let guardThresholds: [String: Double]
    public let ruleThresholds: [String: [VenueRating: Double]]
    /// The API's prompts the run used (version and digest); nil when it ran on the built-in text.
    public let prompts: [PromptStamp]?

    public init(_ settings: EngineSettings) {
        hostName = settings.host
        glamModel = settings.modelPath.map { ($0 as NSString).lastPathComponent }
        guardModel = settings.guardModelPath.map { ($0 as NSString).lastPathComponent }
        rulesEnabled = settings.rulesEnabled
        rulesModel = settings.rulesModel
        alpha = settings.alpha
        coverageThreshold = settings.coverageThreshold
        venueRating = settings.venueRating
        guardThresholds = settings.guardThresholds
        ruleThresholds = settings.ruleThresholds
        prompts = settings.prompts.map(\.stamps).flatMap { $0.isEmpty ? nil : $0 }
    }
}

/// One message Glam considered, with everything the observer shows.
public struct GlamProposal: Codable, Sendable, Hashable, Identifiable {
    public enum Source: String, Codable, Sendable { case live, replay, `try` }

    public let id: String
    public let at: Date
    public let mode: Source
    public let room: ChatRoom
    /// Oldest first. The last line is the one judged; the earlier lines are context only.
    public let lines: [ChatLine]
    /// Handles as the letters the model saw them under (A sent the judged line).
    public let letters: [String: String]
    /// Security and integrity checks on the judged line; nil when the guard is off.
    public let guardChecks: [PolicyCheck]?
    /// Moderation checks on the judged line; nil when the rules are off.
    public let rules: [PolicyCheck]?
    public let ruleActions: [RuleActionProposal]
    /// The guard flagged the line, or couldn't score a check on it.
    public let injection: Bool
    public let choice: GlamChoice?
    public let call: GlamCall
    /// A call whose arguments didn't fit, so it became no action.
    public let rejected: GlamCall?
    public let errors: [String]
    public let gate: GateResult
    public let model: String
    public let durationMs: Int
    /// Whether anything was carried out.
    public var executed: Bool
    /// The feed event the judged line came from; nil for a made-up conversation.
    public let cursor: String?
    public let read: GlamRead?
    /// The read tools Glam called before its call, in order; nil on proposals from before it looked things up first.
    public let lookups: [GlamLookup]?
    public var execution: Execution?
    public var label: ProposalLabel?
    /// The configuration this run belongs to; nil is the default. A variant is for comparing and never carries out.
    public let configuration: String?
    /// What the run used; nil on runs from before it was kept.
    public let settings: RunSettings?

    enum CodingKeys: String, CodingKey {
        case id, at, mode, room, lines, letters, rules, ruleActions, injection, choice, call, rejected, errors, gate, model
        case durationMs, executed, cursor, read, lookups, execution, label, configuration, settings
        case guardChecks = "guard"
    }

    public init(id: String, at: Date, mode: Source, room: ChatRoom, lines: [ChatLine], letters: [String: String],
                guardChecks: [PolicyCheck]?, rules: [PolicyCheck]?, ruleActions: [RuleActionProposal] = [],
                injection: Bool = false, choice: GlamChoice?, call: GlamCall, rejected: GlamCall? = nil,
                errors: [String] = [], gate: GateResult, model: String, durationMs: Int, executed: Bool = false,
                cursor: String?, read: GlamRead? = nil, lookups: [GlamLookup]? = nil, execution: Execution? = nil, label: ProposalLabel? = nil,
                configuration: String? = nil, settings: RunSettings? = nil) {
        self.id = id; self.at = at; self.mode = mode; self.room = room; self.lines = lines; self.letters = letters
        self.guardChecks = guardChecks; self.rules = rules; self.ruleActions = ruleActions; self.injection = injection
        self.choice = choice; self.call = call; self.rejected = rejected; self.errors = errors; self.gate = gate
        self.model = model; self.durationMs = durationMs; self.executed = executed; self.cursor = cursor
        self.read = read; self.lookups = lookups; self.execution = execution; self.label = label
        self.configuration = configuration; self.settings = settings
    }

    /// The line every check and the call are on.
    public var judged: ChatLine? { lines.last }
    /// The earlier lines, shown as context only.
    public var context: ArraySlice<ChatLine> { lines.dropLast() }
    /// Who sent a line, as the observer names them: their role, or the letter the model saw.
    public func speaker(_ line: ChatLine) -> String { line.role?.rawValue ?? letters[line.handle] ?? "?" }
    /// The checks in a group.
    public func checks(_ group: CheckGroup) -> [PolicyCheck]? {
        switch group {
        case .moderation: rules
        case .securityAndIntegrity: guardChecks
        }
    }
}

public struct GlamStatus: Codable, Sendable, Hashable {
    public enum State: String, Codable, Sendable { case stopped, connecting, watching, replaying, error }

    /// A message Glam has yet to finish: the one it's working on, or one waiting its turn.
    public struct Pending: Codable, Sendable, Hashable, Identifiable {
        public let id: String
        public let room: ChatRoom
        /// When it was sent (for a replay, its own time on the evening).
        public let at: Date
        public let text: String
        public let source: GlamProposal.Source
        /// What it's waiting on now (the guard, the rules, Glam, a look-up), for the one in progress.
        public var step: String?
        /// When Glam took it up, for the one in progress.
        public var started: Date?
        /// The lines Glam reads, oldest first, the judged one last.
        public var lines: [ChatLine]
        public var letters: [String: String]
        /// What's known so far, filled in as each step finishes (nil until it has).
        public var guardChecks: [PolicyCheck]?
        public var rules: [PolicyCheck]?
        public var lookups: [GlamLookup]
        public var errors: [String]

        public init(id: String, room: ChatRoom, at: Date, text: String, source: GlamProposal.Source,
                    step: String? = nil, started: Date? = nil, lines: [ChatLine] = [], letters: [String: String] = [:],
                    guardChecks: [PolicyCheck]? = nil, rules: [PolicyCheck]? = nil, lookups: [GlamLookup] = [],
                    errors: [String] = []) {
            self.id = id; self.room = room; self.at = at; self.text = text; self.source = source
            self.step = step; self.started = started; self.lines = lines; self.letters = letters
            self.guardChecks = guardChecks; self.rules = rules; self.lookups = lookups; self.errors = errors
        }

        /// What's known so far as a proposal, for the detail view; its call and gate mean nothing yet.
        public var draft: GlamProposal {
            GlamProposal(id: id, at: started ?? at, mode: source, room: room, lines: lines, letters: letters,
                         guardChecks: guardChecks, rules: rules, choice: nil, call: GlamCall(tool: "no_action"),
                         errors: errors, gate: GateResult(allowed: true, needsApproval: false), model: "",
                         durationMs: started.map { Int(Date().timeIntervalSince($0) * 1000) } ?? 0, cursor: nil,
                         lookups: lookups)
        }
    }

    /// One line of what Glam did, for its log.
    public struct LogLine: Codable, Sendable, Hashable, Identifiable {
        public let id: Int
        public let at: Date
        public let text: String
        public let isError: Bool

        public init(id: Int, at: Date, text: String, isError: Bool = false) {
            self.id = id; self.at = at; self.text = text; self.isError = isError
        }
    }

    /// How many queued messages the status carries; `backlog` still counts them all.
    public static let queuedShown = 50
    /// How many log lines the status keeps, newest last.
    public static let logKept = 300

    public var state: State
    public var message: String?
    public var backlog: Int
    public var handled: Int
    /// The message Glam is working on, if any.
    public var working: Pending?
    /// The next messages waiting, oldest first (at most `queuedShown`).
    public var queued: [Pending]
    /// What Glam did lately, oldest first (at most `logKept`).
    public var log: [LogLine]

    public init(state: State = .stopped, message: String? = nil, backlog: Int = 0, handled: Int = 0,
                working: Pending? = nil, queued: [Pending] = [], log: [LogLine] = []) {
        self.state = state; self.message = message; self.backlog = backlog; self.handled = handled
        self.working = working; self.queued = queued; self.log = log
    }
}

/// A made-up conversation for "Try a conversation": oldest first, the last line judged.
public struct TryLine: Codable, Sendable, Hashable {
    public let author: String
    public let role: ChatLine.Role?
    public let text: String

    public init(author: String, role: ChatLine.Role? = nil, text: String) {
        self.author = author; self.role = role; self.text = text
    }
}

/// Glam, the local AI host (macOS: ArbiterEngine). The UI drives it and renders what it streams.
public protocol GlamService: Sendable {
    func status() -> AsyncStream<GlamStatus>
    /// Each new or changed proposal (a label, an approval).
    func proposals() -> AsyncStream<GlamProposal>
    /// The kept proposals, newest first.
    func recent() async -> [GlamProposal]
    func start() async
    func stop() async
    /// Runs Glam over the feed's kept events between two times, as if live; nothing is carried out.
    func replay(from: Date, to: Date) async throws
    /// Runs one made-up conversation; nothing is carried out.
    func tryConversation(_ lines: [TryLine]) async throws -> GlamProposal
    func label(_ id: String, verdict: ProposalLabel.Verdict, note: String?) async
    /// Carries out a proposal that waits for a person.
    func approve(_ id: String) async throws
    func dismiss(_ id: String) async
    /// Writes the labelled proposals as an eval set; returns the file and how many.
    func exportLabels() async throws -> (url: URL, count: Int)
}
