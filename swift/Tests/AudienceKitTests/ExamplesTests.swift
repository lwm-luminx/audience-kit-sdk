import AudienceKit
import AudienceKitTesting
import Foundation
import Testing

// Runs the programs in Tests/AudienceKitTests/Examples (shown on the developer site) against a stub API.

private func article(_ id: String, _ title: String) -> String {
    #"{"id":"\#(id)","slug":"news","title":"\#(title)","byline":"Sam","kind":"ARTICLE","summary":"It's big.","#
        + #""edited":false,"pinned":false,"teaser":true,"canonicalUrl":"https://paper/news","#
        + #""disclosure":"Sam tends bar there.","publication":{"id":"p1","name":"Paper","trusted":false,"acceptsOpEds":false}}"#
}

@Test func theNewsDigestExample() async throws {
    let api = GraphQLStub { request in
        switch request.operationName {
        case "Locales": .data(#"{"locales":[{"id":"L1","name":"Boulder"},{"id":"L2","name":"Denver"}]}"#)
        case "Articles": .data(#"{"soapbox":{"articles":{"nodes":[\#(article("a1", "Bar opens"))]}}}"#)
        case "NationalArticles":
            .data(#"{"soapbox":{"articles":{"nodes":[\#(article("a1", "Bar opens")),\#(article("a2", "Pride"))]}}}"#)
        default: .error("no \(request.operationName ?? "")")
        }
    }
    let text = try await NewsDigest.digest(api.client, localeName: "Denver")
    #expect(text.hasPrefix("# Denver this week"))
    #expect(text.contains("- **Bar opens**, Sam for Paper ([read on Paper](https://paper/news))\n  It's big.\n  _Sam"))
    #expect(text.contains("## Around the country\n\n- **Pride**"))
    #expect(try await NewsDigest.digest(api.client).hasPrefix("# Boulder"))

    let empty = GraphQLStub { _ in .data(#"{"locales":[]}"#) }
    #expect(try await NewsDigest.digest(empty.client) == "")
}

@Test func theWhatsOnExampleGroupsEventsByNight() async throws {
    let events = #"""
    [{"id":"e2","name":"Bingo","startAt":"2026-12-07T02:30:00Z","isFeatured":false,"isCanceled":true},
     {"id":"e1","name":"Brunch","startAt":"2026-12-06T18:00:00Z","isFeatured":false,"isCanceled":false,"venue":{"name":"Club"}},
     {"id":"e3","startAt":"2026-12-08T03:00:00Z","isFeatured":false,"isCanceled":false},
     {"id":"e4","name":"Someday","isFeatured":false,"isCanceled":false}]
    """#
    let api = GraphQLStub { _ in .data(#"{"events":{"list":{"nodes":\#(events)}}}"#) }
    let nights = try await WhatsOn.load(api.client, localeID: "L1")
    #expect(nights.map(\.title) == ["Sunday, December 6", "Monday, December 7"])
    #expect(nights[0].rows.map(\.name) == ["Brunch", "Bingo"])
    #expect(nights[0].rows[0].time == "11:00 AM")
    #expect(nights[0].rows[0].place == "Club")
    #expect(nights[0].rows[1].canceled)
    #expect(nights[1].rows[0].name == "Untitled")
    #expect(api.requests[0].string("localeId") == "L1")
}

@Test func theMemberActionsExample() async throws {
    let feed = #"{"url":"https://f.ics","webcalUrl":"webcal://f","googleUrl":"https://g","venues":[]}"#
    let admission = #"""
    {"id":"adm-1","status":"PAID","night":"2026-12-06","amount":{"cents":1000,"currency":"usd"},
     "total":{"cents":1000,"currency":"usd"},"isRefundable":false,"passSecret":"c2VjcmV0","scanCount":0,
     "profile":{"id":"u-1","name":"Rae","avatarUrl":null},"venue":{"id":"v1","name":"Club","photoUrl":null}}
    """#
    let api = GraphQLStub { request in
        switch request.operationName {
        case "RSVPEvent": .data(#"{"rsvpEvent":{"event":{"id":"e1","rsvp":{"mine":"ATTENDING","count":4}}}}"#)
        case "CreateCalendarFeed": .data(#"{"createCalendarFeed":{"calendarFeed":\#(feed)}}"#)
        case "SetCalendarFeedVenue": .data(#"{"setCalendarFeedVenue":{"calendarFeed":\#(feed)}}"#)
        case "VenueCover":
            request.string("id") == "v1"
                ? .data(#"{"venues":{"venue":{"id":"v1","tickets":{"cover":{"viewerAdmission":\#(admission)}}}}}"#)
                : .data(#"{"venues":{"venue":null}}"#)
        case "ReportContent": .data(#"{"reportContent":{"reported":true,"blocked":true}}"#)
        default: .error("no \(request.operationName ?? "")")
        }
    }
    #expect(try await MemberActions.goingTo(api.client, eventID: "e1") == .attending)
    #expect(try await MemberActions.calendarLinks(api.client).webcalUrl == "webcal://f")
    #expect(try await MemberActions.calendarLinks(api.client, venueID: "v1").googleUrl == "https://g")
    let pass = try #require(try await MemberActions.doorPass(api.client, venueID: "v1",
                                                            at: Date(timeIntervalSince1970: 1_000_005)))
    #expect(pass.code.hasPrefix("HMC1.adm-1.33333."))
    #expect(pass.refreshInSeconds == 25)
    #expect(try await MemberActions.doorPass(api.client, venueID: "gone") == nil)
    let result = try await MemberActions.reportHarassment(api.client, messageID: "m1")
    #expect(result.reported && result.blocked)
    #expect(api.requests.last?.string("reason") == "Harassment or hate")
}
