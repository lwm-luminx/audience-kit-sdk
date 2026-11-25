import Foundation
import Testing
@testable import StaffKitCore
@testable import StaffKitServices

// Velvet's Tonight switches what a screen shows by putting one screen type first in its ranking.

@Test func leadingWithAnEntryTheScreenHasMovesItUpWithItsOptions() {
    let display = StaffVenueDisplay(id: "d1", name: "Bar TV", ranking: [
        StaffVenueDisplay.Entry(type: .liveActivity),
        StaffVenueDisplay.Entry(type: .board, photos: true),
        StaffVenueDisplay.Entry(type: .chat, chatSize: .large)
    ])
    let ranking = display.ranking(leadingWith: .chat)
    #expect(ranking.map(\.type) == [.chat, .liveActivity, .board])
    #expect(ranking.first?.chatSize == .large)
    #expect(display.leading == .liveActivity)
}

@Test func leadingWithANewTypeAddsItWithDefaults() {
    let display = StaffVenueDisplay(id: "d1", name: "Bar TV")
    #expect(display.ranking(leadingWith: .photoWall).map(\.type) == [.photoWall, .liveActivity, .board])
    let board = StaffVenueDisplay(id: "d2", name: "Patio", ranking: [StaffVenueDisplay.Entry(type: .lineup)])
    #expect(board.ranking(leadingWith: .board).first?.photos == true)
}

@Test func anOffScreenLeadsWithNothing() {
    #expect(StaffVenueDisplay(id: "d1", name: "Bar TV", off: true).leading == nil)
}

@Test func macsAndTVsCanBeGivenKaraFun() {
    #expect(StaffVenueDisplay(id: "d1", name: "Stage", kind: "MAC_SCREEN").screenTypes.contains(.karaoke))
    // TVs play the stream the Mac announces (KaraFunStream).
    #expect(StaffVenueDisplay(id: "d2", name: "Bar TV", kind: "APPLE_TV").screenTypes.contains(.karaoke))
    #expect(StaffVenueDisplay(id: "d4", name: "Lounge TV", kind: "ANDROID_TV").screenTypes.contains(.karaoke))
    #expect(!StaffVenueDisplay(id: "d5", name: "Door iPad", kind: "IPAD").screenTypes.contains(.karaoke))
    #expect(!StaffVenueDisplay(id: "d3", name: "Patio", kind: "CHROMECAST").screenTypes.contains(.karaoke))
}

@Test func aKaraFunEntryDecodesAndSendsNoOptions() throws {
    let entry = try JSONDecoder().decode(StaffVenueDisplay.Entry.self, from: Data(#"{"type":"KARAOKE"}"#.utf8))
    #expect(entry.type == .karaoke)
    #expect(entry.input == .object(["type": .string("KARAOKE")]))
}
