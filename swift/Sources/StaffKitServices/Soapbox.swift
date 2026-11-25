import Foundation
import AudienceCore
import StaffKitCore

// Soapbox for the people who publish (the API's doc/SOAPBOX.md): the publications someone runs, their articles from
// draft to published, the op-ed inbox, locale pushes, and for the audience's admins the review queue and trust. Readers'
// side (live articles, op-eds from the apps) is the AudienceKit SDK's `Soapbox.swift`; this is the staff endpoint's.

/// Where an article is between writing and readers.
public enum SoapboxArticleStatus: String, Codable, Sendable, CaseIterable, Hashable {
    /// A reader's op-ed, waiting for the publication.
    case submitted = "SUBMITTED"
    /// An op-ed the publication won't run.
    case declined = "DECLINED"
    case draft = "DRAFT"
    /// Waiting for the audience's admins (a pending publication's articles).
    case inReview = "IN_REVIEW"
    case published = "PUBLISHED"
    case unpublished = "UNPUBLISHED"

    /// The word the apps show for it.
    public var label: String {
        switch self {
        case .submitted: "Op-ed received"
        case .declined: "Declined"
        case .draft: "Draft"
        case .inReview: "In review"
        case .published: "Published"
        case .unpublished: "Unpublished"
        }
    }

    /// A status this build doesn't know yet reads as a draft, so one new value doesn't fail the whole list.
    public init(from decoder: Decoder) throws {
        self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .draft
    }
}

/// The publication's own article, a reader's op-ed, or a standing guide (a Pride guide).
public enum SoapboxArticleKind: String, Codable, Sendable, Hashable {
    case article = "ARTICLE"
    case opEd = "OP_ED"
    case guide = "GUIDE"

    /// A kind this build doesn't know yet (the API added one) reads as the publication's own article, so the list and
    /// the review queue still load instead of failing the whole response.
    public init(from decoder: Decoder) throws {
        self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .article
    }
}

/// Who can read a published article.
public enum SoapboxVisibility: String, Codable, Sendable, CaseIterable, Hashable {
    /// Anyone signed in to the apps.
    case community = "COMMUNITY"
    /// The web too, once the audience's site shows articles.
    case `public` = "PUBLIC"

    /// A visibility this build doesn't know yet reads as the narrower one, signed in to the apps.
    public init(from decoder: Decoder) throws {
        self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .community
    }
}

/// How far the audience trusts a publication.
public enum SoapboxTrust: String, Codable, Sendable, CaseIterable, Hashable {
    /// Each article waits for the audience's admins.
    case pending = "PENDING"
    /// Its managers publish directly.
    case trusted = "TRUSTED"
    /// Nothing new goes out, and what it published is hidden.
    case suspended = "SUSPENDED"

    public var label: String {
        switch self {
        case .pending: "Pending"
        case .trusted: "Trusted"
        case .suspended: "Suspended"
        }
    }

    /// A trust level this build doesn't know yet reads as pending, the most careful one.
    public init(from decoder: Decoder) throws {
        self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .pending
    }
}

/// What ``SoapboxClient/setStatus(of:to:note:publishAt:push:)`` does to an article.
public enum SoapboxArticleAction: String, Sendable, Hashable {
    case submit = "SUBMIT"
    case publish = "PUBLISH"
    case unpublish = "UNPUBLISH"
    case returnToDraft = "RETURN_TO_DRAFT"
    case acceptOpEd = "ACCEPT_OP_ED"
    case declineOpEd = "DECLINE_OP_ED"
}

/// What a locale push asks people to do. Pushes are for showing up, never for money (the "no grifting" rule).
public enum SoapboxPushPurpose: String, Sendable, CaseIterable, Hashable {
    /// Come to an upcoming event the article is about.
    case event = "EVENT"
    case volunteer = "VOLUNTEER"
    /// The audience's admins only: register, mail ballots, early voting, polling places.
    case election = "ELECTION"

