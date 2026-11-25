import Foundation
import Testing
import AudienceKit
import StaffKitCore
import StaffKitServices

@Test func audienceSwitchUsesNewTokenAndKeepsTestEnvironment() async throws {
    let stub = Stub { request in
        if request.path == "/v1/admin/choices" && request.method == "GET" {
            return .json(status: 200, body: #"{"choices":[{"kind":"audience","allowed":true,"audience":{"id":"venue-audience","name":"Test","subdomain":"test"}},{"kind":"audience","allowed":false,"audience":{"id":"blocked","name":"Blocked","subdomain":"blocked"}}]}"#)
        }
        if request.path == "/v1/admin/choices" {
            return .json(status: 200, body: tokenJSON(makeCredential(token: "selected-token", audienceID: "venue-audience", on: request.url)))
        }
        return .json(status: 200, body: #"{"data":{"me":{"cover":{"doorVenues":{"nodes":[]}}}}}"#)
    }
    let store = InMemoryCredentialStore(credential: makeCredential(token: "initial-token"))
    let focus = AudienceManagementSession(baseURL: stub.baseURL, environment: .staging,
                            credentialStore: store, session: stub.session)
    let choices = try await focus.choices()
    #expect(choices.count == 1)
    let audience = try #require(choices.first?.audience)
    try await focus.choose(audience)
    #expect(try store.load()?.token == "selected-token")
    let venues = try await VenueManagementClient(session: focus).venues()
    #expect(venues.isEmpty)
    let last = try #require(stub.requests.last)
    #expect(last.path == "/v1/audience/venue-audience/staffql")
    #expect(last.header("Authorization") == "Bearer selected-token")
    #expect(last.header("X-AudienceKit-Environment") == "staging")
}

@Test func openingAnAudienceAlongsideKeepsTheSessionItWasOpenedFrom() async throws {
    let stub = Stub { request in
        if request.path == "/v1/admin/choices" {
            return .json(status: 200, body: tokenJSON(makeCredential(token: "hack-token", audienceID: "hack", on: request.url)))
        }
        return .json(status: 200, body: #"{"data":{"me":{"cover":{"doorVenues":{"nodes":[]}}}}}"#)
    }
    let store = InMemoryCredentialStore(credential: makeCredential(token: "hot-mess-token", audienceID: "hot-mess"))
    let own = AudienceManagementSession(baseURL: stub.baseURL, environment: .staging, credentialStore: store,
                                        session: stub.session)
    let hackStore = InMemoryCredentialStore()
    let hackAudience = InMemoryAudienceStore()
    let hack = ManagedAudience(id: "hack", name: "Hack Different", subdomain: "hackdifferent")

    let alongside = try await own.openAlongside(hack, credentialStore: hackStore, audienceStore: hackAudience)

    let choose = try #require(stub.requests.last)
    #expect(choose.method == "POST")
    let body = try choose.jsonBody()
    #expect(body["audience_id"] as? String == "hack")
    #expect(body["alongside"] as? Bool == true)
    #expect(try store.load()?.token == "hot-mess-token")
    #expect(try hackStore.load()?.token == "hack-token")
    #expect(try hackAudience.load() == hack)
    #expect(await alongside.boundAudienceID == "hack")
    _ = try await VenueManagementClient(session: alongside).venues()
    let last = try #require(stub.requests.last)
    #expect(last.path == "/v1/audience/hack/staffql")
    #expect(last.header("Authorization") == "Bearer hack-token")
}

@Test func rejectedSessionIsForgotten() async throws {
    let stub = Stub { _ in .json(status: 401, body: "{}") }
    let store = InMemoryCredentialStore(credential: makeCredential(token: "expired"))
    let focus = AudienceManagementSession(baseURL: stub.baseURL, credentialStore: store, session: stub.session)
    await #expect(throws: AudienceKitError.unauthorized) { try await focus.choices() }
    #expect(try store.load() == nil)
}

@Test func aRejectedSessionTellsTheAppOnceAndForgetsTheAudience() async throws {
    let stub = Stub { _ in .json(status: 401, body: "{}") }
    let store = InMemoryCredentialStore(credential: makeCredential(audienceID: "test-audience", on: stub.baseURL))
    let audiences = InMemoryAudienceStore(audience: ManagedAudience(id: "test-audience", name: "Test", subdomain: "test"))
    let focus = AudienceManagementSession(baseURL: stub.baseURL, credentialStore: store, audienceStore: audiences,
                                          session: stub.session)
    var ended = focus.sessionsEnded.makeAsyncIterator()
    await #expect(throws: AudienceKitError.unauthorized) {
        try await VenueManagementClient(session: focus).venues()
    }
    #expect(await ended.next() != nil)
    #expect(try store.load() == nil)
    #expect(try audiences.load() == nil)
    // Signed out now: nothing more reaches the API, so nothing more reports an ending.
    await #expect(throws: AudienceKitError.notSignedIn) { try await focus.choices() }
    #expect(stub.requests.count == 1)
}

@Test func forbiddenAndRefusedCodesAreNotSessionEndings() async throws {
    let stub = Stub { request in
        request.path == "/v1/admin/review_login" ? .json(status: 401, body: "{}") : .json(status: 403, body: "{}")
    }
    let store = InMemoryCredentialStore(credential: makeCredential(token: "staff-token"))
    let focus = AudienceManagementSession(baseURL: stub.baseURL, credentialStore: store, session: stub.session)
    await #expect(throws: AudienceKitError.forbidden) { try await focus.choices() }
    await #expect(throws: AudienceKitError.signInFailed(message: "That App Review code isn’t valid or has expired.")) {
        try await focus.signIn(reviewCode: "nope", device: DeviceDescription(identifier: "device"))
    }
    #expect(try store.load()?.token == "staff-token")
}

@Test func aSocketRefusalEndsOnlyTheTokenItRefused() async throws {
    let stub = Stub { _ in .json(status: 200, body: "{}") }
    let store = InMemoryCredentialStore(credential: makeCredential(token: "current-token"))
    let focus = AudienceManagementSession(baseURL: stub.baseURL, credentialStore: store, session: stub.session)
    await focus.sessionRejected(token: "older-token")
    #expect(try store.load()?.token == "current-token")
    var ended = focus.sessionsEnded.makeAsyncIterator()
    await focus.sessionRejected(token: "current-token")
    #expect(await ended.next() != nil)
    #expect(try store.load() == nil)
}

@Test func venueEditSurfacesAuthorizationFailure() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"{"errors":[{"message":"You can only change your own listing"}]}"#) }
    let store = InMemoryCredentialStore(credential: makeCredential(audienceID: "test-audience", on: stub.baseURL))
    let focus = AudienceManagementSession(baseURL: stub.baseURL, credentialStore: store, session: stub.session)
    await #expect(throws: AudienceKitError.self) {
        try await VenueManagementClient(session: focus).updateVenue(id: "venue", name: "Name", description: "Details", website: "")
    }
    let request = try #require(stub.requests.last)
    let variables = try request.jsonBody()["variables"] as? [String: Any]
    let input = variables?["input"] as? [String: Any]
    let venue = input?["venue"] as? [String: Any]
    #expect(venue?["name"] as? String == "Name")
    #expect(venue?["hidden"] == nil)
}

