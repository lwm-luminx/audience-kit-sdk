import Foundation
import AudienceCore
import StaffKitCore

/// A guest's "I feel unsafe" alert at a venue, as staff see it (audience-kit api/doc/SAFETY_ALERTS.md): every device
/// on shift hears it, one picks it up ("I'm on it"), they talk in a private thread, and whoever closes it says how it
/// went. Only staff see who sent it.
public struct StaffSafetyAlert: Decodable, Sendable, Identifiable, Hashable {
    public struct Message: Decodable, Sendable, Identifiable, Hashable {
        public let id: String
        public let body: String
        /// Staff sent it; otherwise the guest did.
        public let fromStaff: Bool
        /// The guest's name, or the staff member's first name.
        public let senderName: String
        public let createdAt: String
        /// A community resource staff or a responder shared (shareSafetyAlertResource); the body says the same in
        /// text. Nil from an API before resource sharing, and in Velvet's reads, which don't ask for it.
        public let resource: SharedResource?
    }

    /// A community resource shared in the thread: a shelter, food, a clinic. `sensitive` ones (a DV service) must
    /// never be kept anywhere that shows they were opened.
    public struct SharedResource: Decodable, Sendable, Identifiable, Hashable {
        public let id: String
        public let title: String
        public let phone: String?
        public let textNumber: String?
        public let address: String?
        public let url: String?
        public let intakeNote: String?
        public let sensitive: Bool
    }

    /// Where it was sent, for a responder's list across venues, with its locale (for the resources to share).
    public struct VenueRef: Decodable, Sendable, Hashable {
        public struct LocaleRef: Decodable, Sendable, Hashable {
            public let id: String
            public let name: String?
        }
        public let id: String
        public let name: String?
        public let locale: LocaleRef?
    }

    public struct Reporter: Decodable, Sendable, Hashable {
        public let id: String
        public let name: String
        public let avatarUrl: String?
    }

    public struct EventRef: Decodable, Sendable, Hashable {
        public let id: String
        public let name: String?
    }

    public let id: String
    /// OPEN, ACKNOWLEDGED, CLOSED or CANCELLED.
    public let state: String
    /// BAR, DANCE_FLOOR, RESTROOMS, PATIO, STAGE, ENTRANCE or UNSURE; nil when they didn't say.
    public let place: String?
    public let concerns: [String]
    public let description: String?
    /// One line: where, then what ("Dance floor · Someone's bothering them").
    public let summary: String
    /// Whether anyone on shift has opened it.
    public let seen: Bool
    /// Whether this device or session has opened it.
    public let seenByMe: Bool
    public let acknowledgedByName: String?
    public let acknowledgedAt: String?
    /// When the managers heard it too: nobody picked it up in time, or the guest sent it again.
    public let escalatedAt: String?
    public let remindedAt: String?
    public let closedAt: String?
    /// How staff closed it: SORTED, REMOVED_SOMEONE, NOT_FOUND, NOT_NEEDED, SEEMS_OFF or MISUSE (asks the
    /// audience's team to block the sender; nobody is blocked until the team decides).
    public let outcome: String?
    public let staffNote: String?
    public let supportSharedAt: String?
    public let supportNote: String?
    public let createdAt: String
    public let reporter: Reporter?
    public let event: EventRef?
    public let messages: [Message]
    /// Where it was sent; asked for only in a responder's reads (`SafetyResponderClient`).
    public let venue: VenueRef?
    /// A safety responder picked it up, not the venue's staff; nil from an API before responders.
    public let acknowledgedByResponder: Bool?

    /// Still waiting for someone, or picked up and not closed: what the pinned card shows.
    public var isActive: Bool { state == "OPEN" || state == "ACKNOWLEDGED" }
    public var isOpen: Bool { state == "OPEN" }