    public var label: String {
        switch self {
        case .event: "Come to the event"
        case .volunteer: "Volunteer"
        case .election: "Election info"
        }
    }
}

/// A locale push sent when an article goes live.
public struct SoapboxPush: Sendable, Hashable {
    public let localeIDs: [String]
    public let purpose: SoapboxPushPurpose
    public init(localeIDs: [String], purpose: SoapboxPushPurpose) { self.localeIDs = localeIDs; self.purpose = purpose }
}

/// A venue, event, person or locale, by name: what an article is about, or a publication's person and locale.
public struct SoapboxSubject: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String?
    public init(id: String, name: String?) { self.id = id; self.name = name }
    public var title: String { name ?? "Unnamed" }
}

/// The kinds of thing an article can be about.
public enum SoapboxSubjectKind: String, Sendable, CaseIterable, Hashable, Identifiable {
    case venue, event, person, locale
    public var id: String { rawValue }
    public var plural: String {
        switch self {
        case .venue: "Venues"
        case .event: "Events"
        case .person: "People"
        case .locale: "Locales"
        }
    }
}

/// A publication as the people who run it, and the audience's admins, see it.
public struct SoapboxPublication: Decodable, Sendable, Hashable, Identifiable {
    public let id: String
    /// Its masthead, else its person's name.
    public let name: String
    public let masthead: String?
    public let about: String?
    public let websiteUrl: String?
    public let editorialEmail: String?
    public let photoUrl: String?
    /// Nil when the viewer may not see it (only its managers and admins may).
    public let trust: SoapboxTrust?
    public let trustNote: String?
    public let trusted: Bool
    public let acceptsOpEds: Bool
    public let opEdGuidelines: String?
    /// Its articles link out to its own site, because its publisher doesn't run it here yet.
    public let linksOut: Bool
    public let onboarded: Bool
    public let feedUrl: String?
    public let feedError: String?
    public let locale: SoapboxSubject?
    public let person: SoapboxSubject?
    public let viewerCanManage: Bool
    /// Whether the viewer publishes without the audience approving each article.
    public let viewerCanPublish: Bool

    public init(id: String, name: String, masthead: String? = nil, about: String? = nil, websiteUrl: String? = nil,
                editorialEmail: String? = nil, photoUrl: String? = nil, trust: SoapboxTrust? = .trusted,
                trustNote: String? = nil, trusted: Bool = true, acceptsOpEds: Bool = false, opEdGuidelines: String? = nil,
                linksOut: Bool = false, onboarded: Bool = true, feedUrl: String? = nil, feedError: String? = nil,
                locale: SoapboxSubject? = nil, person: SoapboxSubject? = nil, viewerCanManage: Bool = true,
                viewerCanPublish: Bool = true) {
        self.id = id; self.name = name; self.masthead = masthead; self.about = about; self.websiteUrl = websiteUrl
        self.editorialEmail = editorialEmail; self.photoUrl = photoUrl; self.trust = trust; self.trustNote = trustNote
        self.trusted = trusted; self.acceptsOpEds = acceptsOpEds; self.opEdGuidelines = opEdGuidelines
        self.linksOut = linksOut; self.onboarded = onboarded; self.feedUrl = feedUrl; self.feedError = feedError
        self.locale = locale; self.person = person; self.viewerCanManage = viewerCanManage
        self.viewerCanPublish = viewerCanPublish
    }
}

/// An article or op-ed as its publication sees it. Lists leave out ``body`` and what it's about;
/// ``SoapboxClient/article(id:)`` reads them.
public struct SoapboxArticle: Decodable, Sendable, Hashable, Identifiable {
    public struct Publication: Decodable, Sendable, Hashable {
        public let id: String
        public let name: String
        public init(id: String, name: String) { self.id = id; self.name = name }
    }

