import Foundation
import AudienceCore
import StaffKitCore

public struct StaffEventTag: Decodable, Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let color: String?
    /// The facet the system keeps this tag for, like karaoke; nil for the audience's own tags.
    public let facet: String?
    /// Whether people can identify with it in the apps.
    public let tribe: Bool?
    /// Usage counts; nil when the signed-in staff member can't see them.
    public let eventCount: Int?
    public let personCount: Int?
    public let venueCount: Int?
    public let tribePublicCount: Int?

    public init(id: String, name: String, color: String? = nil, facet: String? = nil, tribe: Bool? = nil, eventCount: Int? = nil,
                personCount: Int? = nil, venueCount: Int? = nil, tribePublicCount: Int? = nil) {
        self.id = id; self.name = name; self.color = color; self.facet = facet; self.tribe = tribe; self.eventCount = eventCount
        self.personCount = personCount; self.venueCount = venueCount; self.tribePublicCount = tribePublicCount
    }

    /// How the apps show it: "drag-brunch" for Drag Brunch.
    public var label: String { tagLabel(name) }
    public var isTribe: Bool { tribe ?? false }

    /// The people, events and venues carrying it, plus, for a tribe, the people who identify with it publicly.
    public var uses: Int {
        (eventCount ?? 0) + (personCount ?? 0) + (venueCount ?? 0) + (isTribe ? tribePublicCount ?? 0 : 0)
    }
}

/// How many tags and tribes a picker offers before you type.
public let staffTopTagCount = 8
public let staffTopTribeCount = 4

/// `tags` in picker order: facets (like karaoke) first, then the audience's own tags, then tribes, each most used
/// first, ties keeping their order.
public func staffRankTags(_ tags: [StaffEventTag]) -> [StaffEventTag] {
    func group(_ tag: StaffEventTag) -> Int { tag.facet != nil ? 0 : tag.isTribe ? 2 : 1 }
    return tags.enumerated().sorted { a, b in
        (group(a.element), -a.element.uses, a.offset) < (group(b.element), -b.element.uses, b.offset)
    }.map(\.element)
}

/// What a picker offers: the most used tags and tribes when nothing is typed, else what matches, both in picker order.
public func staffTagMatches(_ tags: [StaffEventTag], query: String) -> (tags: [StaffEventTag], tribes: [StaffEventTag]) {
    let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
    let ranked = staffRankTags(tags).filter {
        query.isEmpty || $0.label.localizedStandardContains(query) || $0.name.localizedStandardContains(query)
    }
    return (Array(ranked.filter { !$0.isTribe }.prefix(staffTopTagCount)), Array(ranked.filter(\.isTribe).prefix(staffTopTribeCount)))
}

/// A tag's name as the apps show it: lowercase, with a dash for each run of spaces, so "Drag Brunch" is "drag-brunch".
public func tagLabel(_ name: String) -> String {
    name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().split(whereSeparator: \.isWhitespace).joined(separator: "-")
}

public struct StaffKaraokeNight: Decodable, Sendable {
    public let providerName: String?
    public let sessionCode: String?
    public let ownSessionCode: String?
    public let joinUrl: String?
}

/// Shared by event and series editors. Venue control explicitly clears an old session override.
public struct StaffKaraokeDraft: Sendable, Equatable {
    public var enabled: Bool
    public var venueControlled: Bool
    public var sessionCode: String
    public init(enabled: Bool = false, ownSessionCode: String? = nil) {
        self.enabled = enabled
        venueControlled = ownSessionCode?.isEmpty != false
        sessionCode = ownSessionCode ?? ""
    }
    public init(night: StaffKaraokeNight?) { self.init(enabled: night != nil, ownSessionCode: night?.ownSessionCode) }
    public var effectiveCode: String? {
        let code = sessionCode.trimmingCharacters(in: .whitespacesAndNewlines)
        return enabled && !venueControlled && !code.isEmpty ? code : nil
    }
    public var seriesFields: [String: GraphQLValue] {
        ["karaoke": .bool(enabled), "karaokeSessionCode": effectiveCode.map(GraphQLValue.string) ?? .null]
    }
}

extension VenueManagementClient {
    @discardableResult
    public func setKaraoke(eventID: String, draft: StaffKaraokeDraft) async throws -> VenueEvent {
        struct Payload: Decodable, Sendable { let event: VenueEvent }
        struct Response: Decodable, Sendable { let setEventKaraoke: Payload }
        return try await session.graphQL("""
            mutation StaffEventKaraoke($id: ID!, $karaoke: Boolean!, $code: String) {
                setEventKaraoke(input: { id: $id, karaoke: $karaoke, sessionCode: $code }) { event { \(Self.eventFields) } }
            }
            """, variables: ["id": .string(eventID), "karaoke": .bool(draft.enabled),
                "code": .string(draft.effectiveCode ?? "")], as: Response.self).setEventKaraoke.event
    }
    public func tags() async throws -> [StaffEventTag] { try await session.eventTags() }
}

extension TalentManagementClient {
    public func setKaraoke(eventID: String, draft: StaffKaraokeDraft) async throws {
        struct Response: Decodable, Sendable {}
        _ = try await session.graphQL("""
            mutation TalentEventKaraoke($id: ID!, $karaoke: Boolean!, $code: String) {
                setEventKaraoke(input: { id: $id, karaoke: $karaoke, sessionCode: $code }) { event { id } }
            }
            """, variables: ["id": .string(eventID), "karaoke": .bool(draft.enabled),
                "code": .string(draft.effectiveCode ?? "")], as: Response.self)
    }
    public func tags() async throws -> [StaffEventTag] { try await session.eventTags() }
}

private extension AudienceManagementSession {
    func eventTags() async throws -> [StaffEventTag] {
        struct Response: Decodable, Sendable { let tags: [StaffEventTag] }
        return try await graphQL("query StaffEventTags { tags { id name color facet tribe eventCount personCount venueCount tribePublicCount } }", as: Response.self).tags
    }
}
