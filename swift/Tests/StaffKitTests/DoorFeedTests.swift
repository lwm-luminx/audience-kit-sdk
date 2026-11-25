import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
import AudienceCore
@testable import StaffKitCore
@testable import StaffKitServices

private let row = #"{"id":"a1","amount":{"cents":1000,"currency":"usd"},"total":{"cents":1112,"currency":"usd"},"status":"PAID","checkedInAt":null,"scanCount":0,"createdAt":"2026-10-10T05:00:00Z","profile":{"id":"u1","name":"Alex","avatarUrl":null}}"#

@Test func theCableAddressAndIdentifierAreStable() {
    #expect(AudienceCable.url(for: URL(string: "https://api.audiencekit.com")!).absoluteString == "wss://api.audiencekit.com/connection")
    #expect(AudienceCable.url(for: URL(string: "http://localhost:3000/")!).absoluteString == "ws://localhost:3000/connection")
    // Sorted keys, so the string Action Cable matches commands by never changes between sends.
    #expect(AudienceCable.graphQLIdentifier(audienceID: "aud", channelID: "c1", endpoint: .staff)
            == #"{"audience_id":"aud","channel":"GraphQLChannel","channelId":"c1","endpoint":"staffql"}"#)
}

@Test func theExecuteCommandCarriesTheOperation() throws {
    let data = AudienceCable.executeData(query: "subscription { door(venueId: $id) { __typename } }",
                                      variables: ["id": .string("v1")], operationName: "StaffDoor")
    let object = try #require(JSONSerialization.jsonObject(with: Data(data.utf8)) as? [String: Any])
    #expect(object["action"] as? String == "execute")
    #expect(object["query"] as? String == "subscription { door(venueId: $id) { __typename } }")
    #expect((object["variables"] as? [String: Any])?["id"] as? String == "v1")
    #expect(object["operationName"] as? String == "StaffDoor")
}

@Test func protocolFramesAreToldApartFromResults() throws {
    let welcome = try #require(AudienceCable.parse(Data(#"{"type":"welcome"}"#.utf8)))
    #expect(welcome.type == "welcome" && welcome.result == nil)
    let confirm = try #require(AudienceCable.parse(Data(#"{"type":"confirm_subscription","identifier":"{\"channel\":\"GraphQLChannel\"}"}"#.utf8)))
    #expect(confirm.identifier == #"{"channel":"GraphQLChannel"}"#)
    let bye = try #require(AudienceCable.parse(Data(#"{"type":"disconnect","reason":"unauthorized","reconnect":false}"#.utf8)))
    #expect(bye.reason == "unauthorized" && bye.reconnect == false)
    let frame = try #require(AudienceCable.parse(Data(#"{"identifier":"{\"channel\":\"GraphQLChannel\"}","message":{"result":{"data":{"door":null}},"more":true}}"#.utf8)))
    #expect(frame.type == nil && frame.result != nil && frame.more == true)
    let done = try #require(AudienceCable.parse(Data(#"{"identifier":"x","message":{"more":false}}"#.utf8)))
    #expect(done.result == nil && done.more == false)
}

@Test func theDoorReadsOpenedAndAdmissionEvents() throws {
    let night = Data(#"{"data":{"door":{"__typename":"DoorOpened","night":{"night":"2026-10-10","paidCount":1,"checkedInCount":0,"gross":{"cents":1000,"currency":"usd"},"admissions":{"nodes":[\#(row)]}}}}}"#.utf8)
    guard case .night(let state)? = VenueManagementClient.doorEvent(from: night) else { Issue.record("not a night"); return }
    #expect(state.paidCount == 1 && state.admissions.first?.profile.name == "Alex")

    let scanned = row.replacingOccurrences(of: #""checkedInAt":null,"scanCount":0"#, with: #""checkedInAt":"2026-10-10T06:00:00Z","scanCount":1"#)
    func changed(_ outcome: String) -> Data {
        Data(#"{"data":{"door":{"__typename":"DoorAdmissionChanged","outcome":"\#(outcome)","admission":\#(scanned),"paidCount":1,"checkedInCount":1,"gross":{"cents":1000,"currency":"usd"}}}}"#.utf8)
    }
    guard case .admission(let admission, let outcome, let totals)? = VenueManagementClient.doorEvent(from: changed("ADMIT")) else { Issue.record("not an admission"); return }
    #expect(outcome == "admit" && totals.checkedInCount == 1 && admission.scanCount == 1)
    // The uppercase outcomes become the station's own.
    for (wire, station) in [("PAID", "paid"), ("RE_ENTRY", "re_entry"), ("REFUND", "refund")] {
        guard case .admission(_, let outcome, _)? = VenueManagementClient.doorEvent(from: changed(wire)) else { Issue.record("not an admission"); return }
        #expect(outcome == station)
    }

    let updated = state.applying(admission, totals: totals)
    #expect(updated.admissions.count == 1 && updated.admissions[0].scanCount == 1 && updated.checkedInCount == 1)
    let another = try JSONDecoder().decode(VenueAdmission.self, from: Data(row.replacingOccurrences(of: #""id":"a1""#, with: #""id":"a2""#).utf8))
    let grown = updated.applying(another, totals: VenueDoorTotals(paidCount: 2, checkedInCount: 1, gross: .usd(2000)))
    #expect(grown.gross == Money(cents: 2000, currency: "usd"))
    #expect(grown.admissions.map(\.id) == ["a2", "a1"] && grown.paidCount == 2)

    #expect(VenueManagementClient.doorEvent(from: Data(#"{"data":{"door":{"__typename":"DoorMarquee"}}}"#.utf8)) == nil)
    guard case .rejected? = VenueManagementClient.doorEvent(from: Data(#"{"data":null,"errors":[{"message":"This device does not have permission for that venue operation"}]}"#.utf8))
    else { Issue.record("not rejected"); return }
    guard case .offline(let reason)? = VenueManagementClient.doorEvent(from: AudienceCable.Event.disconnected(reason: "unauthorized", reconnects: false)) else { Issue.record("not offline"); return }
    #expect(reason == "unauthorized")
}

@Test func theDoorSubscriptionSelectsOnlyWhatADeviceMay() {
    let query = VenueManagementClient.doorSubscription
    #expect(query.contains("door(venueId: $id)") && query.contains("... on DoorOpened") && query.contains("... on DoorAdmissionChanged"))
    #expect(query.contains("admissions { nodes { id amount { cents currency }") && query.contains("gross { cents currency }"))
}

// The cable's protocol itself is tested with AudienceCable in the AudienceKit SDK.

@Test func aSessionWithoutAnAudienceHasNothingToFollow() async {
    let session = AudienceManagementSession(baseURL: URL(string: "https://api.test")!, credentialStore: InMemoryCredentialStore())
    var events = await session.subscribe("subscription { door(venueId: \"v1\") { __typename } }").makeAsyncIterator()
    guard case .rejected? = await events.next() else { Issue.record("not rejected"); return }
    #expect(await events.next() == nil)
}

@Test func theSessionsAudienceComesFromItsToken() async {
    let session = AudienceManagementSession(baseURL: URL(string: "https://api.test")!,
                                            credentialStore: InMemoryCredentialStore(credential: makeCredential(audienceID: "aud")))
    #expect(await session.operatingAudienceID == "aud")
}
