import Foundation

public struct VenueDeviceSession: Decodable, Sendable {
    public let id: String
    public let venueID: String
    public let venueName: String?
    public let permissions: [String]
    public let expiresAt: String
    public let audience: ManagedAudience
    enum CodingKeys: String, CodingKey {
        case id, permissions, audience
        case venueID = "venue_id", venueName = "venue_name", expiresAt = "expires_at"
    }
    /// What one permission brings with it, as the API's VenueDeviceGrant::IMPLIED: a screen (a TV, Velvet Display)
    /// also reports and fetches music, so its lyrics come through AudienceKit's key like a music device's.
    public static let implied = ["screen": ["music"]]

    public func permits(_ permission: String) -> Bool {
        permissions.contains("admin") || permissions.contains(permission)
            || permissions.contains { Self.implied[$0]?.contains(permission) == true }
    }
}
