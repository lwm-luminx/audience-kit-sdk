import Foundation
import Testing
import AudienceKit
@testable import StaffKitCore
@testable import StaffKitServices

private func talent(_ stub: Stub, audienceID: String?) -> TalentManagementClient {
    TalentManagementClient(session: AudienceManagementSession(
        baseURL: stub.baseURL,
        credentialStore: InMemoryCredentialStore(credential: makeCredential(audienceID: audienceID, role: "user", on: stub.baseURL)),
        session: stub.session))
}

@Test func registersThePushToStartTokenWithTheChosenListing() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{"registerShowNightToken":{"registered":true}}}"#) }
    try await talent(stub, audienceID: "a1").registerShowNightToken(kind: .start, pushToken: "abcd", appID: "com.audiencekit.Backstage",
                                                                    sandbox: true, personID: "p1")

    let request = try #require(stub.requests.last)
    #expect(request.path.hasSuffix("/staffql"))
    let body = try request.jsonBody()
    #expect((body["query"] as? String)?.contains("registerShowNightToken(input:") == true)
    let variables = body["variables"] as? [String: Any]
    #expect(variables?["kind"] as? String == "START")
    #expect(variables?["personId"] as? String == "p1")
    #expect(variables?["sandbox"] as? Bool == true)
    #expect(variables?["eventId"] == nil)
}

@Test func endsATokenOnTheAudiencelessEndpointWithNoAudienceChosen() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{"endShowNightToken":{"ended":true}}}"#) }
    try await talent(stub, audienceID: nil).endShowNightToken(pushToken: "abcd")

    let request = try #require(stub.requests.last)
    #expect(request.path == "/v1/staffql")
    let body = try request.jsonBody()
    #expect((body["variables"] as? [String: Any])?["pushToken"] as? String == "abcd")
}

@Test func registersAnActivityTokenForItsEvent() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{"registerShowNightToken":{"registered":true}}}"#) }
    try await talent(stub, audienceID: "a1").registerShowNightToken(kind: .activity, pushToken: "ef01", appID: "com.audiencekit.Backstage",
                                                                    sandbox: false, eventID: "e1")

    let variables = try #require(stub.requests.last).jsonBody()["variables"] as? [String: Any]
    #expect(variables?["kind"] as? String == "ACTIVITY")
    #expect(variables?["eventId"] as? String == "e1")
    #expect(variables?["personId"] == nil)
}

@Test func readsWhereAndWhenEachAppearanceIsTheEarliestSpotWinning() async throws {
    let body = #"""
    {"data":{"me":{"listings":{"people":[
      {"events":{"involvements":{"edges":[
        {"appearances":[{"startsAt":"2026-11-27T04:00:00Z","projectedStartsAt":"2026-11-27T04:20:00Z","curtainCallMinutes":15},
                        {"startsAt":"2026-11-27T03:00:00Z","projectedStartsAt":null,"curtainCallMinutes":null}],
         "node":{"id":"e1","venue":{"venue":{"location":{"latitude":33.45,"longitude":-112.07,"address":"1 Main St"}}}}},
        {"appearances":[],"node":{"id":"e2","venue":null}}]}}},
      {"events":{"involvements":{"edges":[
        {"appearances":[{"startsAt":"2026-11-27T05:00:00Z","projectedStartsAt":null,"curtainCallMinutes":null}],
         "node":{"id":"e1","venue":{"venue":{"location":{"latitude":33.45,"longitude":-112.07,"address":"1 Main St"}}}}}]}}}
    ]}}}}
    """#
    let stub = Stub { _ in .json(status: 200, body: body) }
    let departures = try await talent(stub, audienceID: "a1").showNightDepartures()

    let first = try #require(departures["e1"])
    #expect(first.curtain == parseInstant("2026-11-27T03:00:00Z"))
    #expect(first.curtainCallMinutes == nil)
    #expect(first.latitude == 33.45)
    #expect(first.longitude == -112.07)
    #expect(first.address == "1 Main St")
    let tba = try #require(departures["e2"])
    #expect(tba.curtain == nil)
    #expect(tba.latitude == nil)
    let query = try #require(stub.requests.last).jsonBody()["query"] as? String
    #expect(query?.contains("appearances { startsAt projectedStartsAt curtainCallMinutes }") == true)
}

@Test func handsOverOnlyTheTimesOfAPlan() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{"setShowNightPlan":{"saved":true}}}"#) }
    let leave = Date(timeIntervalSince1970: 1_800_000_000)
    try await talent(stub, audienceID: nil).setShowNightPlan(
        eventID: "e1", times: ShowNightPlanTimes(readyBy: leave.addingTimeInterval(-5_400), leaveBy: leave))

    let request = try #require(stub.requests.last)
    #expect(request.path == "/v1/staffql")
    let variables = try request.jsonBody()["variables"] as? [String: Any]
    #expect(variables?["eventId"] as? String == "e1")
    #expect(variables?["leaveBy"] as? String == "2027-01-15T08:00:00Z")
    #expect(variables?["readyBy"] as? String == "2027-01-15T06:30:00Z")
    #expect(variables?["arriveBy"] == nil)
    #expect(ShowNightPlanTimes().isEmpty)
}
