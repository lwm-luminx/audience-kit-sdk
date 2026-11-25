import Foundation
import AudienceCore
import StaffKitCore
import ArbiterModels

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Something the API said no to, in its own words.
public struct ArbiterServiceError: LocalizedError, Sendable, Equatable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

/// A device's way into the API as itself rather than as a person: Arbiter on a Mac works the evaluation queue and
/// follows the chat moderation feed on a worker token (Mutation.issueWorkerToken), never on someone's sign-in. The
/// token's secret is traded for a one-hour JWT at `POST /v1/token/service`, which signs one cable to the API; the JWT
/// is renewed before it runs out, so a reconnect always signs in with a live one. Everything goes over that cable:
/// the API lets a service token reach only what its scopes are for (api doc/DECISION_QUEUE.md, doc/CHAT_MODERATION.md).
public actor ArbiterServiceConnection {
    /// The scope a token needs to follow the chat feed (Moderation::Feed::FEED_PERMISSION in the API).
    public static let feedScope = "chat:moderate:*"
    /// Renew the JWT this long before it runs out.
    static let renewBefore: TimeInterval = 5 * 60

    /// A JWT the API minted for the token: when it runs out, the audience it's for, and what it may reach.
    public struct Grant: Sendable, Equatable {
        public let token: String
        public let expiresAt: Date
        public let audienceID: String
        public let scopes: [String]
    }

    public nonisolated let baseURL: URL
    private let secret: @Sendable () -> String?
    private let urlSession: URLSession
    private let current = CredentialBox()
    private var grant: Grant?
    private var liveCable: AudienceCable?
    private var renewal: Task<Void, Never>?

    /// - Parameter secret: The worker token's secret, read whenever the API needs it (from the keychain).
    public init(baseURL: URL, urlSession: URLSession = .shared, secret: @escaping @Sendable () -> String?) {
        self.baseURL = baseURL; self.urlSession = urlSession; self.secret = secret
    }

    /// The live grant, trading the token for a new one when there's none or it's about to run out.
    public func signIn() async throws -> Grant {
        if let grant, grant.expiresAt.timeIntervalSinceNow > Self.renewBefore { return grant }
        guard let secret = secret(), !secret.isEmpty else {
            throw ArbiterServiceError("Create a token for this Mac in Settings first.")
        }
        let fresh = try await exchange(secret)
        grant = fresh
        current.set(Credential(token: fresh.token, userId: "service", audienceId: fresh.audienceID, role: "service",
                               endpoint: baseURL.appendingPathComponent("v1/audience/\(fresh.audienceID)/graphql"),
                               expiresAt: fresh.expiresAt))
        scheduleRenewal(fresh.expiresAt)
        return fresh
    }

    /// Forgets the grant and closes the cable: after a new token is made, say.
    public func reset() async {
        renewal?.cancel(); renewal = nil
        grant = nil
        current.set(nil)
        await liveCable?.disconnect()
        liveCable = nil
    }

    /// Runs one GraphQL operation (a subscription, usually) over the cable, in the token's audience.
    public func subscribe(_ query: String, variables: [String: GraphQLValue] = [:]) async throws
        -> AsyncStream<AudienceCable.Event> {
        let grant = try await signIn()
        return await cable().subscribe(query: query, variables: variables, audienceID: grant.audienceID)
    }

    /// How long a query or mutation waits for its answer: a cable that reconnects can drop one, and Glam handles
    /// messages one at a time, so an answer that never comes would hold up every message behind it.
    static let requestTimeout: Duration = .seconds(45)

    /// Runs a query or mutation over the cable and returns its `data`; throws the API's first error, or when no answer
    /// comes within `requestTimeout`.
    public func request(_ query: String, variables: [String: GraphQLValue] = [:]) async throws -> JSONValue {
        let events = try await subscribe(query, variables: variables)
        return try await withThrowingTaskGroup(of: JSONValue.self) { group in
            group.addTask { try await Self.answer(events) }
            group.addTask {
                try await Task.sleep(for: Self.requestTimeout)
                throw ArbiterServiceError("The API didn't answer in time.")
            }
            defer { group.cancelAll() }
            guard let data = try await group.next() else { throw ArbiterServiceError("The API sent no answer.") }
            return data
        }
    }

    /// Calls one method on the API's MCP server (POST /v1/mcp, api doc/MCP.md) with this Mac's JWT, and returns its
    /// `result`; throws its JSON-RPC error. Stateless JSON-RPC over HTTP, as the server speaks it: no session, no stream.
    /// `worker` names the AI worker making the call (`X-AudienceKit-Worker`, api doc/AI_WORKERS.md), so the server
    /// offers it only the tools the console permits that worker; an API from before the Workers page ignores it.
    public func mcp(_ method: String, params: JSONValue = .object([:]), worker: AIWorkerKey? = nil) async throws -> JSONValue {
        let grant = try await signIn()
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/mcp"))
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(grant.token)", forHTTPHeaderField: "Authorization")
        if let worker { request.setValue(worker.header, forHTTPHeaderField: "X-AudienceKit-Worker") }
        let body: JSONValue = .object(["jsonrpc": .string("2.0"), "id": .number(1), "method": .string(method),
                                       "params": params])
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await urlSession.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { forgetGrant() }
        guard (200..<300).contains(status) else { throw ArbiterServiceError("The API's MCP server answered HTTP \(status).") }
        let reply = try JSONDecoder().decode(JSONValue.self, from: data)
        if let error = reply["error"] { throw ArbiterServiceError(error["message"]?.string ?? "The MCP call failed.") }
        guard let result = reply["result"] else { throw ArbiterServiceError("The MCP server sent no result.") }
        return result
    }

    /// Runs one of the MCP server's tools and returns what it found, parsed from its text; a tool's own refusal (the
    /// result flagged isError) throws with its message.
    public func mcpTool(_ name: String, arguments: [String: JSONValue] = [:], worker: AIWorkerKey? = nil) async throws
        -> JSONValue {
        let result = try await mcp("tools/call", params: .object(["name": .string(name), "arguments": .object(arguments)]),
                                   worker: worker)
        guard case .array(let content)? = result["content"], let text = content.first?["text"]?.string else {
            throw ArbiterServiceError("The MCP tool \(name) sent nothing back.")
        }
        if result["isError"] == .bool(true) { throw ArbiterServiceError(text) }
        return (try? JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))) ?? .string(text)
    }

    private static func answer(_ events: AsyncStream<AudienceCable.Event>) async throws -> JSONValue {
        for await event in events {
            switch event {
            case .subscribed, .disconnected(_, true): continue
            case .result(let data): return try Self.data(of: data)
            case .disconnected(let reason, false): throw ArbiterServiceError(reason ?? "The API closed the connection.")
            default: throw ArbiterServiceError("The API turned this Mac's token away.")  // rejected
            }
        }
        throw ArbiterServiceError("The API sent no answer.")
    }

    /// A GraphQL result's `data`, or its first error.
    static func data(of result: Data) throws -> JSONValue {
        struct Result: Decodable {
            struct Problem: Decodable { let message: String }
            let data: JSONValue?
            let errors: [Problem]?
        }
        let decoded = try JSONDecoder().decode(Result.self, from: result)
        if let problem = decoded.errors?.first { throw ArbiterServiceError(problem.message) }
        guard let data = decoded.data, data != .null else { throw ArbiterServiceError("The API sent no data.") }
        return data
    }

    private func cable() -> AudienceCable {
        if let liveCable { return liveCable }
        let box = current
        let cable = AudienceCable(configuration: AudienceKitConfiguration(baseURL: baseURL), endpoint: .consumer,
                                  url: AudienceCable.url(for: baseURL), session: urlSession,
                                  credential: { box.get() },
                                  unauthorized: { _ in Task { await self.forgetGrant() } })
        liveCable = cable
        return cable
    }

    private func forgetGrant() { grant = nil }

    /// Keeps the credential the cable reconnects with live: a new JWT a few minutes before this one runs out.
    private func scheduleRenewal(_ expiresAt: Date) {
        renewal?.cancel()
        let wait = max(60, expiresAt.timeIntervalSinceNow - Self.renewBefore)
        renewal = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled, let self else { return }
            await self.renew()
        }
    }

    private func renew() async {
        grant = nil
        do { _ = try await signIn() } catch { scheduleRenewal(Date().addingTimeInterval(Self.renewBefore + 60)) }
    }

    private func exchange(_ secret: String) async throws -> Grant {
        struct Body: Encodable { let service_token: String }
        struct Reply: Decodable {
            let token: String
            let expiresAt: String
            let audienceId: String
            let scopes: [String]
        }
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/token/service"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(AudienceKitSDK.apiVersion, forHTTPHeaderField: "X-AudienceKit-API-Version")
        request.httpBody = try JSONEncoder().encode(Body(service_token: secret))
        let (data, response) = try await urlSession.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw ArbiterServiceError(status == 401
                ? "This Mac's token was revoked or has expired. Create a new one in Settings."
                : "Signing in with this Mac's token failed (HTTP \(status)).")
        }
        let reply = try JSONDecoder().decode(Reply.self, from: data)
        return Grant(token: reply.token, expiresAt: ArbiterDates.parse(reply.expiresAt) ?? Date().addingTimeInterval(3600),
                     audienceID: reply.audienceId, scopes: reply.scopes)
    }
}

