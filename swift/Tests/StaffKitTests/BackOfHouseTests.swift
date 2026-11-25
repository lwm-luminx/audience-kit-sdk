import Foundation
import Testing
import AudienceKit
@testable import StaffKitCore
@testable import StaffKitServices

private func rooms(_ stub: Stub) -> RoomsClient {
    let session = AudienceManagementSession(baseURL: stub.baseURL, credentialStore: InMemoryCredentialStore(credential: makeCredential(audienceID: "audience", on: stub.baseURL)), session: stub.session)
    return RoomsClient(session: session, transfer: stub.session)
}
private func graphQLRequest(_ stub: Stub) throws -> (query: String, variables: [String: Any], input: [String: Any]) {
    let body = try #require(stub.requests.last { $0.method == "POST" }).jsonBody()
    let variables = body["variables"] as? [String: Any] ?? [:]
    return (body["query"] as? String ?? "", variables, variables["input"] as? [String: Any] ?? [:])
}
private let poster = #"{"id":"f1","name":"Mess Hall poster.png","kind":"IMAGE","label":null,"byteSize":"1887436","contentType":"image/png","url":"https://bucket.test/f1","uploaderName":"Lady Bunny Hop","createdAt":"2026-10-21T20:00:00Z","promotedAt":null,"viewerCanPromote":true,"viewerCanRemove":true,"appearance":null}"#
private let post = #"{"id":"m1","kind":"POST","title":"Run of show","body":"Doors at nine","authorName":"The Wildrose","avatarUrl":null,"createdAt":"2026-10-21T20:00:00Z","editedAt":null,"pinned":true,"replyCount":1,"mine":false,"viewerCanManage":false,"postedAsVenue":true,"parentId":null,"person":null,"appearance":null,"files":[\#(poster)],"replies":[{"id":"r1","body":"Got it","authorName":"Miss Conduct","avatarUrl":null,"createdAt":"2026-10-21T20:05:00Z","mine":true,"viewerCanManage":true,"postedAsVenue":false,"files":[]}]}"#

@Test func backOfHouseReadsAnEventsRoom() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"""
    {"data":{"events":{"event":{"id":"e1","rooms":{"backOfHouse":{
      "id":"r1","name":"Mess Hall","expiresAt":"2026-10-23T08:00:00Z","viewerCanPostAsVenue":false,
      "viewerPeople":[{"id":"p1","name":"Lady Bunny Hop","avatarUrl":null}],
      "event":{"id":"e1","name":"Mess Hall","startAt":"2026-10-22T04:00:00Z","endAt":null},
      "venue":{"id":"v1","name":"The Wildrose","photoUrl":null},
      "members":[{"userId":"u1","name":"Kim Lee","role":"VENUE","avatarUrl":null,"people":[]}],
      "files":{"nodes":[\#(poster)]},
      "lineup":[{"needsTrack":true,"trackStatus":"MISSING","viewerCanNudge":false,"viewerCanSetNeedsTrack":true,"viewerCanAttachTrack":true,"tracks":[],
        "appearance":{"id":"a1","kind":"ACT","role":"PERFORMER","title":null,"startsAt":"2026-10-22T06:30:00Z","startTiming":"SOFT","state":"UPCOMING","people":{"nodes":[{"id":"p1","name":"Lady Bunny Hop"}]}}}],
      "checklist":[{"id":"c1","title":"Run of show shared","note":null,"done":false,"doneAt":null,"doneByName":null,"auto":"RUN_OF_SHOW","viewerCanChange":false}]
    }}}}}}
    """#) }
    let room = try #require(try await rooms(stub).room(.event("e1")))
    #expect(room.id == "r1")
    #expect(room.isEvent)
    #expect(room.who == "The Wildrose staff and the night’s lineup")
    #expect(room.files.nodes.first?.byteSize == 1_887_436)
    #expect(room.files.nodes.first?.sizeText == "1.8 MB")
    let slot = try #require(room.lineup.first)
    #expect(slot.name == "Lady Bunny Hop")
    #expect(slot.trackTitle == "No track yet")
    #expect(slot.time(in: TimeZone(identifier: "America/Los_Angeles")!).hasPrefix("around "))
    #expect(room.checklist.first?.auto == "RUN_OF_SHOW")
    let (query, variables, _) = try graphQLRequest(stub)
    #expect(query.contains("events { event(id: $id)"))
    #expect(query.contains("rooms { backOfHouse {"))
    #expect(!query.contains("messages("))
    #expect(variables["id"] as? String == "e1")
}

