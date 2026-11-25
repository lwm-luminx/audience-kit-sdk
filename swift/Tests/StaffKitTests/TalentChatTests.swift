import Foundation
import Testing
import AudienceKit
@testable import StaffKitCore
@testable import StaffKitServices

private func talent(_ stub: Stub) -> TalentManagementClient {
    TalentManagementClient(session: AudienceManagementSession(baseURL: stub.baseURL, credentialStore: InMemoryCredentialStore(credential: makeCredential(audienceID: "audience", on: stub.baseURL)), session: stub.session))
}
private func request(_ stub: Stub) throws -> (query: String, variables: [String: Any], input: [String: Any]) {
    let body = try #require(stub.requests.last).jsonBody()
    let variables = body["variables"] as? [String: Any] ?? [:]
    return (body["query"] as? String ?? "", variables, variables["input"] as? [String: Any] ?? [:])
}
private let hostLine = #"{"id":"m1","message":"Doors at nine","body":"Doors at nine","name":"Miss Texas","avatarUrl":null,"presence":null,"endsAt":null,"sentAt":"2026-10-11T04:00:00Z","userId":"ty","role":"HOST","kind":"TEXT","title":null,"photoUrl":null,"pinned":false,"postedAsVenue":false,"automatic":false,"event":null,"postedAsPerson":true,"person":{"id":"miss-texas"}}"#

@Test func talentListsThePersonsRooms() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"""
    {"data":{"people":{"person":{"chat":{"rooms":{"nodes":[
      {"id":"v1","name":"Purr","lastMessage":"Hi","lastMessageAt":null,"lastMessageName":null,"recentCount":1,"onlineCount":2,"venue":{"id":"v1","photoUrl":null,"tickets":{"cover":{"timeZone":"America/Los_Angeles"}},"locale":null},"locale":null}
    ]}}}}}}
    """#) }
    let rooms = try await talent(stub).chatRooms(personID: "miss-texas")
    #expect(rooms.map(\.address) == [.venue("v1")])
    let (query, variables, _) = try request(stub)
    #expect(query.contains("person(id: $id)"))
    #expect(query.contains("chat {") && query.contains("rooms {"))
    #expect(variables["id"] as? String == "miss-texas")
}

@Test func talentReadsWhoPostedAsAPerson() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{"chat":{"localeMessages":{"edges":[{"node":\#(hostLine)}],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}}"#) }
    let messages = try await talent(stub).chatMessages(in: .locale("l1"))
    #expect(messages.first?.postedAsPerson == true)
    #expect(messages.first?.personId == "miss-texas")
    let (query, _, _) = try request(stub)
    #expect(query.contains("localeMessages(localeId: $id, first: $first)"))
    #expect(query.contains("postedAsPerson person { id }"))
}

@Test func talentPostsAsThePerson() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{"sendChatMessage":{"venueMessage":\#(hostLine),"localeMessage":null}}}"#) }
    let sent = try await talent(stub).sendChat(as: "miss-texas", in: .venue("v1"), message: "", kind: "EVENT", eventID: "e1")
    #expect(sent?.role == "HOST")
    let (_, _, input) = try request(stub)
    #expect(input["venueId"] as? String == "v1")
    #expect(input["asPersonId"] as? String == "miss-texas")
    #expect(input["kind"] as? String == "EVENT")
    #expect(input["eventId"] as? String == "e1")
    #expect(input["photo"] == nil)
}

@Test func roomEventsSayWhenAPersonPosted() {
    let result = Data(#"{"data":{"venueChat":{"__typename":"ChatMessagePosted","message":\#(hostLine)}}}"#.utf8)
    guard case .message(let message)? = VenueManagementClient.chatEvents(from: result).first else { Issue.record("Not a message"); return }
    #expect(message.postedAsPerson)
    #expect(message.personId == "miss-texas")
    #expect(message.role == "HOST")
}
