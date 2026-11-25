import Foundation
import AudienceCore
import StaffKitCore

// Switching which publication Soapbox works on, the way Focus picks a locale: search, Nearby and Recents. The
// documents, the directory that searches and ranks, and the recents are the SDK's `PublisherChooser` (AudienceCore),
// shared with Android; this sends them on the staff endpoint.

extension SoapboxClient {
    /// The publications they may switch to (every one for the audience's admins), with the place each covers.
    public func publisherDirectory() async throws -> PublisherDirectory {
        try await session.graphQL(PublisherChooserDocuments.publishersQuery,
                                  as: PublisherChooserDocuments.PublishersResponse.self).directory
    }

    /// The audience's locales a position lies in, outermost first, for Nearby.
    public func localesContaining(_ position: Coordinate) async throws -> [String] {
        try await session.graphQL(PublisherChooserDocuments.localesAtQuery, variables: ["here": position.graphQLValue],
                                  as: PublisherChooserDocuments.LocalesAtResponse.self).ids
    }
}
