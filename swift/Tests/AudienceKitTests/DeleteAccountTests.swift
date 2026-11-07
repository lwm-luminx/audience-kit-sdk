@testable import AudienceCore
import Foundation
import Testing
@testable import AudienceKit

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private let deleteAudienceID = "00000000-0000-4000-8000-000000000003"

private func deleteClient(_ stub: Stub) -> (AudienceKitClient, InMemoryCredentialStore) {
    let endpoint = URL(string: GraphQLEndpoint.consumer.path(audienceID: deleteAudienceID), relativeTo: stub.baseURL)!
        .absoluteURL
    let store = InMemoryCredentialStore(credential: Credential(token: "session-token", userId: "u-1",
                                                               audienceId: deleteAudienceID, role: "member",
                                                               endpoint: endpoint))
    let configuration = AudienceKitConfiguration(baseURL: stub.baseURL, audienceID: deleteAudienceID)
    return (AudienceKitClient(configuration: configuration, credentialStore: store, session: stub.session), store)
}

@Test func deletingTheAccountConfirmsAndSignsOutOnThisDevice() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{"deleteAccount":{"deleted":true}}}"#) }
    let (client, store) = deleteClient(stub)
    var events = client.sessionEvents.makeAsyncIterator()

    #expect(try await client.deleteAccount())

    #expect(try store.load() == nil)
    #expect(await client.isSignedIn == false)
    #expect(await events.next() == .signedOut)
    let body = try stub.requests[0].jsonBody()
    #expect(body["operationName"] as? String == "DeleteAccount")
    #expect((body["variables"] as? [String: Any])?["confirm"] as? Bool == true)
    #expect(stub.requests.count == 1)
}

@Test func anAccountTheAPIKeptStaysSignedIn() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{"deleteAccount":{"deleted":false}}}"#) }
    let (client, store) = deleteClient(stub)

    #expect(try await client.deleteAccount() == false)
    #expect(try store.load()?.token == "session-token")
}

@Test func aFailedDeleteThrowsAndKeepsTheSession() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{"deleteAccount":null},"errors":[{"message":"nope"}]}"#) }
    let (client, store) = deleteClient(stub)

    await #expect(throws: AudienceKitError.self) { try await client.deleteAccount() }
    #expect(try store.load()?.token == "session-token")
}
