import Foundation
import Testing
import AudienceKit
import StaffKitCore
import StaffKitServices

private func client(_ stub: Stub) -> VenueManagementClient {
    VenueManagementClient(session: AudienceManagementSession(baseURL: stub.baseURL, credentialStore: InMemoryCredentialStore(credential: makeCredential(audienceID: "audience", on: stub.baseURL)), session: stub.session))
}
private func input(_ stub: Stub) throws -> [String: Any] {
    let body = try #require(stub.requests.last).jsonBody()
    return (body["variables"] as? [String: Any])?["input"] as? [String: Any] ?? [:]
}

private let mona = #"{"id":"mona","name":"Mona Lott","avatarUrl":null}"#
private let juniper = #"{"id":"juniper","name":"Juniper Blaze","avatarUrl":null}"#
private let coco = #"{"id":"coco","name":"Coco Lumen","avatarUrl":null}"#

/// Act 2 of Friday Follies on Stage: three scenes, a break after the second, scene 2 going straight on.
private let actJSON = #"{"id":"act-2","kind":"ACT","entryKind":"ACT","role":"PERFORMER","title":"Act 2","position":1,"startTiming":"SOFT","#
    + #""endTiming":"ADVANCE","state":"UPCOMING","startsAt":"2026-10-24T06:00:00Z","endsAt":null,"wentOnAt":null,"cameOffAt":null,"#
    + #""person":\#(juniper),"people":{"nodes":[\#(juniper)]},"event":{"id":"follies","name":"Friday Follies","startAt":"2026-10-24T04:00:00Z"},"#
    + #""songRequest":null,"activity":null,"curtainCallMinutes":5,"durationMinutes":null,"estimatedMinutes":40,"missingTracks":0,"#
    + #""projectedStartsAt":null,"projectedEndsAt":null,"lateMinutes":null,"flexible":false,"minMinutes":null,"extraMinutes":10,"#
    + #""triviaSet":null,"triviaDriver":null,"triviaReveal":null,"notes":"Castle **before** scene 2","preshowMinutes":10,"maxMinutes":null,"#
    + #""endsTo":null,"venueWide":false,"lineup":{"id":"follies-stage"},"afterScene":null,"scenes":["#
    + #"{"id":"sc-1","title":"Opener","seconds":210,"gapSeconds":null,"lengthSeconds":210,"performer":\#(juniper),"track":null,"#
    + #""performers":[\#(juniper)],"endsTo":null,"wentOnAt":null,"cameOffAt":null,"setupSeconds":null,"setupNote":null,"gapNote":null,"note":null},"#
    + #"{"id":"sc-2","title":"Rain on Me","seconds":null,"gapSeconds":90,"lengthSeconds":222,"performer":\#(coco),"track":{"id":"f-1","name":"rain.mp3"},"#
    + #""performers":[\#(coco),\#(mona)],"endsTo":"NEXT","wentOnAt":null,"cameOffAt":null,"setupSeconds":120,"setupNote":"Castle","gapNote":null,"note":null},"#
    + #"{"id":"sc-3","title":"Finale","seconds":312,"gapSeconds":null,"lengthSeconds":312,"performer":null,"track":null,"#
    + #""performers":[],"endsTo":null,"wentOnAt":null,"cameOffAt":null,"setupSeconds":null,"setupNote":null,"gapNote":null,"note":null}]}"#

private let breakJSON = #"{"id":"break-1","kind":"INTERMISSION","entryKind":"INTERMISSION","role":null,"title":"Break","position":2,"#
    + #""startTiming":"NONE","endTiming":"ADVANCE","state":"UPCOMING","startsAt":null,"endsAt":null,"wentOnAt":null,"cameOffAt":null,"#
    + #""person":null,"people":{"nodes":[]},"event":{"id":"follies","name":"Friday Follies","startAt":"2026-10-24T04:00:00Z"},"songRequest":null,"#
    + #""activity":null,"curtainCallMinutes":null,"durationMinutes":10,"estimatedMinutes":null,"missingTracks":0,"projectedStartsAt":null,"#
    + #""projectedEndsAt":null,"lateMinutes":null,"flexible":true,"minMinutes":null,"extraMinutes":null,"triviaSet":null,"triviaDriver":null,"#
    + #""triviaReveal":null,"notes":null,"preshowMinutes":null,"maxMinutes":null,"endsTo":"HOST","venueWide":false,"lineup":{"id":"follies-stage"},"#
    + #""afterScene":{"id":"sc-2"},"scenes":[]}"#