@Test func backstageUsesFocusSession() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{"updatePerson":{"person":{"id":"performer","name":"Updated"}}}}"#) }
    let store = InMemoryCredentialStore(credential: makeCredential(audienceID: "test-audience", on: stub.baseURL))
    let focus = AudienceManagementSession(baseURL: stub.baseURL, credentialStore: store, session: stub.session)
    let person = try await TalentManagementClient(session: focus).updateName(personID: "performer", name: "Updated")
    #expect(person.name == "Updated")
    #expect(stub.requests.last?.path == "/v1/audience/test-audience/staffql")
}

@Test func nativeFacebookTokenUsesManagementAppAndStoresSession() async throws {
    let stub = Stub { _ in .json(status: 200, body: tokenJSON(makeCredential(token: "native-session"))) }
    let store = InMemoryCredentialStore()
    let focus = AudienceManagementSession(baseURL: stub.baseURL, environment: .staging, credentialStore: store, session: stub.session)
    try await focus.signIn(accessToken: "native-facebook-token", device: DeviceDescription(identifier: "device"))
    let request = try #require(stub.requests.last)
    let body = try request.jsonBody()
    #expect(request.path == "/v1/token")
    #expect(request.header("X-AudienceKit-Environment") == "staging")
    #expect(body["facebook_token"] as? String == "native-facebook-token")
    #expect(body["facebook_app_id"] as? String == "915436455177328")
    #expect(body["host"] as? String == "admin.next.audiencekit.com")
    #expect(body["code"] == nil)
    #expect(try store.load()?.token == "native-session")
}

@Test func webFallbackExchangesTheExactDialogRedirect() async throws {
    let flow = FacebookOAuth(appID: "713525445368431", configurationID: "4085560021745660", state: "test-state")
    let dialogRedirect = try #require(URLComponents(url: flow.authorizationURL,
        resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "redirect_uri" }?.value)
    #expect(dialogRedirect == "fb713525445368431://authorize/")
    let callback = try #require(URL(string: dialogRedirect + "?code=returned-code&state=test-state"))
    let stub = Stub { _ in .json(status: 200, body: tokenJSON(makeCredential(token: "web-session"))) }
    let focus = AudienceManagementSession(baseURL: stub.baseURL, session: stub.session)
    try await focus.signIn(code: flow.code(from: callback), redirectURI: flow.redirectURI,
                           device: DeviceDescription(identifier: "device"))
    let body = try #require(stub.requests.last).jsonBody()
    #expect(body["redirect_uri"] as? String == dialogRedirect)
    #expect(body["code"] as? String == "returned-code")
}

