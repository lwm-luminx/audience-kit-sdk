import Foundation

// Choosing which Soapbox publication to work on, the way staff apps choose a locale: search by name or place, the ones
// near the device, and the ones chosen last on this device (Rick, 2026-11-23: "soapbox needs a select publisher like
// selecting a locale - with search and near me for admins to use it"). An audience's admins run every publication, so
// a list of them all doesn't fit a sidebar. These documents run on the staff endpoint (`# endpoint: staff`), which
// this SDK doesn't call: StaffKit's session sends them and decodes the answers into ``PublisherDirectory``. Android's
// are the same word for word.

/// A publication someone may switch to, with the place it covers.
public struct PublisherChoice: Decodable, Sendable, Hashable, Identifiable {
    public let id: String
    /// Its masthead, else its person's name.
    public let name: String
    public let masthead: String?
    /// The person listing it publishes as, when its name differs from ``name``.
    public let personName: String?
    /// The API's `PublicationTrust` (`TRUSTED`, `PENDING`, `SUSPENDED`); nil when the viewer may not see it.
    public let trust: String?
    public let localeID: String?
    public let localeName: String?
    /// The locales its locale lies within, innermost first: ["Utah", "United States"].
    public let localeAncestors: [String]
    /// Its locale's point, for Nearby.
    public let coordinate: Coordinate?

    public init(id: String, name: String, masthead: String? = nil, personName: String? = nil, trust: String? = nil,
                localeID: String? = nil, localeName: String? = nil, localeAncestors: [String] = [],
                coordinate: Coordinate? = nil) {
        self.id = id; self.name = name; self.masthead = masthead; self.personName = personName; self.trust = trust
        self.localeID = localeID; self.localeName = localeName; self.localeAncestors = localeAncestors
        self.coordinate = coordinate
    }

    /// "Salt Lake City, Utah": the place it covers with the one it lies within. Nil when it covers no locale.
    public var place: String? {
        guard let localeName, !localeName.isEmpty else { return nil }
        return localeAncestors.first.map { "\(localeName), \($0)" } ?? localeName
    }

    /// Whether it is waiting for the audience's admins (a row says "Pending"), or they suspended it.
    public var isPending: Bool { trust == "PENDING" }
    public var isSuspended: Bool { trust == "SUSPENDED" }

    private struct Ref: Decodable { let id: String?; let name: String? }
    private struct Location: Decodable { let point: String? }
    private struct LocaleField: Decodable {
        let id: String
        let name: String?
        let ancestors: [Ref]?
        let location: Location?
    }

    private enum CodingKeys: String, CodingKey { case id, name, masthead, trust, person, locale }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let name = try container.decode(String.self, forKey: .name)
        let person = try container.decodeIfPresent(Ref.self, forKey: .person)
        let locale = try container.decodeIfPresent(LocaleField.self, forKey: .locale)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            name: name,
            masthead: try container.decodeIfPresent(String.self, forKey: .masthead),
            personName: person?.name.flatMap { $0.isEmpty || $0 == name ? nil : $0 },
            trust: try container.decodeIfPresent(String.self, forKey: .trust),
            localeID: locale?.id,
            localeName: locale?.name,
            // The API lists them outermost first.
            localeAncestors: (locale?.ancestors ?? []).compactMap { $0.name.flatMap { $0.isEmpty ? nil : $0 } }.reversed(),
            coordinate: locale?.location?.point.flatMap(Coordinate.init(wkt:)))
    }
}

/// The publications someone may switch to, as a chooser lists them: by name, found by name or place, nearest first
/// from a position, or picked out by ID (the recent ones).
public struct PublisherDirectory: Sendable, Hashable {
    /// Every publication, by name.
    public let entries: [PublisherChoice]

