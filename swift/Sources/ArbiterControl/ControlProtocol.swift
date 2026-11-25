import Foundation

/// What `arbiterctl` and a running Mac Arbiter say to each other over the control socket (`ControlSocket`): one JSON
/// request on a line, one JSON response, then the connection closes. Foundation only, so the CLI links nothing else
/// and the Linux build (CI) compiles and tests it.
///
/// Every field past the first version is optional, so an older `arbiterctl` and a newer Arbiter (or the other way
/// round) still understand each other; `ControlResponse.protocolVersion` says which one the app speaks.
public enum ArbiterControl {
    /// Bumped when a request or response changes in a way an older peer would misread.
    public static let protocolVersion = 1
    /// The Mac app's one bundle ID (every build, Production and Debug).
    public static let bundleID = "com.audiencekit.Arbiter"
    /// The socket's file name, in the app's sandbox container (its home) or, unsandboxed, its Application Support.
    public static let socketName = "arbiterctl.sock"
    /// Overrides where `arbiterctl` looks for the socket (and where the app makes it, for tests and odd setups).
    public static let socketEnvironmentKey = "ARBITER_SOCKET"

    /// Where the running app makes its socket. Sandboxed, its home is the container's Data folder
    /// (~/Library/Containers/com.audiencekit.Arbiter/Data), which is short enough for a socket path (104 bytes on
    /// macOS); unsandboxed (a `swift run` or test host), it's Application Support/Arbiter.
    public static func serverSocketPath(environment: [String: String] = ProcessInfo.processInfo.environment,
                                        home: String = NSHomeDirectory()) -> String {
        if let explicit = environment[socketEnvironmentKey], !explicit.isEmpty { return explicit }
        if environment["APP_SANDBOX_CONTAINER_ID"] != nil { return (home as NSString).appendingPathComponent(socketName) }
        return (home as NSString).appendingPathComponent("Library/Application Support/Arbiter/\(socketName)")
    }

    /// Where `arbiterctl` (never sandboxed) looks, in order: `$ARBITER_SOCKET`, the sandboxed app's container, then an
    /// unsandboxed app's Application Support.
    public static func clientSocketPaths(environment: [String: String] = ProcessInfo.processInfo.environment,
                                         home: String = NSHomeDirectory()) -> [String] {
        if let explicit = environment[socketEnvironmentKey], !explicit.isEmpty { return [explicit] }
        let base = home as NSString
        return [
            base.appendingPathComponent("Library/Containers/\(bundleID)/Data/\(socketName)"),
            base.appendingPathComponent("Library/Application Support/Arbiter/\(socketName)"),
        ]
    }
}

/// What a request asks the app to do.
public enum ControlCommand: String, Codable, Sendable, CaseIterable {
    /// Answers with nothing but the protocol version: is an Arbiter listening?
    case ping
    /// The whole picture: the build and its server, sign-in, the engine, every audience's worker and Glam.
    case status
    /// Start or stop workers: `audience` names one, else every audience.
    case workerStart = "worker.start"
    case workerStop = "worker.stop"
    /// Start or stop Glam the same way.
    case glamStart = "glam.start"
    case glamStop = "glam.stop"
    /// Read (no `value`) or set (`value`: shadow, approve, live) the Mac's Glam mode.
    case glamMode = "glam.mode"
    /// Every audience's worker and Glam together.
    case engineStart = "engine.start"
    case engineStop = "engine.stop"
    /// Read (no `value`) or set (`value`: on, off) Settings → Audiences → Review only.
    case reviewOnly = "review-only"
    /// Look through the model folders again.
    case modelsRescan = "models.rescan"
    /// Vectors for `input` from the embedding model (`value` names another: a slug on Garage's list or a file),
    /// cut to `dimensions` when given.
    case embed
    /// One moderation test vector (`system` and `user`, from the API's moderation:vectors:export) judged by the
    /// decisions model, or the model `value` names; the answer comes back as `judgment` (VectorJudge.Row).
    case judge
    /// Read (no `value`) or pick (`value`: next, production) the API server for the next launch.
    case server
    /// Glam's log and the workers' decisions, newer than `since` when given.
    case logs
    /// Signs in with `token`: a session the API issued, as its bare JWT or a sign-in's whole JSON answer.
    case signIn = "sign-in"
    /// Signs this Mac out of AudienceKit (signing in again needs the window: Apple's sign-in has a sheet).
    case signOut = "sign-out"
    /// Puts the main window in front, when one exists; says whether it did.
    case showWindow = "window.show"
    /// Quits Arbiter the way its menu does, stopping the engine and freeing the models first.
    case quit
}

