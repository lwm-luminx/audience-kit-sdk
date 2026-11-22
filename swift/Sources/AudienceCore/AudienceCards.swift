import Foundation

// An audience's own cards (promoted, sponsored, charity and announcement cards in its apps' feeds), managed by its
// admins from a staff app such as Soapbox, the way Olympus Audience › Cards does (API doc/PROMOTED_PLACEMENT.md,
// doc/ADVERTISING.md). These documents run on the staff endpoint (`# endpoint: staff`), which this SDK doesn't call:
// StaffKit's session sends them with these variables and decodes the answers, and Android's are the same word for
// word. A Soapbox publisher's ads on its own articles are ``SoapboxAds``; they come back in the same list from the API
// and ``AudienceCards/CardsResponse`` leaves them out.

/// A screen of the apps whose cards the server ranks: the API's `LayoutScreen`.
public enum AudienceCardScreen: String, Codable, Sendable, CaseIterable, Hashable, Identifiable {
    case now = "NOW"
    case venues = "VENUES"
    case people = "PEOPLE"
    case everywhere = "EVERYWHERE"
    case locale = "LOCALE"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .now: "Now"
        case .venues: "Venues"
        case .people: "People"
        case .everywhere: "Everywhere"
        case .locale: "A city's page"
        }
    }
}

/// How much paid placement an audience's apps carry: the API's `AdvertisingMode`.
public enum AudienceCardsLevel: String, Codable, Sendable, CaseIterable, Hashable {
    case adFree = "AD_FREE"
    case open = "OPEN"
    case sponsorships = "SPONSORSHIPS"
    case traditional = "TRADITIONAL"
    /// A mode this SDK doesn't know yet.
    case unknown

    public init(from decoder: Decoder) throws {
        self = AudienceCardsLevel(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
    }

    /// One line on what the audience's cards may be, for the top of the cards list.
    public var note: String {
        switch self {
        case .adFree: "This audience is ad-free: only free charity cards, announcements and AudienceKit's own cards show."
        case .open, .traditional: "Venues, events and local sponsors may be promoted, labelled and at a flat rate."
        case .sponsorships: "Sponsorships only: the audience's own venues and events, labelled Sponsored."
        case .unknown: ""
        }
    }
}

/// A category of card, as the audience publishes it (`CardCategory`).
public struct AudienceCardCategory: Codable, Sendable, Hashable, Identifiable {
    public let key: String
    public let label: String
    public let description: String?
    public let hideable: Bool?

    public init(key: String, label: String, description: String? = nil, hideable: Bool? = true) {
        self.key = key; self.label = label; self.description = description; self.hideable = hideable
    }

    public var id: String { key }

    /// Categories a card made from a staff app can be: venue and event cards point at a venue or event, and
    /// AudienceKit's own cards are booked by AudienceKit's administrators.
    public static let writable: Set<String> = ["health", "employment", "small_business", "charity", "announcement"]

    /// The published list's defaults (config/promo_cards.yml), for before the audience's own list arrives.
    public static let defaults: [AudienceCardCategory] = [
        .init(key: "announcement", label: "Announcements", hideable: false),
        .init(key: "small_business", label: "Local businesses"),
        .init(key: "health", label: "Health"),
        .init(key: "employment", label: "Jobs"),
        .init(key: "charity", label: "Charities"),
    ]
}

/// Where an audience card stands, worked out from its dates and pause.
public enum AudienceCardStatus: String, Sendable, CaseIterable, Hashable, Identifiable {
    case running, scheduled, paused, ended

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .running: "Running"
        case .scheduled: "Scheduled"
        case .paused: "Paused"
        case .ended: "Ended"
        }
    }
}

/// One of the audience's own cards (`PromoPlacement` without a publication).
public struct AudienceCard: Codable, Sendable, Hashable, Identifiable {
    public struct Ref: Codable, Sendable, Hashable { public let id: String; public let name: String? }

    public let id: String
    public let category: String
    /// The badge it carries: Promoted, Sponsored, Charity, Announcement or From AudienceKit.
    public let label: String?
    public let sponsorName: String
    public let headline: String
    public let body: String?
    public let imageUrl: String?
    public let imageAlt: String?
    public let linkUrl: String?
    public let linkLabel: String?
    /// `yyyy-MM-dd`.
    public let startsOn: String
    public let endsOn: String?
    /// 0 (Sunday) to 6; empty is every night.
    public let weekdays: [Int]
    /// Empty is every screen.
    public let screens: [AudienceCardScreen]
    /// Empty is everywhere.
    public let localeIds: [String]
    public let priceCents: Int
    public let paused: Bool
    /// awaiting_payment while a venue's Checkout is open; paid once paid; nil when booked without Checkout.
    public let paymentStatus: String?
    public let venue: Ref?
    public let event: Ref?
    /// Set on a Soapbox publisher's ad, which isn't one of the audience's own cards.
    public let publication: Ref?
    public let weeklyViewers: [PublisherAdWeek]

