import Foundation
import Testing
import AudienceKit
@testable import StaffKitCore
@testable import StaffKitServices

private func calendarClient(_ stub: Stub) -> CalendarSyncClient {
    CalendarSyncClient(session: AudienceManagementSession(baseURL: stub.baseURL, credentialStore: InMemoryCredentialStore(credential: makeCredential(audienceID: "audience", on: stub.baseURL)), session: stub.session))
}

private let feedJSON = #"{"url":"https://api.audiencekit.com/v1/calendar/abc.ics","webcalUrl":"webcal://api.audiencekit.com/v1/calendar/abc.ics","googleUrl":"https://calendar.google.com/calendar/render?cid=webcal%3A%2F%2Fapi"}"#

@Test func theCalendarLinkIsReadBackAndMadeOnAsk() async throws {
    let none = Stub { _ in .json(status: 200, body: #"{"data":{"me":{"calendarFeed":null}}}"#) }
    #expect(try await calendarClient(none).feed() == nil)

    let stub = Stub { _ in .json(status: 200, body: #"{"data":{"createCalendarFeed":{"calendarFeed":\#(feedJSON)}}}"#) }
    let feed = try await calendarClient(stub).create(reset: true)
    #expect(feed.webcalUrl.hasPrefix("webcal://"))
    let body = try #require(stub.requests.last).jsonBody()
    #expect((body["query"] as? String ?? "").contains("createCalendarFeed(input: { reset: $reset })"))
    #expect((body["variables"] as? [String: Any])?["reset"] as? Bool == true)
}

@Test func aCalendarEntryRunsThreeHoursWithoutAnEnd() {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    #expect(CalendarEntry(id: "e1", title: "Show", start: start, end: nil).end == start.addingTimeInterval(3 * 3600))
    #expect(CalendarEntry(id: "e1", title: "Show", start: start, end: start.addingTimeInterval(-60)).end == start.addingTimeInterval(3 * 3600))
    #expect(CalendarEntry(id: "e1", title: "Show", start: start, end: start.addingTimeInterval(7200), location: "").location == nil)
    #expect(CalendarEntry.instant("2026-10-31T03:00:00Z") == Date(timeIntervalSince1970: 1_793_415_600))
}
