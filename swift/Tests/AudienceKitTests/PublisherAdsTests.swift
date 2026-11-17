@testable import AudienceCore
import Foundation
import Testing
@testable import AudienceKit

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private let adsAudienceID = "00000000-0000-4000-8000-000000000098"

private func adsClient(_ stub: Stub) -> AudienceKitClient {
    let endpoint = URL(string: GraphQLEndpoint.consumer.path(audienceID: adsAudienceID),
                       relativeTo: stub.baseURL)!.absoluteURL
    let store = InMemoryCredentialStore(credential: Credential(token: "session-token", userId: "u-1",
                                                               audienceId: adsAudienceID, role: "member",
                                                               endpoint: endpoint))
    let configuration = AudienceKitConfiguration(baseURL: stub.baseURL, audienceID: adsAudienceID)
    return AudienceKitClient(configuration: configuration, credentialStore: store, session: stub.session)
}

private let adJSON = #"""
{"id":"ad-1","category":"small_business","label":"Ad","sponsorName":"Club Verse","soldBy":"QSaltLake",
"headline":"Two-for-one Thursdays","body":null,"imageUrl":null,"imageAlt":null,"linkUrl":"https://verse.example",
"linkLabel":"See the menu"}
"""#

@Test func anArticlesPublisherAdDecodesWithWhoSoldIt() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{"soapbox":{"article":{"id":"a-1","ad":"# + adJSON + "}}}}") }

    let ad = try #require(try await adsClient(stub).publisherAd(articleID: "a-1"))

    #expect(ad.label == "Ad")
    #expect(ad.soldBy == "QSaltLake")
    #expect(ad.isPublisherAd)
    #expect(ad.content.headline == "Two-for-one Thursdays")
    #expect(PublisherAdCopy.soldBy(ad.soldBy!) == "Sold by QSaltLake")
    let request = try #require(stub.requests.first)
    let body = try request.jsonBody()
    #expect(body?["operationName"] as? String == "ArticleAd")
}

@Test func noPublisherAdIsNil() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{"soapbox":{"publication":{"id":"p-1","ad":null}}}}"#) }

    #expect(try await adsClient(stub).publisherAd(publicationID: "p-1") == nil)
}

@Test func anAudienceCardIsNotAPublisherAd() {
    let card = PromoCard(id: "c", category: "health", label: "Promoted", sponsorName: "Clinic",
                         content: CardContent(headline: "Free testing"))
    #expect(!card.isPublisherAd)
    #expect(PublisherAdCopy.why("QSaltLake").contains("keeps all of the money"))
}
