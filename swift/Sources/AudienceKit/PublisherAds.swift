import AudienceCore
import Foundation

// Soapbox publishers' ads on their own content (API doc/SOAPBOX.md "Publisher ads and the media library"): a sponsor's
// card a publication sells and shows after an article in the reader, or on its page. Labelled "Ad" and "Sold by
// <publication>", placed by context only, never shown on a teaser or op-ed, and never to a reader who tipped the
// publication to read it without ads. The publication keeps all of the money. Report it shown with
// ``AudienceSession/recordCardViews(promoIDs:layoutID:)`` like any promoted card, so its sponsor gets their one number.

extension Queries {
    static let publisherAdFields = """
    id category label sponsorName soldBy \(cardContentFields)
    """

    static func articleAd(_ shape: SchemaShape) -> String {
        guard shape.has("Audience", "soapbox"), shape.has("Article", "ad") else { return noSoapbox("ArticleAd") }
        return "query ArticleAd($id: ID!) { soapbox { article(id: $id) { id ad { \(publisherAdFields) } } } }"
    }

    static func publicationAd(_ shape: SchemaShape) -> String {
        guard shape.has("Audience", "soapbox"), shape.has("Publication", "ad") else {
            return noSoapbox("PublicationAd")
        }
        return "query PublicationAd($id: ID!) { soapbox { publication(id: $id) { id ad { \(publisherAdFields) } } } }"
    }
}

struct PublisherAdResponse: Decodable, Sendable {
    struct Holder: Decodable, Sendable { var ad: Lenient<PromoCard>? }
    struct Mixin: Decodable, Sendable { var article: Holder?; var publication: Holder? }
    var soapbox: Mixin?

    var ad: PromoCard? { (soapbox?.article ?? soapbox?.publication)?.ad?.value }
}

extension AudienceSession {
    /// The ad to show after an article in the reader, sold by its publication; nil when there is none (a teaser, an
    /// op-ed, a publication that sells none, a reader reading it without ads, or an API without publisher ads).
    public func publisherAd(articleID: String) async throws -> PromoCard? {
        try await graphQL(types: Queries.soapboxTypes, variables: ["id": .string(articleID)],
                          operationName: "ArticleAd", as: PublisherAdResponse.self,
                          document: Queries.articleAd).ad
    }

    /// The ad to show on a publication's page, on the same terms.
    public func publisherAd(publicationID: String) async throws -> PromoCard? {
        try await graphQL(types: Queries.soapboxTypes, variables: ["id": .string(publicationID)],
                          operationName: "PublicationAd", as: PublisherAdResponse.self,
                          document: Queries.publicationAd).ad
    }
}

/// What the apps say on and about a publisher's ad.
public enum PublisherAdCopy {
    /// Under the ad: who sold it.
    public static func soldBy(_ publication: String) -> String { "Sold by \(publication)" }
    /// The card menu's explanation.
    public static let whyTitle = "Why am I seeing this?"
    public static func why(_ publication: String) -> String {
        "\(publication) sold this ad to support its writers. It's shown because of what you're reading, never "
            + "because of anything about you, and \(publication) keeps all of the money."
    }
    /// The card menu's report action.
    public static let report = "Report this ad"
}
