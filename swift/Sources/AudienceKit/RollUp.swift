import AudienceCore
import Foundation

// Roll-ups (API doc/ROLL_UP.md): items linked to what they are about, shown on that record and everything above it. A
// podcast episode recorded live at a party is linked to that night's event, so it shows on the event and among the
// hosting venue's items; the same goes for a venue's series, a locale's venues and the people billed on an event.
// Links come from fuzzy matching (episode text against venue names and event dates) or from an admin. An API without
// roll-ups returns no items.

/// What kind of item is linked.
public enum RolledUpItemKind: String, Codable, Sendable, CaseIterable {
    /// A podcast episode or music track.
    case track = "TRACK"
    /// A film or television title.
    case mediaTitle = "MEDIA_TITLE"
    /// An episode of a series.
    case mediaEpisode = "MEDIA_EPISODE"
    case article = "ARTICLE"
    case person = "PERSON"

    init?(typename: String?) {
        switch typename {
        case "Track": self = .track
        case "MediaTitle": self = .mediaTitle
        case "MediaEpisode": self = .mediaEpisode
        case "Article": self = .article
        case "Person": self = .person
        default: return nil
        }
    }
}

/// Where a link stands. Everyone sees `linked` items; admins may also ask for the others.
public enum EntityLinkStatus: String, Codable, Sendable, CaseIterable {
    case linked = "LINKED"
    /// Found by matching, but not sure enough to show until an admin confirms it.
    case suggested = "SUGGESTED"
    /// Turned down: never shown, never suggested again.
    case rejected = "REJECTED"
}

/// The event an item was linked to: the night an episode was recorded, say.
public struct RolledUpEvent: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String?
    public let startAt: Date?

    public init(id: String, name: String? = nil, startAt: Date? = nil) {
        self.id = id
        self.name = name
        self.startAt = startAt
    }
}

/// One item linked to a record or to something under it (``AudienceSession/rollUp(id:kinds:limit:)``), flattened for
/// a list row: a title, a line under it, a link out and, for an episode, its audio.
public struct RolledUpItem: Decodable, Sendable, Hashable, Identifiable {
    /// The link's ID.
    public let id: String
    /// What kind of item it is; nil for a kind this SDK doesn't know yet.
    public let kind: RolledUpItemKind?
    /// The item's own ID (a track's, a film's).
    public let itemID: String
    public let title: String?
    /// A line under the title: an episode's event and venue night, a film's year, a series episode's code.
    public let subtitle: String?
    /// Where to open it: the episode on its podcast host, the film on IMDb, the article's page.
    public let url: String?
    public let artworkUrl: String?
    /// An episode's or track's audio.
    public let streamUrl: String?
    /// When the item came out, if known.
    public let publishedAt: Date?
    /// The event it was linked to, if any.
    public let event: RolledUpEvent?
    public let status: EntityLinkStatus?
    /// Whether matching found it (an admin made the others).
    public let isMatched: Bool
    /// How sure matching is, 0 to 1; nil for links people made.
    public let score: Double?

    public init(id: String, kind: RolledUpItemKind?, itemID: String, title: String? = nil, subtitle: String? = nil,
                url: String? = nil, artworkUrl: String? = nil, streamUrl: String? = nil, publishedAt: Date? = nil,
                event: RolledUpEvent? = nil, status: EntityLinkStatus? = .linked, isMatched: Bool = false,
                score: Double? = nil)
    {
        self.id = id
        self.kind = kind
        self.itemID = itemID
        self.title = title
        self.subtitle = subtitle
        self.url = url
        self.artworkUrl = artworkUrl
        self.streamUrl = streamUrl
        self.publishedAt = publishedAt
        self.event = event
        self.status = status
        self.isMatched = isMatched
        self.score = score
    }

    private struct Item: Decodable, Sendable {
        var __typename: String?
        var id: String
        var title: String?
        var filmTitle: String?
        var episodeTitle: String?
        var articleTitle: String?
        var name: String?
        var providerUrl: String?
        var streamUrl: String?
        var artworkUrl: String?
        var releasedAt: Date?
        var filmImdbUrl: String?
        var episodeImdbUrl: String?
        var year: Int?
        var code: String?
        var canonicalUrl: String?
        var heroPhotoUrl: String?
        var publishedAt: Date?
        var avatarUrl: String?
    }

