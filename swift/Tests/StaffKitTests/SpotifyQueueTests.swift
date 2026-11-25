import Foundation
import Testing
import AudienceKit
import StaffKitCore
import StaffKitServices

@Test func theMacAsksTheAPIToMatchSpotifysQueueToTheLineup() async throws {
    let stub = Stub { _ in
        .json(status: 200, body: #"{"data":{"syncSpotifyQueue":{"state":"OK","inSync":true,"changed":true,"deviceName":"Show Mac","playingUri":"spotify:track:1","message":null,"coming":[{"uri":"spotify:track:2","title":"Memory","artist":"Elaine Paige","durationMs":200000}]}}}"#)
    }
    let client = VenueManagementClient(session: AudienceManagementSession(baseURL: stub.baseURL, credentialStore: InMemoryCredentialStore(credential: makeCredential(audienceID: "audience", on: stub.baseURL)), session: stub.session))
    let status = try await client.syncSpotifyQueue(deviceName: "Show Mac", mode: .now)
    #expect(status.ok && status.inSync && status.changed)
    #expect(status.coming == [PlaylistTrack(uri: "spotify:track:2", title: "Memory", artist: "Elaine Paige", durationMs: 200_000)])
    let request = try #require(stub.requests.last)
    let variables = try #require(request.jsonBody()["variables"] as? [String: Any])
    #expect(variables["device"] as? String == "Show Mac" && variables["mode"] as? String == "NOW")
}

@Test func aLineupChangeWaitsForTheEndOfTheSongAndIsFixedOnce() {
    var keeper = SpotifyQueueKeeper()
    let start = Date(timeIntervalSince1970: 0)
    #expect(keeper.checkDue(at: start))
    keeper.checked(SpotifyQueueStatus(state: "OK", inSync: true), at: start)
    #expect(!keeper.checkDue(at: start.addingTimeInterval(5)))
    #expect(keeper.checkDue(at: start.addingTimeInterval(SpotifyQueueKeeper.checkEvery)))
    // In step: Spotify plays its own queue, nothing is asked for at the end.
    let switched1 = keeper.switchNow(track: "a", position: 199.5, duration: 200)
    #expect(!switched1)

    keeper.checked(SpotifyQueueStatus(state: "OK", inSync: false), at: start)
    let switched2 = keeper.switchNow(track: "a", position: 120, duration: 200)
    #expect(!switched2)
    let switched3 = keeper.switchNow(track: "a", position: 198.8, duration: 200)
    #expect(switched3)
    let switched4 = keeper.switchNow(track: "a", position: 199.4, duration: 200)
    #expect(!switched4)

    // A check that couldn't reach Spotify isn't a difference to fix.
    keeper.checked(SpotifyQueueStatus(state: "NO_DEVICE"), at: start)
    let switched5 = keeper.switchNow(track: "b", position: 199, duration: 200)
    #expect(!switched5)
}
