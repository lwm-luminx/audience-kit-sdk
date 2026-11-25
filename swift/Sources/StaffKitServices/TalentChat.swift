import Foundation
import AudienceCore
import StaffKitCore

/// Chat for talent: a person's listing posts, tagged HOST under the person's name and photo, in the rooms of the venues
/// they're featured at or host events at and the locales they're featured in, from anywhere (no location check). The
/// server decides which rooms (`Person.chat.rooms`) and checks every post.
extension TalentManagementClient {
    /// What a message carries in talent's reads: what the room shows, and which listing posted it.
    static let talentMessageFields = VenueManagementClient.messageFields + " postedAsPerson person { id }"

    /// The rooms the person can post in, the most recently active first.
    public func chatRooms(personID: String) async throws -> [AudienceChatRoom] {
        struct Response: Decodable, Sendable {
            struct Chat: Decodable, Sendable { let rooms: GraphQLNodes<AudienceChatRoom> }
            struct Person: Decodable, Sendable { let chat: Chat }
            struct People: Decodable, Sendable { let person: Person? }
            let people: People
        }
        return try await session.graphQL("""
            query BackstageChatRooms($id: ID!) {
              people {
                person(id: $id) {
                  chat {
                    rooms {
                      nodes {
                        id name lastMessage lastMessageAt lastMessageName recentCount onlineCount
                        venue { id photoUrl chatRetentionMinutes tickets { cover { timeZone } } locale { id name } }
                        locale { id name chatRetentionMinutes }
                      }
                    }
                  }
                }
              }
            }
            """, variables: ["id": .string(personID)], as: Response.self).people.person?.chat.rooms.nodes ?? []
    }

    /// The room's last day of messages, newest first, as people in it see them.
    public func chatMessages(in room: AudienceChatRoom.Address, first: Int = 50) async throws -> [VenueChatMessage] {
        struct Response: Decodable, Sendable {
            struct Chat: Decodable, Sendable { let venueMessages: VenueChatPage?; let localeMessages: VenueChatPage? }
            let chat: Chat
        }
        let field = room.isVenue ? "venueMessages(venueId: $id" : "localeMessages(localeId: $id"
        let response = try await session.graphQL("""
            query BackstageChatMessages($id: ID!, $first: Int) {
              chat { \(field), first: $first) { edges { node { \(Self.talentMessageFields) } } pageInfo { hasNextPage endCursor } } }
            }
            """, variables: ["id": .string(room.id), "first": .int(min(max(first, 1), 100))], as: Response.self)
        return (response.chat.venueMessages ?? response.chat.localeMessages)?.edges.map(\.node) ?? []
    }

    /// Posts to the room as the person: TEXT, a PHOTO (`photo` is an image URL or a `data:` URI, with `message` as its
    /// caption) or one of their EVENTs (`eventID`, with `message` as an optional caption). Returns the message as the
    /// room shows it.
    @discardableResult
    public func sendChat(as personID: String, in room: AudienceChatRoom.Address, message: String, kind: String = "TEXT",
                         photo: String? = nil, eventID: String? = nil) async throws -> VenueChatMessage? {
        struct Response: Decodable, Sendable {
            struct Payload: Decodable, Sendable { let venueMessage: VenueChatMessage?; let localeMessage: VenueChatMessage? }
            let sendChatMessage: Payload?
        }
        var input: [String: GraphQLValue] = [room.isVenue ? "venueId" : "localeId": .string(room.id),
                                            "asPersonId": .string(personID), "message": .string(message),
                                            "kind": .string(kind)]
        if let photo { input["photo"] = .string(photo) }
        if let eventID { input["eventId"] = .string(eventID) }
        let payload = try await session.graphQL("""
            mutation BackstageSendMessage($input: ChatMessageSendInput!) {
              sendChatMessage(input: $input) {
                venueMessage { \(Self.talentMessageFields) } localeMessage { \(Self.talentMessageFields) }
              }
            }
            """, variables: ["input": .object(input)], as: Response.self).sendChatMessage
        return payload?.venueMessage ?? payload?.localeMessage
    }

    /// Takes back a message the signed-in user posted as the listing: everyone in the room stops seeing it at once.
    public func removeOwnChat(messageID: String) async throws {
        struct Response: Decodable, Sendable {
            struct Payload: Decodable, Sendable { let deletedId: String }
            let removeMyChatMessage: Payload?
        }
        _ = try await session.graphQL("""
            mutation BackstageRemoveMessage($input: ChatMessageRemoveOwnInput!) {
              removeMyChatMessage(input: $input) { deletedId }
            }
            """, variables: ["input": .object(["messageId": .string(messageID)])], as: Response.self)
    }
}
