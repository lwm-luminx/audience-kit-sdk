import Foundation

/// What Add with AI fills out: the API's `ListingResearchKind`.
public enum ListingResearchKind: String, Codable, Sendable, CaseIterable, Hashable {
    case person = "PERSON"
    case venue = "VENUE"
}

/// Where an Add with AI request is: the API's `ListingResearchState`.
public enum ListingResearchState: String, Decodable, Sendable, Hashable {
    case pending = "PENDING"
    case running = "RUNNING"
    case done = "DONE"
    case failed = "FAILED"

    /// Whether to stop asking: the draft is ready or it failed.
    public var isFinished: Bool { self == .done || self == .failed }
}

/// An Add with AI request and, once ``ListingResearchState/done``, the draft the audience's AI provider filled out
/// (`Audience.listingResearch` on the staff endpoint). Nothing is saved from it: the app opens its editor prefilled with
/// it, and the curator saves with createPerson or createVenue.
public struct ListingResearchDraft: Decodable, Sendable, Identifiable, Hashable {
    /// A profile it found, by provider and handle as `SocialLinkInput` takes them.
    public struct Link: Decodable, Sendable, Hashable {
        public let provider: String
        public let handle: String
        public let url: String
        public init(provider: String, handle: String, url: String) {
            self.provider = provider; self.handle = handle; self.url = url
        }
    }
    /// A page it opened.
    public struct Page: Decodable, Sendable, Hashable {
        public let url: String
        public let title: String
    }
    /// A listing the audience already has with the same name.
    public struct Match: Decodable, Sendable, Hashable, Identifiable {
        public let id: String
        public let name: String?
    }
    public struct Ref: Decodable, Sendable, Hashable { public let id: String }

    public let id: String
    public let state: ListingResearchState
    public let kind: ListingResearchKind
    public let query: String
    public let found: Bool
    public let name: String?
    /// For the curator: who or what it is, and what the provider wasn't sure of.
    public let summary: String?
    public let description: String?
    public let website: String?
    public let city: String?
    public let address: String?
    public let phone: String?
    /// A venue's Google place, for `VenueInput.googlePlaceId`.
    public let googlePlaceId: String?
    /// TALENT or ORGANIZATION, for a person.
    public let personKind: String?
    public let homeVenueName: String?
    public let homeVenue: Ref?
    public let locale: Ref?
    public let links: [Link]
    public let evidence: [Page]
    public let matches: [Match]
    public let error: String?

    /// Its profile on `provider` (instagram, tiktok…), as a link, or "".
    public func link(_ provider: String) -> String { links.first { $0.provider == provider }?.url ?? "" }

    /// Its links as `socialLinks` takes them.
    public var socialLinks: GraphQLValue {
        .array(links.map { .object(["provider": .string($0.provider), "handle": .string($0.handle)]) })
    }
}

/// The GraphQL for Add with AI in Focus, shared by the staff apps (and Android, word for word). It runs on the staff
/// endpoint, which this SDK doesn't call (``GraphQLEndpoint``): StaffKit's session sends ``startMutation``, then asks
/// ``query`` every ``pollInterval`` until the request ``ListingResearchState/isFinished`` or ``timeout`` passes.
public enum ListingResearch {
    /// How often to ask again while it researches.
    public static let pollInterval: Duration = .seconds(2)
    /// When to stop asking: the provider's own limit is three minutes.
    public static let timeout: Duration = .seconds(200)

    public static let listingResearchFields = """
        id state kind query found name summary description website city address phone googlePlaceId personKind \
        homeVenueName homeVenue { id } locale { id } links { provider handle url } evidence { url title } \
        matches { id name } error
        """

    public static let startMutation = """
        # endpoint: staff
        mutation FocusResearchListing($input: ResearchListingInput!) { \
        researchListing(input: $input) { listingResearch { \(listingResearchFields) } } }
        """

    public static let query = """
        # endpoint: staff
        query FocusListingResearch($id: ID!) { listingResearch(id: $id) { \(listingResearchFields) } }
        """

    /// The variables for ``startMutation``: what the curator typed, and the locale they're curating, if one.
    public static func startVariables(kind: ListingResearchKind, query: String, localeID: String?) -> [String: GraphQLValue] {
        var input: [String: GraphQLValue] = [
            "kind": .string(kind.rawValue), "query": .string(query.trimmingCharacters(in: .whitespacesAndNewlines))
        ]
        if let localeID, !localeID.isEmpty { input["localeId"] = .string(localeID) }
        return ["input": .object(input)]
    }

    /// The variables for ``query``.
    public static func queryVariables(id: String) -> [String: GraphQLValue] { ["id": .string(id)] }

    /// ``startMutation``'s answer.
    public struct StartResponse: Decodable, Sendable {
        struct Payload: Decodable, Sendable { let listingResearch: ListingResearchDraft }
        let researchListing: Payload?
        public var research: ListingResearchDraft? { researchListing?.listingResearch }
    }

    /// ``query``'s answer; nil when it's gone or someone else's.
    public struct ReadResponse: Decodable, Sendable {
        let listingResearch: ListingResearchDraft?
        public var research: ListingResearchDraft? { listingResearch }
    }
}

/// Add with AI's words, the same in every staff app.
public enum ListingResearchCopy {
    public static let button = "Add with AI"
    public static func title(_ kind: ListingResearchKind) -> String { kind == .venue ? "Add a venue with AI" : "Add a person with AI" }
    public static func prompt(_ kind: ListingResearchKind) -> String {
        kind == .venue ? "A venue's name and city, like “Nyne Spokane”" : "A name and city, like “Spokane Pride”"
    }
    public static let detail = "AI searches the web and fills out what it finds. You check it before anything is saved."
    public static let start = "Research"
    public static let researching = "Researching on the web…"
    public static let notFound = "Nothing turned up on the web. Check the spelling or add a city, or fill it out yourself."
    public static let timedOut = "That took too long. Try again, or fill it out yourself."
    public static func alreadyListed(_ names: [String]) -> String {
        "Already listed: \(names.joined(separator: ", ")). Make sure this isn't the same one."
    }
    public static let checkDraft = "Filled out by AI. Check every field before you save."
    public static let sources = "Where it looked"
}
