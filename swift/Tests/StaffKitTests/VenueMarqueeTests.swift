import Foundation
import Testing
import AudienceKit
import StaffKitCore
import StaffKitServices

@Test func marqueeSettingsReadAndChangeOnlyWhatWasAskedFor() async throws {
    let stub = Stub { request in
        let body = String(data: request.body ?? Data(), encoding: .utf8) ?? ""
        if body.contains("updateVenue") {
            return .json(status: 200, body: #"{"data":{"updateVenue":{"venue":{"marqueeSlogans":true,"adultVenue":true}}}}"#)
        }
        return .json(status: 200, body: #"{"data":{"venues":{"venue":{"marqueeSlogans":true,"adultVenue":false}}}}"#)
    }
    let client = VenueManagementClient(session: AudienceManagementSession(baseURL: stub.baseURL, credentialStore: InMemoryCredentialStore(credential: makeCredential(audienceID: "audience", on: stub.baseURL)), session: stub.session))
    #expect(try await client.marqueeSettings(venueID: "venue") == VenueMarqueeSettings(marqueeSlogans: true, adultVenue: false))
    let changed = try await client.setMarqueeSettings(venueID: "venue", adultVenue: true)
    #expect(changed.adultVenue)
    let sent = try #require(stub.requests.last).jsonBody()
    let input = try #require((sent["variables"] as? [String: Any])?["input"] as? [String: Any])
    let venue = try #require(input["venue"] as? [String: Any])
    #expect(input["id"] as? String == "venue")
    #expect(venue["adultVenue"] as? Bool == true)
    #expect(venue["marqueeSlogans"] == nil)
}

@Test func marqueeSlidesFollowTheVenuesSettings() {
    let slides = [MarqueeSlide(id: "swipe-less", adult: false, image: "/marquee/swipe-less-sticker.jpg"),
                  MarqueeSlide(id: "getting-out", adult: true, image: "/marquee/getting-out-riso.jpg")]
    #expect(MarqueeSlide.showing(slides, for: nil).isEmpty)
    #expect(MarqueeSlide.showing(slides, for: VenueMarqueeSettings(marqueeSlogans: false, adultVenue: true)).isEmpty)
    #expect(MarqueeSlide.showing(slides, for: VenueMarqueeSettings(marqueeSlogans: true, adultVenue: false)).map(\.id) == ["swipe-less"])
    #expect(MarqueeSlide.showing(slides, for: VenueMarqueeSettings(marqueeSlogans: true, adultVenue: true)).count == 2)
    #expect(slides[0].url?.absoluteString == "https://hotmess.social/marquee/swipe-less-sticker.jpg")
}

@Test func aVenueTurnsOffTheStandardPostersItDoesntWant() {
    let slides = [MarqueeSlide(id: "swipe-less", adult: false, image: "/marquee/swipe-less-sticker.jpg"),
                  MarqueeSlide(id: "beautiful-person", adult: false, image: "/marquee/beautiful-person-riso.jpg"),
                  MarqueeSlide(id: "getting-out", adult: true, image: "/marquee/getting-out-riso.jpg")]
    let settings = VenueMarqueeSettings(marqueeSlogans: true, adultVenue: true, hiddenSlogans: ["swipe-less", "gone"])
    #expect(MarqueeSlide.showing(slides, for: settings).map(\.id) == ["beautiful-person", "getting-out"])
    #expect(MarqueeSlide.choices(slides, adultVenue: false).map(\.id) == ["swipe-less", "beautiful-person"])
    #expect(MarqueeSlide.choices(slides, adultVenue: true).count == 3)
}

@Test func thePosterChoicesReadFromANewServerAndAnOldOne() async throws {
    func client(hasChoice: Bool) -> (VenueManagementClient, Stub) {
        let stub = Stub { request in
            let body = String(data: request.body ?? Data(), encoding: .utf8) ?? ""
            if body.contains("marqueeHiddenSlogans") {
                guard hasChoice else { return .json(status: 200, body: #"{"errors":[{"message":"Field 'marqueeHiddenSlogans' doesn't exist on type 'Venue'"}]}"#) }
                if body.contains("updateVenue") {
                    return .json(status: 200, body: #"{"data":{"updateVenue":{"venue":{"marqueeSlogans":true,"adultVenue":false,"marqueeHiddenSlogans":["a","b"]}}}}"#)
                }
                return .json(status: 200, body: #"{"data":{"venues":{"venue":{"marqueeSlogans":true,"adultVenue":false,"marqueeHiddenSlogans":["a"],"marqueePosters":[{"id":"a","image":"https://hotmess.social/m/a.jpg","adult":false},{"id":"b","image":"https://hotmess.social/m/b.jpg","adult":false}]}}}}"#)
            }
            return .json(status: 200, body: #"{"data":{"venues":{"venue":{"marqueeSlogans":true,"adultVenue":false}}}}"#)
        }
        return (VenueManagementClient(session: AudienceManagementSession(baseURL: stub.baseURL, credentialStore: InMemoryCredentialStore(credential: makeCredential(audienceID: "audience", on: stub.baseURL)), session: stub.session)), stub)
    }
    let (new, stub) = client(hasChoice: true)
    let read = try await new.marqueeSettings(venueID: "venue")
    #expect(read.hiddenSlogans == ["a"])
    #expect(read.posters.map(\.id) == ["a", "b"])
    #expect(read.showing.map(\.id) == ["b"])
    #expect((try #require(stub.requests.last).jsonBody()["query"] as? String)?.contains("marqueePosters { id image adult }") == true)
    let changed = try await new.setMarqueeSettings(venueID: "venue", hiddenSlogans: ["a", "b"])
    #expect(changed.hiddenSlogans == ["a", "b"])
    let sent = try #require(stub.requests.last).jsonBody()
    let input = try #require((sent["variables"] as? [String: Any])?["input"] as? [String: Any])
    #expect((input["venue"] as? [String: Any])?["marqueeHiddenSlogans"] as? [String] == ["a", "b"])
    // A server from before posters per audience: no posters, so the TV shows none rather than another audience's.
    let old = try await client(hasChoice: false).0.marqueeSettings(venueID: "venue")
    #expect(old == VenueMarqueeSettings(marqueeSlogans: true, adultVenue: false))
    #expect(old.showing.isEmpty)
}

@Test func theSafetyScreenShowsOnlyOnceTheVenueHasAPoster() async throws {
    func client(poster: String) -> (VenueManagementClient, Stub) {
        let stub = Stub { _ in .json(status: 200, body: #"{"data":{"venues":{"venue":{"safetyPoster":\#(poster)}}}}"#) }
        return (VenueManagementClient(session: AudienceManagementSession(baseURL: stub.baseURL, credentialStore: InMemoryCredentialStore(credential: makeCredential(audienceID: "audience", on: stub.baseURL)), session: stub.session)), stub)
    }
    let (printed, stub) = client(poster: #"{"url":"https://hotmess.social/help/Ab12Cd34Ef"}"#)
    #expect(try await printed.safetyPosterLink(venueID: "venue")?.absoluteString == "https://hotmess.social/help/Ab12Cd34Ef")
    let sent = try #require(stub.requests.last).jsonBody()
    #expect((sent["query"] as? String)?.contains("safetyPoster { url }") == true)
    #expect(try await client(poster: "null").0.safetyPosterLink(venueID: "venue") == nil)
}

@Test func aDeviceReportsTheSongPlayingAndThatItStopped() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{"reportNowPlaying":{"nowPlaying":{"title":"Vogue","artist":"Madonna","album":null,"artworkUrl":"https://i.scdn.co/image/abc","source":"spotify-mac"}}}}"#) }
    let client = VenueManagementClient(session: AudienceManagementSession(baseURL: stub.baseURL, credentialStore: InMemoryCredentialStore(credential: makeCredential(audienceID: "audience", on: stub.baseURL)), session: stub.session))
    let kept = try await client.reportNowPlaying(VenueNowPlaying(title: "Vogue", artist: "Madonna",
                                                                 artworkUrl: "https://i.scdn.co/image/abc", source: "spotify-mac"))
    #expect(kept?.title == "Vogue" && kept?.artworkUrl == "https://i.scdn.co/image/abc")
    let first = try #require(stub.requests.last)
    let variables = try #require(first.jsonBody()["variables"] as? [String: Any])
    #expect(variables["title"] as? String == "Vogue" && variables["stopped"] as? Bool == false && variables["album"] == nil)
    _ = try await client.reportNowPlaying(nil)
    let last = try #require(stub.requests.last)
    let stopped = try #require(last.jsonBody()["variables"] as? [String: Any])
    #expect(stopped["stopped"] as? Bool == true && stopped["title"] == nil)
}
