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

private let goNoGoJSON = #"{"verdict":"NO_GO","curtainCall":{"id":"act-2","title":"The Queens"},"items":["#
    + #"{"id":"venue","area":"VENUE","state":"READY","note":null,"person":null,"staffAssignment":null},"#
    + #"{"id":"talent-ada","area":"TALENT","state":"NOT_READY","note":"Wig","person":{"id":"ada","name":"Ada","avatarUrl":null},"staffAssignment":null},"#
    + #"{"id":"staff-1","area":"STAFF","state":"PENDING","note":null,"person":null,"staffAssignment":{"id":"s-1","name":"Rick Mark","label":"Photography","mine":true}}],"#
    + #""counts":[{"area":"VENUE","ready":1,"total":1},{"area":"TALENT","ready":0,"total":1}]}"#

private let roundJSON = #"{"id":"r-1","statement":"Divine was in Hairspray.","choices":[{"label":"Myth","count":3},{"label":"Legend","count":9}],"#
    + #""voting":true,"closesAt":null,"driver":"HOST","answer":null,"roomCall":null,"revealsAtEnd":false,"revealedAt":null}"#

private let showJSON = #"{"data":{"venues":{"venue":{"people":{"runningOrder":{"nodes":["#
    + #"{"id":"act-1","entryKind":"ACT","activity":null,"curtainCallMinutes":10,"durationMinutes":null,"estimatedMinutes":14,"missingTracks":1,"#
    + #""projectedStartsAt":"2026-10-23T03:08:00Z","projectedEndsAt":"2026-10-23T03:22:00Z","lateMinutes":8,"flexible":false,"minMinutes":null,"#
    + #""extraMinutes":null,"triviaSet":null,"triviaDriver":null,"triviaReveal":null,"scenes":["#
    + #"{"id":"sc-1","title":"Toxic","seconds":null,"gapSeconds":null,"lengthSeconds":200,"performer":{"id":"ada","name":"Ada","avatarUrl":null},"track":{"id":"f-1","name":"toxic.mp3"}},"#
    + #"{"id":"sc-2","title":"Believe","seconds":240,"gapSeconds":null,"lengthSeconds":240,"performer":null,"track":null}]},"#
    + #"{"id":"seg-1","entryKind":"SEGMENT","activity":"TRIVIA","curtainCallMinutes":null,"durationMinutes":15,"estimatedMinutes":null,"missingTracks":0,"#
    + #""projectedStartsAt":null,"projectedEndsAt":null,"lateMinutes":null,"flexible":true,"minMinutes":5,"extraMinutes":null,"#
    + #""triviaSet":{"key":"drag-herstory","title":"Drag herstory"},"triviaDriver":"HOST","triviaReveal":"END","scenes":[]}]},"#
    + #""goNoGo":\#(goNoGoJSON),"supportStaff":[{"id":"s-1","name":"Rick Mark","label":"Photography","role":"PHOTOGRAPHY","title":null,"#
    + #""required":true,"callAt":null,"mine":true,"person":null}]},"#
    + #""trivia":{"current":\#(roundJSON),"segment":{"id":"seg-1"},"sets":[{"key":"drag-herstory","title":"Drag herstory"}]}}}}}"#

@Test func showControlReadsEntriesThePlacesCheckStaffAndTrivia() async throws {
    let stub = Stub { _ in .json(status: 200, body: showJSON) }
    let show = try await client(stub).showControl(venueID: "venue", night: "2026-10-22")

    #expect(show.entries.map(\.kind) == [.act, .segment])
    let act = try #require(show.entry("act-1"))
    #expect(act.hasCurtainCall && act.expectedMinutes == 14 && act.lateMinutes == 8 && act.missingTracks == 1)
    #expect(act.scenes.map(\.title) == ["Toxic", "Believe"] && act.scenes.first?.track?.name == "toxic.mp3")
    let segment = try #require(show.entry("seg-1"))
    #expect(segment.runsTrivia && segment.triviaReveal == "END" && segment.triviaSet?.key == "drag-herstory")

    let check = try #require(show.goNoGo)
    #expect(check.verdict == .noGo && check.curtainCall.title == "The Queens")
    #expect(check.holdouts.map(\.displayName) == ["Ada", "Rick Mark · Photography"])
    #expect(check.items.first?.displayName == "The venue")
    #expect(show.supportStaff.first?.role == .photography && show.supportStaff.first?.mine == true)
    #expect(show.trivia?.question == "Myth or Legend?" && show.trivia?.totalVotes == 12)
    #expect(show.triviaSegmentID == "seg-1" && show.triviaSets.map(\.title) == ["Drag herstory"])

    let sent = try #require(stub.requests.first).jsonBody()
    let query = sent["query"] as? String ?? ""
    #expect(query.contains("entryKind") && query.contains("goNoGo {") && query.contains("supportStaff(night: $night)"))
    #expect((sent["variables"] as? [String: Any])?["night"] as? String == "2026-10-22")
}

