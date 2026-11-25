import Foundation
import Testing
import StaffKitCore

@Test func businessLoginUsesConfigurationWithoutOverridingPermissions() {
    let flow = FacebookOAuth(appID: "713525445368431", configurationID: "4085560021745660")
    let items = URLComponents(url: flow.authorizationURL, resolvingAgainstBaseURL: false)!.queryItems!
    #expect(items.contains(URLQueryItem(name: "config_id", value: "4085560021745660")))
    #expect(!items.contains { $0.name == "scope" })
    #expect(items.contains(URLQueryItem(name: "response_type", value: "code")))
    #expect(items.contains(URLQueryItem(name: "redirect_uri", value: flow.redirectURI)))
}

@Test func rejectsForgedOAuthCallbacks() throws {
    let flow = FacebookOAuth(appID: "915436455177328", state: "expected-state")
    #expect(try flow.code(from: URL(string: "fb915436455177328://authorize?state=expected-state&code=valid")!) == "valid")
    for callback in [
        "fb915436455177328://authorize?state=wrong&code=valid",
        "fb915436455177328://authorize?state=expected-state&state=wrong&code=valid",
        "fb915436455177328://elsewhere?state=expected-state&code=valid",
        "fb713525445368431://authorize?state=expected-state&code=valid",
        "fb915436455177328://authorize?state=expected-state&code=",
        "fb915436455177328://authorize?state=expected-state&code=a&code=b"
    ] { #expect(throws: FacebookOAuth.OAuthError.self) { try flow.code(from: URL(string: callback)!) } }
}

@Test func loginUsesTestAppAndCodeExchange() {
    let flow = FacebookOAuth(appID: "915436455177328", state: "expected")
    let items = URLComponents(url: flow.authorizationURL, resolvingAgainstBaseURL: false)!.queryItems!
    #expect(items.contains(URLQueryItem(name: "client_id", value: "915436455177328")))
    #expect(items.contains(URLQueryItem(name: "response_type", value: "code")))
    #expect(items.contains(URLQueryItem(name: "scope", value: "public_profile")))
    #expect(items.contains(URLQueryItem(name: "redirect_uri", value: flow.redirectURI)))
}

@Test func sharedAppCallbacksRequireTheirOwnSessionState() throws {
    let appID = "713525445368431"
    let flows = ["focus", "velvet", "backstage"].map { FacebookOAuth(appID: appID, state: "\($0)-state") }
    for flow in flows {
        #expect(flow.redirectURI == "fb713525445368431://authorize/")
        let callback = URL(string: "\(flow.redirectURI)?state=\(flow.state)&code=valid")!
        #expect(try flow.code(from: callback) == "valid")
        for other in flows where other.state != flow.state {
            #expect(throws: FacebookOAuth.OAuthError.self) { try other.code(from: callback) }
        }
    }
}

@Test func instagramSignInSendsOnlyTheVerifiersHash() {
    let flow = InstagramOAuth(baseURL: URL(string: "https://api.next.audiencekit.com")!, app: "com.audiencekit.Backstage",
                              verifier: "abc")
    let url = flow.authorizationURL
    #expect(url.absoluteString.hasPrefix("https://api.next.audiencekit.com/v1/token/instagram/authorize?"))
    let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
    #expect(items.contains(URLQueryItem(name: "platform", value: "ios")))
    #expect(items.contains(URLQueryItem(name: "app", value: "com.audiencekit.Backstage")))
    #expect(items.contains(URLQueryItem(name: "challenge",
                                        value: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")))
    #expect(!url.absoluteString.contains("=abc"))
}

@Test func instagramCallbackGivesTheTicketOrWhyNot() throws {
    #expect(try InstagramOAuth.ticket(from: URL(string: "audiencekit-instagram://callback?ticket=t1")!) == "t1")
    #expect(throws: InstagramOAuth.OAuthError.declined) {
        try InstagramOAuth.ticket(from: URL(string: "audiencekit-instagram://callback?error=access_denied")!)
    }
    #expect(throws: InstagramOAuth.OAuthError.failed("Nope")) {
        try InstagramOAuth.ticket(from: URL(string: "audiencekit-instagram://callback?error=sign_in_failed&error_description=Nope")!)
    }
    #expect(throws: InstagramOAuth.OAuthError.invalidCallback) {
        try InstagramOAuth.ticket(from: URL(string: "audiencekit-apple://callback?ticket=t1")!)
    }
}
