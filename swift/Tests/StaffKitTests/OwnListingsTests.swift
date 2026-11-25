import Foundation
import Testing
import AudienceKit
@testable import StaffKitCore
@testable import StaffKitServices

private func talent(_ stub: Stub, audienceID: String? = nil) -> TalentManagementClient {
    TalentManagementClient(session: AudienceManagementSession(
        baseURL: stub.baseURL,
        credentialStore: InMemoryCredentialStore(credential: makeCredential(audienceID: audienceID, role: "user", on: stub.baseURL)),
        session: stub.session))
}

private let ownPerson = #"{"id":"p1","name":"Anya Bacon","avatarUrl":null,"profile":{"website":null,"socialLinks":{"nodes":[]}},"music":{"links":{"nodes":[]}},"tipping":{"options":[]},"audiences":[],"viewerRole":"OWNER"}"#
private let listedPerson = #"{"id":"p2","name":"Those Bitches","avatarUrl":null,"profile":{"website":null,"socialLinks":{"nodes":[]}},"music":{"links":{"nodes":[]}},"tipping":{"options":[]},"audiences":[{"audienceId":"a1","name":"Hot Mess","subdomain":"hotmess"}],"viewerRole":"TROUPE"}"#

@Test func ownListingsComeFromTheAudiencelessEndpoint() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{"me":{"listings":{"people":[\#(ownPerson),\#(listedPerson)],"troupes":[{"id":"p2"}]}}}}"#) }
    let (listings, troupes) = try await talent(stub).ownListings()

    #expect(stub.requests.last?.path == "/v1/staffql")
    #expect(listings.map(\.id) == ["p1", "p2"])
    #expect(listings[0].audiences.isEmpty && listings[0].role == .owner)
    #expect(listings[1].audiences.map(\.name) == ["Hot Mess"] && listings[1].role == .troupe)
    #expect(troupes == ["p2"])
}

@Test func startsAListingOfTheirOwn() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{"createOwnPerson":{"person":\#(ownPerson)}}}"#) }
    let listing = try await talent(stub).createOwnPerson(name: "Anya Bacon")

    #expect(listing.person.name == "Anya Bacon")
    let body = try #require(stub.requests.last).jsonBody()
    #expect((body["query"] as? String)?.contains("createOwnPerson(input: $input)") == true)
    let input = (body["variables"] as? [String: Any])?["input"] as? [String: Any]
    #expect((input?["person"] as? [String: Any])?["name"] as? String == "Anya Bacon")
}

@Test func ownListingsWaitForThePlatformSignIn() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{}}"#) }
    let client = talent(stub, audienceID: "a1")

    #expect(await client.session.canUseOwnListings == false)
    await #expect(throws: AudienceKitError.self) { _ = try await client.ownListings() }
    #expect(stub.requests.isEmpty)
}
