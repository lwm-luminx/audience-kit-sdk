import Foundation
import Testing
import AudienceKit
import StaffKitCore
import StaffKitServices

@Test func venueCodeCanRedeemWithoutAnExistingSessionAndBindsItsAudience() async throws {
    let stub = Stub { request in
        if request.path == "/v1/venue-devices/redeem" {
            let device = makeCredential(token: "device-token", audienceID: "venue-audience", venueDeviceID: "grant",
                                        role: "venue_device", on: request.url)
            return .json(status: 200, body: tokenJSON(device, extra: """
                "venue_device":{"id":"grant","venue_id":"venue","venue_name":"Velvet","permissions":["door"],"expires_at":"2026-11-01T00:00:00Z","audience":{"id":"venue-audience","name":"Audience","subdomain":"audience"}}
                """))
        }
        return .json(status: 200, body: #"{"data":{"me":{"cover":{"doorVenues":{"nodes":[]}}}}}"#)
    }
    let store = InMemoryCredentialStore()
    let focus = AudienceManagementSession(baseURL: stub.baseURL, credentialStore: store, session: stub.session)
    let access = try await focus.redeemVenueCode("ABCD-EFGH-IJKL-MNOP", identifier: "phone")
    #expect(access.permits("door"))
    #expect(!access.permits("moderation"))
    #expect(await focus.isVenueDevice)
    #expect(try store.load()?.token == "device-token")
    #expect(try store.load()?.venueDeviceId == "grant")
    _ = try await VenueManagementClient(session: focus).venues()
    #expect(stub.requests.last?.path == "/v1/audience/venue-audience/staffql")
}

@Test func venueChatSendsAsVenueAndScopesModerationToRoom() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{}}"#) }
    let focus = AudienceManagementSession(baseURL: stub.baseURL, credentialStore: InMemoryCredentialStore(credential: makeCredential(audienceID: "audience", on: stub.baseURL)), session: stub.session)
    let client = VenueManagementClient(session: focus)
    try await client.send(venueID: "venue", message: "Welcome")
    let sent = try #require(stub.requests.last).jsonBody()
    let variables = try #require(sent["variables"] as? [String: Any])
    let input = try #require(variables["input"] as? [String: Any])
    #expect(input["asVenue"] as? Bool == true)
    #expect(input["venueId"] as? String == "venue")
    try await client.moderateChat(venueID: "venue", userID: "guest", action: "BAN")
    let moderation = try #require(stub.requests.last).jsonBody()
    #expect((moderation["query"] as? String)?.contains("moderateVenueChat") == true)
    #expect((moderation["query"] as? String)?.contains("banAudienceMember") == false)
}

@Test func editingSeriesDoesNotReplaceItsExistingRuleOrOwner() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{}}"#) }
    let focus = AudienceManagementSession(baseURL: stub.baseURL, credentialStore: InMemoryCredentialStore(credential: makeCredential(audienceID: "audience", on: stub.baseURL)), session: stub.session)
    try await VenueManagementClient(session: focus).saveSeries(id: "series", venueID: "venue", fields: ["name": .string("Updated")])
    let request = try #require(stub.requests.last).jsonBody()
    let input = try #require((request["variables"] as? [String: Any])?["input"] as? [String: Any])
    let fields = try #require(input["eventSeries"] as? [String: Any])
    #expect(input["id"] as? String == "series")
    #expect(fields["rrule"] == nil)
    #expect(fields["ownerVenueId"] == nil)
    #expect(fields["venueId"] == nil)
}

private func venueClient(_ stub: Stub) -> VenueManagementClient {
    VenueManagementClient(session: AudienceManagementSession(baseURL: stub.baseURL, credentialStore: InMemoryCredentialStore(credential: makeCredential(audienceID: "audience", on: stub.baseURL)), session: stub.session))
}
private func lastInput(_ stub: Stub) throws -> [String: Any] {
    let body = try stub.requests.last?.jsonBody()
    return (body?["variables"] as? [String: Any])?["input"] as? [String: Any] ?? [:]
}
private let savedEvent = #"{"id":"event","name":"Hot Mess","startAt":"2026-10-10T04:00:00Z","isCanceled":false,"venue":{"name":"Velvet"},"people":{"lineup":{"nodes":[{"id":"host","name":"Ada","avatarUrl":null}]}},"seriesOverride":false,"tickets":{"cover":{"cents":0}},"isFeatured":false,"ping":{"count":3},"rsvp":{"counts":{"going":4,"interested":2}}}"#

