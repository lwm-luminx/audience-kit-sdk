import Foundation
import Testing
import AudienceKit
import StaffKitCore
import StaffKitServices

private let backstagePerson = #"{"id":"mine","name":"Talent","avatarUrl":null,"profile":{"socialLinks":{"nodes":[]}},"music":{"links":{"nodes":[]}},"tipping":{"options":[]},"talentEvents":{"involvements":{"edges":[]}}}"#

@Test func backstageFiltersPeopleByAuthorizedIDsRatherThanNames() async throws {
    let other = backstagePerson.replacingOccurrences(of: "mine", with: "other")
    let stub = Stub { _ in .json(status: 200, body: """
        {"data":{"me":{"listings":{"people":[{"id":"mine"}],"troupes":[]}},"people":{"list":{"nodes":[\(backstagePerson),\(other)]}}}}
        """) }
    let focus = AudienceManagementSession(baseURL: stub.baseURL, credentialStore: InMemoryCredentialStore(credential: makeCredential(audienceID: "audience", on: stub.baseURL)), session: stub.session)
    let client = TalentManagementClient(session: focus)
    #expect(try await client.people(isAdministrator: false).map(\.id) == ["mine"])
    #expect(try await client.people(isAdministrator: true).count == 2)
    #expect(stub.requests.last?.path == "/v1/audience/audience/staffql")
}

