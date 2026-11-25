#if os(macOS) && canImport(AuthenticationServices)
import AppKit
import AuthenticationServices

/// Facebook sign-in for the management apps on the Mac (Arbiter): the same OAuth dialog as on iOS, in a web
/// authentication session, redirecting to fb<app ID>://authorize/ with a code for the API to exchange
/// (``AudienceManagementSession/signIn(code:redirectURI:device:)``). There's no Facebook app to switch to, and the
/// session takes its own redirect, so the app registers no URL scheme for it.
@MainActor
public final class FacebookSignIn: NSObject, ASWebAuthenticationPresentationContextProviding {
    public struct Credential: Sendable {
        public let code: String
        public let redirectURI: String
    }

    public let platform: ManagementPlatform
    /// This app's own URL scheme, carried in the state as on iOS.
    public let ownScheme: String?
    private var session: ASWebAuthenticationSession?

    public init(platform: ManagementPlatform,
                ownScheme: String? = Bundle.main.object(forInfoDictionaryKey: "AudienceKitURLScheme") as? String) {
        self.platform = platform
        self.ownScheme = ownScheme
    }

    public func signIn() async throws -> Credential {
        let flow = FacebookOAuth(appID: platform.facebookAppID, configurationID: platform.facebookLoginConfigurationID,
                                 returnScheme: ownScheme)
        return try await withCheckedThrowingContinuation { continuation in
            // A session that fails to start can still call its completion, so only the first outcome counts.
            var finished = false
            let finish: @MainActor (Result<Credential, Error>) -> Void = { result in
                guard !finished else { return }
                finished = true
                continuation.resume(with: result)
            }
            let session = ASWebAuthenticationSession(url: flow.authorizationURL,
                                                     callbackURLScheme: "fb\(platform.facebookAppID)") { [weak self] callback, error in
                Task { @MainActor in
                    self?.session = nil
                    if let error { finish(.failure(error)); return }
                    finish(Result {
                        guard let callback else { throw FacebookOAuth.OAuthError.invalidCallback }
                        return Credential(code: try flow.code(from: callback), redirectURI: flow.redirectURI)
                    })
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = true
            self.session = session
            if !session.start() {
                self.session = nil
                finish(.failure(FacebookOAuth.OAuthError.invalidCallback))
            }
        }
    }

    /// The web session takes its own redirect, so an opened URL is never one: always false. Here so apps call the
    /// same API on both platforms.
    public func handle(_ url: URL) -> Bool { false }

    public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first ?? ASPresentationAnchor()
    }
}
#endif
