import Foundation
import Testing
import AudienceCore
import StaffKitCore
@testable import StaffKitServices

// Music control from Velvet and Backstage: tonight's queue, its moves and the venueMusic feed.

private func song(_ n: Int) -> VenueQueueSong { VenueQueueSong(id: "s\(n)", title: "Song \(n)", artist: "Artist") }

@Test func aMovedSongTakesItsNewPlaceAtOnce() {
    let queue = VenueMusicQueue(segmentId: "seg", played: 2, playing: song(0), coming: [song(1), song(2), song(3)])
    #expect(queue.moving("s3", to: 0).coming.map(\.id) == ["s3", "s1", "s2"])
    #expect(queue.moving("s1", to: 99).coming.map(\.id) == ["s2", "s3", "s1"])
    #expect(queue.moving("gone", to: 0) == queue)
}

@Test func theNextSongIsTheQueuesElseThePlayersOwn() {
    let playing = VenueNowPlaying(title: "Vogue", upNext: [UpNextSong(title: "Memory")], playing: false)
    let withQueue = VenueMusicState(nowPlaying: playing, queue: VenueMusicQueue(segmentId: "seg", coming: [song(1)]))
    #expect(withQueue.next?.title == "Song 1")
    #expect(withQueue.paused)
    #expect(withQueue.playerOnline)
    #expect(VenueMusicState(nowPlaying: playing).next?.title == "Memory")
    #expect(!VenueMusicState().playerOnline)
}

@Test func readsTheMusicFeed() throws {
    let skip = Data(#"{"data":{"venueMusic":{"id":"c1","kind":"SKIP","at":"2026-11-22T20:00:00Z","nowPlaying":{"title":"Vogue"},"queue":{"segmentId":"seg","played":1,"playing":null,"coming":[{"id":"s1","title":"Memory","artist":null,"trackUri":"spotify:track:1","lengthSeconds":200}]}}}}"#.utf8)
    guard case .change(let change) = VenueManagementClient.venueMusicEvent(from: skip) else {
        Issue.record("no change")
        return
    }
    #expect(change.kind == .skip)
    #expect(change.kind.command == .skip)
    #expect(change.nowPlaying?.title == "Vogue")
    #expect(change.queue?.coming.first?.trackUri == "spotify:track:1")

    let newer = Data(#"{"data":{"venueMusic":{"id":"c2","kind":"SOMETHING_NEW"}}}"#.utf8)
    guard case .change(let unknown) = VenueManagementClient.venueMusicEvent(from: newer) else {
        Issue.record("no change")
        return
    }
    #expect(unknown.kind == .nowPlaying)
    #expect(unknown.kind.command == nil)
}

@Test func aLicensedServiceShowsOnlyTheButtonsItTakes() {
    let mac = VenueMusicState(nowPlaying: VenueNowPlaying(title: "Vogue", source: "spotify"))
    #expect(mac.service == nil)
    #expect(mac.canGoBack && mac.canPause && !mac.canQueueSongs)

    let soundtrack = VenueMusicState(nowPlaying: VenueNowPlaying(title: "Vogue", source: "soundtrack"))
    #expect(soundtrack.service == .soundtrack)
    #expect(soundtrack.service?.name == "Soundtrack")
    #expect(!soundtrack.canGoBack && soundtrack.canPause && soundtrack.canQueueSongs)

    let rockbot = VenueMusicState(nowPlaying: VenueNowPlaying(title: "Vogue", source: "rockbot"))
    #expect(!rockbot.canGoBack && !rockbot.canPause && !rockbot.canQueueSongs)
}

@Test func readsSoundtrackTracks() throws {
    let json = Data(#"[{"id":"VHJr","title":"Believe","artists":["Cher"],"album":null,"artworkUrl":null},{"id":"x","title":"Untitled","artists":[]}]"#.utf8)
    let tracks = try JSONDecoder().decode([VenueServiceTrack].self, from: json)
    #expect(tracks.map(\.artist) == ["Cher", nil])
}

// MARK: - The venue's song timing and blocking a Soundtrack song

private func musicClient(_ stub: Stub) -> VenueManagementClient {
    VenueManagementClient(session: AudienceManagementSession(baseURL: stub.baseURL, credentialStore: InMemoryCredentialStore(credential: makeCredential(audienceID: "audience", on: stub.baseURL)), session: stub.session))
}

@Test func readsWhereTheVenuesSongIs() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{"venues":{"venue":{"music":{"nowPlaying":{"title":"Vogue","artist":"Madonna","positionMs":61500,"playing":true,"reportedAt":"2026-11-24T20:00:00Z","durationMs":316000,"isrc":"USWB19900001"}}}}}}"#) }
    let timing = try #require(try await musicClient(stub).venueTrackTiming(venueID: "v1"))
    #expect(timing.title == "Vogue" && timing.artist == "Madonna" && timing.isrc == "USWB19900001")
    #expect(timing.durationMs == 316000)
    let clock = try #require(timing.clock(trackID: "t1"))
    #expect(clock.trackID == "t1" && clock.position == 61.5 && clock.playing && clock.duration == 316)
    #expect(clock.readAt == ISO8601DateFormatter().date(from: "2026-11-24T20:00:00Z"))
    let body = try #require(stub.requests.first).jsonBody()
    #expect((body["query"] as? String)?.contains("durationMs isrc") == true)
    #expect((body["variables"] as? [String: Any])?["id"] as? String == "v1")
}

@Test func anOlderAPIGivesThePositionAlone() async throws {
    let stub = Stub { request in
        let query = (try? request.jsonBody())?["query"] as? String ?? ""
        if query.contains("isrc") {
            return .json(status: 200, body: #"{"errors":[{"message":"Field 'isrc' doesn't exist on type 'NowPlaying'"}]}"#)
        }
        return .json(status: 200, body: #"{"data":{"venues":{"venue":{"music":{"nowPlaying":{"title":"Vogue","artist":null,"positionMs":1000,"playing":false,"reportedAt":"2026-11-24T20:00:00Z"}}}}}}"#)
    }
    let timing = try #require(try await musicClient(stub).venueTrackTiming(venueID: "v1"))
    #expect(stub.requests.count == 2)
    #expect(timing.durationMs == nil && timing.isrc == nil)
    #expect(timing.clock()?.playing == false)
}

@Test func nothingPlayingHasNoTiming() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{"venues":{"venue":{"music":{"nowPlaying":null}}}}}"#) }
    #expect(try await musicClient(stub).venueTrackTiming(venueID: "v1") == nil)
    #expect(VenueTrackTiming(title: "Vogue").clock() == nil)
    #expect(VenueTrackTiming(title: "Vogue", positionMs: 5000).clock() == nil)
}

@Test func blockingTheSongAsksSoundtrackToBlockIt() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{"controlVenueMusicService":{"nowPlaying":[{"song":{"title":"Next"}}]}}}"#) }
    try await musicClient(stub).blockVenueServiceSong(venueID: "v1")
    let body = try #require(stub.requests.first).jsonBody()
    let query = body["query"] as? String ?? ""
    #expect(query.contains("controlVenueMusicService") && query.contains(#"action: "block""#) && query.contains(#"provider: "soundtrack""#))
    #expect((body["variables"] as? [String: Any])?["venueId"] as? String == "v1")
}
