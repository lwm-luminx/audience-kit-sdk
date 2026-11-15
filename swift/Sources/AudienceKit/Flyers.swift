import AudienceCore
import Foundation

// Digital flyers and community resources (the API's doc/DIGITAL_FLYERS.md).
//
// - A digital flyer is a card for a city, like a flyer on a community board: the server chooses a city's flyers from
//   the city and the time and nothing else, so everyone in the city at that moment sees the same pool. It arrives as
//   the ``CardKind/flyers`` card of the Now layout (``LayoutCard/flyers``).
// - Dismissing one flyer or hiding a whole category is kept on this phone only (``FlyerDismissals``): never sent to the
//   server, never logged, never synced (not even through iCloud), never counted.
// - Show ``FlyersCardContent/disclosure`` and the explainer link on every flyer card. Pick one of a flyer's
//   ``DigitalFlyer/lines`` per showing with ``FlyerLinePicker`` (random, never the same line twice in a row).
// - The community resource directory (``AudienceSession/communityDirectory(localeID:)``) is fetched whole, without
//   sign-in, whenever the app knows the city, and kept on the phone. "I need food", filtering by facet and opening a
//   resource then happen on the phone and send nothing.

extension CardKind {
    /// The city's digital flyers (``LayoutCard/flyers``).
    public static let flyers = "flyers"
}

/// One digital flyer.
public struct DigitalFlyer: Codable, Sendable, Hashable, Identifiable {
    /// Dismissing it is kept on the phone by this.
    public let id: String
    public let headline: String
    public let body: String?
    public let linkUrl: String?
    public let linkLabel: String?
    /// What it is about. Its tone and category follow from these, never from who is looking.
    public let tags: [String]
    /// `gentle`, `health` or `playful`.
    public let tone: String
    /// The category a person can hide it by (``FlyerCopy/categories``).
    public let category: String
    /// The tone's lines, one shown at a time (``FlyerLinePicker``).
    public let lines: [String]
    /// The resource it points at, if any.
    public let resource: ResourceRef?

    public struct ResourceRef: Codable, Sendable, Hashable {
        public let id: String
        /// What to call it: a neutral title for a DV or stalking resource.
        public let title: String
        /// A DV or stalking resource: open it with the quick-exit button and keep it out of history.
        public let sensitive: Bool

        public init(id: String, title: String, sensitive: Bool) {
            self.id = id
            self.title = title
            self.sensitive = sensitive
        }
    }

    public init(id: String, headline: String, body: String? = nil, linkUrl: String? = nil, linkLabel: String? = nil,
                tags: [String] = [], tone: String = "playful", category: String = "community", lines: [String] = [],
                resource: ResourceRef? = nil) {
        self.id = id
        self.headline = headline
        self.body = body
        self.linkUrl = linkUrl
        self.linkLabel = linkLabel
        self.tags = tags
        self.tone = tone
        self.category = category
        self.lines = lines
        self.resource = resource
    }

    /// No cheek: crisis, food, housing, health coverage, youth or DV.
    public var isGentle: Bool { tone == "gentle" }
}

/// What a ``CardKind/flyers`` card carries.
public struct FlyersCardContent: Codable, Sendable, Hashable {
    /// Show on the card. It is about the flyer, never the app; legal review can change it without a release.
    public let disclosure: String
    /// The explainer link's text, e.g. "What's a digital flyer?".
    public let explainerLabel: String
    public let explainerUrl: String
    /// The pool, in rotation order. Drop what ``FlyerDismissals`` says before showing.
    public let flyers: [DigitalFlyer]

    public init(disclosure: String, explainerLabel: String, explainerUrl: String, flyers: [DigitalFlyer]) {
        self.disclosure = disclosure
        self.explainerLabel = explainerLabel
        self.explainerUrl = explainerUrl
        self.flyers = flyers
    }

    /// The flyers still to show after this phone's dismissals.
    public func visible(_ dismissals: FlyerDismissals) -> [DigitalFlyer] {
        flyers.filter { dismissals.allows($0) }
    }
}

/// The flyers and categories dismissed on this phone. Kept in `UserDefaults` only: never sent to the server, logged,
/// counted or synced through iCloud (unlike ``CardPreferences``), because which kinds of help someone hid is nobody
/// else's business.
public final class FlyerDismissals: @unchecked Sendable {
    public static let flyersKey = "audiencekit.flyers.dismissed"
    public static let categoriesKey = "audiencekit.flyers.hiddenCategories"
    /// How many dismissed flyers it remembers; the oldest go first.
    public static let limit = 500

