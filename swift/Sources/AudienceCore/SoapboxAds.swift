import Foundation

// Soapbox publishers' ads, rate sheet and media library, managed from the Soapbox app (API doc/SOAPBOX.md "Publisher
// ads and the media library"; audience_kit_api #698). These documents run on the staff endpoint (`# endpoint: staff`),
// which this SDK doesn't call: StaffKit's session sends them with these variables and decodes the answers, so no app
// writes its own, and Android's are the same word for word. Readers' side (the ad after an article) is AudienceKit's
// ``PublisherAdCopy`` and `publisherAd(articleID:)`.

/// Where a publisher's ad shows on its own content: the API's `PublisherAdSpot`.
public enum PublisherAdSpot: String, Codable, Sendable, CaseIterable, Hashable, Identifiable {
    /// In the article reader, after the body: one ad an article view.
    case article = "ARTICLE"
    /// On the publication's page, below its masthead.
    case publication = "PUBLICATION"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .article: "After articles"
        case .publication: "Publication page"
        }
    }
}

/// Where a publisher's ad stands: the API's `PublisherAdStatus`.
public enum PublisherAdStatus: String, Codable, Sendable, CaseIterable, Hashable, Identifiable {
    case inReview = "IN_REVIEW"
    case rejected = "REJECTED"
    case scheduled = "SCHEDULED"
    case running = "RUNNING"
    case paused = "PAUSED"
    case ended = "ENDED"
    case removed = "REMOVED"
    /// A status this SDK doesn't know yet.
    case unknown

    public init(from decoder: Decoder) throws {
        self = PublisherAdStatus(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
    }

    public var id: String { rawValue }

    /// The word the apps show for it.
    public var title: String {
        switch self {
        case .inReview: "In review"
        case .rejected: "Turned down"
        case .scheduled: "Scheduled"
        case .running: "Running"
        case .paused: "Paused"
        case .ended: "Ended"
        case .removed: "Taken down"
        case .unknown: "Unknown"
        }
    }

    /// The lists the Soapbox app shows, in order.
    public static let listed: [PublisherAdStatus] = [.running, .scheduled, .inReview, .paused, .rejected, .ended,
                                                     .removed]
}

/// Whether an audience's publishers sell ads, and which of their ads its admins review first: `PublisherAdsMode`.
public enum PublisherAdsMode: String, Codable, Sendable, CaseIterable, Hashable, Identifiable {
    case off = "OFF"
    case reviewAll = "REVIEW_ALL"
    case reviewPending = "REVIEW_PENDING"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .off: "Off"
        case .reviewAll: "Review every ad"
        case .reviewPending: "Review pending publications' ads"
        }
    }
}

/// The one number a sponsor gets: different readers who saw the ad in a week (Monday to Sunday, UTC).
public struct PublisherAdWeek: Codable, Sendable, Hashable, Identifiable {
    /// The Monday the week starts, `yyyy-MM-dd`.
    public let weekStart: String
    /// Different readers; nil below the floor.
    public let viewers: Int?
    /// Set (to 20) instead of ``viewers`` when fewer than that many saw it.
    public let fewerThan: Int?

    public init(weekStart: String, viewers: Int? = nil, fewerThan: Int? = nil) {
        self.weekStart = weekStart; self.viewers = viewers; self.fewerThan = fewerThan
    }

    public var id: String { weekStart }

    /// "1,204 readers" or "Fewer than 20 readers".
    public var readersLine: String {
        if let viewers { return "\(viewers.formatted()) reader\(viewers == 1 ? "" : "s")" }
        return "Fewer than \(fewerThan ?? 20) readers"
    }
}

/// A publication's ad, as its managers and the audience's admins see it (`PromoPlacement` with a `publication`).
public struct PublisherAd: Codable, Sendable, Hashable, Identifiable {
    public struct PublicationRef: Codable, Sendable, Hashable { public let id: String; public let name: String }

    public let id: String
    public let adStatus: PublisherAdStatus?
    public let spot: PublisherAdSpot?
    public let category: String
    public let sponsorName: String
    public let sponsorEmail: String?
    public let headline: String
    public let body: String?
    public let imageUrl: String?
    public let imageAlt: String?
    public let linkUrl: String?
    public let linkLabel: String?
    /// Only on these of the publication's articles; empty is all.
    public let articleIds: [String]
    /// `yyyy-MM-dd`.
    public let startsOn: String
    public let endsOn: String?
    /// 0 (Sunday) to 6; empty is every day.
    public let weekdays: [Int]
    public let priceCents: Int
    public let soldOutside: Bool?
    public let paused: Bool
    public let reviewNote: String?
    public let publication: PublicationRef?
    public let weeklyViewers: [PublisherAdWeek]

