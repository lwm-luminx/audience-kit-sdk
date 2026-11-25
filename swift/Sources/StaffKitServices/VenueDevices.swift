import Foundation
import AudienceCore

public struct VenueDevice: Decodable, Sendable, Identifiable {
    public let id: String
    public let label: String
    public let permissions: [String]
    public let codeExpiresAt: String
    public let expiresAt: String
    public let redeemedAt: String?
    public let revokedAt: String?
}
public struct VenueDeviceCode: Decodable, Sendable { public let code: String; public let grant: VenueDevice }
/// What the door should do with a scan: a pass's outcome (ADMIT, RE_ENTRY, NOT_PAID…), or for an ID scanned through
/// `checkAtDoor` its outcome as ID_OK, ID_UNDER_AGE, ID_EXPIRED or ID_SUSPECT with the full answer in `idResult`.
public struct VenueScanResult: Decodable, Sendable {
    public let outcome: String
    public let message: String
    public var idResult: DoorIDResult? = nil
    /// An ID checked on the phone alone because the API couldn't be reached: nothing was logged.
    public var onDevice: DoorIDOnDevice? = nil
    /// Let them in: a paid pass, or an ID that shows they're old enough.
    public var admitted: Bool { ["ADMIT", "RE_ENTRY", "ID_OK"].contains(outcome) }
    public init(outcome: String, message: String, idResult: DoorIDResult? = nil, onDevice: DoorIDOnDevice? = nil) {
        self.outcome = outcome; self.message = message; self.idResult = idResult; self.onDevice = onDevice
    }
    private enum CodingKeys: String, CodingKey { case outcome, message }
}

extension VenueManagementClient {
    static let deviceFields = "id label permissions codeExpiresAt expiresAt redeemedAt revokedAt"
    public func devices(venueID: String) async throws -> [VenueDevice] {
        struct Response: Decodable, Sendable {
            struct Venues: Decodable, Sendable { let devices: GraphQLNodes<VenueDevice> }
            let venues: Venues
        }
        return try await session.graphQL("query VelvetDevices($id: ID!) { venues { devices(venueId: $id) { nodes { \(Self.deviceFields) } } } }",
                                       variables: ["id": .string(venueID)], as: Response.self).venues.devices.nodes
    }
    public func issueDevice(venueID: String, label: String, permissions: [String]) async throws -> VenueDeviceCode {
        struct Response: Decodable, Sendable { let issueVenueDevice: VenueDeviceCode }
        return try await session.graphQL("mutation VelvetDeviceIssue($input: VenueDeviceIssueInput!) { issueVenueDevice(input: $input) { code grant { \(Self.deviceFields) } } }",
            variables: ["input": .object(["venueId": .string(venueID), "label": .string(label), "permissions": .array(permissions.map(GraphQLValue.string))])], as: Response.self).issueVenueDevice
    }
    /// Approves a screen showing a pairing QR code (VenuePairing): `code` is what it shows or its pair link. The screen
    /// then signs in with these permissions, as if it had redeemed a device code.
    public func approvePairing(venueID: String, code: String, label: String, permissions: [String]) async throws -> VenueDevice {
        struct Response: Decodable, Sendable { struct Payload: Decodable, Sendable { let grant: VenueDevice }; let approveVenueDevicePairing: Payload }
        return try await session.graphQL("mutation VelvetPairingApprove($input: VenueDevicePairingApproveInput!) { approveVenueDevicePairing(input: $input) { grant { \(Self.deviceFields) } } }",
            variables: ["input": .object(["venueId": .string(venueID), "code": .string(code), "label": .string(label),
                                          "permissions": .array(permissions.map(GraphQLValue.string))])], as: Response.self).approveVenueDevicePairing.grant
    }
    public func revokeDevice(id: String) async throws {
        _ = try await session.graphQL("mutation VelvetDeviceRevoke($input: VenueDeviceRevokeInput!) { revokeVenueDevice(input: $input) { deletedId } }",
                                    variables: ["input": .object(["id": .string(id)])], as: GraphQLValue.self)
    }
    public func scanPass(venueID: String, code: String) async throws -> VenueScanResult {
        struct Response: Decodable, Sendable {
            struct Payload: Decodable, Sendable { let result: VenueScanResult }
            let scanAdmission: Payload
        }
        return try await session.graphQL("mutation VelvetScan($input: AdmissionScanInput!) { scanAdmission(input: $input) { result { outcome message } } }",
            variables: ["input": .object(["venueId": .string(venueID), "code": .string(code)])], as: Response.self).scanAdmission.result
    }
}

