import Foundation
import Testing
@testable import StaffKitServices

// The follow-us slide in the screens' poster loop: which of a venue's social links show, and how.

private func link(_ provider: String, _ handle: String, _ url: String?) throws -> VenueWorkspace.SocialLink {
    let json: [String: Any] = ["provider": provider, "handle": handle, "url": url ?? NSNull()]
    return try JSONDecoder().decode(VenueWorkspace.SocialLink.self, from: JSONSerialization.data(withJSONObject: json))
}

@Test func theSlideKeepsSocialNetworksWithHttpsLinksInOrderAtMostFour() throws {
    let profiles = MarqueeSocial.profiles([
        try link("tiktok", "kremwerk", "https://tiktok.com/@kremwerk"),
        try link("venmo", "tips", "https://venmo.com/u/tips"),
        try link("instagram", "@kremwerk_sea", "https://instagram.com/kremwerk_sea"),
        try link("instagram", "second", "https://instagram.com/second"),
        try link("facebook", "kremwerk", "http://facebook.com/kremwerk"),
        try link("twitter", "krem", "https://x.com/krem"),
        try link("bluesky", "krem.bsky.social", "https://bsky.app/profile/krem.bsky.social"),
        try link("youtube", "kremtv", "https://youtube.com/kremtv"),
        try link("threads", "nolink", nil),
    ])
    #expect(profiles.map(\.network) == ["Instagram", "TikTok", "X", "Bluesky"])
    #expect(profiles.map(\.handle) == ["@kremwerk_sea", "@kremwerk", "@krem", "@krem.bsky.social"])
    #expect(profiles.first?.url == "https://instagram.com/kremwerk_sea")
    #expect(MarqueeSocial.profiles([]).isEmpty)
}

@Test func eachHandleIsWordedAsPeopleLookForIt() {
    #expect(MarqueeSocial.displayHandle(provider: "instagram", handle: " @@kiki ") == "@kiki")
    #expect(MarqueeSocial.displayHandle(provider: "facebook", handle: "Kremwerk") == "Kremwerk")
    #expect(MarqueeSocial.displayHandle(provider: "youtube", handle: "kremtv") == "@kremtv")
    #expect(MarqueeSocial.displayHandle(provider: "youtube", handle: "channel/UC1") == "channel/UC1")
    #expect(MarqueeSocial.displayHandle(provider: "linktree", handle: "krem") == "linktr.ee/krem")
    #expect(MarqueeSocial.displayHandle(provider: "discord", handle: "abc") == "discord.gg/abc")
    #expect(MarqueeSocial.displayHandle(provider: "tiktok", handle: "@") == "")
}

@Test func theCastGetsEachProfile() throws {
    let cast = MarqueeSocial.castProfiles(MarqueeSocial.profiles([try link("instagram", "krem", "https://instagram.com/krem")]))
    #expect(cast.count == 1)
    #expect(cast[0]["provider"] as? String == "instagram")
    #expect(cast[0]["handle"] as? String == "@krem")
    #expect(cast[0]["url"] as? String == "https://instagram.com/krem")
}

@Test func theCastBoardCarriesTheProfilesOnlyWhenThereAreSome() throws {
    let place = VenueCastBoard.Venue(id: "11111111-1111-4111-8111-111111111111", name: "Neighbours",
                                     timeZone: TimeZone(identifier: "America/Los_Angeles")!, photo: nil)
    var board = VenueCastBoard(chat: false)
    #expect(board.message(venue: place, events: [])["social"] == nil)
    board.social = MarqueeSocial.profiles([try link("tiktok", "neighbours", "https://tiktok.com/@neighbours")])
    let social = board.message(venue: place, events: [])["social"] as? [[String: Any]]
    #expect(social?.first?["handle"] as? String == "@neighbours")
}
