import Foundation
import AudienceCore
import StaffKitCore

// Partner offers as Velvet cards (audience_kit_api doc/REFERRAL_OFFERS.md, Rick 2026-11-24): vendors that pay Love
// Wins Media a referral fee, shown to a venue's managers only where each answers something the venue is missing.
// Stored like TV posters: AudienceKit's own show in every audience, and an audience can add its own. Each card carries
// its disclosure. A click is counted against the venue and the offer only, never the person.

/// One partner offer for a venue (`ReferralOffer`).
public struct StaffReferralOffer: Codable, Sendable, Hashable, Identifiable {
    /// Where Velvet shows it (`ReferralOfferPlacement`).
    public enum Placement: String, Codable, Sendable, CaseIterable {
        case tonight = "TONIGHT", music = "MUSIC", ordering = "ORDERING", karaoke = "KARAOKE", staff = "STAFF"
        case screens = "SCREENS"
    }

    public let id: String
    public let key: String
    public let partner: String
    public let category: String
    /// Nil for a placement this build doesn't know yet.
    public let placement: Placement?
    public let headline: String
    public let body: String
    /// The button's label.
    public let cta: String
    /// The referral link. Open the one ``VenueManagementClient/recordReferralOfferClick(venueID:offerID:)`` answers.
    public let url: String
    public let imageUrl: String?
    /// Shown on the card every time: Love Wins Media may earn a referral fee.
    public let disclosure: String

    public init(id: String, key: String, partner: String, category: String, placement: Placement?, headline: String,
                body: String, cta: String, url: String, imageUrl: String?, disclosure: String) {
        self.id = id; self.key = key; self.partner = partner; self.category = category; self.placement = placement
        self.headline = headline; self.body = body; self.cta = cta; self.url = url; self.imageUrl = imageUrl
        self.disclosure = disclosure
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        key = try container.decode(String.self, forKey: .key)
        partner = try container.decode(String.self, forKey: .partner)
        category = try container.decode(String.self, forKey: .category)
        placement = try container.decodeIfPresent(String.self, forKey: .placement).flatMap(Placement.init(rawValue:))
        headline = try container.decode(String.self, forKey: .headline)
        body = try container.decode(String.self, forKey: .body)
        cta = try container.decode(String.self, forKey: .cta)
        url = try container.decode(String.self, forKey: .url)
        imageUrl = try container.decodeIfPresent(String.self, forKey: .imageUrl)
        disclosure = try container.decode(String.self, forKey: .disclosure)
    }
}

extension VenueManagementClient {
    static let referralOfferFields = "id key partner category placement headline body cta url imageUrl disclosure"

    /// The partner offers the venue's managers see on `placement` (nil for every placement). Empty for anyone who
    /// doesn't manage the venue.
    public func referralOffers(venueID: String,
                               placement: StaffReferralOffer.Placement? = nil) async throws -> [StaffReferralOffer] {
        struct Venue: Decodable, Sendable { let referralOffers: [StaffReferralOffer] }
        struct Venues: Decodable, Sendable { let venue: Venue? }
        struct Response: Decodable, Sendable { let venues: Venues }
        let response = try await session.graphQL("""
            query VelvetReferralOffers($id: ID!, $placement: ReferralOfferPlacement) {
              venues { venue(id: $id) { referralOffers(placement: $placement) { \(Self.referralOfferFields) } } }
            }
            """, variables: ["id": .string(venueID), "placement": placement.map { .string($0.rawValue) } ?? .null],
            as: Response.self)
        return response.venues.venue?.referralOffers ?? []
    }

    /// Counts a tap on an offer (the venue and the offer only) and answers the referral link to open.
    public func recordReferralOfferClick(venueID: String, offerID: String) async throws -> URL? {
        struct Payload: Decodable, Sendable { let url: String }
        struct Response: Decodable, Sendable { let recordReferralOfferClick: Payload }
        let response = try await session.graphQL("""
            mutation VelvetReferralOfferClick($input: ReferralOfferClickRecordInput!) {
              recordReferralOfferClick(input: $input) { url }
            }
            """, variables: ["input": .object(["venueId": .string(venueID), "id": .string(offerID)])],
            as: Response.self)
        return URL(string: response.recordReferralOfferClick.url)
    }

    /// Stops an offer showing for the venue ("Not for us").
    public func dismissReferralOffer(venueID: String, offerID: String) async throws {
        struct Payload: Decodable, Sendable {}
        struct Response: Decodable, Sendable { let dismissReferralOffer: Payload }
        _ = try await session.graphQL("""
            mutation VelvetReferralOfferDismiss($input: ReferralOfferDismissInput!) {
              dismissReferralOffer(input: $input) { venue { id } }
            }
            """, variables: ["input": .object(["venueId": .string(venueID), "id": .string(offerID)])],
            as: Response.self)
    }
}