@Test func readinessAnswersForTheVenueTalentOrStaff() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{"setReadiness":{"goNoGo":\#(goNoGoJSON)}}}"#) }
    let check = try await client(stub).setReadiness(curtainCallID: "act-2", area: .staff, staffAssignmentID: "s-1",
                                                    state: .ready, note: "")
    #expect(check.verdict == .noGo)
    let (query, _, input) = try body(stub)
    #expect(query.contains("setReadiness(input: $input)"))
    #expect(input["curtainCallId"] as? String == "act-2" && input["area"] as? String == "STAFF")
    #expect(input["staffAssignmentId"] as? String == "s-1" && input["state"] as? String == "READY")
    #expect(!input.keys.contains("note") && !input.keys.contains("personId"))
}

@Test func advancingOntoAHoldingCurtainCallCanGoAnyway() async throws {
    let stub = Stub { request in
        let input = ((try? request.jsonBody()["variables"] as? [String: Any])?["input"] as? [String: Any]) ?? [:]
        if input["force"] as? Bool == true {
            return .json(status: 200, body: #"{"data":{"advanceLineup":{"onStage":null,"upNext":null,"runningOrder":[]}}}"#)
        }
        return .json(status: 200, body: #"{"data":{"advanceLineup":null},"errors":[{"message":"Not everyone is ready.","#
                     + #""extensions":{"code":"INVALID","verdict":"NO_GO"}}]}"#)
    }
    let venues = client(stub)
    do {
        _ = try await venues.advanceLineup(venueID: "venue")
        Issue.record("Advancing should have held")
    } catch {
        #expect(isNotEveryoneReady(error))
    }
    #expect(!isNotEveryoneReady(AudienceKitError.notFound))
    _ = try await venues.advanceLineupAnyway(venueID: "venue")
    let (_, _, input) = try body(stub)
    #expect(input["force"] as? Bool == true && input["venueId"] as? String == "venue")
}

@Test func supportStaffAndTriviaUseTheirMutations() async throws {
    let staff = #"{"id":"s-2","name":"Bo","label":"Sound","role":"SOUND","title":null,"required":false,"callAt":null,"mine":false,"person":null}"#
    let answered = roundJSON.replacingOccurrences(of: #""answer":null"#, with: #""answer":"Legend""#)
    let stub = Stub { request in
        let query = (try? request.jsonBody()["query"] as? String) ?? ""
        if query.contains("createStaffAssignment") { return .json(status: 200, body: #"{"data":{"createStaffAssignment":{"staffAssignment":\#(staff)}}}"#) }
        if query.contains("deleteStaffAssignment") { return .json(status: 200, body: #"{"data":{"deleteStaffAssignment":{"clientMutationId":null}}}"#) }
        if query.contains("openTriviaRound") { return .json(status: 200, body: #"{"data":{"openTriviaRound":{"round":\#(roundJSON)}}}"#) }
        return .json(status: 200, body: #"{"data":{"revealTriviaRound":{"round":\#(answered)}}}"#)
    }
    let venues = client(stub)
    let added = try await venues.addSupportStaff(venueID: "venue", night: "2026-10-22", name: "Bo", role: .sound, required: false)
    #expect(added.label == "Sound" && !added.required)
    var sent = try body(stub)
    let fields = try #require(sent.variables["staff"] as? [String: Any])
    #expect(fields["role"] as? String == "SOUND" && fields["name"] as? String == "Bo" && fields["night"] as? String == "2026-10-22")
    #expect(fields["required"] as? Bool == false && !fields.keys.contains("title"))

    try await venues.removeSupportStaff(id: "s-2")
    #expect(try body(stub).variables["id"] as? String == "s-2")

    let opened = try await venues.openTriviaRound(venueID: "venue")
    #expect(opened.voting)
    sent = try body(stub)
    #expect(sent.variables["venueId"] as? String == "venue")
    let revealed = try await venues.revealTriviaRound(id: "r-1")
    #expect(revealed.answer == "Legend")
}

@Test func anEntryDraftSendsOnlyWhatChanged() throws {
    let act = ShowLineupEntry(id: "act-1", kind: .act, curtainCallMinutes: 10, scenes: [
        .init(id: "sc-1", title: "Toxic", performer: .init(id: "ada", name: "Ada", avatarUrl: nil), lengthSeconds: 200,
              track: .init(id: "f-1", name: "toxic.mp3")),
    ])
    var draft = ShowEntryDraft(act)
    #expect(draft.fields(from: act).isEmpty)
    #expect(draft.scenesMinutes == 4)

    draft.curtainCallMinutes = nil
    draft.scenes.append(.init(title: "Believe", seconds: 240))
    let fields = draft.fields(from: act)
    #expect(fields["curtainCallMinutes"] == GraphQLValue.null)
    #expect(fields["scenes"] == .array([
        .object(["title": .string("Toxic"), "performerId": .string("ada"), "trackId": .string("f-1")]),
        .object(["title": .string("Believe"), "seconds": .int(240)]),
    ]))
    #expect(Set(fields.keys) == ["curtainCallMinutes", "scenes"])

    var segment = ShowEntryDraft(kind: .segment, durationMinutes: 15, activity: .trivia, revealAtEnd: true)
    #expect(segment.fields(from: nil) == ["kind": .string("SEGMENT"), "durationMinutes": .int(15),
                                         "activity": .string("TRIVIA"), "triviaReveal": .string("END")])
    segment.curtainCallMinutes = 5
    #expect(!segment.fields(from: nil).keys.contains("curtainCallMinutes"))

    let intermission = ShowEntryDraft(kind: .intermission)
    #expect(intermission.flexible)
    #expect(intermission.fields(from: nil) == ["kind": .string("INTERMISSION")])
}

@Test func aDetailedDraftChangesScenesInPlaceAndSendsTheEditorSettings() throws {
    let act = ShowLineupEntry(id: "act-1", kind: .act, scenes: [
        .init(id: "sc-1", title: "Toxic", lengthSeconds: 200, track: .init(id: "f-1", name: "toxic.mp3")),
        .init(id: "sc-2", title: "Believe", seconds: 240),
    ])
    let details = ShowEntryDetails(id: "act-1", notes: "Castle **up**", preshowMinutes: 10, scenes: [
        .init(id: "sc-2", setupSeconds: 120, setupNote: "Bring out the castle"),
    ])
    var draft = ShowEntryDraft(act, details: details)
    #expect(draft.detailed)
    #expect(draft.preshowMinutes == 10 && draft.scenes[1].setupNote == "Bring out the castle")
    #expect(draft.fields(from: act, details: details).isEmpty)

    draft.scenes[1].gapNote = "Tear the castle down"
    draft.scenes.append(.init(title: "Encore"))
    draft.preshowMinutes = nil
    draft.notes = ""
    let fields = draft.fields(from: act, details: details)
    #expect(fields["preshowMinutes"] == GraphQLValue.null)
    #expect(fields["notes"] == GraphQLValue.null)
    guard case .array(let scenes)? = fields["scenes"], case .object(let second) = scenes[1], case .object(let added) = scenes[2] else {
        Issue.record("no scenes"); return
    }
    #expect(second["id"] == .string("sc-2"))
    #expect(second["setupSeconds"] == .int(120) && second["gapNote"] == .string("Tear the castle down"))
    #expect(added["id"] == nil && added["title"] == .string("Encore"))
}

@Test func showControlReadsTheEditorSettingsWhenTheAPIHasThem() async throws {
    let detailsJSON = #"{"data":{"venues":{"venue":{"people":{"runningOrder":{"nodes":["#
        + #"{"id":"act-1","notes":"Castle **up**","preshowMinutes":10,"maxMinutes":null,"scenes":["#
        + #"{"id":"sc-2","setupSeconds":120,"setupNote":"Bring out the castle","gapSeconds":null,"gapNote":null,"note":null}]}]}}}}}}"#
    let stub = Stub { request in
        let query = (try? request.jsonBody())?["query"] as? String ?? ""
        return .json(status: 200, body: query.contains("StaffShowDetails") ? detailsJSON : showJSON)
    }
    let show = try await client(stub).showControl(venueID: "venue")
    #expect(show.hasDetails)
    #expect(show.details?["act-1"]?.preshowMinutes == 10)
    #expect(show.details?["act-1"]?.scene("sc-2")?.setupNote == "Bring out the castle")

    let older = Stub { request in
        let query = (try? request.jsonBody())?["query"] as? String ?? ""
        return query.contains("StaffShowDetails")
            ? .json(status: 200, body: #"{"errors":[{"message":"Field 'notes' doesn't exist on type 'Appearance'"}]}"#)
            : .json(status: 200, body: showJSON)
    }
    let without = try await client(older).showControl(venueID: "venue")
    #expect(!without.hasDetails && without.entries.count == 2)
}
