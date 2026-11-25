// tvOS has no web authentication session.
#if !os(tvOS)
#if canImport(SwiftUI) && canImport(AuthenticationServices)
import AudienceKit
import AuthenticationServices
import SwiftUI

@available(iOS 16.4, macOS 13.3, *)
extension WebAuthenticationSession {
    /// Sign in with Google (or, with `connect`, connect Google to the signed-in account): opens Google's page in this
    /// authentication session, then ``AudienceSession/signIn(google:callbackURL:device:connect:)``. Returns nil when
    /// they cancelled, in the sheet or on Google's page.
    ///
    /// ```swift
    /// @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    /// let google = GoogleOAuthClient(clientID: iosClientID, serverClientID: webClientID)
    /// let result = try await webAuthenticationSession.signInWithGoogle(google, client: client, device: device)
    /// ```
    @MainActor
    public func signInWithGoogle(_ google: GoogleOAuthClient, client: AudienceKitClient, device: DeviceDescription,
                                 scopes: [String] = GoogleOAuthClient.defaultScopes, connect: Bool = false)
        async throws -> SignInResult?
    {
        let authorization = google.authorization(scopes: scopes)
        let callback: URL
        do {
            callback = try await authenticate(using: authorization.authorizeURL,
                                              callbackURLScheme: google.callbackScheme,
                                              preferredBrowserSession: .shared)
        } catch ASWebAuthenticationSessionError.canceledLogin {
            return nil
        }
        return try await client.signIn(google: authorization, callbackURL: callback, device: device, connect: connect)
    }
}

/// The words around Google sign-in, shared with Android so the apps say the same thing.
public enum GoogleSignInCopy {
    public static let signIn = "Continue with Google"
    public static let connect = "Connect Google"
    public static let connectedLabel = "Google"
    public static let failedTitle = "Couldn't sign in with Google"
}
#endif
#endif