@Test func eachEnvironmentSignsInToItsOwnPlatform() {
    #expect(ManagementPlatform.for(.production).baseURL.absoluteString == "https://api.audiencekit.com")
    #expect(ManagementPlatform.for(.production).facebookAppID == "713525445368431")
    #expect(ManagementPlatform.for(.staging).baseURL.absoluteString == "https://api.next.audiencekit.com")
    #expect(ManagementPlatform.for(.staging).host == "admin.next.audiencekit.com")
    #expect(ManagementPlatform.for(.staging).facebookLoginConfigurationID == "1489636529653307")
}

@Test func facebookAppRedirectCarriesTheCodeInTheFragment() throws {
    let flow = FacebookOAuth(appID: "915436455177328", configurationID: "1489636529653307", state: "test-state")
    let callback = try #require(URL(string: "fb915436455177328://authorize#code=app-code&granted_scopes=public_profile&state=test-state"))
    #expect(try flow.code(from: callback) == "app-code")
    let forged = try #require(URL(string: "fb915436455177328://authorize#code=app-code&state=other-state"))
    #expect(throws: FacebookOAuth.OAuthError.invalidCallback) { try flow.code(from: forged) }
    let declined = try #require(URL(string: "fb915436455177328://authorize#error=access_denied&state=test-state"))
    #expect(throws: FacebookOAuth.OAuthError.declined) { try flow.code(from: declined) }
}

@Test func aRedirectThatReachedTheWrongAppIsSentOnToTheAppThatAsked() throws {
    let flow = FacebookOAuth(appID: "915436455177328", configurationID: "1489636529653307",
                             returnScheme: "audiencekit-backstage")
    #expect(flow.redirectURI == "fb915436455177328://authorize/")
    #expect(flow.state.hasPrefix("audiencekit-backstage."))
    let redirect = try #require(URL(string: "fb915436455177328://authorize#code=app-code&state=\(flow.state)"))

    // Velvet got it: it goes on to Backstage, which takes it.
    let forwarded = try #require(FacebookOAuth.forwardingURL(for: redirect, appID: "915436455177328",
                                                             ownScheme: "audiencekit-velvet"))
    #expect(forwarded.absoluteString == "audiencekit-backstage://authorize#code=app-code&state=\(flow.state)")
    #expect(try flow.code(from: forwarded) == "app-code")
    // Backstage got it itself, or it names no app: nothing to send on.
    #expect(FacebookOAuth.forwardingURL(for: redirect, appID: "915436455177328", ownScheme: "audiencekit-backstage") == nil)
    let plain = try #require(URL(string: "fb915436455177328://authorize#code=app-code&state=1234"))
    #expect(FacebookOAuth.forwardingURL(for: plain, appID: "915436455177328", ownScheme: "audiencekit-velvet") == nil)
    // Only to one of our apps.
    let elsewhere = try #require(URL(string: "fb915436455177328://authorize#code=app-code&state=evil.1234"))
    #expect(FacebookOAuth.forwardingURL(for: elsewhere, appID: "915436455177328", ownScheme: "audiencekit-velvet") == nil)
}

@Test func signInRetriesOnceWhenTheConnectionWasLost() async throws {
    let attempts = Counter()
    let stub = Stub { _ in
        attempts.increment() == 1 ? .failure(URLError(.networkConnectionLost))
            : .json(status: 200, body: tokenJSON(makeCredential(token: "retried-session")))
    }
    let store = InMemoryCredentialStore()
    let focus = AudienceManagementSession(baseURL: stub.baseURL, credentialStore: store, session: stub.session)
    try await focus.signIn(code: "app-code", redirectURI: "fb713525445368431://authorize/",
                           device: DeviceDescription(identifier: "device"))
    #expect(stub.requests.count == 2)
    #expect(try store.load()?.token == "retried-session")
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func increment() -> Int { lock.withLock { value += 1; return value } }
}

@Test func appStoreInstallsNeverOfferTheReviewCode() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"{"enabled":true}"#) }
    let focus = AudienceManagementSession(baseURL: stub.baseURL, credentialStore: InMemoryCredentialStore(),
                                          session: stub.session)
    #expect(await !focus.reviewCodeAvailable(installSource: .appStore))
    #expect(stub.requests.isEmpty)
    #expect(await focus.reviewCodeAvailable(installSource: .testFlight))
    #expect(stub.requests.count == 1)
}

@Test func reviewSignInSendsTheAppTransaction() async throws {
    let stub = Stub { _ in .json(status: 403, body: #"{"error":"FORBIDDEN","reason":"store_install"}"#) }
    let focus = AudienceManagementSession(baseURL: stub.baseURL, credentialStore: InMemoryCredentialStore(),
                                          session: stub.session)
    await #expect(throws: AudienceKitError.self) {
        try await focus.signIn(reviewCode: "code", device: DeviceDescription(identifier: "device"),
                               appTransaction: "signed.jws")
    }
    let body = try #require(stub.requests.first).jsonBody()
    #expect(body["app_transaction"] as? String == "signed.jws")
    #expect(body["code"] as? String == "code")
}
