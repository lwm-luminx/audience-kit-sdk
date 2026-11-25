import Foundation
import AudienceCore
import StaffKitCore

/// The door's totals for the night, as every event on the feed carries them.
public struct VenueDoorTotals: Decodable, Sendable, Hashable {
    public let paidCount: Int
    public let checkedInCount: Int
    /// Covers paid and not refunded, before fees.
    public let gross: Money
    public init(paidCount: Int, checkedInCount: Int, gross: Money) {
        self.paidCount = paidCount; self.checkedInCount = checkedInCount; self.gross = gross
    }
}

/// What a door station hears from the API's `door` subscription.
public enum VenueDoorEvent: Sendable {
    /// The night as it stands (`DoorOpened`), sent on joining and again after a reconnect or when the night rolls
    /// over at 6 AM.
    case night(VenueDoorNight)
    /// One cover changed: `paid` when a guest paid, `admit` on their first scan, `re_entry` on later ones, `refund`.
    case admission(VenueAdmission, outcome: String, totals: VenueDoorTotals)
    /// The server turned the subscription away: no door access here. The feed ends.
    case rejected
    /// The socket dropped; the cable is reconnecting (`nil` reason) or gave up (the session ended).
    case offline(String?)
}

extension VenueDoorNight {
    /// This night with one cover replaced (or added at the top, newest first) and the totals the event came with.
    public func applying(_ admission: VenueAdmission, totals: VenueDoorTotals) -> VenueDoorNight {
        var rows = admissions
        if let index = rows.firstIndex(where: { $0.id == admission.id }) { rows[index] = admission }
        else { rows.insert(admission, at: 0) }
        return VenueDoorNight(night: night, paidCount: totals.paidCount, checkedInCount: totals.checkedInCount,
                              gross: totals.gross, admissions: rows)
    }
}

extension VenueManagementClient {
    /// The subscription a door station follows; every field is one a venue device with `door` may select.
    static let doorSubscription = """
        subscription StaffDoor($id: ID!) {
          door(venueId: $id) {
            __typename
            ... on DoorOpened { night { night paidCount checkedInCount gross { \(moneyFields) } admissions { nodes { \(admissionFields) } } } }
            ... on DoorAdmissionChanged { outcome admission { \(admissionFields) } paidCount checkedInCount gross { \(moneyFields) } }
          }
        }
        """

    /// Follows a venue's door live. Load the night with ``door(venueID:night:)`` first if the screen needs it before
    /// the socket is up; the feed's first `night` event then replaces it. Ending the iteration stops following.
    public func doorFeed(venueID: String) async -> AsyncStream<VenueDoorEvent> {
        let results = await session.subscribe(Self.doorSubscription, variables: ["id": .string(venueID)])
        return AsyncStream { continuation in
            let task = Task {
                for await result in results {
                    guard let event = Self.doorEvent(from: result) else { continue }
                    continuation.yield(event)
                    if case .rejected = event { break }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static func doorEvent(from event: AudienceCable.Event) -> VenueDoorEvent? {
        switch event {
        case .rejected: return .rejected
        case .disconnected(let reason, let reconnects): return .offline(reconnects ? nil : (reason ?? "Signed out"))
        case .result(let data): return doorEvent(from: data)
        default: return nil  // subscribed
        }
    }

    /// The door event one subscription result means, `rejected` for a refusal, or nil for an event of a kind this
    /// build doesn't know.
    static func doorEvent(from data: Data) -> VenueDoorEvent? {
        struct Event: Decodable {
            let __typename: String
            let night: VenueDoorNight?
            let outcome: String?
            let admission: VenueAdmission?
            let paidCount: Int?
            let checkedInCount: Int?
            let gross: Money?
        }
        struct Door: Decodable { let door: Event? }
        guard let result = try? JSONDecoder().decode(GraphQLSubscriptionResult<Door>.self, from: data) else { return nil }
        guard let event = result.data?.door else { return result.refused ? .rejected : nil }
        switch event.__typename {
        case "DoorOpened":
            return event.night.map(VenueDoorEvent.night)
        case "DoorAdmissionChanged":
            guard let admission = event.admission, let paid = event.paidCount, let checkedIn = event.checkedInCount,
                  let gross = event.gross else { return nil }
            // PAID, ADMIT, RE_ENTRY, REFUND → the station's paid, admit, re_entry, refund.
            return .admission(admission, outcome: (event.outcome ?? "").lowercased(),
                              totals: VenueDoorTotals(paidCount: paid, checkedInCount: checkedIn, gross: gross))
        default:
            return nil
        }
    }
}
