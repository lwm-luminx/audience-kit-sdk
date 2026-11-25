import Foundation
import Testing
@testable import StaffKitCore
@testable import StaffKitServices

// Velvet lists every screen at the venue as connected now or by when it last was, from when it was last seen.

private let now = Date(timeIntervalSince1970: 1_795_000_000)

private func display(seen secondsAgo: TimeInterval?) -> StaffVenueDisplay {
    let stamp = secondsAgo.map { now.addingTimeInterval(-$0).formatted(.iso8601) }
    return StaffVenueDisplay(id: "d1", name: "Bar TV", lastSeenAt: stamp)
}

@Test func aScreenSeenInTheLastFewMinutesIsConnected() {
    #expect(display(seen: 0).connection(now: now) == .connected)
    #expect(display(seen: 150).connection(now: now) == .connected)
}

@Test func aScreenSeenLongerAgoSaysWhenItLastConnected() {
    #expect(display(seen: 600).connection(now: now) == .lastConnected(now.addingTimeInterval(-600)))
}

@Test func aScreenNeverSeenHasNeverConnected() {
    #expect(display(seen: nil).connection(now: now) == .never)
}

@Test func aGoogleTVIsNamedAsOne() {
    #expect(StaffVenueDisplay(id: "d1", name: "Patio", kind: "ANDROID_TV").kindTitle == "Google TV")
}
