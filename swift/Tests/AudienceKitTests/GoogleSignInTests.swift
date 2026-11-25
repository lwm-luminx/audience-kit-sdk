import Foundation
import Testing
@testable import AudienceCore
@testable import AudienceKit

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private let device = DeviceDescription(identifier: "device-1", model: "iPhone17,1", version: "2.0", build: "42")
private let iosClient = "123-abc.apps.googleusercontent.com"
private let serverClient = "123-server.apps.googleusercontent.com"

private func googleClient(_ stub: Stub, token: String? = nil) -> AudienceKitClient {
    let configuration = AudienceKitConfiguration(baseURL: stub.baseURL, host: "hotmess.social", audienceID: "a-1")
    let base = stub.baseURL.absoluteString
    let store = InMemoryCredentialStore(credential: token.map {
        Credential(token: $0, userId: "u-1", audienceId: "a-1", role: "member",
                   endpoint: URL(string: "\(base)/v1/audiences/a-1/graphql")!)
    })
    return AudienceKitClient(configuration: configuration, credentialStore: store, session: stub.session,
                             deviceAttestor: nil)
}

private func googleTokenJSON(_ request: RecordedRequest, userId: String = "u-2") -> String {
    let base = "\(request.url.scheme!)://\(request.url.host!)"
    return #"{"token":"jwt-g","userId":"\#(userId)","audienceId":"a-1","role":"member","endpoint":"\#(base)/v1/audiences/a-1/graphql","venueDeviceId":null,"expiresAt":null}"#
}

private func formFields(_ request: RecordedRequest) -> [String: String] {
    let body = String(data: request.body ?? Data(), encoding: .utf8) ?? ""
    var components = URLComponents()
    components.percentEncodedQuery = body
    return Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
}

