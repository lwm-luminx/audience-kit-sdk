import Foundation
import AudienceCore
import StaffKitCore

/// A named set of a venue's screens that show the same thing, such as "Bar TVs" (the API's VenueDisplayGroup; Rick,
/// 2026-11-23: screens "all have edit or assigned groups"). The group holds one setup, and each display assigned to
/// it answers with that in place of its own, so a screen follows its group by reading its display as it always has.
public struct StaffVenueDisplayGroup: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public var name: String
    /// Its screens show only the venue's logo.
    public var off: Bool
    /// Its screens lay the song playing over whatever they show.
    public var nowPlaying: Bool
    public var ranking: [StaffVenueDisplay.Entry]
    public var slideshows: [StaffVenueSlideshow]
    /// The displays assigned to it.
    public var displayIds: [String]

    public init(id: String, name: String, off: Bool = false, nowPlaying: Bool = true,
                ranking: [StaffVenueDisplay.Entry] = StaffVenueDisplay.defaultRanking,
                slideshows: [StaffVenueSlideshow] = [], displayIds: [String] = []) {
        self.id = id; self.name = name; self.off = off; self.nowPlaying = nowPlaying; self.ranking = ranking
        self.slideshows = slideshows; self.displayIds = displayIds
    }

    /// What its screens show, in a line: its ranking in order, or that they're off.
    public var showsLine: String { off ? "Off (logo only)" : ranking.map(\.type.title).joined(separator: ", then ") }

    /// The group a display is assigned to, if any.
    public static func of(_ displayID: String, in groups: [StaffVenueDisplayGroup]) -> StaffVenueDisplayGroup? {
        groups.first { $0.displayIds.contains(displayID) }
    }
}

extension VenueManagementClient {
    static let venueDisplayGroupFields = """
        id name off nowPlaying displayIds ranking { type slideshowId slideId seconds photos chatSize } \
        slideshows { \(venueSlideshowFields) }
        """

    /// The venue's screen groups, by name. Asked on its own, apart from the screens, so an API that has no groups yet
    /// fails only this read.
    public func venueDisplayGroups(venueID: String) async throws -> [StaffVenueDisplayGroup] {
        struct Venue: Decodable, Sendable { let displayGroups: [StaffVenueDisplayGroup] }
        struct Venues: Decodable, Sendable { let venue: Venue? }
        struct Response: Decodable, Sendable { let venues: Venues }
        let response = try await session.graphQL("""
            query StaffVenueDisplayGroups($id: ID!) { venues { venue(id: $id) { displayGroups { \(Self.venueDisplayGroupFields) } } } }
            """, variables: ["id": .string(venueID)], as: Response.self)
        return response.venues.venue?.displayGroups ?? []
    }

    /// Makes a group at the venue (`id` nil, with a name) or changes one; nil leaves each field as it is. A new group
    /// starts with the default ranking.
    @discardableResult
    public func saveVenueDisplayGroup(id: String? = nil, venueID: String? = nil, name: String? = nil, off: Bool? = nil,
                                      nowPlaying: Bool? = nil,
                                      ranking: [StaffVenueDisplay.Entry]? = nil) async throws -> StaffVenueDisplayGroup {
        struct Payload: Decodable, Sendable { let group: StaffVenueDisplayGroup }
        struct Response: Decodable, Sendable { let saveVenueDisplayGroup: Payload }
        var input: [String: GraphQLValue] = [:]
        if let id { input["id"] = .string(id) }
        if let venueID { input["venueId"] = .string(venueID) }
        if let name { input["name"] = .string(name) }
        if let off { input["off"] = .bool(off) }
        if let nowPlaying { input["nowPlaying"] = .bool(nowPlaying) }
        if let ranking { input["ranking"] = .array(ranking.map(\.input)) }
        let response = try await session.graphQL("""
            mutation StaffVenueDisplayGroupSave($input: VenueDisplayGroupSaveInput!) {
              saveVenueDisplayGroup(input: $input) { group { \(Self.venueDisplayGroupFields) } }
            }
            """, variables: ["input": .object(input)], as: Response.self)
        return response.saveVenueDisplayGroup.group
    }

    /// Deletes a group; its screens go back to their own setups.
    public func deleteVenueDisplayGroup(id: String) async throws {
        struct Payload: Decodable, Sendable { let id: String }
        struct Response: Decodable, Sendable { let deleteVenueDisplayGroup: Payload }
        _ = try await session.graphQL("""
            mutation StaffVenueDisplayGroupDelete($id: ID!) { deleteVenueDisplayGroup(input: { id: $id }) { id } }
            """, variables: ["id": .string(id)], as: Response.self)
    }

    /// Assigns a screen to a group, or (nil) takes it out of its group and back to its own setup.
    @discardableResult
    public func assignVenueDisplay(id: String, toGroup groupID: String?) async throws -> StaffVenueDisplay {
        struct Payload: Decodable, Sendable { let display: StaffVenueDisplay }
        struct Response: Decodable, Sendable { let updateVenueDisplay: Payload }
        let input: [String: GraphQLValue] = ["id": .string(id), "groupId": groupID.map(GraphQLValue.string) ?? .null]
        let response = try await session.graphQL("""
            mutation StaffVenueDisplayAssign($input: VenueDisplayUpdateInput!) {
              updateVenueDisplay(input: $input) { display { \(Self.venueDisplayFields) } }
            }
            """, variables: ["input": .object(input)], as: Response.self)
        return response.updateVenueDisplay.display
    }
}