    public init(id: String, category: String = "small_business", label: String? = "Promoted", sponsorName: String,
                headline: String, body: String? = nil, imageUrl: String? = nil, imageAlt: String? = nil,
                linkUrl: String? = nil, linkLabel: String? = nil, startsOn: String, endsOn: String? = nil,
                weekdays: [Int] = [], screens: [AudienceCardScreen] = [], localeIds: [String] = [],
                priceCents: Int = 0, paused: Bool = false, paymentStatus: String? = nil, venue: Ref? = nil,
                event: Ref? = nil, publication: Ref? = nil, weeklyViewers: [PublisherAdWeek] = []) {
        self.id = id; self.category = category; self.label = label; self.sponsorName = sponsorName
        self.headline = headline; self.body = body; self.imageUrl = imageUrl; self.imageAlt = imageAlt
        self.linkUrl = linkUrl; self.linkLabel = linkLabel; self.startsOn = startsOn; self.endsOn = endsOn
        self.weekdays = weekdays; self.screens = screens; self.localeIds = localeIds; self.priceCents = priceCents
        self.paused = paused; self.paymentStatus = paymentStatus; self.venue = venue; self.event = event
        self.publication = publication; self.weeklyViewers = weeklyViewers
    }

    /// Running, scheduled, paused or ended on `today` (`yyyy-MM-dd`, the audience's day).
    public func status(on today: String) -> AudienceCardStatus {
        if let endsOn, endsOn < today { return .ended }
        if paused { return .paused }
        return startsOn > today ? .scheduled : .running
    }

    /// Whether a staff app may change it: not a venue's or event's card, and not AudienceKit's own.
    public var editable: Bool { AudienceCardCategory.writable.contains(category) && venue == nil && event == nil }

    /// The newest closed week's viewers, for a list row.
    public var lastWeek: PublisherAdWeek? { weeklyViewers.first }
}

/// What a new or changed card says, for ``AudienceCards/saveVariables(_:)``. The API's `savePromoPlacement` replaces
/// what it's sent, so a change sends the whole card.
public struct AudienceCardDraft: Sendable, Hashable {
    public var id: String?
    public var category: String
    public var sponsorName: String
    public var headline: String
    public var body: String?
    /// An https link; nil or "" for none.
    public var imageUrl: String?
    public var imageAlt: String?
    public var linkUrl: String?
    public var linkLabel: String?
    public var startsOn: String
    /// nil is open-ended.
    public var endsOn: String?
    public var weekdays: [Int]
    public var screens: [AudienceCardScreen]
    public var localeIDs: [String]
    public var priceCents: Int
    public var paused: Bool

    public init(id: String? = nil, category: String = "small_business", sponsorName: String = "", headline: String = "",
                body: String? = nil, imageUrl: String? = nil, imageAlt: String? = nil, linkUrl: String? = nil,
                linkLabel: String? = nil, startsOn: String, endsOn: String? = nil, weekdays: [Int] = [],
                screens: [AudienceCardScreen] = [], localeIDs: [String] = [], priceCents: Int = 0, paused: Bool = false) {
        self.id = id; self.category = category; self.sponsorName = sponsorName; self.headline = headline
        self.body = body; self.imageUrl = imageUrl; self.imageAlt = imageAlt; self.linkUrl = linkUrl
        self.linkLabel = linkLabel; self.startsOn = startsOn; self.endsOn = endsOn; self.weekdays = weekdays
        self.screens = screens; self.localeIDs = localeIDs; self.priceCents = priceCents; self.paused = paused
    }

    /// A draft of `card` as it stands, to change it.
    public init(_ card: AudienceCard) {
        self.init(id: card.id, category: card.category, sponsorName: card.sponsorName, headline: card.headline,
                  body: card.body, imageUrl: card.imageUrl, imageAlt: card.imageAlt, linkUrl: card.linkUrl,
                  linkLabel: card.linkLabel, startsOn: card.startsOn, endsOn: card.endsOn, weekdays: card.weekdays,
                  screens: card.screens, localeIDs: card.localeIds, priceCents: card.priceCents, paused: card.paused)
    }

