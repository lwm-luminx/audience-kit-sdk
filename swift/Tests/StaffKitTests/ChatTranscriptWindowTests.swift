import Foundation
import Testing
@testable import StaffKitServices

private let now = parseInstant("2026-10-25T12:00:00Z")!

/// A message sent `hoursAgo` before `now`.
private func message(_ id: String, hoursAgo: Double) -> VenueChatMessage {
    VenueChatMessage(id: id, message: id, sentAt: isoInstant(now.addingTimeInterval(-hoursAgo * 3600)), userId: "u")
}

// Newest first, as the API pages them.
private let transcript = [message("now", hoursAgo: 0.1), message("hour", hoursAgo: 1), message("day", hoursAgo: 30),
                          message("twoDays", hoursAgo: 47), message("week", hoursAgo: 160)]

@Test func messagesOlderThanTwoDaysWaitBehindShowMore() {
    let window = ChatTranscriptWindow(newestFirst: transcript, guests: nil, showingAll: false, now: now)
    #expect(window.shown.map(\.id) == ["twoDays", "day", "hour", "now"])
    #expect(window.hiddenCount == 1 && window.canShowMore(hasOlderPages: false))
    #expect(window.expiredCount == 0 && window.firstGuestVisibleID == nil && !window.dividerAtEnd)

    let all = ChatTranscriptWindow(newestFirst: transcript, guests: nil, showingAll: true, now: now)
    #expect(all.shown.map(\.id) == ["week", "twoDays", "day", "hour", "now"] && all.hiddenCount == 0)
    #expect(!all.canShowMore(hasOlderPages: false) && all.canShowMore(hasOlderPages: true))
}

@Test func theDividerSitsWhereGuestsStopSeeingTheRoom() {
    // A venue's default day: the 30- and 47-hour-old messages are history only staff see.
    let venue = ChatTranscriptWindow(newestFirst: transcript, guests: ChatGuestWindow(minutes: 24 * 60), showingAll: false, now: now)
    #expect(venue.expiredCount == 2 && venue.firstGuestVisibleID == "hour")

    // A quiet room where everything has expired: the line goes under the last message.
    let quiet = ChatTranscriptWindow(newestFirst: Array(transcript.dropFirst(2)), guests: ChatGuestWindow(minutes: 240),
                                     showingAll: false, now: now)
    #expect(quiet.dividerAtEnd && quiet.firstGuestVisibleID == nil)

    // A week-long window: guests still see everything shown.
    let long = ChatTranscriptWindow(newestFirst: transcript, guests: ChatGuestWindow(minutes: 7 * 24 * 60), showingAll: true, now: now)
    #expect(long.expiredCount == 0)
}

@Test func theGuestWindowComesFromTheRoomOrFromJoining() {
    #expect(ChatGuestWindow(minutes: 240)?.retention == TimeInterval(4 * 3600))
    #expect(ChatGuestWindow(minutes: nil) == nil && ChatGuestWindow(minutes: 0) == nil)
    let heard = ChatGuestWindow(expiresBefore: "2026-10-24T12:00:00Z", heardAt: now)
    #expect(heard?.retention == TimeInterval(24 * 3600))
    // The cutoff moves with the clock.
    #expect(heard?.cutoff(at: now.addingTimeInterval(3600)) == parseInstant("2026-10-24T13:00:00Z"))
    #expect(ChatGuestWindow(expiresBefore: nil) == nil && ChatGuestWindow(expiresBefore: "soon") == nil)
}
