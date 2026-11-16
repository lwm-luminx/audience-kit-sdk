import AudienceCore
import Foundation

/// A Ping's or Quickie pairing's chat (the API's `PrivateChat`): a short-lived chat for a ping's circle, or a Quickie
/// pair once both accepted. What's said is kept only until it closes, then deleted; nothing is stored on the phone
/// either. Read it from `Ping.chat` or `PairUpMatch.chat` (include ``PrivateChat/graphQLFields`` in the app's query),
/// or with ``AudienceSession/pingChat(pingID:)``.
public struct PrivateChat: Decodable, Sendable, Hashable, Identifiable {
    /// `ping-<ping id>` or `quickie-<match id>`.
    public let id: String
    /// When it closes at the latest. Ending the ping or the pairing closes it sooner.
    public let closesAt: Date
    /// Its newest lines, oldest first.
    public let messages: [PrivateChatMessage]

    public init(id: String, closesAt: Date, messages: [PrivateChatMessage] = []) {
        self.id = id
        self.closesAt = closesAt
        self.messages = messages
    }

    public var isPing: Bool { id.hasPrefix("ping-") }
    public var isQuickie: Bool { id.hasPrefix("quickie-") }

    /// Lenient: a line that doesn't decode is left out rather than losing the chat.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        closesAt = try container.decode(Date.self, forKey: .closesAt)
        messages = (try container.decodeIfPresent([Lenient<PrivateChatMessage>].self, forKey: .messages) ?? [])
            .compactMap(\.value)
    }

    private enum CodingKeys: String, CodingKey { case id, closesAt, messages }
}

/// A line in a ``PrivateChat``. Its `id` also names its chat: report it with ``ReportTarget/privateMessage``.
public struct PrivateChatMessage: Decodable, Sendable, Hashable, Identifiable {
    public struct Sender: Decodable, Sendable, Hashable {
        /// Their user id, to block or report them.
        public let id: String
        /// In full for friends, first name and last initial for anyone else.
        public let name: String

        public init(id: String, name: String) {
            self.id = id
            self.name = name
        }
    }

    public let id: String
    public let chatId: String
    public let body: String
    public let isMine: Bool
    /// Nil when they've deleted their account.
    public let sender: Sender?
    public let sentAt: Date

    public init(id: String, chatId: String, body: String, isMine: Bool, sender: Sender?, sentAt: Date) {
        self.id = id
        self.chatId = chatId
        self.body = body
        self.isMine = isMine
        self.sender = sender
        self.sentAt = sentAt
    }
}

/// What ``AudienceCable/privateChats(audienceID:)`` sends: a new line in one of the person's chats, or a chat closing.
public enum PrivateChatEvent: Sendable, Hashable {
    case message(PrivateChatMessage)
    /// What was said in it is gone, and nothing more can be sent.
    case closed(chatID: String)
}

/// The progress of ``AudienceCable/privateChats(audienceID:)``.
public enum PrivateChatUpdate: Sendable {
    /// Running: lines arrive from now on. Sent again after every reconnect, so refetch the open chat then.
    case subscribed
    case event(PrivateChatEvent)
    case refused([GraphQLError])
    case disconnected(reason: String?, reconnects: Bool)
}

/// The words around Ping and Quickie chats, shared with Android.
public enum PrivateChatCopy {
    public static let placeholder = "Say something"
    public static let pingTitle = "Chat with your circle"
    public static let quickieTitle = "Chat to find each other"
    public static let ephemeral = "Messages disappear when the chat ends."
    public static let closed = "This chat has ended."
}

extension PrivateChat {
    /// Its fields, to put in an app's own ping or Quickie query: `chat { \(PrivateChat.graphQLFields) }`.
    public static let graphQLFields = "id closesAt messages { \(PrivateChatMessage.graphQLFields) }"
}

extension PrivateChatMessage {
    public static let graphQLFields = "id chatId body isMine sentAt sender { id name }"
}