public struct ControlRequest: Codable, Sendable, Hashable {
    public var command: ControlCommand
    /// The audience a worker or Glam command is for (its name, a prefix of it, or its id); nil for all of them.
    public var audience: String?
    /// The new value for a setting command (glam.mode, review-only, server).
    public var value: String?
    /// For logs: only lines at or after this time (seconds since 1970).
    public var since: Double?
    /// For logs: at most this many lines (the newest).
    public var limit: Int?
    /// For sign-in: the token (never logged, never echoed back).
    public var token: String?
    /// For embed: the texts, one vector each.
    public var input: [String]?
    /// For embed: keep this many leading values of each vector (Matryoshka), normalised again.
    public var dimensions: Int?
    /// For judge: the vector's id (echoed in the answer), and its system and user prompts.
    public var id: String?
    public var system: String?
    public var user: String?

    public init(_ command: ControlCommand, audience: String? = nil, value: String? = nil, since: Double? = nil,
                limit: Int? = nil, token: String? = nil, input: [String]? = nil, dimensions: Int? = nil,
                id: String? = nil, system: String? = nil, user: String? = nil) {
        self.command = command; self.audience = audience; self.value = value; self.since = since; self.limit = limit
        self.token = token; self.input = input; self.dimensions = dimensions
        self.id = id; self.system = system; self.user = user
    }
}

public struct ControlResponse: Codable, Sendable, Hashable {
    public var ok: Bool
    public var protocolVersion: Int
    /// What happened, for a person to read (or why it failed).
    public var message: String?
    public var status: ControlStatus?
    public var logs: [ControlLogLine]?
    /// For embed: one L2-normalised vector per input, in order.
    public var embeddings: [[Float]]?
    /// For judge: the answer, in the moderation harness's run format.
    public var judgment: VectorJudge.Row?

    public init(ok: Bool, message: String? = nil, status: ControlStatus? = nil, logs: [ControlLogLine]? = nil,
                embeddings: [[Float]]? = nil, judgment: VectorJudge.Row? = nil) {
        self.ok = ok; self.protocolVersion = ArbiterControl.protocolVersion; self.message = message
        self.status = status; self.logs = logs; self.embeddings = embeddings; self.judgment = judgment
    }

    public static func failure(_ message: String) -> ControlResponse { ControlResponse(ok: false, message: message) }
    public static func success(_ message: String? = nil, status: ControlStatus? = nil) -> ControlResponse {
        ControlResponse(ok: true, message: message, status: status)
    }
}

/// Everything `arbiterctl status` shows.
public struct ControlStatus: Codable, Sendable, Hashable {
    public struct App: Codable, Sendable, Hashable {
        public var bundleID: String
        public var version: String
        public var build: String
        public var debug: Bool
        public var pid: Int32
        public init(bundleID: String, version: String, build: String, debug: Bool, pid: Int32) {
            self.bundleID = bundleID; self.version = version; self.build = build; self.debug = debug; self.pid = pid
        }
    }

    public struct Server: Codable, Sendable, Hashable {
        /// The server this launch runs on: next or production.
        public var current: String
        public var apiURL: String
        /// Whether this install may switch servers (a beta, or a super admin's install, and not a Debug build).
        public var switchable: Bool
        /// The server picked for the next launch, when it differs from `current`.
        public var pending: String?
        public init(current: String, apiURL: String, switchable: Bool, pending: String? = nil) {
            self.current = current; self.apiURL = apiURL; self.switchable = switchable; self.pending = pending
        }
    }

    public struct Account: Codable, Sendable, Hashable {
        public var signedIn: Bool
        /// The audiences the sign-in may open, and those open in the window.
        public var audiences: [String]
        public var opened: [String]
        public var updateRequired: Bool
        public var error: String?
        public init(signedIn: Bool, audiences: [String], opened: [String], updateRequired: Bool, error: String? = nil) {
            self.signedIn = signedIn; self.audiences = audiences; self.opened = opened
            self.updateRequired = updateRequired; self.error = error
        }
    }

