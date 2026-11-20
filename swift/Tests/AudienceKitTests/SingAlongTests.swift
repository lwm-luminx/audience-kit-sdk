@testable import AudienceCore
import Foundation
import Testing
@testable import AudienceKit

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private let singAlongAudienceID = "00000000-0000-4000-8000-000000000760"

private func singAlongClient(_ stub: Stub) -> AudienceKitClient {
    let endpoint = URL(string: GraphQLEndpoint.consumer.path(audienceID: singAlongAudienceID),
                       relativeTo: stub.baseURL)!.absoluteURL
    let store = InMemoryCredentialStore(credential: Credential(token: "session-token", userId: "u-1",
                                                               audienceId: singAlongAudienceID, role: "member",
                                                               endpoint: endpoint))
    let configuration = AudienceKitConfiguration(baseURL: stub.baseURL, audienceID: singAlongAudienceID)
    return AudienceKitClient(configuration: configuration, credentialStore: store, session: stub.session)
}

private extension RecordedRequest {
    var query: String { ((try? jsonBody())?["query"] as? String) ?? "" }
    var variables: [String: Any] { ((try? jsonBody())?["variables"] as? [String: Any]) ?? [:] }
}

private let singAlongJSON = #"""
{"data":{"events":{"event":{"id":"e-1",
 "karaoke":{"singAlong":true,"providerName":"Sing-along"},
 "playlist":{"provider":"spotify","shuffle":true,"url":"https://open.spotify.com/playlist/24Kl",
  "uri":"spotify:playlist:24Kl","tracks":[
   {"title":"Defying Gravity","artist":"Idina Menzel, Kristin Chenoweth","durationMs":294000,"uri":"spotify:track:1"},
   {"title":"Don't Rain on My Parade","artist":"Barbra Streisand","durationMs":163000,"uri":"spotify:track:2"},
   {"title":"Burn","artist":"Hamilton Cast","durationMs":225000,"uri":"spotify:track:3"},
   {"title":"Café Society","artist":"Somebody","durationMs":null,"uri":"spotify:track:4"}]},
 "venue":{"venue":{"id":"v-1","name":"The SunTrapp","music":{"nowPlaying":{
   "title":"Defying Gravity","artist":"Idina Menzel","album":null,"artworkUrl":"https://i.scdn.co/a.jpg",
   "reportedAt":"2026-11-20T04:00:00Z","expiresAt":"2026-11-20T04:10:00Z",
   "upNext":[{"title":"Burn","artist":"Hamilton Cast"},{"title":"Seasons of Love","artist":null}]}}}}
}}}}
"""#

private let reportTime = ISO8601.date(from: "2026-11-20T04:05:00Z")!

@Test func singAlongReadsTheNightItsPlaylistAndRotation() async throws {
    let stub = Stub { _ in .json(status: 200, body: singAlongJSON) }

    let night = try #require(try await singAlongClient(stub).singAlong(eventID: "e-1", now: reportTime))

    #expect(night.isSingAlong)
    #expect(night.providerName == "Sing-along")
    #expect(night.venueID == "v-1")
    #expect(night.venueName == "The SunTrapp")
    #expect(night.playlist?.tracks?.count == 4)
    #expect(night.playlist?.uri == "spotify:playlist:24Kl")
    let playing = try #require(night.nowPlaying)
    #expect(playing.title == "Defying Gravity")
    #expect(playing.upNext.map(\.title) == ["Burn", "Seasons of Love"])
    #expect(playing.reportedAt == ISO8601.date(from: "2026-11-20T04:00:00Z"))

    let request = try #require(stub.requests.first)
    #expect(request.query.contains("karaoke { singAlong providerName }"))
    #expect(request.query.contains("music { nowPlaying {"))
    #expect(request.variables["id"] as? String == "e-1")
}

@Test func singAlongDropsAStaleReport() async throws {
    let stub = Stub { _ in .json(status: 200, body: singAlongJSON) }
    let later = ISO8601.date(from: "2026-11-20T04:30:00Z")!

    let night = try #require(try await singAlongClient(stub).singAlong(eventID: "e-1", now: later))

    #expect(night.nowPlaying == nil)
    #expect(night.playlist != nil)
}

@Test func nowPlayingRefreshesTheRotation() async throws {
    let body = #"{"data":{"node":{"music":{"nowPlaying":{"title":"Burn","artist":"Hamilton Cast","reportedAt":"2026-11-20T04:04:00Z","expiresAt":"2026-11-20T04:12:00Z","upNext":[]}}}}}"#
    let stub = Stub { _ in .json(status: 200, body: body) }

    let playing = try #require(try await singAlongClient(stub).nowPlaying(venueID: "v-1", now: reportTime))

    #expect(playing.title == "Burn")
    #expect(playing.upNext.isEmpty)
    let request = try #require(stub.requests.first)
    #expect(request.query.contains("... on Venue { music { nowPlaying {"))
    #expect(request.variables["id"] as? String == "v-1")
}

@Test func nowPlayingIsNilWithoutAReport() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{"node":{"music":{"nowPlaying":null}}}}"#) }
    #expect(try await singAlongClient(stub).nowPlaying(venueID: "v-1") == nil)
}

@Test func singAlongLeavesOutWhatTheSchemaHasNot() {
    let shape = SchemaShape(fields: ["Event": ["id"], "Venue": ["id"]])
    let document = Queries.singAlong(shape)
    #expect(!document.contains("karaoke"))
    #expect(!document.contains("playlist"))
    #expect(!document.contains("music"))
    #expect(Queries.nowPlaying(shape).contains("node(id: $id) { id }"))
}

@Test func singAlongTextFoldsCaseAccentsAndPunctuation() {
    #expect(SingAlongText.key("Don’t Rain on My Parade!") == "dont rain on my parade")
    #expect(SingAlongText.key("CAFÉ  Society") == "cafe society")
}

@Test func tracksMatchRequestsByTitleAndLooseArtist() {
    let track = SingAlongTrack(title: "Defying Gravity", artist: "Idina Menzel, Kristin Chenoweth", uri: "t:1")
    #expect(track.matches(title: "defying gravity", artist: "Idina Menzel"))
    #expect(track.matches(title: "Defying Gravity", artist: nil))
    #expect(!track.matches(title: "Defying Gravity", artist: "Cher"))
    #expect(!track.matches(title: "Gravity", artist: "Idina Menzel"))
    #expect(track.matches(search: "idina grav"))
    #expect(!track.matches(search: "streisand"))
    #expect(track.matches(search: "  "))
}

@Test func pickerSortsAndBadgesTracks() throws {
    let tracks = [
        SingAlongTrack(title: "Defying Gravity", artist: "Idina Menzel", uri: "t:1"),
        SingAlongTrack(title: "Don't Rain on My Parade", artist: "Barbra Streisand", uri: "t:2"),
        SingAlongTrack(title: "Burn", artist: "Hamilton Cast", uri: "t:3"),
        SingAlongTrack(title: "Seasons of Love", artist: "Rent Cast", uri: "t:4"),
        SingAlongTrack(title: "Cabaret", artist: "Liza Minnelli", uri: "t:5"),
    ]
    let night = SingAlongNight(
        eventID: "e-1", isSingAlong: true,
        playlist: SingAlongPlaylist(url: "https://open.spotify.com/playlist/1", tracks: tracks),
        nowPlaying: NowPlaying(title: "Defying Gravity", artist: "Idina Menzel", upNext: [UpNextSong(title: "Burn")]))
    let window = SongRequestWindow(
        permitted: true, open: true,
        mine: [SongRequest(id: "r-1", kind: .song, title: "Seasons of Love", artist: "Rent Cast", mine: true)],
        queue: [SongRequest(id: "r-2", kind: .song, title: "Cabaret", state: .queued),
                SongRequest(id: "r-3", kind: .song, title: "Don't Rain on My Parade", state: .done)])

    #expect(night.pickableTracks().map(\.title)
        == ["Burn", "Cabaret", "Defying Gravity", "Don't Rain on My Parade", "Seasons of Love"])
    #expect(night.pickableTracks(matching: "love").map(\.uri) == ["t:4"])
    #expect(night.status(of: tracks[0], requests: window) == .playingNow)
    #expect(night.status(of: tracks[2], requests: window) == .upNext)
    #expect(night.status(of: tracks[3], requests: window) == .requested)
    #expect(night.status(of: tracks[4], requests: window) == .inQueue)
    #expect(night.status(of: tracks[1], requests: window) == nil)
    #expect(night.status(of: tracks[4], requests: nil) == nil)
    #expect(night.playlist?.track(title: "burn", artist: nil)?.uri == "t:3")

    let refreshed = night.with(nowPlaying: nil)
    #expect(refreshed.status(of: tracks[0], requests: nil) == nil)
    #expect(refreshed.playlist == night.playlist)
}

@Test func nowPlayingRoundTripsThroughCodable() throws {
    let playing = NowPlaying(title: "Burn", artist: "Hamilton Cast", reportedAt: reportTime,
                             expiresAt: reportTime.addingTimeInterval(60), upNext: [UpNextSong(title: "Cabaret")])
    let data = try JSONEncoder().encode(playing)
    let decoded = try JSONDecoder().decode(NowPlaying.self, from: data)
    #expect(decoded == playing)
    #expect(decoded.isFresh(at: reportTime))
    #expect(!decoded.isFresh(at: reportTime.addingTimeInterval(120)))
    #expect(NowPlaying(title: "x").isFresh())
}
