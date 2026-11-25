import Foundation
import Testing
import AudienceKit
@testable import StaffKitCore
@testable import StaffKitServices

// A venue that signed itself up in Velvet lives in the API's hidden shared tenant: the session opens it
// (openOwnListings) and runs the same staff documents, and the live door and chat, on its staffql
// (the API's doc/VELVET_SUBSCRIPTION.md).

private func platformSession(_ stub: Stub) -> AudienceManagementSession {
    AudienceManagementSession(
        baseURL: stub.baseURL,
        credentialStore: InMemoryCredentialStore(credential: makeCredential(audienceID: nil, role: "user", on: stub.baseURL)),
        session: stub.session)
}

private let admission = #"{"id":"a1","amount":{"cents":1000,"currency":"usd"},"total":{"cents":1112,"currency":"usd"},"status":"PAID","checkedInAt":null,"scanCount":0,"createdAt":"2026-10-10T05:00:00Z","profile":{"id":"u1","name":"Alex","avatarUrl":null}}"#
private let doorNight = #"{"data":{"venues":{"venue":{"tickets":{"cover":{"door":{"night":"2026-11-08","paidCount":1,"checkedInCount":0,"gross":{"cents":1000,"currency":"usd"},"admissions":{"nodes":[\#(admission)]}}}}}}}}"#
private let locked = #"{"data":null,"errors":[{"message":"Subscribe to Velvet to use Club Solo's tools","extensions":{"code":"FORBIDDEN","reason":"subscription_required"}}]}"#

@Test func staffDocumentsWaitForAnAudienceOrOwnListings() async throws {
    let stub = Stub { _ in .json(status: 200, body: doorNight) }

    await #expect(throws: AudienceKitError.self) {
        _ = try await VenueManagementClient(session: platformSession(stub)).door(venueID: "v1")
    }
    #expect(stub.requests.isEmpty)
}

@Test func anAudiencesSignInKeepsItsStaffql() async throws {
    let stub = Stub { _ in .json(status: 200, body: doorNight) }
    let session = AudienceManagementSession(
        baseURL: stub.baseURL,
        credentialStore: InMemoryCredentialStore(credential: makeCredential(audienceID: "aud-1", on: stub.baseURL)),
        session: stub.session)
    _ = try await VenueManagementClient(session: session).door(venueID: "v1")

    #expect(stub.requests.last?.path == "/v1/audience/aud-1/staffql")
}

@Test func aLockedVenuesToolsSaySubscribe() async throws {
    let stub = Stub { request in
        request.path == "/v1/staffql"
            ? .json(status: 200, body: #"{"data":{"me":{"ownListingsAudienceId":"shared-1"}}}"#)
            : .json(status: 200, body: locked)
    }
    let session = platformSession(stub)
    try await session.openOwnListings()

    do {
        _ = try await VenueManagementClient(session: session).door(venueID: "v1")
        Issue.record("expected the lock")
    } catch let error as AudienceKitError {
        #expect(error.isSubscriptionRequired)
    }
}

@Test func ownListingsOpenOnTheSharedTenantsStaffqlAndCloseBack() async throws {
    let stub = Stub { request in
        request.path == "/v1/staffql"
            ? .json(status: 200, body: #"{"data":{"me":{"ownListingsAudienceId":"shared-1"}}}"#)
            : .json(status: 200, body: doorNight)
    }
    let session = platformSession(stub)

    #expect(try await session.openOwnListings() == "shared-1")
    _ = try await VenueManagementClient(session: session).door(venueID: "v1")
    #expect(stub.requests.last?.path == "/v1/audience/shared-1/staffql")

    await session.closeOwnListings()
    #expect(await session.boundAudienceID == nil)
}

@Test func noOwnListingsLeavesTheSessionUnbound() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{"me":{"ownListingsAudienceId":null}}}"#) }
    let session = platformSession(stub)

    #expect(try await session.openOwnListings() == nil)
    #expect(await session.boundAudienceID == nil)
}
