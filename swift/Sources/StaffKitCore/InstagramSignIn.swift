import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

/// One Sign in with Instagram, for Instagram Business and Creator accounts: the verifier this app keeps, and the URLs
/// the browser half runs between. The API does everything that needs the Instagram app secret; the app opens
/// ``authorizationURL`` in a web authentication session, which ends at `audiencekit-instagram://callback` with a ticket
/// (``ticket(from:)``) that signs in only with ``verifier``
/// (``AudienceManagementSession/signIn(instagramTicket:verifier:device:)``). See the API's doc/TOKENS.md, "Sign in
/// with Instagram".
public struct InstagramOAuth: Sendable {
    public enum OAuthError: Error, LocalizedError, Equatable {
        /// They cancelled on Instagram, or Instagram refused.
        case declined
        /// The API couldn't finish the sign-in; its reason, when it gave one.
        case failed(String?)
        case invalidCallback

        public var errorDescription: String? {
            switch self {
            case .declined: "Instagram sign-in was cancelled."
            case .failed(let reason): reason ?? "Instagram sign-in didn’t finish. Try again."
            case .invalidCallback: "Instagram sign-in didn’t finish. Try again."
            }
        }
    }

    /// The scheme the API's callback hands the ticket back on.
    public static let callbackScheme = "audiencekit-instagram"

    public let baseURL: URL
    /// This app's bundle ID, which the API checks is one of the staff apps'.
    public let app: String
    /// Never leaves the app until it signs in; only its SHA-256 goes through the browser.
    public let verifier: String

    public init(baseURL: URL, app: String, verifier: String = InstagramOAuth.randomVerifier()) {
        self.baseURL = baseURL
        self.app = app
        self.verifier = verifier
    }

    public var challenge: String { Self.sha256Hex(verifier) }

    /// Where the sign-in starts: the API's redirect to Instagram's authorization window.
    public var authorizationURL: URL {
        var components = URLComponents(url: baseURL.appendingPathComponent("v1/token/instagram/authorize"),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "platform", value: "ios"),
            URLQueryItem(name: "app", value: app),
            URLQueryItem(name: "challenge", value: challenge),
        ]
        return components.url!
    }

    /// The ticket in the API's callback, or why there is none.
    public static func ticket(from callback: URL) throws -> String {
        guard callback.scheme == callbackScheme,
              let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems
        else { throw OAuthError.invalidCallback }
        let value = { (name: String) in items.first(where: { $0.name == name })?.value.flatMap { $0.isEmpty ? nil : $0 } }
        if let ticket = value("ticket") { return ticket }
        if value("error") == "access_denied" { throw OAuthError.declined }
        if value("error") != nil { throw OAuthError.failed(value("error_description")) }
        throw OAuthError.invalidCallback
    }

    public static func randomVerifier() -> String {
        (0..<2).map { _ in UUID().uuidString.replacingOccurrences(of: "-", with: "") }.joined()
    }

    static func sha256Hex(_ text: String) -> String {
        #if canImport(CryptoKit)
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
        #else
        sha256(Array(text.utf8)).map { String(format: "%02x", $0) }.joined()
        #endif
    }

    #if !canImport(CryptoKit)
    /// FIPS 180-4 SHA-256, for Linux (CI), where there's no CryptoKit.
    static func sha256(_ message: [UInt8]) -> [UInt8] {
        let k: [UInt32] = [
            0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
            0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
            0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
            0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
            0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
            0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
            0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
            0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
        ]
        var h: [UInt32] = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]
        func rotr(_ x: UInt32, _ n: UInt32) -> UInt32 { (x >> n) | (x << (32 - n)) }
        var data = message + [0x80]
        while data.count % 64 != 56 { data.append(0) }
        let bits = UInt64(message.count) * 8
        data += (0..<8).map { UInt8(truncatingIfNeeded: bits >> (56 - 8 * UInt64($0))) }
        for chunk in stride(from: 0, to: data.count, by: 64) {
            var w = [UInt32](repeating: 0, count: 64)
            for i in 0..<16 {
                w[i] = (0..<4).reduce(UInt32(0)) { $0 << 8 | UInt32(data[chunk + 4 * i + $1]) }
            }
            for i in 16..<64 {
                let s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3)
                let s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10)
                w[i] = w[i - 16] &+ s0 &+ w[i - 7] &+ s1
            }
            var (a, b, c, d, e, f, g, hh) = (h[0], h[1], h[2], h[3], h[4], h[5], h[6], h[7])
            for i in 0..<64 {
                let s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)
                let t1 = hh &+ s1 &+ ((e & f) ^ (~e & g)) &+ k[i] &+ w[i]
                let s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)
                let t2 = s0 &+ ((a & b) ^ (a & c) ^ (b & c))
                (hh, g, f, e, d, c, b, a) = (g, f, e, d &+ t1, c, b, a, t1 &+ t2)
            }
            for (i, v) in [a, b, c, d, e, f, g, hh].enumerated() { h[i] = h[i] &+ v }
        }
        return h.flatMap { v in (0..<4).map { UInt8(truncatingIfNeeded: v >> (24 - 8 * UInt32($0))) } }
    }
    #endif
}

#if canImport(UIKit) && canImport(AuthenticationServices) && !os(tvOS)
import AuthenticationServices
import UIKit

/// Continue with Instagram for Backstage and Velvet: runs ``InstagramOAuth`` in a web authentication session and
/// returns what ``AudienceManagementSession/signIn(instagramTicket:verifier:device:)`` needs. The session catches the
/// `audiencekit-instagram` callback itself, so the apps register no URL scheme for it.
@MainActor
public final class InstagramSignIn: NSObject, ASWebAuthenticationPresentationContextProviding {
    public struct Credential: Sendable {
        public let ticket: String
        public let verifier: String
    }

    public let baseURL: URL
    public let app: String
    private var session: ASWebAuthenticationSession?

    public init(baseURL: URL, app: String = Bundle.main.bundleIdentifier ?? "") {
        self.baseURL = baseURL
        self.app = app
    }

    public func signIn() async throws -> Credential {
        let flow = InstagramOAuth(baseURL: baseURL, app: app)
        return try await withCheckedThrowingContinuation { continuation in
            // A session that fails to start can still call its completion, so only the first outcome counts.
            var finished = false
            let finish: @MainActor (Result<Credential, Error>) -> Void = { result in
                guard !finished else { return }
                finished = true
                continuation.resume(with: result)
            }
            let session = ASWebAuthenticationSession(url: flow.authorizationURL,
                                                     callbackURLScheme: InstagramOAuth.callbackScheme) { [weak self] callback, error in
                Task { @MainActor in
                    self?.session = nil
                    if let error {
                        let cancelled = (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin
                        finish(.failure(cancelled ? InstagramOAuth.OAuthError.declined : error))
                        return
                    }
                    finish(Result {
                        guard let callback else { throw InstagramOAuth.OAuthError.invalidCallback }
                        return Credential(ticket: try InstagramOAuth.ticket(from: callback), verifier: flow.verifier)
                    })
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = true
            self.session = session
            if !session.start() {
                self.session = nil
                finish(.failure(InstagramOAuth.OAuthError.invalidCallback))
            }
        }
    }

    public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
}
#endif
