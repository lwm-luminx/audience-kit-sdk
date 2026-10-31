@testable import AudienceCore
import Foundation
import Testing
@testable import AudienceKit

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private let lineupAudienceID = "00000000-0000-4000-8000-000000000001"

/// A signed-in client whose requests `stub` answers.
private func lineupClient(_ stub: Stub) -> AudienceKitClient {
    let endpoint = URL(string: GraphQLEndpoint.consumer.path(audienceID: lineupAudienceID), relativeTo: stub.baseURL)!
        .absoluteURL
    let store = InMemoryCredentialStore(credential: Credential(token: "session-token", userId: "u-1",
                                                               audienceId: lineupAudienceID, role: "member",
                                                               endpoint: endpoint))
    let configuration = AudienceKitConfiguration(baseURL: stub.baseURL, host: "hotmess.admin.audiencekit.com",
                                                 audienceID: lineupAudienceID, facebookAppID: "100000000000001",
                                                 environment: .production)
    return AudienceKitClient(configuration: configuration, credentialStore: store, session: stub.session)
}

private func entry(_ id: String, role: String, state: String, title: String? = nil, song: String? = nil,
                   mine: Bool = false, requestState: String = "QUEUED", kind: String = "ACT") -> String {
    let request = song.map { #"{"id":"r-\#(id)","kind":"KARAOKE","title":"\#($0)","artist":"ABBA","singer":"\#(title ?? "")","# +
        #""requesterName":"Ada L.","note":null,"mine":\#(mine),"state":"\#(requestState)","summary":"x"}"# } ?? "null"
    let roleJSON = kind == "INTERMISSION" ? "null" : "\"\(role)\""
    let titleJSON = title.map { "\"\($0)\"" } ?? "null"
    return #"{"id":"\#(id)","kind":"\#(kind)","role":\#(roleJSON),"title":\#(titleJSON),"state":"\#(state)","# +
        #""startTiming":"NONE","endTiming":"ADVANCE","startsAt":null,"endsAt":null,"people":{"nodes":[]},"# +
        #""songRequest":\#(request)}"#
}

private let lineupJSON = """
{"data":{"venues":{"venue":{"id":"v-1","name":"The SunTrapp",
  "people":{"runningOrder":{"nodes":[
    \(entry("host", role: "HOST", state: "ON", title: "Trixie")),
    \(entry("s1", role: "SINGER", state: "DONE", title: "Marcus", song: "Hallelujah", requestState: "DONE")),
    \(entry("s2", role: "SINGER", state: "ON", title: "Bo & Lee", song: "Islands in the Stream", requestState: "UP")),
    \(entry("break", role: "", state: "UPCOMING", title: "Bar break", kind: "INTERMISSION")),
    \(entry("s3", role: "SINGER", state: "UPCOMING", title: "Jules", song: "Toxic")),
    \(entry("s4", role: "SINGER", state: "UPCOMING", title: "Ada", song: "Dancing Queen", mine: true)),
    \(entry("dj", role: "SOMETHING_NEW", state: "UPCOMING", title: "DJ Kay"))
  ]},"onStage":{"id":"s2"},"upNext":{"id":"break"}},
  "karaoke":{"provider":"audiencekit","providerName":"AudienceKit","joinUrl":null,"sessionCode":null},
  "requests":{"karaoke":{"permitted":true,"open":false,"paused":true,"closedReason":"Signups are paused",
    "host":\(entry("host", role: "HOST", state: "ON", title: "Trixie")),
    "mine":{"nodes":[{"id":"r-s4","kind":"KARAOKE","title":"Dancing Queen","artist":"ABBA","singer":"Ada",
      "requesterName":"Ada L.","note":null,"mine":true,"state":"QUEUED","summary":"Ada to sing Dancing Queen by ABBA"}]}},
    "song":{"permitted":true,"open":true,"paused":false,"closedReason":null,
      "host":\(entry("host", role: "HOST", state: "ON", title: "Trixie")),
      "mine":{"nodes":[\(song("q1", "Toxic", state: "DONE", mine: true)),\(song("q3", "Waterloo", mine: true))]},
      "queue":{"nodes":[\(song("q2", "Dancing Queen", state: "UP")),\(song("q4", "Believe")),
        \(song("q3", "Waterloo", mine: true))]}}}
}}}}
"""

private func song(_ id: String, _ title: String, state: String = "QUEUED", mine: Bool = false) -> String {
    #"{"id":"\#(id)","kind":"SONG","title":"\#(title)","artist":"ABBA","singer":null,"requesterName":"Ada L.","# +
        #""note":null,"mine":\#(mine),"state":"\#(state)","summary":"\#(title) by ABBA","position":0,"# +
        #""createdAt":"2026-10-19T21:04:05Z","calledAt":null,"finishedAt":null}"#
}

@Suite struct LineupTests {
    @Test func readsTheLineupWithItsSingersAndSignups() async throws {
        let stub = Stub { _ in .json(status: 200, body: lineupJSON) }
        let lineup = try #require(try await lineupClient(stub).lineup(venueID: "v-1"))

        #expect(try #require(stub.requests.first).jsonBody()["variables"] as? [String: String] == ["id": "v-1"])
        #expect(lineup.venueName == "The SunTrapp")
        #expect(lineup.acts.map(\.id) == ["host", "break", "dj"])
        #expect(lineup.singers.map(\.displayName) == ["Marcus", "Bo & Lee", "Jules", "Ada"])
        #expect(lineup.entries.last?.role == .unknown)
        #expect(lineup.onStageID == "s2")
        #expect(lineup.karaokeSession?.isAudienceKit == true)
        let window = try #require(lineup.karaoke)
        #expect(window.paused && !window.open && window.closedReason == "Signups are paused")
        #expect(window.host?.displayName == "Trixie")
    }

    @Test func readsTheCutoffAndAsksAnOlderAPIWithoutIt() async throws {
        let cutOff = lineupJSON.replacingOccurrences(
            of: #""paused":true,"closedReason":"Signups are paused""#,
            with: #""paused":false,"closedReason":"Signups are closed for tonight","cutOff":true,"reopened":false,"closesAt":"2026-10-26T08:30:00Z""#)
        let stub = Stub { _ in .json(status: 200, body: cutOff) }
        let window = try #require(try await lineupClient(stub).lineup(venueID: "v-1")?.karaoke)
        #expect(window.cutOff && window.closed && !window.paused && !window.reopened && window.closesAt != nil)
        #expect((try #require(stub.requests.first).jsonBody()["query"] as? String)?.contains("cutOff") == true)

        let older = Stub { request in
            let query = (try? request.jsonBody()["query"] as? String) ?? ""
            if query.contains("cutOff") {
                return .json(status: 200, body: #"{"errors":[{"message":"Field 'cutOff' doesn't exist on type 'SongRequestWindow'"}]}"#)
            }
            return .json(status: 200, body: lineupJSON)
        }
        let window2 = try #require(try await lineupClient(older).lineup(venueID: "v-1")?.karaoke)
        #expect(older.requests.count == 2)
        #expect(window2.paused && window2.closed && !window2.cutOff && window2.closesAt == nil)
    }

    @Test func numbersSingersAndCountsWhoIsBeforeYou() async throws {
        let stub = Stub { _ in .json(status: 200, body: lineupJSON) }
        let lineup = try #require(try await lineupClient(stub).lineup(venueID: "v-1"))
        let mine = try #require(lineup.featuredSignup)

        #expect(mine.id == "r-s4")
        #expect(lineup.entry(for: mine)?.id == "s4")
        #expect(lineup.singerNumber(of: try #require(lineup.entry(for: mine))) == 4)
        #expect(lineup.singersBefore(mine) == 2)
        #expect(lineup.karaokeEntries.map(\.id) == ["s1", "s2", "break", "s3", "s4"])
        #expect(lineup.breakOnNow == nil)
        #expect(lineup.entry(for: mine)?.songRequest?.songLine == "Dancing Queen · ABBA")
    }

    @Test func signsUpToSingAndTakesItBack() async throws {
        let request = #"{"id":"r-1","kind":"KARAOKE","title":"Waterloo","artist":null,"singer":"Ada & Bo","#
            + #""requesterName":"Ada L.","note":null,"mine":true,"state":"QUEUED","summary":"Ada & Bo to sing Waterloo"}"#
        let stub = Stub { request_ in
            let operation = (try? request_.jsonBody()["operationName"] as? String) ?? ""
            let withdrawn = request.replacingOccurrences(of: "QUEUED", with: "WITHDRAWN")
            return .json(status: 200, body: operation == "RequestSong"
                ? #"{"data":{"requestSong":{"request":\#(request)}}}"#
                : #"{"data":{"withdrawSongRequest":{"request":\#(withdrawn)}}}"#)
        }
        let client = lineupClient(stub)

        let signup = try await client.signUpToSing(venueID: "v-1", KaraokeSignup(title: "Waterloo", artist: "",
                                                                                 singer: "Ada & Bo"))
        #expect(signup.state == .queued && signup.singer == "Ada & Bo")
        #expect(try #require(stub.requests.first).jsonBody()["variables"] as? [String: String]
            == ["venueId": "v-1", "kind": "KARAOKE", "title": "Waterloo", "singer": "Ada & Bo"])

        let withdrawn = try await client.withdrawSongRequest(id: "r-1")
        #expect(withdrawn.state == .withdrawn && !withdrawn.state.isOpen)
        #expect(try #require(stub.requests.last).jsonBody()["variables"] as? [String: String] == ["id": "r-1"])
    }

    @Test func readsSongRequestsWithTheQueueAndTheUsersOwn() async throws {
        let stub = Stub { _ in .json(status: 200, body: lineupJSON) }
        let lineup = try #require(try await lineupClient(stub).lineup(venueID: "v-1"))
        let songs = try #require(lineup.songRequests)

        #expect(songs.permitted && songs.open && !songs.paused && songs.closedReason == nil)
        #expect(songs.host?.displayName == "Trixie")
        #expect(songs.playing?.title == "Dancing Queen")
        #expect(songs.queue.map(\.id) == ["q2", "q4", "q3"])
        #expect(lineup.mySongRequests.map(\.id) == ["q3", "q1"])
        let waterloo = try #require(lineup.mySongRequests.first)
        #expect(waterloo.isSong && waterloo.singer == nil && waterloo.createdAt != nil)
        #expect(songs.requestsBefore(waterloo) == 2)
        #expect(songs.requestsBefore(try #require(lineup.mySongRequests.last)) == nil)
        #expect(lineup.karaoke?.queue.isEmpty == true)
        let query = try #require(stub.requests.first).jsonBody()["query"] as? String ?? ""
        #expect(query.contains("song {") && query.contains("queue { nodes"))
    }

    @Test func requestsASongAndTakesItBack() async throws {
        let request = #"{"id":"q-1","kind":"SONG","title":"Dancing Queen","artist":"ABBA","singer":null,"#
            + #""requesterName":"Ada L.","note":"For Bo","mine":true,"state":"QUEUED","summary":"Dancing Queen by ABBA","#
            + #""position":3,"createdAt":"2026-10-19T21:04:05.123Z","calledAt":null,"finishedAt":null}"#
        let stub = Stub { request_ in
            let operation = (try? request_.jsonBody()["operationName"] as? String) ?? ""
            let withdrawn = request.replacingOccurrences(of: "QUEUED", with: "WITHDRAWN")
            return .json(status: 200, body: operation == "RequestSong"
                ? #"{"data":{"requestSong":{"request":\#(request)}}}"#
                : #"{"data":{"withdrawSongRequest":{"request":\#(withdrawn)}}}"#)
        }
        let client = lineupClient(stub)

        let asked = try await client.requestSong(venueID: "v-1", title: "Dancing Queen", artist: "ABBA", note: "For Bo")
        #expect(asked.isSong && asked.state == .queued && asked.position == 3 && asked.note == "For Bo")
        #expect(try #require(stub.requests.first).jsonBody()["variables"] as? [String: String]
            == ["venueId": "v-1", "kind": "SONG", "title": "Dancing Queen", "artist": "ABBA", "note": "For Bo"])

        let withdrawn = try await client.withdrawSongRequest(id: asked.id)
        #expect(withdrawn.state == .withdrawn)
        #expect(try #require(stub.requests.last).jsonBody()["variables"] as? [String: String] == ["id": "q-1"])
    }

    @Test func showsAPartnerSessionOnlyOnKaraokeNights() throws {
        func session(_ tonight: String) throws -> VenueKaraoke {
            let json = #"{"provider":"karafun","providerName":"KaraFun","joinUrl":"https://www.karafun.com/123456/","# +
                #""sessionCode":"123456"\#(tonight)}"#
            return try JSONDecoder.audienceKit.decode(VenueKaraoke.self, from: Data(json.utf8))
        }
        #expect(try session(#","tonight":true"#).isPartnerSessionTonight)
        #expect(try !session(#","tonight":false"#).isPartnerSessionTonight)
        // An API that doesn't say yet keeps showing it.
        #expect(try session("").isPartnerSessionTonight)
        #expect(!VenueKaraoke(provider: "audiencekit", tonight: true).isPartnerSessionTonight)
    }

    @Test func roundTripsALineupEntry() throws {
        let entry = LineupEntry(id: "s1", role: .singer, title: "Ada", people: [.init(id: "p1", name: "Ada")],
                                songRequest: SongRequest(id: "r1", title: "Waterloo", mine: true))
        let data = try JSONEncoder().encode(entry)
        #expect(try JSONDecoder.audienceKit.decode(LineupEntry.self, from: data) == entry)
    }
    @Test func listsAnActsScenesInTurnWithTheBreaksAfterThem() throws {
        let kiki = LineupEntry.Person(id: "p1", name: "Kiki"), aurora = LineupEntry.Person(id: "p2", name: "Aurora")
        let act = LineupEntry(id: "act", role: .performer, title: "First Set", people: [kiki, aurora], state: .on,
                              scenes: [.init(id: "sc1", performers: [kiki], wentOnAt: .now, cameOffAt: .now),
                                       .init(id: "sc2", performers: [aurora], wentOnAt: .now), .init(id: "sc3")])
        let pause = LineupEntry(id: "break", kind: .intermission, title: "Bar break", afterSceneID: "sc1")
        let host = LineupEntry(id: "host", role: .host, people: [kiki])
        let order = [host, act, pause]

        let turns = LineupEntry.inTurn(order)
        #expect(turns.map(\.id) == ["host", "sc1", "break", "sc2", "sc3"])
        #expect(turns.map(\.displayName) == ["Kiki", "Kiki", "Bar break", "Aurora", "Kiki & Aurora"])
        #expect(turns.map(\.state) == [.upcoming, .done, .upcoming, .on, .upcoming])
        #expect(LineupEntry.turnID(of: "act", in: order, state: .on) == "sc2")
        #expect(LineupEntry.turnID(of: "host", in: order, state: .on) == "host")

        let data = try JSONEncoder().encode(act)
        #expect(try JSONDecoder.audienceKit.decode(LineupEntry.self, from: data).scenes.map(\.id) == ["sc1", "sc2", "sc3"])
    }
}