/// The credential a cable reconnects with, read from outside the actor.
private final class CredentialBox: @unchecked Sendable {
    private let lock = NSLock()
    private var credential: Credential?
    func get() -> Credential? { lock.lock(); defer { lock.unlock() }; return credential }
    func set(_ value: Credential?) { lock.lock(); credential = value; lock.unlock() }
}

/// The API's ISO 8601 times, with or without fractional seconds.
enum ArbiterDates {
    static func parse(_ text: String?) -> Date? {
        guard let text else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            guard let date = parse(text) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Not a time: \(text)"))
            }
            return date
        }
        return decoder
    }

    /// A JSONValue read as a Decodable type, the API's way (ISO 8601 times).
    static func decode<T: Decodable>(_ type: T.Type, from value: JSONValue) throws -> T {
        try decoder().decode(type, from: JSONEncoder().encode(value))
    }
}

extension GraphQLValue {
    /// A JSON value as a GraphQL variable. Whole numbers go as Int, so they fit Int arguments (a cooldown's minutes).
    public init(_ json: JSONValue) {
        switch json {
        case .null: self = .null
        case .bool(let value): self = .bool(value)
        case .number(let value):
            if value.rounded() == value, abs(value) < 1e15 { self = .int(Int(value)) } else { self = .double(value) }
        case .string(let value): self = .string(value)
        case .array(let values): self = .array(values.map(GraphQLValue.init))
        case .object(let fields): self = .object(fields.mapValues(GraphQLValue.init))
        }
    }
}

