import AudienceCore
import Foundation

// Soapbox: articles from the audience's publications (a newspaper such as QSaltLake, a candidate), and op-eds readers
// send them from the apps. The API's `soapbox` mixin and each venue's, event's, person's and locale's `articles`;
// audiences without the Soapbox module have neither, so every helper here returns nothing for them.

/// Who wrote an article: the publication, or a reader who sent it as an op-ed.
public enum ArticleKind: String, Codable, Sendable, CaseIterable {
    case article = "ARTICLE"
    case opEd = "OP_ED"
}

/// Where an article stands. Readers only see it on their own op-eds (``AudienceSession/myOpEds()``).
public enum ArticleStatus: String, Codable, Sendable, CaseIterable {
    /// An op-ed waiting for the publication.
    case submitted = "SUBMITTED"
    /// An op-ed the publication won't run; ``Article/reviewNote`` says why.
    case declined = "DECLINED"
    case draft = "DRAFT"
    case inReview = "IN_REVIEW"
    case published = "PUBLISHED"
    case unpublished = "UNPUBLISHED"
}

/// A publication as an article shows it: its name, photo and whether it takes op-eds.
public struct PublicationSummary: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let photoUrl: String?
    public let trusted: Bool
    public let acceptsOpEds: Bool

    public init(id: String, name: String, photoUrl: String? = nil, trusted: Bool = false, acceptsOpEds: Bool = false) {
        self.id = id
        self.name = name
        self.photoUrl = photoUrl
        self.trusted = trusted
        self.acceptsOpEds = acceptsOpEds
    }
}

/// A venue, event, person or locale an article is about, by name.
public struct ArticleSubject: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String?

    public init(id: String, name: String? = nil) {
        self.id = id
        self.name = name
    }
}

/// A publication: a ``Person`` listing that publishes (a newspaper, a candidate), with its masthead.
public struct Publication: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    /// Its masthead, else its person's name.
    public let name: String
    public let masthead: String?
    public let about: String?
    public let websiteUrl: String?
    public let photoUrl: String?
    /// Whether the audience trusts it to publish without approving each article.
    public let trusted: Bool
    /// Whether readers can send it op-eds (``AudienceSession/submitOpEd(publicationID:title:body:summary:byline:)``).
    public let acceptsOpEds: Bool
    /// What it asks of op-eds: length, topics, how it edits.
    public let opEdGuidelines: String?
    public let locale: ArticleSubject?
    public let person: ArticleSubject?

    public init(id: String, name: String, masthead: String? = nil, about: String? = nil, websiteUrl: String? = nil,
                photoUrl: String? = nil, trusted: Bool = false, acceptsOpEds: Bool = false,
                opEdGuidelines: String? = nil, locale: ArticleSubject? = nil, person: ArticleSubject? = nil)
    {
        self.id = id
        self.name = name
        self.masthead = masthead
        self.about = about
        self.websiteUrl = websiteUrl
        self.photoUrl = photoUrl
        self.trusted = trusted
        self.acceptsOpEds = acceptsOpEds
        self.opEdGuidelines = opEdGuidelines
        self.locale = locale
        self.person = person
    }
}