    private let defaults: UserDefaults
    private let lock = NSLock()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var dismissedFlyers: [String] { lock.withLock { defaults.stringArray(forKey: Self.flyersKey) ?? [] } }
    public var hiddenCategories: Set<String> {
        lock.withLock { Set(defaults.stringArray(forKey: Self.categoriesKey) ?? []) }
    }

    public func allows(_ flyer: DigitalFlyer) -> Bool {
        !hiddenCategories.contains(flyer.category) && !dismissedFlyers.contains(flyer.id)
    }

    public func dismiss(_ flyer: DigitalFlyer) {
        lock.withLock {
            var ids = (defaults.stringArray(forKey: Self.flyersKey) ?? []).filter { $0 != flyer.id }
            ids.append(flyer.id)
            defaults.set(Array(ids.suffix(Self.limit)), forKey: Self.flyersKey)
        }
    }

    public func setHidden(category: String, _ hide: Bool) {
        lock.withLock {
            var hidden = Set(defaults.stringArray(forKey: Self.categoriesKey) ?? [])
            if hide { hidden.insert(category) } else { hidden.remove(category) }
            defaults.set(hidden.sorted(), forKey: Self.categoriesKey)
        }
    }

    /// Shows every flyer and category again.
    public func reset() {
        lock.withLock {
            defaults.removeObject(forKey: Self.flyersKey)
            defaults.removeObject(forKey: Self.categoriesKey)
        }
    }
}

/// Picks the line a flyer shows: at random, never the line this phone showed last (unless it's the only one). The last
/// line is kept on the phone only.
public final class FlyerLinePicker: @unchecked Sendable {
    public static let key = "audiencekit.flyers.lastLine"

    private let defaults: UserDefaults
    private let lock = NSLock()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func line(for flyer: DigitalFlyer) -> String? {
        var generator = SystemRandomNumberGenerator()
        return line(for: flyer, using: &generator)
    }

    public func line(for flyer: DigitalFlyer, using generator: inout some RandomNumberGenerator) -> String? {
        lock.withLock {
            let picked = Self.pick(from: flyer.lines, last: defaults.string(forKey: Self.key), using: &generator)
            if let picked { defaults.set(picked, forKey: Self.key) }
            return picked
        }
    }

    /// A random line other than `last`, when there is another.
    public static func pick(from lines: [String], last: String?,
                            using generator: inout some RandomNumberGenerator) -> String? {
        let choices = lines.count > 1 ? lines.filter { $0 != last } : lines
        return choices.randomElement(using: &generator)
    }
}

/// A kind of flyer a person can hide all of.
public struct FlyerCategory: Codable, Sendable, Hashable, Identifiable {
    public let key: String
    public let label: String
    public var id: String { key }

    public init(key: String, label: String) {
        self.key = key
        self.label = label
    }
}

/// "I need...": a choice that goes straight to resources with these facets, filtered on the phone.
public struct ResourceNeed: Codable, Sendable, Hashable, Identifiable {
    public let key: String
    public let label: String
    public let facets: [String]
    public var id: String { key }

    public init(key: String, label: String, facets: [String]) {
        self.key = key
        self.label = label
        self.facets = facets
    }
}

/// The words around flyers and resources, from the server (legal review is pending, so none live in the apps).
public struct FlyerCopy: Codable, Sendable, Hashable {
    public let disclosure: String
    public let explainerLabel: String
    public let explainerUrl: String
    public let categories: [FlyerCategory]
    public let needs: [ResourceNeed]
    public let advocacy: [String]
    public let quickExit: String
}

/// One entry of a resource's hours or sessions. Days are 0 (Sunday) to 6; times are HH:MM in the city's time zone.
public struct ResourceSlot: Codable, Sendable, Hashable {
    public let days: [Int]
    public let from: String?
    public let until: String?
    public let place: String?
    public let address: String?
    public let note: String?

    public init(days: [Int] = [], from: String? = nil, until: String? = nil, place: String? = nil,
                address: String? = nil, note: String? = nil) {
        self.days = days
        self.from = from
        self.until = until
        self.place = place
        self.address = address
        self.note = note
    }

