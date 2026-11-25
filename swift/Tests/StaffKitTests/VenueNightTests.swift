import Foundation
import Testing
import AudienceKit
import StaffKitCore
import StaffKitServices

private func client(_ stub: Stub) -> VenueManagementClient {
    VenueManagementClient(session: AudienceManagementSession(baseURL: stub.baseURL, credentialStore: InMemoryCredentialStore(credential: makeCredential(audienceID: "audience", on: stub.baseURL)), session: stub.session))
}
private func body(_ stub: Stub) throws -> (query: String, variables: [String: Any], input: [String: Any]) {
    let body = try #require(stub.requests.last).jsonBody()
    let variables = body["variables"] as? [String: Any] ?? [:]
    return (body["query"] as? String ?? "", variables, variables["input"] as? [String: Any] ?? [:])
}
private let appearance = #"{"id":"on","role":"DJ","startsAt":"2026-10-10T04:00:00Z","endsAt":null,"person":{"id":"ada","name":"Ada","avatarUrl":null}}"#

@Test func aNightReadsItsLineupCoverAndChanges() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{"venues":{"venue":{"tickets":{"cover":{"charge":{"amount":{"cents":500,"currency":"usd"},"total":{"cents":560,"currency":"usd"},"payable":true,"night":"2026-10-09","from":"22:00","until":null,"override":true},"nights":[{"night":"2026-10-09","coverCents":500,"from":"22:00","until":null}]}},"people":{"lineup":{"nodes":[\#(appearance)]},"onNow":{"nodes":[{"id":"mc","role":"STILT_WALKER","startsAt":"2026-10-10T03:00:00Z","endsAt":null,"person":{"id":"bo","name":"Bo","avatarUrl":null}}]}}}}}}"#) }
    let night = try await client(stub).night(venueID: "venue", night: "2026-10-09")
    #expect(night.lineup.first?.role == .dj)
    #expect(night.onNow.first?.role?.rawValue == "STILT_WALKER")
    #expect(night.coverCharge?.override == true && night.coverCharge?.amount == .usd(500))
    #expect(night.coverNight?.coverCents == 500)
    let (query, variables, _) = try body(stub)
    #expect(query.contains("people {") && query.contains("lineup(night: $night)") && query.contains("onNow") && query.contains("nights {"))
    #expect(variables["night"] as? String == "2026-10-09")
    _ = try await client(stub).night(venueID: "venue")
    #expect(try body(stub).variables["night"] is NSNull)
}

@Test func lineupChangesUseTheAppearanceMutations() async throws {
    let stub = Stub { request in
        let query = (try? request.jsonBody()["query"] as? String) ?? ""
        if query.contains("createAppearance") { return .json(status: 200, body: #"{"data":{"createAppearance":{"appearance":\#(appearance)}}}"#) }
        if query.contains("updateAppearance") { return .json(status: 200, body: #"{"data":{"updateAppearance":{"appearance":\#(appearance)}}}"#) }
        return .json(status: 200, body: #"{"data":{"deleteAppearance":{"appearance":null}}}"#)
    }
    let venues = client(stub)
    let added = try await venues.addAppearance(venueID: "venue", personID: "ada", role: .dj, startsAt: "2026-10-10T04:00:00Z", endsAt: nil)
    #expect(added.person?.name == "Ada")
    var sent = try body(stub)
    #expect(sent.query.contains("AppearanceCreateInput!"))
    #expect(sent.input["venueId"] as? String == "venue")
    let fields = try #require(sent.input["appearance"] as? [String: Any])
    #expect(fields["personId"] as? String == "ada")
    #expect(fields["role"] as? String == "DJ")
    #expect(fields["endsAt"] is NSNull)

    _ = try await venues.updateAppearance(id: "on", fields: ["endsAt": .string("2026-10-10T06:00:00Z")])
    sent = try body(stub)
    #expect(sent.query.contains("updateAppearance(input: $input)"))
    #expect(sent.input["id"] as? String == "on")
    #expect((sent.input["appearance"] as? [String: Any])?.keys.sorted() == ["endsAt"])

    try await venues.deleteAppearance(id: "on")
    sent = try body(stub)
    #expect(sent.query.contains("deleteAppearance(input: $input)"))
    #expect(sent.input["id"] as? String == "on")
}

@Test func aNightsCoverIsSetAndCleared() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{}}"#) }
    let venues = client(stub)
    try await venues.setCoverNight(venueID: "venue", night: "2026-10-09", amount: .usd(0), from: nil, until: "02:00")
    var sent = try body(stub)
    #expect(sent.query.contains("setCoverNight(input: $input)") && sent.query.contains("CoverNightSetInput!"))
    #expect(sent.input["night"] as? String == "2026-10-09")
    #expect((sent.input["amount"] as? [String: Any])?["cents"] as? Int == 0)
    #expect((sent.input["amount"] as? [String: Any])?["currency"] as? String == "usd")
    #expect(sent.input["from"] is NSNull)
    #expect(sent.input["until"] as? String == "02:00")
    try await venues.setCoverNight(venueID: "venue", night: "2026-10-09", amount: nil, from: "22:00", until: nil)
    #expect(try body(stub).input["amount"] is NSNull)
    try await venues.clearCoverNight(venueID: "venue", night: "2026-10-09")
    sent = try body(stub)
    #expect(sent.query.contains("clearCoverNight(input: $input)"))
    #expect(sent.input.keys.sorted() == ["night", "venueId"])
}

private let post = #"{"id":"post","body":"Doors at 9","photoUrl":null,"pinned":true,"createdAt":"2026-10-09T20:00:00Z","updatedAt":"2026-10-09T20:00:00Z","event":null,"eventSeries":{"id":"series","name":"Fridays"},"viewerCanManage":true,"commentCount":1,"comments":{"nodes":[{"id":"c1","body":"See you","createdAt":"2026-10-09T20:05:00Z","authorId":"guest-1","authorName":"Aurora B.","authorAvatarUrl":null,"viewerCanRemove":true}]}}"#

@Test func postsAreReadFromTheirTarget() async throws {
    let stub = Stub { request in
        let query = (try? request.jsonBody()["query"] as? String) ?? ""
        if query.contains("eventSeries(id:") { return .json(status: 200, body: #"{"data":{"events":{"eventSeries":{"posts":{"list":{"nodes":[\#(post)]}}}}}}"#) }
        if query.contains("post(id:") { return .json(status: 200, body: #"{"data":{"posts":{"post":\#(post)}}}"#) }
        if query.contains("event(id:") { return .json(status: 200, body: #"{"data":{"events":{"event":{"posts":{"list":{"nodes":[\#(post)]}}}}}}"#) }
        return .json(status: 200, body: #"{"data":{"venues":{"venue":{"posts":{"list":{"nodes":[\#(post)]}}}}}}"#)
    }
    let venues = client(stub)
    let posts = try await venues.posts(on: .venue(id: "venue"))
    #expect(posts.first?.eventSeries?.name == "Fridays")
    #expect(try body(stub).query.contains("posts { list(first: 30)"))
    // Lists leave comments out, to stay under the API's complexity limit; one post brings them.
    #expect(try !body(stub).query.contains("comments("))
    #expect(try await venues.post(id: "post")?.comments.first?.authorName == "Aurora B.")
    #expect(try await venues.post(id: "post")?.comments.first?.authorId == "guest-1")
    #expect(try body(stub).query.contains("comments(first: 50)"))
    #expect(try await venues.posts(on: .event(id: "event")).count == 1)
    #expect(try body(stub).variables["id"] as? String == "event")
    #expect(try await venues.posts(on: .series(id: "series", venueID: "venue")).first?.id == "post")
    #expect(try body(stub).variables["id"] as? String == "series")
}

@Test func postsAreWrittenOnExactlyOneTarget() async throws {
    let stub = Stub { request in
        let query = (try? request.jsonBody()["query"] as? String) ?? ""
        if query.contains("createPost") { return .json(status: 200, body: #"{"data":{"createPost":{"post":\#(post)}}}"#) }
        if query.contains("updatePost") { return .json(status: 200, body: #"{"data":{"updatePost":{"post":\#(post)}}}"#) }
        return .json(status: 200, body: #"{"data":{}}"#)
    }
    let venues = client(stub)
    _ = try await venues.createPost(on: .series(id: "series", venueID: "venue"), body: "Doors at 9", photo: "data:image/jpeg;base64,AAAA", pinned: true)
    var sent = try body(stub)
    #expect(sent.query.contains("PostCreateInput!"))
    #expect(sent.input["eventSeriesId"] as? String == "series")
    #expect(sent.input["venueId"] == nil && sent.input["eventId"] == nil)
    #expect(sent.input["pinned"] as? Bool == true)
    #expect(sent.input["photo"] as? String == "data:image/jpeg;base64,AAAA")

    _ = try await venues.updatePost(id: "post", photo: "", pinned: false)
    sent = try body(stub)
    #expect(sent.input.keys.sorted() == ["id", "photo", "pinned"])
    #expect(sent.input["photo"] as? String == "")

    try await venues.deletePost(id: "post")
    #expect(try body(stub).query.contains("deletePost(input: $input)"))
    try await venues.removePostComment(id: "c1")
    sent = try body(stub)
    #expect(sent.query.contains("removePostComment(input: $input)") && sent.query.contains("PostCommentRemoveInput!"))
    #expect(sent.input["id"] as? String == "c1")
}

private let photo = #"{"id":"photo","url":"https://cdn.example/p.jpg","caption":null,"altText":null,"takenAt":null,"width":800,"height":1000,"isHidden":true,"photographer":{"name":"Lens"},"event":null}"#

@Test func photosIncludeHiddenOnesAndCanBeHiddenOrShown() async throws {
    let stub = Stub { request in
        let query = (try? request.jsonBody()["query"] as? String) ?? ""
        if query.contains("hideEventPhoto") { return .json(status: 200, body: #"{"data":{"hideEventPhoto":{"photo":\#(photo)}}}"#) }
        if query.contains("showEventPhoto") { return .json(status: 200, body: #"{"data":{"showEventPhoto":{"photo":\#(photo)}}}"#) }
        return .json(status: 200, body: #"{"data":{"events":{"event":{"photography":{"photos":{"nodes":[\#(photo)]}}}}}}"#)
    }
    let venues = client(stub)
    let photos = try await venues.photos(of: .event(id: "event"))
    #expect(photos.first?.isHidden == true)
    #expect(photos.first?.photographer.name == "Lens")
    #expect(try body(stub).query.contains("includeHidden: true"))
    _ = try await venues.hidePhoto(id: "photo", reason: "Blurry")
    var sent = try body(stub)
    #expect(sent.query.contains("EventPhotoHideInput!"))
    #expect(sent.input["reason"] as? String == "Blurry")
    _ = try await venues.hidePhoto(id: "photo", reason: "")
    #expect(try body(stub).input["reason"] == nil)
    _ = try await venues.showPhoto(id: "photo")
    sent = try body(stub)
    #expect(sent.query.contains("showEventPhoto(input: $input)"))
    #expect(sent.input["id"] as? String == "photo")
}

@Test func venuesReadActivityAndCoverEnd() async throws {
    let venue = #"{"id":"venue","name":"Velvet","locale":{"name":"Seattle"},"upcomingEvents":{"upcoming":{"nodes":[]}},"tickets":{"cover":{"canWorkDoor":true,"until":"02:00"}},"activity":{"pinging":{"atLeast":5,"label":"5+"},"hereLastHour":{"atLeast":1,"label":"A few"}}}"#
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{"me":{"cover":{"doorVenues":{"nodes":[\#(venue)]}}}}}"#) }
    let workspace = try #require(try await client(stub).venues().first)
    #expect(workspace.activity?.pinging.label == "5+")
    #expect(workspace.activity?.hereLastHour.atLeast == 1)
    #expect(workspace.coverUntil == "02:00")
    #expect(try body(stub).query.contains("hereLastHour { atLeast label }"))
}

@Test func aVenueListReadsNoEventsAndTheOpenVenueReadsInFull() async throws {
    let light = #"{"id":"venue","name":"Velvet","locale":{"name":"Seattle"},"profile":{"address":"1 Pike St"}}"#
    let listStub = Stub { _ in .json(status: 200, body: #"{"data":{"me":{"cover":{"doorVenues":{"nodes":[\#(light)]}}}}}"#) }
    let listed = try #require(try await client(listStub).venues(detailed: false).first)
    #expect(!listed.isDetailed)
    #expect(listed.address == "1 Pike St")
    let listQuery = try body(listStub).query
    #expect(!listQuery.contains("upcomingEvents"))

    let full = #"{"id":"venue","name":"Velvet","locale":{"name":"Seattle"},"upcomingEvents":{"upcoming":{"nodes":[]}}}"#
    let venueStub = Stub { _ in .json(status: 200, body: #"{"data":{"venues":{"venue":\#(full)}}}"#) }
    let opened = try #require(try await client(venueStub).venue(id: "venue"))
    #expect(opened.isDetailed)
    let sent = try body(venueStub)
    #expect(sent.query.contains("venue(id: $id)") && sent.query.contains("upcomingEvents"))
}

@Test func anOutdatedSDKIsReportedOnceForAnyCall() async throws {
    let stub = Stub { _ in .json(status: 426, body: #"{"error":"update_required","platform":"ios","minimum_sdk_version":"9.0.0","message":"Update to keep going."}"#) }
    let session = AudienceManagementSession(baseURL: stub.baseURL, credentialStore: InMemoryCredentialStore(credential: makeCredential(audienceID: "audience", on: stub.baseURL)), session: stub.session)
    var updates = session.updatesRequired.makeAsyncIterator()
    await #expect(throws: AudienceKitError.updateRequired(minimumSDKVersion: "9.0.0", message: "Update to keep going.")) {
        _ = try await VenueManagementClient(session: session).venues()
    }
    #expect(await updates.next() == UpdateRequirement(minimumSDKVersion: "9.0.0", message: "Update to keep going."))
}

@Test func statusSaysWhenThisSDKIsTooOld() async throws {
    let stub = Stub { request in
        #expect(request.path == "/v1/status")
        #expect(request.header("Authorization") == nil)
        return .json(status: 200, body: #"{"api":{"version":"2026-10-11","sdk":{"ios":{"minimumVersion":"99.0"},"android":{"minimumVersion":"0.1.0"}}}}"#)
    }
    let session = AudienceManagementSession(baseURL: stub.baseURL, session: stub.session)
    var updates = session.updatesRequired.makeAsyncIterator()
    let requirement = await session.checkForRequiredUpdate()
    #expect(requirement?.minimumSDKVersion == "99.0")
    #expect(await updates.next()?.minimumSDKVersion == "99.0")

    let current = Stub { _ in .json(status: 200, body: #"{"api":{"sdk":{"ios":{"minimumVersion":"0.1.0"}}}}"#) }
    #expect(await AudienceManagementSession(baseURL: current.baseURL, session: current.session).checkForRequiredUpdate() == nil)
}

private let duet = #"{"id":"duet","kind":"ACT","role":"PERFORMER","title":null,"position":1,"startTiming":"NONE","endTiming":"ADVANCE","state":"ON","startsAt":"2026-10-10T05:00:00Z","endsAt":null,"wentOnAt":"2026-10-10T05:00:00Z","cameOffAt":null,"person":{"id":"ada","name":"Ada","avatarUrl":null},"people":{"nodes":[{"id":"ada","name":"Ada","avatarUrl":null},{"id":"bo","name":"Bo","avatarUrl":null}]}}"#
private let intermission = #"{"id":"break","kind":"INTERMISSION","role":null,"title":null,"position":2,"startTiming":"NONE","endTiming":"ADVANCE","state":"UPCOMING","startsAt":null,"endsAt":null,"wentOnAt":null,"cameOffAt":null,"person":null,"people":{"nodes":[]}}"#

@Test func aNightReadsItsRunningOrderWithDuetsAndIntermissions() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{"venues":{"venue":{"tickets":null,"people":{"lineup":{"nodes":[\#(appearance),\#(duet)]},"onNow":{"nodes":[\#(duet)]},"runningOrder":{"nodes":[\#(appearance),\#(duet),\#(intermission)]},"onStage":\#(duet),"upNext":\#(intermission)}}}}}"#) }
    let night = try await client(stub).night(venueID: "venue")
    #expect(night.runningOrder.map(\.id) == ["on", "duet", "break"])
    #expect(night.onStage?.displayName == "Ada and Bo")
    #expect(night.onStage?.status == .on && night.onStage?.isAdvanceable == true)
    #expect(night.upNext?.isIntermission == true && night.upNext?.displayName == "Intermission" && night.upNext?.person == nil)
    // An entry from an API before running orders: a hard-timed act on until close.
    let old = try #require(night.runningOrder.first)
    #expect(old.startTiming == .hard && old.endTiming == .close && old.people.map(\.id) == ["ada"] && !old.isAdvanceable)
    let query = try body(stub).query
    #expect(query.contains("runningOrder(night: $night)") && query.contains("onStage {") && query.contains("upNext {"))
}

@Test func theRunningOrderIsAdvancedAndReordered() async throws {
    let stub = Stub { request in
        let query = (try? request.jsonBody()["query"] as? String) ?? ""
        if query.contains("advanceLineup") { return .json(status: 200, body: #"{"data":{"advanceLineup":{"onStage":\#(intermission),"upNext":null,"runningOrder":[\#(duet),\#(intermission)]}}}"#) }
        if query.contains("reorderLineup") { return .json(status: 200, body: #"{"data":{"reorderLineup":{"runningOrder":[\#(intermission),\#(duet)]}}}"#) }
        return .json(status: 200, body: #"{"data":{"createAppearance":{"appearance":\#(intermission)}}}"#)
    }
    let venues = client(stub)
    let advanced = try await venues.advanceLineup(venueID: "venue")
    #expect(advanced.onStage?.id == "break" && advanced.upNext == nil && advanced.runningOrder.count == 2)
    var sent = try body(stub)
    #expect(sent.query.contains("LineupAdvanceInput!") && sent.input["venueId"] as? String == "venue" && sent.input["back"] as? Bool == false)
    _ = try await venues.advanceLineup(venueID: "venue", back: true)
    #expect(try body(stub).input["back"] as? Bool == true)

    let order = try await venues.reorderLineup(venueID: "venue", night: "2026-10-09", ids: ["break", "duet"])
    #expect(order.map(\.id) == ["break", "duet"])
    sent = try body(stub)
    #expect(sent.query.contains("LineupReorderInput!") && sent.input["ids"] as? [String] == ["break", "duet"] && sent.input["night"] as? String == "2026-10-09")

    let added = try await venues.addLineupEntry(venueID: "venue", fields: ["kind": .string("INTERMISSION"), "startTiming": .string("NONE"), "endTiming": .string("ADVANCE")])
    #expect(added.isIntermission)
    sent = try body(stub)
    #expect((sent.input["appearance"] as? [String: Any])?["kind"] as? String == "INTERMISSION")
}

@Test func anEventsLineupIsBuiltAheadAndAdvancedOnItsOwn() async throws {
    let onEvent = #"{"id":"queen","kind":"ACT","role":"PERFORMER","title":null,"position":0,"startTiming":"NONE","endTiming":"ADVANCE","state":"UPCOMING","startsAt":null,"endsAt":null,"wentOnAt":null,"cameOffAt":null,"person":{"id":"ada","name":"Ada","avatarUrl":null},"people":{"nodes":[{"id":"ada","name":"Ada","avatarUrl":null}]},"event":{"id":"brunch","name":"Drag Brunch","startAt":"2026-10-17T18:00:00Z"}}"#
    let stub = Stub { request in
        let query = (try? request.jsonBody()["query"] as? String) ?? ""
        if query.contains("advanceLineup") { return .json(status: 200, body: #"{"data":{"advanceLineup":{"onStage":\#(onEvent),"upNext":null,"runningOrder":[\#(onEvent)]}}}"#) }
        if query.contains("createAppearance") { return .json(status: 200, body: #"{"data":{"createAppearance":{"appearance":\#(onEvent)}}}"#) }
        return .json(status: 200, body: #"{"data":{"events":{"event":{"people":{"runningOrder":{"nodes":[\#(onEvent),\#(intermission)]}}}}}}"#)
    }
    let venues = client(stub)
    let lineup = try await venues.eventLineup(eventID: "brunch")
    #expect(lineup.map(\.id) == ["queen", "break"])
    #expect(lineup.first?.event?.name == "Drag Brunch" && lineup.last?.event == nil)
    var sent = try body(stub)
    #expect(sent.query.contains("event(id: $id)") && sent.query.contains("runningOrder { nodes {") && sent.variables["id"] as? String == "brunch")

    _ = try await venues.addLineupEntry(venueID: "venue", fields: ["eventId": .string("brunch"), "personIds": .array([.string("ada")])])
    #expect((try body(stub).input["appearance"] as? [String: Any])?["eventId"] as? String == "brunch")

    _ = try await venues.advanceLineup(venueID: "venue", eventID: "brunch")
    sent = try body(stub)
    #expect(sent.input["eventId"] as? String == "brunch")
    _ = try await venues.advanceLineup(venueID: "venue")
    #expect(try body(stub).input["eventId"] is NSNull)
}

@Test func anEventsHostsReorderJustItsLineup() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{"reorderLineup":{"runningOrder":[]}}}"#) }
    _ = try await client(stub).reorderLineup(venueID: "venue", night: "2026-10-17", eventID: "brunch", ids: ["break", "queen"])
    let sent = try body(stub)
    #expect(sent.input["eventId"] as? String == "brunch" && sent.input["ids"] as? [String] == ["break", "queen"])
    _ = try await client(stub).reorderLineup(venueID: "venue", night: nil, ids: [])
    #expect(try body(stub).input["eventId"] == nil)
}

@Test func aLineupsPlaceCountsNightsFromSixInTheMorning() throws {
    let zone = try #require(TimeZone(identifier: "America/Los_Angeles"))
    // 1 AM Saturday Oct 18 in Seattle is Friday night's.
    let event = VenueAppearance.Event(id: "late", name: "Late show", startAt: "2026-10-18T08:00:00Z")
    let place = LineupPlace(venueID: "venue", zone: zone, event: event, tonight: "2026-10-17")
    #expect(place.night == "2026-10-17" && place.isTonight && place.event?.id == "late")
    #expect(place.nightStart == parseInstant("2026-10-17T13:00:00Z"))
    #expect(place.eventStart == parseInstant("2026-10-18T08:00:00Z"))
    let undated = LineupPlace(venueID: "venue", zone: zone, event: .init(id: "tba", name: nil), tonight: "2026-10-20")
    #expect(undated.night == "2026-10-20")
}

private let singer = #"{"id":"s1","kind":"ACT","role":"SINGER","title":"Bo & Lee","position":3,"startTiming":"NONE","endTiming":"ADVANCE","state":"UPCOMING","startsAt":null,"endsAt":null,"person":null,"people":{"nodes":[]},"songRequest":{"id":"r1","title":"Islands in the Stream","artist":"Dolly Parton","singer":"Bo & Lee","note":"for Bo’s birthday","state":"QUEUED","requesterName":"Bo L."}}"#

@Test func aSingerReadsTheirSignup() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{"venues":{"venue":{"people":{"lineup":{"nodes":[]},"onNow":{"nodes":[]},"runningOrder":{"nodes":[\#(singer)]},"onStage":null,"upNext":\#(singer)}}}}}"#) }
    let night = try await client(stub).night(venueID: "venue")
    let entry = try #require(night.runningOrder.first)
    #expect(entry.role == .singer && entry.isSinger && entry.displayName == "Bo & Lee")
    #expect(entry.songRequest?.song == "Islands in the Stream · Dolly Parton")
    #expect(entry.songRequest?.note == "for Bo’s birthday" && entry.songRequest?.state == .queued)
    #expect(night.upNext?.songRequest?.id == "r1")
    #expect(!VenueAppearance.Role.all.contains(.singer))
    #expect(try body(stub).query.contains("songRequest { id title artist singer note state requesterName }"))
}

@Test func karaokeSignupsArePausedAndSingersSkipped() async throws {
    let window = #"{"permitted":true,"open":false,"paused":true,"closedReason":"Signups are paused","host":null}"#
    let stub = Stub { request in
        let query = (try? request.jsonBody()["query"] as? String) ?? ""
        if query.contains("updateVenue") { return .json(status: 200, body: #"{"data":{"updateVenue":{"venue":{"requests":{"karaoke":\#(window)}}}}}"#) }
        if query.contains("setSongRequestState") { return .json(status: 200, body: #"{"data":{"setSongRequestState":{"request":{"id":"r1","state":"SKIPPED"}}}}"#) }
        return .json(status: 200, body: #"{"data":{"venues":{"venue":{"requests":{"karaoke":\#(window)}}}}}"#)
    }
    let venues = client(stub)
    let signups = try await venues.karaokeSignups(venueID: "venue")
    #expect(signups.permitted && signups.paused && !signups.open && signups.closedReason == "Signups are paused")
    #expect(try body(stub).query.contains("requests { karaoke {"))

    let paused = try await venues.setKaraokePaused(venueID: "venue", true)
    #expect(paused.paused)
    var sent = try body(stub)
    #expect(sent.query.contains("VenueUpdateInput!"))
    #expect(sent.input["id"] as? String == "venue")
    #expect((sent.input["venue"] as? [String: Any])?["karaokePaused"] as? Bool == true)

    try await venues.setSongRequestState(id: "r1", .skipped)
    sent = try body(stub)
    #expect(sent.query.contains("setSongRequestState(input: $input)"))
    #expect(sent.input["id"] as? String == "r1" && sent.input["state"] as? String == "SKIPPED")
}
