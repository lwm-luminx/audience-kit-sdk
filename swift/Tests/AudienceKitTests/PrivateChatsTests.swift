@testable import AudienceCore
import Foundation
import Testing
@testable import AudienceKit

private let privateLine = #"{"id":"ping-1.a","chatId":"ping-1","body":"Door at 10?","isMine":true,"#
    + #""sentAt":"2026-11-16T05:00:00Z","sender":{"id":"u1","name":"Bo Peep"}}"#

@Test func privateChatEventsDecodeLinesAndClosing() throws {
    let line = Data(#"{"data":{"privateChat":{"chatId":"ping-1","closed":false,"message":\#(privateLine)}}}"#.utf8)
    guard case let .success(.message(message))? = PrivateChatEvent.decode(result: line) else {
        Issue.record("expected a line")
        return
    }
    #expect(message.body == "Door at 10?")
    #expect(message.sender == PrivateChatMessage.Sender(id: "u1", name: "Bo Peep"))

    let closed = Data(#"{"data":{"privateChat":{"chatId":"ping-1","closed":true,"message":null}}}"#.utf8)
    guard case .success(.closed(chatID: "ping-1"))? = PrivateChatEvent.decode(result: closed) else {
        Issue.record("expected the chat to close")
        return
    }
    #expect(PrivateChatEvent.decode(result: Data(#"{"data":{"privateChat":null}}"#.utf8)) == nil)
}

@Test func aPrivateChatLeavesOutLinesThatDontDecode() throws {
    let json = #"{"id":"quickie-1","closesAt":"2026-11-16T06:00:00Z","messages":[\#(privateLine),{"id":"x"}]}"#
    let chat = try JSONDecoder.audienceKit.decode(PrivateChat.self, from: Data(json.utf8))
    #expect(chat.isQuickie)
    #expect(chat.messages.map(\.body) == ["Door at 10?"])
}
