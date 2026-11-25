import Testing
import StaffKitServices

@Test func tagsShowLowercaseWithDashesForSpaces() {
    #expect(tagLabel("Drag Brunch") == "drag-brunch")
    #expect(tagLabel("  Resident   DJ ") == "resident-dj")
    #expect(tagLabel("Leather") == "leather")
}

@Test func pickersOfferTheMostUsedTagsThenTribesThenMatchWhatIsTyped() {
    let tags = (0..<12).map { StaffEventTag(id: "t\($0)", name: "Tag \($0)", eventCount: $0 == 11 ? 20 : $0 % 3) }
        + (0..<6).map { StaffEventTag(id: "r\($0)", name: "Tribe \($0)", tribe: true, tribePublicCount: $0 == 5 ? 50 : 0) }
    let top = staffTagMatches(tags, query: "")
    #expect(top.tags.prefix(4).map(\.id) == ["t11", "t2", "t5", "t8"])
    #expect(top.tags.count == staffTopTagCount)
    #expect(top.tribes.map(\.id) == ["r5", "r0", "r1", "r2"])
    #expect(staffTagMatches(tags, query: "tag-1").tags.map(\.id) == ["t11", "t1", "t10"])
    #expect(staffTagMatches([StaffEventTag(id: "d", name: "Drag Brunch")], query: "drag b").tags.map(\.id) == ["d"])
}

@Test func pickersOrderFacetsThenTagsThenTribes() {
    let ranked = staffRankTags([
        StaffEventTag(id: "tribe", name: "Bears", tribe: true, tribePublicCount: 99),
        StaffEventTag(id: "tag", name: "Drag", eventCount: 1),
        StaffEventTag(id: "facet", name: "Karaoke", facet: "karaoke"),
    ])
    #expect(ranked.map(\.id) == ["facet", "tag", "tribe"])
}
