import Foundation
import AudienceCore
import StaffKitCore

// The audience's own cards (promoted, sponsored, charity and announcement cards in its apps' feeds), managed by its
// admins from Soapbox the way Olympus Audience › Cards does. The documents and models are the SDK's `AudienceCards`
// (AudienceCore), shared with Android; this sends them on the staff endpoint. The API lets only the audience's admins.

/// The audience's own cards, with the categories it publishes and how much advertising it carries.
public struct AudienceCardList: Sendable, Hashable {
    public var cards: [AudienceCard]
    public var categories: [AudienceCardCategory]
    public var level: AudienceCardsLevel

    public init(cards: [AudienceCard] = [], categories: [AudienceCardCategory] = AudienceCardCategory.defaults,
                level: AudienceCardsLevel = .unknown) {
        self.cards = cards; self.categories = categories; self.level = level
    }
}

extension SoapboxClient {
    public func audienceCards() async throws -> AudienceCardList {
        let response = try await session.graphQL(AudienceCards.cardsQuery, as: AudienceCards.CardsResponse.self)
        return AudienceCardList(cards: response.cards, categories: response.categories, level: response.level)
    }

    /// Saves a new or changed card; the API answers with it as stored.
    public func saveCard(_ draft: AudienceCardDraft) async throws -> AudienceCard? {
        try await session.graphQL(AudienceCards.saveMutation, variables: AudienceCards.saveVariables(draft),
                                  as: AudienceCards.SaveResponse.self).card
    }

    public func deleteCard(id: String) async throws {
        _ = try await session.graphQL(AudienceCards.deleteMutation, variables: AudienceCards.idVariables(id),
                                      as: AudienceCards.DeleteResponse.self)
    }
}
