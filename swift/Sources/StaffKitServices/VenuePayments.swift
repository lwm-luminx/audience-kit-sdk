import Foundation
import StaffKitCore

/// Which of a venue's payment accounts: production, or Square's sandbox that Next builds pay through.
public enum VenuePaymentEnvironment: String, Sendable, Codable {
    case production = "PRODUCTION"
    case sandbox = "SANDBOX"
}

/// The venue's own Stripe or Square account, which its cover is paid to. The venue is the seller.
public struct VenuePaymentAccount: Decodable, Sendable {
    public enum Provider: String, Decodable, Sendable { case stripe = "STRIPE", square = "SQUARE" }
    /// A Square location that can take cards.
    public struct SquareLocation: Decodable, Sendable, Identifiable, Hashable {
        public let id: String
        public let name: String?
        public let address: String?
    }

    public let provider: Provider
    /// active (taking payments), pending (Stripe is reviewing it), incomplete (Stripe onboarding isn't finished, or no
    /// Square location is picked) or disconnected.
    public let status: String
    public let chargesEnabled: Bool
    public let locationName: String?
    /// Square: the seller's locations, when Square answers.
    public let squareLocations: [SquareLocation]?

    public var isActive: Bool { status == "active" }
    /// Square is connected but hasn't been told which location gets paid.
    public var needsLocation: Bool { provider == .square && status == "incomplete" }
}

extension VenueManagementClient {
    /// The page on the API host that `app`'s Stripe or Square connection comes back to. It hands the outcome to the
    /// app as `<scheme>://payments/return?square=…` (or `stripe=…`), which a web authentication session can wait for.
    public func paymentsReturnURL(app: String) -> URL {
        var components = URLComponents(url: session.baseURL, resolvingAgainstBaseURL: false) ?? URLComponents()
        components.path = "/v1/payments/return/\(app)"
        components.query = nil
        return components.url ?? session.baseURL
    }

    private static let accountFields = "provider status chargesEnabled locationName squareLocations { id name address }"

    /// The venue's account in `environment`, or nil when it hasn't connected one.
    public func paymentAccount(venueID: String, environment: VenuePaymentEnvironment) async throws -> VenuePaymentAccount? {
        struct Cover: Decodable, Sendable { let paymentAccount: VenuePaymentAccount? }
        struct Tickets: Decodable, Sendable { let cover: Cover? }
        struct Venue: Decodable, Sendable { let tickets: Tickets? }
        struct Venues: Decodable, Sendable { let venue: Venue? }
        struct Response: Decodable, Sendable { let venues: Venues }
        let response = try await session.graphQL("""
            query VelvetPaymentAccount($id: ID!, $environment: PaymentEnvironment) {
              venues { venue(id: $id) { tickets { cover { paymentAccount(environment: $environment) { \(Self.accountFields) } } } } }
            }
            """, variables: ["id": .string(venueID), "environment": .string(environment.rawValue)], as: Response.self)
        return response.venues.venue?.tickets?.cover?.paymentAccount
    }

    /// Stripe's page for setting up the venue's account. Stripe sends the manager back to `returnTo` with
    /// `stripe=connected`, `pending` or `error`.
    public func connectStripe(venueID: String, returnTo: URL) async throws -> URL {
        struct Payload: Decodable, Sendable { let onboardingUrl: String }
        struct Response: Decodable, Sendable { let connectVenueStripe: Payload }
        let response = try await session.graphQL("""
            mutation VelvetConnectStripe($input: VenueStripeConnectInput!) { connectVenueStripe(input: $input) { onboardingUrl } }
            """, variables: ["input": .object(["venueId": .string(venueID), "returnTo": .string(returnTo.absoluteString)])],
            as: Response.self)
        guard let url = URL(string: response.connectVenueStripe.onboardingUrl) else { throw URLError(.badURL) }
        return url
    }

    /// Square's page for allowing payments. Square sends the manager back to `returnTo` with `square=connected`,
    /// `pick_location`, `declined` or `error`.
    public func connectSquare(venueID: String, returnTo: URL, environment: VenuePaymentEnvironment) async throws -> URL {
        struct Payload: Decodable, Sendable { let authorizeUrl: String }
        struct Response: Decodable, Sendable { let connectVenueSquare: Payload }
        let response = try await session.graphQL("""
            mutation VelvetConnectSquare($input: VenueSquareConnectInput!) { connectVenueSquare(input: $input) { authorizeUrl } }
            """, variables: ["input": .object(["venueId": .string(venueID), "returnTo": .string(returnTo.absoluteString),
                                               "environment": .string(environment.rawValue)])],
            as: Response.self)
        guard let url = URL(string: response.connectVenueSquare.authorizeUrl) else { throw URLError(.badURL) }
        return url
    }

    /// Picks which of the venue's Square locations its cover is paid to.
    public func setSquareLocation(venueID: String, locationID: String, environment: VenuePaymentEnvironment) async throws {
        _ = try await session.graphQL("""
            mutation VelvetSquareLocation($input: VenueSquareLocationSetInput!) { setVenueSquareLocation(input: $input) { venue { id } } }
            """, variables: ["input": .object(["venueId": .string(venueID), "locationId": .string(locationID),
                                               "environment": .string(environment.rawValue)])],
            as: GraphQLValue.self)
    }

    /// Stops the venue taking cover through its account in `environment`.
    public func disconnectPayments(venueID: String, environment: VenuePaymentEnvironment) async throws {
        _ = try await session.graphQL("""
            mutation VelvetDisconnectPayments($input: VenuePaymentsDisconnectInput!) { disconnectVenuePayments(input: $input) { venue { id } } }
            """, variables: ["input": .object(["venueId": .string(venueID), "environment": .string(environment.rawValue)])],
            as: GraphQLValue.self)
    }
}
