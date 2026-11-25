import Foundation
import Testing
import AudienceKit
import StaffKitCore
import StaffKitServices

private func client(_ stub: Stub) -> VenueManagementClient {
    VenueManagementClient(session: AudienceManagementSession(baseURL: stub.baseURL, credentialStore: InMemoryCredentialStore(credential: makeCredential(audienceID: "audience", on: stub.baseURL)), session: stub.session))
}

private let gameJSON = #"{"id":"g-1","style":"SEVENTY_FIVE","pattern":"Four corners","running":true,"highest":75,"remaining":72,"#
    + #""startedAt":"2026-11-21T03:00:00Z","endedAt":null,"calls":[{"number":12,"letter":"B","label":"B-12"},"#
    + #"{"number":44,"letter":"N","label":"N-44"},{"number":71,"letter":"O","label":"O-71"}],"lastCall":{"number":71,"letter":"O","label":"O-71"}}"#

private let roundJSON = #"{"id":"r-2","statement":"Stonewall began in June ___.","choices":[],"voting":true,"closesAt":null,"#
    + #""answer":null,"roomCall":null,"reveal":null,"revealsAtEnd":false,"revealedAt":null,"format":"FILL_BLANK","#
    + #""roundTitle":"Round 2: Fill in the blank","questionNumber":1,"roundSize":3}"#

// An API from before Venue.liveActivity, so the screens pick between bingo and trivia themselves.
private let noLiveActivity = #"{"errors":[{"message":"Field 'liveActivity' doesn't exist on type 'Venue'"}]}"#