    public let id: String
    public let slug: String
    public let title: String
    public let summary: String?
    /// Markdown; nil in lists.
    public let body: String?
    /// Its byline, else the publication's name.
    public let byline: String
    public let kind: SoapboxArticleKind
    public let status: SoapboxArticleStatus?
    /// When it went (or, scheduled, goes) live.
    public let publishedAt: Date?
    /// Published, but not live yet.
    public let scheduled: Bool
    public let edited: Bool
    public let pinned: Bool
    /// A headline and blurb linking to ``canonicalUrl`` (a publication that links out).
    public let teaser: Bool
    public let canonicalUrl: String?
    public let disclosure: String?
    public let heroPhotoUrl: String?
    public let heroAltText: String?
    public let visibility: SoapboxVisibility
    /// Why an admin sent it back, or why an op-ed was declined.
    public let reviewNote: String?
    public let submittedAt: Date?
    /// When its locale push went out.
    public let pushedAt: Date?
    public let updatedAt: Date
    public let viewerCanManage: Bool
    public let publication: Publication
    public let venues: [SoapboxSubject]?
    public let events: [SoapboxSubject]?
    public let people: [SoapboxSubject]?
    public let locales: [SoapboxSubject]?

    public init(id: String, slug: String = "", title: String, summary: String? = nil, body: String? = nil,
                byline: String = "", kind: SoapboxArticleKind = .article, status: SoapboxArticleStatus? = .draft,
                publishedAt: Date? = nil, scheduled: Bool = false, edited: Bool = false, pinned: Bool = false,
                teaser: Bool = false, canonicalUrl: String? = nil, disclosure: String? = nil,
                heroPhotoUrl: String? = nil, heroAltText: String? = nil, visibility: SoapboxVisibility = .community,
                reviewNote: String? = nil, submittedAt: Date? = nil, pushedAt: Date? = nil, updatedAt: Date = Date(),
                viewerCanManage: Bool = true, publication: Publication, venues: [SoapboxSubject]? = nil,
                events: [SoapboxSubject]? = nil, people: [SoapboxSubject]? = nil, locales: [SoapboxSubject]? = nil) {
        self.id = id; self.slug = slug; self.title = title; self.summary = summary; self.body = body
        self.byline = byline; self.kind = kind; self.status = status; self.publishedAt = publishedAt
        self.scheduled = scheduled; self.edited = edited; self.pinned = pinned; self.teaser = teaser
        self.canonicalUrl = canonicalUrl; self.disclosure = disclosure; self.heroPhotoUrl = heroPhotoUrl
        self.heroAltText = heroAltText; self.visibility = visibility; self.reviewNote = reviewNote
        self.submittedAt = submittedAt; self.pushedAt = pushedAt; self.updatedAt = updatedAt
        self.viewerCanManage = viewerCanManage; self.publication = publication; self.venues = venues
        self.events = events; self.people = people; self.locales = locales
    }

    public var isOpEd: Bool { kind == .opEd }

    /// What it's about, of one kind.
    public func subjects(_ kind: SoapboxSubjectKind) -> [SoapboxSubject] {
        switch kind {
        case .venue: venues ?? []
        case .event: events ?? []
        case .person: people ?? []
        case .locale: locales ?? []
        }
    }

    /// Which list it belongs in.
    public var shelf: SoapboxShelf {
        switch status {
        case .submitted: .opEds
        case .draft, .declined, nil: .drafts
        case .inReview: .inReview
        case .published: scheduled ? .scheduled : .published
        case .unpublished: .drafts
        }
    }
}

/// The lists a publication's articles are sorted into.
public enum SoapboxShelf: String, Sendable, CaseIterable, Hashable, Identifiable {
    case drafts, inReview, scheduled, published, opEds
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .drafts: "Drafts"
        case .inReview: "In review"
        case .scheduled: "Scheduled"
        case .published: "Published"
        case .opEds: "Op-ed inbox"
        }
    }
    public var systemImage: String {
        switch self {
        case .drafts: "doc.text"
        case .inReview: "hourglass"
        case .scheduled: "calendar.badge.clock"
        case .published: "newspaper"
        case .opEds: "tray.and.arrow.down"
        }
    }
}