/// A sliding-scale cover's least and most, in cents: guests pay what they choose between them, starting at the cover's
/// suggested amount.
public struct VenueCoverScale: Sendable, Hashable {
    public let min: Int
    public let max: Int
    public init(min: Int, max: Int) { self.min = min; self.max = max }

    /// Whether `suggested` cents fits: the most above the least, and the suggested amount between them.
    public func fits(suggested: Int) -> Bool { max > min && (min...max).contains(suggested) }
}

public struct VenueCoverSettings: Decodable, Sendable {
    public struct Charge: Decodable, Sendable, Hashable {
        /// The cover the venue receives.
        public let amount: Money
        /// What the guest pays in the app, all in.
        public let total: Money
        public let payable: Bool
        /// The night it's for, "yyyy-MM-dd".
        public let night: String?
        /// When it starts and ends that night, a TimeOfDay (HH:MM, local); nil for all night.
        public let from: String?
        public let until: String?
        /// Whether the night's cover was changed from the usual one.
        public let override: Bool?
        /// Its sliding scale, when guests choose what to pay; ``amount`` is then the suggested amount.
        public let scale: Scale?

        public struct Scale: Decodable, Sendable, Hashable {
            public let min: Money
            public let max: Money
        }
    }
    /// The usual cover in cents; on a sliding scale, the suggested amount.
    public let coverCents: Int?
    /// The usual sliding scale's least and most, in cents; nil for a fixed cover. Nil from servers that predate it.
    public let coverMinCents: Int?
    public let coverMaxCents: Int?
    public let coverDays: [Int]
    public let coverTimeZone: String?
    public let coverFeePayer: String
    /// Whether guests can pay the cover in the app. When false it's paid at the door with no fees added, so
    /// coverFeePayer doesn't apply. Nil from servers that predate it.
    public let coverPayable: Bool?
    public let coverFrom: String?
    /// When the cover ends each night, as HH:MM; nil for close.
    public let coverUntil: String?
    public let coverCharge: Charge?
}

/// One cover at the door.
public struct VenueAdmission: Decodable, Sendable, Identifiable {
    public let id: String
    /// The cover.
    public let amount: Money
    /// What the guest paid, all in.
    public let total: Money
    public let status: String
    public let checkedInAt: String?
    public let scanCount: Int
    public let createdAt: String
    /// The guest: their name for the door, their picture so the door can match faces.
    public let profile: Profile
}

/// A venue's door for one night.
public struct VenueDoorNight: Decodable, Sendable {
    public let night: String
    public let paidCount: Int
    public let checkedInCount: Int
    /// Covers paid and not refunded, before fees.
    public let gross: Money
    /// Everyone through the door, read from the `admissions` connection's `nodes`.
    public let admissions: [VenueAdmission]
    public init(night: String, paidCount: Int, checkedInCount: Int, gross: Money, admissions: [VenueAdmission]) {
        self.night = night; self.paidCount = paidCount; self.checkedInCount = checkedInCount
        self.gross = gross; self.admissions = admissions
    }

