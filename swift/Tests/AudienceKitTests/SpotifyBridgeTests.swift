@testable import AudienceCore
import Foundation
import Testing
@testable import AudienceKit

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private let bridgeAudienceID = "00000000-0000-4000-8000-000000000001"

/// A signed-in client whose requests `stub` answers.
private func bridgeClient(_ stub: Stub) -> AudienceKitClient {
    let endpoint = URL(string: GraphQLEndpoint.consumer.path(audienceID: bridgeAudienceID), relativeTo: stub.baseURL)!
        .absoluteURL
    let store = InMemoryCredentialStore(credential: Credential(token: "session-token", userId: "u-1",
                                                               audienceId: bridgeAudienceID, role: "member",
                                                               endpoint: endpoint))
    let configuration = AudienceKitConfiguration(baseURL: stub.baseURL, host: "hotmess.admin.audiencekit.com",
                                                 audienceID: bridgeAudienceID, facebookAppID: "100000000000001",
                                                 environment: .production)
    return AudienceKitClient(configuration: configuration, credentialStore: store, session: stub.session)
}

private let undefined = #"{"errors":[{"message":"Field doesn't exist","extensions":{"code":"undefinedField"}}]}"#

@Suite struct SpotifyBridgeTests {
    @Test func findsTheSpotifyLinkInSharedText() {
        #expect(SpotifyLink.firstLink(in: "Listen on Spotify: https://open.spotify.com/track/0GjEhVFGZW8afUYGChu3Rr?si=a")
            == "https://open.spotify.com/track/0GjEhVFGZW8afUYGChu3Rr?si=a")
        #expect(SpotifyLink.firstLink(in: "https://spotify.link/AbCd") == "https://spotify.link/AbCd")
        #expect(SpotifyLink.firstLink(in: "spotify:album:4aawyAB9vmqN3uQ7FjRGTy") == "spotify:album:4aawyAB9vmqN3uQ7FjRGTy")
        #expect(SpotifyLink.firstLink(in: "https://example.com/track/1") == nil)
    }

    @Test func readsALink() async throws {
        let stub = Stub { _ in
            .json(status: 200, body: #"{"data":{"spotifyLink":{"kind":"track","id":"0GjEhVFGZW8afUYGChu3Rr","#
                + #""title":"Dancing Queen","artist":"ABBA","thumbnailUrl":"https://i.scdn.co/image/a","#
                + #""uri":"spotify:track:0GjEhVFGZW8afUYGChu3Rr","url":"https://open.spotify.com/track/0GjEhVFGZW8afUYGChu3Rr","#
                + #""embedUrl":"https://open.spotify.com/embed/track/0GjEhVFGZW8afUYGChu3Rr"}}}"#)
        }
        let link = try #require(try await bridgeClient(stub).spotifyLink(url: "https://spotify.link/AbCd"))
        #expect(link.isSong && link.title == "Dancing Queen" && link.artist == "ABBA")
        #expect(link.embedUrl.absoluteString == "https://open.spotify.com/embed/track/0GjEhVFGZW8afUYGChu3Rr")
        #expect(try #require(stub.requests.first).jsonBody()["variables"] as? [String: String]
            == ["url": "https://spotify.link/AbCd"])
    }

    @Test func readsNothingFromAnOlderAPI() async throws {
        let stub = Stub { _ in .json(status: 200, body: undefined) }
        let client = bridgeClient(stub)
        #expect(try await client.spotifyLink(url: "https://open.spotify.com/track/x") == nil)
        #expect(try await client.setList(eventID: "e-1") == nil)
    }

    @Test func asksForASharedSong() async throws {
        let request = #"{"id":"q-1","kind":"SONG","title":"Dancing Queen","artist":"ABBA","singer":null,"#
            + #""requesterName":"Ada L.","note":null,"mine":true,"state":"QUEUED","summary":"Dancing Queen by ABBA","#
            + #""position":0,"createdAt":"2026-11-21T21:04:05.123Z","calledAt":null,"finishedAt":null}"#
        let stub = Stub { _ in .json(status: 200, body: #"{"data":{"requestSong":{"request":\#(request)}}}"#) }
        let asked = try await bridgeClient(stub).requestSong(venueID: "v-1",
                                                              spotifyURL: "https://open.spotify.com/track/abc",
                                                              note: "For Bo")
        #expect(asked.summary == "Dancing Queen by ABBA")
        let body = try #require(stub.requests.first).jsonBody()
        #expect(body["operationName"] as? String == "RequestSongFromSpotify")
        #expect(body["variables"] as? [String: String]
            == ["venueId": "v-1", "spotifyUrl": "https://open.spotify.com/track/abc", "note": "For Bo"])
    }

    @Test func readsASetList() async throws {
        let stub = Stub { _ in
            .json(status: 200, body: #"{"data":{"events":{"event":{"id":"e-1","setList":{"#
                + #""spotifyUri":"spotify:playlist:pl1","spotifyUrl":"https://open.spotify.com/playlist/pl1","#
                + #""songCount":12,"syncedAt":"2026-11-21T21:00:00Z"}}}}}"#)
        }
        let list = try #require(try await bridgeClient(stub).setList(eventID: "e-1"))
        #expect(list.spotifyUri == "spotify:playlist:pl1" && list.songCount == 12 && list.syncedAt != nil)
    }
}