    public init(id: String, adStatus: PublisherAdStatus? = .running, spot: PublisherAdSpot? = .article,
                category: String = "small_business", sponsorName: String, sponsorEmail: String? = nil,
                headline: String, body: String? = nil, imageUrl: String? = nil, imageAlt: String? = nil,
                linkUrl: String? = nil, linkLabel: String? = nil, articleIds: [String] = [], startsOn: String,
                endsOn: String? = nil, weekdays: [Int] = [], priceCents: Int = 0, soldOutside: Bool? = true,
                paused: Bool = false, reviewNote: String? = nil, publication: PublicationRef? = nil,
                weeklyViewers: [PublisherAdWeek] = []) {
        self.id = id; self.adStatus = adStatus; self.spot = spot; self.category = category
        self.sponsorName = sponsorName; self.sponsorEmail = sponsorEmail; self.headline = headline; self.body = body
        self.imageUrl = imageUrl; self.imageAlt = imageAlt; self.linkUrl = linkUrl; self.linkLabel = linkLabel
        self.articleIds = articleIds; self.startsOn = startsOn; self.endsOn = endsOn; self.weekdays = weekdays
        self.priceCents = priceCents; self.soldOutside = soldOutside; self.paused = paused
        self.reviewNote = reviewNote; self.publication = publication; self.weeklyViewers = weeklyViewers
    }

    public var status: PublisherAdStatus { adStatus ?? .unknown }

    /// The newest closed week's readers, for a list row.
    public var lastWeek: PublisherAdWeek? { weeklyViewers.first }
}

/// One spot on a publication's public rate sheet.
public struct PublicationRate: Codable, Sendable, Hashable, Identifiable {
    public let spot: PublisherAdSpot
    /// A week, in cents; nil when not listed.
    public let weeklyCents: Int?
    /// How many sponsors share the spot in a week.
    public let slots: Int

    public init(spot: PublisherAdSpot, weeklyCents: Int? = nil, slots: Int = 4) {
        self.spot = spot; self.weeklyCents = weeklyCents; self.slots = slots
    }

    public var id: String { spot.rawValue }
}

/// A publication's public rate sheet: flat weekly prices, never per view or tap. All of the money is the publication's.
public struct PublicationRateSheet: Codable, Sendable, Hashable {
    public let notes: String?
    public let contactEmail: String?
    public let rates: [PublicationRate]

    public init(notes: String? = nil, contactEmail: String? = nil, rates: [PublicationRate] = []) {
        self.notes = notes; self.contactEmail = contactEmail; self.rates = rates
    }

    public func rate(for spot: PublisherAdSpot) -> PublicationRate {
        rates.first { $0.spot == spot } ?? PublicationRate(spot: spot)
    }
}

/// A picture in a publication's media library, for its articles and ads.
public struct PublicationMediaItem: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let url: String
    public let altText: String?
    public let caption: String?
    public let credit: String?
    public let createdAt: String?

    public init(id: String, url: String, altText: String? = nil, caption: String? = nil, credit: String? = nil,
                createdAt: String? = nil) {
        self.id = id; self.url = url; self.altText = altText; self.caption = caption; self.credit = credit
        self.createdAt = createdAt
    }
}

/// What a new or changed ad says, for ``SoapboxAds/saveAdVariables(_:)``. Nil leaves a field as it is on a change.
public struct PublisherAdDraft: Sendable, Hashable {
    public var id: String?
    public var publicationID: String?
    public var spot: PublisherAdSpot?
    public var category: String?
    public var sponsorName: String?
    public var sponsorEmail: String?
    public var headline: String?
    public var body: String?
    /// A data: URI upload or an https link; "" removes the picture.
    public var image: String?
    public var imageMediaID: String?
    public var imageAlt: String?
    public var linkUrl: String?
    public var linkLabel: String?
    public var articleIDs: [String]?
    public var startsOn: String?
    public var endsOn: String?
    public var weekdays: [Int]?
    public var priceCents: Int?
    public var paused: Bool?
    public var dryRun: Bool

