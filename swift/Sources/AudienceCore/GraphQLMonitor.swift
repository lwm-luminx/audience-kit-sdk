import Foundation

/// An app's monitoring (New Relic, say), told about every GraphQL operation the SDK runs and about the cable's socket.
/// Hand one to ``AudienceSession/init(configuration:credentialStore:session:monitor:)``; the session's cables
/// (``AudienceSession/makeCable(endpoint:url:session:silenceLimit:)``) report to it too.
///
/// HTTP operations also carry `X-APOLLO-OPERATION-NAME` and `X-APOLLO-OPERATION-TYPE`, which New Relic's mobile agents
/// record with each network request, so those show up by operation even without a monitor. Operations over the cable
/// share one WebSocket the agents can't see into: this is their only record. Calls come from the SDK's own tasks and
/// should return quickly.
public protocol GraphQLMonitor: Sendable {
    func record(_ event: GraphQLOperationEvent)
    func record(_ event: CableSocketEvent)
}

extension GraphQLMonitor {
    public func record(_ event: CableSocketEvent) {}
}

/// Something that happened to one GraphQL operation.
public struct GraphQLOperationEvent: Sendable, Hashable {
    public enum Transport: String, Sendable, Hashable {
        /// A request to the audience's `graphql` or `staffql` endpoint.
        case http
        /// An operation on the cable (``AudienceCable``), one of many sharing its socket.
        case cable
    }

    public enum Kind: String, Sendable, Hashable {
        /// An HTTP operation was answered, or failed (``GraphQLOperationEvent/error``).
        case completed
        /// A cable operation's channel was confirmed and the operation went out: after it opens, and again after every
        /// reconnect.
        case subscribed
        /// A result for a cable operation: its first (``GraphQLOperationEvent/duration`` is from going out to the
        /// result), then each subscription update after it.
        case result
        /// A cable operation ended: the server finished it, or the app stopped following it.
        case ended
        /// The server turned a cable operation's channel away.
        case rejected
    }

    public var kind: Kind
    /// The operation's name: the one passed with it, or the one its document gives (`subscription VenueChat { … }`).
    public var name: String?
    /// `query`, `mutation` or `subscription`.
    public var type: String
    public var transport: Transport
    public var endpoint: GraphQLEndpoint
    /// How long it took: an HTTP operation's request, or a cable operation's first result.
    public var duration: Duration?
    /// What went wrong, for a failed HTTP operation or a result carrying GraphQL errors.
    public var error: String?

    public init(kind: Kind, name: String?, type: String, transport: Transport, endpoint: GraphQLEndpoint,
                duration: Duration? = nil, error: String? = nil) {
        self.kind = kind
        self.name = name
        self.type = type
        self.transport = transport
        self.endpoint = endpoint
        self.duration = duration
        self.error = error
    }

    /// The operation's type and name, from its document: the first `query`, `mutation` or `subscription` and the name
    /// after it. A document that opens with `{` is an anonymous query. `operationName`, when given, wins.
    public static func describe(query: String, operationName: String? = nil) -> (type: String, name: String?) {
        let pattern = #"(?:^|[\s}])(query|mutation|subscription)\b\s*([_A-Za-z][_0-9A-Za-z]*)?"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: query, range: NSRange(query.startIndex..., in: query)),
              let typeRange = Range(match.range(at: 1), in: query)
        else {
            return ("query", operationName)
        }
        let name = Range(match.range(at: 2), in: query).map { String(query[$0]) }
        return (String(query[typeRange]), operationName ?? name)
    }
}

/// Something that happened to a cable's socket.
public struct CableSocketEvent: Sendable, Hashable {
    public enum Kind: String, Sendable, Hashable {
        /// The server welcomed the socket.
        case connected
        /// The socket dropped, went quiet or was closed by the server; ``CableSocketEvent/reconnects`` says whether the
        /// cable tries again.
        case disconnected
    }

    public var kind: Kind
    public var endpoint: GraphQLEndpoint
    /// How many operations the socket carries.
    public var operations: Int
    /// Why it went, when it did.
    public var reason: String?
    public var reconnects: Bool?

    public init(kind: Kind, endpoint: GraphQLEndpoint, operations: Int, reason: String? = nil,
                reconnects: Bool? = nil) {
        self.kind = kind
        self.endpoint = endpoint
        self.operations = operations
        self.reason = reason
        self.reconnects = reconnects
    }
}