/// An article or op-ed. Lists leave out ``body``; ``AudienceSession/article(id:)`` reads it.
public struct Article: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let slug: String
    public let title: String
    public let summary: String?
    /// What it says, in Markdown; nil in lists.
    public let body: String?
    /// Who it shows as written by: its byline, else the publication's name.
    public let byline: String
    public let kind: ArticleKind
    public let publishedAt: Date?
    /// Whether it changed after it was published.
    public let edited: Bool
    public let pinned: Bool
    /// A summary that links to ``canonicalUrl`` instead of a body.
    public let teaser: Bool
    public let canonicalUrl: String?
    /// What ties the publication to what it covers (its own gala, a sponsor): show it above the article.
    public let disclosure: String?
    public let heroPhotoUrl: String?
    public let heroAltText: String?
    public let publication: PublicationSummary
    public let venues: [ArticleSubject]?
    public let events: [ArticleSubject]?
    public let people: [ArticleSubject]?
    public let locales: [ArticleSubject]?
    /// The signed-in writer's own op-eds only: where it stands, and why it was declined.
    public let status: ArticleStatus?
    public let reviewNote: String?
    public let submittedAt: Date?

    public init(id: String, slug: String = "", title: String, summary: String? = nil, body: String? = nil,
                byline: String = "", kind: ArticleKind = .article, publishedAt: Date? = nil, edited: Bool = false,
                pinned: Bool = false, teaser: Bool = false, canonicalUrl: String? = nil, disclosure: String? = nil,
                heroPhotoUrl: String? = nil, heroAltText: String? = nil, publication: PublicationSummary,
                venues: [ArticleSubject]? = nil, events: [ArticleSubject]? = nil, people: [ArticleSubject]? = nil,
                locales: [ArticleSubject]? = nil, status: ArticleStatus? = nil, reviewNote: String? = nil,
                submittedAt: Date? = nil)
    {
        self.id = id
        self.slug = slug
        self.title = title
        self.summary = summary
        self.body = body
        self.byline = byline
        self.kind = kind
        self.publishedAt = publishedAt
        self.edited = edited
        self.pinned = pinned
        self.teaser = teaser
        self.canonicalUrl = canonicalUrl
        self.disclosure = disclosure
        self.heroPhotoUrl = heroPhotoUrl
        self.heroAltText = heroAltText
        self.publication = publication
        self.venues = venues
        self.events = events
        self.people = people
        self.locales = locales
        self.status = status
        self.reviewNote = reviewNote
        self.submittedAt = submittedAt
    }

    /// Whether to show it as an op-ed ("Op-ed" label, the writer's byline).
    public var isOpEd: Bool { kind == .opEd }
}

/// What ``AudienceSession/articles(about:first:)`` lists articles about.
public enum ArticleTopic: Sendable, Hashable {
    case venue(String)
    case event(String)
    case person(String)
    /// A locale's news: about it or anything in it, or by a publication covering it, from the last 30 days.
    case locale(String)
}

extension Queries {
    /// The types the Soapbox documents depend on: the root's `soapbox` and each listing's `articles`.
    static let soapboxTypes = ["Audience", "Venue", "Event", "Person", "Locale"]

    static let publicationSummaryFields = "id name photoUrl trusted acceptsOpEds"
    static let articleFields = """
    id slug title summary byline kind publishedAt edited pinned teaser canonicalUrl disclosure heroPhotoUrl \
    heroAltText publication { \(publicationSummaryFields) }
    """
    static let articleSubjectFields = "venues { id name } events { id name } people { id name } locales { id name }"
    static let publicationFields = """
    id name masthead about websiteUrl photoUrl trusted acceptsOpEds opEdGuidelines locale { id name } \
    person { id name }
    """

    /// The document when the audience has no Soapbox: asks for nothing the helpers decode, under the operation's name.
    static func noSoapbox(_ name: String) -> String { "query \(name) { id }" }

    static func articles(_ shape: SchemaShape) -> String {
        guard shape.has("Audience", "soapbox") else { return noSoapbox("Articles") }
        return """
        query Articles($localeId: ID, $publicationId: ID, $first: Int) {
          soapbox {
            articles(localeId: $localeId, publicationId: $publicationId, first: $first) { nodes { \(articleFields) } }
          }
        }
        """
    }

    static func article(_ shape: SchemaShape) -> String {
        guard shape.has("Audience", "soapbox") else { return noSoapbox("Article") }
        return """
        query Article($id: ID!) {
          soapbox { article(id: $id) { \(articleFields) body \(articleSubjectFields) } }
        }
        """
    }

