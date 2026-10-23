import AudienceCore
import Foundation

// Server-driven cards (the API's doc/plans/SERVER_DRIVEN_CARDS_PLAN.md). The server ranks the cards of a screen (Now,
// Venues, People) for this moment and the app draws them in that order. A card points at records the app already loads
// (by id), so the layout call stays small and the app's own queries stay the source of the content.
//
// - The app says which kinds it can draw (``CardRegistry/kinds``); the server never sends another kind, and the client
//   skips one it doesn't know anyway.
// - When the layout can't be fetched (offline, an error, more than ``LayoutClient/timeout``), ``LayoutClient`` returns
//   the app's built-in order instead, so the screen fills either way.
// - Promoted cards come in slots with ranked candidates. The app draws the first one whose category the viewer hasn't
//   turned off (``CardFilter``); what they turned off stays on the device and is never sent.

/// A screen whose cards the server ranks.
public enum LayoutScreen: String, Codable, Sendable, Hashable {
    case now = "NOW", venues = "VENUES", people = "PEOPLE"
}

/// The card kinds the API knows of today. `kind` is a string, so a newer API can add kinds; an app lists the ones it
/// draws.
public enum CardKind {
    public static let nowStage = "now.stage"
    public static let nowChat = "now.chat"
    public static let nowSmallTalk = "now.smallTalk"
    public static let postsTonight = "posts.tonight"
    public static let postsLocale = "posts.locale"
    public static let eventsUpcoming = "events.upcoming"
    public static let venuesNearby = "venues.nearby"
    public static let venuesFriends = "venues.friends"
    public static let venuesTonight = "venues.tonight"
    public static let venuesAll = "venues.all"
    public static let venuesThinCity = "venues.thinCity"
    public static let peoplePlayingThisWeek = "people.playingThisWeek"
    public static let peopleBasedHere = "people.basedHere"
    public static let peopleEveryone = "people.everyone"
    public static let pings = "pings"
    public static let web = "web"
    public static let promoSlot = "promo.slot"
}

/// The words, picture and link of a web card (the audience's own announcement) or a promoted card. Links and images
/// are https; open the link in an in-app browser, never an embedded web view.
public struct CardContent: Codable, Sendable, Hashable {
    public let headline: String
    public let body: String?
    public let imageUrl: String?
    /// What the picture shows, for screen readers.
    public let imageAlt: String?
    public let linkUrl: String?
    /// The link's button text.
    public let linkLabel: String?

    public init(headline: String, body: String? = nil, imageUrl: String? = nil, imageAlt: String? = nil,
                linkUrl: String? = nil, linkLabel: String? = nil) {
        self.headline = headline
        self.body = body
        self.imageUrl = imageUrl
        self.imageAlt = imageAlt
        self.linkUrl = linkUrl
        self.linkLabel = linkLabel
    }
}

/// A promoted or charity card, one of a promo slot's candidates. Show ``label`` and the category's name as the server
/// sends them: they can change without an app release.
public struct PromoCard: Decodable, Sendable, Hashable, Identifiable {
    private struct Ref: Decodable, Sendable, Hashable { var id: String }

    /// The placement, as ``AudienceSession/recordCardViews(promoIDs:layoutID:)`` takes it.
    public let id: String
    /// One of ``AudienceSession/cardCategories()``' keys: venue, event, health, employment, small_business, charity.
    public let category: String
    /// Its badge, e.g. "Promoted" or "Charity".
    public let label: String
    /// Who placed it.
    public let sponsorName: String
    public let content: CardContent
    /// The venue it promotes, for a venue card.
    public let venueID: String?
    /// The event it promotes, for an event card.
    public let eventID: String?

    public init(id: String, category: String, label: String, sponsorName: String, content: CardContent,
                venueID: String? = nil, eventID: String? = nil) {
        self.id = id
        self.category = category
        self.label = label
        self.sponsorName = sponsorName
        self.content = content
        self.venueID = venueID
        self.eventID = eventID
    }

