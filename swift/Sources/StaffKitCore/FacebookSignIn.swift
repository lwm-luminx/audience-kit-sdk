#if canImport(UIKit) && canImport(AuthenticationServices) && !os(tvOS)
import AuthenticationServices
import UIKit

/// Facebook sign-in for the management apps, with the platform's Facebook Login for Business configuration.
///
/// With the Facebook app installed it opens the OAuth dialog there, as fbauth2://authorize: the same switch the
/// Facebook SDK makes, except that it carries `config_id`, which the SDK can't send and Login for Business requires.
/// Otherwise it opens the dialog in a web authentication session. Both redirect to fb<app ID>://authorize/ with a
/// code for the API to exchange (``AudienceManagementSession/signIn(code:redirectURI:device:)``). Apps register that
/// URL scheme and their own (the `AudienceKitURLScheme` Info.plist key, e.g. audiencekit-backstage), and forward
/// incoming URLs to ``handle(_:)``.
///
/// Velvet, Focus and Backstage share a Facebook app, and Facebook allows only one URL scheme suffix per app, so they
/// all receive fb<app ID> and iOS picks one for the Facebook app's redirect. The state names the app that asked, and
/// whichever app gets the redirect sends it on to that one's own scheme.
@MainActor
public final class FacebookSignIn: NSObject, ASWebAuthenticationPresentationContextProviding {
    public struct Credential: Sendable {
        public let code: String
        public let redirectURI: String
    }

    public let platform: ManagementPlatform
    /// This app's own URL scheme, e.g. audiencekit-backstage.
    public let ownScheme: String?
    private var session: ASWebAuthenticationSession?
    private var appSwitch: CheckedContinuation<URL?, Never>?
    private var activeObserver: NSObjectProtocol?

    public init(platform: ManagementPlatform,
                ownScheme: String? = Bundle.main.object(forInfoDictionaryKey: "AudienceKitURLScheme") as? String) {
        self.platform = platform
        self.ownScheme = ownScheme
    }

    public func signIn() async throws -> Credential {
        let flow = FacebookOAuth(appID: platform.facebookAppID, configurationID: platform.facebookLoginConfigurationID,
                                 returnScheme: ownScheme)
        if let url = Self.facebookAppURL(for: flow), UIApplication.shared.canOpenURL(url) {
            return try await signInWithFacebookApp(url: url, flow: flow)
        }
        return try await signInOnTheWeb(flow: flow)
    }

    /// Takes the Facebook app's redirect while a sign-in is waiting for it, or sends on one meant for another of the
    /// apps sharing the Facebook app; returns whether the URL was a Facebook redirect.
    public func handle(_ url: URL) -> Bool {
        if let forward = FacebookOAuth.forwardingURL(for: url, appID: platform.facebookAppID, ownScheme: ownScheme) {
            UIApplication.shared.open(forward)
            return true
        }
        guard appSwitch != nil, url.scheme == "fb\(platform.facebookAppID)" || (ownScheme != nil && url.scheme == ownScheme)
        else { return false }
        finishAppSwitch(url)
        return true
    }

    /// The web dialog's URL as the Facebook app takes it, with the SDK's app-switch parameters.
    static func facebookAppURL(for flow: FacebookOAuth) -> URL? {
        guard var components = URLComponents(url: flow.authorizationURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.scheme = "fbauth2"
        components.host = "authorize"
        components.path = ""
        components.queryItems = (components.queryItems ?? []) + [
            URLQueryItem(name: "ios_fast_app_switch", value: "true"),
            URLQueryItem(name: "sdk", value: "ios"),
            URLQueryItem(name: "display", value: "touch"),
            URLQueryItem(name: "return_scopes", value: "true"),
        ]
        return components.url
    }

    private func signInWithFacebookApp(url: URL, flow: FacebookOAuth) async throws -> Credential {
        let callback: URL? = await withCheckedContinuation { continuation in
            appSwitch = continuation
            UIApplication.shared.open(url) { [weak self] opened in
                guard let self else { return }
                guard opened else { self.finishAppSwitch(nil); return }
                // Coming back without the redirect (cancelling in the Facebook app, or switching back by hand)
                // ends the sign-in. The redirect, when there is one, arrives as the app becomes active.
                self.activeObserver = NotificationCenter.default.addObserver(
                    forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
                ) { [weak self] _ in
                    guard let self else { return }
                    Task { @MainActor [weak self] in
                        try? await Task.sleep(for: .seconds(1))
                        self?.finishAppSwitch(nil)
                    }
                }
            }
        }
        guard let callback else { throw FacebookOAuth.OAuthError.declined }
        return Credential(code: try flow.code(from: callback), redirectURI: flow.redirectURI)
    }

    private func finishAppSwitch(_ url: URL?) {
        if let activeObserver { NotificationCenter.default.removeObserver(activeObserver) }
        activeObserver = nil
        appSwitch?.resume(returning: url)
        appSwitch = nil
    }

    private func signInOnTheWeb(flow: FacebookOAuth) async throws -> Credential {
        try await withCheckedThrowingContinuation { continuation in
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

    public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
}
#endif
