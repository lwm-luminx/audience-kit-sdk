import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// An app's Google OAuth client, for Sign in with Google without Google's SDK: the app opens
/// ``GoogleAuthorization/authorizeURL`` in `ASWebAuthenticationSession`, Google sends the browser back to
/// ``redirectURI`` with a code, and ``AudienceSession/signIn(google:callbackURL:device:)`` trades the code (with the
/// PKCE verifier that never left the device) for Google's ID token, then the ID token for an AudienceKit session
/// (`POST /v1/token/google`).
///
/// `clientID` is the app's **iOS** OAuth client from the Google Cloud project (its bundle ID registered there); the
/// redirect goes to its reversed client ID, a URL scheme that needs no `CFBundleURLTypes` entry, since the
/// authentication session catches it. `serverClientID` is the project's **web** ("server") client, the one Android's
/// Credential Manager uses: Google then issues the ID token for it, so the API, which accepts that client
/// (`google.client_ids`), doesn't need the iOS client listed too.
public struct GoogleOAuthClient: Sendable, Hashable {
    /// The Google account's other verified emails, so the API can match an existing account by any of them
    /// (`access_token` in `POST /v1/token/google`).
    public static let emailsScope = "https://www.googleapis.com/auth/user.emails.read"
    public static let defaultScopes = ["openid", "email", "profile"]

    public let clientID: String
    public let serverClientID: String?
    public let authorizationEndpoint: URL
    public let tokenEndpoint: URL

    public init(clientID: String, serverClientID: String? = nil,
                authorizationEndpoint: URL = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!,
                tokenEndpoint: URL = URL(string: "https://oauth2.googleapis.com/token")!)
    {
        self.clientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.serverClientID = serverClientID.flatMap { $0.isEmpty ? nil : $0 }
        self.authorizationEndpoint = authorizationEndpoint
        self.tokenEndpoint = tokenEndpoint
    }

    /// The reversed client ID (`com.googleusercontent.apps.<id>`), the scheme Google redirects an iOS client to.
    public var callbackScheme: String {
        clientID.split(separator: ".").reversed().joined(separator: ".")
    }

    public var redirectURI: String { "\(callbackScheme):/oauth2redirect" }

    /// Whether this is an OAuth client ID at all (`….apps.googleusercontent.com`); apps hide Google when it isn't.
    public var isConfigured: Bool {
        clientID.hasSuffix(".apps.googleusercontent.com") && clientID.count > ".apps.googleusercontent.com".count
    }

    /// A new sign-in: Google's consent page with PKCE (S256) and a `state` tying the redirect to it.
    public func authorization(scopes: [String] = GoogleOAuthClient.defaultScopes, loginHint: String? = nil,
                              verifier: String = GoogleAuthorization.randomToken(),
                              state: String = GoogleAuthorization.randomToken(byteCount: 16)) -> GoogleAuthorization
    {
        var components = URLComponents(url: authorizationEndpoint, resolvingAgainstBaseURL: false)!
        var items = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: GoogleAuthorization.challenge(for: verifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "prompt", value: "select_account"),
        ]
        // What Google's own iOS SDK sends for its serverClientID: the ID token is then issued for the server client.
        if let serverClientID { items.append(URLQueryItem(name: "audience", value: serverClientID)) }
        if let loginHint { items.append(URLQueryItem(name: "login_hint", value: loginHint)) }
        components.queryItems = items
        // `+` would read as a space in the query; Google wants it escaped.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return GoogleAuthorization(client: self, authorizeURL: components.url!, verifier: verifier, state: state)
    }
}

/// One Sign in with Google in progress (``GoogleOAuthClient/authorization(scopes:loginHint:verifier:state:)``).
public struct GoogleAuthorization: Sendable, Hashable {
    public let client: GoogleOAuthClient
    /// Open this in `ASWebAuthenticationSession` with ``GoogleOAuthClient/callbackScheme``.
    public let authorizeURL: URL
    /// The PKCE secret; Google only trades the code for tokens with it.
    public let verifier: String
    public let state: String

    public init(client: GoogleOAuthClient, authorizeURL: URL, verifier: String, state: String) {
        self.client = client
        self.authorizeURL = authorizeURL
        self.verifier = verifier
        self.state = state
    }

    /// What Google's redirect said.
    public enum Answer: Sendable, Equatable {
        case code(String)
        /// They closed or declined Google's page.
        case cancelled
        /// Google refused (or the redirect wasn't for this sign-in); `message` is Google's, when it gave one.
        case failed(message: String?)
    }

    /// Reads Google's redirect (`com.googleusercontent.apps.<id>:/oauth2redirect?code=…&state=…`), or nil when the
    /// URL isn't one.
    public func answer(from callbackURL: URL) -> Answer? {
        guard callbackURL.scheme?.lowercased() == client.callbackScheme.lowercased(),
              let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems
        else { return nil }
        let value = { (name: String) in items.first { $0.name == name }?.value.flatMap { $0.isEmpty ? nil : $0 } }
        if let error = value("error") {
            return error == "access_denied" ? .cancelled : .failed(message: value("error_description") ?? error)
        }
        guard value("state") == state else { return .failed(message: "Google's answer wasn't for this sign-in.") }
        guard let code = value("code") else { return nil }
        return .code(code)
    }

