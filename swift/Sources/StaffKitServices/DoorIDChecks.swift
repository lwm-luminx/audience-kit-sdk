import Foundation
import AudienceCore

/// What the venue's door must do with IDs where it is (the API's `Venue.idCheckPolicy`, api doc DOOR_ID_CHECKS.md).
/// In Utah a bar scans every ID and its log keeps each check for seven days; nothing is reported to the state.
public struct DoorIDPolicy: Decodable, Sendable, Hashable {
    /// The state or province, e.g. "UT"; nil when unknown.
    public let jurisdiction: String?
    /// EVERYONE, APPEARS_35_OR_UNDER or OPTIONAL.
    public let scan: String
    public let retentionHours: Int
    public let drinkingAge: Int
    /// What to look for on the card that a scanner can't read, e.g. Utah's NO ALCOHOL SALE.
    public let visualCheck: String?
    public let citation: String?
    public let summary: String

    public var scansEveryone: Bool { scan == "EVERYONE" }
    static let fields = "jurisdiction scan retentionHours drinkingAge visualCheck citation summary"
}

/// One ID the door checked, as its log keeps it until `expiresAt`.
public struct DoorIDCheck: Decodable, Sendable, Hashable, Identifiable {
    public let id: String
    /// SCAN or MANUAL.
    public let entry: String
    /// DRIVERS_LICENSE, ID_CARD, PASSPORT, MILITARY or OTHER.
    public let documentKind: String
    /// OK, UNDER_AGE, EXPIRED or SUSPECT.
    public let outcome: String
    public let name: String?
    public let age: Int?
    public let birthDate: String?
    public let expiresOn: String?
    public let gender: String?
    public let issuer: String?
    /// Kept only for IDs typed in by hand.
    public let idNumber: String?
    public let noAlcoholSale: Bool
    public let checkedAt: String
    public let expiresAt: String

    public var admitted: Bool { outcome == "OK" }
    static let fields = "id entry documentKind outcome name age birthDate expiresOn gender issuer idNumber noAlcoholSale checkedAt expiresAt"
}

/// The answer to an ID checked at the door.
public struct DoorIDResult: Decodable, Sendable {
    /// Nil when what was scanned isn't an ID's barcode (nothing was logged).
    public let idCheck: DoorIDCheck?
    /// OK, UNDER_AGE, EXPIRED or SUSPECT; nil when not an ID.
    public let outcome: String?
    public let message: String
    /// The ID number, to show now; a scanned one isn't kept.
    public let idNumber: String?
    /// Why the barcode looks fake, when it does.
    public let problems: [String]
    public let policy: DoorIDPolicy

    static let fields = "outcome message idNumber problems policy { \(DoorIDPolicy.fields) } idCheck { \(DoorIDCheck.fields) }"
}

/// The door's ID log: every check still kept, newest first, and the same as CSV for law enforcement.
public struct DoorIDLog: Decodable, Sendable {
    public let checks: [DoorIDCheck]
    public let csv: String
}

/// An ID typed in because it couldn't be scanned (a passport, a foreign licence, a worn barcode).
public struct DoorIDEntry: Sendable, Hashable {
    public var documentKind: String
    public var name: String
    /// yyyy-MM-dd.
    public var birthDate: String
    /// yyyy-MM-dd.
    public var expiresOn: String
    public var idNumber: String
    public var issuer: String?
    public var suspect: Bool

    public init(documentKind: String = "PASSPORT", name: String = "", birthDate: String = "", expiresOn: String = "",
                idNumber: String = "", issuer: String? = nil, suspect: Bool = false) {
        self.documentKind = documentKind; self.name = name; self.birthDate = birthDate; self.expiresOn = expiresOn
        self.idNumber = idNumber; self.issuer = issuer; self.suspect = suspect
    }
}

public enum DoorID {
    /// Whether a scanned code is a licence barcode (PDF417, AAMVA) rather than a pass: the door sends those to the ID
    /// check instead.
    public static func isLicence(_ code: String) -> Bool {
        let head = code.prefix(40)
        return head.contains("ANSI ") || head.contains("AAMVA") || code.contains("ANSI 636")
    }

    /// Whether a request failed because the phone couldn't reach the API (no signal, no Wi-Fi), rather than an answer.
    public static func isOffline(_ error: Error) -> Bool {
        guard let failure = (error as? URLError) ?? (error as? AudienceKitError)?.underlying else { return false }
        return [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost, .cannotFindHost,
         .dnsLookupFailed, .dataNotAllowed, .internationalRoamingOff].contains(failure.code)
    }
}