    /// "Dance floor", for a place the API names.
    public static func placeTitle(_ place: String) -> String {
        switch place {
        case "BAR": "Bar"
        case "DANCE_FLOOR": "Dance floor"
        case "RESTROOMS": "Restrooms"
        case "PATIO": "Patio"
        case "STAGE": "Near the stage"
        case "ENTRANCE": "Entrance"
        case "UNSURE": "Not sure where"
        default: place.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    /// What's going on, as staff read it ("Someone's bothering them").
    public static func concernTitle(_ concern: String) -> String {
        switch concern {
        case "BOTHERING": "Someone’s bothering them"
        case "FOLLOWING": "Someone’s following them"
        case "INTOXICATED": "Someone’s had too much"
        case "UNWELL": "They don’t feel well"
        case "OTHER": "Something else"
        default: concern.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    /// How it can be closed, in the order the close sheet offers them.
    public static let outcomes: [(value: String, title: String)] = [
        ("SORTED", "Sorted, they're OK"),
        ("REMOVED_SOMEONE", "Someone was asked to leave"),
        ("NOT_FOUND", "Couldn't find them"),
        ("NOT_NEEDED", "They no longer needed help"),
        ("SEEMS_OFF", "Something seems off"),
        ("MISUSE", "Misusing alerts, ask to block"),
    ]
}

/// Whether this device hears a venue's safety alerts, and the first name guests see when it picks one up.
public struct SafetyShift: Decodable, Sendable, Hashable {
    /// Whether the shift is switched on. A geofenced shift hears alerts only while the device is inside (`hearing`).
    public let onShift: Bool
    /// Nil uses the account's first name, or the venue's name on a Velvet device.
    public let staffName: String?
    /// Hears alerts only while this device reports being inside the venue.
    public let geofenced: Bool
    /// Whether it hears alerts right now.
    public let hearing: Bool
    /// Whether the last report (in the last 12 hours) put the device inside; nil without one.
    public let inside: Bool?

    public init(onShift: Bool, staffName: String?, geofenced: Bool = false, hearing: Bool? = nil, inside: Bool? = nil) {
        self.onShift = onShift; self.staffName = staffName; self.geofenced = geofenced
        self.hearing = hearing ?? (onShift && (!geofenced || inside == true)); self.inside = inside
    }

    /// Always, when at the venue, or never.
    public var mode: SafetyAlertMode { SafetyAlertMode(onShift: onShift, geofenced: geofenced) }

    private enum CodingKeys: String, CodingKey { case onShift, staffName, geofenced, hearing, inside }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(onShift: try container.decode(Bool.self, forKey: .onShift),
                  staffName: try container.decodeIfPresent(String.self, forKey: .staffName),
                  geofenced: try container.decodeIfPresent(Bool.self, forKey: .geofenced) ?? false,
                  hearing: try container.decodeIfPresent(Bool.self, forKey: .hearing),
                  inside: try container.decodeIfPresent(Bool.self, forKey: .inside))
    }
}

/// The three choices staff make for a venue's safety alerts. They map onto a shift's `onShift` and `geofenced`:
/// Always is on and not geofenced, "When I'm at the venue" is on and geofenced, Never is off.
public enum SafetyAlertMode: String, CaseIterable, Sendable, Hashable, Identifiable {
    case always, atVenue, never

    public var id: String { rawValue }
    public var onShift: Bool { self != .never }
    /// Whether Velvet watches the venue's fence for this choice.
    public var geofenced: Bool { self == .atVenue }

    public init(onShift: Bool, geofenced: Bool) {
        self = !onShift ? .never : geofenced ? .atVenue : .always
    }

    /// The picker's label, e.g. "When I'm at Club Blue".
    public func title(venueName: String?) -> String {
        switch self {
        case .always: "Always"
        case .atVenue: "When I’m at \(venueName ?? "the venue")"
        case .never: "Never"
        }
    }

    /// What the choice does, under the picker.
    public func explanation(venueName: String?) -> String {
        let place = venueName ?? "the venue"
        return switch self {
        case .always: "This device hears \(place)’s safety alerts wherever it is."
        case .atVenue: "This device goes on shift when it arrives at \(place) and off when it leaves, even with Velvet closed."
        case .never: "This device won’t hear guests at \(place) who feel unsafe."
        }
    }
}

/// The circle a venue places people in (its point and distance tolerance), which a geofenced safety shift watches.
public struct VenueFence: Codable, Sendable, Hashable {
    public let venueID: String
    public let latitude: Double
    public let longitude: Double
    /// Meters.
    public let radius: Double

    public init(venueID: String, latitude: Double, longitude: Double, radius: Double) {
        self.venueID = venueID; self.latitude = latitude; self.longitude = longitude; self.radius = radius
    }
}

extension VenueManagementClient {
    static let safetyShiftFields = "onShift staffName geofenced hearing inside"
    static let safetyAlertFields = """
        id state place concerns description summary seen seenByMe acknowledgedByName acknowledgedAt escalatedAt \
        remindedAt closedAt outcome staffNote supportSharedAt supportNote createdAt reporter { id name avatarUrl } \
        event { id name } messages { id body fromStaff senderName createdAt }
        """

    /// The venue's alerts, newest first: the ones still open or picked up, and the ones closed in the last 12 hours.
    public func safetyAlerts(venueID: String) async throws -> [StaffSafetyAlert] {
        struct Response: Decodable, Sendable {
            struct Venue: Decodable, Sendable { let safetyAlerts: [StaffSafetyAlert] }
            struct Venues: Decodable, Sendable { let venue: Venue? }
            let venues: Venues
        }
        return try await session.graphQL("query VelvetSafetyAlerts($id: ID!) { venues { venue(id: $id) { safetyAlerts { \(Self.safetyAlertFields) } } } }",
                                         variables: ["id": .string(venueID)], as: Response.self).venues.venue?.safetyAlerts ?? []
    }

    /// Whether this device is on shift for the venue's alerts; nil when it can't hear them.
    public func safetyShift(venueID: String) async throws -> SafetyShift? {
        struct Response: Decodable, Sendable {
            struct Venue: Decodable, Sendable { let safetyShift: SafetyShift? }
            struct Venues: Decodable, Sendable { let venue: Venue? }
            let venues: Venues
        }
        return try await session.graphQL("query VelvetSafetyShift($id: ID!) { venues { venue(id: $id) { safetyShift { \(Self.safetyShiftFields) } } } }",
                                         variables: ["id": .string(venueID)], as: Response.self).venues.venue?.safetyShift
    }

    /// The venue's fence for a geofenced shift; nil when it has no point.
    public func venueFence(venueID: String) async throws -> VenueFence? {
        struct Response: Decodable, Sendable {
            struct Venue: Decodable, Sendable { let point: String?; let distanceTolerance: Int }
            struct Venues: Decodable, Sendable { let venue: Venue? }
            let venues: Venues
        }
        let venue = try await session.graphQL("query VelvetVenueFence($id: ID!) { venues { venue(id: $id) { point distanceTolerance } } }",
                                              variables: ["id": .string(venueID)], as: Response.self).venues.venue
        guard let venue, let coordinate = wktCoordinate(venue.point) else { return nil }
        return VenueFence(venueID: venueID, latitude: coordinate.latitude, longitude: coordinate.longitude,
                          radius: Double(venue.distanceTolerance))
    }

    /// Tells the API this device crossed into or out of the venue, for a geofenced shift. A location, when sent, lets
    /// the API overrule an "inside" that's really outside.
    @discardableResult
    public func reportSafetyShiftPresence(venueID: String, inside: Bool, latitude: Double? = nil, longitude: Double? = nil,
                                          accuracy: Double? = nil) async throws -> SafetyShift? {
        struct Response: Decodable, Sendable {
            struct Venue: Decodable, Sendable { let safetyShift: SafetyShift? }
            struct Payload: Decodable, Sendable { let venue: Venue? }
            let reportSafetyShiftPresence: Payload?
        }
        var input: [String: GraphQLValue] = ["venueId": .string(venueID), "inside": .bool(inside)]
        if let latitude, let longitude { input["latitude"] = .double(latitude); input["longitude"] = .double(longitude) }
        if let accuracy { input["accuracy"] = .double(accuracy) }
        return try await session.graphQL("mutation VelvetReportSafetyShiftPresence($input: SafetyShiftPresenceReportInput!) { reportSafetyShiftPresence(input: $input) { venue { safetyShift { \(Self.safetyShiftFields) } } } }",
                                         variables: ["input": .object(input)], as: Response.self).reportSafetyShiftPresence?.venue?.safetyShift
    }

    /// Goes on or off shift for the venue's alerts, and sets the first name guests see ("" to clear it) and whether the
    /// shift follows the venue's geofence (nil keeps it).
    @discardableResult
    public func setSafetyShift(venueID: String, onShift: Bool, staffName: String?, geofenced: Bool? = nil) async throws -> SafetyShift? {
        struct Response: Decodable, Sendable {
            struct Venue: Decodable, Sendable { let safetyShift: SafetyShift? }
            struct Payload: Decodable, Sendable { let venue: Venue? }
            let setSafetyShift: Payload?
        }
        var input: [String: GraphQLValue] = ["venueId": .string(venueID), "onShift": .bool(onShift)]
        if let staffName { input["staffName"] = .string(staffName) }
        if let geofenced { input["geofenced"] = .bool(geofenced) }
        return try await session.graphQL("mutation VelvetSetSafetyShift($input: SafetyShiftSetInput!) { setSafetyShift(input: $input) { venue { safetyShift { \(Self.safetyShiftFields) } } } }",
                                         variables: ["input": .object(input)], as: Response.self).setSafetyShift?.venue?.safetyShift
    }

    /// Records that this device opened the alert, so the guest sees "Seen by staff".
    @discardableResult
    public func seeSafetyAlert(id: String) async throws -> StaffSafetyAlert {
        try await safetyAlertMutation("seeSafetyAlert", "mutation VelvetSeeSafetyAlert($input: SafetyAlertSeeInput!) { seeSafetyAlert(input: $input) { safetyAlert { \(Self.safetyAlertFields) } } }", ["id": .string(id)])
    }

    /// "I'm on it": the guest is told `staffName` (or the shift's name) is on the way.
    @discardableResult
    public func acknowledgeSafetyAlert(id: String, staffName: String? = nil) async throws -> StaffSafetyAlert {
        var input: [String: GraphQLValue] = ["id": .string(id)]
        if let staffName, !staffName.isEmpty { input["staffName"] = .string(staffName) }
        return try await safetyAlertMutation("acknowledgeSafetyAlert", "mutation VelvetAcknowledgeSafetyAlert($input: SafetyAlertAcknowledgeInput!) { acknowledgeSafetyAlert(input: $input) { safetyAlert { \(Self.safetyAlertFields) } } }", input)
    }

    /// Sends a message to the guest in the alert's private thread.
    @discardableResult
    public func sendSafetyAlertMessage(id: String, body: String) async throws -> StaffSafetyAlert {
        try await safetyAlertMutation("sendSafetyAlertMessage", "mutation VelvetSendSafetyAlertMessage($input: SafetyAlertMessageSendInput!) { sendSafetyAlertMessage(input: $input) { safetyAlert { \(Self.safetyAlertFields) } } }",
                                      ["id": .string(id), "body": .string(body)])
    }

    /// Shares "Need support?" with the guest, with a note if you like.
    @discardableResult
    public func shareSafetyAlertSupport(id: String, note: String?) async throws -> StaffSafetyAlert {
        var input: [String: GraphQLValue] = ["id": .string(id)]
        if let note, !note.isEmpty { input["note"] = .string(note) }
        return try await safetyAlertMutation("shareSafetyAlertSupport", "mutation VelvetShareSafetyAlertSupport($input: SafetyAlertSupportShareInput!) { shareSafetyAlertSupport(input: $input) { safetyAlert { \(Self.safetyAlertFields) } } }", input)
    }

    /// Closes the alert with how it went; the guest only hears that it's closed.
    @discardableResult
    public func closeSafetyAlert(id: String, outcome: String, note: String?) async throws -> StaffSafetyAlert {
        var input: [String: GraphQLValue] = ["id": .string(id), "outcome": .string(outcome)]
        if let note, !note.isEmpty { input["note"] = .string(note) }
        return try await safetyAlertMutation("closeSafetyAlert", "mutation VelvetCloseSafetyAlert($input: SafetyAlertCloseInput!) { closeSafetyAlert(input: $input) { safetyAlert { \(Self.safetyAlertFields) } } }", input)
    }

    private struct SafetyAlertPayload: Decodable, Sendable { let safetyAlert: StaffSafetyAlert? }

    /// Runs one of the alert mutations, each named `name` and answering `{ safetyAlert }`.
    private func safetyAlertMutation(_ name: String, _ document: String, _ input: [String: GraphQLValue]) async throws -> StaffSafetyAlert {
        let response = try await session.graphQL(document, variables: ["input": .object(input)],
                                                 as: [String: SafetyAlertPayload?].self)
        guard let alert = response[name]??.safetyAlert else { throw SafetyAlertError.missing }
        return alert
    }
}

public enum SafetyAlertError: LocalizedError, Sendable {
    case missing
    public var errorDescription: String? { "That alert isn't available any more." }
}

/// A staff push about a safety alert (category `SAFETY_ALERT`, `data.kind = safety_alert`): tapping it opens the alert.
public struct SafetyAlertPush: Sendable, Hashable, Identifiable {
    public let alertID: String
    public let venueID: String
    public let audienceID: String?
    public var id: String { alertID }

    public init(alertID: String, venueID: String, audienceID: String? = nil) {
        self.alertID = alertID; self.venueID = venueID; self.audienceID = audienceID
    }

    public init?(userInfo: [AnyHashable: Any]) {
        func string(_ key: String) -> String? {
            if let value = userInfo[key] as? String, !value.isEmpty { return value }
            return (userInfo[key] as? Int).map(String.init)
        }
        guard string("kind") == "safety_alert", let alertID = string("alert_id"), let venueID = string("venue_id") else { return nil }
        self.init(alertID: alertID, venueID: venueID, audienceID: string("audience_id"))
    }
}