    private enum CodingKeys: String, CodingKey { case id, category, label, sponsorName, venue, event }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        category = try container.decode(String.self, forKey: .category)
        label = try container.decode(String.self, forKey: .label)
        sponsorName = try container.decodeIfPresent(String.self, forKey: .sponsorName) ?? ""
        content = try CardContent(from: decoder)
        venueID = try container.decodeIfPresent(Ref.self, forKey: .venue)?.id
        eventID = try container.decodeIfPresent(Ref.self, forKey: .event)?.id
    }
}

/// One card of a screen, in rank order. It carries the ids of the records it's about (load them as before), a web
/// card's content, or a promo slot's candidates.
public struct LayoutCard: Decodable, Sendable, Hashable, Identifiable {
    private struct Ref: Decodable, Sendable, Hashable { var id: String }

    /// Stable for this card in its place, e.g. `now.chat:<venue id>`.
    public let id: String
    /// What it is (``CardKind``).
    public let kind: String
    /// Its place, from 1 at the top.
    public let rank: Int
    /// A heading to use instead of the app's own, when the server sends one.
    public let title: String?
    public let venueID: String?
    public let eventID: String?
    public let localeID: String?
    /// A venues card's venues, in the order to show them.
    public let venueIDs: [String]
    /// An events card's events, soonest first.
    public let eventIDs: [String]
    /// A people card's people, in the order to show them.
    public let personIDs: [String]
    /// A web card's announcement.
    public let web: CardContent?
    /// A promo slot's candidates, in the order to try them.
    public let candidates: [PromoCard]
    /// True for a card of the app's built-in order, used when the layout couldn't be fetched: it carries no ids, so
    /// draw it from the app's own data.
    public let isFallback: Bool

    public init(id: String, kind: String, rank: Int, title: String? = nil, venueID: String? = nil,
                eventID: String? = nil, localeID: String? = nil, venueIDs: [String] = [], eventIDs: [String] = [],
                personIDs: [String] = [], web: CardContent? = nil, candidates: [PromoCard] = [],
                isFallback: Bool = false) {
        self.id = id
        self.kind = kind
        self.rank = rank
        self.title = title
        self.venueID = venueID
        self.eventID = eventID
        self.localeID = localeID
        self.venueIDs = venueIDs
        self.eventIDs = eventIDs
        self.personIDs = personIDs
        self.web = web
        self.candidates = candidates
        self.isFallback = isFallback
    }

    /// A card of the built-in order: nothing but its kind.
    public static func fallback(_ kind: String, rank: Int) -> LayoutCard {
        LayoutCard(id: "fallback:\(kind)", kind: kind, rank: rank, isFallback: true)
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, rank, title, venue, event, stageEvent, locale, venues, events, people, headline, candidates
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        kind = try container.decode(String.self, forKey: .kind)
        rank = try container.decodeIfPresent(Int.self, forKey: .rank) ?? 0
        title = try container.decodeIfPresent(String.self, forKey: .title)
        venueID = try container.decodeIfPresent(Ref.self, forKey: .venue)?.id
        eventID = try (container.decodeIfPresent(Ref.self, forKey: .stageEvent)
            ?? container.decodeIfPresent(Ref.self, forKey: .event))?.id
        localeID = try container.decodeIfPresent(Ref.self, forKey: .locale)?.id
        venueIDs = try container.decodeIfPresent([Ref].self, forKey: .venues)?.map(\.id) ?? []
        eventIDs = try container.decodeIfPresent([Ref].self, forKey: .events)?.map(\.id) ?? []
        personIDs = try container.decodeIfPresent([Ref].self, forKey: .people)?.map(\.id) ?? []
        web = container.contains(.headline) ? try CardContent(from: decoder) : nil
        // One bad candidate (a field a newer API changed) loses that candidate, not the slot.
        candidates = (try? container.decodeIfPresent([Lenient<PromoCard>].self, forKey: .candidates))?
            .compactMap(\.value) ?? []
        isFallback = false
    }

