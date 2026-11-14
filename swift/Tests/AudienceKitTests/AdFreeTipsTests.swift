@testable import AudienceCore
import Foundation
import Testing
@testable import AudienceKit

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private let adFreeAudienceID = "00000000-0000-4000-8000-000000000072"

private func adFreeClient(_ stub: Stub) -> AudienceKitClient {
    let endpoint = URL(string: GraphQLEndpoint.consumer.path(audienceID: adFreeAudienceID),
                       relativeTo: stub.baseURL)!.absoluteURL
    let store = InMemoryCredentialStore(credential: Credential(token: "session-token", userId: "u-1",
                                                               audienceId: adFreeAudienceID, role: "member",
                                                               endpoint: endpoint))
    let configuration = AudienceKitConfiguration(baseURL: stub.baseURL, audienceID: adFreeAudienceID)
    return AudienceKitClient(configuration: configuration, credentialStore: store, session: stub.session)
}

private extension RecordedRequest {
    var query: String { ((try? jsonBody())?["query"] as? String) ?? "" }
    var operationName: String? { (try? jsonBody())?["operationName"] as? String }
    var variables: [String: Any] { ((try? jsonBody())?["variables"] as? [String: Any]) ?? [:] }
}

@Test func startingAnAdFreeTipReturnsTheWebCheckout() async throws {
    let stub = Stub { _ in
        .json(status: 200, body: #"{"data":{"startTip":{"checkoutUrl":"https://api.example/v1/tips/t-1/checkout?token=x","tip":{"id":"t-1"}}}}"#)
    }

    let checkout = try await adFreeClient(stub).startAdFreeTip(publicationID: "pub-1", amountCents: 500)

    #expect(checkout == AdFreeTipCheckout(tipID: "t-1",
                                          checkoutURL: URL(string: "https://api.example/v1/tips/t-1/checkout?token=x")!))
    let request = try #require(stub.requests.first)
    #expect(request.operationName == "StartAdFreeTip")
    #expect(request.variables["publicationId"] as? String == "pub-1")
    #expect(request.variables["amountCents"] as? Int == 500)
    #expect(request.variables["showFirstName"] as? Bool == false)
    #expect(!request.query.contains("paymentIntentClientSecret"))
}

@Test func anAdFreeTipWithoutACheckoutThrows() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{"startTip":{"checkoutUrl":null,"tip":{"id":"t-1"}}}}"#) }

    await #expect(throws: AdFreeTipUnavailable.self) {
        try await adFreeClient(stub).startAdFreeTip(publicationID: "pub-1", amountCents: 500)
    }
}

@Test func confirmingATipReadsWhenAdsComeBack() async throws {
    let stub = Stub { _ in
        .json(status: 200, body: #"{"data":{"confirmTip":{"tip":{"id":"t-1","status":"PAID","readsAdFreeUntil":"2026-12-14T12:00:00Z"}}}}"#)
    }

    let tip = try #require(try await adFreeClient(stub).confirmTip(id: "t-1"))

    #expect(tip.isPaid)
    #expect(tip.readsAdFreeUntil == ISO8601DateFormatter().date(from: "2026-12-14T12:00:00Z"))
    #expect(stub.requests.first?.variables["tipId"] as? String == "t-1")
}

@Test func soapboxQueriesAskForAdFreeFieldsOnlyWhenTheAPIHasThem() {
    let newer = SchemaShape(fields: ["Article": ["viewerAdFree"], "Publication": ["adFreeOffered"],
                                     "Audience": ["soapbox"]])
    let older = SchemaShape(fields: ["Article": ["id"], "Publication": ["id"], "Audience": ["soapbox"]])

    #expect(Queries.article(newer).contains("viewerAdFree"))
    #expect(Queries.article(newer).contains("acceptsOpEds adFreeOffered"))
    #expect(!Queries.article(older).contains("viewerAdFree"))
    #expect(Queries.publication(newer).contains("adFreeTipCents adFreeDays viewerAdFree viewerAdFreeUntil"))
    #expect(!Queries.publication(older).contains("adFree"))
}

@Test func anArticleDecodesWhetherTheReaderTipped() throws {
    let json = #"""
    {"id":"a-1","slug":"pride","title":"Pride","byline":"QSaltLake","kind":"ARTICLE","edited":false,"pinned":false,"teaser":false,
     "publication":{"id":"pub-1","name":"QSaltLake","trusted":true,"acceptsOpEds":true,"adFreeOffered":true},
     "viewerAdFree":true}
    """#
    let article = try JSONDecoder().decode(Article.self, from: Data(json.utf8))
    #expect(article.showsWithoutAds)
    #expect(article.publication.adFreeOffered == true)

    let older = try JSONDecoder().decode(Article.self, from: Data(#"""
    {"id":"a-1","slug":"","title":"Pride","byline":"","kind":"ARTICLE","edited":false,"pinned":false,"teaser":false,
     "publication":{"id":"pub-1","name":"QSaltLake","trusted":true,"acceptsOpEds":true}}
    """#.utf8))
    #expect(!older.showsWithoutAds)
    #expect(older.publication.adFreeOffered == nil)
}

@Test func adFreeTipsAreOfferedInUSStorefrontsOnly() {
    let offered = Publication(id: "p", name: "QSaltLake", adFreeOffered: true, adFreeTipCents: 500, adFreeDays: 30)
    #expect(AdFreeTips.isOffered(offered, storefrontCountryCode: "USA"))
    #expect(AdFreeTips.isOffered(offered, storefrontCountryCode: "us"))
    #expect(!AdFreeTips.isOffered(offered, storefrontCountryCode: "GBR"))
    #expect(!AdFreeTips.isOffered(offered, storefrontCountryCode: nil))
    #expect(!AdFreeTips.isOffered(Publication(id: "p", name: "Q"), storefrontCountryCode: "USA"))
    #expect(AdFreeTips.isOffered(PublicationSummary(id: "p", name: "Q", adFreeOffered: true),
                                 storefrontCountryCode: "USA"))
}

@Test func adFreeTipsCopyNamesThePublicationAndTheTerms() {
    #expect(AdFreeTips.button(publicationName: "QSaltLake") == "Tip QSaltLake to read without ads")
    let explanation = AdFreeTips.explanation(publicationName: "QSaltLake", tipCents: 500, days: 30)
    #expect(explanation.contains("$5 or more goes straight to QSaltLake"))
    #expect(explanation.contains("without ads for 30 days"))
    #expect(AdFreeTips.money(550) == "$5.50")
    #expect(AdFreeTips.thanks(publicationName: "QSaltLake", until: nil).contains("No ads here for you."))
    #expect(AdFreeTips.thanks(publicationName: "QSaltLake", until: Date()).contains("until"))
}
