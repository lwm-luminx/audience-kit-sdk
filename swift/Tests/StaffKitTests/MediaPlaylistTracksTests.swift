import Foundation
import Testing
import AudienceCore
import StaffKitCore
@testable import StaffKitServices

// YouTube videos as playlist tracks, and gathering the licenses of songs released only there.

private func mediaClient(_ stub: Stub) -> VenueManagementClient {
    VenueManagementClient(session: AudienceManagementSession(baseURL: stub.baseURL, credentialStore: InMemoryCredentialStore(credential: makeCredential(audienceID: "audience", on: stub.baseURL)), session: stub.session))
}

private let video = #"{"id":"m1","kind":"MUSIC_VIDEO","title":"Glitter Riot","artists":"Mx Example","spotifyUrl":null,"youtubeUrl":"https://www.youtube.com/watch?v=aaaaaaaaaaa","youtubeChannel":"Mx Example","youtubeOnly":true,"studio":null,"licenseStatus":"NEEDED","licenseNote":null}"#

@Test func addsYouTubeLinksToAPlaylist() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{"addMediaPlaylistLinks":{"added":1,"items":["# + video + #"]}}}"#) }
    let result = try await mediaClient(stub).addMediaPlaylistLinks(playlistID: "p1", links: ["https://youtu.be/aaaaaaaaaaa"], position: 2, title: "Glitter Riot")
    #expect(result.added == 1)
    let track = try #require(result.items.first)
    #expect(track.youtubeOnly && track.licenseStatus == .needed && track.rightsHolder == "Mx Example")
    #expect(track.licenseStatus?.label == "License needed")
    let body = try #require(stub.requests.first).jsonBody()
    #expect((body["query"] as? String)?.contains("addMediaPlaylistLinks") == true)
    let variables = try #require(body["variables"] as? [String: Any])
    #expect(variables["playlistId"] as? String == "p1" && variables["position"] as? Int == 2)
    #expect(variables["links"] as? [String] == ["https://youtu.be/aaaaaaaaaaa"] && variables["title"] as? String == "Glitter Riot")
}

@Test func readsAPlaylistsTracksAndTheLicensesToGather() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{"media":{"items":["# + video + #",{"id":"m2","kind":"RECORDING","title":"Vogue","licenseStatus":"SOMETHING_NEW"}]}}}"#) }
    let client = mediaClient(stub)
    let tracks = try await client.mediaPlaylistTracks(playlistID: "p1")
    #expect(tracks.map(\.id) == ["m1", "m2"])
    #expect(tracks[1].licenseStatus == nil && !tracks[1].youtubeOnly && tracks[1].rightsHolder == nil)
    #expect((try #require(stub.requests.first).jsonBody()["variables"] as? [String: Any])?["id"] as? String == "p1")

    _ = try await client.mediaLicenses()
    let statuses = (try #require(stub.requests.last).jsonBody()["variables"] as? [String: Any])?["statuses"] as? [String]
    #expect(statuses == ["NEEDED", "REQUESTED"])
}

@Test func recordsWhereALicenseStands() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{"saveMediaItem":{"item":"# + video.replacingOccurrences(of: #""NEEDED""#, with: #""GRANTED""#) + #"}}}"#) }
    let client = mediaClient(stub)
    let saved = try await client.setMediaLicense(itemID: "m1", status: .granted, rightsHolder: "Example Records", note: "Signed")
    #expect(saved.licenseStatus == .granted)
    let item = (try #require(stub.requests.first).jsonBody()["variables"] as? [String: Any])?["item"] as? [String: Any]
    #expect(item?["licenseStatus"] as? String == "GRANTED" && item?["studio"] as? String == "Example Records" && item?["licenseNote"] as? String == "Signed")

    try await client.setMediaLicense(itemID: "m1", status: nil)
    let cleared = (try #require(stub.requests.last).jsonBody()["variables"] as? [String: Any])?["item"] as? [String: Any]
    #expect(cleared?["licenseStatus"] is NSNull && cleared?["studio"] == nil)
    #expect(MediaLicenseStatus.allCases.map(\.label).count == 5)
}