extension VenueManagementClient {
    /// Checks whatever the door scanned: a licence barcode goes to the ID check (and its log), anything else is a pass.
    /// Both answer as a `VenueScanResult`, so one scanner serves both; an ID's answer carries `idCheck`.
    ///
    /// The phone reads the licence first and sends only the fields a door may use (`AAMVABarcode.minimized`): the
    /// address and the rest of the card never leave it. When the API can't be reached, the phone answers on its own
    /// (`onDevice`, with `drinkingAge`) and nothing is logged.
    public func checkAtDoor(venueID: String, code: String, drinkingAge: Int = 21) async throws -> VenueScanResult {
        guard DoorID.isLicence(code) else { return try await scanPass(venueID: venueID, code: code) }
        do {
            let result = try await scanID(venueID: venueID, barcode: AAMVABarcode.minimized(code))
            return VenueScanResult(outcome: result.outcome.map { "ID_\($0)" } ?? "UNREADABLE", message: result.message, idResult: result)
        } catch where DoorID.isOffline(error) {
            guard let local = DoorIDOnDevice(barcode: code, drinkingAge: drinkingAge) else { throw error }
            return VenueScanResult(outcome: "ID_\(local.outcome)", message: local.message, onDevice: local)
        }
    }

    /// Checks an ID from the barcode on its back, as the camera or a scanner read it (control characters included).
    public func scanID(venueID: String, barcode: String) async throws -> DoorIDResult {
        struct Response: Decodable, Sendable {
            struct Payload: Decodable, Sendable { let result: DoorIDResult }
            let scanId: Payload
        }
        return try await session.graphQL("mutation DoorScanID($input: IdCheckScanInput!) { scanId(input: $input) { result { \(DoorIDResult.fields) } } }",
            variables: ["input": .object(["venueId": .string(venueID), "barcode": .string(barcode)])], as: Response.self).scanId.result
    }

    /// Logs an ID the door typed in by hand.
    public func recordID(venueID: String, entry: DoorIDEntry) async throws -> DoorIDResult {
        struct Response: Decodable, Sendable {
            struct Payload: Decodable, Sendable { let result: DoorIDResult }
            let recordIdCheck: Payload
        }
        var input: [String: GraphQLValue] = ["venueId": .string(venueID), "documentKind": .string(entry.documentKind),
            "name": .string(entry.name), "birthDate": .string(entry.birthDate), "expiresOn": .string(entry.expiresOn),
            "idNumber": .string(entry.idNumber), "suspect": .bool(entry.suspect)]
        if let issuer = entry.issuer, !issuer.isEmpty { input["issuer"] = .string(issuer) }
        return try await session.graphQL("mutation DoorRecordID($input: IdCheckRecordInput!) { recordIdCheck(input: $input) { result { \(DoorIDResult.fields) } } }",
            variables: ["input": .object(input)], as: Response.self).recordIdCheck.result
    }

    /// Marks a check after looking at the card: NO ALCOHOL SALE on it (they may come in but not drink), or fake on sight.
    public func markID(id: String, noAlcoholSale: Bool? = nil, suspect: Bool? = nil) async throws -> DoorIDCheck {
        struct Response: Decodable, Sendable {
            struct Payload: Decodable, Sendable { let idCheck: DoorIDCheck }
            let markIdCheck: Payload
        }
        var input: [String: GraphQLValue] = ["id": .string(id)]
        if let noAlcoholSale { input["noAlcoholSale"] = .bool(noAlcoholSale) }
        if let suspect { input["suspect"] = .bool(suspect) }
        return try await session.graphQL("mutation DoorMarkID($input: IdCheckMarkInput!) { markIdCheck(input: $input) { idCheck { \(DoorIDCheck.fields) } } }",
            variables: ["input": .object(input)], as: Response.self).markIdCheck.idCheck
    }

    /// The venue's ID rules and its log as it stands. Nil when the API predates door ID checks.
    public func idLog(venueID: String) async throws -> (policy: DoorIDPolicy?, log: DoorIDLog?) {
        struct Response: Decodable, Sendable {
            struct Venue: Decodable, Sendable { let idCheckPolicy: DoorIDPolicy?; let idChecks: DoorIDLog? }
            let node: Venue?
        }
        let venue = try await session.graphQL("query DoorIDLog($id: ID!) { node(id: $id) { ... on Venue { idCheckPolicy { \(DoorIDPolicy.fields) } idChecks { checks { \(DoorIDCheck.fields) } csv } } } }",
            variables: ["id": .string(venueID)], as: Response.self).node
        return (venue?.idCheckPolicy, venue?.idChecks)
    }
}
