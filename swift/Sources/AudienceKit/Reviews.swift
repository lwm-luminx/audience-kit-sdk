import AudienceCore
import Foundation

// Reviews: written takes on a venue, event or person (no rating, on purpose). Some are a line quoted from a news
// article (City Weekly's guide to Salt Lake's LGBTQ bars, a line on each bar it names): show those as a quote from the
// article's publication and open the article to read the rest. APIs from before reviews have none, and helpers here
// return nothing for them.

/// A review of a venue, event or person.
public struct Review: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    /// What it says, in Markdown.
    public let body: String
    public let publishedAt: Date?
    /// The news article it's quoted from, when it is a line from one: credit ``Article/publication`` and open the
    /// article (a ``Article/teaser`` opens ``Article/canonicalUrl``).
    public let article: Article?

    public init(id: String, body: String, publishedAt: Date? = nil, article: Article? = nil) {
        self.id = id
        self.body = body
        self.publishedAt = publishedAt
        self.article = article
    }

    /// Whether it's a line quoted from a news article.
    public var isQuote: Bool { article != nil }

    /// Who to credit it to: the article's publication ("City Weekly") when it is a quote.
    public var sourceName: String? { article?.publication.name }
}

extension Queries {
    static let reviewTypes = ["Venue", "Event", "Person", "Review", "Article", "Publication"]

    static func reviews(of topic: ArticleTopic) -> (SchemaShape) -> String {
        let (type, path): (String, (String) -> String) = switch topic {
        case .venue: ("Venue", { "venues { venue(id: $id) { \($0) } }" })
        case .event: ("Event", { "events { event(id: $id) { \($0) } }" })
        case .person: ("Person", { "people { person(id: $id) { \($0) } }" })
        case .locale: ("Locale", { "locale(id: $id) { \($0) }" })
        }
        return { shape in
            guard shape.has(type, "reviews") else { return noSoapbox("Reviews") }
            let article = shape.has("Review", "article") ? " article { \(articleFieldsFor(shape)) }" : ""
            return "query Reviews($id: ID!) { \(path("reviews { id body publishedAt\(article) }")) }"
        }
    }
}

/// A listing's `reviews`, under whichever root field reads the listing.
struct ReviewsResponse: Decodable, Sendable {
    struct Listing: Decodable, Sendable { var reviews: [Review]? }
    struct Venues: Decodable, Sendable { var venue: Listing? }
    struct Events: Decodable, Sendable { var event: Listing? }
    struct People: Decodable, Sendable { var person: Listing? }

    var venues: Venues?
    var events: Events?
    var people: People?
    var locale: Listing?

    var reviews: [Review] { (venues?.venue ?? events?.event ?? people?.person ?? locale)?.reviews ?? [] }
}

extension AudienceSession {
    /// A venue's, event's or person's published reviews, newest first: quotes from news articles among them
    /// (``Review/isQuote``). Empty for a locale, and when the audience's API has no reviews yet.
    public func reviews(of topic: ArticleTopic) async throws -> [Review] {
        let id: String
        switch topic {
        case let .venue(value), let .event(value), let .person(value): id = value
        case .locale: return []
        }
        return try await graphQL(types: Queries.reviewTypes, variables: ["id": .string(id)], operationName: "Reviews",
                                 as: ReviewsResponse.self, document: Queries.reviews(of: topic)).reviews
    }
}
