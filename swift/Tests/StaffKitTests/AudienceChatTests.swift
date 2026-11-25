import Foundation
import Testing
import AudienceKit
import StaffKitCore
import StaffKitServices

private func adminChat(_ stub: Stub) -> AudienceChatClient {
    AudienceChatClient(session: AudienceManagementSession(baseURL: stub.baseURL, credentialStore: InMemoryCredentialStore(credential: makeCredential(audienceID: "audience", on: stub.baseURL)), session: stub.session))
}
private func request(_ stub: Stub) throws -> (query: String, variables: [String: Any], input: [String: Any]) {
    let body = try #require(stub.requests.last).jsonBody()
    let variables = body["variables"] as? [String: Any] ?? [:]
    return (body["query"] as? String ?? "", variables, variables["input"] as? [String: Any] ?? [:])
}
private let guestLine = #"{"id":"m1","message":"Hi","body":"Hi","name":"Aurora Borealis","avatarUrl":null,"presence":"ONLINE","endsAt":null,"sentAt":"2026-10-10T04:00:00Z","userId":"guest","role":null,"kind":"TEXT","title":null,"photoUrl":null,"pinned":false,"postedAsVenue":false,"automatic":false,"event":null,"member":{"id":"membership","canModerate":true,"bannedAt":null}}"#
private let staffLine = #"{"id":"m2","message":"Be kind","body":"Be kind","name":"Rick Mark","sentAt":"2026-10-10T04:01:00Z","userId":"admin","role":"STAFF","kind":"TEXT","pinned":false,"postedAsVenue":false,"automatic":false,"event":null,"member":{"id":"me","canModerate":false,"bannedAt":null}}"#

@Test func roomsListVenuesAndLocalesWithTheirLatestMessage() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"""
    {"data":{"chat":{"rooms":{"nodes":[
      {"id":"v1","name":"Purr","lastMessage":"Hi","lastMessageAt":"2026-10-10T04:00:00.123Z","lastMessageName":"Aurora Borealis","recentCount":1,"onlineCount":2,"venue":{"id":"v1","photoUrl":null,"tickets":{"cover":{"timeZone":"America/Chicago"}},"locale":{"id":"l1","name":"Chicago"}},"locale":null},
      {"id":"l1","name":"Chicago","lastMessage":null,"lastMessageAt":null,"lastMessageName":null,"recentCount":0,"onlineCount":0,"venue":null,"locale":{"id":"l1","name":"Chicago"}}
    ]}}}}
    """#) }
    let rooms = try await adminChat(stub).rooms()
    #expect(rooms.map(\.id) == ["v1", "l1"])
    #expect(rooms[0].address == .venue("v1"))
    #expect(rooms[0].timeZone.identifier == "America/Chicago")
    #expect(rooms[0].lastMessageDate != nil)
    #expect(rooms[0].venue?.locale?.name == "Chicago")
    #expect(rooms[1].address == .locale("l1"))
    #expect(rooms[1].lastMessage == nil)
    #expect(rooms[1].timeZone == .current)
    let query = try request(stub).query
    #expect(query.contains("chat {") && query.contains("rooms {"))
    #expect(query.contains("lastMessageAt lastMessageName recentCount onlineCount"))
}