    public init(id: String? = nil, publicationID: String? = nil, spot: PublisherAdSpot? = nil, category: String? = nil,
                sponsorName: String? = nil, sponsorEmail: String? = nil, headline: String? = nil, body: String? = nil,
                image: String? = nil, imageMediaID: String? = nil, imageAlt: String? = nil, linkUrl: String? = nil,
                linkLabel: String? = nil, articleIDs: [String]? = nil, startsOn: String? = nil, endsOn: String? = nil,
                weekdays: [Int]? = nil, priceCents: Int? = nil, paused: Bool? = nil, dryRun: Bool = false) {
        self.id = id; self.publicationID = publicationID; self.spot = spot; self.category = category
        self.sponsorName = sponsorName; self.sponsorEmail = sponsorEmail; self.headline = headline; self.body = body
        self.image = image; self.imageMediaID = imageMediaID; self.imageAlt = imageAlt; self.linkUrl = linkUrl
        self.linkLabel = linkLabel; self.articleIDs = articleIDs; self.startsOn = startsOn; self.endsOn = endsOn
        self.weekdays = weekdays; self.priceCents = priceCents; self.paused = paused; self.dryRun = dryRun
    }
}

/// The GraphQL for Soapbox publishers' ads, rate sheet and media library, shared so no app writes its own. Staff
/// endpoint; the API decides who may (the publication's managers, and the audience's admins for review).
public enum SoapboxAds {
    /// The categories a publisher's ad may be, with their names.
    public static let categories: [(key: String, title: String)] = [
        ("small_business", "Local business"), ("health", "Health"), ("employment", "Jobs"), ("charity", "Charity"),
    ]

    public static let adFields = """
        id adStatus spot category sponsorName sponsorEmail headline body imageUrl imageAlt linkUrl linkLabel \
        articleIds startsOn endsOn weekdays priceCents soldOutside paused reviewNote publication { id name } \
        weeklyViewers { weekStart viewers fewerThan }
        """
    public static let rateSheetFields = "rateSheet { notes contactEmail rates { spot weeklyCents slots } }"
    public static let mediaFields = "id url altText caption credit createdAt"

    public static let adsQuery = """
        # endpoint: staff
        query SoapboxAds($id: ID!) { soapbox { publication(id: $id) { id adsEnabled adsNeedReview \
        \(rateSheetFields) ads { \(adFields) } } } }
        """

    public static let mediaQuery = """
        # endpoint: staff
        query SoapboxMedia($id: ID!) { soapbox { publication(id: $id) { id media { \(mediaFields) } } } }
        """

    public static let reviewQueueQuery = """
        # endpoint: staff
        query SoapboxAdReviewQueue { soapbox { publisherAds adReviewQueue { \(adFields) } } }
        """

    public static let saveAdMutation = """
        # endpoint: staff
        mutation SoapboxSaveAd($input: PublicationAdSaveInput!) { savePublicationAd(input: $input) { problems \
        ad { \(adFields) } } }
        """

    public static let deleteAdMutation = """
        # endpoint: staff
        mutation SoapboxDeleteAd($id: ID!) { deletePublicationAd(input: { id: $id }) { ad { id } } }
        """

    public static let reviewAdMutation = """
        # endpoint: staff
        mutation SoapboxReviewAd($id: ID!, $approve: Boolean!, $note: String) { \
        reviewPublicationAd(input: { id: $id, approve: $approve, note: $note }) { ad { \(adFields) } } }
        """

    public static let removeAdMutation = """
        # endpoint: staff
        mutation SoapboxRemoveAd($id: ID!, $removed: Boolean!, $note: String) { \
        removePublicationAd(input: { id: $id, removed: $removed, note: $note }) { ad { \(adFields) } } }
        """

    public static let enableAdsMutation = """
        # endpoint: staff
        mutation SoapboxEnableAds($id: ID!, $enabled: Boolean!) { \
        enablePublicationAds(input: { id: $id, enabled: $enabled }) { publication { id adsEnabled } } }
        """

    public static let setModeMutation = """
        # endpoint: staff
        mutation SoapboxSetPublisherAds($mode: PublisherAdsMode!) { setSoapboxPublisherAds(input: { mode: $mode }) { mode } }
        """

    public static let saveRateSheetMutation = """
        # endpoint: staff
        mutation SoapboxSaveRateSheet($input: PublicationRateSheetSaveInput!) { \
        savePublicationRateSheet(input: $input) { publication { id \(rateSheetFields) } } }
        """

    public static let addMediaMutation = """
        # endpoint: staff
        mutation SoapboxAddMedia($input: PublicationMediaAddInput!) { addPublicationMedia(input: $input) { \
        media { \(mediaFields) } } }
        """

    public static let updateMediaMutation = """
        # endpoint: staff
        mutation SoapboxUpdateMedia($input: PublicationMediaUpdateInput!) { updatePublicationMedia(input: $input) { \
        media { \(mediaFields) } } }
        """

    public static let deleteMediaMutation = """
        # endpoint: staff
        mutation SoapboxDeleteMedia($id: ID!) { deletePublicationMedia(input: { id: $id }) { media { id } } }
        """