private let step = #"{"id":"step:scene:sc-1","targetId":"sc-1","kind":"SCENE","title":"Opener","performers":[\#(juniper)],"state":"UPCOMING","#
    + #""wentOnAt":null,"cameOffAt":null,"endsTo":null,"act":{"id":"act-2"},"entry":null,"lineup":{"id":"follies-stage"}}"#

private let folliesJSON = #"{"id":"follies-stage","name":"Friday Follies","zoneName":"Stage","zone":null,"night":"2026-10-23","phase":"HOST","#
    + #""opensAt":null,"closesAt":null,"startedAt":"2026-10-24T04:10:00Z","endedAt":null,"sceneEndsTo":null,"title":null,"#
    + #""event":{"id":"follies","name":"Friday Follies","startAt":"2026-10-24T04:00:00Z","endAt":"2026-10-24T07:00:00Z"},"#
    + #""hosts":[\#(mona)],"current":null,"upNext":\#(step),"entries":[\#(actJSON),\#(breakJSON)]}"#

private let zoneNightJSON = #"{"data":{"venues":{"venue":{"people":{"#
    + #""stageZones":[{"id":"patio","name":"Patio","isDefault":false,"position":1}],"#
    + #""lineups":["#
    + #"{"id":"stage-night","name":"Stage","zoneName":"Stage","zone":null,"night":"2026-10-23","phase":"EVENT","opensAt":"2026-10-24T02:00:00Z","#
    + #""closesAt":"2026-10-24T09:00:00Z","startedAt":null,"endedAt":null,"sceneEndsTo":null,"title":null,"event":null,"hosts":[],"#
    + #""current":null,"upNext":null,"entries":[],"children":[\#(folliesJSON)]},"#
    + #"{"id":"patio-night","name":"Patio","zoneName":"Patio","zone":{"id":"patio"},"night":"2026-10-23","phase":"HOST","opensAt":null,"#
    + #""closesAt":null,"startedAt":null,"endedAt":null,"sceneEndsTo":null,"title":null,"event":null,"hosts":[],"current":null,"upNext":null,"#
    + #""entries":[],"children":[]}],"#
    + #""supportStaff":[{"id":"s-1","name":"Sam Ortiz","label":"Sound","role":"SOUND","title":null,"required":true,"callAt":null,"mine":false,"#
    + #""person":null,"lineup":{"id":"follies-stage"}},{"id":"s-2","name":"Dee Park","label":"Door","role":"DOOR","title":null,"required":false,"#
    + #""callAt":null,"mine":false,"person":null,"lineup":null},{"id":"s-3","name":"Ola","label":"Bar","role":"BAR","title":null,"required":false,"#
    + #""callAt":null,"mine":false,"person":null,"lineup":{"id":"patio-night"}}]}}}}}"#

@Test func zoneNightReadsZonesLineupsActsScenesAndBreaks() async throws {
    let stub = Stub { _ in .json(status: 200, body: zoneNightJSON) }
    let night = try await client(stub).zoneNight(venueID: "venue", night: "2026-10-23")

    #expect(night.zones.map(\.name) == ["Patio"])
    #expect(night.lineups.map(\.zoneName) == ["Stage", "Patio"])
    let stage = try #require(night.lineup(zoneID: nil))
    #expect(stage.isZoneNight && stage.phase == .event && night.lineup(zoneID: "patio")?.id == "patio-night")

    let follies = try #require(stage.children.first)
    #expect(stage.live.id == "follies-stage" && follies.phase == .host && follies.hosts.map(\.name) == ["Mona Lott"])
    #expect(follies.upNext?.displayName == "Juniper Blaze" && follies.upNext?.actID == "act-2")
    #expect(night.events.map(\.name) == ["Friday Follies"])

    let act = try #require(follies.acts.first)
    #expect(act.appearance.displayName == "Act 2" && act.show.curtainCallMinutes == 5 && act.details.preshowMinutes == 10)
    #expect(act.show.scenes.map(\.people.count) == [1, 2, 0])
    #expect(act.show.scenes[1].endsTo == .next && act.details.scene("sc-2")?.setupSeconds == 120)
    #expect(follies.topLevel.map(\.id) == ["act-2"])
    #expect(follies.breaks(in: act)["sc-2"]?.map(\.id) == ["break-1"])
    #expect(follies.entries.last?.endsTo == .host && follies.entries.last?.afterSceneID == "sc-2")

    #expect(night.supportStaff(in: stage).map(\.name) == ["Sam Ortiz", "Dee Park"])
    #expect(night.supportStaff(in: try #require(night.lineup(zoneID: "patio"))).map(\.name) == ["Dee Park", "Ola"])

    let query = try #require(stub.requests.first).jsonBody()["query"] as? String ?? ""
    #expect(query.contains("stageZones") && query.contains("lineups(night: $night)") && query.contains("children {"))
}

