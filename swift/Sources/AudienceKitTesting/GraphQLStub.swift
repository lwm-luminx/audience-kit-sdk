import AudienceCore
import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A stand-in for an audience's GraphQL API, for an app's unit tests: it answers each request from a closure, records
/// what was asked, and hands out an ``AudienceSession`` signed in as a member that talks only to it.
///
/// ``withinComplexityBudget(_:perItem:pageArgument:overhead:otherwise:)`` refuses a page the way the API does when it's
/// over a member's complexity budget, so a test catches a page size the server would turn away. (The DNC demo app
/// asked for 25 events per locale, about 1,900 against a budget of 1,000, and every events screen came up empty.)
///
/// ```swift
/// let api = GraphQLStub(respond: GraphQLStub.withinComplexityBudget(perItem: 77) { request in
///     .data(#"{"events":{"list":{"nodes":[]}}}"#)
/// })
/// _ = try await MyService(client: api.client).events()
/// #expect(api.requests.count == 1)
/// ```
public final class GraphQLStub: @unchecked Sendable {
    /// One request as the stub saw it.
    public struct Request: @unchecked Sendable {
        public let operationName: String?
        public let query: String
        public let variables: [String: Any]
        public let headers: [String: String]

        public init(operationName: String? = nil, query: String = "", variables: [String: Any] = [:],
                    headers: [String: String] = [:]) {
            self.operationName = operationName
            self.query = query
            self.variables = variables
            self.headers = headers
        }

        /// A variable as an integer (JSON numbers arrive as `Int` or `Double`).
        public func int(_ name: String) -> Int? {
            switch variables[name] {
            case let value as Int: value
            case let value as Double: Int(value)
            case let value as NSNumber: value.intValue
            default: nil
            }
        }

        public func string(_ name: String) -> String? { variables[name] as? String }
    }

    /// What the stub answers.
    public enum Reply: Sendable {
        /// `{"data": <json>}`, with `json` the data object's JSON text.
        case data(String)
        /// `{"errors": [{"message": …}, …]}`, status 200, as the API reports a refused or failed operation.
        case errors([String])
        /// Any status and body.
        case raw(status: Int, body: String)
        /// The request fails before a response.
        case failure(URLError)

        public static func error(_ message: String) -> Reply { .errors([message]) }
    }

    public static let domain = "graphql-stub.test"
    private static let lock = NSLock()
    /// Weak, so a stub goes away with its test (a session that outlives it gets `unsupportedURL`).
    private struct Weak { weak var stub: GraphQLStub? }
    nonisolated(unsafe) private static var stubs: [String: Weak] = [:]

    public let audienceID: String
    public let id = UUID().uuidString.lowercased()
    private let lock = NSLock()
    private let respond: @Sendable (Request) -> Reply
    private var recorded: [Request] = []

    public init(audienceID: String = "00000000-0000-0000-0000-000000000001",
                respond: @escaping @Sendable (Request) -> Reply) {
        self.audienceID = audienceID
        self.respond = respond
        Self.lock.withLock { Self.stubs[id] = Weak(stub: self) }
    }

    deinit {
        let id = id
        Self.lock.withLock { _ = Self.stubs.removeValue(forKey: id) }
    }

    /// Every request so far, oldest first.
    public var requests: [Request] { lock.withLock { recorded } }

    /// The base URL that reaches this stub (each stub has its own host, so tests can run side by side).
    public var baseURL: URL { URL(string: "https://\(id).\(Self.domain)")! }

    /// A URL session whose requests to ``baseURL`` the stub answers.
    public var urlSession: URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GraphQLStubProtocol.self]
        return URLSession(configuration: configuration)
    }

    /// A session signed in as a member of ``audienceID``, talking to the stub.
    public func client(monitor: (any GraphQLMonitor)? = nil, role: String = "member") -> AudienceSession {
        let endpoint = URL(string: GraphQLEndpoint.consumer.path(audienceID: audienceID), relativeTo: baseURL)!.absoluteURL
        let store = InMemoryCredentialStore(credential: Credential(token: "test", userId: "u-test", audienceId: audienceID,
                                                                   role: role, endpoint: endpoint))
        return AudienceSession(configuration: AudienceKitConfiguration(baseURL: baseURL, audienceID: audienceID),
                               credentialStore: store, session: urlSession, monitor: monitor, deviceAttestor: nil)
    }

    /// A session signed in as a member, talking to the stub.
    public var client: AudienceSession { client() }

    /// Answers like the API's complexity check: a request whose page (`pageArgument`, `first` by default) times
    /// `perItem`, plus `overhead`, is over `budget` gets the API's error; anything else goes to `otherwise`.
    /// A member's budget is 1000; an event in a list costs about 75 to 77.
    public static func withinComplexityBudget(
        _ budget: Int = 1_000,
        perItem: Int,
        pageArgument: String = "first",
        overhead: Int = 3,
        otherwise: @escaping @Sendable (Request) -> Reply
    ) -> @Sendable (Request) -> Reply {
        { request in
            if let page = request.int(pageArgument), page * perItem + overhead > budget {
                return .error("Query has complexity of \(page * perItem + overhead), which exceeds max complexity of \(budget)")
            }
            return otherwise(request)
        }
    }

    static func find(_ id: String) -> GraphQLStub? {
        lock.withLock { stubs[id]?.stub }
    }

    func answer(_ request: Request) -> Reply {
        lock.withLock { recorded.append(request) }
        return respond(request)
    }
}

/// Routes requests for ``GraphQLStub/domain`` hosts to their stub.
final class GraphQLStubProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host?.hasSuffix(".\(GraphQLStub.domain)") == true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let id = request.url?.host?.replacingOccurrences(of: ".\(GraphQLStub.domain)", with: "") ?? ""
        guard let url = request.url, let stub = GraphQLStub.find(id) else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        let body = request.httpBody ?? request.httpBodyStream.map(Self.read) ?? Data()
        let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
        let parsed = GraphQLStub.Request(operationName: json["operationName"] as? String,
                                         query: json["query"] as? String ?? "",
                                         variables: json["variables"] as? [String: Any] ?? [:],
                                         headers: request.allHTTPHeaderFields ?? [:])
        let status: Int
        let text: String
        switch stub.answer(parsed) {
        case let .data(data): (status, text) = (200, #"{"data":\#(data)}"#)
        case let .errors(messages):
            let encoded = messages.map { message -> String in
                let data = try? JSONSerialization.data(withJSONObject: ["message": message])
                return data.flatMap { String(data: $0, encoding: .utf8) } ?? #"{"message":"error"}"#
            }
            (status, text) = (200, #"{"errors":[\#(encoded.joined(separator: ","))]}"#)
        case let .raw(code, raw): (status, text) = (code, raw)
        case let .failure(error):
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(text.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func read(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
