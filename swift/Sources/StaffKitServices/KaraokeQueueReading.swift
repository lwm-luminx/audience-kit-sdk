import AudienceCore
import StaffKitCore
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

extension VenueManagementClient {
    /// How often Velvet Display sends the same queue again: inside the three minutes the API keeps a report.
    public static let karaokeQueueInterval: Double = 60

    /// Reports the queue read off the karaoke app on this Mac (`reportKaraokeQueue`), for the board, Tonight and the
    /// apps. Only a venue device whose code has the music permission may, at a venue whose karaoke runs in KaraFun.
    /// Returns the queue as the API keeps it.
    @discardableResult
    public func reportKaraokeQueue(_ turns: [KaraokeQueueTurn], source: String) async throws -> [KaraokeQueueTurn] {
        struct Payload: Decodable, Sendable { let queue: [KaraokeQueueTurn]? }
        struct Response: Decodable, Sendable { let reportKaraokeQueue: Payload }
        let entries: [GraphQLValue] = turns.prefix(KaraokeQueueText.limit).map { turn in
            var fields: [String: GraphQLValue] = ["title": .string(turn.title)]
            if let singer = turn.singer { fields["singer"] = .string(singer) }
            if let artist = turn.artist { fields["artist"] = .string(artist) }
            return .object(fields)
        }
        let reply = try await session.graphQL("""
            mutation VelvetKaraokeQueue($entries: [KaraokeQueueEntryInput!]!, $source: String) {
              reportKaraokeQueue(input: { entries: $entries, source: $source }) { queue { singer title artist } }
            }
            """, variables: ["entries": .array(entries), "source": .string(source)], as: Response.self)
        return reply.reportKaraokeQueue.queue ?? []
    }
}

/// A venue's karaoke queue as the API keeps it (`Venue.karaoke.queue`): KaraFun's as Velvet Display last read it off
/// the Mac, or the chat's signups on an AudienceKit night. Nil turns: nothing to show (no karaoke tonight, or nobody's
/// read the queue in the last few minutes).
public struct VenueKaraokeQueue: Decodable, Sendable, Equatable {
    public let tonight: Bool
    public let providerName: String?
    public let queue: [KaraokeQueueTurn]?

    public init(tonight: Bool, providerName: String? = nil, queue: [KaraokeQueueTurn]? = nil) {
        self.tonight = tonight; self.providerName = providerName; self.queue = queue
    }

    /// The turns to put up: tonight's, when there are any.
    public var turns: [KaraokeQueueTurn] { tonight ? queue ?? [] : [] }
}

extension VenueManagementClient {
    /// How often the board looks at the karaoke queue again: Velvet Display reads KaraFun every 10 seconds.
    public static let karaokeQueueRefresh: Double = 20

    /// The venue's karaoke queue now, or nil when it has no karaoke.
    public func karaokeQueue(venueID: String) async throws -> VenueKaraokeQueue? {
        struct Venue: Decodable, Sendable { let karaoke: VenueKaraokeQueue? }
        struct Venues: Decodable, Sendable { let venue: Venue? }
        struct Response: Decodable, Sendable { let venues: Venues }
        return try await session.graphQL("""
            query VelvetKaraokeQueue($id: ID!) {
              venues { venue(id: $id) { karaoke { tonight providerName queue { singer title artist } } } }
            }
            """, variables: ["id": .string(venueID)], as: Response.self).venues.venue?.karaoke
    }
}
