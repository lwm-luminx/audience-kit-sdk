import Foundation
import Testing
@testable import StaffKitServices

// The board's Coming up times: "8pm on Tuesday" this week, "8pm Next Tuesday" the week after, "8pm on Tuesday the
// 12th" further out.

private let denver = TimeZone(identifier: "America/Denver")!

private func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = denver
    return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

// Monday 2026-11-23, 1 PM in Denver.
private let now = at(2026, 11, 23, 13)

@Test func anEventInTheNextSixDaysNamesOnlyItsWeekday() {
    #expect(MarqueeWhen.label(at(2026, 11, 24, 20), now: now, zone: denver) == "8pm on Tuesday")
    #expect(MarqueeWhen.label(at(2026, 11, 29, 21, 30), now: now, zone: denver) == "9:30pm on Sunday")
}

@Test func anEventInTheWeekAfterIsNextAndItsWeekday() {
    #expect(MarqueeWhen.label(at(2026, 11, 30, 20), now: now, zone: denver) == "8pm Next Monday")
    #expect(MarqueeWhen.label(at(2026, 12, 1, 20), now: now, zone: denver) == "8pm Next Tuesday")
    #expect(MarqueeWhen.label(at(2026, 12, 6, 19), now: now, zone: denver) == "7pm Next Sunday")
}

@Test func anEventTwoWeeksOutOrMoreAddsTheDayOfTheMonth() {
    #expect(MarqueeWhen.label(at(2026, 12, 7, 20), now: now, zone: denver) == "8pm on Monday the 7th")
    #expect(MarqueeWhen.label(at(2026, 12, 12, 19), now: now, zone: denver) == "7pm on Saturday the 12th")
}

@Test func anEventMoreThanFourWeeksOutNamesItsMonth() {
    #expect(MarqueeWhen.label(at(2027, 1, 22, 22), now: now, zone: denver) == "10pm on Friday the 22nd of January")
}

@Test func daysAreCountedAtTheVenueNotInUTC() {
    // 11 PM Sunday in Denver is already Monday in UTC; it is still six days out there.
    #expect(MarqueeWhen.label(at(2026, 11, 29, 23), now: now, zone: denver) == "11pm on Sunday")
}

@Test func timesAndOrdinalsRead() {
    #expect(MarqueeWhen.time(hour: 0, minute: 0) == "12am")
    #expect(MarqueeWhen.time(hour: 12, minute: 5) == "12:05pm")
    #expect((1...4).map(MarqueeWhen.ordinal) == ["1st", "2nd", "3rd", "4th"])
    #expect([11, 12, 13, 21, 23, 31].map(MarqueeWhen.ordinal) == ["11th", "12th", "13th", "21st", "23rd", "31st"])
}

@Test func lineupKeepsWhatsOnAndNextBeforeFinishedSets() {
    let order = (1...10).map { "d\($0)" } + (1...6).map { "u\($0)" }
    let shown = MarqueeLineup.window(order) { $0.hasPrefix("d") }
    #expect(shown == ["d9", "d10", "u1", "u2", "u3", "u4", "u5", "u6"])
}

@Test func shortLineupKeepsItsFinishedSets() {
    let shown = MarqueeLineup.window(["d1", "on", "u1"]) { $0.hasPrefix("d") }
    #expect(shown == ["d1", "on", "u1"])
}

@Test func comingUpGoesUnderAShortLineupOnly() {
    #expect(MarqueeLineup.comingUpCount(under: 1) == 3)
    #expect(MarqueeLineup.comingUpCount(under: 2) == 3)
    #expect(MarqueeLineup.comingUpCount(under: 4) == 1)
    #expect(MarqueeLineup.comingUpCount(under: 5) == 0)
    #expect(MarqueeLineup.comingUpCount(under: 8) == 0)
}
