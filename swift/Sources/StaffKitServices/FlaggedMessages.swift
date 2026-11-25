import Foundation
import AudienceCore
import StaffKitCore

/// Velvet's flagged messages (audience_kit_api doc/MESSAGE_ANALYSIS.md, "Staff review"): what the AI host flagged in a
/// venue's room, for its staff to settle with one tap. The model, GraphQL and words are the AudienceKit SDK's
/// (``FlaggedMessage``, ``FlaggedMessages``, ``FlaggedMessageCopy``), so every staff app and Android share them; these
/// send them on the staff endpoint.
extension VenueManagementClient {
    /// The venue's flagged messages from the last two days, newest first: the ones waiting for staff, and the settled
    /// ones too with `includeReviewed`. Empty on an API without them, or for someone who can't moderate the venue.
    public func flaggedMessages(venueID: String, includeReviewed: Bool = false) async throws -> [FlaggedMessage] {
        try await session.graphQL(FlaggedMessages.query,
                                  variables: FlaggedMessages.queryVariables(venueID: venueID, includeReviewed: includeReviewed),
                                  as: FlaggedMessages.ListResponse.self).messages
    }

    /// Settles one: `minutes` is a cooldown's length, `text` a warning's words or an escalation's note. Returns it as
    /// it now stands.
    @discardableResult
    public func reviewFlaggedMessage(id: String, action: FlaggedMessageAction, minutes: Int? = nil,
                                     text: String? = nil) async throws -> FlaggedMessage? {
        try await session.graphQL(FlaggedMessages.reviewMutation,
                                  variables: FlaggedMessages.reviewVariables(id: id, action: action, minutes: minutes, text: text),
                                  as: FlaggedMessages.ReviewResponse.self).message
    }
}