    private enum CodingKeys: String, CodingKey { case days, from, until, place, address, note }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        days = try container.decodeIfPresent([Int].self, forKey: .days) ?? []
        from = try container.decodeIfPresent(String.self, forKey: .from)
        until = try container.decodeIfPresent(String.self, forKey: .until)
        place = try container.decodeIfPresent(String.self, forKey: .place)
        address = try container.decodeIfPresent(String.self, forKey: .address)
        note = try container.decodeIfPresent(String.self, forKey: .note)
    }
}

/// A community resource: a food pantry, shelter, clinic, STI testing, mental health, crisis or DV service.
public struct CommunityResource: Codable, Sendable, Hashable, Identifiable {
    public struct NextSession: Codable, Sendable, Hashable {
        public let session: ResourceSlot
        public let startsAt: String
        public let endsAt: String
    }

    public let id: String
    /// Show this in lists, flyers and screen titles: a neutral title for a DV or stalking resource.
    public let title: String
    /// Its real name, for its page body only.
    public let name: String
    /// A DV or stalking resource: show the quick-exit button, keep it out of history, recents and favorites, and use
    /// ``title`` everywhere but the page body.
    public let sensitive: Bool
    public let description: String?
    public let facets: [String]
    public let address: String?
    public let latitude: Double?
    public let longitude: Double?
    public let phone: String?
    public let textNumber: String?
    public let url: String?
    public let hours: [ResourceSlot]
    public let sessions: [ResourceSlot]
    public let intakeNote: String?
    public let sourceUrl: String?
    /// When its details were checked (yyyy-mm-dd); nil until someone has, and the app shows no date.
    public let checkedAt: String?
    public let nextSession: NextSession?

    public func has(_ facet: String) -> Bool { facets.contains(facet) }
}

/// A city's community resource directory, kept on the phone and filtered there.
public struct CommunityDirectory: Codable, Sendable, Hashable {
    public struct Locale: Codable, Sendable, Hashable {
        public let id: String
        public let name: String
    }

    public let locale: Locale
    public let resources: [CommunityResource]
    public let facets: [String]
    public let needs: [ResourceNeed]
    public let advocacy: [String]
    public let quickExit: String

    /// The resources for a need, filtered on the phone: nothing is sent.
    public func resources(for need: ResourceNeed) -> [CommunityResource] {
        resources(withAnyOf: need.facets)
    }

    /// The resources with any of `facets`, and all of `alsoRequiring` (e.g. `no-id-required`, `lgbtq-affirming`).
    public func resources(withAnyOf facets: [String], alsoRequiring: [String] = []) -> [CommunityResource] {
        resources.filter { resource in
            (facets.isEmpty || facets.contains(where: resource.has)) && alsoRequiring.allSatisfy(resource.has)
        }
    }
}

// MARK: - Operations

extension Queries {
    static let flyerFields = """
    disclosure explainerLabel explainerUrl
    flyers { id headline body linkUrl linkLabel tags tone category lines resource { id title sensitive } }
    """

    static let flyerCopy = """
    query FlyerCopy {
      flyerCopy {
        disclosure explainerLabel explainerUrl quickExit advocacy
        categories { key label } needs { key label facets }
      }
    }
    """
}

struct FlyerCopyResponse: Decodable, Sendable {
    var flyerCopy: FlyerCopy
}

extension AudienceSession {
    /// The words around flyers and resources: the categories to offer in settings, the "I need..." choices, the DV
    /// advocacy lines and the quick-exit label.
    public func flyerCopy() async throws -> FlyerCopy {
        try await graphQL(Queries.flyerCopy, operationName: "FlyerCopy", as: FlyerCopyResponse.self).flyerCopy
    }

    /// A city's whole community resource directory, `GET /v1/audience/<id>/community_resources?locale_id=<id>`, sent
    /// without the session token so it says nothing about who asked. Fetch it whenever the city is known, whether or
    /// not anyone opens it, and keep it: needs and resource pages then work from it without another request.
    public func communityDirectory(localeID: String) async throws -> CommunityDirectory {
        let request = APIRequest(path: "/v1/audience/\(try await audienceID())/community_resources",
                                 queryItems: [URLQueryItem(name: "locale_id", value: localeID)], authenticated: false)
        let data = try await data(for: request)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            return try decoder.decode(CommunityDirectory.self, from: data)
        } catch {
            throw AudienceKitError.decoding(String(describing: error))
        }
    }
}