    // MARK: Variables

    public static func idVariables(_ id: String) -> [String: GraphQLValue] { ["id": .string(id)] }

    public static func saveAdVariables(_ draft: PublisherAdDraft) -> [String: GraphQLValue] {
        var input: [String: GraphQLValue] = [:]
        func put(_ key: String, _ value: String?) { if let value { input[key] = .string(value) } }
        put("id", draft.id)
        put("publicationId", draft.publicationID)
        put("spot", draft.spot?.rawValue)
        put("category", draft.category)
        put("sponsorName", draft.sponsorName)
        put("sponsorEmail", draft.sponsorEmail)
        put("headline", draft.headline)
        put("body", draft.body)
        put("image", draft.image)
        put("imageMediaId", draft.imageMediaID)
        put("imageAlt", draft.imageAlt)
        put("linkUrl", draft.linkUrl)
        put("linkLabel", draft.linkLabel)
        put("startsOn", draft.startsOn)
        if let endsOn = draft.endsOn { input["endsOn"] = endsOn.isEmpty ? .null : .string(endsOn) }
        if let articles = draft.articleIDs { input["articles"] = .array(articles.map { .string($0) }) }
        if let weekdays = draft.weekdays { input["weekdays"] = .array(weekdays.sorted().map { .int($0) }) }
        if let price = draft.priceCents { input["priceCents"] = .int(price) }
        if let paused = draft.paused { input["paused"] = .bool(paused) }
        if draft.dryRun { input["dryRun"] = .bool(true) }
        return ["input": .object(input)]
    }

    public static func reviewVariables(id: String, approve: Bool, note: String? = nil) -> [String: GraphQLValue] {
        var variables: [String: GraphQLValue] = ["id": .string(id), "approve": .bool(approve)]
        if let note = trimmed(note) { variables["note"] = .string(note) }
        return variables
    }

    public static func removeVariables(id: String, removed: Bool = true, note: String? = nil) -> [String: GraphQLValue] {
        var variables: [String: GraphQLValue] = ["id": .string(id), "removed": .bool(removed)]
        if let note = trimmed(note) { variables["note"] = .string(note) }
        return variables
    }

    public static func enableVariables(publicationID: String, enabled: Bool) -> [String: GraphQLValue] {
        ["id": .string(publicationID), "enabled": .bool(enabled)]
    }

    public static func modeVariables(_ mode: PublisherAdsMode) -> [String: GraphQLValue] { ["mode": .string(mode.rawValue)] }

    /// A spot's weekly price (nil unlists it) and slots, for ``saveRateSheetMutation``.
    public static func rateSheetVariables(publicationID: String, sheet: PublicationRateSheet) -> [String: GraphQLValue] {
        var input: [String: GraphQLValue] = ["id": .string(publicationID)]
        for rate in sheet.rates {
            let prefix = rate.spot == .article ? "article" : "publication"
            input["\(prefix)WeeklyCents"] = rate.weeklyCents.map { .int($0) } ?? .null
            input["\(prefix)Slots"] = .int(rate.slots)
        }
        input["notes"] = trimmed(sheet.notes).map { .string($0) } ?? .null
        input["contactEmail"] = trimmed(sheet.contactEmail).map { .string($0) } ?? .null
        return ["input": .object(input)]
    }

    /// `photo` is a data: URI upload or an https link.
    public static func addMediaVariables(publicationID: String, photo: String, altText: String? = nil,
                                         caption: String? = nil, credit: String? = nil) -> [String: GraphQLValue] {
        var input: [String: GraphQLValue] = ["publicationId": .string(publicationID), "photo": .string(photo)]
        if let altText = trimmed(altText) { input["altText"] = .string(altText) }
        if let caption = trimmed(caption) { input["caption"] = .string(caption) }
        if let credit = trimmed(credit) { input["credit"] = .string(credit) }
        return ["input": .object(input)]
    }

    public static func updateMediaVariables(id: String, altText: String?, caption: String?,
                                            credit: String?) -> [String: GraphQLValue] {
        ["input": .object(["id": .string(id), "altText": .string(altText ?? ""), "caption": .string(caption ?? ""),
                           "credit": .string(credit ?? "")])]
    }

    private static func trimmed(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }

    // MARK: Answers

