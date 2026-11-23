@testable import AudienceCore
import Foundation
import Testing
@testable import AudienceKit

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private let privacyAudienceID = "00000000-0000-4000-8000-000000000073"

private func privacyClient(_ stub: Stub) -> AudienceKitClient {
    let endpoint = URL(string: GraphQLEndpoint.consumer.path(audienceID: privacyAudienceID),
                       relativeTo: stub.baseURL)!.absoluteURL
    let store = InMemoryCredentialStore(credential: Credential(token: "session-token", userId: "u-1",
                                                               audienceId: privacyAudienceID, role: "member",
                                                               endpoint: endpoint))
    let configuration = AudienceKitConfiguration(baseURL: stub.baseURL, audienceID: privacyAudienceID)
    return AudienceKitClient(configuration: configuration, credentialStore: store, session: stub.session)
}

private extension RecordedRequest {
    var operationName: String? { (try? jsonBody())?["operationName"] as? String }
    var variables: [String: Any] { ((try? jsonBody())?["variables"] as? [String: Any]) ?? [:] }
}

private let choicesJSON = #"""
{"saleShareOptedOut":true,"saleShareOptedOutAt":"2026-11-23T01:00:00Z","saleShareOptOutSource":"GLOBAL_PRIVACY_CONTROL","adMeasurement":true,"countedInAdMeasurement":true,"personalizedAds":false,"mayShare":false,"privacyPassUntil":null}
"""#

@Test func readsTheOfferAndTheMembersChoices() async throws {
    let stub = Stub { _ in
        .json(status: 200, body: #"{"data":{"privacyOffer":{"choices":["SALE_SHARE_OPT_OUT","AD_MEASUREMENT","SOMETHING_NEW","PRIVACY_PASS"],"passCents":299,"passDays":30},"me":{"privacy":"# + choicesJSON + "}}}")
    }

    let (offer, choices) = try await privacyClient(stub).privacy()

    #expect(offer == PrivacyOffer(choices: [.saleShareOptOut, .adMeasurement, .privacyPass], passCents: 299,
                                  passDays: 30))
    #expect(choices.saleShareOptedOut)
    #expect(choices.saleShareOptOutSource == .globalPrivacyControl)
    #expect(choices.isOn(.saleShareOptOut))
    #expect(!choices.isOn(.personalizedAds))
    #expect(!choices.mayShare)
}

@Test func signedOutReadsTheDefaults() async throws {
    let stub = Stub { _ in
        .json(status: 200, body: #"{"data":{"privacyOffer":{"choices":["SALE_SHARE_OPT_OUT"],"passCents":null,"passDays":30},"me":null}}"#)
    }

    let (offer, choices) = try await privacyClient(stub).privacy()

    #expect(offer.choices == [.saleShareOptOut])
    #expect(choices == .defaults)
    #expect(choices.adMeasurement && !choices.personalizedAds && !choices.saleShareOptedOut)
}

@Test func turningOneSwitchSendsOnlyThatChoice() async throws {
    let stub = Stub { _ in
        .json(status: 200, body: #"{"data":{"updatePrivacyChoices":{"privacy":"# + choicesJSON + "}}}")
    }

    let choices = try await privacyClient(stub).setPrivacyChoice(.saleShareOptOut, on: true)

    #expect(choices.saleShareOptedOut)
    let request = try #require(stub.requests.first)
    #expect(request.operationName == "UpdatePrivacyChoices")
    #expect(request.variables["saleShareOptOut"] as? Bool == true)
    #expect(request.variables["adMeasurement"] is NSNull)
}

@Test func startingAPrivacyPassReturnsTheCheckout() async throws {
    let stub = Stub { _ in
        .json(status: 200, body: #"{"data":{"startPrivacyPass":{"checkoutUrl":"https://checkout.stripe.com/c/pay/cs_1","passId":"p-1"}}}"#)
    }

    let checkout = try await privacyClient(stub).startPrivacyPass(returnURL: "hotmess://privacy")

    #expect(checkout == PrivacyPassCheckout(passID: "p-1", checkoutURL: URL(string: "https://checkout.stripe.com/c/pay/cs_1")!))
    #expect(stub.requests.first?.variables["returnUrl"] as? String == "hotmess://privacy")
}

@Test func aPrivacyPassWithoutACheckoutThrows() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{"startPrivacyPass":null}}"#) }

    await #expect(throws: PrivacyPassUnavailable.self) {
        try await privacyClient(stub).startPrivacyPass()
    }
}

@Test func offersThePassOnlyInUSStorefrontsOrOnTheWeb() {
    let offer = PrivacyOffer(choices: [.saleShareOptOut, .privacyPass], passCents: 299, passDays: 30)

    #expect(PrivacyChoicesCopy.isPassOffered(offer, storefrontCountryCode: "USA"))
    #expect(PrivacyChoicesCopy.isPassOffered(offer, storefrontCountryCode: "us"))
    #expect(!PrivacyChoicesCopy.isPassOffered(offer, storefrontCountryCode: "GBR"))
    #expect(!PrivacyChoicesCopy.isPassOffered(offer, storefrontCountryCode: nil))
    #expect(PrivacyChoicesCopy.isPassOffered(offer, storefrontCountryCode: nil, isWeb: true))
    #expect(!PrivacyChoicesCopy.isPassOffered(.minimum, storefrontCountryCode: "USA"))
}

@Test func privacyCopyNamesEachChoice() {
    #expect(PrivacyChoicesCopy.title == "Your privacy choices")
    #expect(PrivacyChoicesCopy.label(.saleShareOptOut) == "Do not sell or share my personal information")
    #expect(PrivacyChoicesCopy.passButton(cents: 299, days: 30) == "Go without ads for 30 days, $2.99")
    #expect(PrivacyChoicesCopy.detail(.saleShareOptOut, appName: "Hot Mess").hasPrefix("Hot Mess doesn't sell"))
    #expect(PrivacyChoicesCopy.passExplanation(days: 7).contains("nothing renews"))
    for key in PrivacyChoiceKey.allCases {
        #expect(!PrivacyChoicesCopy.detail(key, appName: "Hot Mess").isEmpty)
    }
}
