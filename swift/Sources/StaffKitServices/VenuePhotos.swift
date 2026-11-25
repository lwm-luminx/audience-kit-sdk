import Foundation
import AudienceCore

/// A photographer's photo of an event or venue: only a preview.
public struct VenueEventPhoto: Decodable, Sendable, Identifiable, Hashable {
    public struct Photographer: Decodable, Sendable, Hashable { public let name: String }
    public struct Event: Decodable, Sendable, Hashable { public let id: String; public let name: String? }
    public let id: String
    /// The preview image.
    public let url: String
    public let caption: String?
    public let altText: String?
    public let takenAt: String?
    public let width: Int?
    public let height: Int?
    /// Hidden from the apps: by a manager or an admin, or after a report.
    public let isHidden: Bool
    public let photographer: Photographer
    public let event: Event?
}

/// Whose photographers' photos: a venue's or an event's.
public enum VenuePhotoSubject: Sendable, Hashable {
    case venue(id: String)
    case event(id: String)
}

extension VenueManagementClient {
    static let photoFields = "id url caption altText takenAt width height isHidden photographer { name } event { id name }"

    /// Photographers' photos, hidden ones too: an event's oldest first, a venue's newest first.
    public func photos(of subject: VenuePhotoSubject, first: Int = 100) async throws -> [VenueEventPhoto] {
        struct Photos: Decodable, Sendable { let nodes: [VenueEventPhoto] }
        struct Photography: Decodable, Sendable { let photos: Photos }
        /// Its photography mixin, null where the audience has no photographers.
        struct Owner: Decodable, Sendable { let photography: Photography? }
        let selection = "photography { photos(first: \(first), includeHidden: true) { nodes { \(Self.photoFields) } } }"
        switch subject {
        case let .venue(id):
            struct Venues: Decodable, Sendable { let venue: Owner? }
            struct Response: Decodable, Sendable { let venues: Venues }
            return try await session.graphQL("query VelvetVenuePhotos($id: ID!) { venues { venue(id: $id) { \(selection) } } }",
                                           variables: ["id": .string(id)], as: Response.self).venues.venue?.photography?.photos.nodes ?? []
        case let .event(id):
            struct Events: Decodable, Sendable { let event: Owner? }
            struct Response: Decodable, Sendable { let events: Events }
            return try await session.graphQL("query VelvetEventPhotos($id: ID!) { events { event(id: $id) { \(selection) } } }",
                                           variables: ["id": .string(id)], as: Response.self).events.event?.photography?.photos.nodes ?? []
        }
    }

    /// Hides a photo from the apps; publishing it again doesn't bring it back.
    public func hidePhoto(id: String, reason: String? = nil) async throws -> VenueEventPhoto {
        struct Payload: Decodable, Sendable { let photo: VenueEventPhoto }
        struct Response: Decodable, Sendable { let hideEventPhoto: Payload }
        var input: [String: GraphQLValue] = ["id": .string(id)]
        if let reason, !reason.isEmpty { input["reason"] = .string(reason) }
        return try await session.graphQL("mutation VelvetPhotoHide($input: EventPhotoHideInput!) { hideEventPhoto(input: $input) { photo { \(Self.photoFields) } } }",
                                       variables: ["input": .object(input)], as: Response.self).hideEventPhoto.photo
    }

    /// Shows a hidden or reported photo again.
    public func showPhoto(id: String) async throws -> VenueEventPhoto {
        struct Payload: Decodable, Sendable { let photo: VenueEventPhoto }
        struct Response: Decodable, Sendable { let showEventPhoto: Payload }
        return try await session.graphQL("mutation VelvetPhotoShow($input: EventPhotoShowInput!) { showEventPhoto(input: $input) { photo { \(Self.photoFields) } } }",
                                       variables: ["input": .object(["id": .string(id)])], as: Response.self).showEventPhoto.photo
    }
}