@Test func venueTranscriptsCarryTheSendersMembership() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{"chat":{"venueMessages":{"edges":[{"node":\#(guestLine)},{"node":\#(staffLine)}],"pageInfo":{"hasNextPage":true,"endCursor":"c50"}}}}}"#) }
    let page = try await adminChat(stub).messages(in: .venue("v1"))
    #expect(page.edges.count == 2)
    #expect(page.edges[0].node.member == AudienceChatMember(id: "membership", canModerate: true))
    #expect(page.edges[1].node.member?.canModerate == false)
    #expect(page.pageInfo.endCursor == "c50")
    let (query, variables, _) = try request(stub)
    #expect(query.contains("venueMessages(venueId: $id, first: $first, after: $after)"))
    #expect(query.contains("member { id canModerate bannedAt }"))
    #expect(query.contains("automatic"))
    #expect(variables["id"] as? String == "v1")
    #expect(variables["first"] as? Int == 50)
    #expect(variables["after"] is NSNull)
}

@Test func localeTranscriptsPageOlder() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{"chat":{"localeMessages":{"edges":[{"node":\#(guestLine)}],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}}"#) }
    let page = try await adminChat(stub).messages(in: .locale("l1"), after: "c50", first: 500)
    #expect(page.edges.first?.node.member?.id == "membership")
    #expect(page.pageInfo.hasNextPage == false)
    let (query, variables, _) = try request(stub)
    #expect(query.contains("localeMessages(localeId: $id, first: $first, after: $after)"))
    #expect(variables["after"] as? String == "c50")
    // The API pages at most 100.
    #expect(variables["first"] as? Int == 100)
}

@Test func messagesWithoutAMembershipDecode() throws {
    let message = try JSONDecoder().decode(VenueChatMessage.self, from: Data(#"{"id":"m","message":"Hi","sentAt":"2026-10-10T04:00:00Z","userId":"u","kind":"TEXT","pinned":false,"postedAsVenue":false,"member":null}"#.utf8))
    #expect(message.member == nil)
    let banned = try JSONDecoder().decode(AudienceChatMember.self, from: Data(#"{"id":"m","canModerate":true,"bannedAt":"2026-10-10T04:00:00Z"}"#.utf8))
    #expect(banned.isBanned)
}

@Test func pinnedMessageIsAskedOfVenuesOnly() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{"venues":{"venue":{"chat":{"pinnedMessage":{"id":"pin","message":"Announcement: Patio","body":"","sentAt":"2026-10-01T04:00:00Z","userId":"u","kind":"ANNOUNCEMENT","title":"Patio","pinned":true,"postedAsVenue":false,"automatic":false,"event":null,"member":null}}}}}}"#) }
    let client = adminChat(stub)
    #expect(try await client.pinnedMessage(in: .venue("v1"))?.title == "Patio")
    #expect(try await client.pinnedMessage(in: .locale("l1")) == nil)
    #expect(stub.requests.count == 1)
}

@Test func postingAsStaffInALocaleRoom() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{"sendChatMessage":{"venueMessage":null,"localeMessage":\#(staffLine)}}}"#) }
    let sent = try await adminChat(stub).send(in: .locale("l1"), message: "Be kind")
    #expect(sent?.role == "STAFF")
    let (query, _, input) = try request(stub)
    #expect(query.contains("sendChatMessage(input: $input)"))
    #expect(query.contains("localeMessage {"))
    #expect(input.keys.sorted() == ["kind", "localeId", "message"])
    #expect(input["kind"] as? String == "TEXT")
    #expect(input["localeId"] as? String == "l1")
}

@Test func postingAPinnedAnnouncementAsTheVenue() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{"sendChatMessage":{"venueMessage":\#(staffLine),"localeMessage":null}}}"#) }
    _ = try await adminChat(stub).send(in: .venue("v1"), message: "Grab your things", asVenue: true, kind: "ANNOUNCEMENT",
                                       title: "Coat check closes at midnight", pinned: true)
    let input = try request(stub).input
    #expect(input["venueId"] as? String == "v1")
    #expect(input["asVenue"] as? Bool == true)
    #expect(input["pinned"] as? Bool == true)
    #expect(input["kind"] as? String == "ANNOUNCEMENT")
    #expect(input["title"] as? String == "Coat check closes at midnight")
    #expect(input["localeId"] == nil)
}

@Test func moderatingMessagesAndRooms() async throws {
    let stub = Stub { request in
        let query = (try? request.jsonBody()["query"] as? String) ?? ""
        if query.contains("clearChatRoom") { return .json(status: 200, body: #"{"data":{"clearChatRoom":{"removedCount":7}}}"#) }
        if query.contains("removeChatMessage") { return .json(status: 200, body: #"{"data":{"removeChatMessage":{"deletedId":"m1"}}}"#) }
        return .json(status: 200, body: #"{"data":{"pinChatMessage":{"venueMessage":{"id":"m1","pinned":false},"localeMessage":null}}}"#)
    }
    let client = adminChat(stub)

    try await client.pin(messageID: "m1", pinned: false)
    var (query, _, input) = try request(stub)
    #expect(query.contains("pinChatMessage(input: $input)"))
    #expect(query.contains("ChatMessagePinInput!"))
    #expect(input["id"] as? String == "m1")
    #expect(input["pinned"] as? Bool == false)

    try await client.remove(messageID: "m1")
    (query, _, input) = try request(stub)
    #expect(query.contains("removeChatMessage(input: $input) { deletedId }"))
    #expect(input.keys.sorted() == ["id"])

    #expect(try await client.clear(.locale("l1")) == 7)
    (query, _, input) = try request(stub)
    #expect(query.contains("ChatRoomClearInput!"))
    #expect(input.keys.sorted() == ["localeId"])
}

@Test func kickingAndBanningUseTheMembership() async throws {
    let stub = Stub { request in
        let query = (try? request.jsonBody()["query"] as? String) ?? ""
        let field = ["kickAudienceMember", "unbanAudienceMember", "banAudienceMember"].first { query.contains($0) } ?? ""
        let banned = field == "banAudienceMember" ? #""2026-10-10T04:00:00Z""# : "null"
        return .json(status: 200, body: #"{"data":{"\#(field)":{"member":{"id":"membership","canModerate":true,"bannedAt":\#(banned)}}}}"#)
    }
    let client = adminChat(stub)

    #expect(try await client.kick(memberID: "membership").isBanned == false)
    var (query, _, input) = try request(stub)
    #expect(query.contains("kickAudienceMember(input: $input)"))
    #expect(query.contains("AudienceMemberKickInput!"))
    #expect(input.keys.sorted() == ["id"])

    #expect(try await client.ban(memberID: "membership", reason: "  Spam  ").isBanned)
    (query, _, input) = try request(stub)
    #expect(query.contains("banAudienceMember(input: $input)"))
    #expect(input["reason"] as? String == "Spam")

    _ = try await client.ban(memberID: "membership", reason: "   ")
    #expect(try request(stub).input.keys.sorted() == ["id"])

    #expect(try await client.unban(memberID: "membership").isBanned == false)
    (query, _, _) = try request(stub)
    #expect(query.contains("unbanAudienceMember(input: $input)"))
}

@Test func refusalsComeBackAsErrors() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"{"data":null,"errors":[{"message":"Administrator access required"}]}"#) }
    await #expect(throws: (any Error).self) { try await adminChat(stub).rooms() }
}

@Test func roomsCarryTheirPointsAndTheClosestPrefersTheVenueYouAreAt() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"""
    {"data":{"chat":{"rooms":{"nodes":[
      {"id":"v1","name":"Purr","recentCount":0,"onlineCount":0,"venue":{"id":"v1","point":"SRID=4326;POINT (-87.6500 41.9400)","locale":{"id":"l1","name":"Chicago"}},"locale":null},
      {"id":"v2","name":"Far","recentCount":0,"onlineCount":0,"venue":{"id":"v2","point":"POINT (-87.7000 41.9000)"},"locale":null},
      {"id":"v3","name":"Nowhere","recentCount":0,"onlineCount":0,"venue":{"id":"v3","point":null},"locale":null},
      {"id":"l1","name":"Chicago","recentCount":0,"onlineCount":0,"venue":null,"locale":{"id":"l1","name":"Chicago","chatRetentionMinutes":240,"location":{"point":"POINT (-87.6298 41.8781)"}}}
    ]}}}}
    """#) }
    let rooms = try await adminChat(stub).rooms()
    #expect(rooms[0].coordinate?.latitude == 41.94)
    #expect(rooms[3].coordinate?.longitude == -87.6298)
    #expect(rooms[2].coordinate == nil)
    let query = try request(stub).query
    #expect(query.contains("venue { id photoUrl point"))
    #expect(query.contains("locale { id name chatRetentionMinutes location { point } }"))
    #expect(rooms[3].guestWindow?.retention == TimeInterval(4 * 60 * 60))
    #expect(rooms[0].guestWindow == nil)
    // A few metres from Purr: its room.
    #expect(AudienceChatRoom.closest(in: rooms, latitude: 41.9401, longitude: -87.6501)?.id == "v1")
    // Out in the city, away from any venue: the locale's small talk, though a venue is nearer than its centre.
    #expect(AudienceChatRoom.closest(in: rooms, latitude: 41.9200, longitude: -87.6600)?.id == "l1")
    // No locale has a point: the nearest venue.
    #expect(AudienceChatRoom.closest(in: Array(rooms.prefix(3)), latitude: 41.9200, longitude: -87.6600)?.id == "v1")
    #expect(AudienceChatRoom.closest(in: [rooms[2]], latitude: 0, longitude: 0) == nil)
}
