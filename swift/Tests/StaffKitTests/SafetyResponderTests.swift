import Foundation
import Testing
import AudienceKit
import StaffKitCore
@testable import StaffKitServices

private func responderClient(_ stub: Stub) -> SafetyResponderClient {
    SafetyResponderClient(session: AudienceManagementSession(baseURL: stub.baseURL, credentialStore: InMemoryCredentialStore(credential: makeCredential(audienceID: "audience", on: stub.baseURL)), session: stub.session))
}
private func lastRequest(_ stub: Stub) throws -> (query: String, variables: [String: Any], input: [String: Any]) {
    let body = try #require(stub.requests.last).jsonBody()
    let variables = body["variables"] as? [String: Any] ?? [:]
    return (body["query"] as? String ?? "", variables, variables["input"] as? [String: Any] ?? [:])
}

private let responderAlertJSON = #"""
{"id":"s2","state":"ACKNOWLEDGED","place":"BAR","concerns":["UNWELL"],"description":null,"summary":"Bar · They don’t feel well",
 "seen":true,"seenByMe":true,"acknowledgedByName":"Dee","acknowledgedByResponder":true,"acknowledgedAt":"2026-11-26T03:00:00Z",
 "escalatedAt":"2026-11-26T02:59:00Z","remindedAt":null,"closedAt":null,"outcome":null,"staffNote":null,"supportSharedAt":null,
 "supportNote":null,"createdAt":"2026-11-26T02:57:00Z","venue":{"id":"v1","name":"Club Try-Angles","locale":{"id":"l1","name":"Salt Lake"}},"event":null,
 "messages":[{"id":"m1","body":"Try here\nFood Bank\nCall 555-0100","fromStaff":true,"senderName":"Dee","createdAt":"2026-11-26T03:01:00Z",
   "resource":{"id":"r1","title":"Food Bank","phone":"555-0100","textNumber":null,"address":null,"url":null,"intakeNote":"No ID needed.","sensitive":false}}]}
