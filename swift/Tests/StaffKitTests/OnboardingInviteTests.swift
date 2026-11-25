import Foundation
import Testing
import AudienceKit
import StaffKitCore

@Test func invitesLinksAreReadTheWayTheAPIReadsCodes() throws {
    let velvet = try #require(OnboardingLink(url: URL(string: "https://audiencekit.com/v/k7qx-2m9p-h4td")!))
    #expect(velvet.app == .velvet)
    #expect(velvet.code == "K7QX2M9PH4TD")
    #expect(velvet.displayCode == "K7QX-2M9P-H4TD")
    #expect(velvet.url.absoluteString == "https://audiencekit.com/v/K7QX2M9PH4TD")

    let backstage = try #require(OnboardingLink(url: URL(string: "https://www.audiencekit.com/b/ILO0ILO0ILO0")!))
    #expect(backstage.app == .backstage)
    #expect(backstage.code == "110011001100")

    #expect(OnboardingLink(url: URL(string: "https://audiencekit.com/apps/velvet")!) == nil)
    #expect(OnboardingLink(url: URL(string: "https://audiencekit.com/v/SHORT")!) == nil)
    #expect(OnboardingLink(url: URL(string: "https://hotmess.social/v/K7QX2M9PH4TD")!) == nil)

    // The App Store Connect experience URLs are https://audiencekit.com/v and /b; the code can ride as a query item.
    let query = try #require(OnboardingLink(url: URL(string: "https://audiencekit.com/b?code=k7qx-2m9p-h4td")!))
    #expect(query.app == .backstage)
    #expect(query.code == "K7QX2M9PH4TD")
    #expect(OnboardingLink(url: URL(string: "https://audiencekit.com/b")!) == nil)
}

@Test func aNewListingChoiceSaysWhatAcceptingSends() {
    let listed = OnboardingMatches.Place(placeId: "ChIJ1", name: "The Wildrose", address: "1021 E Pike St", venueId: "v1")
    #expect(OnboardingListingChoice.place(listed).isRequest)
    #expect(OnboardingListingChoice.place(listed).body["match_id"] as? String == "v1")
    let typed = OnboardingListingChoice.typed(name: "Lady Lux", address: nil)
    #expect(!typed.isRequest)
    #expect((typed.body["listing"] as? [String: String]) == ["name": "Lady Lux"])
}

@Test func anInviteIsPreviewedClaimedAndAcceptedIntoItsAudience() async throws {
    let subject = #"{"type":"Venue","id":"venue-1","name":"The Wildrose","image_url":null}"#
    let preview = #"{"app":"velvet","access":"staff","status":"pending","expires_at":"2026-11-01T06:00:00Z","note":"Door on Friday","invited_by":"Rick M.","audience":{"id":"hot-mess","name":"Hot Mess","subdomain":"hotmess"},"subject":"# + subject
    let stub = Stub { request in
        switch (request.method, request.path) {
        case ("GET", "/v1/onboarding/K7QX2M9PH4TD"):
            return .json(status: 200, body: preview + "}")
        case ("POST", "/v1/onboarding/K7QX2M9PH4TD/claim"):
            return .json(status: 200, body: preview + #","prefill":{"title":"Door lead"}}"#)
        case ("POST", "/v1/onboarding/K7QX2M9PH4TD/accept"):
            let credential = makeCredential(token: "audience-token", audienceID: "hot-mess", role: "listing", on: request.url)
            return .json(status: 201, body: tokenJSON(credential, extra: #""tenant":{"audience":{"id":"hot-mess","name":"Hot Mess","subdomain":"hotmess"}},"role":"listing","subject":"# + subject))
        default:
            return .json(status: 404, body: "{}")
        }
    }
    let store = InMemoryCredentialStore(credential: makeCredential(token: "platform-token"))
    let audiences = InMemoryAudienceStore()
    let session = AudienceManagementSession(baseURL: stub.baseURL, credentialStore: store, audienceStore: audiences,
                                            session: stub.session)
    let link = OnboardingLink(app: .velvet, code: "K7QX2M9PH4TD")

    let shown = try await session.onboardingPreview(link)
    #expect(shown.invitedBy == "Rick M.")
    #expect(shown.subject?.name == "The Wildrose")
    #expect(shown.invitation == "join the team at The Wildrose")
    #expect(stub.requests.last?.header("Authorization") == nil)

    let claimed = try await session.claimOnboarding(link)
    #expect(claimed.prefill?["title"] == "Door lead")
    #expect(stub.requests.last?.header("Authorization") == "Bearer platform-token")

    let accepted = try await session.acceptOnboarding(link)
    #expect(accepted.audience.id == "hot-mess")
    #expect(accepted.subject.id == "venue-1")
    #expect(try store.load()?.token == "audience-token")
    #expect(try audiences.load()?.id == "hot-mess")
    #expect(await session.boundAudienceID == "hot-mess")
}

@Test func anEndedInviteSaysSoInTheAPIsWords() async throws {
    let stub = Stub { _ in
        .json(status: 410, body: #"{"error":"EXPIRED","message":"This invite has ended. Ask whoever invited you for a new one."}"#)
    }
    let session = AudienceManagementSession(baseURL: stub.baseURL, session: stub.session)
    do {
        _ = try await session.onboardingPreview(OnboardingLink(app: .backstage, code: "K7QX2M9PH4TD"))
        Issue.record("An ended invite previewed")
    } catch let error as AudienceKitError {
        #expect(error.code == "EXPIRED")
        #expect(error.message.hasPrefix("This invite has ended"))
    }
}
