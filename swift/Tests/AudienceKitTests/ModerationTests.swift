@testable import AudienceCore
import Foundation
import Testing
@testable import AudienceKit

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private let moderationAudienceID = "00000000-0000-4000-8000-000000000004"

private func moderationClient(_ stub: Stub) -> AudienceKitClient {
    let endpoint = URL(string: GraphQLEndpoint.consumer.path(audienceID: moderationAudienceID),
                       relativeTo: stub.baseURL)!.absoluteURL
    let store = InMemoryCredentialStore(credential: Credential(token: "session-token", userId: "u-1",
                                                               audienceId: moderationAudienceID, role: "member",
                                                               endpoint: endpoint))
    let configuration = AudienceKitConfiguration(baseURL: stub.baseURL, audienceID: moderationAudienceID)
    return AudienceKitClient(configuration: configuration, credentialStore: store, session: stub.session)
}

@Test func reportingAMessageSendsItsFrameAndCanBlock() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{"reportContent":{"reported":true,"blocked":true}}}"#) }
    let client = moderationClient(stub)

    let result = try await client.reportContent(.message, id: "frame-1", reason: "Spam", block: true)

    #expect(result == ReportResult(reported: true, blocked: true))
    let body = try stub.requests[0].jsonBody()
    #expect(body["operationName"] as? String == "ReportContent")
    let variables = body["variables"] as? [String: Any]
    #expect(variables?["targetType"] as? String == "MESSAGE")
    #expect(variables?["targetId"] as? String == "frame-1")
    #expect(variables?["reason"] as? String == "Spam")
    #expect(variables?["block"] as? Bool == true)
}

@Test func aReportWithoutAReasonSendsNull() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{"reportContent":{"reported":true,"blocked":false}}}"#) }
    let client = moderationClient(stub)

    let result = try await client.reportContent(.person, id: "user-2")

    #expect(result.reported)
    #expect(!result.blocked)
    let variables = try stub.requests[0].jsonBody()["variables"] as? [String: Any]
    #expect(variables?["reason"] is NSNull)
    #expect(variables?["block"] as? Bool == false)
}

@Test func aMissingReportPayloadIsNotReported() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{"reportContent":null}}"#) }

    #expect(try await moderationClient(stub).reportContent(.message, id: "frame-1") == ReportResult())
}

@Test func blockingAndUnblockingSendTheUserID() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{"blockUser":{"blockedUsers":[{"id":"user-2"}]}}}"#) }
    let client = moderationClient(stub)

    try await client.blockUser("user-2")
    try await client.unblockUser("user-2")

    #expect(try stub.requests.map { try $0.jsonBody()["operationName"] as? String } == ["BlockUser", "UnblockUser"])
    #expect((try stub.requests[1].jsonBody()["variables"] as? [String: Any])?["userId"] as? String == "user-2")
}

@Test func aFailedBlockThrows() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{"blockUser":null},"errors":[{"message":"nope"}]}"#) }

    await #expect(throws: AudienceKitError.self) { try await moderationClient(stub).blockUser("user-2") }
}

@Test func theReportCopyOffersReasons() {
    #expect(ReportCopy.reasons.contains("Spam"))
    #expect(ReportTarget.allCases.count == 7)
}
