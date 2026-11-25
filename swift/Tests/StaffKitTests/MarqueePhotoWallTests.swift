import Foundation
import Testing
@testable import StaffKitCore
@testable import StaffKitServices

// The photo wall screen: a venue's trusted photographers' recent photos, and whether it has any (so a screen ranking
// it can fall through to its next type).

private let now = parseInstant("2026-11-21T06:00:00Z")!

private func photo(_ id: String, by photographer: String = "Ana", taken: String? = "2026-11-20T05:00:00Z",
                   url: String? = nil, hidden: Bool = false, caption: String? = nil, event: String? = nil,
                   alt: String? = nil, width: Int? = nil, height: Int? = nil) throws -> VenueEventPhoto {
    let json: [String: Any?] = [
        "id": id, "url": url ?? "https://cdn.example/\(id).jpg", "caption": caption, "altText": alt, "takenAt": taken,
        "width": width, "height": height, "isHidden": hidden, "photographer": ["name": photographer],
        "event": event.map { ["id": "e-\(id)", "name": $0] as [String: Any] },
    ]
    let data = try JSONSerialization.data(withJSONObject: json.mapValues { $0 ?? NSNull() })
    return try JSONDecoder().decode(VenueEventPhoto.self, from: data)
}

@Test func theWallKeepsOnlyVisibleRecentHttpsPhotos() throws {
    let wall = MarqueePhotoWall([
        try photo("a"),
        try photo("hidden", hidden: true),
        try photo("insecure", url: "http://cdn.example/x.jpg"),
        try photo("old", taken: "2026-06-01T05:00:00Z"),
        try photo("undated", taken: nil),
        try photo("dupe", url: "https://cdn.example/a.jpg"),
        try photo("b", taken: "2026-09-01T05:00:00Z"),
    ], now: now)
    #expect(wall.photos.map(\.id) == ["a", "b"])
    #expect(wall.hasContent)
}

@Test func aWallWithNothingRecentHasNoContent() throws {
    let wall = MarqueePhotoWall([try photo("old", taken: "2025-11-01T05:00:00Z"), try photo("x", hidden: true)], now: now)
    #expect(!wall.hasContent)
    #expect(wall.showing(from: 0).isEmpty)
    #expect(wall.castPhotos().isEmpty)
    #expect(!MarqueePhotoWall([], now: now).hasContent)
}

@Test func theWallShowsTheLeadAndTheOnesAfterItRoundAgain() throws {
    let wall = MarqueePhotoWall(try (1...7).map { try photo("p\($0)") }, now: now)
    #expect(wall.showing(from: 0).map(\.id) == ["p1", "p2", "p3", "p4", "p5"])
    #expect(wall.showing(from: 5).map(\.id) == ["p6", "p7", "p1", "p2", "p3"])
    let two = MarqueePhotoWall([try photo("a"), try photo("b")], now: now)
    #expect(two.showing(from: 1).map(\.id) == ["b", "a"])
}

@Test func theCreditNamesEachPhotographerOnce() throws {
    let one = [try photo("a", by: "Ana"), try photo("b", by: "ana")]
    #expect(MarqueePhotoWall.creditLine(one) == "Photos by Ana")
    #expect(MarqueePhotoWall.creditLine([try photo("a", by: "Ana"), try photo("b", by: "Bo")]) == "Photos by Ana and Bo")
    let many = try ["Ana", "Bo", "Cy", "Di"].enumerated().map { try photo("p\($0.offset)", by: $0.element) }
    #expect(MarqueePhotoWall.creditLine(many) == "Photos by Ana, Bo and 2 more")
    #expect(MarqueePhotoWall.creditLine([]) == nil)
}

@Test func thePhotoSaysItsCaptionElseItsEvent() throws {
    #expect(MarqueePhotoWall.words(try photo("a", caption: "  Last call  ", event: "Mess Hall")) == "Last call")
    #expect(MarqueePhotoWall.words(try photo("b", caption: " ", event: "Mess Hall")) == "Mess Hall")
    #expect(MarqueePhotoWall.words(try photo("c")) == nil)
}

@Test func theCastGetsEachPhotoWithItsCredit() throws {
    let wall = MarqueePhotoWall([try photo("a", by: "Ana", caption: "Encore", alt: "A queen bows", width: 1600, height: 1067),
                                 try photo("b", by: "Bo", width: 0, height: 900)], now: now)
    let cast = wall.castPhotos()
    #expect(cast.count == 2)
    #expect(cast[0]["url"] as? String == "https://cdn.example/a.jpg")
    #expect(cast[0]["credit"] as? String == "Ana")
    #expect(cast[0]["caption"] as? String == "Encore")
    #expect(cast[0]["alt"] as? String == "A queen bows")
    #expect(cast[0]["width"] as? Int == 1600)
    #expect(cast[1]["caption"] == nil)
    #expect(cast[1]["width"] == nil)
    #expect(wall.castPhotos(max: 1).count == 1)
}
