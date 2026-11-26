//
//  ShowNightPlans.swift
//  Backstage's departure timeline (Rick 2026-11-26: "uses location + travel time + curtain time to build a timeline
//  backwards for departure"). The app reads where each coming appearance is and when the performer goes on
//  (`showNightDepartures()`), works out on the phone when to get ready and leave from where the phone is and the
//  travel time there, and hands the API only the resulting times (`setShowNightPlan`), so the show-night Live
//  Activity the API pushes keeps counting down to them. The phone's location never leaves it.
//

import AudienceCore
import Foundation
import StaffKitCore

/// Where one of the performer's coming appearances is, and when they go on.
public struct ShowNightDeparture: Sendable, Equatable {
    public let eventID: String
    /// The venue's point; nil while the venue is to be announced or has no location.
    public let latitude: Double?
    public let longitude: Double?
    /// The venue's full address, for directions.
    public let address: String?
    /// When they go on: their first spot on the lineup (its projected start as the night runs, else its set time),
    /// their own or a troupe's; nil when they're billed but not on its lineup yet (the event's start counts then).
    public let curtain: Date?
    /// Places is called this many minutes before their spot, when it has a curtain call.
    public let curtainCallMinutes: Int?

    public init(eventID: String, latitude: Double?, longitude: Double?, address: String?, curtain: Date?,
                curtainCallMinutes: Int?) {
        self.eventID = eventID
        self.latitude = latitude
        self.longitude = longitude
        self.address = address
        self.curtain = curtain
        self.curtainCallMinutes = curtainCallMinutes
    }
}

/// A departure timeline, worked out backwards from the curtain; any step can be unknown.
public struct ShowNightPlanTimes: Sendable, Equatable {
    public var readyBy: Date?
    public var leaveBy: Date?
    public var arriveBy: Date?
    public var curtain: Date?

    public init(readyBy: Date? = nil, leaveBy: Date? = nil, arriveBy: Date? = nil, curtain: Date? = nil) {
        self.readyBy = readyBy
        self.leaveBy = leaveBy
        self.arriveBy = arriveBy
        self.curtain = curtain
    }

    public var isEmpty: Bool { readyBy == nil && leaveBy == nil && arriveBy == nil && curtain == nil }
}

extension TalentManagementClient {
    /// Where each of their listings' coming appearances is and when they go on, by event ID. Kept out of
    /// `listings(isAdministrator:)` so the listings still load against an API without it.
    public func showNightDepartures() async throws -> [String: ShowNightDeparture] {
        struct Spot: Decodable, Sendable { let startsAt: String?; let projectedStartsAt: String?; let curtainCallMinutes: Int? }
        struct Location: Decodable, Sendable { let latitude: Double?; let longitude: Double?; let address: String? }
        struct Venue: Decodable, Sendable { let location: Location? }
        struct Place: Decodable, Sendable { let venue: Venue? }
        struct Event: Decodable, Sendable { let id: String; let venue: Place? }
        struct Edge: Decodable, Sendable { let appearances: [Spot]; let node: Event }
        struct Involvements: Decodable, Sendable { let edges: [Edge] }
        struct Events: Decodable, Sendable { let involvements: Involvements }
        struct Person: Decodable, Sendable { let events: Events }
        struct Listings: Decodable, Sendable { let people: [Person] }
        struct Me: Decodable, Sendable { let listings: Listings }
        struct Response: Decodable, Sendable { let me: Me? }
        let response = try await showNightGraphQL("""
            query BackstageDepartures {
              me { listings { people { events { involvements { edges {
                appearances { startsAt projectedStartsAt curtainCallMinutes }
                node { id venue { venue { location { latitude longitude address } } } }
              } } } } } }
            }
            """, variables: [:], as: Response.self)
        var departures: [String: ShowNightDeparture] = [:]
        for edge in response.me?.listings.people.flatMap(\.events.involvements.edges) ?? [] {
            let spot = edge.appearances.compactMap { spot -> (Date, Int?)? in
                guard let at = parseInstant(spot.projectedStartsAt) ?? parseInstant(spot.startsAt) else { return nil }
                return (at, spot.curtainCallMinutes)
            }.min { $0.0 < $1.0 }
            let location = edge.node.venue?.venue?.location
            let departure = ShowNightDeparture(eventID: edge.node.id, latitude: location?.latitude,
                                               longitude: location?.longitude, address: location?.address,
                                               curtain: spot?.0, curtainCallMinutes: spot?.1)
            // An event on two of their listings: the earlier spot is when they're needed.
            if let known = departures[edge.node.id], let mine = known.curtain,
               departure.curtain.map({ $0 >= mine }) ?? true { continue }
            departures[edge.node.id] = departure
        }
        return departures
    }

    /// Hands the API the departure timeline Backstage worked out for one appearance (only the times), so the
    /// show-night Live Activity it pushes shows them. Empty `times` clears it.
    public func setShowNightPlan(eventID: String, times: ShowNightPlanTimes) async throws {
        struct Payload: Decodable, Sendable { let saved: Bool }
        struct Response: Decodable, Sendable { let setShowNightPlan: Payload }
        var variables: [String: GraphQLValue] = ["eventId": .string(eventID)]
        let format = ISO8601DateFormatter()
        if let at = times.readyBy { variables["readyBy"] = .string(format.string(from: at)) }
        if let at = times.leaveBy { variables["leaveBy"] = .string(format.string(from: at)) }
        if let at = times.arriveBy { variables["arriveBy"] = .string(format.string(from: at)) }
        if let at = times.curtain { variables["curtainAt"] = .string(format.string(from: at)) }
        _ = try await showNightGraphQL("""
            mutation ShowNightPlanSet($eventId: ID!, $readyBy: ISO8601DateTime, $leaveBy: ISO8601DateTime, $arriveBy: ISO8601DateTime, $curtainAt: ISO8601DateTime) {
              setShowNightPlan(input: { eventId: $eventId, readyBy: $readyBy, leaveBy: $leaveBy, arriveBy: $arriveBy, curtainAt: $curtainAt }) { saved }
            }
            """, variables: variables, as: Response.self)
    }
}