@Test func backOfHouseReadsAVenuesConversation() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{"venues":{"venue":{"id":"v1","rooms":{"backOfHouse":{"id":"r2","messages":{"nodes":[\#(post)]}}}}}}}"#) }
    let messages = try await rooms(stub).messages(in: .venue("v1"))
    let message = try #require(messages.first)
    #expect(message.isPost && message.pinned && message.postedAsVenue)
    #expect(message.files.first?.isImage == true)
    #expect(message.replies.first?.mine == true)
    let (query, _, _) = try graphQLRequest(stub)
    #expect(query.contains("venues { venue(id: $id)"))
    #expect(query.contains("messages(first: 15)"))
}

@Test func backOfHouseReadsALocalesRoomOfEveryVenuesStaff() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"""
    {"data":{"locale":{"id":"l1","rooms":{"backOfHouse":{
      "id":"r9","name":"Seattle","expiresAt":null,"viewerCanPostAsVenue":true,"viewerPeople":[],
      "viewerVenues":[{"id":"v1","name":"The Wildrose","photoUrl":null}],
      "event":null,"venue":null,"locale":{"id":"l1","name":"Seattle"},
      "members":[{"userId":"u1","name":"Kim Lee","role":"LOCALE","avatarUrl":null,"people":[],"venues":[]},
                 {"userId":"u2","name":"Bo Back","role":"STAFF","avatarUrl":null,"people":[],"venues":[{"id":"v2","name":"The Cuff","photoUrl":null}]}],
      "files":{"nodes":[]},"lineup":[],"checklist":[]
    }}}}}
    """#) }
    let room = try #require(try await rooms(stub).room(.locale("l1")))
    #expect(room.isLocale && !room.isEvent)
    #expect(room.who == "Staff across Seattle")
    #expect(room.postingVenues.map(\.id) == ["v1"])
    #expect(room.members.first?.roleTitle == "City")
    #expect(room.members.last?.venues?.first?.name == "The Cuff")
    let (query, variables, _) = try graphQLRequest(stub)
    #expect(query.contains("locale(id: $id)"))
    #expect(query.contains("viewerVenues {"))
    #expect(variables["id"] as? String == "l1")

    let summary = try JSONDecoder().decode(RoomSummary.self, from: Data(#"{"id":"r9","name":"Seattle","lastMessageAt":null,"expiresAt":null,"event":null,"venue":null,"locale":{"id":"l1","name":"Seattle"}}"#.utf8))
    #expect(summary.place == .locale("l1"))
    #expect(RoomPush(userInfo: ["kind": "room_message", "room_id": "r9", "locale_id": "l1"])?.place == .locale("l1"))
}

@Test func backOfHousePostsAsOneOfTheirVenuesInALocalesRoom() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{"sendRoomMessage":{"message":\#(post)}}}"#) }
    try await rooms(stub).send(roomID: "r9", body: "Anyone have spare ice?", as: .venueID("v1"))
    let (_, _, input) = try graphQLRequest(stub)
    #expect(input["asVenueId"] as? String == "v1")
    #expect(input["asVenue"] == nil)
}

@Test func backOfHousePostsAsTheVenueOrATalent() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{"sendRoomMessage":{"message":\#(post)}}}"#) }
    let client = rooms(stub)
    try await client.send(roomID: "r1", body: "Doors at nine", kind: "POST", title: "Run of show", pinned: true, fileIDs: ["f1"], as: .venue)
    var (_, _, input) = try graphQLRequest(stub)
    #expect(input["roomId"] as? String == "r1")
    #expect(input["kind"] as? String == "POST")
    #expect(input["title"] as? String == "Run of show")
    #expect(input["pinned"] as? Bool == true)
    #expect(input["fileIds"] as? [String] == ["f1"])
    #expect(input["asVenue"] as? Bool == true)
    #expect(input["asPersonId"] == nil)

    try await client.send(roomID: "r1", body: "On my way", replyTo: "m1", as: .person(id: "p1"))
    (_, _, input) = try graphQLRequest(stub)
    #expect(input["kind"] as? String == "MESSAGE")
    #expect(input["replyToId"] as? String == "m1")
    #expect(input["asPersonId"] as? String == "p1")
    #expect(input["asVenue"] == nil)
    #expect(input["pinned"] == nil)
}

@Test func backOfHouseUploadsStraightToStorage() async throws {
    let track = poster.replacingOccurrences(of: #""kind":"IMAGE""#, with: #""kind":"AUDIO""#)
        .replacingOccurrences(of: "image/png", with: "audio/mpeg")
    let base = BaseBox()
    let stub = Stub { request in
        if request.method == "PUT" { return .json(status: 200, body: "") }
        let query = (try? request.jsonBody())?["query"] as? String ?? ""
        if query.contains("startRoomUpload") {
            return .json(status: 200, body: #"{"data":{"startRoomUpload":{"file":\#(track),"uploadUrl":"\#(base.url)/private/rooms/r1/f1/track.mp3?X-Amz-Signature=x"}}}"#)
        }
        return .json(status: 200, body: #"{"data":{"finishRoomUpload":{"file":\#(track)}}}"#)
    }
    base.url = stub.baseURL.absoluteString
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("track-\(UUID().uuidString).mp3")
    try Data(repeating: 7, count: 2048).write(to: file)
    defer { try? FileManager.default.removeItem(at: file) }

    let uploaded = try await rooms(stub).upload(file, name: "track.mp3", contentType: "audio/mpeg", in: "r1", appearanceID: "a1")
    #expect(uploaded.isAudio)
    let methods = stub.requests.map(\.method)
    #expect(methods == ["POST", "PUT", "POST"])
    let put = try #require(stub.requests.first { $0.method == "PUT" })
    #expect(put.path == "/private/rooms/r1/f1/track.mp3")
    #expect(put.header("Content-Type") == "audio/mpeg")
    #expect(put.header("Authorization") == nil)
    let start = try #require(stub.requests.first).jsonBody()
    let input = (start["variables"] as? [String: Any])?["input"] as? [String: Any] ?? [:]
    #expect(input["byteSize"] as? String == "2048")
    #expect(input["appearanceId"] as? String == "a1")
    #expect(input["filename"] as? String == "track.mp3")
}

/// The stub's address, which its handler needs before the stub exists.
private final class BaseBox: @unchecked Sendable { var url = "" }

@Test func backOfHouseSizesFilesAsTheAppsShowThem() async throws {
    #expect(RoomsClient.maxFileSize == 200 * 1024 * 1024)
    #expect(RoomFile.size(140 * 1024) == "140 KB")
    #expect(RoomFile.size(12 * 1024 * 1024) == "12 MB")
}

@Test func backOfHouseFeedSaysWhatChanged() {
    let added = Data(#"{"data":{"room":{"change":"ADDED","messageId":"m1","message":\#(post)}}}"#.utf8)
    guard case .added(let message)? = RoomsClient.feedEvents(from: added).first else { Issue.record("Not added"); return }
    #expect(message.id == "m1")
    let removed = Data(#"{"data":{"room":{"change":"REMOVED","messageId":"m1","message":null}}}"#.utf8)
    guard case .removed(let id)? = RoomsClient.feedEvents(from: removed).first else { Issue.record("Not removed"); return }
    #expect(id == "m1")
    let refused = Data(#"{"data":null,"errors":[{"message":"This room has closed"}]}"#.utf8)
    guard case .rejected? = RoomsClient.feedEvents(from: refused).first else { Issue.record("Not rejected"); return }
}

@Test func backOfHouseReadsARoomPush() {
    let event = RoomPush(userInfo: ["kind": "room_message", "room_id": "r1", "message_id": "m1", "event_id": "e1",
                                    "venue_id": "v1", "audience_id": "a1"])
    #expect(event?.place == .event("e1"))
    #expect(event?.roomID == "r1")
    #expect(event?.audienceID == "a1")
    #expect(RoomPush(userInfo: ["kind": "room_message", "room_id": "r2", "venue_id": "v1"])?.place == .venue("v1"))
    #expect(RoomPush(userInfo: ["kind": "event_reminder", "event_id": "e1", "audience_id": "a1"]) == nil)
    #expect(RoomPush(userInfo: ["kind": "room_message", "room_id": "r3"]) == nil)
}

@Test func backOfHouseReadsTheServersAudioCheck() throws {
    let track = try JSONDecoder().decode(RoomFile.self, from: Data(#"""
    {"id":"f2","name":"reveal mix.mp3","kind":"AUDIO","label":null,"byteSize":"6501171","contentType":"audio/mpeg","url":"https://bucket.test/f2","uploaderName":"Lady Bunny Hop","createdAt":"2026-10-23T15:00:00Z","promotedAt":null,"viewerCanPromote":false,"viewerCanRemove":true,"appearance":{"id":"a1"},"durationSeconds":243,"audioStatus":"READY","audioError":null,"waveform":[10,20,30,40,50,60,70,80,90,100,0,5]}
    """#.utf8))
    #expect(track.durationText == "4:03")
    #expect(track.waveformBars(6) == [0.2, 0.4, 0.6, 0.8, 1.0, 0.05])
    #expect(track.waveformBars(24).count == 24)
    #expect(!track.audioRejected)
    #expect(RoomsClient.fileFields.contains("audioStatus audioError waveform"))

    let rejected = try JSONDecoder().decode(RoomFile.self, from: Data(#"""
    {"id":"f3","name":"cover.mp3","kind":"AUDIO","byteSize":"20","contentType":"audio/mpeg","createdAt":"2026-10-23T15:00:00Z","durationSeconds":null,"audioStatus":"REJECTED","audioError":"This file has no sound in it.","waveform":null}
    """#.utf8))
    #expect(rejected.audioRejected)
    #expect(rejected.waveformBars(20).isEmpty)
    #expect(rejected.durationText == nil)
}
