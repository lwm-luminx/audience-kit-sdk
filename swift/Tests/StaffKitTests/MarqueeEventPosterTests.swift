import Foundation
import Testing
@testable import StaffKitCore
@testable import StaffKitServices

// Upcoming events' full-screen posters in the venue TV's loop (Velvet's marquee and the cast receiver).

private func event(_ id: String, _ name: String, start: String, end: String? = nil, canceled: Bool = false,
                   cents: Int? = nil, scale: (Int, Int)? = nil, banner: String? = nil,
                   people: [String] = []) throws -> VenueEvent {
    var json: [String: Any] = ["id": id, "name": name, "startAt": start, "isCanceled": canceled, "seriesOverride": false]
    if let end { json["endAt"] = end }
    if let banner { json["bannerUrl"] = banner }
    if let cents {
        var cover: [String: Any] = ["cents": cents]
        if let scale { cover["minCents"] = scale.0; cover["maxCents"] = scale.1 }
        json["tickets"] = ["url": NSNull(), "cover": cover]
    }
    if !people.isEmpty {
        json["people"] = ["lineup": ["nodes": people.enumerated().map { ["id": "p\($0.offset)", "name": $0.element] }]]
    }
    return try JSONDecoder().decode(VenueEvent.self, from: JSONSerialization.data(withJSONObject: json))
}

private let zone = TimeZone(identifier: "America/Los_Angeles")!
// Tonight: 6 AM Fri Oct 9 to 6 AM Sat Oct 10, Pacific; it's 8 PM Friday.
private let tonight = DateInterval(start: parseInstant("2026-10-09T13:00:00Z")!, duration: 24 * 3600)
private let now = parseInstant("2026-10-10T03:00:00Z")!

@Test func postersRunFromTonightThroughTwoWeeksSoonestFirst() throws {
    let events = [
        try event("later", "Drag Brunch", start: "2026-10-17T19:00:00Z"),
        try event("over", "Happy Hour", start: "2026-10-09T23:00:00Z", end: "2026-10-10T02:00:00Z"),
        try event("tonight", "Show Tunes", start: "2026-10-10T04:00:00Z", cents: 0, people: ["Anya", "Darcy"]),
        try event("canceled", "Bingo", start: "2026-10-11T03:00:00Z", canceled: true),
        try event("tomorrow", "Karaoke", start: "2026-10-11T04:30:00Z", cents: 1050, banner: "https://cdn.example/k.jpg"),
        try event("far", "New Year's", start: "2026-12-31T05:00:00Z"),
    ]
    let posters = MarqueeEventPoster.upcoming(events, tonight: tonight, zone: zone, at: now)
    #expect(posters.map(\.id) == ["tonight", "tomorrow", "later"])
    #expect(posters[0].when == "Tonight · 9 PM")
    #expect(posters[0].billing == "with Anya · Darcy")
    #expect(posters[0].cover == "Free")
    #expect(posters[0].link == "https://hotmess.social/events/tonight")
    #expect(posters[1].when == "Tomorrow · 9:30 PM")
    #expect(posters[1].cover == "$10.50 cover")
    #expect(posters[1].image == "https://cdn.example/k.jpg")
    #expect(posters[2].when == "Sat, Oct 17 · 12 PM")
    #expect(posters[2].cover == nil)
}

@Test func aSlidingScaleCoverShowsItsRange() throws {
    let sliding = try event("sliding", "Benefit", start: "2026-10-10T04:00:00Z", cents: 1500, scale: (500, 3000))
    #expect(sliding.coverMinCents == 500)
    #expect(MarqueeEventPoster.upcoming([sliding], tonight: tonight, zone: zone, at: now).first?.cover
        == "$5–$30 cover, pay what you can")
}

@Test func atMostSixPostersAndOnlyHTTPSPictures() throws {
    let events = try (1...9).map { try event("e\($0)", "Night \($0)", start: "2026-10-1\($0 - 1)T04:00:00Z") }
    #expect(MarqueeEventPoster.upcoming(events, tonight: tonight, zone: zone, at: now).count == MarqueeEventPoster.limit)
    #expect(MarqueeEventPoster(id: "x", name: "X", when: "", image: "http://cdn.example/x.jpg").image == nil)
}

@Test func theCastBoardSendsThePosters() throws {
    var board = VenueCastBoard(chat: false)
    let place = VenueCastBoard.Venue(id: "11111111-1111-4111-8111-111111111111", name: "Neighbours", timeZone: zone)
    #expect(board.message(venue: place, events: [])["posters"] == nil)
    board.posters = [MarqueeEventPoster(id: "e1", name: "Show Tunes", when: "Tonight · 9 PM", billing: "with Anya",
                                        cover: "Free", image: "https://cdn.example/s.jpg")]
    let sent = try #require(board.message(venue: place, events: [])["posters"] as? [[String: Any]])
    #expect(sent.count == 1)
    #expect(sent[0]["name"] as? String == "Show Tunes")
    #expect(sent[0]["when"] as? String == "Tonight · 9 PM")
    #expect(sent[0]["cover"] as? String == "Free")
    #expect(sent[0]["image"] as? String == "https://cdn.example/s.jpg")
    #expect(sent[0]["link"] as? String == "https://hotmess.social/events/e1")
}

@Test func venueReadsItsBannerPhotosInstagramsIncluded() throws {
    let json: [String: Any] = ["id": "v", "name": "Milk+", "locale": ["id": "l", "name": "Salt Lake"],
                               "bannerUrl": "https://cdn.example/place.jpg",
                               "bannerPhotos": [["url": "https://cdn.example/own.jpg"], ["url": "https://cdn.example/ig1.jpg"]]]
    let venue = try JSONDecoder().decode(VenueWorkspace.self, from: JSONSerialization.data(withJSONObject: json))
    #expect(venue.bannerPhotoUrls == ["https://cdn.example/own.jpg", "https://cdn.example/ig1.jpg"])

    let older = try JSONDecoder().decode(VenueWorkspace.self, from: JSONSerialization.data(withJSONObject: [
        "id": "v", "name": "Milk+", "locale": ["id": "l", "name": "Salt Lake"]] as [String: Any]))
    #expect(older.bannerPhotoUrls.isEmpty)
}
