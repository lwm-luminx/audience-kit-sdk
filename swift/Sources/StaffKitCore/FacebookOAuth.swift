import Foundation

/// OAuth state and redirect validation shared by management apps; no app secret belongs in a client.
public struct FacebookOAuth: Sendable {
    public static let permissions = ["public_profile"]
    public let appID: String
    public let configurationID: String?
    /// The app's own URL scheme (e.g. audiencekit-backstage), when apps share the Facebook app. Facebook redirects
    /// to fb<app ID>, which they all register, so iOS may hand the redirect to another of them; the state starts with
    /// this scheme, and that app sends the redirect on here (see ``forwardingURL(for:appID:ownScheme:)``).
    public let returnScheme: String?
    public let state: String
    public var redirectURI: String { "fb\(appID)://authorize/" }
    public init(appID: String, configurationID: String? = nil, returnScheme: String? = nil, state: String? = nil) {
        self.appID = appID
        self.configurationID = configurationID
        self.returnScheme = returnScheme.flatMap { $0.isEmpty ? nil : $0 }
        self.state = state ?? [self.returnScheme, UUID().uuidString].compactMap(\.self).joined(separator: ".")
    }

    /// For a Facebook redirect that reached the wrong app: the same redirect addressed to the app whose sign-in it
    /// answers, named at the start of its state. Nil when it's this app's own (or names no app).
    public static func forwardingURL(for callback: URL, appID: String, ownScheme: String?) -> URL? {
        guard callback.scheme == "fb\(appID)", callback.host == "authorize",
              let state = parameters(of: callback)?.first(where: { $0.name == "state" })?.value,
              let dot = state.firstIndex(of: ".") else { return nil }
        let scheme = String(state[..<dot])
        guard scheme != ownScheme, scheme.hasPrefix("audiencekit-"),
              scheme.allSatisfy({ $0.isLetter || $0 == "-" }),
              var components = URLComponents(url: callback, resolvingAgainstBaseURL: false) else { return nil }
        components.scheme = scheme
        return components.url
    }
    public var authorizationURL: URL {
        var components = URLComponents(string: "https://www.facebook.com/v26.0/dialog/oauth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: appID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "state", value: state)
        ]
        if let configurationID {
            components.queryItems?.append(URLQueryItem(name: "config_id", value: configurationID))
        } else {
            components.queryItems?.append(URLQueryItem(name: "scope", value: Self.permissions.joined(separator: ",")))
        }
        return components.url!
    }
    /// The authorization code from the redirect. The web dialog puts its parameters in the query; the Facebook
    /// app, opened as fbauth2://authorize, puts them in the fragment.
    public func code(from callback: URL) throws -> String {
        guard callback.scheme == "fb\(appID)" || (returnScheme != nil && callback.scheme == returnScheme),
              callback.host == "authorize",
              callback.path.isEmpty || callback.path == "/",
              let items = Self.parameters(of: callback),
              items.filter({ $0.name == "state" }).count == 1,
              items.first(where: { $0.name == "state" })?.value == state else { throw OAuthError.invalidCallback }
        if items.contains(where: { $0.name == "error" }) { throw OAuthError.declined }
        let codes = items.filter { $0.name == "code" }
        guard codes.count == 1, let code = codes.first?.value, !code.isEmpty else { throw OAuthError.invalidCallback }
        return code
    }
    static func parameters(of callback: URL) -> [URLQueryItem]? {
        guard let components = URLComponents(url: callback, resolvingAgainstBaseURL: false) else { return nil }
        if let query = components.queryItems, !query.isEmpty { return query }
        guard let fragment = components.fragment, !fragment.isEmpty else { return nil }
        return URLComponents(string: "?" + fragment)?.queryItems
    }
        public enum OAuthError: Error, LocalizedError {
        case invalidCallback, declined
        public var errorDescription: String? {
            switch self {
            case .invalidCallback: "Sign-in could not be verified. Please try again."
            case .declined: "Facebook sign-in was canceled."
            }
        }
    }
}