/// What to write into an article. A nil field is left as it is; a new draft needs ``title``.
public struct SoapboxArticleChanges: Sendable, Hashable {
    public var title: String?
    public var summary: String?
    public var body: String?
    /// Empty: the writer's name.
    public var byline: String?
    public var canonicalUrl: String?
    public var disclosure: String?
    /// An image URL or a data: URI; empty removes the photo.
    public var heroPhoto: String?
    public var heroAltText: String?
    /// A picture from the publication's media library as the photo, instead of ``heroPhoto``.
    public var heroMediaID: String?
    public var pinned: Bool?
    public var visibility: SoapboxVisibility?
    /// Replaces what it's about, kind by kind: a kind left out keeps what it had.
    public var subjects: [SoapboxSubjectKind: [String]] = [:]

    public init(title: String? = nil, summary: String? = nil, body: String? = nil, byline: String? = nil,
                canonicalUrl: String? = nil, disclosure: String? = nil, heroPhoto: String? = nil,
                heroAltText: String? = nil, heroMediaID: String? = nil, pinned: Bool? = nil,
                visibility: SoapboxVisibility? = nil, subjects: [SoapboxSubjectKind: [String]] = [:]) {
        self.title = title; self.summary = summary; self.body = body; self.byline = byline
        self.canonicalUrl = canonicalUrl; self.disclosure = disclosure; self.heroPhoto = heroPhoto
        self.heroAltText = heroAltText; self.heroMediaID = heroMediaID; self.pinned = pinned
        self.visibility = visibility; self.subjects = subjects
    }

    var input: [String: GraphQLValue] {
        var input: [String: GraphQLValue] = [:]
        for (key, value) in [("title", title), ("summary", summary), ("body", body), ("byline", byline),
                             ("canonicalUrl", canonicalUrl), ("disclosure", disclosure), ("heroPhoto", heroPhoto),
                             ("heroAltText", heroAltText), ("heroMediaId", heroMediaID)] {
            if let value { input[key] = .string(value) }
        }
        if let pinned { input["pinned"] = .bool(pinned) }
        if let visibility { input["visibility"] = .string(visibility.rawValue) }
        for (kind, ids) in subjects { input[SoapboxClient.subjectInput[kind]!] = .array(ids.map { .string($0) }) }
        return input
    }
}

/// What to change about a publication. A nil field is left as it is; an empty string clears it.
public struct SoapboxPublicationChanges: Sendable, Hashable {
    public var masthead: String?
    public var about: String?
    public var websiteUrl: String?
    public var editorialEmail: String?
    public var acceptsOpEds: Bool?
    public var opEdGuidelines: String?
    /// Empty clears the locale it covers.
    public var localeID: String?
    /// Its RSS or Atom feed; empty stops reading it.
    public var feedUrl: String?

    public init(masthead: String? = nil, about: String? = nil, websiteUrl: String? = nil, editorialEmail: String? = nil,
                acceptsOpEds: Bool? = nil, opEdGuidelines: String? = nil, localeID: String? = nil,
                feedUrl: String? = nil) {
        self.masthead = masthead; self.about = about; self.websiteUrl = websiteUrl; self.editorialEmail = editorialEmail
        self.acceptsOpEds = acceptsOpEds; self.opEdGuidelines = opEdGuidelines; self.localeID = localeID
        self.feedUrl = feedUrl
    }

    var input: [String: GraphQLValue] {
        var input: [String: GraphQLValue] = [:]
        for (key, value) in [("masthead", masthead), ("about", about), ("websiteUrl", websiteUrl),
                             ("editorialEmail", editorialEmail), ("opEdGuidelines", opEdGuidelines),
                             ("feedUrl", feedUrl)] {
            if let value { input[key] = .string(value) }
        }
        if let localeID { input["localeId"] = localeID.isEmpty ? .null : .string(localeID) }
        if let acceptsOpEds { input["acceptsOpEds"] = .bool(acceptsOpEds) }
        return input
    }
}