    /// The candidate to draw in a promo slot: the first the filter allows, or nil to draw nothing.
    public func promo(_ filter: CardFilter) -> PromoCard? {
        candidates.first { filter.allows($0.category) }
    }
}

/// A screen's cards, top first.
public struct Layout: Sendable, Hashable {
    /// This ranking, for ``AudienceSession/recordCardViews(promoIDs:layoutID:)``. Nil for the built-in order.
    public let id: String?
    public let cards: [LayoutCard]
    /// Seconds until the app should ask again.
    public let refreshAfter: Int

    public init(id: String?, cards: [LayoutCard], refreshAfter: Int = 60) {
        self.id = id
        self.cards = cards
        self.refreshAfter = refreshAfter
    }

    /// The app's built-in order, used when the server's can't be had.
    public static func fallback(_ kinds: [String], refreshAfter: Int = 60) -> Layout {
        Layout(id: nil, cards: kinds.enumerated().map { LayoutCard.fallback($1, rank: $0 + 1) },
               refreshAfter: refreshAfter)
    }

    /// Whether this is the built-in order rather than the server's.
    public var isFallback: Bool { id == nil }

    /// The first card of a kind.
    public func card(_ kind: String) -> LayoutCard? {
        cards.first { $0.kind == kind }
    }
}

/// A category of promoted card, from the audience's published list, for the app's "Cards you see" settings. Show the
/// label and description as sent.
public struct CardCategory: Codable, Sendable, Hashable, Identifiable {
    /// The category cards carry: venue, health, charity, ...
    public let key: String
    /// Its name, e.g. "Health".
    public let label: String
    /// Examples, e.g. "STI testing, PrEP clinics".
    public let description: String
    /// Whether people can turn it off. Never announcements; not by default venues and events.
    public let hideable: Bool

    public var id: String { key }

    public init(key: String, label: String, description: String, hideable: Bool) {
        self.key = key
        self.label = label
        self.description = description
        self.hideable = hideable
    }
}

/// Which promoted cards the viewer will see: every category but the hideable ones they turned off. Built on the device
/// from what they chose (``CardPreferences``); it never leaves the device.
public struct CardFilter: Sendable, Hashable {
    public var hidden: Set<String>
    /// The published categories, when they've loaded. A category it lists as not hideable is always shown, even if it
    /// was hidden before the audience changed that; until they load, every hidden category is honoured.
    public var categories: [CardCategory]?

    public init(hidden: Set<String> = [], categories: [CardCategory]? = nil) {
        self.hidden = hidden
        self.categories = categories
    }

    /// Shows everything.
    public static let none = CardFilter()

    public func allows(_ category: String) -> Bool {
        guard hidden.contains(category) else { return true }
        guard let categories else { return false }
        return categories.first { $0.key == category }?.hideable == false
    }
}

/// The cards an app can draw, and what each becomes: for SwiftUI, an enum the screen switches on is a good `Rendered`.
/// Register every kind the app draws; its ``kinds`` go to the server, and ``render(_:)`` skips the rest.
public struct CardRegistry<Rendered> {
    private var renderers: [String: (LayoutCard) -> Rendered?] = [:]
    private var order: [String] = []

    public init() {}

    /// Draws `kind` with `render`; returning nil leaves the card out (a promo slot whose candidates are all hidden).
    public mutating func register(_ kind: String, _ render: @escaping (LayoutCard) -> Rendered?) {
        if renderers[kind] == nil { order.append(kind) }
        renderers[kind] = render
    }

    /// Every kind registered, in the order registered.
    public var kinds: [String] { order }

    public func canRender(_ kind: String) -> Bool { renderers[kind] != nil }

    /// The card drawn, or nil for a kind this app doesn't know or a card it leaves out.
    public func render(_ card: LayoutCard) -> Rendered? {
        renderers[card.kind]?(card)
    }

    /// The layout's cards drawn in order, leaving out unknown kinds.
    public func render(_ layout: Layout) -> [(card: LayoutCard, rendered: Rendered)] {
        layout.cards.compactMap { card in render(card).map { (card, $0) } }
    }
}

