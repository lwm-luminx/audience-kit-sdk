import Foundation
import Testing
@testable import ArbiterModels

/// What copying a message in Arbiter puts on the pasteboard.
@Suite struct GlamCopyTextTests {
    let room = ChatRoom(id: "r1", name: "Purr", kind: "venue")
    let first = Date(timeIntervalSince1970: 1_800_000_000)

    func proposal(_ lines: [ChatLine]) -> GlamProposal {
        GlamProposal(id: "p1", at: first.addingTimeInterval(120), mode: .live, room: room, lines: lines,
                     letters: [:], guardChecks: nil, rules: nil, choice: nil, call: GlamCall(tool: "no_action"),
                     gate: GateResult(allowed: true, needsApproval: false), model: "m", durationMs: 10, cursor: "c9")
    }

    @Test func theMessageIsTheJudgedLinesWordsAlone() {
        let p = proposal([ChatLine(handle: "Sam K.", text: "hi"), ChatLine(handle: "Glam", role: .host, text: "Welcome!")])
        #expect(GlamCopyText.message(p) == "Welcome!")
    }

    @Test func aRichMessageKeepsItsTitle() {
        let p = proposal([ChatLine(handle: "Purr", role: .venue, text: "Two for one", kind: "special", title: "Happy hour")])
        #expect(GlamCopyText.message(p) == "Happy hour · Two for one")
        #expect(GlamCopyText.line(p.lines[0]) == "Purr [venue]: Happy hour · Two for one")
    }

    @Test func theReportHasTheRoomTimesAndConversation() {
        let p = proposal([ChatLine(handle: "Sam K.", text: "hi", sentAt: first),
                          ChatLine(handle: "Glam", role: .host, text: "Welcome!", sentAt: first.addingTimeInterval(60))])
        let report = GlamCopyText.report(p)
        #expect(report.contains("Room: Purr (venue r1)"))
        #expect(report.contains("Message: Glam [host]: Welcome!"))
        #expect(report.contains("Sent: \(ArbiterJSON.formatDate(first.addingTimeInterval(60)))"))
        #expect(report.contains("Feed event: c9"))
        #expect(report.contains("[\(ArbiterJSON.formatDate(first))] Sam K.: hi"))
        #expect(!report.contains("sent before"))
    }

    @Test func aLineSentBeforeTheOneAboveItSaysSo() {
        let text = GlamCopyText.conversation([
            ChatLine(handle: "Sam K.", text: "one", sentAt: first.addingTimeInterval(60)),
            ChatLine(handle: "Glam", role: .host, text: "two", sentAt: first),
            ChatLine(handle: "Sam K.", text: "three", sentAt: first.addingTimeInterval(90)),
        ])
        let lines = text.split(separator: "\n")
        #expect(lines.count == 3)
        #expect(lines[1].hasSuffix("(sent before the line above)"))
        #expect(!lines[2].contains("sent before"))
    }

    @Test func aPendingMessageReportsWhatGlamIsDoing() {
        let pending = GlamStatus.Pending(id: "m1", room: room, at: first, text: "hello", source: .replay,
                                         step: "The guard", started: first)
        #expect(GlamCopyText.message(pending) == "hello")
        let report = GlamCopyText.report(pending)
        #expect(report.contains("Message: hello"))
        #expect(report.contains("(replay)"))
        #expect(report.contains("working on it (The guard)"))
    }
}
