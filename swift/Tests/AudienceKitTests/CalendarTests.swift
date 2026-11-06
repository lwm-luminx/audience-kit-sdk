@testable import AudienceCore
import Foundation
import Testing
@testable import AudienceKit

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private let calendarAudienceID = "00000000-0000-4000-8000-000000000002"

private func calendarClient(_ stub: Stub) -> AudienceKitClient {
    let endpoint = URL(string: GraphQLEndpoint.consumer.path(audienceID: calendarAudienceID), relativeTo: stub.baseURL)!
        .absoluteURL
    let store = InMemoryCredentialStore(credential: Credential(token: "session-token", userId: "u-1",
                                                               audienceId: calendarAudienceID, role: "member",
                                                               endpoint: endpoint))
    let configuration = AudienceKitConfiguration(baseURL: stub.baseURL, audienceID: calendarAudienceID)
    return AudienceKitClient(configuration: configuration, credentialStore: store, session: stub.session)
}

private let feedJSON = #"""
{"url":"https://api.example.com/v1/calendar/abc.ics","webcalUrl":"webcal://api.example.com/v1/calendar/abc.ics",
 "googleUrl":"https://calendar.google.com/calendar/render?cid=webcal%3A%2F%2Fapi.example.com%2Fv1%2Fcalendar%2Fabc.ics",
 "venues":[{"id":"v-1"}]}
"""#

@Test func linksForAFeedAreBuiltAsTheAPIMakesThem() {
    let links = CalendarLinks(feed: URL(string: "https://api.audiencekit.com/v1/venues/v-1/calendar.ics?key=k_1")!)

    #expect(links.webcalUrl == "webcal://api.audiencekit.com/v1/venues/v-1/calendar.ics?key=k_1")
    #expect(links.googleUrl == "https://calendar.google.com/calendar/render?cid="
        + "webcal%3A%2F%2Fapi.audiencekit.com%2Fv1%2Fvenues%2Fv-1%2Fcalendar.ics%3Fkey%3Dk_1")
    #expect(links.feedURL?.scheme == "https")
    #expect(links.webcalURL?.scheme == "webcal")
    #expect(links.googleURL?.host == "calendar.google.com")
}

@Test func followingAVenueAddsItToTheOneFeed() async throws {
    let stub = Stub { request in
        let following = ((try? request.jsonBody())?["variables"] as? [String: Any])?["following"] as? Bool
        let venues = following == true ? #"[{"id":"v-1"}]"# : "[]"
        return .json(status: 200, body: #"""
        {"data":{"setCalendarFeedVenue":{"calendarFeed":{"url":"https://api.example.com/v1/calendar/abc.ics",
         "webcalUrl":"webcal://api.example.com/v1/calendar/abc.ics","googleUrl":"https://example.com",
         "venues":\#(venues)}}}}
        """#)
    }
    let client = calendarClient(stub)

    let feed = try await client.followVenueInCalendar(venueID: "v-1")
    #expect(feed.follows(venueID: "v-1"))
    #expect(!feed.follows(venueID: "v-2"))
    #expect(feed.links.url == "https://api.example.com/v1/calendar/abc.ics")
    let unfollowed = try await client.followVenueInCalendar(venueID: "v-1", following: false)
    #expect(!unfollowed.follows(venueID: "v-1"))

    let body = try stub.requests[0].jsonBody()
    #expect(body["operationName"] as? String == "SetCalendarFeedVenue")
    #expect((body["variables"] as? [String: Any])?["venueId"] as? String == "v-1")
    #expect(CalendarFeed(links: feed.links).venueIDs.isEmpty)
}

@Test func thePersonalFeedIsReadMadeAndDeleted() async throws {
    let stub = Stub { request in
        switch (try? request.jsonBody())?["operationName"] as? String {
        case "CalendarFeed":
            return .json(status: 200, body: #"{"data":{"me":{"calendarFeed":null}}}"#)
        case "CreateCalendarFeed":
            return .json(status: 200, body: #"{"data":{"createCalendarFeed":{"calendarFeed":\#(feedJSON)}}}"#)
        default:
            return .json(status: 200, body: #"{"data":{"deleteCalendarFeed":{"deleted":true}}}"#)
        }
    }
    let client = calendarClient(stub)

    #expect(try await client.calendarFeed() == nil)
    let feed = try await client.createCalendarFeed(reset: true)
    #expect(feed.links.webcalUrl == "webcal://api.example.com/v1/calendar/abc.ics")
    #expect(feed.links == CalendarLinks(feed: URL(string: "https://api.example.com/v1/calendar/abc.ics")!))
    #expect(feed.venueIDs == ["v-1"])
    #expect(try await client.deleteCalendarFeed())

    let operations = stub.requests.map { ((try? $0.jsonBody())?["operationName"] as? String) ?? "" }
    #expect(operations == ["CalendarFeed", "CreateCalendarFeed", "DeleteCalendarFeed"])
    let variables = (try stub.requests[1].jsonBody())["variables"] as? [String: Any]
    #expect(variables?["reset"] as? Bool == true)
}
