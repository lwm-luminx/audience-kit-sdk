import Foundation
import AudienceCore

/// An amount of money as the API gives it (`Money`): whole `cents` of a `currency`, the currency as its lower-case
/// ISO 4217 code (`usd`). $10.00 is `Money(cents: 1000, currency: "usd")`.
public struct Money: Codable, Sendable, Hashable {
    /// The amount in the currency's minor unit (cents for dollars).
    public let cents: Int
    /// The currency's ISO 4217 code in lower case.
    public let currency: String

    public init(cents: Int, currency: String = "usd") {
        self.cents = cents
        self.currency = currency
    }

    /// Money in US dollars.
    public static func usd(_ cents: Int) -> Money { Money(cents: cents, currency: "usd") }

    /// The `MoneyInput` the API's mutations take.
    public var graphQLValue: GraphQLValue { .object(["cents": .int(cents), "currency": .string(currency)]) }
}
