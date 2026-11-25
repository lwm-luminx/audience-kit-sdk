import Foundation
import Testing
import AudienceKit
import StaffKitCore
import StaffKitServices

private func client(_ stub: Stub) -> VenueManagementClient {
    VenueManagementClient(session: AudienceManagementSession(baseURL: stub.baseURL, credentialStore: InMemoryCredentialStore(credential: makeCredential(audienceID: "audience", on: stub.baseURL)), session: stub.session))
}
private func sent(_ stub: Stub) throws -> (query: String, variables: [String: Any], input: [String: Any]) {
    let body = try #require(stub.requests.last).jsonBody()
    let variables = body["variables"] as? [String: Any] ?? [:]
    return (body["query"] as? String ?? "", variables, variables["input"] as? [String: Any] ?? [:])
}

@Test func aVenueReadsItsPartnerOffersForAPlacement() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{"venues":{"venue":{"referralOffers":[{"id":"o1","key":"fire_tv","partner":"Amazon","category":"screens","placement":"SCREENS","headline":"Put Tonight on a TV","body":"A Fire TV Stick runs Velvet.","cta":"See Fire TV","url":"https://amzn.to/x","imageUrl":null,"disclosure":"Love Wins Media may earn a referral fee."},{"id":"o2","key":"new","partner":"New","category":"x","placement":"SOMEWHERE_NEW","headline":"h","body":"b","cta":"c","url":"https://x.test","imageUrl":"https://x.test/l.png","disclosure":"d"}]}}}}"#) }
    let offers = try await client(stub).referralOffers(venueID: "venue", placement: .screens)
    #expect(offers.map(\.key) == ["fire_tv", "new"])
    #expect(offers[0].placement == .screens && offers[0].imageUrl == nil)
    #expect(offers[1].placement == nil)
    let request = try sent(stub)
    #expect(request.query.contains("referralOffers(placement: $placement)"))
    #expect(request.variables["placement"] as? String == "SCREENS" && request.variables["id"] as? String == "venue")
}

@Test func tappingAnOfferCountsItAndOpensItsLinkAndNotForUsDismissesIt() async throws {
    let stub = Stub { request in
        let query = (try? request.jsonBody()["query"] as? String) ?? ""
        if query.contains("recordReferralOfferClick") { return .json(status: 200, body: #"{"data":{"recordReferralOfferClick":{"url":"https://amzn.to/x"}}}"#) }
        return .json(status: 200, body: #"{"data":{"dismissReferralOffer":{"venue":{"id":"venue"}}}}"#)
    }
    let venues = client(stub)
    #expect(try await venues.recordReferralOfferClick(venueID: "venue", offerID: "o1")?.host == "amzn.to")
    var request = try sent(stub)
    #expect(request.input["venueId"] as? String == "venue" && request.input["id"] as? String == "o1")
    try await venues.dismissReferralOffer(venueID: "venue", offerID: "o1")
    request = try sent(stub)
    #expect(request.query.contains("dismissReferralOffer(input: $input)"))
    #expect(request.input["id"] as? String == "o1")
}