/// Who is signed in, as Soapbox needs it: whether they run the audience, and the person listings they manage (each can
/// start a publication).
public struct SoapboxViewer: Decodable, Sendable, Hashable {
    public let isAdmin: Bool
    public let people: [SoapboxSubject]
    public init(isAdmin: Bool, people: [SoapboxSubject]) { self.isAdmin = isAdmin; self.people = people }
}

/// The audience's staff endpoint for Soapbox. Every call answers what the API kept, so screens show the server's word.
public struct SoapboxClient: Sendable {
    public let session: AudienceManagementSession
    public init(session: AudienceManagementSession) { self.session = session }

    /// The most articles a list asks for (the API's page cap).
    public static let pageSize = 50

    static let subjectInput: [SoapboxSubjectKind: String] = [
        .venue: "venueIds", .event: "eventIds", .person: "personIds", .locale: "localeIds",
    ]

    static let publicationFields = """
    id name masthead about websiteUrl editorialEmail photoUrl trust trustNote trusted acceptsOpEds opEdGuidelines \
    linksOut onboarded feedUrl feedError locale { id name } person { id name } viewerCanManage viewerCanPublish
    """
    static let articleFields = """
    id slug title summary byline kind status publishedAt scheduled edited pinned teaser canonicalUrl disclosure \
    heroPhotoUrl heroAltText visibility reviewNote submittedAt pushedAt updatedAt viewerCanManage \
    publication { id name }
    """
    static let subjectFields = "venues { id name } events { id name } people { id name } locales { id name }"

    static let viewerQuery = "query SoapboxViewer { me { consoleRole listings { people { id name } } } }"
    static let myPublicationsQuery = "query SoapboxMyPublications { soapbox { myPublications { \(publicationFields) } } }"
    static let publicationsQuery = """
    query SoapboxPublications($trust: [PublicationTrust!]) { soapbox { publications(trust: $trust) { \(publicationFields) } } }
    """
    static let articlesQuery = """
    query SoapboxArticles($id: ID!, $statuses: [ArticleStatus!], $first: Int) {
      soapbox { publication(id: $id) { allArticles(statuses: $statuses, first: $first) { nodes { \(articleFields) } } } }
    }
    """
    static let articleQuery = """
    query SoapboxArticle($id: ID!) { soapbox { article(id: $id) { \(articleFields) body \(subjectFields) } } }
    """
    static let reviewQueueQuery = "query SoapboxReviewQueue { soapbox { reviewQueue { \(articleFields) } } }"
    static let saveArticleMutation = """
    mutation SoapboxSaveArticle($input: ArticleSaveInput!) { saveArticle(input: $input) { article { \(articleFields) body \(subjectFields) } } }
    """
    static let setStatusMutation = """
    mutation SoapboxSetArticleStatus($input: ArticleStatusSetInput!) { setArticleStatus(input: $input) { article { \(articleFields) body \(subjectFields) } } }
    """
    static let deleteArticleMutation = """
    mutation SoapboxDeleteArticle($input: ArticleDeleteInput!) { deleteArticle(input: $input) { article { id } } }
    """
    static let removeArticleMutation = """
    mutation SoapboxRemoveArticle($input: ArticleRemoveInput!) { removeArticle(input: $input) { article { \(articleFields) } } }
    """
    static let savePublicationMutation = """
    mutation SoapboxSavePublication($input: PublicationSaveInput!) { savePublication(input: $input) { publication { \(publicationFields) } } }
    """
    static let setTrustMutation = """
    mutation SoapboxSetPublicationTrust($input: PublicationTrustSetInput!) { setPublicationTrust(input: $input) { publication { \(publicationFields) } } }
    """
    static let venuesQuery = "query SoapboxVenues($search: String) { venues { list(search: $search, first: 25) { nodes { id name } } } }"
    static let eventsQuery = "query SoapboxEvents($search: String) { events { list(search: $search, first: 25) { nodes { id name } } } }"
    static let peopleQuery = "query SoapboxPeople { people { list(first: 200) { nodes { id name } } } }"
    static let localesQuery = "query SoapboxLocales { locales { id name } }"