    private enum CodingKeys: String, CodingKey { case night, paidCount, checkedInCount, gross, admissions }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        night = try container.decode(String.self, forKey: .night)
        paidCount = try container.decode(Int.self, forKey: .paidCount)
        checkedInCount = try container.decode(Int.self, forKey: .checkedInCount)
        gross = try container.decode(Money.self, forKey: .gross)
        admissions = try container.decode(GraphQLNodes<VenueAdmission>.self, forKey: .admissions).nodes
    }
}
extension VenueManagementClient {
    public func coverSettings(venueID: String) async throws -> VenueCoverSettings {
        struct Tickets: Decodable, Sendable { let cover: VenueCoverSettings? }
        struct Venue: Decodable, Sendable { let tickets: Tickets? }
        struct Venues: Decodable, Sendable { let venue: Venue? }
        struct Response: Decodable, Sendable { let venues: Venues }
        // The cover mixin's fields (inside tickets), aliased to the names VenueCoverSettings has always had.
        let response = try await session.graphQL("""
            query VelvetCover($id: ID!) {
              venues {
                venue(id: $id) {
                  tickets {
                    cover {
                      coverCents: cents coverMinCents: minCents coverMaxCents: maxCents
                      coverDays: days coverTimeZone: timeZone coverFeePayer: feePayer
                      coverPayable: payable coverFrom: from coverUntil: until coverCharge: charge { \(Self.chargeFields) }
                    }
                  }
                }
              }
            }
            """, variables: ["id": .string(venueID)], as: Response.self)
        guard let settings = response.venues.venue?.tickets?.cover else { throw AudienceKitError.notFound }
        return settings
    }
    /// The usual cover, `cents` in US dollars. `from` and `until` are HH:MM, blank for all night and until close, nil to
    /// leave as they are.
    /// Listing managers save it on the listing; venue devices through updateVenueCover. `scale` is a sliding scale's
    /// least and most in cents, with `cents` as the suggested amount: `.some(nil)` makes it a fixed cover, nil leaves
    /// it as it is.
    public func saveCover(venueID: String, cents: Int?, days: [Int], timeZone: String, feePayer: String,
                          from: String? = nil, until: String? = nil, scale: VenueCoverScale?? = nil,
                          device: Bool = false) async throws {
        if !device {
            var fields: [String: GraphQLValue] = [
                "coverCents": cents.map { .int($0) } ?? .null, "coverDays": .array(days.map { .int($0) }),
                "coverTimeZone": .string(timeZone), "coverFeePayer": .string(feePayer)
            ]
            if let scale {
                fields["coverMinCents"] = scale.map { .int($0.min) } ?? .null
                fields["coverMaxCents"] = scale.map { .int($0.max) } ?? .null
            }
            if let from { fields["coverFrom"] = from.isEmpty ? .null : .string(from) }
            if let until { fields["coverUntil"] = until.isEmpty ? .null : .string(until) }
            _ = try await session.graphQL("mutation VelvetCoverListing($input: VenueUpdateInput!) { updateVenue(input: $input) { venue { id } } }",
                variables: ["input": .object(["id": .string(venueID), "venue": .object(fields)])], as: GraphQLValue.self)
            return
        }
        var input: [String: GraphQLValue] = ["venueId": .string(venueID), "amount": cents.map { Money.usd($0).graphQLValue } ?? .null,
            "days": .array(days.map { .int($0) }), "timeZone": .string(timeZone), "feePayer": .string(feePayer)]
        if let from { input["from"] = from.isEmpty ? .null : .string(from) }
        if let until { input["until"] = until.isEmpty ? .null : .string(until) }
        if let scale {
            input["min"] = scale.map { Money.usd($0.min).graphQLValue } ?? .null
            input["max"] = scale.map { Money.usd($0.max).graphQLValue } ?? .null
        }
        _ = try await session.graphQL("mutation VelvetCoverUpdate($input: VenueCoverUpdateInput!) { updateVenueCover(input: $input) { venue { id } } }",
            variables: ["input": .object(input)], as: GraphQLValue.self)
    }
}

extension VenueManagementClient {
    static let moneyFields = "cents currency"
    static let admissionFields = "id amount { \(moneyFields) } total { \(moneyFields) } status checkedInAt scanCount createdAt profile { id name avatarUrl }"
    /// The door for a night, tonight by default (the venue's nights start at 6 AM). Nil without door access.
    public func door(venueID: String, night: String? = nil) async throws -> VenueDoorNight? {
        struct Response: Decodable, Sendable {
            struct Cover: Decodable, Sendable { let door: VenueDoorNight? }
            struct Tickets: Decodable, Sendable { let cover: Cover? }
            struct Venue: Decodable, Sendable { let tickets: Tickets? }
            struct Venues: Decodable, Sendable { let venue: Venue? }
            let venues: Venues
        }
        return try await session.graphQL("""
            query VelvetDoor($id: ID!, $night: ISO8601Date) {
              venues {
                venue(id: $id) {
                  tickets { cover { door(night: $night) { night paidCount checkedInCount gross { \(Self.moneyFields) } admissions { nodes { \(Self.admissionFields) } } } } }
                }
              }
            }
            """, variables: ["id": .string(venueID), "night": night.map(GraphQLValue.string) ?? .null], as: Response.self).venues.venue?.tickets?.cover?.door
    }
    /// Refunds a paid cover; its pass stops working.
    public func refundAdmission(id: String) async throws -> VenueAdmission {
        struct Response: Decodable, Sendable {
            struct Payload: Decodable, Sendable { let admission: VenueAdmission }
            let refundAdmission: Payload
        }
        return try await session.graphQL("mutation VelvetRefund($input: AdmissionRefundInput!) { refundAdmission(input: $input) { admission { \(Self.admissionFields) } } }",
            variables: ["input": .object(["admissionId": .string(id)])], as: Response.self).refundAdmission.admission
    }
}
