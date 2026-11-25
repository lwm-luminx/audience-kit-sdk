import Foundation
import Testing
import AudienceKit
@testable import StaffKitCore
@testable import StaffKitServices

private func accessClient(_ stub: Stub) -> EventAccessClient {
    EventAccessClient(session: AudienceManagementSession(baseURL: stub.baseURL, credentialStore: InMemoryCredentialStore(credential: makeCredential(audienceID: "audience", on: stub.baseURL)), session: stub.session))
}
private func lastRequest(_ stub: Stub) throws -> (query: String, variables: [String: Any]) {
    let body = try #require(stub.requests.last).jsonBody()
    return (body["query"] as? String ?? "", body["variables"] as? [String: Any] ?? [:])
}

private let grantsJSON = #"[{"id":"g1","createdAt":"2026-10-24T03:00:00Z","person":{"id":"p-pat","name":"Pat Photos"}}]"#

@Test func anEventsGrantsAreReadForThoseWhoManageThem() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{"events":{"event":{"id":"e1","accessGrants":\#(grantsJSON)}}}}"#) }
    let grants = try #require(try await accessClient(stub).grants(eventID: "e1"))
    #expect(grants == [EventAccessGrant(id: "g1", createdAt: "2026-10-24T03:00:00Z", person: .init(id: "p-pat", name: "Pat Photos"))])
    let (query, variables) = try lastRequest(stub)
    #expect(query.contains("event(id: $id) { id accessGrants { id createdAt person { id name } } }"))
    #expect(variables["id"] as? String == "e1")

    // Anyone else gets nil, and the section draws nothing.
    let hidden = Stub { _ in .json(status: 200, body: #"{"data":{"events":{"event":{"id":"e1","accessGrants":null}}}}"#) }
    #expect(try await accessClient(hidden).grants(eventID: "e1") == nil)
}

@Test func grantingSendsTheEventAndTheListing() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{"grantEventAccess":{"event":{"id":"e1","accessGrants":\#(grantsJSON)}}}}"#) }
    let grants = try await accessClient(stub).grant(eventID: "e1", personID: "p-pat")
    #expect(grants.map(\.id) == ["g1"])
    let (query, variables) = try lastRequest(stub)
    #expect(query.contains("grantEventAccess(input: $input)") && query.contains("EventAccessGrantInput!"))
    let input = try #require(variables["input"] as? [String: Any])
    #expect(input["eventId"] as? String == "e1" && input["personId"] as? String == "p-pat")
}

@Test func revokingSendsTheGrant() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{"revokeEventAccess":{"event":{"id":"e1","accessGrants":[]}}}}"#) }
    #expect(try await accessClient(stub).revoke(grantID: "g1").isEmpty)
    let (query, variables) = try lastRequest(stub)
    #expect(query.contains("revokeEventAccess(input: $input)") && query.contains("EventAccessRevokeInput!"))
    #expect((variables["input"] as? [String: Any])?["id"] as? String == "g1")
}