@Test func cueingAZoneSendsTheCueAndReadsTheStage() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{"cueLineup":{"stage":\#(folliesJSON)}}}"#) }
    let stage = try await client(stub).cueLineup(id: "stage-night", cue: .advance, force: true)
    #expect(stage.id == "follies-stage" && stage.phase == .host)
    let sent = try input(stub)
    #expect(sent["lineupId"] as? String == "stage-night" && sent["cue"] as? String == "ADVANCE" && sent["force"] as? Bool == true)
}

@Test func puttingAHostOnSendsThePersonAndLineupOrVenue() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{"putHostOn":{"lineup":\#(folliesJSON)}}}"#) }
    let lineup = try await client(stub).putHostOn(personID: "dalton", lineupID: "follies-stage", venueID: "bar", replace: true)
    #expect(lineup.id == "follies-stage")
    let sent = try input(stub)
    #expect(sent["personId"] as? String == "dalton" && sent["lineupId"] as? String == "follies-stage" && sent["replace"] as? Bool == true)
    #expect(sent["venueId"] as? String == "bar")

    let byVenue = Stub { _ in .json(status: 200, body: #"{"data":{"putHostOn":{"lineup":\#(folliesJSON)}}}"#) }
    _ = try await client(byVenue).putHostOn(personID: "dalton", venueID: "bar", eventID: "follies")
    let venueSent = try input(byVenue)
    #expect(venueSent["venueId"] as? String == "bar" && venueSent["eventId"] as? String == "follies" && venueSent["lineupId"] == nil)
}

@Test func lineupAndZoneMutationsSendTheirInputs() async throws {
    let stub = Stub { request in
        let query = (try? request.jsonBody()["query"] as? String) ?? ""
        if query.contains("createLineup") { return .json(status: 200, body: #"{"data":{"createLineup":{"lineup":{"id":"follies-patio"}}}}"#) }
        if query.contains("createStageZone") {
            return .json(status: 200, body: #"{"data":{"createStageZone":{"zone":{"id":"up","name":"Upstairs","isDefault":false,"position":2}}}}"#)
        }
        return .json(status: 200, body: #"{"data":{"ok":null}}"#)
    }
    let venues = client(stub)
    #expect(try await venues.createEventLineup(eventID: "follies", zoneID: "patio") == "follies-patio")
    #expect(try input(stub)["zoneId"] as? String == "patio")
    try await venues.updateLineup(id: "follies-stage", fields: ["hostIds": .array([.string("mona")]), "sceneEndsTo": .string("NEXT")])
    let lineup = try input(stub)["lineup"] as? [String: Any]
    #expect(lineup?["hostIds"] as? [String] == ["mona"] && lineup?["sceneEndsTo"] as? String == "NEXT")
    #expect(try await venues.createStageZone(venueID: "venue", name: "Upstairs").name == "Upstairs")
    #expect((try input(stub)["zone"] as? [String: Any])?["name"] as? String == "Upstairs")
    try await venues.deleteLineup(id: "follies-patio")
    #expect(try input(stub)["id"] as? String == "follies-patio")
}

@Test func aZonedDraftSendsScenePerformersAndWhereScenesEnd() throws {
    let data = Data(#"{"data":\#(actJSON)}"#.utf8)
    struct Wrapper: Decodable { let data: ZoneLineupEntry }
    let act = try JSONDecoder().decode(Wrapper.self, from: data).data
    var draft = ShowEntryDraft(act.show, details: act.details, zoned: true)
    #expect(draft.fields(from: act.show, details: act.details).isEmpty)

    draft.scenes[2].performers = [VenueEvent.Person(id: "mona", name: "Mona Lott")]
    draft.scenes[0].endsTo = .next
    draft.endsTo = .host
    let fields = draft.fields(from: act.show, details: act.details)
    guard case .array(let scenes)? = fields["scenes"], case .object(let first) = scenes[0], case .object(let third) = scenes[2] else {
        Issue.record("scenes weren't sent"); return
    }
    #expect(first["id"] == .string("sc-1") && first["endsTo"] == .string("NEXT"))
    #expect(third["performerIds"] == .array([.string("mona")]) && third["performerId"] == .string("mona"))
    #expect(fields["endsTo"] == .string("HOST"))

    // The running order's editor (not zoned) sends neither.
    var plain = ShowEntryDraft(act.show, details: act.details)
    plain.scenes[0].title = "Opener!"
    guard case .array(let plainScenes)? = plain.fields(from: act.show, details: act.details)["scenes"], case .object(let scene) = plainScenes[0] else {
        Issue.record("scenes weren't sent"); return
    }
    #expect(scene["performerIds"] == nil && scene["endsTo"] == nil)
}

@Test func eventZoneLineupsReadsItsLineupsAndTheVenuesOtherZones() async throws {
    let body = #"{"data":{"events":{"event":{"people":{"lineups":[\#(folliesJSON)],"supportStaff":[]},"#
        + #""venue":{"venue":{"people":{"stageZones":[{"id":"main","name":"Main Room","isDefault":true,"position":0},"#
        + #"{"id":"patio","name":"Patio","isDefault":false,"position":1}]}}}}}}}"#
    let stub = Stub { _ in .json(status: 200, body: body) }
    let event = try await client(stub).eventZoneLineups(eventID: "follies")

    #expect(event.lineups.map(\.id) == ["follies-stage"] && event.lineup(zoneID: nil)?.hosts.map(\.name) == ["Mona Lott"])
    #expect(event.defaultZoneName == "Main Room")
    // It's in the default zone already, so only Patio is left to put it in.
    #expect(event.otherZones == [EventZoneLineups.ZoneChoice(id: "patio", name: "Patio")])
    let query = try #require(stub.requests.last).jsonBody()["query"] as? String
    #expect(query?.contains("stageZones") == true)
}

// The automatic act (Rick, 2026-10-31): an event's lineup as one list of who's on.

private func follies() async throws -> ZoneLineup {
    let stub = Stub { _ in .json(status: 200, body: zoneNightJSON) }
    let night = try await client(stub).zoneNight(venueID: "venue", night: "2026-10-23")
    return try #require(night.lineup(zoneID: nil)?.children.first)
}

@Test func anEventsListNumbersScenesDownTheLineupWithBreaksAfterTheirScene() async throws {
    let lineup = try await follies()
    #expect(!lineup.namesActs)
    #expect(lineup.listRows.map(\.id) == ["scene-act-2-sc-1", "scene-act-2-sc-2", "entry-break-1", "scene-act-2-sc-3"])
    #expect(lineup.listRows.map(\.performers.count) == [1, 2, 0, 1])
    #expect(lineup.automaticAct?.id == "act-2" && lineup.lastScene?.id == "sc-3")
}

@Test func addingSomeoneJoinsTheLastActAsItsNextSceneAndItsBilling() async throws {
    let act = try #require(try await follies().automaticAct)
    let rex = VenueEvent.Person(id: "rex", name: "Rex")
    let fields = LineupList.appending([rex], to: act)
    #expect(fields["scenes"] == .array([
        .object(["id": .string("sc-1")]), .object(["id": .string("sc-2")]), .object(["id": .string("sc-3")]),
        .object(["performerIds": .array([.string("rex")]), "performerId": .string("rex")]),
    ]))
    #expect(fields["personIds"] == .array(["juniper", "coco", "mona", "rex"].map(GraphQLValue.string)))
}

@Test func theFirstOneOnMakesTheActAndAnIntermissionFollowsAScene() async throws {
    let lineup = try await follies()
    let rex = VenueEvent.Person(id: "rex", name: "Rex")
    let act = LineupList.firstAct([rex], on: lineup)
    #expect(act["kind"] == .string("ACT") && act["lineupId"] == .string("follies-stage") && act["eventId"] == .string("follies"))
    #expect(act["startTiming"] == .string("NONE") && act["endTiming"] == .string("ADVANCE") && act["night"] == .string("2026-10-23"))
    let pause = LineupList.intermission(on: lineup, after: "sc-1")
    #expect(pause["kind"] == .string("INTERMISSION") && pause["afterSceneId"] == .string("sc-1") && pause["durationMinutes"] == .int(15))
    #expect(LineupList.intermission(on: lineup, after: nil)["afterSceneId"] == nil)
}

@Test func removingAndMovingScenesKeepTheOthers() async throws {
    let act = try #require(try await follies().automaticAct)
    let removed = try #require(LineupList.removing("sc-2", from: act))
    #expect(removed["scenes"] == .array([.object(["id": .string("sc-1")]), .object(["id": .string("sc-3")])]))
    #expect(removed["personIds"] == .array([.string("juniper")]))
    let moved = LineupList.moving(IndexSet(integer: 2), to: 0, in: act)
    #expect(moved["scenes"] == .array(["sc-3", "sc-1", "sc-2"].map { .object(["id": .string($0)]) }))
    let down = LineupList.moving(IndexSet(integer: 0), to: 2, in: act)
    #expect(down["scenes"] == .array(["sc-2", "sc-1", "sc-3"].map { .object(["id": .string($0)]) }))
}

// MARK: The advanced act editor (docs/ADVANCED_ACT_EDITOR.md)

@Test func anActsFlowRunsHostScenesBreaksAndBackToTheHost() async throws {
    let lineup = try await follies()
    let act = try #require(lineup.automaticAct)
    // Scene 2 runs straight on, but the break after it goes back to the host; scene 1 and 3 go to the host.
    #expect(lineup.flow(of: act).map(\.id) == [
        "host-opens-", "scene-sc-1-1", "host-between-sc-1", "scene-sc-2-2", "pause-break-1", "host-between-sc-2", "scene-sc-3-3", "host-closes-sc-3",
    ])
    #expect(lineup.seams(of: act).map(\.index) == [0, 1, 2, 3])
    #expect(lineup.seams(of: act).map(\.afterScene) == [nil, "sc-1", "sc-2", "sc-3"])
    #expect(lineup.endsTo(of: act.show.scenes[1], in: act) == .next)
    #expect(lineup.number(of: act.show.scenes[2], in: act) == 3)
    #expect(lineup.following(act) == nil)
}

@Test func anActWithNoSceneRowsFlowsAsOneSceneOfItsPeople() throws {
    let data = Data(#"{"data":\#(actJSON)}"#.utf8)
    struct Wrapper: Decodable { let data: ZoneLineupEntry }
    var act = try JSONDecoder().decode(Wrapper.self, from: data).data
    act = ZoneLineupEntry(appearance: act.appearance, show: ShowLineupEntry(id: act.id, kind: .act), details: act.details, lineupID: act.lineupID)
    let lineup = ZoneLineup(id: "l", name: "Stage", night: "2026-10-23", entries: [act])
    #expect(lineup.flow(of: act).map(\.id) == ["host-opens-", "scene-act-1", "host-closes-"])
    #expect(lineup.seams(of: act).count == 1)
}

@Test func insertingASceneAtASeamKeepsTheOthersAndBillsInOrder() async throws {
    let act = try #require(try await follies().automaticAct)
    let rex = VenueEvent.Person(id: "rex", name: "Rex")
    let fields = LineupList.inserting([rex], at: 1, in: act)
    #expect(fields["scenes"] == .array([
        .object(["id": .string("sc-1")]), .object(["performerIds": .array([.string("rex")]), "performerId": .string("rex")]),
        .object(["id": .string("sc-2")]), .object(["id": .string("sc-3")]),
    ]))
    #expect(fields["personIds"] == .array(["juniper", "rex", "coco", "mona"].map(GraphQLValue.string)))
    var draft = ShowEntryDraft(act.show, details: act.details, zoned: true)
    draft.scenes[2].performers = [rex]
    #expect(LineupList.billing(of: draft.scenes, in: act) == .array(["juniper", "coco", "mona", "rex"].map(GraphQLValue.string)))
    draft.extraMinutes = 12
    #expect(draft.fields(from: act.show, details: act.details)["extraMinutes"] == .int(12))
}
