import Foundation
import StaffKitCore

/// Something that runs a staff GraphQL document: an audience's staffql (``AudienceManagementSession``) or the
/// audience-less endpoint a venue that signed itself up uses. Velvet's subscription calls work on either.
public protocol StaffGraphQLRunning: Sendable {
    func graphQL<Response: Decodable & Sendable>(_ query: String, variables: [String: GraphQLValue]?,
                                                 as type: Response.Type) async throws -> Response
}

extension AudienceManagementSession: StaffGraphQLRunning {}

/// The audience-less endpoint (`/v1/staffql`, with no audience), for a venue that signed itself up: the same session, signed in on the
/// platform with no audience chosen (``AudienceManagementSession/canUseOwnListings``).
public struct OwnListingsGraphQL: StaffGraphQLRunning {
    public let session: AudienceManagementSession
    public init(session: AudienceManagementSession) { self.session = session }

    public func graphQL<Response: Decodable & Sendable>(_ query: String, variables: [String: GraphQLValue]?,
                                                        as type: Response.Type) async throws -> Response {
        try await session.ownListingsGraphQL(query, variables: variables, as: type)
    }
}

/// Velvet's subscription for a venue that signed itself up outside any audience (the API's
/// doc/VELVET_SUBSCRIPTION.md). A venue an audience lists doesn't need one: `required` is false and it's `unlocked`.
public struct VenueVelvetSubscription: Decodable, Sendable, Equatable {
    public enum Status: String, Decodable, Sendable {
        case none = "NONE", trialing = "TRIALING", active = "ACTIVE", pastDue = "PAST_DUE", lapsed = "LAPSED"
        case canceled = "CANCELED"
    }
    public enum Source: String, Decodable, Sendable { case stripe = "STRIPE", appStore = "APP_STORE", googlePlay = "GOOGLE_PLAY" }
    /// The plan and the store products that sell it.
    public struct Plan: Decodable, Sendable, Equatable {
        public let name: String
        public let monthlyCents: Int
        public let yearlyCents: Int
        public let trialDays: Int
        public let appStoreProductIds: [String]
    }

    public let status: Status
    public let source: Source?
    /// Whether the venue pays for Velvet itself (it signed itself up).
    public let required: Bool
    /// Whether its tools are open: covered by an audience, comped, or subscribed (trial and past due included).
    public let unlocked: Bool
    public let comped: Bool
    /// month or year.
    public let interval: String?
    public let trialAvailable: Bool
    /// ISO 8601 times, as the API sends them (``trialEnds``, ``periodEnds`` read them).
    public let trialEndsAt: String?
    public let periodEndsAt: String?
    public let cancelAtPeriodEnd: Bool
    /// Whether the signed-in person may subscribe for it and manage its billing (its owner and managers).
    public let canManage: Bool
    public let plan: Plan

    public var trialEnds: Date? { trialEndsAt.flatMap { ISO8601DateFormatter().date(from: $0) } }
    public var periodEnds: Date? { periodEndsAt.flatMap { ISO8601DateFormatter().date(from: $0) } }

    /// The tools lock when the venue must pay and doesn't.
    public var locksTools: Bool { required && !unlocked }

    public static let fields = """
        status source required unlocked comped interval trialAvailable trialEndsAt periodEndsAt cancelAtPeriodEnd canManage
        plan { name monthlyCents yearlyCents trialDays appStoreProductIds }
        """
}

/// Reads and changes a venue's Velvet subscription.
public struct VenueSubscriptionClient: Sendable {
    public let runner: any StaffGraphQLRunning

    public init(runner: any StaffGraphQLRunning) { self.runner = runner }

    /// The venue's subscription, or nil when the API doesn't have the field yet (an older server): treat that as
    /// unlocked, so nobody is locked out by a version mismatch.
    public func subscription(venueID: String) async throws -> VenueVelvetSubscription? {
        struct Venue: Decodable, Sendable { let velvetSubscription: VenueVelvetSubscription? }
        struct Response: Decodable, Sendable { let node: Venue? }
        let response = try await runner.graphQL("""
            query VelvetSubscription($id: ID!) { node(id: $id) { ... on Venue { velvetSubscription { \(VenueVelvetSubscription.fields) } } } }
            """, variables: ["id": .string(venueID)], as: Response.self)
        return response.node?.velvetSubscription
    }

