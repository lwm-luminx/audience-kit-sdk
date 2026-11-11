import AudienceCore
import Foundation

// Civic organizing: who represents a place and who is running for it (the API's `PersonOffice`), and where to give to
// them (`DonationTarget`). An audience whose locales nest (country, state, district) asks for "my representatives"
// with ``AudienceSession/offices(at:localeID:status:)``; a person's page reads ``AudienceSession/officeHolder(id:)``.
// An audience without offices simply gets none back.

/// What an office is: the API's `OfficeKind`. A kind this SDK doesn't know is kept as ``unknown(_:)``.
public enum OfficeKind: Sendable, Hashable, RawRepresentable, Codable {
    case usPresident, usSenate, usHouse, governor, lieutenantGovernor, attorneyGeneral, secretaryOfState, statewide
    case stateSenate, stateHouse, countyExecutive, countyBoard, mayor, cityCouncil, schoolBoard, partyOffice, other
    /// Community titles (the API's `PersonOffice::TITLES`): a pageant crown, an Imperial Court reign, a club title
    /// (Mr. Leather), a chapter's lead (a DEF CON Group's point of contact). See ``isTitle``.
    case pageantTitle, courtTitle, clubTitle, chapterLead
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "US_PRESIDENT": self = .usPresident
        case "US_SENATE": self = .usSenate
        case "US_HOUSE": self = .usHouse
        case "GOVERNOR": self = .governor
        case "LIEUTENANT_GOVERNOR": self = .lieutenantGovernor
        case "ATTORNEY_GENERAL": self = .attorneyGeneral
        case "SECRETARY_OF_STATE": self = .secretaryOfState
        case "STATEWIDE": self = .statewide
        case "STATE_SENATE": self = .stateSenate
        case "STATE_HOUSE": self = .stateHouse
        case "COUNTY_EXECUTIVE": self = .countyExecutive
        case "COUNTY_BOARD": self = .countyBoard
        case "MAYOR": self = .mayor
        case "CITY_COUNCIL": self = .cityCouncil
        case "SCHOOL_BOARD": self = .schoolBoard
        case "PARTY_OFFICE": self = .partyOffice
        case "OTHER": self = .other
        case "PAGEANT_TITLE": self = .pageantTitle
        case "COURT_TITLE": self = .courtTitle
        case "CLUB_TITLE": self = .clubTitle
        case "CHAPTER_LEAD": self = .chapterLead
        default: self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .usPresident: "US_PRESIDENT"
        case .usSenate: "US_SENATE"
        case .usHouse: "US_HOUSE"
        case .governor: "GOVERNOR"
        case .lieutenantGovernor: "LIEUTENANT_GOVERNOR"
        case .attorneyGeneral: "ATTORNEY_GENERAL"
        case .secretaryOfState: "SECRETARY_OF_STATE"
        case .statewide: "STATEWIDE"
        case .stateSenate: "STATE_SENATE"
        case .stateHouse: "STATE_HOUSE"
        case .countyExecutive: "COUNTY_EXECUTIVE"
        case .countyBoard: "COUNTY_BOARD"
        case .mayor: "MAYOR"
        case .cityCouncil: "CITY_COUNCIL"
        case .schoolBoard: "SCHOOL_BOARD"
        case .partyOffice: "PARTY_OFFICE"
        case .other: "OTHER"
        case .pageantTitle: "PAGEANT_TITLE"
        case .courtTitle: "COURT_TITLE"
        case .clubTitle: "CLUB_TITLE"
        case .chapterLead: "CHAPTER_LEAD"
        case let .unknown(value): value
        }
    }

    /// Whether it's a community title rather than a civic office. Titles never widen a Soapbox push's reach.
    public var isTitle: Bool {
        switch self {
        case .pageantTitle, .courtTitle, .clubTitle, .chapterLead: true
        default: false
        }
    }

    /// Whether it's a federal office (President, Senate, House).
    public var isFederal: Bool {
        switch self {
        case .usPresident, .usSenate, .usHouse: true
        default: false
        }
    }

    public init(from decoder: any Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Whether someone holds an office, is running for it, or used to hold it: the API's `OfficeStatus`.
public enum OfficeStatus: String, Codable, Sendable, Hashable, CaseIterable {
    case incumbent = "INCUMBENT"
    case candidate = "CANDIDATE"
    case former = "FORMER"
}

/// Where a donation goes: the API's `DonationTarget`. Apps open ``url`` outside the app (ActBlue, the recipient's own
/// page) and show ``disclaimer`` with it; a political one is never pushed or prompted, only offered.
public struct DonationTarget: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    /// `ACTBLUE`, `WEBSITE`, `PAYPAL`, `VENMO` or `CASHAPP`.
    public let provider: String
    public let url: String
    /// Whom the money goes to, when it isn't the person themself (their campaign committee).
    public let recipientName: String?
    /// The "Paid for by" line to show with it.
    public let disclaimer: String?
    /// Whether it goes to a political committee.
    public let political: Bool

    public init(id: String, provider: String, url: String, recipientName: String? = nil, disclaimer: String? = nil,
                political: Bool = false)
    {
        self.id = id
        self.provider = provider
        self.url = url
        self.recipientName = recipientName
        self.disclaimer = disclaimer
        self.political = political
    }
}