    private struct Soapbox<Field: Decodable & Sendable>: Decodable, Sendable { let soapbox: Field }

    // MARK: Who and what

    /// Whether they run the audience, and the person listings they manage.
    public func viewer() async throws -> SoapboxViewer {
        struct Listings: Decodable, Sendable { let people: [SoapboxSubject] }
        struct Me: Decodable, Sendable { let consoleRole: String?; let listings: Listings? }
        struct Response: Decodable, Sendable { let me: Me? }
        let me = try await session.graphQL(Self.viewerQuery, as: Response.self).me
        return SoapboxViewer(isAdmin: me?.consoleRole == "ADMIN", people: me?.listings?.people ?? [])
    }

    /// The publications they run (every one for the audience's admins), oldest first.
    public func myPublications() async throws -> [SoapboxPublication] {
        struct Field: Decodable, Sendable { let myPublications: [SoapboxPublication]? }
        return try await session.graphQL(Self.myPublicationsQuery, as: Soapbox<Field>.self).soapbox.myPublications ?? []
    }

    /// The audience's publications with these trusts (admins; everyone else gets the trusted ones), by name.
    public func publications(trust: [SoapboxTrust]) async throws -> [SoapboxPublication] {
        struct Field: Decodable, Sendable { let publications: [SoapboxPublication] }
        return try await session.graphQL(Self.publicationsQuery,
                                         variables: ["trust": .array(trust.map { .string($0.rawValue) })],
                                         as: Soapbox<Field>.self).soapbox.publications
    }

    /// A publication's articles, drafts and op-eds included, last changed first.
    public func articles(publicationID: String, statuses: [SoapboxArticleStatus]? = nil,
                         first: Int = pageSize) async throws -> [SoapboxArticle] {
        struct All: Decodable, Sendable { let allArticles: GraphQLNodes<SoapboxArticle>? }
        struct Field: Decodable, Sendable { let publication: All? }
        var variables: [String: GraphQLValue] = ["id": .string(publicationID), "first": .int(min(first, Self.pageSize))]
        if let statuses { variables["statuses"] = .array(statuses.map { .string($0.rawValue) }) }
        return try await session.graphQL(Self.articlesQuery, variables: variables, as: Soapbox<Field>.self)
            .soapbox.publication?.allArticles?.nodes ?? []
    }

    /// One article with its body and what it's about.
    public func article(id: String) async throws -> SoapboxArticle? {
        struct Field: Decodable, Sendable { let article: SoapboxArticle? }
        return try await session.graphQL(Self.articleQuery, variables: ["id": .string(id)], as: Soapbox<Field>.self)
            .soapbox.article
    }

    /// Articles waiting for the audience's admins, oldest first. Empty for everyone else.
    public func reviewQueue() async throws -> [SoapboxArticle] {
        struct Field: Decodable, Sendable { let reviewQueue: [SoapboxArticle]? }
        return try await session.graphQL(Self.reviewQueueQuery, as: Soapbox<Field>.self).soapbox.reviewQueue ?? []
    }

    // MARK: Writing

    /// Starts a draft for a publication.
    public func createArticle(publicationID: String, _ changes: SoapboxArticleChanges) async throws -> SoapboxArticle {
        var input = changes.input
        input["publicationId"] = .string(publicationID)
        return try await saveArticle(input)
    }