"""#

@Test func aResponderAlertDecodesWithoutItsReporter() throws {
    let alert = try JSONDecoder().decode(StaffSafetyAlert.self, from: Data(responderAlertJSON.utf8))
    #expect(alert.reporter == nil)
    #expect(alert.venue?.name == "Club Try-Angles" && alert.venue?.locale?.id == "l1")
    #expect(alert.acknowledgedByResponder == true)
    #expect(alert.messages.first?.resource?.title == "Food Bank")
    #expect(alert.messages.first?.resource?.sensitive == false)
}

@Test func aVelvetAlertStillDecodesWithoutResponderFields() throws {
    let json = #"{"id":"s1","state":"OPEN","place":null,"concerns":[],"description":null,"summary":"No details yet","seen":false,"seenByMe":false,"acknowledgedByName":null,"acknowledgedAt":null,"escalatedAt":null,"remindedAt":null,"closedAt":null,"outcome":null,"staffNote":null,"supportSharedAt":null,"supportNote":null,"createdAt":"2026-10-23T03:15:00Z","reporter":null,"event":null,"messages":[{"id":"m1","body":"Hi","fromStaff":false,"senderName":"Alex","createdAt":"2026-10-23T03:16:00Z"}]}"#
    let alert = try JSONDecoder().decode(StaffSafetyAlert.self, from: Data(json.utf8))
    #expect(alert.venue == nil && alert.acknowledgedByResponder == nil && alert.messages.first?.resource == nil)
}

@Test func aResponderSaysWhatTheyCover() throws {
    let regional = try JSONDecoder().decode(SafetyResponder.self, from: Data(#"{"kind":"SOCIAL_WORKER","hears":"ESCALATED","onDuty":true,"everywhere":false,"locales":[{"id":"l1","name":"Salt Lake"},{"id":"l2","name":"Provo"}]}"#.utf8))
    #expect(regional.coverage == "Salt Lake, Provo")
    #expect(SafetyResponder(kind: "MODERATOR", hears: "ALL", onDuty: false, everywhere: true).coverage == "Every venue")
    #expect(SafetyResponder.hearsChoices.map(\.value) == ["ESCALATED", "ALL", "NONE"])
}

@Test func responderPushesSayTheyAreForAResponder() {
    #expect(SafetyAlertPush.isForResponder(["kind": "safety_alert", "responder": "true"]))
    #expect(!SafetyAlertPush.isForResponder(["kind": "safety_alert"]))
}

@Test func aResponderListsTheAlertsTheyCover() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{"responderSafetyAlerts":{"nodes":[\#(responderAlertJSON)]}}}"#) }
    let alerts = try await responderClient(stub).alerts(localeID: "l1")
    #expect(alerts.map(\.id) == ["s2"])
    let (query, variables, _) = try lastRequest(stub)
    #expect(query.contains("responderSafetyAlerts(localeId: $localeId, first: 100)"))
    #expect(query.contains("acknowledgedByResponder") && query.contains("resource {") && !query.contains("reporter"))
    #expect(variables["localeId"] as? String == "l1")
}

@Test func aResponderReadsAndSetsTheirDuty() async throws {
    let responder = #"{"kind":"MODERATOR","hears":"ALL","onDuty":false,"everywhere":true,"locales":[]}"#
    let stub = Stub { request in
        let query = (try? request.jsonBody()["query"] as? String) ?? ""
        return query.contains("setSafetyResponderDuty")
            ? .json(status: 200, body: #"{"data":{"setSafetyResponderDuty":{"safetyResponder":\#(responder)}}}"#)
            : .json(status: 200, body: #"{"data":{"safetyResponder":null}}"#)
    }
    let client = responderClient(stub)
    #expect(try await client.responder() == nil)
    let set = try await client.setDuty(onDuty: false, hears: "ALL")
    #expect(set?.onDuty == false && set?.hears == "ALL")
    #expect(try lastRequest(stub).input["onDuty"] as? Bool == false)
}

@Test func anAdminCoversEveryVenue() async throws {
    let stub = Stub { _ in
        .json(status: 200, body: #"{"data":{"saveSafetyResponder":{"safetyResponder":{"kind":"SOCIAL_WORKER","hears":"ESCALATED","onDuty":true,"everywhere":true,"locales":[]}}}}"#)
    }
    let responder = try await responderClient(stub).coverEveryVenue(kind: "SOCIAL_WORKER")
    #expect(responder.everywhere && responder.onDuty && responder.coverage == "Every venue")
    let request = try lastRequest(stub)
    #expect(request.input["kind"] as? String == "SOCIAL_WORKER")
    #expect((request.input["localeIds"] as? [Any])?.isEmpty == true)
    #expect(request.input["userId"] == nil)
}

@Test func aResponderActsOnAnAlertAndSharesAResource() async throws {
    let stub = Stub { request in
        let query = (try? request.jsonBody()["query"] as? String) ?? ""
        if query.contains("communityResources") {
            return .json(status: 200, body: #"{"data":{"communityResources":[{"id":"r1","title":"Food Bank","phone":null,"textNumber":null,"address":null,"url":null,"intakeNote":null,"sensitive":false}]}}"#)
        }
        let name = ["seeSafetyAlert", "acknowledgeSafetyAlert", "sendSafetyAlertMessage", "shareSafetyAlertSupport",
                    "shareSafetyAlertResource", "closeSafetyAlert"].first { query.contains("{ \($0)(") } ?? "none"
        return .json(status: 200, body: #"{"data":{"\#(name)":{"safetyAlert":\#(responderAlertJSON)}}}"#)
    }
    let client = responderClient(stub)
    #expect(try await client.resources(localeID: "l1").first?.title == "Food Bank")
    _ = try await client.see(id: "s2")
    _ = try await client.acknowledge(id: "s2", name: "Dee")
    #expect(try lastRequest(stub).input["staffName"] as? String == "Dee")
    _ = try await client.sendMessage(id: "s2", body: "I'm here")
    _ = try await client.shareSupport(id: "s2", note: "Call any time")
    let shared = try await client.shareResource(id: "s2", resourceID: "r1", note: "Try here")
    #expect(shared.messages.first?.resource?.id == "r1")
    let (query, _, input) = try lastRequest(stub)
    #expect(query.contains("mutation ArbiterShareSafetyAlertResource($input: SafetyAlertResourceShareInput!)"))
    #expect(input["resourceId"] as? String == "r1" && input["note"] as? String == "Try here")
    _ = try await client.close(id: "s2", outcome: "SORTED", note: nil)
    try await client.registerDevice(token: "abc", appID: "com.audiencekit.Arbiter", sandbox: true)
    #expect(try lastRequest(stub).input["appId"] as? String == "com.audiencekit.Arbiter")
    #expect(try lastRequest(stub).input["note"] == nil)
}

@Test func aMissingAlertSaysItIsGone() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{"seeSafetyAlert":null}}"#) }
    await #expect(throws: SafetyAlertError.self) { try await responderClient(stub).see(id: "gone") }
}

private let applicationJSON = #"{"id":"a1","audienceId":"audience","audienceName":"Hot Mess","name":"Dee Lopez","email":"dee@example.com","kind":"SOCIAL_WORKER","credential":"LCSW","credentialOther":null,"licenseNumber":"LCSW-1234","issuedBy":"Utah","note":"Weekends","status":"PENDING","reviewNote":null,"createdAt":"2026-11-26T05:00:00Z","reviewedAt":null}"#

@Test func someoneSignedInOnThePlatformAppliesToBeAResponder() async throws {
    let stub = Stub { request in
        let query = (try? request.jsonBody()["query"] as? String) ?? ""
        if query.contains("applyToBeSafetyResponder") {
            return .json(status: 200, body: #"{"data":{"applyToBeSafetyResponder":{"application":\#(applicationJSON)}}}"#)
        }
        return .json(status: 200, body: #"{"data":{"me":{"responderCommunities":[{"audienceId":"audience","name":"Hot Mess","responder":false,"pending":false}],"safetyResponderApplications":[]}}}"#)
    }
    let session = AudienceManagementSession(baseURL: stub.baseURL, credentialStore: InMemoryCredentialStore(credential: makeCredential(audienceID: nil, on: stub.baseURL)), session: stub.session)
    let client = SafetyResponderApplyClient(session: session)
    #expect(await client.canApply)
    let overview = try await client.overview()
    #expect(overview.communities.map(\.name) == ["Hot Mess"] && overview.applications.isEmpty)
    #expect(try #require(stub.requests.last).path == "/v1/staffql")

    let application = try await client.apply(SafetyResponderApplicationInput(audienceID: "audience", credential: "LCSW",
                                                                             licenseNumber: " LCSW-1234 ", issuedBy: "Utah", note: ""))
    #expect(application.isPending && application.credentialTitle.hasPrefix("LCSW") && application.statusTitle == "Waiting for an admin")
    let input = try lastRequest(stub).input
    #expect(input["licenseNumber"] as? String == "LCSW-1234" && input["note"] == nil && input["kind"] as? String == "SOCIAL_WORKER")
}

@Test func anAdminApprovesAnApplicationForSomeLocales() async throws {
    let stub = Stub { request in
        let query = (try? request.jsonBody()["query"] as? String) ?? ""
        if query.contains("reviewSafetyResponderApplication") {
            return .json(status: 200, body: #"{"data":{"reviewSafetyResponderApplication":{"application":\#(applicationJSON.replacingOccurrences(of: "\"PENDING\"", with: "\"APPROVED\""))}}}"#)
        }
        return .json(status: 200, body: #"{"data":{"safetyResponderApplications":[\#(applicationJSON)]}}"#)
    }
    let client = responderClient(stub)
    let queue = try await client.applications()
    #expect(queue.map(\.email) == ["dee@example.com"])
    #expect(try lastRequest(stub).variables["status"] as? String == "PENDING")
    let decided = try await client.review(id: "a1", approve: true, localeIDs: ["l1"], note: "Checked")
    #expect(decided.status == "APPROVED")
    let input = try lastRequest(stub).input
    #expect(input["approve"] as? Bool == true && input["localeIds"] as? [String] == ["l1"] && input["note"] as? String == "Checked")
    _ = try await client.review(id: "a1", approve: false)
    #expect(try lastRequest(stub).input["localeIds"] == nil)
}

@Test func anAdminBrowsesLocalesToCover() async throws {
    let stub = Stub { request in
        let query = (try? request.jsonBody()["query"] as? String) ?? ""
        if query.contains("parentId") {
            return .json(status: 200, body: #"{"data":{"locales":[{"id":"c2","name":"Provo","kind":"CITY"},{"id":"c1","name":"Ogden","kind":"CITY"}]}}"#)
        }
        return .json(status: 200, body: #"{"data":{"locales":[{"id":"s1","name":"Utah","kind":"STATE"}]}}"#)
    }
    let client = responderClient(stub)
    #expect(try await client.locales().map(\.title) == ["Utah"])
    #expect(try await client.locales(parentID: "s1").map(\.title) == ["Ogden", "Provo"])
    #expect(try lastRequest(stub).variables["parentId"] as? String == "s1")
}
