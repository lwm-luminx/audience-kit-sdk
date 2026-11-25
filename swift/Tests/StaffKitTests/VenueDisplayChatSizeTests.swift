import Foundation
import Testing
@testable import StaffKitCore
@testable import StaffKitServices

// A display's chat size (ChatTextSize): set on a board or chat wall from any app, medium when unset or unknown.

@Test func displayEntriesReadTheirChatSizeAndFallBackToMedium() throws {
    let json = Data(#"[{"type":"CHAT","chatSize":"EXTRA_LARGE"},{"type":"BOARD","chatSize":"HUGE"},{"type":"LINEUP"}]"#.utf8)
    let entries = try JSONDecoder().decode([StaffVenueDisplay.Entry].self, from: json)
    #expect(entries.map(\.chatSize) == [.extraLarge, .medium, .medium])
    #expect(StaffVenueDisplay.ChatSize.medium.scale == 1)
    #expect(StaffVenueDisplay.ChatSize.allCases.map(\.scale) == StaffVenueDisplay.ChatSize.allCases.map(\.scale).sorted())
}

@Test func displayEntriesSendTheChatSizeOnlyWhereAChatShows() {
    let chat = StaffVenueDisplay.Entry(type: .chat, chatSize: .large).input
    #expect(chat == .object(["type": .string("CHAT"), "chatSize": .string("LARGE")]))
    let board = StaffVenueDisplay.Entry(type: .board, photos: true, chatSize: .small).input
    #expect(board == .object(["type": .string("BOARD"), "photos": .bool(true), "chatSize": .string("SMALL")]))
    let lineup = StaffVenueDisplay.Entry(type: .lineup, chatSize: .large).input
    #expect(lineup == .object(["type": .string("LINEUP")]))
}