    /// Records a StoreKit transaction (its `jwsRepresentation`) bought with the venue's ID as `appAccountToken`.
    public func recordAppStorePurchase(venueID: String, signedTransaction: String) async throws -> VenueVelvetSubscription? {
        try await record(venueID: venueID, ["signedTransaction": .string(signedTransaction)])
    }

    /// Records a Play Billing purchase token bought with the venue's ID as `obfuscatedAccountId`.
    public func recordGooglePlayPurchase(venueID: String, purchaseToken: String) async throws -> VenueVelvetSubscription? {
        try await record(venueID: venueID, ["purchaseToken": .string(purchaseToken)])
    }

    private func record(venueID: String, _ purchase: [String: GraphQLValue]) async throws -> VenueVelvetSubscription? {
        struct Venue: Decodable, Sendable { let velvetSubscription: VenueVelvetSubscription? }
        struct Payload: Decodable, Sendable { let venue: Venue }
        struct Response: Decodable, Sendable { let recordVenueStorePurchase: Payload }
        var input = purchase
        input["venueId"] = .string(venueID)
        let response = try await runner.graphQL("""
            mutation VelvetRecordPurchase($input: VenueStorePurchaseRecordInput!) {
              recordVenueStorePurchase(input: $input) { venue { velvetSubscription { \(VenueVelvetSubscription.fields) } } }
            }
            """, variables: ["input": .object(input)], as: Response.self)
        return response.recordVenueStorePurchase.venue.velvetSubscription
    }

    /// Stripe's Customer Portal, for a venue that pays on the web.
    public func billingPortal(venueID: String) async throws -> URL {
        struct Payload: Decodable, Sendable { let url: String }
        struct Response: Decodable, Sendable { let openVenueBillingPortal: Payload }
        let response = try await runner.graphQL("""
            mutation VelvetBillingPortal($input: VenueBillingPortalInput!) { openVenueBillingPortal(input: $input) { url } }
            """, variables: ["input": .object(["venueId": .string(venueID)])], as: Response.self)
        guard let url = URL(string: response.openVenueBillingPortal.url) else { throw URLError(.badURL) }
        return url
    }
}

extension VenueSubscriptionClient {
    /// The audiences that list the venue, 0 or more.
    public func audiences(venueID: String) async throws -> [ListedAudience] {
        struct Venue: Decodable, Sendable { let audiences: [ListedAudience]? }
        struct Response: Decodable, Sendable { let node: Venue? }
        let response = try await runner.graphQL("""
            query VelvetVenueAudiences($id: ID!) { node(id: $id) { ... on Venue { audiences { audienceId name subdomain } } } }
            """, variables: ["id": .string(venueID)], as: Response.self)
        return response.node?.audiences ?? []
    }

    /// Signs up a venue of the person's own, in no audience, on the audience-less endpoint. Answers its ID.
    public func createOwnVenue(name: String, googlePlaceID: String? = nil, website: String? = nil,
                               phone: String? = nil, timeZone: String? = TimeZone.current.identifier) async throws -> String {
        struct Venue: Decodable, Sendable { let id: String }
        struct Payload: Decodable, Sendable { let venue: Venue }
        struct Response: Decodable, Sendable { let createOwnVenue: Payload }
        var venue: [String: GraphQLValue] = ["name": .string(name)]
        if let googlePlaceID, !googlePlaceID.isEmpty { venue["googlePlaceId"] = .string(googlePlaceID) }
        if let website, !website.isEmpty { venue["website"] = .string(website) }
        if let phone, !phone.isEmpty { venue["phone"] = .string(phone) }
        if let timeZone { venue["coverTimeZone"] = .string(timeZone) }
        let response = try await runner.graphQL("""
            # endpoint: audienceless
            mutation VelvetCreateOwnVenue($input: OwnVenueCreateInput!) { createOwnVenue(input: $input) { venue { id } } }
            """, variables: ["input": .object(["venue": .object(venue)])], as: Response.self)
        return response.createOwnVenue.venue.id
    }
}

extension AudienceKitError {
    /// Whether the API refused a Velvet tool because the venue signed itself up and hasn't subscribed
    /// (`FORBIDDEN`, `extensions.reason: subscription_required`): show the paywall rather than the error.
    public var isSubscriptionRequired: Bool {
        code == Code.forbidden && errors.contains { $0.extensions?["reason"] == .string("subscription_required") }
    }
}
