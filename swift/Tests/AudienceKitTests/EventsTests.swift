@testable import AudienceCore
import Foundation
import Testing
@testable import AudienceKit

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private let eventsAudienceID = "00000000-0000-4000-8000-000000000001"

/// A signed-in client whose requests `stub` answers.
private func eventsClient(_ stub: Stub) -> AudienceKitClient {
    let endpoint = URL(string: GraphQLEndpoint.consumer.path(audienceID: eventsAudienceID), relativeTo: stub.baseURL)!
        .absoluteURL
    let store = InMemoryCredentialStore(credential: Credential(token: "session-token", userId: "u-1",
                                                               audienceId: eventsAudienceID, role: "member",
                                                               endpoint: endpoint))
    let configuration = AudienceKitConfiguration(baseURL: stub.baseURL, host: "hackdifferent.admin.audiencekit.com",
                                                 audienceID: eventsAudienceID, facebookAppID: nil,
                                                 environment: .production)
    return AudienceKitClient(configuration: configuration, credentialStore: store, session: stub.session)
}

private extension RecordedRequest {
    var query: String { ((try? jsonBody())?["query"] as? String) ?? "" }
    var operationName: String? { (try? jsonBody())?["operationName"] as? String }
    var variables: [String: Any] { ((try? jsonBody())?["variables"] as? [String: Any]) ?? [:] }
}

private let eventJSON = #"""
{"id":"e-1","name":"DEF CON 35","description":"Hacker summer camp","startAt":"2027-08-05T16:00:00Z",
 "endAt":"2027-08-08T23:00:00Z","isFeatured":true,"isCanceled":false,"bannerUrl":null,
 "sourceUrl":"https://defcon.org","locale":{"id":"l-1","name":"Las Vegas","label":"LV","cityNames":null,"bannerUrl":null},
 "tags":[{"id":"t-1","name":"Conference","color":"#00ff00"}],
 "venue":{"name":"LVCC","venue":{"id":"v-1","name":"LVCC","photoUrl":null,
   "location":{"id":"loc-1","point":"POINT (-115.1523 36.1318)","address":"3150 Paradise Rd"}}},
 "rsvp":{"mine":"ATTENDING","count":12},
 "people":{"hosts":{"nodes":[{"id":"p-1","name":"Dark Tangent","avatarUrl":null}]},"lineup":{"nodes":[]}},
 "tickets":{"url":"https://defcon.org/tickets",
   "offers":{"nodes":[{"price":{"cents":46000,"currency":"usd"},"url":"https://defcon.org/tickets",
     "seller":{"key":"defcon","name":"DEF CON"}}]},
   "cover":{"charge":null}}}