    /// What stops it saving, in words; empty when it can be sent.
    public var problems: [String] {
        var found: [String] = []
        func blank(_ text: String?) -> Bool { (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if blank(sponsorName) { found.append("Say who placed it.") }
        if blank(headline) { found.append("Add a headline.") }
        for (name, link) in [("picture", imageUrl), ("link", linkUrl)] where !blank(link) {
            if !(link ?? "").lowercased().hasPrefix("https://") { found.append("The \(name) needs an https link.") }
        }
        if !blank(imageUrl) && blank(imageAlt) { found.append("Say what the picture shows.") }
        if let endsOn, endsOn < startsOn { found.append("It ends before it starts.") }
        return found
    }
}

/// The GraphQL for an audience's own cards, shared so no app writes its own. Staff endpoint; the API lets only the
/// audience's admins (`audience:read:*` to list, `audience:write:*` to change).
public enum AudienceCards {
    public static let cardFields = """
        id category label sponsorName headline body imageUrl imageAlt linkUrl linkLabel startsOn endsOn weekdays \
        screens localeIds priceCents paused paymentStatus venue { id name } event { id name } publication { id name } \
        weeklyViewers { weekStart viewers fewerThan }
        """

    public static let cardsQuery = """
        # endpoint: staff
        query AudienceCards { advertising cardCategories { key label description hideable } \
        promoPlacements { \(cardFields) } }
        """

    public static let saveMutation = """
        # endpoint: staff
        mutation AudienceSaveCard($input: PromoPlacementSaveInput!) { savePromoPlacement(input: $input) { \
        promoPlacement { \(cardFields) } } }
        """

    public static let deleteMutation = """
        # endpoint: staff
        mutation AudienceDeleteCard($id: ID!) { deletePromoPlacement(input: { id: $id }) { deletedId } }
        """

    // MARK: Variables

    public static func idVariables(_ id: String) -> [String: GraphQLValue] { ["id": .string(id)] }

    public static func saveVariables(_ draft: AudienceCardDraft) -> [String: GraphQLValue] {
        var input: [String: GraphQLValue] = [
            "category": .string(draft.category),
            "sponsorName": .string(draft.sponsorName.trimmingCharacters(in: .whitespacesAndNewlines)),
            "headline": .string(draft.headline.trimmingCharacters(in: .whitespacesAndNewlines)),
            "startsOn": .string(draft.startsOn),
            "endsOn": draft.endsOn.map { .string($0) } ?? .null,
            "weekdays": .array(draft.weekdays.sorted().map { .int($0) }),
            "screens": .array(draft.screens.map { .string($0.rawValue) }),
            "localeIds": .array(draft.localeIDs.map { .string($0) }),
            "priceCents": .int(draft.priceCents),
            "paused": .bool(draft.paused),
        ]
        if let id = draft.id { input["id"] = .string(id) }
        for (key, value) in [("body", draft.body), ("imageUrl", draft.imageUrl), ("imageAlt", draft.imageAlt),
                             ("linkUrl", draft.linkUrl), ("linkLabel", draft.linkLabel)] {
            input[key] = trimmed(value).map { .string($0) } ?? .null
        }
        return ["input": .object(input)]
    }

    private static func trimmed(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }

    // MARK: Answers

    /// ``cardsQuery``'s answer: the audience's own cards (publishers' ads left out), its categories and level.
    public struct CardsResponse: Decodable, Sendable {
        let advertising: AudienceCardsLevel?
        let cardCategories: [AudienceCardCategory]?
        let promoPlacements: [AudienceCard]?

        public var cards: [AudienceCard] { (promoPlacements ?? []).filter { $0.publication == nil } }
        public var categories: [AudienceCardCategory] {
            let list = cardCategories ?? []
            return list.isEmpty ? AudienceCardCategory.defaults : list
        }
        public var level: AudienceCardsLevel { advertising ?? .unknown }
    }

    /// ``saveMutation``'s answer.
    public struct SaveResponse: Decodable, Sendable {
        struct Payload: Decodable, Sendable { let promoPlacement: AudienceCard? }
        let savePromoPlacement: Payload?
        public var card: AudienceCard? { savePromoPlacement?.promoPlacement }
    }

    /// ``deleteMutation``'s answer.
    public struct DeleteResponse: Decodable, Sendable {
        struct Payload: Decodable, Sendable { let deletedId: String? }
        let deletePromoPlacement: Payload?
        public var deletedID: String? { deletePromoPlacement?.deletedId }
    }
}

/// The words a staff app shows around the audience's cards, the same on Android.
public enum AudienceCardsCopy {
    public static let cards = "Cards"
    public static let newCard = "New card"
    public static let noCards = "No cards yet. Cards show between the apps' own rows, at most two a screen, never first."
    public static let viewersNote = "Viewers: different people who saw the card each week (Monday to Sunday). Under 20 "
        + "shows as fewer than 20."
    public static let notEditable = "This card is a venue's or event's, or AudienceKit's own: change it in Olympus."
    public static let everyScreen = "Every screen"
    public static let everywhere = "Everywhere"

    /// "1,204 viewers" or "Fewer than 20 viewers".
    public static func viewers(_ week: PublisherAdWeek) -> String {
        if let viewers = week.viewers { return "\(viewers.formatted()) viewer\(viewers == 1 ? "" : "s")" }
        return "Fewer than \(week.fewerThan ?? 20) viewers"
    }
}
