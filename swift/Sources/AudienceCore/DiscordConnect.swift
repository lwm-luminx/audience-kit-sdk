import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Connecting a Discord account to the signed-in one, for someone who signed in another way (Sign in with Apple, say),
/// so the audience's Discord bridge knows them as the same person and can show them its channels.
///
/// Discord's OAuth needs the API's client secret, so the API runs it and the app only ever holds a short-lived ticket
/// bound to a verifier that never goes through the browser:
///
/// 1. ``AudienceSession/discordConnection(app:platform:)`` makes the verifier and the API's authorize URL.
/// 2. The app opens ``DiscordConnection/authorizeURL`` in `ASWebAuthenticationSession` (callback scheme
///    ``DiscordConnection/callbackScheme``) or a Custom Tab; the API sends the browser back to
///    `audiencekit-discord://callback?ticket=…` (or `?error=…`).
/// 3. ``AudienceSession/connectDiscord(callbackURL:connection:device:)`` reads the callback and connects the account.
///
/// The app must be listed in the audience's console (Apps), and the iOS app needs nothing else: the authentication
/// session catches the scheme. (`AudienceKitUI`'s `ConnectDiscordButton` does all three.)
public struct DiscordConnection: Sendable, Hashable {
    /// The URL scheme the API sends the answer to.
    public static let callbackScheme = "audiencekit-discord"

    /// The API's page that starts Discord's sign-in.
    public let authorizeURL: URL
    /// The secret whose SHA-256 the authorize URL carries; the ticket is no use without it.
    public let verifier: String

    public init(authorizeURL: URL, verifier: String) {
        self.authorizeURL = authorizeURL
        self.verifier = verifier
    }

    /// A new connection for `app` on `platform`, against the API at `base`.
    public static func make(base: URL, app: String, platform: String = "ios",
                            verifier: String = DiscordConnection.randomVerifier()) -> DiscordConnection
    {
        var components = URLComponents(url: base.appendingPathComponent("v1/token/discord/authorize"),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "platform", value: platform),
            URLQueryItem(name: "app", value: app),
            URLQueryItem(name: "challenge", value: SHA256Hex.digest(verifier)),
        ]
        return DiscordConnection(authorizeURL: components.url!, verifier: verifier)
    }

    /// 32 random bytes as hex.
    public static func randomVerifier() -> String {
        var generator = SystemRandomNumberGenerator()
        return (0 ..< 32).map { _ in String(format: "%02x", UInt8.random(in: .min ... .max, using: &generator)) }
            .joined()
    }

    /// What the API's callback said: the ticket, or why there isn't one.
    public enum Answer: Sendable, Equatable {
        case ticket(String)
        /// They cancelled on Discord's page.
        case cancelled
        /// Discord or the API refused; `message` is the API's, when it gave one.
        case failed(message: String?)
    }

    /// Reads the API's callback URL (`audiencekit-discord://callback?ticket=…`), or nil when it isn't one.
    public static func answer(from callbackURL: URL) -> Answer? {
        guard callbackURL.scheme?.lowercased() == callbackScheme,
              let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems
        else { return nil }
        let value = { (name: String) in items.first { $0.name == name }?.value.flatMap { $0.isEmpty ? nil : $0 } }
        if let ticket = value("ticket") { return .ticket(ticket) }
        switch value("error") {
        case "access_denied": return .cancelled
        case nil: return nil
        default: return .failed(message: value("error_description"))
        }
    }
}

extension AudienceSession {
    /// A new ``DiscordConnection`` for this app, against the API instance that holds the session (so a next build
    /// connects on next).
    public func discordConnection(app: String, platform: String = "ios") throws -> DiscordConnection {
        DiscordConnection.make(base: configuration.apiBase(for: try credential()), app: app, platform: platform)
    }

    /// Connects the Discord account the callback names to the signed-in account and stores the session the API
    /// returns: `POST /v1/token/discord { ticket, verifier, host, device, connect: true }`. When the Discord bridge had
    /// already made an account for that Discord user, the two become one, so the session can name a different user ID.
    ///
    /// Throws ``AudienceKitError/signInFailed(message:)`` with the API's reason when it refuses (the account already has
    /// another Discord, say) and when Discord's page failed; returns nil when they cancelled.
    @discardableResult
    public func connectDiscord(callbackURL: URL, connection: DiscordConnection, device: DeviceDescription)
        async throws -> SignInResult?
    {
        switch DiscordConnection.answer(from: callbackURL) {
        case let .ticket(ticket):
            return try await connectDiscord(ticket: ticket, verifier: connection.verifier, device: device)
        case .cancelled:
            return nil
        case let .failed(message):
            throw AudienceKitError.signInFailed(message: message ?? "Discord didn't connect. Try again.")
        case nil:
            throw AudienceKitError.signInFailed(message: "Discord didn't connect. Try again.")
        }
    }

    /// Connects Discord with a ticket from the API's callback and the verifier that started it.
    @discardableResult
    public func connectDiscord(ticket: String, verifier: String, device: DeviceDescription) async throws
        -> SignInResult
    {
        let body = DiscordConnectRequest(ticket: ticket, verifier: verifier, host: configuration.host, device: device)
        return try await signIn(path: "/v1/token/discord", body: try JSONEncoder().encode(body), authenticated: true)
    }