    static func publications(_ shape: SchemaShape) -> String {
        guard shape.has("Audience", "soapbox") else { return noSoapbox("Publications") }
        return "query Publications { soapbox { publications { \(publicationFields) } } }"
    }

    static func publication(_ shape: SchemaShape) -> String {
        guard shape.has("Audience", "soapbox") else { return noSoapbox("Publication") }
        return "query Publication($id: ID!) { soapbox { publication(id: $id) { \(publicationFields) } } }"
    }

    static func myOpEds(_ shape: SchemaShape) -> String {
        guard shape.has("Audience", "soapbox") else { return noSoapbox("MyOpEds") }
        return """
        query MyOpEds {
          soapbox { myOpEds { \(articleFields) status reviewNote submittedAt } }
        }
        """
    }

    static func articles(about topic: ArticleTopic) -> (type: String, document: (SchemaShape) -> String) {
        let (type, path): (String, (String) -> String) = switch topic {
        case .venue: ("Venue", { "venues { venue(id: $id) { \($0) } }" })
        case .event: ("Event", { "events { event(id: $id) { \($0) } }" })
        case .person: ("Person", { "people { person(id: $id) { \($0) } }" })
        case .locale: ("Locale", { "locale(id: $id) { \($0) }" })
        }
        return (type, { shape in
            guard shape.has(type, "articles") else { return noSoapbox("ArticlesAbout") }
            return """
            query ArticlesAbout($id: ID!, $first: Int) {
              \(path("articles { list(first: $first) { nodes { \(articleFields) } } }"))
            }
            """
        })
    }

    static let submitOpEd = """
    mutation SubmitOpEd($publicationId: ID!, $title: String!, $body: String!, $summary: String, $byline: String) {
      submitOpEd(input: { publicationId: $publicationId, title: $title, body: $body, summary: $summary,
                          byline: $byline }) {
        article { \(articleFields) status reviewNote submittedAt }
      }
    }
    """
}

/// `soapbox { … }` on the root, the audience; nil when the audience has no Soapbox.
struct SoapboxResponse: Decodable, Sendable {
    struct Mixin: Decodable, Sendable {
        var articles: Nodes<Article>?
        var article: Article?
        var publications: [Publication]?
        var publication: Publication?
        var myOpEds: [Article]?
    }

    var soapbox: Mixin?
}

/// A listing's `articles { list { nodes } }`, under whichever root field reads the listing.
struct ArticlesAboutResponse: Decodable, Sendable {
    struct Listing: Decodable, Sendable {
        struct Mixin: Decodable, Sendable { var list: Nodes<Article>? }
        var articles: Mixin?
    }

    struct Venues: Decodable, Sendable { var venue: Listing? }
    struct Events: Decodable, Sendable { var event: Listing? }
    struct People: Decodable, Sendable { var person: Listing? }

    var venues: Venues?
    var events: Events?
    var people: People?
    var locale: Listing?

    var articles: [Article] {
        (venues?.venue ?? events?.event ?? people?.person ?? locale)?.articles?.list?.nodes ?? []
    }
}

struct SubmitOpEdResponse: Decodable, Sendable {
    struct Payload: Decodable, Sendable { var article: Article? }
    var submitOpEd: Payload?
}

/// The API's answer to ``AudienceSession/submitOpEd(publicationID:title:body:summary:byline:)`` had no article.
public struct OpEdNotSubmitted: Error, Sendable {}

extension AudienceSession {
    /// The audience's live articles, pinned first, then newest: a locale's news, or one publication's, when given.
    /// Empty when the audience doesn't have Soapbox.
    public func articles(localeID: String? = nil, publicationID: String? = nil, first: Int? = nil) async throws
        -> [Article]
    {
        var variables: [String: GraphQLValue] = [:]
        if let localeID { variables["localeId"] = .string(localeID) }
        if let publicationID { variables["publicationId"] = .string(publicationID) }
        if let first { variables["first"] = .int(first) }
        return try await graphQL(types: Queries.soapboxTypes, variables: variables, operationName: "Articles",
                                 as: SoapboxResponse.self, document: Queries.articles).soapbox?.articles?.nodes ?? []
    }