@Test func creatingAnEventPutsItAtTheVenueWithHostsAndImage() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{"createEvent":{"event":\#(savedEvent)}}}"#) }
    let event = try await venueClient(stub).saveEvent(id: nil, venueID: "venue", fields: [
        "name": .string("Hot Mess"), "hostIds": .array([.string("host")]), "photo": .string("data:image/jpeg;base64,AAAA"), "coverCents": .int(0)
    ])
    #expect(event.people.first?.name == "Ada")
    #expect(event.coverCents == 0)
    #expect(event.pingCount == 3)
    #expect(event.rsvpCounts?.going == 4)
    let request = try #require(stub.requests.last).jsonBody()
    #expect((request["query"] as? String)?.contains("createEvent(input: $input)") == true)
    #expect((request["query"] as? String)?.contains("EventCreateInput!") == true)
    #expect((request["query"] as? String)?.contains("rsvp { counts { going interested } }") == true)
    let input = try #require((request["variables"] as? [String: Any])?["input"] as? [String: Any])
    let fields = try #require(input["event"] as? [String: Any])
    #expect(input["id"] == nil)
    #expect(fields["venueId"] as? String == "venue")
    #expect(fields["hostIds"] as? [String] == ["host"])
    #expect(fields["photo"] as? String == "data:image/jpeg;base64,AAAA")
    #expect(fields["isFeatured"] == nil)
}

@Test func updatingAnEventSendsOnlyItsChangedFields() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{"updateEvent":{"event":\#(savedEvent)}}}"#) }
    _ = try await venueClient(stub).saveEvent(id: "event", venueID: "venue", fields: ["seriesOverride": .bool(false)])
    let request = try #require(stub.requests.last).jsonBody()
    #expect((request["query"] as? String)?.contains("updateEvent(input: $input)") == true)
    let input = try #require((request["variables"] as? [String: Any])?["input"] as? [String: Any])
    #expect(input["id"] as? String == "event")
    #expect((input["event"] as? [String: Any])?.keys.sorted() == ["seriesOverride"])
}

@Test func deletingEventsAndSeriesUseTheirOwnMutations() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{}}"#) }
    let client = venueClient(stub)
    try await client.deleteEvent(id: "event")
    let event = try #require(stub.requests.last).jsonBody()
    #expect((event["query"] as? String)?.contains("deleteEvent(input: $input)") == true)
    #expect(((event["variables"] as? [String: Any])?["input"] as? [String: Any])?["id"] as? String == "event")
    try await client.deleteSeries(id: "series")
    let series = try #require(stub.requests.last).jsonBody()
    #expect((series["query"] as? String)?.contains("deleteEventSeries(input: $input)") == true)
    #expect((series["query"] as? String)?.contains("EventSeriesDeleteInput!") == true)
}

