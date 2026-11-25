import Foundation
import Testing
import AudienceKit
import StaffKitCore
import StaffKitServices

private func client(_ stub: Stub) -> VenueManagementClient {
    VenueManagementClient(session: AudienceManagementSession(baseURL: stub.baseURL, credentialStore: InMemoryCredentialStore(credential: makeCredential(audienceID: "audience", on: stub.baseURL)), session: stub.session))
}
private func sent(_ stub: Stub) throws -> (query: String, input: [String: Any]) {
    let body = try #require(stub.requests.last).jsonBody()
    let variables = body["variables"] as? [String: Any] ?? [:]
    return (body["query"] as? String ?? "", variables["input"] as? [String: Any] ?? [:])
}
private let licence = "@\n\u{1e}\rANSI 636040100001DL00310250DLDAQ123456789\nDCSDOE\nDACALEX\nDBB06151995\nDBA06152029\r"
private let policy = #"{"jurisdiction":"UT","scan":"EVERYONE","retentionHours":168,"drinkingAge":21,"visualCheck":"Look for NO ALCOHOL SALE","citation":"Utah Code 32B-1-407","summary":"Scan every ID"}"#
private let check = #"{"id":"c1","entry":"SCAN","documentKind":"DRIVERS_LICENSE","outcome":"OK","name":"Alex Doe","age":31,"birthDate":"1995-06-15","expiresOn":"2029-06-15","gender":"female","issuer":"UT","idNumber":null,"noAlcoholSale":false,"checkedAt":"2026-11-13T06:00:00Z","expiresAt":"2026-11-20T06:00:00Z"}"#

@Test func theDoorSendsALicenceToTheIDCheckAndAPassToTheCover() async throws {
    let stub = Stub { request in
        let query = (try? request.jsonBody()["query"] as? String) ?? ""
        if query.contains("scanId") {
            return .json(status: 200, body: #"{"data":{"scanId":{"result":{"outcome":"OK","message":"OK · Alex Doe, 31","idNumber":"123456789","problems":[],"policy":\#(policy),"idCheck":\#(check)}}}}"#)
        }
        return .json(status: 200, body: #"{"data":{"scanAdmission":{"result":{"outcome":"ADMIT","message":"Paid · Alex"}}}}"#)
    }
    let venues = client(stub)
    let id = try await venues.checkAtDoor(venueID: "venue", code: licence)
    #expect(id.outcome == "ID_OK" && id.admitted)
    #expect(id.idResult?.idNumber == "123456789")
    #expect(id.idResult?.policy.scansEveryone == true)
    #expect(id.idResult?.idCheck?.idNumber == nil)
    var request = try sent(stub)
    #expect(request.query.contains("scanId(input: $input)"))
    #expect(request.input["barcode"] as? String == AAMVABarcode.minimized(licence))

    let pass = try await venues.checkAtDoor(venueID: "venue", code: "HMC1.abc")
    #expect(pass.outcome == "ADMIT" && pass.admitted && pass.idResult == nil)
    request = try sent(stub)
    #expect(request.query.contains("scanAdmission"))
}

@Test func typedInIDsAndMarksUseTheirMutations() async throws {
    let stub = Stub { request in
        let query = (try? request.jsonBody()["query"] as? String) ?? ""
        if query.contains("markIdCheck") { return .json(status: 200, body: #"{"data":{"markIdCheck":{"idCheck":\#(check)}}}"#) }
        return .json(status: 200, body: #"{"data":{"recordIdCheck":{"result":{"outcome":"OK","message":"OK","idNumber":"X1","problems":[],"policy":\#(policy),"idCheck":\#(check)}}}}"#)
    }
    let venues = client(stub)
    _ = try await venues.recordID(venueID: "venue", entry: DoorIDEntry(name: "Pat Lee", birthDate: "1990-01-02", expiresOn: "2030-01-01", idNumber: "X1"))
    var request = try sent(stub)
    #expect(request.query.contains("IdCheckRecordInput!"))
    #expect(request.input["documentKind"] as? String == "PASSPORT")
    #expect(request.input["idNumber"] as? String == "X1")
    #expect(request.input["issuer"] == nil)

    _ = try await venues.markID(id: "c1", noAlcoholSale: true)
    request = try sent(stub)
    #expect(request.input["noAlcoholSale"] as? Bool == true)
    #expect(request.input["suspect"] == nil)
}

@Test func theLogReadsThePolicyAndCSV() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{"node":{"idCheckPolicy":\#(policy),"idChecks":{"checks":[\#(check)],"csv":"checked_at\n"}}}}"#) }
    let (rules, log) = try await client(stub).idLog(venueID: "venue")
    #expect(rules?.retentionHours == 168)
    #expect(log?.checks.first?.name == "Alex Doe")
    #expect(log?.csv.hasPrefix("checked_at") == true)
    #expect(DoorID.isLicence(licence) && !DoorID.isLicence("HMC1.abc"))
}
