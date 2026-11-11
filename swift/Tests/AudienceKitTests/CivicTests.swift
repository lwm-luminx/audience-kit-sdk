@testable import AudienceCore
import Foundation
import Testing
@testable import AudienceKit

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private let civicAudienceID = "00000000-0000-4000-8000-000000000477"

private func civicClient(_ stub: Stub) -> AudienceKitClient {
    let endpoint = URL(string: GraphQLEndpoint.consumer.path(audienceID: civicAudienceID),
                       relativeTo: stub.baseURL)!.absoluteURL
    let store = InMemoryCredentialStore(credential: Credential(token: "session-token", userId: "u-1",
                                                               audienceId: civicAudienceID, role: "member",
                                                               endpoint: endpoint))
    let configuration = AudienceKitConfiguration(baseURL: stub.baseURL, audienceID: civicAudienceID)
    return AudienceKitClient(configuration: configuration, credentialStore: store, session: stub.session)
}

private extension RecordedRequest {
    var query: String { ((try? jsonBody())?["query"] as? String) ?? "" }
    var operationName: String? { (try? jsonBody())?["operationName"] as? String }
    var variables: [String: Any] { ((try? jsonBody())?["variables"] as? [String: Any]) ?? [:] }
}

private let officeJSON = #"""
{"id":"o-1","office":"US_HOUSE","title":"U.S. Representative","label":"U.S. Representative, UT-3","status":"INCUMBENT",
"party":"Democratic","caucus":null,"electionDate":"2026-11-03","termStart":"2025-01-03","termEnd":"2027-01-03",
"locale":{"id":"l-ut3","name":"Utah's 3rd","label":"UT-3","kind":"CONGRESSIONAL_DISTRICT",
"divisionId":"ocd-division/country:us/state:ut/cd:3"},"person":{"id":"p-1","name":"Pat Example","avatarUrl":"/photos/p-1.jpg",
"donateTarget":{"id":"d-1","provider":"ACTBLUE","url":"https://secure.actblue.com/donate/pat","recipientName":"Pat for Utah",
"disclaimer":"Paid for by Pat for Utah","political":true}}}
"""#

@Test func officesAtAPositionDecodeMostLocalFirst() async throws {
    let senator = officeJSON.replacingOccurrences(of: "\"o-1\"", with: "\"o-2\"")
        .replacingOccurrences(of: "US_HOUSE", with: "US_SENATE")
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{"offices":["# + officeJSON + "," + senator + "]}}") }

    let offices = try await civicClient(stub).offices(at: Coordinate(latitude: 40.76, longitude: -111.89))

    #expect(offices.map(\.id) == ["o-1", "o-2"])
    let office = try #require(offices.first)
    #expect(office.office == .usHouse)
    #expect(office.office.isFederal)
    #expect(office.status == .incumbent)
    #expect(office.label == "U.S. Representative, UT-3")
    #expect(office.locale.kind == "CONGRESSIONAL_DISTRICT")
    #expect(office.person?.donateTarget?.political == true)
    #expect(office.person?.donateTarget?.disclaimer == "Paid for by Pat for Utah")
    #expect(offices.last?.office == .usSenate)
    let request = try #require(stub.requests.first)
    #expect(request.operationName == "Offices")
    let at = try #require(request.variables["at"] as? [String: Any])
    #expect(at["latitude"] as? Double == 40.76)
    #expect(request.variables["localeId"] == nil)
}

@Test func officesForALocaleSendItsIDAndStatuses() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{"offices":[]}}"#) }

    let offices = try await civicClient(stub).offices(localeID: "l-ut", status: [.candidate])

    #expect(offices.isEmpty)
    let request = try #require(stub.requests.first)
    #expect(request.variables["localeId"] as? String == "l-ut")
    #expect(request.variables["status"] as? [String] == ["CANDIDATE"])
    #expect(request.variables["at"] == nil)
}

@Test func officesWithoutAPlaceAskNothing() async throws {
    let stub = Stub { _ in .json(status: 500, body: "{}") }

    let offices = try await civicClient(stub).offices()

    #expect(offices.isEmpty)
    #expect(stub.requests.isEmpty)
}

@Test func anUnknownOfficeKindIsKept() throws {
    let kind = try JSONDecoder().decode([OfficeKind].self, from: Data(#"["SHERIFF","GOVERNOR"]"#.utf8))
    #expect(kind == [.unknown("SHERIFF"), .governor])
    #expect(kind.first?.rawValue == "SHERIFF")
    #expect(OfficeKind.stateHouse.rawValue == "STATE_HOUSE")
    #expect(!OfficeKind.mayor.isFederal)
    let encoded = try JSONEncoder().encode([OfficeKind.lieutenantGovernor])
    #expect(String(decoding: encoded, as: UTF8.self) == #"["LIEUTENANT_GOVERNOR"]"#)
}

@Test func anOfficeHolderReadsOfficesSocialsEventsAndSharedIssues() async throws {
    let office = officeJSON.replacingOccurrences(of: #","person":{"#, with: #","ignored":{"#)
    let body = #"""
    {"data":{"node":{"id":"p-1","name":"Pat Example","avatarUrl":null,"bannerUrl":null,
    "donateTarget":{"id":"d-1","provider":"ACTBLUE","url":"https://secure.actblue.com/donate/pat","recipientName":null,
    "disclaimer":null,"political":true},
    "offices":[\#(office)],
    "profile":{"website":"https://pat.house.gov","socialLinks":{"nodes":[{"id":"s-1","provider":"bluesky",
    "handle":"pat.bsky.social","url":"https://bsky.app/profile/pat.bsky.social"}]}},
    "events":{"involvements":{"edges":[{"node":{"id":"e-1","name":"Town hall","startAt":"2026-12-01T01:00:00Z",
    "locale":null,"tags":[]}}]}},
    "sharedTribes":[{"id":"t-1","name":"Health care","color":null}]}}}
    """#
    let stub = Stub { _ in .json(status: 200, body: body) }

    let holder = try #require(try await civicClient(stub).officeHolder(id: "p-1"))

    #expect(holder.name == "Pat Example")
    #expect(holder.offices.first?.person == nil)
    #expect(holder.offices.first?.locale.divisionId == "ocd-division/country:us/state:ut/cd:3")
    #expect(holder.donateTarget?.provider == "ACTBLUE")
    #expect(holder.website == "https://pat.house.gov")
    #expect(holder.socialAccounts.map(\.provider) == ["bluesky"])
    #expect(holder.events.map(\.name) == ["Town hall"])
    #expect(holder.sharedIssues.map(\.name) == ["Health care"])
    let request = try #require(stub.requests.first)
    #expect(request.operationName == "OfficeHolder")
    #expect(request.variables["id"] as? String == "p-1")
    #expect(request.query.contains("... on Person"))
}

@Test func aMissingOfficeHolderIsNil() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{"node":null}}"#) }

    #expect(try await civicClient(stub).officeHolder(id: "nobody") == nil)
}

@Test func anAudienceWithoutOfficesAsksAgainWithoutThem() async throws {
    let stub = Stub { request in
        if request.query.contains("__type") {
            let pattern = try! NSRegularExpression(pattern: #"(t\d+): __type\(name: "(\w+)"\)"#)
            let query = request.query
            let entries = pattern.matches(in: query, range: NSRange(query.startIndex..., in: query)).map { match in
                let alias = String(query[Range(match.range(at: 1), in: query)!])
                return #""\#(alias)":{"fields":[{"name":"id"},{"name":"name"}]}"#
            }
            return .json(status: 200, body: #"{"data":{"# + entries.joined(separator: ",") + "}}")
        }
        if request.query.contains("offices") {
            return .json(status: 200, body: #"{"errors":[{"message":"Field 'offices' doesn't exist","extensions":{"code":"undefinedField"}}]}"#)
        }
        return .json(status: 200, body: #"{"data":{"id":"a-1"}}"#)
    }

    let offices = try await civicClient(stub).offices(localeID: "l-1")

    #expect(offices.isEmpty)
    #expect(stub.requests.last?.query.contains("offices") == false)
}