@Test func venueGamesReadsBingoAndTriviaForTheScreens() async throws {
    let stub = Stub { request in
        let query = (try? request.jsonBody()["query"] as? String) ?? ""
        if query.contains("liveActivity") { return .json(status: 200, body: noLiveActivity) }
        if query.contains("bingo") { return .json(status: 200, body: #"{"data":{"venues":{"venue":{"bingo":{"current":\#(gameJSON)}}}}}"#) }
        return .json(status: 200, body: #"{"data":{"venues":{"venue":{"trivia":{"current":\#(roundJSON)}}}}}"#)
    }
    let games = try await client(stub).venueGames(venueID: "venue")

    let game = try #require(games.bingo)
    #expect(game.lastCall?.label == "O-71" && game.called == [12, 44, 71] && game.pattern == "Four corners")
    #expect(game.previous(5).map(\.label) == ["N-44", "B-12"])
    #expect(game.rows.map { $0.label } == ["B", "I", "N", "G", "O"] && game.rows[4].numbers.first == 61)
    #expect(games.showing == .bingo(game))

    let round = try #require(games.trivia)
    #expect(round.isFillBlank && round.progress == "Question 1 of 3" && round.roundTitle == "Round 2: Fill in the blank")
    #expect(MarqueeTriviaRound.letter(0) == "A" && MarqueeTriviaRound.letter(3) == "D")
}

@Test func venueGamesShowsTriviaOverAnEndedGameAndStillReadsOneWithoutTheOther() async throws {
    let stub = Stub { request in
        let query = (try? request.jsonBody()["query"] as? String) ?? ""
        if query.contains("liveActivity") { return .json(status: 200, body: noLiveActivity) }
        if query.contains("bingo") { return .json(status: 200, body: #"{"errors":[{"message":"Field 'bingo' doesn't exist on type 'Venue'"}]}"#) }
        return .json(status: 200, body: #"{"data":{"venues":{"venue":{"trivia":{"current":\#(roundJSON)}}}}}"#)
    }
    let games = try await client(stub).venueGames(venueID: "venue")
    #expect(games.bingo == nil)
    #expect(games.showing == .trivia(try #require(games.trivia)))

    let ended = StaffBingoGame(id: "g-0", style: StaffBingoGame.ninety, running: false, calls: [BingoCall(number: 7)])
    #expect(VenueGames(bingo: ended, trivia: games.trivia).showing == .trivia(try #require(games.trivia)))
    #expect(VenueGames(bingo: ended).showing == .bingo(ended))
    #expect(ended.rows.count == 9 && ended.rows[8].numbers.last == 90 && ended.rows[0].label == nil)
    #expect(ended.calls.first?.label == "7" && ended.remaining == 89)
    #expect(VenueGames().showing == .nothing)
}

@Test func bingoHostMutationsSendTheGame() async throws {
    let stub = Stub { request in
        let query = (try? request.jsonBody()["query"] as? String) ?? ""
        let name = ["startBingoGame", "drawBingoNumber", "undoBingoCall", "endBingoGame"].first { query.contains($0) } ?? ""
        return .json(status: 200, body: #"{"data":{"\#(name)":{"game":\#(gameJSON)}}}"#)
    }
    let venues = client(stub)
    _ = try await venues.startBingoGame(venueID: "venue", style: StaffBingoGame.ninety, pattern: "Blackout")
    var sent = try #require(stub.requests.last).jsonBody()
    let variables = sent["variables"] as? [String: Any] ?? [:]
    #expect(variables["style"] as? String == "NINETY" && variables["pattern"] as? String == "Blackout")

    let drawn = try await venues.drawBingoNumber(gameID: "g-1")
    sent = try #require(stub.requests.last).jsonBody()
    #expect((sent["query"] as? String ?? "").contains("drawBingoNumber") && drawn.lastCall?.number == 71)
    _ = try await venues.undoBingoCall(gameID: "g-1")
    _ = try await venues.endBingoGame(gameID: "g-1")
    #expect(stub.requests.count == 4)
}

private let singAlongJSON = #"{"kind":"SING_ALONG","song":{"title":"Daisy Bell","artist":"Harry Dacre","line":1,"#
    + #""startedAt":"2026-11-21T03:00:00Z","timing":{"syncedLines":[{"time":0,"text":"Daisy, Daisy"},"#
    + #"{"time":4,"text":"Give me your answer, do"},{"time":8,"text":"I'm half crazy"}]}}}"#

private func gamesWith(live: String) async throws -> VenueGames {
    let stub = Stub { request in
        let query = (try? request.jsonBody()["query"] as? String) ?? ""
        if query.contains("liveActivity") { return .json(status: 200, body: #"{"data":{"venues":{"venue":{"liveActivity":\#(live)}}}}"#) }
        if query.contains("bingo") { return .json(status: 200, body: #"{"data":{"venues":{"venue":{"bingo":{"current":\#(gameJSON)}}}}}"#) }
        return .json(status: 200, body: #"{"data":{"venues":{"venue":{"trivia":{"current":\#(roundJSON)}}}}}"#)
    }
    return try await client(stub).venueGames(venueID: "venue")
}

@Test func venueGamesFollowsWhatTheLineupSet() async throws {
    // Trivia set on the lineup beats a running bingo game.
    let trivia = try await gamesWith(live: #"{"kind":"TRIVIA","song":null}"#)
    let round = try #require(trivia.trivia)
    #expect(trivia.followsActivity)
    #expect(trivia.showing == .trivia(round))

    let none = try await gamesWith(live: "null")
    #expect(none.followsActivity)
    #expect(none.showing == .nothing)

    let singing = try await gamesWith(live: singAlongJSON)
    guard case .singAlong(let song) = singing.showing else { Issue.record("expected a sing-along"); return }
    #expect(song.title == "Daisy Bell")
    #expect(song.lyrics?.lines.map(\.text).last == "I'm half crazy")
}

@Test func liveSongHoldsItsLineOrFollowsTheClock() throws {
    let lines = [LiveSong.Line(time: 0, text: "a"), LiveSong.Line(time: 4, text: "b"), LiveSong.Line(time: 8, text: "c")]
    let held = try #require(LiveSong(title: "Daisy Bell", line: 1, lines: lines).clock())
    #expect(!held.playing && held.position > 4 && held.position < 8)
    #expect(held.position(at: Date().addingTimeInterval(600)) == held.position)

    let now = Date()
    let started = Date(timeIntervalSince1970: (now.timeIntervalSince1970 - 30).rounded(.down))
    let running = try #require(LiveSong(title: "x", startedAt: started.ISO8601Format(), lines: lines).clock(at: now))
    #expect(running.playing && abs(running.position - now.timeIntervalSince(started)) < 0.01)
    #expect(LiveSong(title: "x", lines: lines).clock() == nil)
    #expect(LiveSong(title: "x", lines: []).lyrics == nil)
}

@Test func liveSongFollowsThePlayersPositionThroughPausesAndSeeks() throws {
    let lines = [LiveSong.Line(time: 0, text: "a"), LiveSong.Line(time: 60, text: "b")]
    let started = Date().addingTimeInterval(-300).ISO8601Format()
    let at = Date(timeIntervalSince1970: (Date().timeIntervalSince1970 - 10).rounded(.down))
    // Paused 61.5 s in: held there, whatever startedAt says.
    let paused = try #require(LiveSong(title: "x", startedAt: started, lines: lines, position: 61.5,
                                       positionAt: at.ISO8601Format(), playing: false).clock())
    #expect(!paused.playing && paused.position(at: Date()) == 61.5)
    // Playing from a seek to 20 s ten seconds ago: about 30 s in now.
    let playing = try #require(LiveSong(title: "x", startedAt: started, lines: lines, position: 20,
                                        positionAt: at.ISO8601Format(), playing: true).clock())
    #expect(abs(playing.position(at: Date()) - 20 - Date().timeIntervalSince(at)) < 0.5)
}

@Test func venueGamesFromAnAPIWithoutLiveActivityPicksAsBefore() {
    let game = StaffBingoGame(id: "g", calls: [BingoCall(number: 3)])
    #expect(VenueGames(bingo: game).showing == .bingo(game))
    #expect(VenueGames(bingo: game, activity: nil, followsActivity: true).showing == .nothing)
    #expect(VenueGames(bingo: game, activity: VenueLiveActivity(kind: "BINGO"), followsActivity: true).showing == .bingo(game))
}