extension Queries {
    static let privateChatFields = PrivateChat.graphQLFields
    static let privateChatMessageFields = PrivateChatMessage.graphQLFields

    static let pingChat = """
        query PingChat($id: ID!) {
          node(id: $id) { ... on Ping { id chat { \(privateChatFields) } } }
        }
        """

    static let sendPrivateChatMessage = """
        mutation SendPrivateChatMessage($chatId: ID!, $body: String!) {
          sendPrivateChatMessage(input: { chatId: $chatId, body: $body }) { message { \(privateChatMessageFields) } }
        }
        """

    static let privateChatSubscription = """
        subscription PrivateChat {
          privateChat { chatId closed message { \(privateChatMessageFields) } }
        }
        """
}

extension AudienceSession {
    /// A ping's chat, when the signed-in person is in its circle and someone has joined; nil otherwise.
    public func pingChat(pingID: String) async throws -> PrivateChat? {
        struct Response: Decodable, Sendable {
            struct Node: Decodable, Sendable { var chat: PrivateChat? }
            var node: Node?
        }
        return try await graphQL(Queries.pingChat, variables: ["id": .string(pingID)], operationName: "PingChat",
                                 as: Response.self).node?.chat
    }

    /// Says something in a Ping or Quickie chat. Throws when the chat has ended, the word list refuses it, or the
    /// person is sending too fast.
    @discardableResult
    public func sendPrivateChatMessage(_ body: String, chatID: String) async throws -> PrivateChatMessage {
        struct Response: Decodable, Sendable {
            struct Payload: Decodable, Sendable { var message: PrivateChatMessage }
            var sendPrivateChatMessage: Payload
        }
        return try await graphQL(Queries.sendPrivateChatMessage,
                                 variables: ["chatId": .string(chatID), "body": .string(body)],
                                 operationName: "SendPrivateChatMessage", as: Response.self)
            .sendPrivateChatMessage.message
    }
}

extension AudienceCable {
    /// Every Ping and Quickie chat the signed-in person is in: new lines and chats closing, while the app is open.
    public func privateChats(audienceID: String) -> AsyncStream<PrivateChatUpdate> {
        let events = subscribe(query: Queries.privateChatSubscription, operationName: "PrivateChat",
                               audienceID: audienceID)
        return AsyncStream { continuation in
            let task = Task {
                for await event in events {
                    switch event {
                    case .subscribed:
                        continuation.yield(.subscribed)
                    case let .result(data):
                        switch PrivateChatEvent.decode(result: data) {
                        case let .success(event)?: continuation.yield(.event(event))
                        case let .failure(errors)?:
                            continuation.yield(.refused(errors))
                            continuation.finish()
                            return
                        case nil: break
                        }
                    case .rejected:
                        continuation.yield(.refused([]))
                        continuation.finish()
                        return
                    case let .disconnected(reason, reconnects):
                        continuation.yield(.disconnected(reason: reason, reconnects: reconnects))
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

extension PrivateChatEvent {
    enum Decoded {
        case success(PrivateChatEvent)
        case failure([GraphQLError])
    }

    /// One subscription result: the event, the server's refusal, or nil for the empty first result.
    static func decode(result data: Data) -> Decoded? {
        struct Wire: Decodable {
            var chatId: String
            var closed: Bool
            var message: PrivateChatMessage?
        }
        struct Envelope: Decodable {
            struct Payload: Decodable { var privateChat: Wire? }
            var data: Payload?
            var errors: [GraphQLError]?
        }
        guard let envelope = try? JSONDecoder.audienceKit.decode(Envelope.self, from: data) else { return nil }
        if let wire = envelope.data?.privateChat {
            if let message = wire.message, !wire.closed { return .success(.message(message)) }
            return .success(.closed(chatID: wire.chatId))
        }
        if let errors = envelope.errors, !errors.isEmpty { return .failure(errors) }
        return nil
    }
}
