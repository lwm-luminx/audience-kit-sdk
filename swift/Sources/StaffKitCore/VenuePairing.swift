import Foundation
import AudienceCore

/// A screen asking to be signed in to a venue (API VenueDevicePairing, doc/VENUE_DEVICES.md): Velvet on Apple TV shows
/// `url` (https://audiencekit.com/pair/ABCD-EFGH) as a QR code, a venue manager approves it in Velvet on their phone,
/// and the TV picks up its venue device sign-in with `claimVenuePairing`.
public struct VenuePairing: Decodable, Sendable, Equatable {
    /// As shown, e.g. ABCD-EFGH.
    public let code: String
    public let url: URL
    public let pollToken: String
    public let expiresAt: Date
    /// How often to ask whether it has been approved.
    public let interval: Int
    enum CodingKeys: String, CodingKey {
        case code, url, interval
        case pollToken = "poll_token", expiresAt = "expires_at"
    }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decode(String.self, forKey: .code)
        url = try container.decode(URL.self, forKey: .url)
        pollToken = try container.decode(String.self, forKey: .pollToken)
        interval = max(1, try container.decodeIfPresent(Int.self, forKey: .interval) ?? 3)
        let raw = try container.decode(String.self, forKey: .expiresAt)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        expiresAt = formatter.date(from: raw) ?? ISO8601DateFormatter().date(from: raw) ?? Date().addingTimeInterval(600)
    }
}

/// A pair link a phone scanned or opened: https://audiencekit.com/pair/<code>.
public struct VenuePairingLink: Sendable, Hashable, Identifiable {
    public static let host = "audiencekit.com"
    public static let pathPrefix = "pair"
    /// As the screen shows it, e.g. ABCD-EFGH.
    public let code: String
    public var id: String { code }

    public init(code: String) { self.code = code }

    /// The custom scheme the audiencekit.com/pair page's "Open in Velvet" button uses
    /// (`audiencekit-velvet://pair?code=ABCD-EFGH`), for when iOS hasn't picked up the universal link yet and the Camera
    /// opened the page in Safari instead of Velvet.
    public static let appScheme = "audiencekit-velvet"

    /// The pairing in `url`, or nil when it isn't a pair link.
    public init?(url: URL) {
        let raw: String
        if url.scheme?.lowercased() == Self.appScheme {
            guard url.host?.lowercased() == Self.pathPrefix,
                  let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
                    .first(where: { $0.name == "code" })?.value else { return nil }
            raw = code
        } else {
            guard let host = url.host?.lowercased(), host == Self.host || host == "www.\(Self.host)" else { return nil }
            let parts = url.path.split(separator: "/").map(String.init)
            guard parts.count == 2, parts[0] == Self.pathPrefix else { return nil }
            raw = parts[1]
        }
        self.init(raw: raw)
    }

    private init?(raw value: String) {
        let raw = value.uppercased().filter { $0.isLetter || $0.isNumber }
        guard raw.count == 8 else { return nil }
        code = String(raw.prefix(4)) + "-" + String(raw.suffix(4))
    }

    /// What a QR scanner read: a pair link, or nil for anything else (a device code, a pass).
    public init?(scanned: String) {
        guard let url = URL(string: scanned.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        self.init(url: url)
    }
}
