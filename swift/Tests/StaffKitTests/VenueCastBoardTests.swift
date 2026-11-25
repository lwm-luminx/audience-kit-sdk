import Foundation
import Testing
@testable import StaffKitCore
@testable import StaffKitServices

// The board Velvet sends the cast receiver (hotmess.social /cast/velvet), which draws whatever it's sent.

private func chat(_ id: String, _ text: String, sent: String = "2026-10-10T05:00:00Z", kind: String = "TEXT",
                  title: String? = nil, venue: Bool = false, automatic: Bool = false, avatar: String? = nil,
                  photo: String? = nil, endsAt: String? = nil) throws -> VenueChatMessage {
    let json: [String: Any?] = [
        "__typename": "VenueMessage", "id": id, "message": text, "body": text, "name": "Sam K.", "avatarUrl": avatar,
        "presence": "ONLINE", "endsAt": endsAt, "sentAt": sent, "userId": "u1", "role": "GUEST", "kind": kind,
        "title": title, "photoUrl": photo, "pinned": false, "postedAsVenue": venue, "automatic": automatic, "event": nil,
    ]
    let data = try JSONSerialization.data(withJSONObject: json.mapValues { $0 ?? NSNull() })
    return try JSONDecoder().decode(VenueChatMessage.self, from: data)
}

private let venue = VenueCastBoard.Venue(id: "11111111-1111-4111-8111-111111111111", name: "Neighbours",
                                         timeZone: TimeZone(identifier: "America/Los_Angeles")!,
                                         photo: "https://cdn.example/room.jpg")
private let now = parseInstant("2026-10-10T06:00:00Z")!

private func room(_ board: [String: Any]) -> [String: Any]? { board["chat"] as? [String: Any] }
private func texts(_ board: [String: Any]) -> [String] {
    (room(board)?["messages"] as? [[String: Any]] ?? []).compactMap { $0["text"] as? String }
}

@Test func theBoardNamesTheVenueTonightAndItsJoinLink() {
    var board = VenueCastBoard(chat: false)
    board.lineup = [VenueCastBoard.Entry(id: "a", name: "Lola", role: "Performer", time: "10:00 PM", state: .on,
                                         images: ["http://insecure/x.jpg", "https://cdn/1.jpg", "https://cdn/2.jpg", "https://cdn/3.jpg"])]
    let message = board.message(venue: venue, events: ["Mess Hall", ""], at: now)
    #expect(message["type"] as? String == "tonight")
    let place = message["venue"] as? [String: Any]
    #expect(place?["name"] as? String == "Neighbours")
    #expect(place?["timeZone"] as? String == "America/Los_Angeles")
    #expect(place?["photo"] as? String == "https://cdn.example/room.jpg")
    #expect(message["events"] as? [String] == ["Mess Hall"])
    #expect(message["join"] as? String == "https://hotmess.social/v/2FbpUzu8")
    let row = (message["lineup"] as? [[String: Any]])?.first
    #expect(row?["state"] as? String == "on")
    // Only https faces, two at most.
    #expect(row?["images"] as? [String] == ["https://cdn/1.jpg", "https://cdn/2.jpg"])
    // No chat without moderation, and no slogan slides until the venue's settings say so.
    #expect(message["chat"] == nil)
    #expect(message["slogans"] == nil)
}

@Test func aVenueWithoutAPhotoOrNameStillShows() {
    let plain = VenueCastBoard.Venue(id: "v-1", name: nil, timeZone: TimeZone(identifier: "UTC")!, photo: "javascript:alert(1)")
    let message = VenueCastBoard(chat: false).message(venue: plain, events: [], at: now)
    let place = message["venue"] as? [String: Any]
    #expect(place?["name"] as? String == "Tonight")
    #expect(place?["photo"] == nil)
    // Not a UUID: the receiver makes the full chat link itself.
    #expect(message["join"] == nil)
}

