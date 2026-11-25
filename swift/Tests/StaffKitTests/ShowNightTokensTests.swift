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
