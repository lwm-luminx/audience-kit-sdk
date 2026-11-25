import Foundation
import Testing
@testable import StaffKitCore
@testable import StaffKitServices

// Event playlists on the venue's Mac: Spotify links it can play, and the playlist of the event under way.

@Test func spotifyLinksBecomeURIsAndNothingElseDoes() {
    #expect(SpotifyLink.uri("https://open.spotify.com/playlist/37i9dQZF1DX4fpCWaHOned?si=abc123") == "spotify:playlist:37i9dQZF1DX4fpCWaHOned")
    #expect(SpotifyLink.uri(" https://open.spotify.com/intl-de/track/4uLU6hMCjMI75M1A2tKUQC ") == "spotify:track:4uLU6hMCjMI75M1A2tKUQC")
    #expect(SpotifyLink.uri("spotify:album:1DFixLWuPkv3KT3TnV35m3") == "spotify:album:1DFixLWuPkv3KT3TnV35m3")
    #expect(SpotifyLink.uri("https://example.com/playlist/37i9dQZF1DX4fpCWaHOned") == nil)
    #expect(SpotifyLink.uri("spotify:playlist:abc\" & quit") == nil)
    #expect(SpotifyLink.uri("https://open.spotify.com/show/37i9dQZF1DX4fpCWaHOned") == nil)
    #expect(SpotifyLink.uri("") == nil)
}

private func event(_ id: String, _ name: String, start: String, end: String? = nil, canceled: Bool = false) throws -> VenueEvent {
    var json: [String: Any] = ["id": id, "name": name, "startAt": start, "isCanceled": canceled, "seriesOverride": false]
    if let end { json["endAt"] = end }
    return try JSONDecoder().decode(VenueEvent.self, from: JSONSerialization.data(withJSONObject: json))
}

@Test func theEventUnderWayPlaysItsPlaylist() throws {
    let tunes = EventPlaylist(url: "https://open.spotify.com/playlist/37i9dQZF1DX4fpCWaHOned")
    let divas = EventPlaylist(url: "https://example.com/x", uri: "spotify:playlist:1DFixLWuPkv3KT3TnV35m3", shuffle: false)
    let playlists = ["tunes": tunes, "divas": divas, "off": tunes,
                     "elsewhere": EventPlaylist(url: "https://music.apple.com/playlist/x", provider: "other")]
    let events = [
        try event("happy", "Happy Hour", start: "2026-11-25T01:00:00Z", end: "2026-11-25T03:00:00Z"),
        try event("tunes", "Show Tunes", start: "2026-11-25T04:00:00Z"),
        try event("divas", "Diva Night", start: "2026-11-26T04:00:00Z", end: "2026-11-26T08:00:00Z"),
        try event("off", "Canceled", start: "2026-11-27T04:00:00Z", canceled: true),
        try event("elsewhere", "Apple Music", start: "2026-11-28T04:00:00Z"),
    ]
    func running(_ at: String) -> String? { EventPlaylist.running(events, playlists: playlists, at: parseInstant(at)!)?.event.id }
    #expect(running("2026-11-25T02:00:00Z") == nil)
    #expect(running("2026-11-25T05:00:00Z") == "tunes")
    #expect(running("2026-11-25T08:30:00Z") == nil)  // four hours without an end
    #expect(running("2026-11-26T07:00:00Z") == "divas")
    #expect(running("2026-11-27T05:00:00Z") == nil)
    #expect(running("2026-11-28T05:00:00Z") == nil)
    #expect(tunes.playable == "spotify:playlist:37i9dQZF1DX4fpCWaHOned")
    #expect(divas.playable == "spotify:playlist:1DFixLWuPkv3KT3TnV35m3")
}

@Test func playlistsDecodeFromTheAPI() throws {
    let json = #"{"url":"https://open.spotify.com/playlist/37i9dQZF1DX4fpCWaHOned","uri":null,"provider":"spotify","shuffle":true}"#
    let playlist = try JSONDecoder().decode(EventPlaylist.self, from: Data(json.utf8))
    #expect(playlist.shuffle && !playlist.singAlong)
    #expect(playlist.playable == "spotify:playlist:37i9dQZF1DX4fpCWaHOned")
}