/// A locale an office is on, with where it sits: the API's `Locale` with `kind` and `divisionId`.
public struct OfficeLocale: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String?
    public let label: String?
    /// The API's `LocaleKind`: `COUNTRY`, `STATE`, `CONGRESSIONAL_DISTRICT`, `CITY`…
    public let kind: String?
    /// Its Open Civic Data division ID, e.g. `ocd-division/country:us/state:ut/cd:3`.
    public let divisionId: String?

    public init(id: String, name: String? = nil, label: String? = nil, kind: String? = nil, divisionId: String? = nil) {
        self.id = id
        self.name = name
        self.label = label
        self.kind = kind
        self.divisionId = divisionId
    }
}

/// Who holds or seeks an office, as an office lists them.
public struct OfficeHolderSummary: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String?
    public let avatarUrl: String?
    public let donateTarget: DonationTarget?

    public init(id: String, name: String? = nil, avatarUrl: String? = nil, donateTarget: DonationTarget? = nil) {
        self.id = id
        self.name = name
        self.avatarUrl = avatarUrl
        self.donateTarget = donateTarget
    }
}

/// An office someone holds or is running for: the API's `PersonOffice`.
public struct PersonOffice: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let office: OfficeKind
    /// The office's title, e.g. "U.S. Representative".
    public let title: String
    /// The title with where, e.g. "U.S. Representative, UT-3".
    public let label: String
    public let status: OfficeStatus
    public let party: String?
    public let caucus: String?
    public let electionDate: String?
    public let termStart: String?
    public let termEnd: String?
    public let locale: OfficeLocale
    /// Nil when read from the person's own page (``OfficeHolder/offices``).
    public let person: OfficeHolderSummary?

    public init(id: String, office: OfficeKind, title: String, label: String, status: OfficeStatus = .incumbent,
                party: String? = nil, caucus: String? = nil, electionDate: String? = nil, termStart: String? = nil,
                termEnd: String? = nil, locale: OfficeLocale, person: OfficeHolderSummary? = nil)
    {
        self.id = id
        self.office = office
        self.title = title
        self.label = label
        self.status = status
        self.party = party
        self.caucus = caucus
        self.electionDate = electionDate
        self.termStart = termStart
        self.termEnd = termEnd
        self.locale = locale
        self.person = person
    }
}

/// One of a person's social accounts: the API's `SocialLink`.
public struct SocialAccount: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    /// `instagram`, `x`, `facebook`, `bluesky`, `threads`, `youtube`, `tiktok`…
    public let provider: String
    public let handle: String
    public let url: String?

    public init(id: String, provider: String, handle: String, url: String? = nil) {
        self.id = id
        self.provider = provider
        self.handle = handle
        self.url = url
    }
}

/// A representative's or candidate's page: their offices, where to give, their website and social accounts, and their
/// upcoming events.
public struct OfficeHolder: Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let avatarUrl: String?
    public let bannerUrl: String?
    public let offices: [PersonOffice]
    public let donateTarget: DonationTarget?
    public let website: String?
    public let socialAccounts: [SocialAccount]
    public let events: [PersonEvent]
    /// The voter issues they and the signed-in person share (the audience's tribes).
    public let sharedIssues: [Tag]

    public init(id: String, name: String, avatarUrl: String? = nil, bannerUrl: String? = nil,
                offices: [PersonOffice] = [], donateTarget: DonationTarget? = nil, website: String? = nil,
                socialAccounts: [SocialAccount] = [], events: [PersonEvent] = [], sharedIssues: [Tag] = [])
    {
        self.id = id
        self.name = name
        self.avatarUrl = avatarUrl
        self.bannerUrl = bannerUrl
        self.offices = offices
        self.donateTarget = donateTarget
        self.website = website
        self.socialAccounts = socialAccounts
        self.events = events
        self.sharedIssues = sharedIssues
    }
}

extension Queries {
    /// The types the civic documents depend on.
    static let civicTypes = ["Audience", "Person", "ListingProfile", "Event"]

    static let donationTargetFields = "id provider url recipientName disclaimer political"
    static let officeFields = """
    id office title label status party caucus electionDate termStart termEnd \
    locale { id name label kind divisionId }
    """