"""#

/// An audience without the RSVP, People, Ticketing, Listings, Google Places or Friends modules: each type's fields
/// as introspection shows them (no `ListingProfile` at all).
private let reducedFields: [String: [String]] = [
    "Event": ["id", "name", "description", "startAt", "locale", "tags", "venue"],
    "EventSeries": ["id", "name", "venue"],
    "Locale": ["id", "name", "label"],
    "Location": ["id", "point", "address"],
    "Person": ["id", "name"],
    "Venue": ["id", "name", "locale", "location", "tags", "events", "chat"],
]

/// Answers a `SchemaFields` request (`tN: __type(name: "Type") { … }`) from ``reducedFields``.
private func reducedSchema(_ request: RecordedRequest) -> StubResponse {
    let pattern = try! NSRegularExpression(pattern: #"(t\d+): __type\(name: "(\w+)"\)"#)
    let query = request.query
    let entries = pattern.matches(in: query, range: NSRange(query.startIndex..., in: query)).map { match in
        let alias = String(query[Range(match.range(at: 1), in: query)!])
        let type = String(query[Range(match.range(at: 2), in: query)!])
        let fields = reducedFields[type].map { names in
            #"{"fields":["# + names.map { #"{"name":"\#($0)"}"# }.joined(separator: ",") + "]}"
        } ?? "null"
        return #""\#(alias)":\#(fields)"#
    }
    return .json(status: 200, body: #"{"data":{"# + entries.joined(separator: ",") + "}}")
}

@Test func eventsDecodeEveryModulesFieldsAndTheWKTPoint() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{"events":{"list":{"nodes":[\#(eventJSON)]}}}}"#) }
    let client = eventsClient(stub)

    let events = try await client.events(localeID: "l-1")

    let request = try #require(stub.requests.first)
    #expect(request.operationName == "Events")
    #expect(request.variables["window"] as? String == "UPCOMING")
    #expect(request.variables["localeId"] as? String == "l-1")
    // No page: a page of 100 events is over the API's complexity budget.
    #expect(request.variables["first"] == nil)
    #expect(request.query.contains("rsvp { mine count }"))

    let event = try #require(events.first)
    #expect(event.name == "DEF CON 35")
    #expect(event.startAt == ISO8601.date(from: "2027-08-05T16:00:00Z"))
    #expect(event.venue?.id == "v-1")
    #expect(event.venueName == "LVCC")
    #expect(event.venue?.location?.coordinate == Coordinate(latitude: 36.1318, longitude: -115.1523))
    #expect(event.rsvp == Event.RSVP(mine: .attending, count: 12))
    #expect(event.hosts?.map(\.name) == ["Dark Tangent"])
    #expect(event.lineup == [])
    #expect(event.ticketURL == URL(string: "https://defcon.org/tickets"))
    #expect(event.ticketOffers == [AdmissionOffer(price: Money(cents: 46000, currency: "usd"),
                                                  url: "https://defcon.org/tickets",
                                                  seller: .init(key: "defcon", name: "DEF CON"))])
    #expect(event.coverCharge == nil)
    #expect(request.query.contains("offers { nodes { price { cents currency } url seller { key name } } }"))
    #expect(request.query.contains("cover { charge {"))
    #expect(event.tags?.first?.name == "Conference")
    #expect(try JSONDecoder().decode(Event.self, from: JSONEncoder().encode(event)) == event)
}

@Test func anAudienceWithoutAModuleGetsTheQueryAgainWithoutItsFields() async throws {
    let stub = Stub { request in
        switch request.operationName {
        case "SchemaFields":
            return reducedSchema(request)
        case "Events" where request.query.contains("rsvp"):
            return .json(status: 200, body: #"""
            {"errors":[{"message":"Field 'rsvp' doesn't exist on type 'Event'","extensions":{"code":"undefinedField"}}]}
            """#)
        default:
            return .json(status: 200, body: #"""
            {"data":{"events":{"list":{"nodes":[{"id":"e-2","name":"801 Labs open night","isFeatured":false,
              "isCanceled":false,"locale":null,"tags":[],"venue":{"name":"801 Labs","venue":null}}]}}}}
            """#)
        }
    }
    let client = eventsClient(stub)

    let events = try await client.events()
    #expect(events.map(\.name) == ["801 Labs open night"])
    #expect(events.first?.rsvp == nil)
    #expect(events.first?.venueName == "801 Labs")

    #expect(stub.requests.map(\.operationName) == ["Events", "SchemaFields", "Events"])
    let retried = stub.requests[2].query
    #expect(!retried.contains("rsvp"))
    #expect(!retried.contains("people"))
    #expect(!retried.contains("tickets"))
    #expect(!retried.contains("places"))
    #expect(!retried.contains("profile"))
    #expect(retried.contains("venue { name venue"))

    // The session remembers the schema: the next call goes straight to the reduced document.
    _ = try await client.event(id: "e-2")
    #expect(stub.requests.count == 4)
    #expect(stub.requests[3].operationName == "Event")
    #expect(!stub.requests[3].query.contains("rsvp"))
}

@Test func venuesWithoutFacebookOrPlacesLeaveThePageAndPlaceOut() async throws {
    let stub = Stub { request in
        switch request.operationName {
        case "SchemaFields":
            return reducedSchema(request)
        case "Venues" where request.query.contains("facebook"):
            return .json(status: 200, body: #"""
            {"errors":[{"message":"Field 'facebook' doesn't exist on type 'ListingProfile'","extensions":{"code":"undefinedField"}}]}
            """#)
        default:
            return .json(status: 200, body: #"""
            {"data":{"venues":{"list":{"nodes":[{"id":"v-1","name":"801 Labs","hidden":false,"order":0,
              "photoUrl":null,"bannerUrl":null,"locale":{"id":"l-1","name":"Salt Lake City"},
              "location":{"id":"loc-1","point":"POINT (-111.89 40.76)","address":null},"tags":[]}]}}}}
            """#)
        }
    }

    let venues = try await eventsClient(stub).venues()

    #expect(venues.map(\.name) == ["801 Labs"])
    #expect(venues.first?.page == nil)
    #expect(venues.first?.location?.coordinate == Coordinate(latitude: 40.76, longitude: -111.89))
    let retried = try #require(stub.requests.last).query
    #expect(!retried.contains("facebook"))
    #expect(!retried.contains("places"))
}

@Test func otherGraphQLErrorsAreNotRetried() async throws {
    let stub = Stub { _ in
        .json(status: 200, body: #"{"errors":[{"message":"Not allowed","extensions":{"code":"FORBIDDEN"}}]}"#)
    }

    await #expect(throws: AudienceKitError.self) { try await eventsClient(stub).events() }
    #expect(stub.requests.count == 1)
}

@Test func eventSeriesDecode() async throws {
    let stub = Stub { _ in
        .json(status: 200, body: #"""
        {"data":{"events":{"series":{"nodes":[{"id":"s-1","name":"Open hack night","description":null,
          "recurrenceText":"Every Tuesday","startsOn":"2026-01-06","startTime":"19:00","timeZone":"America/Denver",
          "durationMinutes":180,"bannerUrl":null,"locale":null,"tags":[],
          "venue":{"name":"801 Labs","venue":{"id":"v-1","name":"801 Labs","photoUrl":null,"location":null}}}]}}}}
        """#)
    }

    let series = try await eventsClient(stub).eventSeries(venueID: "v-1")

    let first = try #require(series.first)
    #expect(first.recurrenceText == "Every Tuesday")
    #expect(first.startTime == "19:00")
    #expect(first.venue?.id == "v-1")
    #expect(try #require(stub.requests.first).variables["venueId"] as? String == "v-1")
    #expect(try JSONDecoder().decode(EventSeries.self, from: JSONEncoder().encode(first)) == first)
}

@Test func venueDetailReadsTheProfileChatAndEvents() async throws {
    let stub = Stub { _ in
        .json(status: 200, body: #"""
        {"data":{"venues":{"venue":{"id":"v-1","name":"801 Labs","hidden":false,"order":0,"photoUrl":null,
          "bannerUrl":null,"description":"Salt Lake's hackerspace","locale":{"id":"l-1","name":"Salt Lake City"},
          "location":null,"tags":[],
          "profile":{"address":"615 S 300 W","phone":null,"website":"https://801labs.org",
            "socialLinks":{"nodes":[{"id":"s-1","handle":"801labs","provider":"discord","url":"https://discord.gg/x"}]},
            "facebook":{"page":null}},
          "chat":{"open":true,"recentMessages":{"nodes":[{"id":"m-1","body":"hi","message":"hi","name":"Ada L.",
            "userId":"u-2","sentAt":"2026-11-06T18:00:00Z","kind":"TEXT","pinned":false}]}},
          "events":{"upcoming":{"nodes":[\#(eventJSON)]}}}}}}
        """#)
    }

    let detail = try #require(try await eventsClient(stub).venueDetail(id: "v-1"))

    #expect(detail.venue.name == "801 Labs")
    #expect(detail.description == "Salt Lake's hackerspace")
    #expect(detail.address == "615 S 300 W")
    #expect(detail.website == "https://801labs.org")
    #expect(detail.socialLinks?.first?.provider == "discord")
    #expect(detail.chatOpen == true)
    #expect(detail.recentMessages?.first?.name == "Ada L.")
    #expect(detail.upcomingEvents?.first?.id == "e-1")
    let request = try #require(stub.requests.first)
    #expect(request.variables["recentMessages"] as? Int == 20)
    #expect(request.query.contains("recentMessages(limit: $recentMessages)"))
}

@Test func venueOffersListEveryWayInForTheNight() async throws {
    let stub = Stub { _ in
        .json(status: 200, body: #"""
        {"data":{"venues":{"venue":{"id":"v-1","tickets":{"offers":{"nodes":[
          {"price":{"cents":1500,"currency":"usd"},"url":null,"seller":{"key":"audiencekit","name":"AudienceKit"}}]}}}}}}
        """#)
    }

    let offers = try await eventsClient(stub).venueOffers(venueID: "v-1", night: "2026-11-07")

    #expect(offers.map(\.seller.key) == ["audiencekit"])
    #expect(offers.first?.price == Money(cents: 1500, currency: "usd"))
    let request = try #require(stub.requests.first)
    #expect(request.operationName == "VenueOffers")
    #expect(request.variables["night"] as? String == "2026-11-07")
}

@Test func venueCoverAndOffersWithoutTicketingAskOnlyForTheVenue() async throws {
    let stub = Stub { request in
        switch request.operationName {
        case "SchemaFields":
            return reducedSchema(request)
        case _ where request.query.contains("tickets"):
            return .json(status: 200, body: #"""
            {"errors":[{"message":"Field 'tickets' doesn't exist on type 'Venue'","extensions":{"code":"undefinedField"}}]}
            """#)
        default:
            return .json(status: 200, body: #"{"data":{"venues":{"venue":{"id":"v-1","name":"801 Labs"}}}}"#)
        }
    }
    let client = eventsClient(stub)

    let cover = try #require(try await client.venueCover(venueID: "v-1"))
    #expect(cover.name == "801 Labs")
    #expect(cover.coverCharge == nil)
    #expect(cover.viewerAdmission == nil)

    let offers = try await client.venueOffers(venueID: "v-1")
    #expect(offers == [])
    #expect(stub.requests.map(\.operationName) == ["VenueCover", "SchemaFields", "VenueCover", "VenueOffers"])
    #expect(!stub.requests[3].query.contains("$night"))
}

@Test func sendChatMessageNamesTheRoom() async throws {
    let stub = Stub { _ in
        .json(status: 200, body: #"""
        {"data":{"sendMyChatMessage":{"message":{"id":"m-9","body":"on my way","message":"on my way",
          "name":"Rick M.","userId":"u-1","sentAt":"2026-11-06T18:00:00Z","kind":"TEXT","pinned":false}}}}
        """#)
    }

    let message = try await eventsClient(stub).sendChatMessage("on my way", in: .locale(id: "l-1"))

    #expect(message.id == "m-9")
    let request = try #require(stub.requests.first)
    let input = try #require(request.variables["input"] as? [String: Any])
    #expect(input["localeId"] as? String == "l-1")
    #expect(input["message"] as? String == "on my way")
    #expect(input["venueId"] == nil)
}

@Test func chatRoomEventsDecode() throws {
    func decode(_ json: String) -> ChatRoomEvent? {
        guard case let .success(events)? = ChatRoomEvent.decode(result: Data(json.utf8)) else { return nil }
        return events.first
    }
    let line = #"{"id":"m-1","body":"hi","message":"hi","name":"Ada L.","userId":"u-2","kind":"TEXT","pinned":false}"#

    #expect(decode(#"{"data":{"room":{"__typename":"ChatJoined","outOfRange":true,"#
        + #""roster":{"people":[{"userId":"u-2","name":"Ada L.","avatarUrl":null,"friend":true}]},"#
        + #""history":[{"message":\#(line)}],"pinnedMessage":null}}}"#)
        == .joined(people: [ChatRosterPerson(userId: "u-2", name: "Ada L.", friend: true)],
                   history: [ChatMessage(id: "m-1", body: "hi", name: "Ada L.", userId: "u-2")], pinned: nil,
                   outOfRange: true))
    #expect(decode(#"{"data":{"room":{"__typename":"ChatMessagePosted","message":\#(line)}}}"#)
        == .posted(ChatMessage(id: "m-1", body: "hi", name: "Ada L.", userId: "u-2")))
    #expect(decode(#"{"data":{"room":{"__typename":"ChatMessageRemoved","messageId":"m-1"}}}"#)
        == .removed(messageID: "m-1"))
    #expect(decode(#"{"data":{"room":{"__typename":"ChatLeft","reason":"BANNED"}}}"#) == .left(reason: "BANNED"))

    let mirror = #"{"data":{"room":{"__typename":"ChatJoined","outOfRange":false,"readOnly":true,"#
        + #""replyUrl":"https://discord.com/channels/1/2","roster":{"people":[]},"history":[],"pinnedMessage":null}}}"#
    guard case let .success(events)? = ChatRoomEvent.decode(result: Data(mirror.utf8)) else {
        Issue.record("not decoded")
        return
    }
    #expect(events.last == .readOnly(replyURL: URL(string: "https://discord.com/channels/1/2")))
    #expect(events.count == 2)
    #expect(decode(#"{"data":{"room":{"__typename":"ChatSomethingNew"}}}"#) == .unknown("ChatSomethingNew"))
    #expect(ChatRoomEvent.decode(result: Data(#"{"data":null}"#.utf8)) == nil)

    guard case let .failure(errors)? = ChatRoomEvent.decode(
        result: Data(#"{"data":null,"errors":[{"message":"Not at the venue"}]}"#.utf8)
    ) else {
        Issue.record("expected a refusal")
        return
    }
    #expect(errors.first?.message == "Not at the venue")
}

@Test func chatRoomDocumentNamesItsField() {
    #expect(Queries.chatRoom(.venue(id: "v-1"), watch: false).contains("room: venueChat(venueId: $id)"))
    #expect(Queries.chatRoom(.locale(id: "l-1"), watch: true).contains("room: localeChat(localeId: $id, watch: true)"))
}