extension JSONValue {
    public init(_ value: GraphQLValue) {
        switch value {
        case .bool(let value): self = .bool(value)
        case .int(let value): self = .number(Double(value))
        case .double(let value): self = .number(value)
        case .string(let value): self = .string(value)
        case .array(let values): self = .array(values.map(JSONValue.init))
        case .object(let fields): self = .object(fields.mapValues(JSONValue.init))
        default: self = .null  // null
        }
    }
}

// MARK: - The evaluation queue

/// The evaluation queue on this Mac's token (ArbiterModels' `WorkerQueue`, which ArbiterEngine's DecisionWorker drives):
/// Subscription.evaluationQueue says when work waits, claimEvaluation takes it, and completeEvaluation,
/// failEvaluation and renewEvaluationLease answer for it (api doc/DECISION_QUEUE.md).
public struct CableWorkerQueue: WorkerQueue {
    static let follow = """
        subscription ArbiterWorkWaiting($types: [String!]) { evaluationQueue(evaluationTypes: $types) { evaluationTypes pending } }
        """
    static let claim = """
        mutation ArbiterClaim($types: [String!]) { claimEvaluation(input: { evaluationTypes: $types }) { work {
          id evaluationType lease leaseExpiresAt attempt question decisionKind input options { key label description }
        } } }
        """
    static let complete = """
        mutation ArbiterComplete($input: EvaluationCompleteInput!) { completeEvaluation(input: $input) { decision { id state unsure needsPerson } } }
        """
    static let fail = """
        mutation ArbiterFail($input: EvaluationFailInput!) { failEvaluation(input: $input) { decision { id state } } }
        """
    static let renew = """
        mutation ArbiterRenew($input: EvaluationLeaseRenewInput!) { renewEvaluationLease(input: $input) { leaseExpiresAt } }
        """
    static let retry: [Duration] = [.seconds(1), .seconds(5), .seconds(15), .seconds(60)]

    let connection: ArbiterServiceConnection
    let types: @Sendable () -> [String]

    /// - Parameter types: The evaluation types to hear about (Settings); empty for every type the token may take.
    public init(connection: ArbiterServiceConnection, types: @escaping @Sendable () -> [String]) {
        self.connection = connection; self.types = types
    }

    private static func typesVariable(_ types: [String]?) -> GraphQLValue {
        guard let types, !types.isEmpty else { return .null }
        return .array(types.map(GraphQLValue.string))
    }