    private enum CodingKeys: String, CodingKey { case id, item, event, status, origin, score }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let item = try container.decode(Item.self, forKey: .item)
        id = try container.decode(String.self, forKey: .id)
        kind = RolledUpItemKind(typename: item.__typename)
        itemID = item.id
        title = item.title ?? item.filmTitle ?? item.episodeTitle ?? item.articleTitle ?? item.name
        event = try container.decodeIfPresent(RolledUpEvent.self, forKey: .event)
        subtitle = item.code ?? item.year.map(String.init) ?? event?.name
        url = item.providerUrl ?? item.filmImdbUrl ?? item.episodeImdbUrl ?? item.canonicalUrl
        artworkUrl = item.artworkUrl ?? item.heroPhotoUrl ?? item.avatarUrl
        streamUrl = item.streamUrl
        publishedAt = item.releasedAt ?? item.publishedAt
        status = (try? container.decodeIfPresent(String.self, forKey: .status)).flatMap(EntityLinkStatus.init)
        isMatched = (try? container.decodeIfPresent(String.self, forKey: .origin)) == "FUZZY"
        score = try container.decodeIfPresent(Double.self, forKey: .score)
    }
}

extension Queries {
    /// The record types `rollUp` is on, and the item types its rows read (each module's, when the audience has it).
    static let rollUpTypes = ["Venue", "Event", "EventSeries", "Person", "Locale", "EntityLink", "Track", "MediaTitle",
                              "MediaEpisode", "Article"]

    /// Each kind of item a row reads, if the schema has it: an audience without the media module has no MediaTitle.
    static let rolledUpItemFragments: [(type: String, check: String, fields: String)] = [
        ("Track", "streamUrl", "id title providerUrl streamUrl artworkUrl releasedAt"),
        // Titles and IMDb links differ in nullability between types, so all but the track's are aliased.
        ("MediaTitle", "imdbUrl", "id filmTitle: title year filmImdbUrl: imdbUrl"),
        ("MediaEpisode", "code", "id episodeTitle: title code episodeImdbUrl: imdbUrl"),
        ("Article", "canonicalUrl", "id articleTitle: title canonicalUrl heroPhotoUrl publishedAt"),
        ("Person", "avatarUrl", "id name avatarUrl"),
    ]

    static func rolledUpItemFields(_ shape: SchemaShape) -> String {
        let fragments = rolledUpItemFragments.filter { shape.has($0.type, $0.check) }
            .map { "... on \($0.type) { \($0.fields) }" }.joined(separator: " ")
        return "id status origin score event { id name startAt } item { __typename \(fragments) }"
    }

    static func rollUp(_ shape: SchemaShape) -> String {
        guard shape.has("Venue", "rollUp") else { return "query RollUp { id }" }
        let field = "rollUp(itemKinds: $kinds, limit: $limit, statuses: $statuses) { \(rolledUpItemFields(shape)) }"
        let records = ["Venue", "Event", "EventSeries", "Person", "Locale"].filter { shape.has($0, "rollUp") }
        return """
        query RollUp($id: ID!, $kinds: [EntityLinkItemKind!], $limit: Int, $statuses: [EntityLinkStatus!]) {
          node(id: $id) { \(records.map { "... on \($0) { \(field) }" }.joined(separator: " ")) }
        }
        """
    }
}

struct RollUpResponse: Decodable, Sendable {
    struct Holder: Decodable, Sendable { var rollUp: [Lenient<RolledUpItem>]? }
    var node: Holder?

    var items: [RolledUpItem] { node?.rollUp?.compactMap(\.value) ?? [] }
}

extension AudienceSession {
    /// Items linked to a venue, event, event series, person or locale, or to anything under it, newest first: a
    /// venue's include those linked to its events, so a podcast episode recorded live at a party shows among the
    /// venue's items. Empty from an API without roll-ups. Only admins get anything but linked items.
    public func rollUp(id: String, kinds: [RolledUpItemKind]? = nil, limit: Int = 50,
                       statuses: [EntityLinkStatus]? = nil) async throws -> [RolledUpItem]
    {
        var variables: [String: GraphQLValue] = ["id": .string(id), "limit": .int(limit)]
        if let kinds { variables["kinds"] = .array(kinds.map { .string($0.rawValue) }) }
        if let statuses { variables["statuses"] = .array(statuses.map { .string($0.rawValue) }) }
        return try await graphQL(types: Queries.rollUpTypes, variables: variables, operationName: "RollUp",
                                 as: RollUpResponse.self, document: Queries.rollUp).items
    }
}
