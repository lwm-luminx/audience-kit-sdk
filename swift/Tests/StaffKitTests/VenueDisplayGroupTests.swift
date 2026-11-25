import Foundation
import Testing
@testable import StaffKitCore
@testable import StaffKitServices

// Screen groups: a venue's screens that share one setup ("Bar TVs").

@Test func aScreenIsInTheGroupThatListsIt() {
    let bar = StaffVenueDisplayGroup(id: "g1", name: "Bar TVs", displayIds: ["d1", "d2"])
    let patio = StaffVenueDisplayGroup(id: "g2", name: "Patio", displayIds: ["d3"])
    #expect(StaffVenueDisplayGroup.of("d3", in: [bar, patio])?.name == "Patio")
    #expect(StaffVenueDisplayGroup.of("d2", in: [bar, patio])?.id == "g1")
    #expect(StaffVenueDisplayGroup.of("d9", in: [bar, patio]) == nil)
}

@Test func aGroupSaysWhatItsScreensShow() {
    let group = StaffVenueDisplayGroup(id: "g1", name: "Bar TVs", ranking: [
        StaffVenueDisplay.Entry(type: .liveActivity), StaffVenueDisplay.Entry(type: .lineup)
    ])
    #expect(group.showsLine == "Live activity, then Lineup")
    #expect(StaffVenueDisplayGroup(id: "g2", name: "Patio", off: true).showsLine == "Off (logo only)")
}

@Test func aGroupDecodesFromTheStaffAPI() throws {
    let json = """
        {"id":"g1","name":"Bar TVs","off":false,"nowPlaying":true,"displayIds":["d1"],
         "ranking":[{"type":"BOARD","slideshowId":null,"slideId":null,"seconds":null,"photos":true,"chatSize":"LARGE"}],
         "slideshows":[{"id":"s1","name":"Posters","default":true,"slides":[]}]}
        """
    let group = try JSONDecoder().decode(StaffVenueDisplayGroup.self, from: Data(json.utf8))
    #expect(group.displayIds == ["d1"])
    #expect(group.ranking.first?.chatSize == .large)
    #expect(group.slideshows.first?.isDefault == true)
}