    public struct Engine: Codable, Sendable, Hashable {
        public var reviewOnly: Bool
        /// Launched with -ArbiterReviewOnly, so `review-only off` can't turn it off.
        public var reviewOnlyForced: Bool
        public var glamMode: String
        public var modelPath: String?
        public var guardModelPath: String?
        /// The embedding model picked (one of Garage's list when found).
        public var embeddingModelPath: String?
        public var modelFolders: [String]
        /// Every model found in the folders.
        public var models: [String]
        /// Models downloading or failed, by file name: "41%" or the error.
        public var downloads: [String: String]
        public var autoStartWorker: Bool
        public var autoStartGlam: Bool
        public var error: String?
        public init(reviewOnly: Bool, reviewOnlyForced: Bool, glamMode: String, modelPath: String?, guardModelPath: String?,
                    modelFolders: [String], models: [String], downloads: [String: String], autoStartWorker: Bool,
                    autoStartGlam: Bool, error: String?, embeddingModelPath: String? = nil) {
            self.embeddingModelPath = embeddingModelPath
            self.reviewOnly = reviewOnly; self.reviewOnlyForced = reviewOnlyForced; self.glamMode = glamMode
            self.modelPath = modelPath; self.guardModelPath = guardModelPath; self.modelFolders = modelFolders
            self.models = models; self.downloads = downloads; self.autoStartWorker = autoStartWorker
            self.autoStartGlam = autoStartGlam; self.error = error
        }
    }

    public struct Background: Codable, Sendable, Hashable {
        public var keepsRunning: Bool
        public var menuBar: Bool
        public var opensAtLogin: Bool
        public var keepsMacAwake: Bool
        public init(keepsRunning: Bool, menuBar: Bool, opensAtLogin: Bool, keepsMacAwake: Bool) {
            self.keepsRunning = keepsRunning; self.menuBar = menuBar; self.opensAtLogin = opensAtLogin
            self.keepsMacAwake = keepsMacAwake
        }
    }

    public struct Audience: Codable, Sendable, Hashable {
        public struct Worker: Codable, Sendable, Hashable {
            public var running: Bool
            /// stopped, connecting, idle, working, error.
            public var state: String
            public var message: String?
            public var handled: Int
            /// The last decision, as "evaluation type → choice".
            public var last: String?
            public init(running: Bool, state: String, message: String? = nil, handled: Int = 0, last: String? = nil) {
                self.running = running; self.state = state; self.message = message; self.handled = handled; self.last = last
            }
        }
        public struct Glam: Codable, Sendable, Hashable {
            public var running: Bool
            /// stopped, connecting, watching, replaying, error.
            public var state: String
            public var message: String?
            public var backlog: Int
            public var handled: Int
            /// Proposals waiting for a person to approve.
            public var awaiting: Int
            public init(running: Bool, state: String, message: String? = nil, backlog: Int = 0, handled: Int = 0,
                        awaiting: Int = 0) {
                self.running = running; self.state = state; self.message = message; self.backlog = backlog
                self.handled = handled; self.awaiting = awaiting
            }
        }

        /// The link's own id (its storage name).
        public var id: String
        public var name: String
        public var audienceID: String?
        public var hostName: String
        /// The one the window shows.
        public var current: Bool
        public var worker: Worker
        public var glam: Glam
        public init(id: String, name: String, audienceID: String?, hostName: String, current: Bool, worker: Worker,
                    glam: Glam) {
            self.id = id; self.name = name; self.audienceID = audienceID; self.hostName = hostName
            self.current = current; self.worker = worker; self.glam = glam
        }
    }

    public var app: App
    public var server: Server
    public var account: Account
    public var engine: Engine
    public var background: Background?
    public var audiences: [Audience]

    public init(app: App, server: Server, account: Account, engine: Engine, background: Background?, audiences: [Audience]) {
        self.app = app; self.server = server; self.account = account; self.engine = engine
        self.background = background; self.audiences = audiences
    }
}

/// One line of `arbiterctl logs`: Glam's log or a worker's decision, for one audience.
public struct ControlLogLine: Codable, Sendable, Hashable {
    public enum Source: String, Codable, Sendable { case glam, worker }
    public var audience: String
    public var source: Source
    /// Unique per audience and source, so a follower can skip lines it has printed.
    public var key: String
    public var at: Double
    public var text: String
    public var isError: Bool

    public init(audience: String, source: Source, key: String, at: Double, text: String, isError: Bool = false) {
        self.audience = audience; self.source = source; self.key = key; self.at = at; self.text = text
        self.isError = isError
    }

    /// Lines at or after `since`, oldest first, at most `limit` of the newest.
    public static func select(_ lines: [ControlLogLine], since: Double?, limit: Int?) -> [ControlLogLine] {
        var picked = lines.filter { since == nil || $0.at >= since! }.sorted { $0.at < $1.at }
        if let limit, limit >= 0, picked.count > limit { picked = Array(picked.suffix(limit)) }
        return picked
    }
}

/// Finds the audience a command names among the app's: an exact id, audience id or name (ignoring case) first, then a
/// unique name prefix.
public enum ControlAudienceMatch {
    public enum Result<ID: Hashable>: Equatable { case found(ID), none, ambiguous([String]) }