    /// Changes an article. An op-ed has to be accepted before it can be edited.
    public func updateArticle(id: String, _ changes: SoapboxArticleChanges) async throws -> SoapboxArticle {
        var input = changes.input
        input["id"] = .string(id)
        return try await saveArticle(input)
    }

    private func saveArticle(_ input: [String: GraphQLValue]) async throws -> SoapboxArticle {
        struct Payload: Decodable, Sendable { let article: SoapboxArticle? }
        struct Response: Decodable, Sendable { let saveArticle: Payload }
        let response = try await session.graphQL(Self.saveArticleMutation, variables: ["input": .object(input)],
                                                 as: Response.self)
        guard let article = response.saveArticle.article else { throw AudienceKitError.decoding("The article was missing") }
        return article
    }

    /// Moves an article on: submit it for review, publish it now or at `publishAt` (with a locale push), unpublish it,
    /// send it back to a draft, or accept or decline an op-ed. `note` is the writer's or publication's to read.
    ///
    /// A push is checked here first: one asking for money is refused before it's sent (``SoapboxPushRules``).
    public func setStatus(of articleID: String, to action: SoapboxArticleAction, note: String? = nil,
                          publishAt: Date? = nil, push: SoapboxPush? = nil,
                          article: SoapboxArticle? = nil) async throws -> SoapboxArticle {
        struct Payload: Decodable, Sendable { let article: SoapboxArticle? }
        struct Response: Decodable, Sendable { let setArticleStatus: Payload }
        var input: [String: GraphQLValue] = ["id": .string(articleID), "action": .string(action.rawValue)]
        if let note = note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty { input["note"] = .string(note) }
        if action == .publish {
            if let publishAt { input["publishAt"] = .string(ISO8601.string(from: publishAt)) }
            if let push, !push.localeIDs.isEmpty {
                if let article, let reason = SoapboxPushRules.refusal(title: article.title, summary: article.summary) {
                    throw AudienceKitError.decoding(reason)
                }
                input["pushLocaleIds"] = .array(push.localeIDs.map { .string($0) })
                input["pushPurpose"] = .string(push.purpose.rawValue)
            }
        }
        let response = try await session.graphQL(Self.setStatusMutation, variables: ["input": .object(input)],
                                                 as: Response.self)
        guard let moved = response.setArticleStatus.article else { throw AudienceKitError.decoding("The article was missing") }
        return moved
    }

    /// Deletes an article for good (unpublishing takes it down for now).
    public func deleteArticle(id: String) async throws {
        _ = try await session.graphQL(Self.deleteArticleMutation, variables: ["input": .object(["id": .string(id)])],
                                      as: GraphQLValue.self)
    }

    // MARK: Publications

    /// Starts publishing as a person listing they manage. It waits for the audience to trust it, unless an admin
    /// starts it.
    public func startPublication(personID: String, _ changes: SoapboxPublicationChanges = .init()) async throws -> SoapboxPublication {
        var input = changes.input
        input["personId"] = .string(personID)
        return try await savePublication(input)
    }

    /// Changes a publication's masthead, about, op-eds and the rest. Saving it onboards a publication that linked out.
    public func updatePublication(id: String, _ changes: SoapboxPublicationChanges) async throws -> SoapboxPublication {
        var input = changes.input
        input["id"] = .string(id)
        return try await savePublication(input)
    }

    private func savePublication(_ input: [String: GraphQLValue]) async throws -> SoapboxPublication {
        struct Payload: Decodable, Sendable { let publication: SoapboxPublication? }
        struct Response: Decodable, Sendable { let savePublication: Payload }
        let response = try await session.graphQL(Self.savePublicationMutation, variables: ["input": .object(input)],
                                                 as: Response.self)
        guard let publication = response.savePublication.publication else {
            throw AudienceKitError.decoding("The publication was missing")
        }
        return publication
    }

    // MARK: The audience's admins