    /// ``adsQuery``'s answer: the publication's ads, rate sheet and whether it sells ads.
    public struct AdsResponse: Decodable, Sendable {
        struct Publication: Decodable, Sendable {
            let adsEnabled: Bool?
            let adsNeedReview: Bool?
            let rateSheet: PublicationRateSheet?
            let ads: [PublisherAd]?
        }
        struct Soapbox: Decodable, Sendable { let publication: Publication? }
        let soapbox: Soapbox?
        public var ads: [PublisherAd] { soapbox?.publication?.ads ?? [] }
        public var adsEnabled: Bool { soapbox?.publication?.adsEnabled ?? false }
        public var adsNeedReview: Bool { soapbox?.publication?.adsNeedReview ?? true }
        public var rateSheet: PublicationRateSheet { soapbox?.publication?.rateSheet ?? PublicationRateSheet() }
    }

    /// ``mediaQuery``'s answer.
    public struct MediaResponse: Decodable, Sendable {
        struct Publication: Decodable, Sendable { let media: [PublicationMediaItem]? }
        struct Soapbox: Decodable, Sendable { let publication: Publication? }
        let soapbox: Soapbox?
        public var media: [PublicationMediaItem] { soapbox?.publication?.media ?? [] }
    }

    /// ``reviewQueueQuery``'s answer; empty for someone who isn't the audience's admin.
    public struct ReviewQueueResponse: Decodable, Sendable {
        struct Soapbox: Decodable, Sendable { let publisherAds: PublisherAdsMode?; let adReviewQueue: [PublisherAd]? }
        let soapbox: Soapbox?
        public var queue: [PublisherAd] { soapbox?.adReviewQueue ?? [] }
        public var mode: PublisherAdsMode { soapbox?.publisherAds ?? .reviewPending }
    }

    /// ``saveAdMutation``'s answer.
    public struct SaveAdResponse: Decodable, Sendable {
        struct Payload: Decodable, Sendable { let ad: PublisherAd?; let problems: [String] }
        let savePublicationAd: Payload?
        public var ad: PublisherAd? { savePublicationAd?.ad }
        public var problems: [String] { savePublicationAd?.problems ?? [] }
    }

    /// The answer of ``reviewAdMutation`` or ``removeAdMutation``.
    public struct ModerateAdResponse: Decodable, Sendable {
        struct Payload: Decodable, Sendable { let ad: PublisherAd? }
        let reviewPublicationAd: Payload?
        let removePublicationAd: Payload?
        public var ad: PublisherAd? { (reviewPublicationAd ?? removePublicationAd)?.ad }
    }

    /// ``saveRateSheetMutation``'s answer.
    public struct RateSheetResponse: Decodable, Sendable {
        struct Publication: Decodable, Sendable { let rateSheet: PublicationRateSheet? }
        struct Payload: Decodable, Sendable { let publication: Publication? }
        let savePublicationRateSheet: Payload?
        public var rateSheet: PublicationRateSheet? { savePublicationRateSheet?.publication?.rateSheet }
    }

    /// The answer of ``addMediaMutation`` or ``updateMediaMutation``.
    public struct MediaItemResponse: Decodable, Sendable {
        struct Payload: Decodable, Sendable { let media: PublicationMediaItem? }
        let addPublicationMedia: Payload?
        let updatePublicationMedia: Payload?
        public var media: PublicationMediaItem? { (addPublicationMedia ?? updatePublicationMedia)?.media }
    }
}

/// The words the Soapbox app shows around ads and media, the same on Android.
public enum SoapboxAdsCopy {
    public static let ads = "Ads"
    public static let newAd = "New ad"
    public static let rateSheet = "Rate sheet"
    public static let reports = "Reports"
    public static let media = "Media"
    public static let addMedia = "Add pictures"
    public static let adReview = "Ads to review"
    public static let approve = "Approve"
    public static let turnDown = "Turn down"
    public static let takeDown = "Take down"
    public static let putBack = "Put back"
    public static let soldOutsideNote = "You sell this ad yourself. The price is for your own records: AudienceKit "
        + "takes nothing."
    public static let notEnabled = "Ads aren't on for this publication yet. The audience's admins switch them on."
    public static let contextualNote = "Ads show with your own articles and page, chosen by what's being read, never "
        + "by anything about the reader. Readers who tip to read without ads see none."
    public static let needsReview = "New ads and changes to their words, picture or link wait for the audience's "
        + "admins before they run."
    public static let noAds = "No ads here yet."
    public static let noMedia = "No pictures yet. Add the ones you use in articles and ads."
    public static let readersNote = "Readers: different people who saw the ad each week (Monday to Sunday). Under 20 "
        + "shows as fewer than 20."

    /// "$50 a week".
    public static func weekly(_ cents: Int) -> String { "\(money(cents)) a week" }

    public static func money(_ cents: Int) -> String {
        cents % 100 == 0 ? "$\(cents / 100)" : String(format: "$%.2f", Double(cents) / 100)
    }
}