    public init(_ publishers: [PublisherChoice]) {
        entries = publishers.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public func entry(_ id: String) -> PublisherChoice? { entries.first { $0.id == id } }

    /// The ones with these IDs, in this order, leaving out any no longer here (``PublisherRecents``).
    public func entries(_ ids: [String]) -> [PublisherChoice] { ids.compactMap(entry) }

    /// Publications matching `text`, best first: a name that is the text, then names starting with it, then a word in
    /// the name starting with it, then names containing it, then its masthead or person, then the place it covers
    /// ("salt lake", "Utah" finds every Utah paper). Case and accents are ignored.
    public func search(_ text: String) -> [PublisherChoice] {
        let query = Self.fold(text)
        guard !query.isEmpty else { return entries }
        return entries.enumerated().compactMap { offset, entry -> (PublisherChoice, Int, Int)? in
            let name = Self.fold(entry.name)
            let rank: Int
            if name == query { rank = 0 }
            else if name.hasPrefix(query) { rank = 1 }
            else if Self.words(name).contains(where: { $0.hasPrefix(query) }) { rank = 2 }
            else if name.contains(query) { rank = 3 }
            else if [entry.masthead, entry.personName].contains(where: { $0.map { Self.fold($0).contains(query) } ?? false }) { rank = 4 }
            else if let place = entry.place, Self.fold(place).contains(query) { rank = 5 }
            else if entry.localeAncestors.contains(where: { Self.fold($0).contains(query) }) { rank = 6 }
            else { return nil }
            return (entry, rank, offset)
        }
        // Stable within a rank: entries are already by name.
        .sorted { ($0.1, $0.2) < ($1.1, $1.2) }.map(\.0)
    }

    /// A publication near a position: whether the position lies inside the place it covers, and how far away that
    /// place's point is.
    public struct Nearby: Sendable, Hashable, Identifiable {
        public let publisher: PublisherChoice
        public let inside: Bool
        /// Meters; nil when its locale has no point.
        public let distance: Double?
        public var id: String { publisher.id }
    }

    /// Publications near `position`, best first: the ones covering a locale it lies in (`containing`, from the API's
    /// `locales(at:)`, outermost first as it answers, so the most local come first), then the closest by their
    /// locale's point within `radius` meters. At most `limit`.
    public func nearby(_ position: Coordinate, containing: [String] = [], radius: Double = 150_000,
                       limit: Int = 8) -> [Nearby] {
        let depth = Dictionary(containing.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: { first, _ in first })
        let inside = entries.compactMap { entry -> (Nearby, Int)? in
            guard let localeID = entry.localeID, let level = depth[localeID] else { return nil }
            return (Nearby(publisher: entry, inside: true, distance: entry.coordinate.map { Self.distance(position, $0) }), level)
        }
        // Innermost locale first; the same locale by name.
        .sorted { $0.1 > $1.1 }.map(\.0)
        let insideIDs = Set(inside.map(\.id))
        let close = entries.compactMap { entry -> Nearby? in
            guard !insideIDs.contains(entry.id), let point = entry.coordinate else { return nil }
            let meters = Self.distance(position, point)
            return meters <= radius ? Nearby(publisher: entry, inside: false, distance: meters) : nil
        }
        .sorted { ($0.distance ?? 0) < ($1.distance ?? 0) }
        return Array((inside + close).prefix(limit))
    }

    /// Great-circle distance in meters.
    public static func distance(_ from: Coordinate, _ to: Coordinate) -> Double {
        let radians = Double.pi / 180
        let dLat = (to.latitude - from.latitude) * radians
        let dLon = (to.longitude - from.longitude) * radians
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(from.latitude * radians) * cos(to.latitude * radians) * sin(dLon / 2) * sin(dLon / 2)
        return 6_371_000 * 2 * atan2(sqrt(a), sqrt(1 - a))
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func words(_ text: String) -> [Substring] {
        text.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
    }
}

/// The publications last chosen in an audience on this device, newest first; the first is the one being worked on.
/// Kept in `UserDefaults` per audience and never sent anywhere. Forget it on sign-out with ``clear()``.
public struct PublisherRecents: @unchecked Sendable {
    public static let limit = 6
    public let audienceID: String
    private let defaults: UserDefaults
    private var key: String { "AudienceKit.recentPublishers.\(audienceID)" }

    public init(audienceID: String, defaults: UserDefaults = .standard) {
        self.audienceID = audienceID
        self.defaults = defaults
    }

    /// Newest first.
    public func ids() -> [String] { defaults.stringArray(forKey: key) ?? [] }

    public func record(_ id: String) {
        guard !id.isEmpty else { return }
        defaults.set(Self.adding(id, to: ids()), forKey: key)
    }

    public func clear() { defaults.removeObject(forKey: key) }

    /// `id` moved to the front, without duplicates, at most ``limit``.
    public static func adding(_ id: String, to list: [String]) -> [String] {
        Array(([id] + list.filter { $0 != id }).prefix(limit))
    }
}

/// The documents a publisher chooser sends, and their answers.
public enum PublisherChooserDocuments {
    public static let publisherFields = """
        id name masthead trust person { id name } locale { id name ancestors { id name } location { point } }
        """

    /// The publications the signed-in user runs; every one for the audience's admins.
    public static let publishersQuery = """
        # endpoint: staff
        query SoapboxPublisherChooser { soapbox { myPublications { \(publisherFields) } } }
        """

    /// The locales a position lies in, outermost first: pass `here` as ``Coordinate/graphQLValue``.
    public static let localesAtQuery = """
        # endpoint: staff
        query SoapboxLocalesAt($here: CoordinatesInput!) { locales(at: $here) { id } }
        """

    /// ``publishersQuery``'s `data`.
    public struct PublishersResponse: Decodable, Sendable {
        private struct Soapbox: Decodable { let myPublications: [PublisherChoice]? }
        private let soapbox: Soapbox
        public var publishers: [PublisherChoice] { soapbox.myPublications ?? [] }
        public var directory: PublisherDirectory { PublisherDirectory(publishers) }
    }

    /// ``localesAtQuery``'s `data`.
    public struct LocalesAtResponse: Decodable, Sendable {
        private struct Ref: Decodable { let id: String }
        private let locales: [Ref]
        /// Outermost first.
        public var ids: [String] { locales.map(\.id) }
    }
}