@Suite struct GoogleSignInTests {
    @Test func buildsGooglesConsentURLWithPKCE() throws {
        let client = GoogleOAuthClient(clientID: iosClient, serverClientID: serverClient)
        let authorization = client.authorization(scopes: ["openid", "email", GoogleOAuthClient.emailsScope],
                                                 verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk",
                                                 state: "s-1")

        #expect(client.callbackScheme == "com.googleusercontent.apps.123-abc")
        #expect(client.redirectURI == "com.googleusercontent.apps.123-abc:/oauth2redirect")
        #expect(client.isConfigured)
        let components = try #require(URLComponents(url: authorization.authorizeURL, resolvingAgainstBaseURL: false))
        #expect(components.host == "accounts.google.com")
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })
        #expect(items["client_id"] == iosClient)
        #expect(items["redirect_uri"] == client.redirectURI)
        #expect(items["response_type"] == "code")
        #expect(items["scope"] == "openid email \(GoogleOAuthClient.emailsScope)")
        #expect(items["state"] == "s-1")
        #expect(items["audience"] == serverClient)
        #expect(items["code_challenge_method"] == "S256")
        // RFC 7636 appendix B's example.
        #expect(items["code_challenge"] == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test func randomTokensAreLongEnoughForPKCE() {
        let token = GoogleAuthorization.randomToken()
        #expect(token.count == 43)
        #expect(!token.contains("=") && !token.contains("+") && !token.contains("/"))
        #expect(token != GoogleAuthorization.randomToken())
    }

    @Test func unconfiguredClientsSaySo() {
        #expect(!GoogleOAuthClient(clientID: "").isConfigured)
        #expect(!GoogleOAuthClient(clientID: "$(GOOGLE_IOS_CLIENT_ID)").isConfigured)
        #expect(GoogleOAuthClient(clientID: iosClient, serverClientID: "").serverClientID == nil)
    }

    @Test func readsGooglesRedirect() throws {
        let authorization = GoogleOAuthClient(clientID: iosClient).authorization(verifier: "v", state: "s-1")
        let scheme = "com.googleusercontent.apps.123-abc:/oauth2redirect"
        #expect(authorization.answer(from: URL(string: "\(scheme)?code=c-1&state=s-1")!) == .code("c-1"))
        #expect(authorization.answer(from: URL(string: "\(scheme)?error=access_denied&state=s-1")!) == .cancelled)
        #expect(authorization.answer(from: URL(string: "\(scheme)?code=c-1&state=other")!)
            == .failed(message: "Google's answer wasn't for this sign-in."))
        #expect(authorization.answer(from: URL(string: "\(scheme)?error=invalid_request&error_description=Bad")!)
            == .failed(message: "Bad"))
        #expect(authorization.answer(from: URL(string: "hotmess://callback?code=c-1&state=s-1")!) == nil)
    }

    @Test func signsInWithAGoogleIDToken() async throws {
        let stub = Stub { request in .json(status: 200, body: googleTokenJSON(request)) }
        let client = googleClient(stub)

        let result = try await client.signIn(googleIDToken: "id-jwt", accessToken: "access-1", name: "Ada",
                                             device: device)

        #expect(result.userId == "u-2")
        let request = try #require(stub.requests.first)
        #expect(request.path == "/v1/token/google")
        #expect(request.header("Authorization") == nil)
        let body = try request.jsonBody()
        #expect(body["id_token"] as? String == "id-jwt")
        #expect(body["access_token"] as? String == "access-1")
        #expect(body["name"] as? String == "Ada")
        #expect(body["host"] as? String == "hotmess.social")
        #expect(body["connect"] == nil)
        #expect(try await client.credential()?.token == "jwt-g")
    }

    @Test func connectsGoogleWithTheCurrentSession() async throws {
        let stub = Stub { request in .json(status: 200, body: googleTokenJSON(request, userId: "u-1")) }
        let client = googleClient(stub, token: "jwt-1")

        try await client.connectGoogle(idToken: "id-jwt", device: device)

        let request = try #require(stub.requests.first)
        #expect(request.path == "/v1/token/google")
        #expect(request.header("Authorization") == "Bearer jwt-1")
        #expect(try request.jsonBody()["connect"] as? Bool == true)
    }

    @Test func aRefusedConnectionKeepsTheSession() async throws {
        let stub = Stub { _ in .json(status: 400, body: #"{"error":"INVALID","message":"That Google account has its own Facebook."}"#) }
        let client = googleClient(stub, token: "jwt-1")

        await #expect(throws: AudienceKitError.signInFailed(message: "That Google account has its own Facebook.")) {
            try await client.connectGoogle(idToken: "id-jwt", device: device)
        }
        #expect(try await client.credential()?.token == "jwt-1")
    }

    @Test func tradesGooglesCodeThenSignsIn() async throws {
        let stub = Stub { request in
            if request.path == "/token" {
                return .json(status: 200, body: #"{"id_token":"id-jwt","access_token":"access-1","scope":"openid \#(GoogleOAuthClient.emailsScope)","token_type":"Bearer"}"#)
            }
            return .json(status: 200, body: googleTokenJSON(request))
        }
        let client = googleClient(stub)
        let google = GoogleOAuthClient(clientID: iosClient, serverClientID: serverClient,
                                       tokenEndpoint: stub.baseURL.appendingPathComponent("token"))
        let authorization = google.authorization(verifier: "verifier-1", state: "s-1")

        let result = try await client.signIn(
            google: authorization, callbackURL: URL(string: "\(google.redirectURI)?code=c%2F1&state=s-1")!,
            device: device)

        #expect(result?.userId == "u-2")
        let exchange = try #require(stub.requests.first)
        #expect(exchange.method == "POST")
        #expect(exchange.header("Content-Type") == "application/x-www-form-urlencoded")
        let form = formFields(exchange)
        #expect(form["code"] == "c/1")
        #expect(form["code_verifier"] == "verifier-1")
        #expect(form["client_id"] == iosClient)
        #expect(form["grant_type"] == "authorization_code")
        #expect(form["redirect_uri"] == google.redirectURI)
        #expect(form["audience"] == serverClient)
        let signIn = try #require(stub.requests.last)
        #expect(signIn.path == "/v1/token/google")
        #expect(try signIn.jsonBody()["access_token"] as? String == "access-1")
    }

    @Test func leavesOutAnAccessTokenThatCantReadEmails() async throws {
        let stub = Stub { request in
            if request.path == "/token" {
                return .json(status: 200, body: #"{"id_token":"id-jwt","access_token":"access-1","scope":"openid email"}"#)
            }
            return .json(status: 200, body: googleTokenJSON(request))
        }
        let client = googleClient(stub)
        let google = GoogleOAuthClient(clientID: iosClient, tokenEndpoint: stub.baseURL.appendingPathComponent("token"))
        let authorization = google.authorization(verifier: "v", state: "s")

        try await client.signIn(google: authorization, callbackURL: URL(string: "\(google.redirectURI)?code=c&state=s")!,
                                device: device)

        let signIn = try #require(stub.requests.last)
        #expect(try signIn.jsonBody()["access_token"] == nil)
    }

    @Test func cancellingOnGooglesPageSignsNobodyIn() async throws {
        let stub = Stub { _ in .json(status: 500, body: "{}") }
        let client = googleClient(stub)
        let google = GoogleOAuthClient(clientID: iosClient)
        let authorization = google.authorization(verifier: "v", state: "s")

        let result = try await client.signIn(
            google: authorization, callbackURL: URL(string: "\(google.redirectURI)?error=access_denied&state=s")!,
            device: device)

        #expect(result == nil)
        #expect(stub.requests.isEmpty)
    }

    @Test func googleRefusingTheCodeSaysWhy() async throws {
        let stub = Stub { _ in .json(status: 400, body: #"{"error":"invalid_grant","error_description":"Bad Request"}"#) }
        let client = googleClient(stub)
        let google = GoogleOAuthClient(clientID: iosClient, tokenEndpoint: stub.baseURL.appendingPathComponent("token"))
        let authorization = google.authorization(verifier: "v", state: "s")

        await #expect(throws: AudienceKitError.signInFailed(message: "Bad Request")) {
            try await client.signIn(google: authorization,
                                    callbackURL: URL(string: "\(google.redirectURI)?code=c&state=s")!, device: device)
        }
        #expect(stub.requests.count == 1)
    }
}