    /// Trusts, holds or suspends a publication, with why.
    public func setTrust(of publicationID: String, to trust: SoapboxTrust, note: String? = nil) async throws -> SoapboxPublication {
        struct Payload: Decodable, Sendable { let publication: SoapboxPublication? }
        struct Response: Decodable, Sendable { let setPublicationTrust: Payload }
        var input: [String: GraphQLValue] = ["id": .string(publicationID), "trust": .string(trust.rawValue)]
        if let note = note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty { input["note"] = .string(note) }
        let response = try await session.graphQL(Self.setTrustMutation, variables: ["input": .object(input)],
                                                 as: Response.self)
        guard let publication = response.setPublicationTrust.publication else {
            throw AudienceKitError.decoding("The publication was missing")
        }
        return publication
    }

    /// Takes an article down as the audience, whatever its publication says, or puts it back.
    public func removeArticle(id: String, removed: Bool = true, note: String? = nil) async throws -> SoapboxArticle {
        struct Payload: Decodable, Sendable { let article: SoapboxArticle? }
        struct Response: Decodable, Sendable { let removeArticle: Payload }
        var input: [String: GraphQLValue] = ["id": .string(id), "removed": .bool(removed)]
        if let note = note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty { input["note"] = .string(note) }
        let response = try await session.graphQL(Self.removeArticleMutation, variables: ["input": .object(input)],
                                                 as: Response.self)
        guard let article = response.removeArticle.article else { throw AudienceKitError.decoding("The article was missing") }
        return article
    }

    // MARK: Pickers

    /// Venues, events, people or locales to tag an article with, matching `search` (by name, for people and locales,
    /// which the API lists whole).
    public func subjects(_ kind: SoapboxSubjectKind, matching search: String) async throws -> [SoapboxSubject] {
        struct List: Decodable, Sendable { let list: GraphQLNodes<SoapboxSubject> }
        let trimmed = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let variables: [String: GraphQLValue] = trimmed.isEmpty ? [:] : ["search": .string(trimmed)]
        let found: [SoapboxSubject]
        switch kind {
        case .venue:
            struct Response: Decodable, Sendable { let venues: List }
            found = try await session.graphQL(Self.venuesQuery, variables: variables, as: Response.self).venues.list.nodes
        case .event:
            struct Response: Decodable, Sendable { let events: List }
            found = try await session.graphQL(Self.eventsQuery, variables: variables, as: Response.self).events.list.nodes
        case .person:
            struct Response: Decodable, Sendable { let people: List }
            found = try await session.graphQL(Self.peopleQuery, as: Response.self).people.list.nodes
        case .locale:
            struct Response: Decodable, Sendable { let locales: [SoapboxSubject] }
            found = try await session.graphQL(Self.localesQuery, as: Response.self).locales
        }
        guard !trimmed.isEmpty, kind == .person || kind == .locale else { return found }
        return found.filter { $0.title.localizedCaseInsensitiveContains(trimmed) }
    }
}

/// The "no grifting" rule as the apps check it before sending, the same words the API refuses
/// (`ArticlePush::FUNDRAISING`): a push asks people to show up, never to pay. Fundraising stays on quiet surfaces.
public enum SoapboxPushRules {
    /// The API's pattern, case-insensitive.
    static let fundraising = #"\b(donat\w*|chip\s+in|contribut\w*|fund-?rais\w*|give\s+now|pledge|matching\s+gift|match(ed)?\s+\d|paypal|venmo|cash\s?app|act\s?blue|win\s?red|deadline\s+to\s+give)\b|\$\s?\d"#

    /// Why a push for this headline and summary would be refused, or nil when it may go.
    public static func refusal(title: String, summary: String?) -> String? {
        let text = "\(title) \(summary ?? "")"
        guard text.range(of: fundraising, options: [.regularExpression, .caseInsensitive]) != nil else { return nil }
        return "Pushes can’t ask for money: fundraising stays on quiet surfaces like tipping. Change the headline or summary, or publish without a push."
    }
}
