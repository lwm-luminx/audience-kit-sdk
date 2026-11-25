import Foundation
import Testing
@testable import StaffKitServices

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Reading a playlist's songs from Spotify's public player page on the venue's Mac, for a playlist AudienceKit's own
// Spotify account can't read.

private let page = """
<html><head></head><body><div id="__next"></div>\
<script id="__NEXT_DATA__" type="application/json">{"props":{"pageProps":{"state":{"data":{"entity":{"type":"playlist",\
"uri":"spotify:playlist:1ZvNoZEQuZIVhnePKIRrKV","trackList":[\
{"uri":"spotify:track:41B9fQdLUzodBGDLfcYl50","title":"MYB (feat. Starlito)","subtitle":"Kevin Gates, Starlito","duration":221006},\
{"uri":"spotify:episode:5Xr0nBPYUnLiI1MBz2yZjG","title":"A podcast","subtitle":"Someone","duration":1000},\
{"uri":"spotify:track:41B9fQdLUzodBGDLfcYl50","title":"MYB (feat. Starlito)","subtitle":"Kevin Gates, Starlito","duration":221006},\
{"uri":"spotify:track:7ouMYWpwJ422jRcDASZB7P","title":"Knights of Cydonia","subtitle":""}]}}}}}}</script></body></html>
"""

@Test func thePlayerPageIsForPlaylistsAndAlbumsOnly() {
    #expect(SpotifyLocalPlaylist.pageURL(for: "https://open.spotify.com/playlist/1ZvNoZEQuZIVhnePKIRrKV?si=x")?.absoluteString
            == "https://open.spotify.com/embed/playlist/1ZvNoZEQuZIVhnePKIRrKV")
    #expect(SpotifyLocalPlaylist.pageURL(for: "spotify:album:1DFixLWuPkv3KT3TnV35m3")?.absoluteString
            == "https://open.spotify.com/embed/album/1DFixLWuPkv3KT3TnV35m3")
    #expect(SpotifyLocalPlaylist.pageURL(for: "spotify:track:41B9fQdLUzodBGDLfcYl50") == nil)
    #expect(SpotifyLocalPlaylist.pageURL(for: "https://example.com/playlist/1ZvNoZEQuZIVhnePKIRrKV") == nil)
}

@Test func itReadsThePagesSongsInOrderEachOnce() throws {
    let songs = try #require(SpotifyLocalPlaylist.tracks(fromPage: page))
    #expect(songs == [
        PlaylistTrack(uri: "spotify:track:41B9fQdLUzodBGDLfcYl50", title: "MYB (feat. Starlito)",
                      artist: "Kevin Gates, Starlito", durationMs: 221006),
        PlaylistTrack(uri: "spotify:track:7ouMYWpwJ422jRcDASZB7P", title: "Knights of Cydonia"),
    ])
    #expect(SpotifyLocalPlaylist.tracks(fromPage: "<html>nothing here</html>") == nil)
}

@Test func itReadsThePageOverTheNetworkAndGivesUpQuietly() async {
    let ok: HTTPTransport = { request in
        #expect(request.url?.absoluteString == "https://open.spotify.com/embed/playlist/1ZvNoZEQuZIVhnePKIRrKV")
        return (Data(page.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
    #expect(await SpotifyLocalPlaylist.tracks(uri: "spotify:playlist:1ZvNoZEQuZIVhnePKIRrKV", transport: ok)?.count == 2)
    let refused: HTTPTransport = { request in
        (Data(), HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: nil, headerFields: nil)!)
    }
    #expect(await SpotifyLocalPlaylist.tracks(uri: "spotify:playlist:1ZvNoZEQuZIVhnePKIRrKV", transport: refused) == nil)
}