    public func workAvailable() -> AsyncStream<Void> {
        let connection = connection, types = types
        return AsyncStream { continuation in
            let task = Task {
                var attempt = 0
                while !Task.isCancelled {
                    do {
                        let variables = ["types": Self.typesVariable(types())]
                        for await event in try await connection.subscribe(Self.follow, variables: variables) {
                            switch event {
                            case .subscribed: attempt = 0; continuation.yield()
                            case .result: continuation.yield()
                            default: break  // rejected, disconnected
                            }
                        }
                    } catch {}
                    try? await Task.sleep(for: Self.retry[min(attempt, Self.retry.count - 1)])
                    attempt += 1
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func claim(types: [String]?) async throws -> DecisionWork? {
        let data = try await connection.request(Self.claim, variables: ["types": Self.typesVariable(types)])
        guard let work = data["claimEvaluation"]?["work"], work != .null else { return nil }
        return try ArbiterDates.decode(DecisionWork.self, from: work)
    }

    public func complete(_ work: DecisionWork, answer: EngineAnswer) async throws {
        let input: [String: GraphQLValue] = [
            "id": .string(work.id), "lease": .string(work.lease),
            "scores": .object(answer.scores.mapValues(GraphQLValue.double)),
            "conformalSet": .array(answer.conformalSet.map(GraphQLValue.string)),
            "result": GraphQLValue(answer.result),
        ]
        _ = try await connection.request(Self.complete, variables: ["input": .object(input)])
    }

    public func fail(_ work: DecisionWork, error: String) async throws {
        let input: [String: GraphQLValue] = ["id": .string(work.id), "lease": .string(work.lease), "error": .string(error)]
        _ = try await connection.request(Self.fail, variables: ["input": .object(input)])
    }

    public func renewLease(_ work: DecisionWork) async throws -> Date {
        let input: [String: GraphQLValue] = ["id": .string(work.id), "lease": .string(work.lease)]
        let data = try await connection.request(Self.renew, variables: ["input": .object(input)])
        guard let date = ArbiterDates.parse(data["renewEvaluationLease"]?["leaseExpiresAt"]?.string) else {
            throw ArbiterServiceError("The API didn't say when the lease runs out.")
        }
        return date
    }
}

// MARK: - The chat moderation feed

/// The audience's chat moderation feed on this Mac's token (ArbiterModels' `ModerationFeed`, which Glam follows):
/// Subscription.chatModeration, people as opaque handles only. Needs a token made with the chat feed. Reconnects
/// after the last message it passed on, and never passes one on twice.
public struct CableModerationFeed: ModerationFeed {
    static let line = "subject role kind title body text sentAt"
    static let subscription = subscription(glamOutputs: false)
    /// The fast lane's outputs are asked for only while the audience has it on: an API from before them would refuse
    /// the whole subscription over the unknown type.
    static func subscription(glamOutputs: Bool) -> String {
        let glam = glamOutputs ? """

                ... on ChatModerationGlamOutput { outputId kind category suggestedAction safetyKind reason text posted
                  subject glamMessage: message { \(line) } target { \(line) } handles { handle subject } }
            """ : ""
        return """
            subscription ArbiterFeed($after: ID) {
              chatModeration(after: $after) {
                __typename
                ... on IChatModerationEvent { cursor at room { id kind name } }
                ... on ChatModerationMessageCreated { message { \(line) } context { \(line) } }
                ... on ChatModerationFeedGap { after }
                ... on ChatModerationCaughtUp { caughtUpCursor: cursor }\(glam)
              }
            }
            """
    }
    /// The title of the host's own posts, which are venue announcements (the API's Moderation::Hosting).
    public static let hostTitle = "Glam (AI host)"
    public static let noFeedScope = "This Mac's token can only work the queue. In Settings, create a new token for "
        + "this Mac with \u{201C}Let Glam follow the chat feed\u{201D} on."

    let connection: ArbiterServiceConnection
    /// Read at each (re)connect: whether to ask for the fast lane's outputs (the audience has it on).
    let glamOutputs: @Sendable () -> Bool

    public init(connection: ArbiterServiceConnection, glamOutputs: @escaping @Sendable () -> Bool = { false }) {
        self.connection = connection
        self.glamOutputs = glamOutputs
    }

    public func follow(after: String?) -> AsyncThrowingStream<ModerationFeedFrame, Error> {
        let connection = connection
        let glamOutputs = glamOutputs
        return AsyncThrowingStream { continuation in
            let task = Task {
                var last = after
                var attempt = 0
                while !Task.isCancelled {
                    do {
                        let grant = try await connection.signIn()
                        guard grant.scopes.contains(ArbiterServiceConnection.feedScope) else {
                            throw ArbiterServiceError(Self.noFeedScope)
                        }
                        let variables: [String: GraphQLValue] = ["after": last.map(GraphQLValue.string) ?? .null]
                        let query = Self.subscription(glamOutputs: glamOutputs())
                        stream: for await event in try await connection.subscribe(query, variables: variables) {
                            switch event {
                            case .subscribed: attempt = 0
                            case .result(let data):
                                guard let frame = try Self.frame(ArbiterServiceConnection.data(of: data)) else { continue }
                                if let cursor = frame.feedCursor {
                                    // A reconnect re-runs the subscription from where it started: skip what was passed on.
                                    if let last, let seen = Int(last), let now = Int(cursor), now <= seen { continue }
                                    last = cursor
                                }
                                continuation.yield(frame)
                            case .disconnected(_, let reconnects): if !reconnects { break stream }
                            default: throw ArbiterServiceError("The API turned this Mac's token away from the chat feed.")  // rejected
                            }
                        }
                    } catch let error as ArbiterServiceError {
                        continuation.finish(throwing: error)
                        return
                    } catch {}
                    try? await Task.sleep(for: CableWorkerQueue.retry[min(attempt, CableWorkerQueue.retry.count - 1)])
                    attempt += 1
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// One feed item as Glam reads it; nil for the events it doesn't (reports, removals, kicks) and its own posts.
    static func frame(_ data: JSONValue) throws -> ModerationFeedFrame? {
        guard let item = data["chatModeration"] else { return nil }
        switch item["__typename"]?.string {
        case "ChatModerationCaughtUp": return .caughtUp(cursor: item["caughtUpCursor"]?.string)
        case "ChatModerationFeedGap": return .gap
        case "ChatModerationMessageCreated": break
        case "ChatModerationGlamOutput": return glamOutput(item).map(ModerationFeedFrame.glamOutput)
        default: return nil
        }
        guard let cursor = item["cursor"]?.string, let room = item["room"], let roomID = room["id"]?.string,
              let message = item["message"] else { return nil }
        let judged = line(message)
        if judged.role == .venue && (judged.kind == "announcement" && judged.title == hostTitle
                                     || judged.title == nil && judged.text.hasPrefix("Announcement: \(hostTitle)")) { return nil }
        var lines: [ChatLine] = []
        if case .array(let context)? = item["context"] { lines = context.map(line) }
        lines.append(judged)
        return .message(cursor: cursor, at: ArbiterDates.parse(item["at"]?.string) ?? Date(),
                        room: ChatRoom(id: roomID, name: room["name"]?.string,
                                       kind: (room["kind"]?.string ?? "venue").lowercased()),
                        lines: lines.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || $0.title != nil })
    }

    /// A fast-lane output; nil when it lacks what a review needs (its id, cursor, room or a kind this Mac knows).
    static func glamOutput(_ item: JSONValue) -> GlamOutputEvent? {
        guard let cursor = item["cursor"]?.string, let room = item["room"], let roomID = room["id"]?.string,
              let outputID = item["outputId"]?.string,
              let kind = item["kind"]?.string.flatMap(GlamOutputEvent.Kind.init(rawValue:)) else { return nil }
        var handles: [GlamOutputEvent.Handle] = []
        if case .array(let listed)? = item["handles"] {
            handles = listed.compactMap { entry in
                guard let handle = entry["handle"]?.string, let subject = entry["subject"]?.string else { return nil }
                return GlamOutputEvent.Handle(handle: handle, subject: subject)
            }
        }
        let present = { (value: JSONValue?) -> JSONValue? in value == nil || value == .null ? nil : value }
        return GlamOutputEvent(
            cursor: cursor, at: ArbiterDates.parse(item["at"]?.string) ?? Date(),
            room: ChatRoom(id: roomID, name: room["name"]?.string, kind: (room["kind"]?.string ?? "venue").lowercased()),
            outputID: outputID, kind: kind, category: item["category"]?.string,
            suggestedAction: item["suggestedAction"]?.string.flatMap(GlamAction.init(rawValue:)),
            safetyKind: item["safetyKind"]?.string, reason: item["reason"]?.string, text: item["text"]?.string,
            posted: item["posted"] == .bool(true), message: present(item["glamMessage"]).map(line),
            target: present(item["target"]).map(line), subject: item["subject"]?.string, handles: handles)
    }

    /// A rich message's title and words apart (`text` is them run together as "Announcement: Quickie" and its words,
    /// which a model reads as a speaker or a system notice); older events only have `text`.
    static func line(_ raw: JSONValue) -> ChatLine {
        let title = raw["title"]?.string, body = raw["body"]?.string
        let rich = title != nil || body != nil
        return ChatLine(handle: raw["subject"]?.string ?? "?",
                        role: raw["role"]?.string.flatMap { ChatLine.Role(rawValue: $0.lowercased()) },
                        text: rich ? body ?? "" : raw["text"]?.string ?? "", sentAt: ArbiterDates.parse(raw["sentAt"]?.string),
                        kind: raw["kind"]?.string?.lowercased(), title: title)
    }
}

// MARK: - Hosting

/// Glam's actions in a room on this Mac's token (ArbiterModels' `HostActions`): Mutation.chat.moderation's host
/// actions, and Query.chat.moderation.room for its read tools (api doc/CHAT_MODERATION.md, "Hosting"). The API keeps
/// its own guards: its feed's handles only, never the room's own people, the host speaks at most once a minute.
public struct CableHostActions: HostActions {
    /// Each step's mutation, by its `field`, with its input type.
    static let inputs: [String: String] = [
        "say": "ChatModerationSayInput", "shareCard": "ChatModerationShareCardInput", "warnUser": "ChatModerationWarnUserInput",
        "pinMessage": "ChatModerationPinMessageInput", "cooldownUser": "ChatModerationCooldownUserInput",
        "banUser": "ChatModerationBanUserInput", "escalate": "ChatModerationEscalateInput",
        "notifyVenue": "ChatModerationNotifyVenueInput", "crisisResources": "ChatModerationCrisisResourcesInput",
    ]
    static let room = """
        query ArbiterRoom($cursor: ID!, $days: Int) { chat { moderation { room(cursor: $cursor, days: $days) } } }
        """

    let connection: ArbiterServiceConnection

    public init(connection: ArbiterServiceConnection) { self.connection = connection }

    static func mutation(_ field: String) -> String? {
        inputs[field].map { "mutation($input: \($0)!) { chat { moderation { \(field)(input: $input) { action { action } } } } }" }
    }

    /// A step's input as the API takes it: nulls and empty strings left out, since required fields mustn't be null.
    static func cleaned(_ input: [String: JSONValue]) -> [String: GraphQLValue] {
        input.filter { _, value in value != .null && value != .string("") }.mapValues(GraphQLValue.init)
    }

    public func perform(_ step: HostStep) async throws {
        if step.field == "openSafetyAlert" {
            guard let cursor = step.input["cursor"]?.string else { throw ArbiterServiceError("Missing message cursor") }
            var arguments: [String: JSONValue] = ["about_message": .string(cursor)]
            if let text = step.input["text"]?.string, !text.isEmpty { arguments["text"] = .string(text) }
            _ = try await connection.mcpTool("open_safety_alert", arguments: arguments)
            return
        }
        guard let mutation = Self.mutation(step.field) else { throw ArbiterServiceError("Unknown host action: \(step.field)") }
        _ = try await connection.request(mutation, variables: ["input": .object(Self.cleaned(step.input))])
    }

    public func referenceData(cursor: String) async throws -> JSONValue? {
        try await connection.mcpTool("search_reference", arguments: ["about_message": .string(cursor)])
    }

    static let review = """
        mutation($input: ChatModerationReviewGlamOutputInput!) {
          chat { moderation { reviewGlamOutput(input: $input) { action { action } } } }
        }
        """

    /// The verdict as the API takes it: the action and reason only when there are some.
    static func reviewInput(_ review: GlamOutputReview) -> [String: GraphQLValue] {
        var input: [String: GraphQLValue] = ["outputId": .string(review.outputID), "outcome": .string(review.outcome.rawValue),
                                             "retract": .bool(review.retract)]
        if let action = review.action { input["action"] = .string(action.rawValue) }
        if let reason = review.reason, !reason.isEmpty { input["reason"] = .string(reason) }
        return input
    }

    public func reviewGlamOutput(_ review: GlamOutputReview) async throws {
        _ = try await connection.request(Self.review, variables: ["input": .object(Self.reviewInput(review))])
    }

    public func userSafetyContext(cursor: String) async throws -> JSONValue? {
        try await connection.mcpTool("user_safety_context", arguments: ["about_message": .string(cursor)])
    }

    public func roomInfo(cursor: String, days: Int) async throws -> JSONValue? {
        // The MCP server's room_info first (api doc/MCP.md, "Worker devices"); a token from before the worker scopes,
        // or an API from before the tool, refuses it, and the cable's query answers instead.
        if let found = try? await connection.mcpTool("room_info", arguments: ["about_message": .string(cursor),
                                                                              "days": .number(Double(days))],
                                                     worker: .glam) {
            return found == .null ? nil : found
        }
        // An API from before `days` refuses the argument, so it only goes when asked for.
        var variables: [String: GraphQLValue] = ["cursor": .string(cursor)]
        if days > 0 { variables["days"] = .int(days) }
        let data = try await connection.request(Self.room, variables: variables)
        let room = data["chat"]?["moderation"]?["room"]
        return room == .null ? nil : room
    }
}

// MARK: - Settings from the admin console

/// What the audience's admins set for Arbiter in the admin console (Plugins → Moderation), on this Mac's token:
/// Query.chat.moderation.settings (api doc/CHAT_MODERATION.md, "Arbiter's settings"). Only what someone set comes back.
public struct CableEngineSettings: Sendable {
    static let query = "query ArbiterSettings { chat { moderation { settings } } }"

    let connection: ArbiterServiceConnection

    public init(connection: ArbiterServiceConnection) { self.connection = connection }

    /// The audience's settings, or nil when the API has none for this Mac's provider (or is from before them).
    public func fetch() async throws -> ServerEngineSettings? {
        let data = try await connection.request(Self.query)
        guard let settings = data["chat"]?["moderation"]?["settings"], settings != .null else { return nil }
        return try ArbiterDates.decode(ServerEngineSettings.self, from: settings)
    }
}

// MARK: - Prompts from the API

/// The prompts the API serves for the audience (MCP `prompts/list` and `prompts/get`, api doc/MCP.md, "Prompts"), on
/// this Mac's token. Each template is fetched with every argument set to its own `{{name}}`, so the server fills only
/// its own variables (the host's name, the app's) and the engine fills the rest per call (`ArbiterPrompt.render`).
public struct MCPPrompts: Sendable {
    let connection: ArbiterServiceConnection

    public init(connection: ArbiterServiceConnection) { self.connection = connection }

    /// Every prompt the API has; an empty set from an API from before templates, so the engine's own text holds.
    public func fetch(updatedAt: String? = nil) async throws -> ArbiterPromptSet {
        let listed = try await connection.mcp("prompts/list")
        guard case .array(let entries)? = listed["prompts"] else { return ArbiterPromptSet(updatedAt: updatedAt) }
        var prompts: [String: ArbiterPrompt] = [:]
        for entry in entries {
            guard let name = entry["name"]?.string else { continue }
            var placeholders: [String: JSONValue] = [:]
            if case .array(let arguments)? = entry["arguments"] {
                for argument in arguments {
                    if let key = argument["name"]?.string { placeholders[key] = .string("{{\(key)}}") }
                }
            }
            let got = try await connection.mcp("prompts/get", params: .object(["name": .string(name),
                                                                               "arguments": .object(placeholders)]))
            guard case .array(let messages)? = got["messages"], let text = messages.first?["content"]?["text"]?.string
            else { continue }
            let meta = got["_meta"]
            prompts[name] = ArbiterPrompt(name: name, text: text, version: meta?["version"]?.string ?? "",
                                          digest: meta?["digest"]?.string ?? "")
        }
        return ArbiterPromptSet(prompts: prompts, updatedAt: updatedAt)
    }
}

// MARK: - Research tools

/// What research may call (ArbiterModels' `ResearchToolbox`): the API's MCP tools on this Mac's token (the listings,
/// the suggestions, Google Places, as the token's scopes allow) and this Mac's own web tools (`WebTools` on `browser`,
/// Chrome on the Mac). An API, or a token, from before the worker tools leaves only the web tools.
public struct MCPResearchToolbox: ResearchToolbox {
    let connection: ArbiterServiceConnection
    let browser: any WebBrowsing

    public init(connection: ArbiterServiceConnection, browser: any WebBrowsing) {
        self.connection = connection; self.browser = browser
    }

    public func tools() async throws -> [JSONValue] {
        var tools: [JSONValue] = []
        if let listed = try? await connection.mcp("tools/list", worker: .research), case .array(let server)? = listed["tools"] {
            tools = server.filter { tool in !WebTools.names.contains(tool["name"]?.string ?? "") }
        }
        return tools + WebTools.definitions
    }

    public func call(_ name: String, arguments: JSONValue) async -> JSONValue {
        if WebTools.names.contains(name) { return await WebTools.call(name, arguments: arguments, browser: browser) }
        do {
            return try await connection.mcp("tools/call", params: .object(["name": .string(name), "arguments": arguments]),
                                            worker: .research)
        } catch {
            return .object(["content": .array([.object(["type": .string("text"), "text": .string(error.localizedDescription)])]),
                            "isError": .bool(true)])
        }
    }
}

// MARK: - Uploading decisions

/// Each of Glam's decisions, kept on the API on this Mac's token (chat.moderation.recordDecision), so the iPad can open
/// it in the field to diagnose: the whole proposal, with what it read and checked. Sending it again as it changes
/// (approved, carried out, labelled) replaces it, by its id.
public struct CableDecisionUploads: Sendable {
    static let document = """
        mutation ArbiterRecordDecision($trace: JSON!) { chat { moderation { recordDecision(input: {trace: $trace}) { decision { id } } } } }
        """

    let connection: ArbiterServiceConnection

    public init(connection: ArbiterServiceConnection) { self.connection = connection }

    /// The proposal as it's kept on this Mac (glam/proposals.jsonl), as a JSON variable.
    static func trace(_ proposal: GlamProposal) throws -> GraphQLValue {
        GraphQLValue(try ArbiterJSON.decoder.decode(JSONValue.self, from: ArbiterJSON.encoder.encode(proposal)))
    }

    public func upload(_ proposal: GlamProposal) async throws {
        _ = try await connection.request(Self.document, variables: ["trace": try Self.trace(proposal)])
    }
}

// MARK: - Making a token

/// This Mac's worker token: minted from the signed-in admin's session (Mutation.issueWorkerToken on staffql; they must
/// administer the audience), with the queue's scopes and, with `chatFeed`, the chat feed's, so Glam follows the chat
/// on the same token. Returns the secret, which only goes to the keychain.
public enum WorkerTokens {
    static let document = "mutation ArbiterIssueWorkerToken($input: WorkerTokenIssueInput!) { issueWorkerToken(input: $input) { id scopes secret } }"

    /// With `deviceId` (this computer's stable id, `WorkerDevice.id`), an audience that already has a token for this
    /// computer gives that one back with a new secret instead of a second token.
    public static func issue(session: AudienceManagementSession, name: String, chatFeed: Bool,
                             deviceId: String? = nil) async throws -> String {
        struct Response: Decodable { struct Token: Decodable { let secret: String }; let issueWorkerToken: Token }
        // chatFeed only goes when asked for, so an API from before it still mints a queue-only token.
        var input: [String: GraphQLValue] = ["name": .string(name)]
        if chatFeed { input["chatFeed"] = .bool(true) }
        guard let deviceId else {
            return try await session.graphQL(document, variables: ["input": .object(input)], as: Response.self)
                .issueWorkerToken.secret
        }
        var withDevice = input
        withDevice["deviceId"] = .string(deviceId)
        do {
            return try await session.graphQL(document, variables: ["input": .object(withDevice)], as: Response.self)
                .issueWorkerToken.secret
        } catch let error where unknownDeviceID(error) {
            // An API from before deviceId refuses the argument: mint a token the old way.
            return try await session.graphQL(document, variables: ["input": .object(input)], as: Response.self)
                .issueWorkerToken.secret
        }
    }

    /// Only the schema error an API from before deviceId gives for it ("Variable $input of type WorkerTokenIssueInput!
    /// was provided invalid value for deviceId (Field is not defined on WorkerTokenIssueInput)"), never any other
    /// failure, which must not quietly mint a second token without the device id.
    static func unknownDeviceID(_ error: Error) -> Bool {
        let text = "\(error) \(error.localizedDescription)"
        return text.contains("invalid value for deviceId") && text.contains("Field is not defined")
    }
}

#if canImport(Security)
import Security

/// Where this Mac keeps its worker token's secret: one generic password in its own keychain. With `dataProtection`,
/// in the data protection keychain, which goes by team and bundle ID, so a rebuild with another signature still reads
/// it; the file keychain opens an item only for the signature that saved it.
public struct WorkerTokenStore: Sendable {
    public let service: String
    public let account: String
    public let dataProtection: Bool

    public init(service: String, account: String = "worker-token", dataProtection: Bool = false) {
        self.service = service; self.account = account; self.dataProtection = dataProtection
    }

    private var query: [String: Any] {
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account]
        if dataProtection { query[kSecUseDataProtectionKeychain as String] = true }
        return query
    }

    public func load() -> String? {
        var item: CFTypeRef?
        var query = self.query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func save(_ secret: String) throws {
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = Data(secret.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw ArbiterServiceError("The keychain refused the token (\(status)).") }
    }

    public func delete() { SecItemDelete(query as CFDictionary) }
}
#endif
