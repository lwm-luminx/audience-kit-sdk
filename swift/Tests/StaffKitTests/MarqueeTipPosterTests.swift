import Foundation
import Testing
@testable import StaffKitServices

// The screens' tip posters: which of tonight's people get one, in what order, and how their handles print.

private func event(_ id: String, canceled: Bool = false, hosts: String, lineup: String = "") throws -> VenueEvent {
    let json = #"{"id":"\#(id)","isCanceled":\#(canceled),"seriesOverride":false,"people":{"lineup":{"nodes":[\#(lineup)]},"hosts":{"nodes":[\#(hosts)]}}}"#
    return try JSONDecoder().decode(VenueEvent.self, from: Data(json.utf8))
}

private func person(_ id: String, _ name: String, tips: String) -> String {
    #"{"id":"\#(id)","name":"\#(name)","avatarUrl":"https://x/\#(id).jpg","tipping":{"options":[\#(tips)]}}"#
}

private let cash = #"{"name":"Cash App","handle":"$daltonkj","url":"https://cash.app/$daltonkj","isInApp":false}"#
private let venmo = #"{"name":"Venmo","handle":"daltonkj","url":"https://venmo.com/u/daltonkj","isInApp":false}"#
private let inApp = #"{"name":"In the app","handle":null,"url":null,"isInApp":true}"#

@Test func hostsComeFirstOnceEachWithTheirCodes() throws {
    let tonight = [
        try event("e1", hosts: person("dalton", "Dalton", tips: "\(cash),\(venmo),\(inApp)"),
                  lineup: "\(person("anya", "Anya", tips: venmo)),\(person("quiet", "Quiet", tips: inApp))"),
        try event("e2", hosts: person("anya", "Anya", tips: venmo)),
    ]
    let posters = MarqueeTipPoster.tonight(tonight)
    #expect(posters.map(\.name) == ["Dalton", "Anya"])
    #expect(posters[0].photo == "https://x/dalton.jpg")
    #expect(posters[0].links.map(\.provider) == ["Cash App", "Venmo"])
    #expect(posters[0].links.map(\.handle) == ["$daltonkj", "@daltonkj"])
    #expect(posters[0].links.first?.url == "https://cash.app/$daltonkj")
}

@Test func canceledEventsAndNightsWithoutTipLinksHaveNone() throws {
    #expect(MarqueeTipPoster.tonight([try event("e1", canceled: true, hosts: person("d", "Dalton", tips: cash))]).isEmpty)
    #expect(MarqueeTipPoster.tonight([try event("e1", hosts: person("q", "Quiet", tips: inApp))]).isEmpty)
    #expect(MarqueeTipPoster.tonight([]).isEmpty)
}

@Test func atMostSixPeopleAndThreeCodesEach() throws {
    let many = (1...8).map { person("p\($0)", "P\($0)", tips: "\(cash),\(venmo),\(cash.replacingOccurrences(of: "Cash App", with: "PayPal")),\(venmo)") }
    let posters = MarqueeTipPoster.tonight([try event("e1", hosts: many.joined(separator: ","))])
    #expect(posters.count == MarqueeTipPoster.limit)
    #expect(posters.allSatisfy { $0.links.count == MarqueeTipPoster.linksPerPoster })
}

@Test func theKJGetsAPosterBilledWithTheirTitle() throws {
    let json = #"{"id":"e1","isCanceled":false,"seriesOverride":false,"karaoke":{"providerName":"KaraFun","sessionCode":null},"people":{"lineup":{"nodes":[]},"hosts":{"nodes":[\#(person("alma", "Mama Alma", tips: venmo))]},"jockeys":{"nodes":[\#(person("dalton", "Dalton", tips: cash))]},"jockeyLabel":"KJ"}}"#
    let night = try JSONDecoder().decode(VenueEvent.self, from: Data(json.utf8))
    #expect(MarqueeTipPoster.tonight([night]).map(\.name) == ["Mama Alma", "KJ Dalton"])
}

@Test func slidesStandOnTheVenuesInstagramPostsWithoutText() {
    let banner = ScreenBackdrop(url: "https://x/banner.jpg", source: "banner", hasText: false)
    let flyer = ScreenBackdrop(url: "https://x/flyer.jpg", source: "instagram", hasText: true)
    let post = ScreenBackdrop(url: "https://x/post.jpg", source: "instagram", hasText: false)
    let unchecked = ScreenBackdrop(url: "https://x/new.jpg", source: "instagram")
    #expect([banner, flyer, post].slideBackdrop?.url == "https://x/post.jpg")
    #expect([flyer, unchecked].slideBackdrop?.url == "https://x/new.jpg")
    #expect([flyer, banner].slideBackdrop?.url == "https://x/banner.jpg")
    #expect([flyer].slideBackdrop == nil)
}