    /// The Discord account connected to the signed-in one (`me { self { signedInWithDiscord discordUsername } }`):
    /// nil when there's none, and when the API is older than the field.
    public func connectedDiscord() async throws -> ConnectedDiscord? {
        struct Response: Decodable, Sendable {
            struct Me: Decodable, Sendable {
                struct SelfUser: Decodable, Sendable {
                    let signedInWithDiscord: Bool?
                    let discordUsername: String?
                }

                let `self`: SelfUser?
            }

            let me: Me?
        }
        let response: Response
        do {
            response = try await graphQL(
                "query ConnectedDiscord { me { self { signedInWithDiscord discordUsername } } }",
                operationName: "ConnectedDiscord", as: Response.self)
        } catch let error as AudienceKitError
            where error.code == "undefinedField" || error.code == AudienceKitError.Code.graphQL
        {
            return nil
        }
        guard let user = response.me?.`self`, user.signedInWithDiscord == true else { return nil }
        return ConnectedDiscord(username: user.discordUsername)
    }
}

/// The Discord account connected to the signed-in one.
public struct ConnectedDiscord: Sendable, Hashable {
    /// Their Discord username, as of the last time they signed in or connected.
    public let username: String?

    public init(username: String?) {
        self.username = username
    }
}

struct DiscordConnectRequest: Encodable {
    var ticket: String
    var verifier: String
    var host: String?
    var device: DeviceDescription
    var connect = true
}

/// SHA-256 as lowercase hex, without CryptoKit so it works on Linux too. Only for the verifier's challenge.
enum SHA256Hex {
    private static let k: [UInt32] = [
        0x428A_2F98, 0x7137_4491, 0xB5C0_FBCF, 0xE9B5_DBA5, 0x3956_C25B, 0x59F1_11F1, 0x923F_82A4, 0xAB1C_5ED5,
        0xD807_AA98, 0x1283_5B01, 0x2431_85BE, 0x550C_7DC3, 0x72BE_5D74, 0x80DE_B1FE, 0x9BDC_06A7, 0xC19B_F174,
        0xE49B_69C1, 0xEFBE_4786, 0x0FC1_9DC6, 0x240C_A1CC, 0x2DE9_2C6F, 0x4A74_84AA, 0x5CB0_A9DC, 0x76F9_88DA,
        0x983E_5152, 0xA831_C66D, 0xB003_27C8, 0xBF59_7FC7, 0xC6E0_0BF3, 0xD5A7_9147, 0x06CA_6351, 0x1429_2967,
        0x27B7_0A85, 0x2E1B_2138, 0x4D2C_6DFC, 0x5338_0D13, 0x650A_7354, 0x766A_0ABB, 0x81C2_C92E, 0x9272_2C85,
        0xA2BF_E8A1, 0xA81A_664B, 0xC24B_8B70, 0xC76C_51A3, 0xD192_E819, 0xD699_0624, 0xF40E_3585, 0x106A_A070,
        0x19A4_C116, 0x1E37_6C08, 0x2748_774C, 0x34B0_BCB5, 0x391C_0CB3, 0x4ED8_AA4A, 0x5B9C_CA4F, 0x682E_6FF3,
        0x748F_82EE, 0x78A5_636F, 0x84C8_7814, 0x8CC7_0208, 0x90BE_FFFA, 0xA450_6CEB, 0xBEF9_A3F7, 0xC671_78F2,
    ]

    static func digest(_ string: String) -> String {
        var message = Array(string.utf8)
        let bitLength = UInt64(message.count) * 8
        message.append(0x80)
        while message.count % 64 != 56 { message.append(0) }
        for shift in stride(from: 56, through: 0, by: -8) {
            message.append(UInt8(truncatingIfNeeded: bitLength >> UInt64(shift)))
        }

        var h: [UInt32] = [0x6A09_E667, 0xBB67_AE85, 0x3C6E_F372, 0xA54F_F53A, 0x510E_527F, 0x9B05_688C, 0x1F83_D9AB,
                           0x5BE0_CD19]
        func rotr(_ x: UInt32, _ n: UInt32) -> UInt32 { (x >> n) | (x << (32 - n)) }
        for chunk in stride(from: 0, to: message.count, by: 64) {
            var w = [UInt32](repeating: 0, count: 64)
            for i in 0 ..< 16 {
                let b = chunk + i * 4
                w[i] = UInt32(message[b]) << 24 | UInt32(message[b + 1]) << 16 | UInt32(message[b + 2]) << 8
                    | UInt32(message[b + 3])
            }
            for i in 16 ..< 64 {
                let s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3)
                let s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10)
                w[i] = w[i - 16] &+ s0 &+ w[i - 7] &+ s1
            }
            var (a, b, c, d, e, f, g, hh) = (h[0], h[1], h[2], h[3], h[4], h[5], h[6], h[7])
            for i in 0 ..< 64 {
                let t1 = hh &+ (rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)) &+ ((e & f) ^ (~e & g)) &+ k[i] &+ w[i]
                let t2 = (rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)) &+ ((a & b) ^ (a & c) ^ (b & c))
                (hh, g, f, e, d, c, b, a) = (g, f, e, d &+ t1, c, b, a, t1 &+ t2)
            }
            h = zip(h, [a, b, c, d, e, f, g, hh]).map { $0 &+ $1 }
        }
        return h.map { String(format: "%08x", $0) }.joined()
    }
}