@Test func doorListsTonightsAdmissionsAndRefundsOne() async throws {
    let admission = #"{"id":"cover","amount":{"cents":1000,"currency":"usd"},"total":{"cents":1120,"currency":"usd"},"status":"PAID","checkedInAt":null,"scanCount":0,"createdAt":"2026-10-10T04:00:00Z","profile":{"id":"u-ada","name":"Ada","avatarUrl":null}}"#
    let stub = Stub { request in
        let query = (try? request.jsonBody()["query"] as? String) ?? ""
        if query.contains("refundAdmission") {
            return .json(status: 200, body: #"{"data":{"refundAdmission":{"admission":\#(admission.replacingOccurrences(of: "PAID", with: "REFUNDED"))}}}"#)
        }
        return .json(status: 200, body: #"{"data":{"venues":{"venue":{"tickets":{"cover":{"door":{"night":"2026-10-09","paidCount":1,"checkedInCount":0,"gross":{"cents":1000,"currency":"usd"},"admissions":{"nodes":[\#(admission)]}}}}}}}}"#)
    }
    let client = venueClient(stub)
    let door = try #require(try await client.door(venueID: "venue"))
    #expect(door.admissions.first?.profile.name == "Ada")
    #expect(door.gross == .usd(1000) && door.admissions.first?.total.cents == 1120)
    let night = try #require(stub.requests.last).jsonBody()
    #expect((night["variables"] as? [String: Any])?["night"] is NSNull)
    let refunded = try await client.refundAdmission(id: "cover")
    #expect(refunded.status == "REFUNDED")
    let refund = try #require(stub.requests.last).jsonBody()
    #expect(((refund["variables"] as? [String: Any])?["input"] as? [String: Any])?["admissionId"] as? String == "cover")
}

@Test func listingUpdateSendsSocialProfilesOnlyWhenGiven() async throws {
    let venue = #"{"id":"venue","name":"Velvet","locale":{"name":"Seattle"},"upcomingEvents":{"upcoming":{"nodes":[]}},"tickets":{"cover":{"canWorkDoor":true,"timeZone":"America/Los_Angeles"}},"profile":{"address":null,"phone":null,"website":null,"socialLinks":{"nodes":[{"provider":"instagram","handle":"velvet","url":null}]}}}"#
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{"updateVenue":{"venue":\#(venue)}}}"#) }
    let client = venueClient(stub)
    let current = try JSONDecoder().decode(VenueWorkspace.self, from: Data(venue.replacingOccurrences(
        of: #"{"provider":"instagram","handle":"velvet","url":null}"#,
        with: #"{"provider":"instagram","handle":"old","url":null},{"provider":"x","handle":"velvet","url":null}"#).utf8))
    let links = current.socialLinks(replacing: ["instagram": "velvet", "tiktok": ""])
    #expect(links == [SocialLinkInput(provider: "x", handle: "velvet"), SocialLinkInput(provider: "instagram", handle: "velvet")])
    let updated = try await client.updateVenue(id: "venue", name: "Velvet", description: "", website: "", socialLinks: links, phone: "")
    #expect(updated.instagram == "velvet")
    #expect(updated.coverTimeZone == "America/Los_Angeles")
    let fields = try #require(try lastInput(stub)["venue"] as? [String: Any])
    let sent = try #require(fields["socialLinks"] as? [[String: Any]])
    #expect(sent.map { $0["provider"] as? String } == ["x", "instagram"])
    #expect(fields["instagram"] == nil)
    #expect(fields["phone"] as? String == "")
    #expect(fields["photo"] == nil)
    _ = try await client.updateVenue(id: "venue", name: "Velvet", description: "", website: "")
    let plain = try #require(try lastInput(stub)["venue"] as? [String: Any])
    #expect(plain["socialLinks"] == nil)
}

@Test func coverHoursGoToTheListingAndToDevices() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{}}"#) }
    let client = venueClient(stub)
    try await client.saveCover(venueID: "venue", cents: 1000, days: [5, 6], timeZone: "America/Los_Angeles", feePayer: "BUYER", from: "21:00", until: "02:00")
    let listing = try #require(try lastInput(stub)["venue"] as? [String: Any])
    #expect(listing["coverFrom"] as? String == "21:00")
    #expect(listing["coverUntil"] as? String == "02:00")
    try await client.saveCover(venueID: "venue", cents: 1000, days: [], timeZone: "America/Los_Angeles", feePayer: "BUYER", from: "21:00", device: true)
    let device = try lastInput(stub)
    #expect(device["venueId"] as? String == "venue")
    #expect(device["from"] as? String == "21:00")
    #expect(device["until"] == nil && device["coverFrom"] == nil)
    try await client.saveCover(venueID: "venue", cents: 1000, days: [], timeZone: "America/Los_Angeles", feePayer: "BUYER", from: "", until: "")
    let cleared = try #require(try lastInput(stub)["venue"] as? [String: Any])
    #expect(cleared["coverFrom"] is NSNull && cleared["coverUntil"] is NSNull)
    try await client.saveCover(venueID: "venue", cents: 1000, days: [], timeZone: "America/Los_Angeles", feePayer: "BUYER", from: "", until: "", device: true)
    let clearedDevice = try lastInput(stub)
    #expect(clearedDevice["from"] is NSNull && clearedDevice["until"] is NSNull)
}

@Test func screenDeviceMayFetchMusicAsTheAPIAllows() throws {
    let json = #"{"id":"g","venue_id":"v","permissions":["screen"],"expires_at":"2026-11-01T00:00:00Z","audience":{"id":"a","name":"A","subdomain":"a"}}"#
    let device = try JSONDecoder().decode(VenueDeviceSession.self, from: Data(json.utf8))
    #expect(device.permits("screen"))
    #expect(device.permits("music"))
    #expect(!device.permits("door"))
}
