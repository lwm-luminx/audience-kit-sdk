import Foundation
import Testing
import AudienceKit
@testable import StaffKitCore
@testable import StaffKitServices

private func ownSession(_ stub: Stub) -> AudienceManagementSession {
    AudienceManagementSession(
        baseURL: stub.baseURL,
        credentialStore: InMemoryCredentialStore(credential: makeCredential(audienceID: nil, role: "user", on: stub.baseURL)),
        session: stub.session)
}

private let lockedSubscription = #"{"status":"NONE","source":null,"required":true,"unlocked":false,"comped":false,"interval":null,"trialAvailable":true,"trialEndsAt":null,"periodEndsAt":null,"cancelAtPeriodEnd":false,"canManage":true,"plan":{"name":"Velvet","monthlyCents":2900,"yearlyCents":29000,"trialDays":14,"appStoreProductIds":["com.audiencekit.velvet.monthly","com.audiencekit.velvet.yearly"]}}"#
private let trialSubscription = lockedSubscription
    .replacingOccurrences(of: #""status":"NONE","source":null"#, with: #""status":"TRIALING","source":"APP_STORE""#)
    .replacingOccurrences(of: #""unlocked":false"#, with: #""unlocked":true"#)
    .replacingOccurrences(of: #""trialEndsAt":null"#, with: #""trialEndsAt":"2026-11-22T00:00:00Z""#)

@Test func signsUpAVenueOfTheirOwnOnTheAudiencelessEndpoint() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{"createOwnVenue":{"venue":{"id":"v1"}}}}"#) }
    let client = VenueSubscriptionClient(runner: OwnListingsGraphQL(session: ownSession(stub)))
    let id = try await client.createOwnVenue(name: "Club Solo", website: "https://solo.example", phone: "", timeZone: "America/Denver")

    #expect(id == "v1")
    #expect(stub.requests.last?.path == "/v1/staffql")
    let body = try #require(stub.requests.last).jsonBody()
    let venue = ((body["variables"] as? [String: Any])?["input"] as? [String: Any])?["venue"] as? [String: Any]
    #expect(venue?["name"] as? String == "Club Solo")
    #expect(venue?["coverTimeZone"] as? String == "America/Denver")
    #expect(venue?["phone"] == nil)
}

@Test func readsWhetherTheVenuesToolsAreLocked() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{"node":{"velvetSubscription":\#(lockedSubscription)}}}"#) }
    let subscription = try #require(try await VenueSubscriptionClient(runner: OwnListingsGraphQL(session: ownSession(stub))).subscription(venueID: "v1"))

    #expect(subscription.locksTools)
    #expect(subscription.status == .none && subscription.trialAvailable && subscription.canManage)
    #expect(subscription.plan.appStoreProductIds.count == 2)
}

@Test func recordsAnAppStorePurchaseForTheVenue() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{"recordVenueStorePurchase":{"venue":{"velvetSubscription":\#(trialSubscription)}}}}"#) }
    let client = VenueSubscriptionClient(runner: OwnListingsGraphQL(session: ownSession(stub)))
    let subscription = try #require(try await client.recordAppStorePurchase(venueID: "v1", signedTransaction: "jws.payload.sig"))

    #expect(subscription.status == .trialing && subscription.source == .appStore && !subscription.locksTools)
    #expect(subscription.trialEnds != nil)
    let body = try #require(stub.requests.last).jsonBody()
    let input = (body["variables"] as? [String: Any])?["input"] as? [String: Any]
    #expect(input?["signedTransaction"] as? String == "jws.payload.sig")
    #expect(input?["venueId"] as? String == "v1")
}