    /// One article with its body and what it's about: a live one, or one the signed-in person may see before it is
    /// (their own op-ed). Nil when there's no such article, or the audience doesn't have Soapbox.
    public func article(id: String) async throws -> Article? {
        try await graphQL(types: Queries.soapboxTypes, variables: ["id": .string(id)], operationName: "Article",
                          as: SoapboxResponse.self, document: Queries.article).soapbox?.article
    }

    /// Live articles about a venue, event or person, newest first, or a locale's news ("In the news").
    public func articles(about topic: ArticleTopic, first: Int? = nil) async throws -> [Article] {
        let id: String = switch topic {
        case let .venue(id), let .event(id), let .person(id), let .locale(id): id
        }
        var variables: [String: GraphQLValue] = ["id": .string(id)]
        if let first { variables["first"] = .int(first) }
        let query = Queries.articles(about: topic)
        return try await graphQL(types: Queries.soapboxTypes, variables: variables, operationName: "ArticlesAbout",
                                 as: ArticlesAboutResponse.self, document: query.document).articles
    }

    /// The audience's publications (its admins can ask for other trusts on the staff endpoint).
    public func publications() async throws -> [Publication] {
        try await graphQL(types: Queries.soapboxTypes, operationName: "Publications", as: SoapboxResponse.self,
                          document: Queries.publications).soapbox?.publications ?? []
    }

    /// One publication, for its page and its "Write an op-ed" button.
    public func publication(id: String) async throws -> Publication? {
        try await graphQL(types: Queries.soapboxTypes, variables: ["id": .string(id)], operationName: "Publication",
                          as: SoapboxResponse.self, document: Queries.publication).soapbox?.publication
    }

    /// The op-eds the signed-in person sent, newest first, with ``Article/status`` and ``Article/reviewNote``.
    public func myOpEds() async throws -> [Article] {
        try await graphQL(types: Queries.soapboxTypes, operationName: "MyOpEds", as: SoapboxResponse.self,
                          document: Queries.myOpEds).soapbox?.myOpEds ?? []
    }

    /// Sends a publication an op-ed under the signed-in person's name (`byline` overrides it). The publication runs
    /// it (edited, bylined to the writer) or declines it with a note; ``myOpEds()`` shows which. A writer can have three
    /// waiting at once, and only a publication with ``Publication/acceptsOpEds`` takes them.
    @discardableResult
    public func submitOpEd(publicationID: String, title: String, body: String, summary: String? = nil,
                           byline: String? = nil) async throws -> Article
    {
        let variables: [String: GraphQLValue] = [
            "publicationId": .string(publicationID), "title": .string(title), "body": .string(body),
            "summary": summary.map { .string($0) } ?? .null, "byline": byline.map { .string($0) } ?? .null,
        ]
        let response = try await graphQL(Queries.submitOpEd, variables: variables, operationName: "SubmitOpEd",
                                         as: SubmitOpEdResponse.self)
        guard let article = response.submitOpEd?.article else { throw OpEdNotSubmitted() }
        return article
    }
}

/// The words around Soapbox, shared with Android so both apps say the same thing.
public enum SoapboxCopy {
    public static let news = "News"
    public static let inTheNews = "In the news"
    public static let opEd = "Op-ed"
    public static let writeOpEd = "Write an op-ed"
    public static let opEdSent = "Sent. The publication will let you know if it runs it."
    public static let edited = "Updated"
    public static let readMore = "Read on the publication's site"
    public static func status(_ status: ArticleStatus) -> String {
        switch status {
        case .submitted: "Waiting for the publication"
        case .declined: "Not running"
        case .draft, .inReview: "Being edited"
        case .published: "Published"
        case .unpublished: "Taken down"
        }
    }
}
