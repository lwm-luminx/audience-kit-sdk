import Foundation
import Testing
import AudienceKit
@testable import StaffKitCore
@testable import StaffKitServices

// Velvet Display's Developer ID build signs in with Apple through a browser, the way the Android staff apps do.

private func flow() -> AppleWebOAuth {
    AppleWebOAuth(clientID: AppleWebOAuth.clientID(for: .production), apiBaseURL: URL(string: "https://api.test/")!,
                  package: "com.audiencekit.Velvet", random: "r4nd0m", nonce: "abc")
}

@Test func theAuthorizationURLAsksAppleToPostToTheAPIWithTheNonceHashed() throws {
    let url = flow().authorizationURL
    let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
    func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
    #expect(url.host == "appleid.apple.com")
    #expect(url.path == "/auth/authorize")
    #expect(value("client_id") == "com.audiencekit.admin")
    #expect(value("redirect_uri") == "https://api.test/v1/token/apple/callback")
    #expect(value("response_type") == "code id_token")
    #expect(value("response_mode") == "form_post")
    #expect(value("scope") == "name email")
    #expect(value("state") == "com.audiencekit.Velvet~r4nd0m")
    // SHA-256("abc")
    #expect(value("nonce") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
}

@Test func nextSignsInWithTheNextServicesID() {
    #expect(AppleWebOAuth.clientID(for: .staging) == "com.audiencekit.admin.next")
}

@Test func theAnswerIsReadFromTheIntentRedirect() throws {
    let callback = try #require(URL(string: "intent://callback?code=c0de&first_name=Rick&id_token=jwt.one.two&last_name=M&state=com.audiencekit.Velvet~r4nd0m#Intent;scheme=audiencekit-apple;package=com.audiencekit.Velvet;end"))
    let answer = try flow().answer(from: callback)
    #expect(answer.identityToken == "jwt.one.two")
    #expect(answer.authorizationCode == "c0de")
    #expect(answer.firstName == "Rick")
    #expect(answer.lastName == "M")
}

@Test func anAnswerForAnotherSignInIsRefused() throws {
    let callback = try #require(URL(string: "intent://callback?id_token=jwt&state=com.audiencekit.Velvet~other"))
    #expect(throws: AppleWebOAuth.OAuthError.invalidCallback) { try flow().answer(from: callback) }
}

@Test func cancellingAtAppleIsToldApartFromARefusal() throws {
    let cancelled = try #require(URL(string: "intent://callback?error=user_cancelled_authorize&state=com.audiencekit.Velvet~r4nd0m"))
    #expect(throws: AppleWebOAuth.OAuthError.cancelled) { try flow().answer(from: cancelled) }
    let refused = try #require(URL(string: "intent://callback?error=invalid_client&state=com.audiencekit.Velvet~r4nd0m"))
    #expect(throws: AppleWebOAuth.OAuthError.refused("invalid_client")) { try flow().answer(from: refused) }
}

@Test func aBrowserAppleSignInSendsTheNonceAndKeepsTheSession() async throws {
    let stub = Stub { request in
        .json(status: 200, body: tokenJSON(makeCredential(token: "apple-web-token", on: request.url)))
    }
    let store = InMemoryCredentialStore()
    let session = AudienceManagementSession(baseURL: stub.baseURL, environment: .staging, credentialStore: store,
                                            session: stub.session)
    try await session.signIn(appleIdentityToken: "jwt", nonce: "abc", authorizationCode: "c0de",
                             redirectURI: "https://api.test/v1/token/apple/callback", firstName: "Rick",
                             device: DeviceDescription(identifier: "mac-1", model: "Mac16,1", version: "1.0", build: "1"))
    let request = try #require(stub.requests.last)
    #expect(request.method == "POST")
    #expect(request.path == "/v1/token/apple")
    #expect(request.header("Authorization") == nil)
    let body = try request.jsonBody()
    #expect(body["identity_token"] as? String == "jwt")
    #expect(body["nonce"] as? String == "abc")
    #expect(body["authorization_code"] as? String == "c0de")
    #expect(body["redirect_uri"] as? String == "https://api.test/v1/token/apple/callback")
    #expect(body["first_name"] as? String == "Rick")
    #expect(body["last_name"] == nil)
    #expect(try store.load()?.token == "apple-web-token")
}
