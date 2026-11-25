import Foundation
import Testing
import AudienceKit
import StaffKitCore
import StaffKitServices

private func client(_ stub: Stub) -> VenueManagementClient {
    VenueManagementClient(session: AudienceManagementSession(baseURL: stub.baseURL, credentialStore: InMemoryCredentialStore(credential: makeCredential(audienceID: "audience", on: stub.baseURL)), session: stub.session))
}
private func sent(_ stub: Stub) throws -> (query: String, variables: [String: Any], input: [String: Any]) {
    let body = try #require(stub.requests.last).jsonBody()
    let variables = body["variables"] as? [String: Any] ?? [:]
    return (body["query"] as? String ?? "", variables, variables["input"] as? [String: Any] ?? [:])
}

@Test func aVenueReadsItsPaymentAccountInAnEnvironment() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{"venues":{"venue":{"tickets":{"cover":{"paymentAccount":{"provider":"SQUARE","status":"incomplete","chargesEnabled":false,"locationName":null,"squareLocations":[{"id":"L1","name":"Bar","address":"1 Main St"}]}}}}}}}"#) }
    let account = try #require(try await client(stub).paymentAccount(venueID: "venue", environment: .sandbox))
    #expect(account.provider == .square)
    #expect(account.needsLocation && !account.isActive)
    #expect(account.squareLocations?.first?.name == "Bar")
    let request = try sent(stub)
    #expect(request.query.contains("paymentAccount(environment: $environment)"))
    #expect(request.variables["environment"] as? String == "SANDBOX")
}

@Test func connectingComesBackToTheAppsReturnPage() async throws {
    let stub = Stub { request in
        let query = (try? request.jsonBody()["query"] as? String) ?? ""
        if query.contains("connectVenueStripe") { return .json(status: 200, body: #"{"data":{"connectVenueStripe":{"onboardingUrl":"https://connect.stripe.com/setup/s/abc"}}}"#) }
        return .json(status: 200, body: #"{"data":{"connectVenueSquare":{"authorizeUrl":"https://connect.squareup.com/oauth2/authorize?x=1"}}}"#)
    }
    let venues = client(stub)
    let back = venues.paymentsReturnURL(app: "velvet")
    #expect(back.path == "/v1/payments/return/velvet" && back.host == stub.baseURL.host)

    #expect(try await venues.connectStripe(venueID: "venue", returnTo: back).host == "connect.stripe.com")
    #expect(try sent(stub).input["returnTo"] as? String == back.absoluteString)

    #expect(try await venues.connectSquare(venueID: "venue", returnTo: back, environment: .production).host == "connect.squareup.com")
    let square = try sent(stub)
    #expect(square.input["environment"] as? String == "PRODUCTION")
    #expect(square.input["venueId"] as? String == "venue")
}

@Test func pickingALocationAndDisconnectingUseTheirMutations() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{"x":{"venue":{"id":"venue"}}}}"#) }
    let venues = client(stub)
    try await venues.setSquareLocation(venueID: "venue", locationID: "L2", environment: .sandbox)
    var request = try sent(stub)
    #expect(request.query.contains("setVenueSquareLocation(input: $input)"))
    #expect(request.input["locationId"] as? String == "L2" && request.input["environment"] as? String == "SANDBOX")
    try await venues.disconnectPayments(venueID: "venue", environment: .production)
    request = try sent(stub)
    #expect(request.query.contains("disconnectVenuePayments(input: $input)"))
    #expect(request.input["venueId"] as? String == "venue")
}
