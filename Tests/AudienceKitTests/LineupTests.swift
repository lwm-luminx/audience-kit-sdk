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
      "requesterName":"Ada L.","note":null,"mine":true,"state":"QUEUED","summary":"Ada to sing Dancing Queen by ABBA"}]}}}
}}}}
"""

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

    @Test func roundTripsALineupEntry() throws {
        let entry = LineupEntry(id: "s1", role: .singer, title: "Ada", people: [.init(id: "p1", name: "Ada")],
                                songRequest: SongRequest(id: "r1", title: "Waterloo", mine: true))
        let data = try JSONEncoder().encode(entry)
        #expect(try JSONDecoder.audienceKit.decode(LineupEntry.self, from: data) == entry)
    }
}