/// Fetches a screen's layout, falling back to the app's built-in order when it can't.
public struct LayoutClient: Sendable {
    public let session: AudienceSession
    public let screen: LayoutScreen
    /// Every kind the app draws (``CardRegistry/kinds``).
    public let cardKinds: [String]
    /// The app's built-in order for this screen, used offline, on an error, or past ``timeout``.
    public let fallback: [String]
    /// The app's marketing version, for the server's logs.
    public var appVersion: String?
    public var timeout: Duration = .seconds(2)

    public init(session: AudienceSession, screen: LayoutScreen, cardKinds: [String], fallback: [String],
                appVersion: String? = nil) {
        self.session = session
        self.screen = screen
        self.cardKinds = cardKinds
        self.fallback = fallback
        self.appVersion = appVersion
    }

    /// The server's layout for where the device is (or the app's locale when there's no position), with any kind the
    /// app didn't list left out; the built-in order when that fails. Never throws: the screen fills either way.
    public func load(position: Coordinate? = nil, beaconMajor: Int? = nil, localeID: String? = nil) async -> Layout {
        let session = session, screen = screen, kinds = cardKinds, version = appVersion
        let fetched: Layout? = await withTaskGroup(of: Layout?.self) { group in
            group.addTask {
                try? await session.layout(screen: screen, cardKinds: kinds, position: position,
                                          beaconMajor: beaconMajor, localeID: localeID, appVersion: version)
            }
            group.addTask { [timeout] in
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        guard let fetched else { return .fallback(fallback) }
        let known = Set(kinds)
        return Layout(id: fetched.id, cards: fetched.cards.filter { known.contains($0.kind) },
                      refreshAfter: fetched.refreshAfter)
    }
}

/// Reports the promoted cards the viewer saw: each on screen for a second or more, once per layout, signed in only.
/// Call ``appeared(_:layoutID:)`` and ``disappeared(_:)`` as a promo card comes and goes.
public actor PromoViewRecorder {
    private let session: AudienceSession
    private let minimumOnScreen: Duration
    private var visible: [String: Task<Void, Never>] = [:]
    private var reported: Set<String> = []
    private var pending: [String: String?] = [:]
    private var flushing: Task<Void, Never>?

    public init(session: AudienceSession, minimumOnScreen: Duration = .seconds(1)) {
        self.session = session
        self.minimumOnScreen = minimumOnScreen
    }

    public func appeared(_ promoID: String, layoutID: String?) {
        let key = "\(layoutID ?? ""):\(promoID)"
        guard visible[promoID] == nil, !reported.contains(key) else { return }
        let wait = minimumOnScreen
        visible[promoID] = Task { [weak self] in
            try? await Task.sleep(for: wait)
            guard !Task.isCancelled else { return }
            await self?.seen(promoID, layoutID: layoutID, key: key)
        }
    }

    public func disappeared(_ promoID: String) {
        visible.removeValue(forKey: promoID)?.cancel()
    }

    private func seen(_ promoID: String, layoutID: String?, key: String) async {
        visible[promoID] = nil
        guard await session.isSignedIn, reported.insert(key).inserted else { return }
        pending[promoID] = layoutID
        guard flushing == nil else { return }
        flushing = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            await self?.flush()
        }
    }

    private func flush() async {
        flushing = nil
        let batch = pending
        pending = [:]
        // One call per layout; the API takes ten at a time.
        for (layoutID, ids) in Dictionary(grouping: batch.keys, by: { batch[$0] ?? nil }) {
            for chunk in stride(from: 0, to: ids.count, by: 10).map({ Array(ids[$0 ..< min($0 + 10, ids.count)]) }) {
                _ = try? await session.recordCardViews(promoIDs: chunk, layoutID: layoutID)
            }
        }
    }
}

/// Decodes an element, or nil when it can't, so one bad element doesn't lose the list.
struct Lenient<Value: Decodable & Sendable>: Decodable, Sendable {
    let value: Value?