    public static func find<ID: Hashable>(_ query: String, in candidates: [(id: ID, name: String, keys: [String])]) -> Result<ID> {
        let wanted = query.trimmingCharacters(in: .whitespaces).lowercased()
        if let exact = candidates.first(where: { candidate in
            candidate.name.lowercased() == wanted || candidate.keys.contains { $0.lowercased() == wanted }
        }) { return .found(exact.id) }
        let prefixed = candidates.filter { $0.name.lowercased().hasPrefix(wanted) }
        switch prefixed.count {
        case 1: return .found(prefixed[0].id)
        case 0: return .none
        default: return .ambiguous(prefixed.map(\.name))
        }
    }
}

/// A session token handed to `arbiterctl sign-in`, read into what a sign-in's answer says (the API's TokenResponse:
/// token, userId, audienceId, role, endpoint, expiresAt). Takes that JSON answer as it is, or a bare JWT, whose claims
/// carry the same: `sub`, `audience_id`, `audience_role` / `role`, `aud` (the endpoint) and `exp`. The signature isn't
/// checked here; the API checks it on the first request, and Arbiter signs out again when it's refused.
public struct ControlToken: Equatable, Sendable {
    public var token: String
    public var userID: String
    public var audienceID: String?
    public var role: String
    public var endpoint: URL
    public var expiresAt: Date?

    public init(token: String, userID: String, audienceID: String?, role: String, endpoint: URL, expiresAt: Date?) {
        self.token = token; self.userID = userID; self.audienceID = audienceID; self.role = role
        self.endpoint = endpoint; self.expiresAt = expiresAt
    }

    /// The roles a sign-in answers with; anything else in a JWT's `audience_role` falls back to its `role`.
    static let roles: Set<String> = ["member", "listing", "admin", "venue_device"]

    public static func parse(_ text: String) throws -> ControlToken {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ControlUsageError("The token is empty.") }
        if trimmed.hasPrefix("{") { return try parseResponse(trimmed) }
        let jwt = trimmed.hasPrefix("Bearer ") ? String(trimmed.dropFirst(7)) : trimmed
        return try parseJWT(jwt)
    }

    static func parseResponse(_ json: String) throws -> ControlToken {
        struct Response: Decodable {
            let token: String
            let userId: String?
            let audienceId: String?
            let role: String?
            let endpoint: String?
            let expiresAt: String?
        }
        guard let response = try? JSONDecoder().decode(Response.self, from: Data(json.utf8)) else {
            throw ControlUsageError("That JSON isn't a sign-in answer (it needs at least a token).")
        }
        // Whatever the answer leaves out, the JWT says.
        let claims = try parseJWT(response.token)
        return ControlToken(token: response.token, userID: response.userId ?? claims.userID,
                            audienceID: response.audienceId ?? claims.audienceID, role: response.role ?? claims.role,
                            endpoint: response.endpoint.flatMap(URL.init(string:)) ?? claims.endpoint,
                            expiresAt: response.expiresAt.flatMap { ISO8601DateFormatter().date(from: $0) } ?? claims.expiresAt)
    }

    static func parseJWT(_ jwt: String) throws -> ControlToken {
        let parts = jwt.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, let payload = base64URLDecode(String(parts[1])),
              let claims = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] else {
            throw ControlUsageError("That isn't a session token: expected a JWT (three dot-separated parts) or a sign-in's JSON.")
        }
        func string(_ key: String) -> String? {
            if let value = claims[key] as? String { return value }
            if let value = claims[key] as? NSNumber { return value.stringValue }
            return nil
        }
        guard let userID = string("sub") ?? string("id") else { throw ControlUsageError("The token names no user (no sub claim).") }
        guard let audience = string("aud"), let endpoint = URL(string: audience), endpoint.host != nil else {
            throw ControlUsageError("The token names no API endpoint (no aud claim); is it a service or worker token?")
        }
        let role: String
        if let audienceRole = string("audience_role"), roles.contains(audienceRole) { role = audienceRole }
        else { role = string("role") == "admin" ? "admin" : "member" }
        let expiresAt = (claims["exp"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
        if let expiresAt, expiresAt < Date() { throw ControlUsageError("That token expired at \(expiresAt).") }
        return ControlToken(token: jwt, userID: userID, audienceID: string("audience_id"), role: role, endpoint: endpoint,
                            expiresAt: expiresAt)
    }

    static func base64URLDecode(_ text: String) -> Data? {
        var base64 = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64.append("=") }
        return Data(base64Encoded: base64)
    }
}