    static func offices(_ shape: SchemaShape) -> String {
        guard shape.has("Audience", "offices") else { return "query Offices { id }" }
        let donate = shape.has("Person", "donateTarget") ? "donateTarget { \(donationTargetFields) }" : ""
        return """
        query Offices($at: CoordinatesInput, $localeId: ID, $status: [OfficeStatus!]) {
          offices(at: $at, localeId: $localeId, status: $status) {
            \(officeFields) person { id name avatarUrl \(donate) }
          }
        }
        """
    }

    static func officeHolder(_ shape: SchemaShape) -> String {
        let donate = shape.has("Person", "donateTarget") ? "donateTarget { \(donationTargetFields) }" : ""
        let offices = shape.has("Person", "offices") ? "offices { \(officeFields) }" : ""
        let profile = shape.has("Person", "profile") && shape.has("ListingProfile", "socialLinks")
            ? "profile { website socialLinks { nodes { id provider handle url } } }" : ""
        let events = shape.has("Person", "events")
            ? "events { involvements { edges { node { \(personEventFields(shape)) } } } }" : ""
        let issues = shape.has("Person", "sharedTribes") ? "sharedTribes { \(tagFields) }" : ""
        return """
        query OfficeHolder($id: ID!) {
          node(id: $id) {
            ... on Person { id name avatarUrl bannerUrl \(donate) \(offices) \(profile) \(events) \(issues) }
          }
        }
        """
    }
}

struct OfficesResponse: Decodable, Sendable { var offices: [PersonOffice]? }

struct OfficeHolderResponse: Decodable, Sendable {
    struct Profile: Decodable, Sendable {
        var website: String?
        var socialLinks: Nodes<SocialAccount>?
    }

    struct Edge: Decodable, Sendable { var node: PersonEvent }
    struct Edges: Decodable, Sendable { var edges: [Edge?]? }
    struct EventsMixin: Decodable, Sendable { var involvements: Edges? }

    struct Holder: Decodable, Sendable {
        var id: String?
        var name: String?
        var avatarUrl: String?
        var bannerUrl: String?
        var donateTarget: DonationTarget?
        var offices: [PersonOffice]?
        var profile: Profile?
        var events: EventsMixin?
        var sharedTribes: [Tag]?
    }

    var node: Holder?

    var holder: OfficeHolder? {
        guard let node, let id = node.id else { return nil }
        return OfficeHolder(id: id, name: node.name ?? "", avatarUrl: node.avatarUrl, bannerUrl: node.bannerUrl,
                            offices: node.offices ?? [], donateTarget: node.donateTarget,
                            website: node.profile?.website, socialAccounts: node.profile?.socialLinks?.nodes ?? [],
                            events: node.events?.involvements?.edges?.compactMap { $0?.node } ?? [],
                            sharedIssues: node.sharedTribes ?? [])
    }
}

extension OfficeHolder {
    /// Their community titles (crowns, reigns, club titles, chapter leads), reigning first.
    public var titles: [PersonOffice] { offices.only(titles: true) }
    /// Their civic offices.
    public var civicOffices: [PersonOffice] { offices.only(titles: false) }
}

extension Array where Element == PersonOffice {
    /// Only community titles (true), only civic offices (false), or all of them (nil).
    public func only(titles: Bool?) -> [PersonOffice] {
        guard let titles else { return self }
        return filter { $0.office.isTitle == titles }
    }
}

extension AudienceSession {
    /// Someone's representatives and candidates, most local first (their House seat, then their senators and
    /// statewide offices), the holder before those running: the offices on the districts a position lies in or on a
    /// locale, and on every locale above. Empty without either, or in an audience without offices.
    ///
    /// - Parameters:
    ///   - status: only these; incumbents and candidates when nil.
    ///   - titles: only community titles (true, Hot Mess's crowns and reigns), only civic offices (false), or both
    ///     (nil). Filtered here, so it works against an API from before titles too.
    public func offices(at position: Coordinate? = nil, localeID: String? = nil, status: [OfficeStatus]? = nil,
                        titles: Bool? = nil) async throws -> [PersonOffice]
    {
        guard position != nil || localeID != nil else { return [] }
        var variables: [String: GraphQLValue] = [:]
        if let position { variables["at"] = position.graphQLValue }
        if let localeID { variables["localeId"] = .string(localeID) }
        if let status { variables["status"] = .array(status.map { .string($0.rawValue) }) }
        let offices = try await graphQL(types: Queries.civicTypes, variables: variables, operationName: "Offices",
                                        as: OfficesResponse.self, document: Queries.offices).offices ?? []
        return offices.only(titles: titles)
    }

    /// A representative's or candidate's page, or nil when there's no such person in the audience.
    public func officeHolder(id: String) async throws -> OfficeHolder? {
        try await graphQL(types: Queries.civicTypes, variables: ["id": .string(id)], operationName: "OfficeHolder",
                          as: OfficeHolderResponse.self, document: Queries.officeHolder).holder
    }
}
