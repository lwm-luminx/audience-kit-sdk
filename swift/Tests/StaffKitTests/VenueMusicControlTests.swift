import Foundation
import Testing
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