    /// The form that trades `code` for tokens at ``GoogleOAuthClient/tokenEndpoint``.
    public func tokenRequest(code: String) -> URLRequest {
        var request = URLRequest(url: client.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        var fields = [
            ("client_id", client.clientID),
            ("code", code),
            ("code_verifier", verifier),
            ("grant_type", "authorization_code"),
            ("redirect_uri", client.redirectURI),
        ]
        if let server = client.serverClientID { fields.append(("audience", server)) }
        request.httpBody = Data(fields.map { "\($0.0)=\(Self.formEncode($0.1))" }.joined(separator: "&").utf8)
        return request
    }

    /// The PKCE challenge: base64url of the verifier's SHA-256, unpadded.
    public static func challenge(for verifier: String) -> String {
        base64URL(SHA256Hex.data(verifier))
    }

    /// `byteCount` random bytes, base64url: 43 characters for the default 32, as PKCE wants.
    public static func randomToken(byteCount: Int = 32) -> String {
        var generator = SystemRandomNumberGenerator()
        return base64URL(Data((0 ..< byteCount).map { _ in UInt8.random(in: .min ... .max, using: &generator) }))
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func formEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

/// What Google's token endpoint answers: the ID token for the API, and an access token for the granted scopes.
public struct GoogleTokens: Sendable, Hashable, Decodable {
    public let idToken: String
    public let accessToken: String?
    /// The scopes granted, space-separated.
    public let scope: String?

    public init(idToken: String, accessToken: String? = nil, scope: String? = nil) {
        self.idToken = idToken
        self.accessToken = accessToken
        self.scope = scope
    }

    /// Whether the access token can read the account's other emails (``GoogleOAuthClient/emailsScope``).
    public var grantsEmails: Bool {
        scope?.split(separator: " ").contains { $0 == GoogleOAuthClient.emailsScope } ?? false
    }

    enum CodingKeys: String, CodingKey {
        case idToken = "id_token"
        case accessToken = "access_token"
        case scope
    }
}

extension AudienceSession {
    /// Exchanges a Google ID token for an AudienceKit session and stores it (`POST /v1/token/google`).
    ///
    /// The ID token only carries the Google account's primary email. Pass `accessToken`, an OAuth access token for
    /// ``GoogleOAuthClient/emailsScope``, and the API can also match an existing account by the Google account's other
    /// verified emails. Without it, sign-in works the same, matching by the primary one. A 401 (the token isn't from a
    /// Google client the API accepts) throws ``AudienceKitError/signInRejected``.
    @discardableResult
    public func signIn(googleIDToken: String, accessToken: String? = nil, name: String? = nil,
                       device: DeviceDescription) async throws -> SignInResult
    {
        let body = GoogleSignInRequest(idToken: googleIDToken, accessToken: accessToken, host: configuration.host,
                                       device: device, name: name)
        return try await signIn(path: "/v1/token/google", body: try JSONEncoder().encode(body), authenticated: false)
    }

    /// Connects a Google account to the signed-in account (one that signed in with Facebook or Apple), so Google signs
    /// in to it from then on, and stores the session the API answers with. When the Google account already had its own
    /// account, the two become one, so the session can name a different user ID. Refusals throw
    /// ``AudienceKitError/signInFailed(message:)`` with the API's reason and keep the current session.
    @discardableResult
    public func connectGoogle(idToken: String, device: DeviceDescription) async throws -> SignInResult {
        let body = GoogleSignInRequest(idToken: idToken, host: configuration.host, device: device, connect: true)
        return try await signIn(path: "/v1/token/google", body: try JSONEncoder().encode(body), authenticated: true)
    }

    /// Finishes a ``GoogleAuthorization`` with Google's redirect: trades the code for Google's tokens, then signs in
    /// (or, with `connect`, connects Google to the signed-in account). Returns nil when they cancelled on Google's
    /// page; throws ``AudienceKitError/signInFailed(message:)`` when Google refused.
    @discardableResult
    public func signIn(google authorization: GoogleAuthorization, callbackURL: URL, device: DeviceDescription,
                       connect: Bool = false) async throws -> SignInResult?
    {
        guard let tokens = try await googleTokens(authorization: authorization, callbackURL: callbackURL) else {
            return nil
        }
        if connect { return try await connectGoogle(idToken: tokens.idToken, device: device) }
        return try await signIn(googleIDToken: tokens.idToken, accessToken: tokens.grantsEmails ? tokens.accessToken : nil,
                                device: device)
    }

    /// Reads Google's redirect and trades its code for tokens; nil when they cancelled.
    public func googleTokens(authorization: GoogleAuthorization, callbackURL: URL) async throws -> GoogleTokens? {
        let code: String
        switch authorization.answer(from: callbackURL) {
        case let .code(value):
            code = value
        case .cancelled:
            return nil
        case let .failed(message):
            throw AudienceKitError.signInFailed(message: message ?? Self.googleFailure)
        case nil:
            throw AudienceKitError.signInFailed(message: Self.googleFailure)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.audienceKitData(for: authorization.tokenRequest(code: code))
        } catch let error as URLError {
            throw AudienceKitError.network(error)
        }
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            let fault = try? JSONDecoder().decode(GoogleTokenError.self, from: data)
            throw AudienceKitError.signInFailed(message: fault?.errorDescription ?? fault?.error ?? Self.googleFailure)
        }
        do {
            return try JSONDecoder().decode(GoogleTokens.self, from: data)
        } catch {
            throw AudienceKitError.signInFailed(message: "Google didn't send an ID token. Try again.")
        }
    }

    static let googleFailure = "Google sign-in didn't finish. Try again."
}

struct GoogleTokenError: Decodable {
    var error: String?
    var errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}

/// `POST /v1/token/google`'s body.
struct GoogleSignInRequest: Encodable {
    var idToken: String
    var accessToken: String?
    var host: String?
    var device: DeviceDescription
    var name: String?
    var connect: Bool?

    enum CodingKeys: String, CodingKey {
        case idToken = "id_token"
        case accessToken = "access_token"
        case host
        case device
        case name
        case connect
    }
}
