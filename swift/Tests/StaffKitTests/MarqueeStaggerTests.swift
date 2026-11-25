import Foundation
import Testing
@testable import StaffKitServices

// Several screens showing the board take their breaks in turn (MarqueeStagger).

private func display(_ id: String, types: [StaffVenueDisplay.Screen] = [.board], off: Bool = false,
                     seen: Date?) -> StaffVenueDisplay {
    StaffVenueDisplay(id: id, name: id, kind: "APPLE_TV", off: off, ranking: types.map { .init(type: $0) },
                      lastSeenAt: seen.map { $0.formatted(.iso8601) })
}

@Test func aScreenAloneKeepsItsOwnTime() {
    #expect(MarqueeStagger.alone.wait(from: Date(timeIntervalSince1970: 1_000), board: 45, slide: 12) == 45)
    #expect(MarqueeStagger.alone.turn(at: Date(timeIntervalSince1970: 1_000)) == nil)
}

@Test func twoScreensBreakHalfACycleApart() {
    let now = Date(timeIntervalSince1970: 57 * 1_000)   // a cycle boundary for the first screen
    let first = MarqueeStagger(index: 0, count: 2), second = MarqueeStagger(index: 1, count: 2)
    // The first is at its turn, which is too soon to take: the one after, a whole cycle on.
    #expect(first.wait(from: now, board: 45, slide: 12) == 57)
    // The second's turn is half a cycle after the first's.
    #expect(second.wait(from: now, board: 45, slide: 12) == 28.5)
}

@Test func aTurnTooCloseIsLeftForTheNext() {
    let first = MarqueeStagger(index: 0, count: 2)
    let now = Date(timeIntervalSince1970: 57 * 1_000 + 47)   // 10 seconds before its turn, under half a look
    #expect(first.wait(from: now, board: 45, slide: 12) == 67)
    let earlier = Date(timeIntervalSince1970: 57 * 1_000 + 13)   // just back from a slide: 44 seconds to go
    #expect(first.wait(from: earlier, board: 45, slide: 12) == 44)
}

@Test func neighboursCountDifferentBreaksAndEachMovesOnACycle() {
    let first = MarqueeStagger(index: 0, count: 2), second = MarqueeStagger(index: 1, count: 2)
    let start = Date(timeIntervalSince1970: 57 * 1_000)
    let firstTurn = first.turn(at: start, board: 45, slide: 12)
    let secondTurn = second.turn(at: start.addingTimeInterval(28.5), board: 45, slide: 12)
    #expect(firstTurn == 1_000)
    #expect(secondTurn == 1_001)
    #expect(first.turn(at: start.addingTimeInterval(57), board: 45, slide: 12) == 1_001)
    // A moment early or late is still the same break.
    #expect(first.turn(at: start.addingTimeInterval(1.5), board: 45, slide: 12) == 1_000)
    #expect(first.turn(at: start.addingTimeInterval(-1.5), board: 45, slide: 12) == 1_000)
}

@Test func placeCountsConnectedBoardScreensInIDOrder() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let displays = [
        display("c", seen: now.addingTimeInterval(-30)),
        display("a", seen: now.addingTimeInterval(-30)),
        display("b", seen: now.addingTimeInterval(-3_600)),           // not connected
        display("d", types: [.chat], seen: now.addingTimeInterval(-30)),   // no board
        display("e", off: true, seen: now.addingTimeInterval(-30)),   // off
        display("f", types: [.liveActivity, .lineup], seen: now.addingTimeInterval(-30)),
    ]
    #expect(MarqueeStagger.of("a", among: displays, now: now) == MarqueeStagger(index: 0, count: 3))
    #expect(MarqueeStagger.of("c", among: displays, now: now) == MarqueeStagger(index: 1, count: 3))
    #expect(MarqueeStagger.of("f", among: displays, now: now) == MarqueeStagger(index: 2, count: 3))
    // This screen counts itself even before its own mark is fresh.
    #expect(MarqueeStagger.of("b", among: displays, now: now) == MarqueeStagger(index: 1, count: 4))
    #expect(MarqueeStagger.of("d", among: displays, now: now) == .alone)
    #expect(MarqueeStagger.of("zz", among: displays, now: now) == .alone)
}