@Test func sloganSlidesFollowTheVenuesTVSettings() {
    var board = VenueCastBoard(chat: false)
    board.slogans = VenueMarqueeSettings(marqueeSlogans: false, adultVenue: true)
    #expect(board.message(venue: venue, events: [], at: now)["slogans"] == nil)
    board.slogans = VenueMarqueeSettings(marqueeSlogans: true, adultVenue: true)
    let none = board.message(venue: venue, events: [], at: now)["slogans"] as? [String: Any]
    #expect(none?["adult"] as? Bool == true)
    // No posters for the venue's audience: an empty list, so the receiver shows none rather than its own.
    #expect((none?["slides"] as? [[String: Any]])?.isEmpty == true)
    let posters = [MarqueeSlide(id: "swipe-less", adult: false, image: "https://hotmess.social/m/a.jpg"),
                   MarqueeSlide(id: "daddy-issues", adult: false, image: "https://hotmess.social/m/b.jpg"),
                   MarqueeSlide(id: "cheeky", adult: true, image: "https://hotmess.social/m/c.jpg")]
    board.slogans = VenueMarqueeSettings(marqueeSlogans: true, adultVenue: false, hiddenSlogans: ["daddy-issues"],
                                         posters: posters)
    let slogans = board.message(venue: venue, events: [], at: now)["slogans"] as? [String: Any]
    #expect(slogans?["hidden"] as? [String] == ["daddy-issues"])
    let slides = slogans?["slides"] as? [[String: Any]]
    #expect(slides?.compactMap { $0["id"] as? String } == ["swipe-less"])
    #expect(slides?.first?["image"] as? String == "https://hotmess.social/m/a.jpg")
}

@Test func shortLinksMatchTheSiteAndTheAPI() {
    // Same codes as hotmess.social src/lib/venueShortLink.ts and Velvet Android's venueJoinLink.
    #expect(venueShortLink("ffffffff-ffff-4fff-8fff-ffffffffffff") == "https://hotmess.social/v/DXLgGAi3")
    #expect(venueShortLink("a52a0862-e4f4-4113-a513-f425a4161f58") == "https://hotmess.social/v/pMAeFhUe")
    #expect(venueShortLink("3f2a9c1e-7b4d-4e8a-9c3b-1d2e3f4a5b6c") == "https://hotmess.social/v/9Rn77sFM")
    #expect(venueShortLink("00000000-0000-0000-0000-000000000000") == "https://hotmess.social/v/00000000")
    #expect(venueShortLink("v-1") == nil)
    #expect(venueShortLink("zzzzzzzz-zzzz-zzzz-zzzz-zzzzzzzzzzzz") == nil)
}

@Test func theWallShowsTheRoomAsGuestsSeeItOldestFirst() throws {
    var board = VenueCastBoard(chat: true)
    board.apply(.history([try chat("m2", "second", sent: "2026-10-10T05:02:00Z"),
                          try chat("auto", "Sam joined", automatic: true),
                          try chat("m1", "first", sent: "2026-10-10T05:01:00Z")], pinned: nil))
    #expect(texts(board.message(venue: venue, events: [], at: now)) == ["first", "second"])

    board.apply(.message(try chat("m3", "", sent: "2026-10-10T05:03:00Z", kind: "PHOTO", photo: "https://cdn/p.jpg")))
    board.apply(.message(try chat("m4", "Doors at 9", sent: "2026-10-10T05:04:00Z", kind: "ANNOUNCEMENT",
                                  title: "Tonight", venue: true, avatar: "https://cdn/v.jpg")))
    let rows = room(board.message(venue: venue, events: [], at: now))?["messages"] as? [[String: Any]] ?? []
    #expect(rows.map { $0["text"] as? String } == ["first", "second", "📷 Photo", "Tonight: Doors at 9"])
    #expect(rows[2]["photo"] as? String == "https://cdn/p.jpg")
    #expect(rows[3]["sender"] as? String == "Neighbours")
    #expect(rows[3]["venue"] as? Bool == true)
    #expect(rows[3]["avatar"] as? String == "https://cdn/v.jpg")
    #expect(rows[0]["sender"] as? String == "Sam K.")

    board.apply(.updated(try chat("m1", "first, edited", sent: "2026-10-10T05:01:00Z")))
    board.apply(.removed(id: "m2"))
    #expect(texts(board.message(venue: venue, events: [], at: now)) == ["first, edited", "📷 Photo", "Tonight: Doors at 9"])
}