@Test func backstageListsTroupeEventsWithTheTroupeTheyComeThrough() async throws {
    let event = #"{"id":"e-1","name":"Brunch","description":null,"startAt":null,"endAt":null,"isCanceled":false,"venue":{"name":"Purr"},"tickets":{"url":null},"bannerUrl":null,"people":{"lineup":{"nodes":[]}},"eventSeries":null,"seriesOverride":false}"#
    let person = backstagePerson.replacingOccurrences(of: #""edges":[]"#, with: """
        "edges":[{"role":"performer","via":{"id":"troupe","name":"Those Bitches"},"node":\(event)}]
        """)
    let stub = Stub { _ in .json(status: 200, body: """
        {"data":{"me":{"listings":{"people":[{"id":"mine"}],"troupes":[]}},"people":{"list":{"nodes":[\(person)]}}}}
        """) }
    let focus = AudienceManagementSession(baseURL: stub.baseURL, credentialStore: InMemoryCredentialStore(credential: makeCredential(audienceID: "audience", on: stub.baseURL)), session: stub.session)
    let mine = try #require(try await TalentManagementClient(session: focus).people(isAdministrator: false).first)
    #expect(mine.events.map(\.id) == ["e-1"])
    #expect(mine.involvements.first?.via?.name == "Those Bitches")
    #expect(mine.involvements.first?.role == "performer")
}

@Test func backstageOneOffEventIsOwnedByTheListing() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{"createEvent":{"event":{"id":"e-1"}}}}"#) }
    let focus = AudienceManagementSession(baseURL: stub.baseURL, credentialStore: InMemoryCredentialStore(credential: makeCredential(audienceID: "audience", on: stub.baseURL)), session: stub.session)
    try await TalentManagementClient(session: focus).createEvent(personID: "performer", fields: ["name": .string("Show"), "startAt": .string("2026-11-01T04:00:00Z")])
    let body = try #require(stub.requests.last).jsonBody()
    #expect((body["query"] as? String)?.contains("createEvent(input: $input)") == true)
    let input = try #require((body["variables"] as? [String: Any])?["input"] as? [String: Any])
    let event = try #require(input["event"] as? [String: Any])
    #expect(event["ownerPersonId"] as? String == "performer")
    #expect(event["name"] as? String == "Show")
}

@Test func backstageSeriesCreationUsesPersonOwnershipAndEditPreservesRelationships() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{}}"#) }
    let focus = AudienceManagementSession(baseURL: stub.baseURL, credentialStore: InMemoryCredentialStore(credential: makeCredential(audienceID: "audience", on: stub.baseURL)), session: stub.session)
    let client = TalentManagementClient(session: focus)
    try await client.saveSeries(id: nil, personID: "performer", fields: ["name": .string("Show"), "rrule": .string("FREQ=WEEKLY;BYDAY=FR")])
    let create = try #require(stub.requests.last).jsonBody()
    let input = try #require((create["variables"] as? [String: Any])?["input"] as? [String: Any])
    let fields = try #require(input["eventSeries"] as? [String: Any])
    #expect(fields["ownerPersonId"] as? String == "performer")
    #expect(fields["ownerVenueId"] == nil)
    #expect(fields["venueId"] == nil)
    try await client.saveSeries(id: "series", personID: "performer", fields: ["name": .string("New name")])
    let edit = try #require(stub.requests.last).jsonBody()
    let editInput = try #require((edit["variables"] as? [String: Any])?["input"] as? [String: Any])
    let editFields = try #require(editInput["eventSeries"] as? [String: Any])
    #expect(editInput["id"] as? String == "series")
    #expect(editFields["ownerPersonId"] == nil)
    #expect(editFields["rrule"] == nil)
    #expect(editFields["hostIds"] == nil)
    #expect(editFields["venueId"] == nil)
}

@Test func backstageProfileOnlyWritesSupportedListingFields() async throws {
    let stub = Stub { _ in .json(status: 200, body: "{\"data\":{\"updatePerson\":{\"person\":\(backstagePerson)}}}") }
    let focus = AudienceManagementSession(baseURL: stub.baseURL, credentialStore: InMemoryCredentialStore(credential: makeCredential(audienceID: "audience", on: stub.baseURL)), session: stub.session)
    let person = try JSONDecoder().decode(ManagedPerson.self, from: Data(backstagePerson.replacingOccurrences(
        of: #""socialLinks":{"nodes":[]}"#,
        with: #""socialLinks":{"nodes":[{"id":"l1","provider":"youtube","handle":"@talent","url":null},{"id":"l2","provider":"instagram","handle":"old","url":null}]}"#).utf8))
    let links = person.socialLinks(replacing: ["instagram": "", "tiktok": "talent", "cashapp": "", "venmo": "talent"])
    #expect(links == [SocialLinkInput(provider: "youtube", handle: "@talent"), SocialLinkInput(provider: "tiktok", handle: "talent"),
                      SocialLinkInput(provider: "venmo", handle: "talent")])
    _ = try await TalentManagementClient(session: focus).updateProfile(id: "mine", name: "Talent", socialLinks: links)
    let request = try #require(stub.requests.last).jsonBody()
    let input = try #require((request["variables"] as? [String: Any])?["input"] as? [String: Any])
    let fields = try #require(input["person"] as? [String: Any])
    #expect(Set(fields.keys) == Set(["name", "socialLinks"]))
    let sent = try #require(fields["socialLinks"] as? [[String: Any]])
    #expect(sent.map { $0["provider"] as? String } == ["youtube", "tiktok", "venmo"])
    #expect(sent.first?["handle"] as? String == "@talent")
}

@Test func socialLinkInputsKnowTheirProviderByHost() {
    #expect(SocialLinkInput.provider(ofLink: "https://open.spotify.com/artist/1") == "spotify")
    #expect(SocialLinkInput.provider(ofLink: "www.soundcloud.com/group") == "soundcloud")
    #expect(SocialLinkInput.provider(ofLink: "https://bandcamp.com/x") == "bandcamp")
    #expect(SocialLinkInput.provider(ofLink: "@group") == nil)
    let grouped = SocialLinkInput.grouped(links: [" https://soundcloud.com/group ", "", "music.apple.com/us/artist/x/1"], providers: ["soundcloud", "spotify", "apple_music"])
    #expect(grouped == ["soundcloud": ["https://soundcloud.com/group"], "spotify": [], "apple_music": ["music.apple.com/us/artist/x/1"]])
}

@Test func backstageNeverTreatsEmptyListingIDsAsAdminAccess() async throws {
    let stub = Stub { _ in .json(status: 200, body: "{\"data\":{\"me\":{\"listings\":{\"people\":[],\"troupes\":[]}},\"people\":{\"list\":{\"nodes\":[\(backstagePerson)]}}}}") }
    let focus = AudienceManagementSession(baseURL: stub.baseURL, credentialStore: InMemoryCredentialStore(credential: makeCredential(audienceID: "audience", on: stub.baseURL)), session: stub.session)
    #expect(try await TalentManagementClient(session: focus).people(isAdministrator: false).isEmpty)
}

@Test func backstageOnlyOffersManagedVenuesAndKeepsLocalesAvailable() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{"me":{"listings":{"venues":[{"id":"own"}]}},"venues":{"list":{"nodes":[{"id":"own","name":"Managed"},{"id":"other","name":"Other"}]}},"locales":[{"id":"city","name":"City"}]}}"#) }
    let focus = AudienceManagementSession(baseURL: stub.baseURL, credentialStore: InMemoryCredentialStore(credential: makeCredential(audienceID: "audience", on: stub.baseURL)), session: stub.session)
    let client = TalentManagementClient(session: focus)
    let listingLocations = try await client.locations(isAdministrator: false)
    #expect(listingLocations.venues.map(\.id) == ["own"])
    #expect(listingLocations.locales.map(\.id) == ["city"])
    #expect(try await client.locations(isAdministrator: true).venues.count == 2)
}

@Test func backstageKeepsSoloAndGroupListingsSeparateForOneAccount() async throws {
    let solo = backstagePerson.replacingOccurrences(of: "mine", with: "anya").replacingOccurrences(of: "Talent", with: "Anya Bacon")
    let group = backstagePerson.replacingOccurrences(of: "mine", with: "group").replacingOccurrences(of: "Talent", with: "Those Bitches")
    let stub = Stub { request in
        let query = (try? request.jsonBody()["query"] as? String) ?? ""
        if query.contains("BackstagePeople") {
            return .json(status: 200, body: "{\"data\":{\"me\":{\"listings\":{\"people\":[{\"id\":\"anya\"},{\"id\":\"group\"}],\"troupes\":[]}},\"people\":{\"list\":{\"nodes\":[\(solo),\(group),\(backstagePerson)]}}}}")
        }
        return .json(status: 200, body: #"{"data":{}}"#)
    }
    let focus = AudienceManagementSession(baseURL: stub.baseURL, credentialStore: InMemoryCredentialStore(credential: makeCredential(audienceID: "audience", on: stub.baseURL)), session: stub.session)
    let client = TalentManagementClient(session: focus)
    let listings = try await client.people(isAdministrator: false)
    #expect(listings.map(\.name) == ["Anya Bacon", "Those Bitches"])
    for listing in listings {
        try await client.saveSeries(id: nil, personID: listing.id, fields: ["name": .string("Show")])
        let request = try #require(stub.requests.last).jsonBody()
        let input = try #require((request["variables"] as? [String: Any])?["input"] as? [String: Any])
        let fields = try #require(input["eventSeries"] as? [String: Any])
        #expect(fields["ownerPersonId"] as? String == listing.id)
    }
}

@Test func backstageMarksTroupesReachedThroughAMemberListing() async throws {
    let troupe = backstagePerson.replacingOccurrences(of: "mine", with: "troupe")
    let stub = Stub { _ in .json(status: 200, body: """
        {"data":{"me":{"listings":{"people":[{"id":"mine"},{"id":"troupe"}],"troupes":[{"id":"troupe"}]}},"people":{"list":{"nodes":[\(backstagePerson),\(troupe)]}}}}
        """) }
    let focus = AudienceManagementSession(baseURL: stub.baseURL, credentialStore: InMemoryCredentialStore(credential: makeCredential(audienceID: "audience", on: stub.baseURL)), session: stub.session)
    let listings = try await TalentManagementClient(session: focus).listings(isAdministrator: false)
    #expect(listings.people.map(\.id) == ["mine", "troupe"])
    #expect(listings.troupeIDs == ["troupe"])
    let query = try #require(stub.requests.last).jsonBody()["query"] as? String
    #expect(query?.contains("listings { people { id } troupes { id } }") == true)
}

@Test func backstageEventsKnowTheirHostsAndWhereTheirLineupIs() async throws {
    let event = #"{"id":"e-1","name":"Brunch","description":null,"startAt":"2026-10-18T18:00:00Z","endAt":null,"isCanceled":false,"venue":{"name":"Purr","venue":{"id":"purr","tickets":{"cover":{"timeZone":"America/Los_Angeles"}}}},"tickets":{"url":null},"bannerUrl":null,"people":{"lineup":{"nodes":[{"id":"mine","name":"Talent"}]},"hosts":{"nodes":[{"id":"mine","name":"Talent"}]}},"eventSeries":null,"seriesOverride":false}"#
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{"events":{"event":\#(event)}}}"#) }
    let focus = AudienceManagementSession(baseURL: stub.baseURL, credentialStore: InMemoryCredentialStore(credential: makeCredential(audienceID: "audience", on: stub.baseURL)), session: stub.session)
    let loaded = try #require(try await TalentManagementClient(session: focus).event(id: "e-1"))
    #expect(loaded.hostIDs == ["mine"])
    let place = try #require(loaded.lineupPlace)
    #expect(place.venueID == "purr" && place.zone.identifier == "America/Los_Angeles" && place.night == "2026-10-18" && place.event?.id == "e-1")
    let query = try #require(stub.requests.last).jsonBody()["query"] as? String ?? ""
    #expect(query.contains("hosts { nodes { id name } }") && query.contains("venue { name venue { id tickets { cover { timeZone } } } }"))

    let tba = #"{"id":"e-2","name":"TBA","description":null,"startAt":null,"endAt":null,"isCanceled":false,"venue":null,"tickets":{"url":null},"bannerUrl":null,"people":{"lineup":{"nodes":[]}},"eventSeries":null,"seriesOverride":false}"#
    let other = Stub { _ in .json(status: 200, body: #"{"data":{"events":{"event":\#(tba)}}}"#) }
    let session = AudienceManagementSession(baseURL: other.baseURL, credentialStore: InMemoryCredentialStore(credential: makeCredential(audienceID: "audience", on: other.baseURL)), session: other.session)
    let unplaced = try #require(try await TalentManagementClient(session: session).event(id: "e-2"))
    #expect(unplaced.lineupPlace == nil && unplaced.hostIDs.isEmpty)
}
