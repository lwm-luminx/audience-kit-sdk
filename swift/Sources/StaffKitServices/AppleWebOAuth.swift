import Foundation
import AudienceCore

/// Sign in with Apple through a browser, for a staff app that can't carry the Sign in with Apple entitlement: Velvet
/// Display's Developer ID build (Apple grants the entitlement to App Store and development builds only, so the
/// download from audiencekit.com never has it; Rick, 2026-11-23: "sign in through the browser").
///
/// It is the flow the Android staff apps use (audience_kit_api doc/TOKENS.md, "Sign in with Apple on Android"): Apple's
/// web sign-in with the console's Services ID, which posts the result to the API's return URL
/// (`POST /v1/token/apple/callback`), which redirects to the app named in `state`. The API answers that redirect as an
/// Android intent URL (`intent://callback?code=…&id_token=…&state=…#Intent;…`) for the staff apps' package names, and
/// Velvet's package name is its bundle ID, so the Mac starts the same sign-in and takes the `intent` redirect in its
/// web authentication session, which hands it straight back to the app without the system trying to open it.
///
/// The identity token travels through the browser, so it is bound to this app with a nonce: Apple is given the
/// SHA-256 of `nonce`, and the API accepts the token only with `nonce` itself, which never leaves the app.
public struct AppleWebOAuth: Sendable, Hashable {
    /// The scheme of the redirect that carries Apple's answer back (an Android intent URL).
    public static let callbackScheme = "intent"

    public enum OAuthError: Error, LocalizedError, Hashable {
        /// The person closed Apple's page or pressed Cancel there.
        case cancelled
        /// The redirect wasn't this sign-in's: no token, or another sign-in's state.
        case invalidCallback
        /// Apple refused, with its reason.
        case refused(String)

        public var errorDescription: String? {
            switch self {
            case .cancelled: "Sign in with Apple was cancelled."
            case .invalidCallback: "Apple’s answer didn’t match this sign-in. Try again."
            case .refused(let reason): "Apple didn’t sign you in (\(reason))."
            }
        }
    }

    /// What Apple sent back: the identity token for the API, the one-time code, and the name on a first sign-in.
    public struct Answer: Sendable, Hashable {
        public let identityToken: String
        public let authorizationCode: String?
        public let firstName: String?
        public let lastName: String?
    }

    /// The Services ID the sign-in is for.
    public let clientID: String
    /// The API's return URL, which Apple posts to and the API needs again with the code.
    public let redirectURI: String
    /// `<package>~<random>`: names the app the API hands the answer to, and ties the answer to this sign-in.
    public let state: String
    /// The value whose SHA-256 Apple puts in the token; sent to the API with the token.
    public let nonce: String

    /// The staff apps' Services ID for an environment: the admin console's, which the Android staff apps share.
    public static func clientID(for environment: AudienceKitEnvironment) -> String {
        environment == .production ? "com.audiencekit.admin" : "com.audiencekit.admin.next"
    }

    /// - Parameters:
    ///   - apiBaseURL: the API the app signs in to; its `/v1/token/apple/callback` is the return URL.
    ///   - package: the app's name to the API, one of the staff apps' (e.g. `com.audiencekit.Velvet`).
    public init(clientID: String, apiBaseURL: URL, package: String,
                random: String = UUID().uuidString, nonce: String = UUID().uuidString + UUID().uuidString) {
        self.clientID = clientID
        var base = apiBaseURL.absoluteString
        while base.hasSuffix("/") { base.removeLast() }
        redirectURI = base + "/v1/token/apple/callback"
        state = "\(package)~\(random)"
        self.nonce = nonce
    }

    /// Apple's sign-in page for this sign-in.
    public var authorizationURL: URL {
        var components = URLComponents(string: "https://appleid.apple.com/auth/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code id_token"),
            URLQueryItem(name: "response_mode", value: "form_post"),
            URLQueryItem(name: "scope", value: "name email"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "nonce", value: SHA256Digest.hex(Array(nonce.utf8)))
        ]
        // Apple reads the query as a form: a + in a value would be a space, so it's escaped too.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return components.url!
    }

    /// Reads Apple's answer from the redirect the API sent the browser to.
    public func answer(from callback: URL) throws -> Answer {
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value.flatMap { $0.isEmpty ? nil : $0 }
        }
        guard value("state") == state else { throw OAuthError.invalidCallback }
        if let error = value("error") {
            throw error == "user_cancelled_authorize" ? OAuthError.cancelled : OAuthError.refused(error)
        }
        guard let token = value("id_token") else { throw OAuthError.invalidCallback }
        return Answer(identityToken: token, authorizationCode: value("code"), firstName: value("first_name"),
                      lastName: value("last_name"))
    }
}