@Test func theWallKeepsWhatFitsATV() throws {
    var board = VenueCastBoard(chat: true)
    for i in 0..<20 { board.apply(.message(try chat("m\(i)", "line \(i)"))) }
    let shown = texts(board.message(venue: venue, events: [], at: now))
    #expect(shown.count == VenueCastBoard.keep)
    #expect(shown.last == "line 19")
    #expect(shown.first == "line 8")
}

@Test func expiryClearingAndSpecialsLeaveTheWallAsTheyLeaveTheRoom() throws {
    var board = VenueCastBoard(chat: true)
    let pin = try chat("p", "Drag brunch Sunday", kind: "ANNOUNCEMENT", title: "Brunch", venue: true)
    board.apply(.history([try chat("new", "new", sent: "2026-10-10T05:30:00Z"),
                          try chat("special", "2-for-1", sent: "2026-10-10T05:10:00Z", kind: "SPECIAL",
                               endsAt: "2026-10-10T05:59:00Z"),
                          try chat("old", "old", sent: "2026-10-10T04:00:00Z")], pinned: pin))
    var message = board.message(venue: venue, events: [], at: now)
    #expect(room(message)?["pinned"] as? String == "Brunch")
    // The special ended before now.
    #expect(texts(message) == ["old", "new"])

    // Staff are sent older history; guests no longer see it.
    board.apply(.expiry(before: "2026-10-10T05:00:00Z"))
    #expect(texts(board.message(venue: venue, events: [], at: now)) == ["new"])

    // Messages expiring keep the pin; an admin clearing takes it.
    board.apply(.cleared(before: "2026-10-10T05:30:00Z", expired: true))
    message = board.message(venue: venue, events: [], at: now)
    #expect(texts(message).isEmpty && room(message)?["pinned"] as? String == "Brunch")
    board.apply(.cleared(before: "2026-10-10T05:30:00Z", expired: false))
    #expect(room(board.message(venue: venue, events: [], at: now))?["pinned"] == nil)

    board.apply(.pinned(pin))
    board.apply(.updated(try chat("p", "Brunch moved", kind: "ANNOUNCEMENT", title: nil, venue: true)))
    #expect(room(board.message(venue: venue, events: [], at: now))?["pinned"] as? String == "Brunch moved")
    board.apply(.unpinned(id: "p"))
    #expect(room(board.message(venue: venue, events: [], at: now))?["pinned"] == nil)
}

@Test func aRoomThatTurnsTheDeviceAwayLeavesTheTV() throws {
    var board = VenueCastBoard(chat: true)
    board.apply(.message(try chat("m1", "hi")))
    board.apply(.left)
    #expect(!board.chat)
    #expect(board.message(venue: venue, events: [], at: now)["chat"] == nil)
}

@Test func theLineupShowsWhatsOnThenFinishedSetsWhileTheresRoom() {
    let sets = (0..<12).map { (id: $0, done: $0 < 6) }
    let shown = VenueCastBoard.visible(sets, isDone: \.done).map(\.id)
    // 6 still to come leave room for the last 2 finished.
    #expect(shown == [4, 5, 6, 7, 8, 9, 10, 11])
    let late = (0..<12).map { (id: $0, done: $0 < 11) }
    #expect(VenueCastBoard.visible(late, isDone: \.done).map(\.id) == Array(4...11))
}

@Test func theTextIsJSONTheReceiverReads() throws {
    let text = try #require(VenueCastBoard(chat: true).text(venue: venue, events: ["Mess Hall"], at: now))
    let decoded = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    #expect(decoded["type"] as? String == "tonight")
    #expect((decoded["chat"] as? [String: Any])?["messages"] as? [Any] != nil)
}
