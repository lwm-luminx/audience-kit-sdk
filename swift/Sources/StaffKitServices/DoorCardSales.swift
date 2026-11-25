import Foundation
import StaffKitCore

/// The answer to selling a walk-in's cover on a card reader (``VenueManagementClient/chargeCoverAtDoor(venueID:arqc:quantity:amount:readerSerial:readerModel:)``).
public struct DoorCardSale: Decodable, Sendable {
    /// The walk-in pass the sale made: paid and checked in when approved, failed when declined.
    public struct Pass: Decodable, Sendable {
        public let id: String
        /// PAID, FAILED, …
        public let status: String
        public let quantity: Int
        public let total: Money
    }

    /// Whether the card was approved.
    public let approved: Bool
    /// What to show the door, e.g. "Approved · 2 covers, $20.00" or "Declined · Insufficient funds".
    public let message: String
    public let admission: Pass
}

extension VenueManagementClient {
    /// Sells tonight's cover to a walk-in on the venue's MagTek account: `arqc` is the encrypted card data (hex) the
    /// MagTek reader, or Tap to Pay on iPhone, produced for the total. Approved, the pass is paid and checked in at
    /// once; declined, `approved` is false and `message` says why (read the card again to retry). No fee is added.
    /// `amount` is each cover's amount on a sliding scale; nil charges the suggested one.
    public func chargeCoverAtDoor(venueID: String, arqc: String, quantity: Int = 1, amount: Money? = nil,
                                  readerSerial: String? = nil, readerModel: String? = nil) async throws -> DoorCardSale {
        var input: [String: GraphQLValue] = ["venueId": .string(venueID), "arqc": .string(arqc), "quantity": .int(quantity)]
        if let amount { input["amount"] = amount.graphQLValue }
        if let readerSerial { input["readerSerial"] = .string(readerSerial) }
        if let readerModel { input["readerModel"] = .string(readerModel) }
        struct Response: Decodable, Sendable { let chargeCoverAtDoor: DoorCardSale }
        return try await session.graphQL("""
            mutation DoorChargeCover($input: CoverDoorChargeInput!) {
              chargeCoverAtDoor(input: $input) { approved message admission { id status quantity total { cents currency } } }
            }
            """, variables: ["input": .object(input)], as: Response.self).chargeCoverAtDoor
    }

    /// The token that activates Tap to Pay on iPhone at the venue's door (`PaymentCardReader(token:)` in Apple's
    /// ProximityReader framework), signed by Magensa for the venue's MagTek account. `readerIdentifier` is computed
    /// from `PaymentCardReader.readerIdentifier`. Ask again when ProximityReader says the token expired.
    public func tapToPayToken(venueID: String, readerIdentifier: String) async throws -> String {
        struct Payload: Decodable, Sendable { let token: String }
        struct Response: Decodable, Sendable { let startTapToPay: Payload }
        return try await session.graphQL("""
            mutation DoorTapToPayToken($input: TapToPayReaderTokenInput!) { startTapToPay(input: $input) { token } }
            """, variables: ["input": .object(["venueId": .string(venueID), "readerIdentifier": .string(readerIdentifier)])],
            as: Response.self).startTapToPay.token
    }
}
