import AudienceCore
import StaffKitCore

/// Performer management uses StaffKitCore's session and audience authorization, just like StaffKit.
public struct TalentManagementClient: Sendable {
    public struct Performer: Decodable, Sendable, Identifiable {
        public let id: String
        public let name: String?
    }
    public let session: AudienceManagementSession
    public init(session: AudienceManagementSession) { self.session = session }

    public func updateName(personID: String, name: String) async throws -> Performer {
        struct Response: Decodable, Sendable {
            struct Payload: Decodable, Sendable { let person: Performer }
            let updatePerson: Payload
        }
        return try await session.graphQL("""
            mutation BackstageUpdatePerson($input: PersonUpdateInput!) {
              updatePerson(input: $input) { person { id name } }
            }
            """, variables: ["input": .object(["id": .string(personID),
                           "person": .object(["name": .string(name)])])], as: Response.self).updatePerson.person
    }
}
