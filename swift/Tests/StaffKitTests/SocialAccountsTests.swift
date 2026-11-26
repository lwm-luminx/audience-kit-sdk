import Foundation
import Testing
import AudienceKit
import StaffKitCore
import StaffKitServices

private func socialAccounts(_ stub: Stub) -> SocialAccountsClient {
    SocialAccountsClient(session: AudienceManagementSession(baseURL: stub.baseURL, credentialStore: InMemoryCredentialStore(credential: makeCredential(audienceID: "audience", on: stub.baseURL)), session: stub.session))
}

@Test func aListingsAccountsSayWhatIsLinked() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"""
        {"data":{"people":{"person":{"socialAccounts":[
          {"id":"f1","provider":"facebook","handle":"1480867398434400","name":"The Demo Room","profileUrl":null,"connected":true,
           "connectedAt":"2026-11-26T21:30:00Z","connectedByName":"Rick M.","lastError":null},
          {"id":"i1","provider":"instagram","handle":"anyabacon","name":null,"profileUrl":"https://instagram.com/anyabacon","connected":false,
           "connectedAt":null,"connectedByName":null,"lastError":null}]}}}}
        """#) }
    let accounts = try await socialAccounts(stub).accounts(of: .person(id: "p1"))
    #expect(accounts.isLinked("facebook"))
    #expect(!accounts.isLinked("instagram"))
    #expect(accounts.facebook?.displayName == "The Demo Room")
    #expect(accounts.instagram?.displayName == "@anyabacon")
    #expect(accounts.instagramHint?.contains("professional account") == true)
    let body = try #require(stub.requests.last).jsonBody()
    #expect((body["query"] as? String)?.contains("people { person(id: $id) { socialAccounts") == true)
    #expect((body["variables"] as? [String: Any])?["id"] as? String == "p1")
}

@Test func linkingFacebookSendsTheCodeForTheAPIToExchange() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"""
        {"data":{"connectSocialFacebook":{"accounts":[
          {"id":"f1","provider":"facebook","handle":"anyabacon","name":"Anya Bacon","profileUrl":null,"connected":true,"connectedAt":null,"connectedByName":null,"lastError":null},
          {"id":"i1","provider":"instagram","handle":"anyabacon","name":"Anya","profileUrl":null,"connected":true,"connectedAt":null,"connectedByName":null,"lastError":null}]}}}
        """#) }
    let accounts = try await socialAccounts(stub).linkFacebook(.person(id: "p1"), code: "the-code",
                                                              redirectURI: "fb713525445368431://authorize/",
                                                              facebookAppID: "713525445368431")
    #expect(accounts.isLinked("instagram"))
    #expect(accounts.instagramHint == nil)
    let input = try #require(((try #require(stub.requests.last).jsonBody()["variables"] as? [String: Any])?["input"]) as? [String: Any])
    #expect(input["ownerId"] as? String == "p1")
    #expect(input["facebookCode"] as? String == "the-code")
    #expect(input["redirectUri"] as? String == "fb713525445368431://authorize/")
    #expect(input["facebookAppId"] as? String == "713525445368431")
    #expect(input["pageId"] == nil)
}

@Test func unlinkingNamesTheOwnerAndTheAccount() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"""
        {"data":{"disconnectSocialAccount":{"accounts":[
          {"id":"i1","provider":"instagram","handle":"milkplus","name":null,"profileUrl":null,"connected":false,"connectedAt":null,"connectedByName":null,"lastError":null}]}}}
        """#) }
    let account = LinkedSocialAccount(id: "i1", provider: "instagram", handle: "milkplus", connected: true)
    let accounts = try await socialAccounts(stub).unlink(account, of: .venue(id: "v1"))
    #expect(!accounts.isLinked("instagram"))
    let input = try #require(((try #require(stub.requests.last).jsonBody()["variables"] as? [String: Any])?["input"]) as? [String: Any])
    #expect(input["ownerId"] as? String == "v1")
    #expect(input["id"] as? String == "i1")
}

@Test func onlyPlatformsWithAPublishingConfigurationLinkPages() {
    #expect(ManagementPlatform.production.canLinkSocialAccounts)
    #expect(ManagementPlatform.production.facebookPublishLoginConfigurationID == "1658512575778916")
    #expect(!ManagementPlatform.next.canLinkSocialAccounts)
}

@Test func linkingOpensTheDialogWithThePublishingConfiguration() {
    let flow = FacebookOAuth(appID: "713525445368431", configurationID: ManagementPlatform.production.facebookPublishLoginConfigurationID)
    let items = URLComponents(url: flow.authorizationURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
    #expect(items.first(where: { $0.name == "config_id" })?.value == "1658512575778916")
    #expect(items.first(where: { $0.name == "scope" }) == nil)
}
