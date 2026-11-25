import Foundation
import AudienceCore
import StaffKitCore

/// A talent listing granted an event without hosting it or being on its lineup, like crew or a photographer
/// (`Event.accessGrants`; the API's doc/EVENT_ACCESS.md). Its managers have the event like someone on it: among the
/// listing's events in Backstage, on its lineup's editors and in its back-of-house room. Its hosts and lineup have it
/// already.
public struct EventAccessGrant: Decodable, Sendable, Identifiable, Equatable {
    public struct Person: Decodable, Sendable, Equatable {
        public let id: String
        public let name: String?
        public init(id: String, name: String?) { self.id = id; self.name = name }
    }
    public let id: String
    public let createdAt: String?
    public let person: Person?
    public init(id: String, createdAt: String? = nil, person: Person?) { self.id = id; self.createdAt = createdAt; self.person = person }
}

/// Reads and changes who's granted an event (`Event.accessGrants`, `grantEventAccess`, `revokeEventAccess`). Its
/// venue's managers, the talent who listed it, its hosts' managers and admins manage them; the server checks on every
/// call, and answers nil grants to anyone else.
public struct EventAccessClient: Sendable {
    public let session: AudienceManagementSession
    public init(session: AudienceManagementSession) { self.session = session }

    static let grantFields = "id createdAt person { id name }"
    static let readQuery = """
        query StaffEventAccess($id: ID!) { events { event(id: $id) { id accessGrants { \(grantFields) } } } }
        """
    static let grantMutation = """
        mutation StaffGrantEventAccess($input: EventAccessGrantInput!) {
          grantEventAccess(input: $input) { event { id accessGrants { \(grantFields) } } }
        }
        """
    static let revokeMutation = """
        mutation StaffRevokeEventAccess($input: EventAccessRevokeInput!) {
          revokeEventAccess(input: $input) { event { id accessGrants { \(grantFields) } } }
        }
        """

    private struct Event: Decodable, Sendable { let id: String; let accessGrants: [EventAccessGrant]? }

    /// The event's grants, oldest first; nil when the event isn't there or they may not manage its grants.
    public func grants(eventID: String) async throws -> [EventAccessGrant]? {
        struct Response: Decodable, Sendable {
            struct Events: Decodable, Sendable { let event: Event? }
            let events: Events?
        }
        return try await session.graphQL(Self.readQuery, variables: ["id": .string(eventID)], as: Response.self)
            .events?.event?.accessGrants
    }

    /// Grants the event to a talent listing. Returns its grants after.
    @discardableResult
    public func grant(eventID: String, personID: String) async throws -> [EventAccessGrant] {
        struct Response: Decodable, Sendable {
            struct Payload: Decodable, Sendable { let event: Event }
            let grantEventAccess: Payload?
        }
        let input: [String: GraphQLValue] = ["eventId": .string(eventID), "personId": .string(personID)]
        let response = try await session.graphQL(Self.grantMutation, variables: ["input": .object(input)], as: Response.self)
        return try Self.grants(response.grantEventAccess?.event)
    }

    /// Takes a grant back. Returns the event's grants after.
    @discardableResult
    public func revoke(grantID: String) async throws -> [EventAccessGrant] {
        struct Response: Decodable, Sendable {
            struct Payload: Decodable, Sendable { let event: Event }
            let revokeEventAccess: Payload?
        }
        let response = try await session.graphQL(Self.revokeMutation, variables: ["input": .object(["id": .string(grantID)])],
                                                 as: Response.self)
        return try Self.grants(response.revokeEventAccess?.event)
    }

    private static func grants(_ event: Event?) throws -> [EventAccessGrant] {
        guard let grants = event?.accessGrants else { throw AudienceKitError.decoding("The event's access was missing") }
        return grants
    }
}
