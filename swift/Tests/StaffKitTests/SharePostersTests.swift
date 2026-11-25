import Foundation
import Testing
import AudienceKit
import StaffKitCore
import StaffKitServices

private func backstage(_ stub: Stub) -> TalentManagementClient {
    TalentManagementClient(session: AudienceManagementSession(baseURL: stub.baseURL, credentialStore: InMemoryCredentialStore(credential: makeCredential(audienceID: "audience", on: stub.baseURL)), session: stub.session))
}

@Test func eventShareCarriesTheSignedLinkCutOutsAndFinishedArt() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"""
        {"data":{"shareLink":{"url":"https://hotmess.social/events/e1?e=v3.abc"},
         "events":{"event":{"id":"e1","name":"Karaoke at PAX","startAt":"2026-10-31T04:00:00Z","bannerUrl":null,
          "venue":{"name":"PAX","venue":{"id":"v1","tickets":{"cover":{"timeZone":"America/Los_Angeles"}}}},
          "people":{"lineup":{"nodes":[{"id":"p1","name":"Anya","posterCutoutUrl":"https://cdn/anya.png"},{"id":"p2","name":"Darcy","posterCutoutUrl":null}]}},
          "posterArt":[{"id":"a1","kind":"BACKGROUND","status":"READY","orientation":"SQUARE","url":"https://cdn/sq.png","artistName":null},
                       {"id":"a2","kind":"BACKGROUND","status":"READY","orientation":"PORTRAIT","url":"https://cdn/tall.png","artistName":null}]}}}}
        """#) }
    let pack = try #require(try await backstage(stub).eventShare(id: "e1"))
    #expect(pack.link?.absoluteString == "https://hotmess.social/events/e1?e=v3.abc")
    #expect(pack.when == "Fri, Oct 30 · 9 PM")
    #expect(pack.billing == "with Anya · Darcy")
    #expect(pack.background(for: "PORTRAIT")?.id == "a2")
    #expect(pack.background(for: "LANDSCAPE")?.id == "a1")
    #expect(pack.artistPoster == nil)
    #expect(pack.caption() == "Karaoke at PAX\nFri, Oct 30 · 9 PM · PAX\nwith Anya · Darcy\nhttps://hotmess.social/events/e1?e=v3.abc")
    let variables = try #require(stub.requests.last).jsonBody()["variables"] as? [String: Any]
    #expect(variables?["path"] as? String == "/events/e1")
}

@Test func aTroupeStandsAsItsMembersAndAnArtistPosterTakesOver() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"""
        {"data":{"shareLink":null,"people":{"person":{"id":"t1","name":"The Coven","posterCutoutUrl":null,"bannerUrl":null,
          "members":[{"id":"m1","name":"Jinx","posterCutoutUrl":"https://cdn/jinx.png"}],
          "posterArt":[{"id":"a3","kind":"COMMISSIONED","status":"READY","orientation":"PORTRAIT","url":"https://cdn/art.png","artistName":"Kiki"},
                       {"id":"a4","kind":"BACKGROUND","status":"GENERATING","orientation":"PORTRAIT","url":null,"artistName":null}]}}}}
        """#) }
    let pack = try #require(try await backstage(stub).personShare(id: "t1"))
    #expect(pack.performers.map(\.id) == ["m1"])
    #expect(pack.artistPoster?.artistName == "Kiki")
    #expect(pack.art.map(\.id) == ["a3"])
    #expect(pack.link == nil)
    #expect(pack.caption() == "The Coven\nwith Jinx")
}
