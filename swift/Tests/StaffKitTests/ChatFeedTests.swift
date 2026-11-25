import Foundation
import Testing
@testable import StaffKitCore
@testable import StaffKitServices

private let line = #"{"__typename":"VenueMessage","id":"m1","message":"hello","body":"hello","name":"Rick M.","avatarUrl":null,"presence":"ONLINE","endsAt":null,"sentAt":"2026-10-10T05:00:00Z","userId":"u1","role":"STAFF","kind":"TEXT","title":null,"photoUrl":null,"pinned":false,"postedAsVenue":false,"automatic":false,"event":null}"#
private let announcement = #"{"__typename":"VenueMessage","id":"m2","message":"Announcement: Doors at 9","body":"","name":"Purr","avatarUrl":"https://cdn/p.jpg","presence":"OFFLINE","endsAt":null,"sentAt":"2026-10-10T05:01:00Z","userId":"u2","role":"STAFF","kind":"ANNOUNCEMENT","title":"Doors at 9","photoUrl":null,"pinned":true,"postedAsVenue":true,"automatic":false,"event":{"id":"e1","name":"Sunset Social","startAt":"2026-10-11T04:00:00Z","endAt":null,"venue":{"name":"Purr"},"bannerUrl":null}}"#

/// A `venueChat` subscription result carrying one event.
private func result(_ event: String, field: String = "venueChat") -> Data {
    Data(#"{"data":{"\#(field)":\#(event)}}"#.utf8)
}

@Test func theRoomsAreFollowedBySubscriptions() {
    let (venue, venueVariables) = VenueManagementClient.chatSubscription(for: .venue("v1"), withPeople: true)
    #expect(venue.contains("venueChat(venueId: $id)") && venueVariables == ["id": .string("v1")])
    #expect(venue.contains("... on VenueMessage {") && venue.contains("postedAsPerson person { id }"))
    // The two meanings of `pinned` are aliased apart, so the document validates.
    #expect(venue.contains("pinnedPost: pinned") && venue.contains("isPinned: pinned"))
    let (locale, localeVariables) = VenueManagementClient.chatSubscription(for: .locale("l1"), withPeople: true)
    #expect(locale.contains("localeChat(localeId: $id)") && localeVariables == ["id": .string("l1")])
    // A venue device selects only what its field policy lists.
    let (device, _) = VenueManagementClient.chatSubscription(for: .venue("v1"), withPeople: false)
    #expect(!device.contains("postedAsPerson") && !device.contains("person {"))
}

@Test func aPostedMessageIsTheMessageTheReadsReturn() throws {
    let posted = VenueManagementClient.chatEvents(from: result(#"{"__typename":"ChatMessagePosted","message":\#(line)}"#))
    guard case .message(let message)? = posted.first, posted.count == 1 else { Issue.record("not a message"); return }
    #expect(message.id == "m1" && message.userId == "u1" && message.name == "Rick M." && message.presence == "ONLINE")
    #expect(message.role == "STAFF" && message.kind == "TEXT" && !message.postedAsVenue && !message.pinned)

    let rich = VenueManagementClient.chatEvents(from: result(#"{"__typename":"ChatMessagePosted","message":\#(announcement)}"#, field: "localeChat"))
    guard case .message(let shown)? = rich.first else { Issue.record("not a message"); return }
    #expect(shown.kind == "ANNOUNCEMENT" && shown.title == "Doors at 9" && shown.pinned && shown.postedAsVenue)
    #expect(shown.event?.name == "Sunset Social" && shown.event?.venueName == "Purr" && shown.avatarUrl == "https://cdn/p.jpg")
}

@Test func joiningGivesTheHistoryNewestFirstWithThePinnedAnnouncementAndTheRange() throws {
    let joined = VenueManagementClient.chatEvents(from: result(#"""
        {"__typename":"ChatJoined","outOfRange":true,"history":[{"message":\#(line)},{"message":\#(announcement)}],"pinnedPost":{"message":\#(announcement)}}
        """#))
    guard case .history(let messages, let pinned)? = joined.first else { Issue.record("not history"); return }
    #expect(messages.map(\.id) == ["m2", "m1"] && pinned?.id == "m2")
    guard case .range(let outOfRange)? = joined.last, joined.count == 2 else { Issue.record("no range"); return }
    #expect(outOfRange)

    let dated = VenueManagementClient.chatEvents(from: result(#"{"__typename":"ChatJoined","outOfRange":false,"expiresBefore":"2026-10-09T06:00:00Z","history":[],"pinnedPost":null}"#))
    guard dated.count == 3, case .expiry(let cutoff) = dated[1] else { Issue.record("no expiry"); return }
    #expect(cutoff == "2026-10-09T06:00:00Z")

    let empty = VenueManagementClient.chatEvents(from: result(#"{"__typename":"ChatJoined","outOfRange":false,"history":[],"pinnedPost":null}"#))
    guard case .history(let none, let nothing)? = empty.first else { Issue.record("not history"); return }
    #expect(none.isEmpty && nothing == nil)
}

@Test func theRoomsChangesAreToldApart() throws {
    func one(_ event: String) -> VenueChatEvent? {
        let events = VenueManagementClient.chatEvents(from: result(event))
        return events.count == 1 ? events[0] : nil
    }
    guard case .updated(let edited)? = one(#"{"__typename":"ChatMessageUpdated","message":\#(announcement)}"#)
    else { Issue.record("not an update"); return }
    #expect(edited.id == "m2")
    guard case .removed(let removed)? = one(#"{"__typename":"ChatMessageRemoved","messageId":"m1"}"#) else { Issue.record("not removed"); return }
    #expect(removed == "m1")
    guard case .cleared(let before, let expired)? = one(#"{"__typename":"ChatRoomCleared","clearedAt":"2026-10-10T06:00:00Z"}"#) else { Issue.record("not cleared"); return }
    #expect(before == "2026-10-10T06:00:00Z" && !expired)
    guard case .cleared(_, let aged)? = one(#"{"__typename":"ChatRoomCleared","clearedAt":"2026-10-10T06:00:00Z","expired":true}"#) else { Issue.record("not cleared"); return }
    #expect(aged)
    guard case .pinned(let pinned)? = one(#"{"__typename":"ChatPinChanged","messageId":"m2","isPinned":true,"announcement":\#(announcement)}"#) else { Issue.record("not a pin"); return }
    #expect(pinned.id == "m2" && pinned.pinned)
    guard case .unpinned(let unpinned)? = one(#"{"__typename":"ChatPinChanged","messageId":"m2","isPinned":false,"announcement":null}"#) else { Issue.record("not an unpin"); return }
    #expect(unpinned == "m2")
    guard case .range(let outOfRange)? = one(#"{"__typename":"ChatRangeChanged","outOfRange":true}"#) else { Issue.record("not range"); return }
    #expect(outOfRange)
    guard case .left? = one(#"{"__typename":"ChatLeft","reason":"BANNED"}"#) else { Issue.record("not left"); return }
    // Who comes and goes is for the consumer apps; staff screens skip it.
    #expect(VenueManagementClient.chatEvents(from: result(#"{"__typename":"ChatPresenceChanged","userId":"u1","presence":"OFFLINE"}"#)).isEmpty)
    #expect(pinned.withPinned(false).pinned == false && pinned.withPinned(false).id == "m2")
}

@Test func aRefusedRoomIsRejectedAndTheCableEventsMapOver() {
    let refused = Data(#"{"data":null,"errors":[{"message":"You're not at this venue"}]}"#.utf8)
    guard case .rejected? = VenueManagementClient.chatEvents(from: refused).first else { Issue.record("not rejected"); return }
    guard case .rejected? = VenueManagementClient.chatEvents(from: AudienceCable.Event.rejected).first else { Issue.record("not rejected"); return }
    guard case .offline(let reconnecting)? = VenueManagementClient.chatEvents(from: AudienceCable.Event.disconnected(reason: "lost", reconnects: true)).first
    else { Issue.record("not offline"); return }
    #expect(reconnecting == nil)
}

@Test func guestsSeeWhatTheRoomStillShows() throws {
    func message(_ json: String) throws -> VenueChatMessage { try JSONDecoder().decode(VenueChatMessage.self, from: Data(json.utf8)) }
    let hello = try message(line)
    #expect(hello.showsToGuests(expiresBefore: nil))
    #expect(hello.showsToGuests(expiresBefore: "2026-10-10T04:00:00Z"))
    #expect(!hello.showsToGuests(expiresBefore: "2026-10-10T06:00:00Z"))
    #expect(hello.sent(atOrBefore: "2026-10-10T05:00:00Z") && !hello.sent(atOrBefore: "2026-10-10T04:59:59Z"))

    let special = try message(line.replacingOccurrences(of: #""kind":"TEXT""#, with: #""kind":"SPECIAL""#)
        .replacingOccurrences(of: #""endsAt":null"#, with: #""endsAt":"2026-10-10T07:00:00.000Z""#))
    #expect(special.showsToGuests(expiresBefore: nil, at: parseInstant("2026-10-10T06:59:00Z")!))
    #expect(!special.showsToGuests(expiresBefore: nil, at: parseInstant("2026-10-10T07:00:00Z")!))
}