    init(from decoder: any Decoder) throws {
        value = try? Value(from: decoder)
    }
}

// MARK: - Operations

extension Queries {
    static let cardContentFields = "headline body imageUrl imageAlt linkUrl linkLabel"

    static let layout = """
    query Layout($screen: LayoutScreen!, $client: LayoutClientInput!, $position: CoordinatesInput, $localeId: ID) {
      layout(screen: $screen, client: $client, position: $position, localeId: $localeId) {
        id refreshAfter
        cards {
          id kind rank title
          ... on StageCard { stageEvent: event { id } venue { id } }
          ... on ChatCard { event { id } venue { id } locale { id } }
          ... on PostsCard { event { id } venue { id } locale { id } }
          ... on EventsCard { events { id } venue { id } locale { id } }
          ... on VenuesCard { venues { id } locale { id } }
          ... on PeopleCard { people { id } locale { id } }
          ... on WebCard { \(cardContentFields) }
          ... on PromoSlotCard {
            candidates { id category label sponsorName \(cardContentFields) venue { id } event { id } }
          }
        }
      }
    }
    """

    static let cardCategories = """
    query CardCategories {
      cardCategories { key label description hideable }
    }
    """

    static let recordCardViews = """
    mutation RecordCardViews($promoIds: [ID!]!, $layoutId: ID) {
      recordCardViews(input: { promoIds: $promoIds, layoutId: $layoutId }) { recorded }
    }
    """
}

struct LayoutResponse: Decodable, Sendable {
    struct Payload: Decodable, Sendable {
        var id: String
        var refreshAfter: Int
        var cards: [Lenient<LayoutCard>]
    }
    var layout: Payload
}

struct CardCategoriesResponse: Decodable, Sendable {
    var cardCategories: [CardCategory]
}

struct RecordCardViewsResponse: Decodable, Sendable {
    struct Payload: Decodable, Sendable { var recorded: Int }
    var recordCardViews: Payload?
}

extension AudienceSession {
    /// A screen's cards, ranked by the server for where the device is (or `localeID` when it has no position). Only
    /// kinds in `cardKinds` come back. ``LayoutClient`` adds the timeout and the fallback order.
    public func layout(screen: LayoutScreen, cardKinds: [String], position: Coordinate? = nil,
                       beaconMajor: Int? = nil, localeID: String? = nil, appVersion: String? = nil)
        async throws -> Layout {
        var client: [String: GraphQLValue] = ["cardKinds": .array(cardKinds.map(GraphQLValue.string))]
        if let appVersion { client["appVersion"] = .string(appVersion) }
        var variables: [String: GraphQLValue] = ["screen": .string(screen.rawValue), "client": .object(client)]
        if let position { variables["position"] = position.coordinatesInput(beaconMajor: beaconMajor) }
        if let localeID { variables["localeId"] = .string(localeID) }

        let payload = try await graphQL(Queries.layout, variables: variables, operationName: "Layout",
                                        as: LayoutResponse.self).layout
        return Layout(id: payload.id, cards: payload.cards.compactMap(\.value).sorted { $0.rank < $1.rank },
                      refreshAfter: payload.refreshAfter)
    }

    /// The published categories of promoted cards, in the audience's words, for "Cards you see".
    public func cardCategories() async throws -> [CardCategory] {
        try await graphQL(Queries.cardCategories, operationName: "CardCategories",
                          as: CardCategoriesResponse.self).cardCategories
    }

    /// Says which promoted cards were on screen (send only those actually shown, at most 10). Signed in only.
    @discardableResult
    public func recordCardViews(promoIDs: [String], layoutID: String?) async throws -> Int {
        var variables: [String: GraphQLValue] = ["promoIds": .array(promoIDs.map(GraphQLValue.string))]
        if let layoutID { variables["layoutId"] = .string(layoutID) }
        return try await graphQL(Queries.recordCardViews, variables: variables, operationName: "RecordCardViews",
                                 as: RecordCardViewsResponse.self).recordCardViews?.recorded ?? 0
    }
}
