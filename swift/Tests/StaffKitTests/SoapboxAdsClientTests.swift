import Foundation
import Testing
import AudienceKit
@testable import StaffKitCore
@testable import StaffKitServices

private func adsClient(_ stub: Stub) -> SoapboxClient {
    SoapboxClient(session: AudienceManagementSession(baseURL: stub.baseURL, credentialStore: InMemoryCredentialStore(credential: makeCredential(audienceID: "audience", on: stub.baseURL)), session: stub.session))
}
private func lastRequest(_ stub: Stub) throws -> (query: String, variables: [String: Any]) {
    let body = try #require(stub.requests.last).jsonBody()
    return (body["query"] as? String ?? "", body["variables"] as? [String: Any] ?? [:])
}

private let ad = #"{"id":"ad-1","adStatus":"IN_REVIEW","spot":"ARTICLE","category":"small_business","sponsorName":"Club Verse","sponsorEmail":null,"headline":"Two-for-one Thursdays","body":null,"imageUrl":null,"imageAlt":null,"linkUrl":null,"linkLabel":null,"articleIds":[],"startsOn":"2026-11-20","endsOn":null,"weekdays":[],"priceCents":5000,"soldOutside":true,"paused":false,"reviewNote":null,"publication":{"id":"p1","name":"QSaltLake"},"weeklyViewers":[]}"#

@Test func aPublicationsAdsComeWithItsRateSheet() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{"soapbox":{"publication":{"id":"p1","adsEnabled":true,"adsNeedReview":true,"rateSheet":{"notes":null,"contactEmail":null,"rates":[{"spot":"ARTICLE","weeklyCents":5000,"slots":4}]},"ads":[\#(ad)]}}}}"#) }
    let ads = try await adsClient(stub).ads(publicationID: "p1")
    #expect(ads.adsEnabled && ads.adsNeedReview)
    #expect(ads.ads.first?.status == .inReview)
    #expect(ads.rateSheet.rate(for: .article).weeklyCents == 5000)
    let (query, variables) = try lastRequest(stub)
    #expect(query.contains("query SoapboxAds"))
    #expect(variables["id"] as? String == "p1")
    #expect(try #require(stub.requests.last).path.hasSuffix("staffql"))
}

@Test func aTurnedDownSaveThrowsItsProblemsAndADryRunReturnsThem() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{"savePublicationAd":{"problems":["Add a picture's description."],"ad":null}}}"#) }
    let client = adsClient(stub)
    let checked = try await client.saveAd(PublisherAdDraft(publicationID: "p1", headline: "Hi", dryRun: true))
    #expect(checked.problems == ["Add a picture's description."])
    #expect(try lastRequest(stub).variables["input"].flatMap { $0 as? [String: Any] }?["dryRun"] as? Bool == true)
    await #expect(throws: PublisherAdProblems.self) {
        try await client.saveAd(PublisherAdDraft(publicationID: "p1", headline: "Hi"))
    }
}

@Test func adminsReviewTheQueueAndSetTheMode() async throws {
    let stub = Stub { request in
        let query = (try? request.jsonBody()["query"] as? String) ?? ""
        if query.contains("SoapboxAdReviewQueue") {
            return .json(status: 200, body: #"{"data":{"soapbox":{"publisherAds":"REVIEW_ALL","adReviewQueue":[\#(ad)]}}}"#)
        }
        if query.contains("SoapboxReviewAd") {
            return .json(status: 200, body: #"{"data":{"reviewPublicationAd":{"ad":\#(ad.replacingOccurrences(of: "IN_REVIEW", with: "RUNNING"))}}}"#)
        }
        return .json(status: 200, body: #"{"data":{"setSoapboxPublisherAds":{"mode":"OFF"}}}"#)
    }
    let client = adsClient(stub)
    let review = try await client.adReviewQueue()
    #expect(review.mode == .reviewAll && review.queue.count == 1)
    let approved = try await client.reviewAd(id: "ad-1", approve: true)
    #expect(approved?.status == .running)
    try await client.setPublisherAds(.off)
    #expect(try lastRequest(stub).variables["mode"] as? String == "OFF")
}

@Test func mediaIsAddedWithItsDescription() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{"addPublicationMedia":{"media":{"id":"m1","url":"https://x.example/a.jpg","altText":"A bar","caption":null,"credit":null,"createdAt":null}}}}"#) }
    let item = try await adsClient(stub).addMedia(publicationID: "p1", photo: "data:image/jpeg;base64,AA==", altText: "A bar")
    #expect(item?.id == "m1")
    let input = try lastRequest(stub).variables["input"] as? [String: Any]
    #expect(input?["publicationId"] as? String == "p1")
    #expect(input?["altText"] as? String == "A bar")
}
