import Foundation
import Testing
@testable import ArbiterModels

/// How this Mac reviews Glam's fast lane (api doc/GLAM_FAST_LANE.md): nothing heavier than removing a line without a
/// person, and the console's switch reaching the engine.
@Suite struct GlamFastLaneTests {
    private func output(_ kind: GlamOutputEvent.Kind, suggesting action: GlamAction? = nil) -> GlamOutputEvent {
        GlamOutputEvent(cursor: "9", at: Date(), room: ChatRoom(id: "v1", name: "Purr", kind: "venue"), outputID: "o1",
                        kind: kind, suggestedAction: action,
                        target: ChatLine(handle: "subj_1", text: "look at the size of her"))
    }

    @Test func confirmsWhatActsOnNobody() {
        for kind in [GlamOutputEvent.Kind.doNotReply, .reply, .privateNudge, .safetyResponse] {
            let verdict = GlamReviewPolicy.review(output(kind), rulesFlagged: nil)
            #expect(verdict == GlamOutputReview(outputID: "o1", outcome: .confirm))
        }
        #expect(GlamReviewPolicy.review(output(.flag, suggesting: .nothing), rulesFlagged: nil).outcome == .confirm)
    }

    @Test func removesOnlyWhenTheRulesAgree() {
        #expect(GlamReviewPolicy.review(output(.flag, suggesting: .remove), rulesFlagged: true).outcome == .confirm)
        #expect(GlamReviewPolicy.review(output(.flag, suggesting: .remove), rulesFlagged: false).outcome == .overturn)
        #expect(GlamReviewPolicy.review(output(.flag, suggesting: .remove), rulesFlagged: nil).outcome == .escalate)
    }

    @Test func neverCoolsDownOrBlocksWithoutAPerson() {
        let cooldown = GlamReviewPolicy.review(output(.flag, suggesting: .cooldown), rulesFlagged: true)
        #expect(cooldown.outcome == .downgrade)
        #expect(cooldown.action == .remove)
        #expect(GlamReviewPolicy.review(output(.flag, suggesting: .cooldown), rulesFlagged: false).outcome == .overturn)
        for flagged in [true, false, nil] as [Bool?] {
            #expect(GlamReviewPolicy.review(output(.flag, suggesting: .block), rulesFlagged: flagged).outcome == .escalate)
        }
    }

    @Test func ordersActionsLightestFirst() {
        #expect(GlamAction.nothing < .cooldown && GlamAction.cooldown < .remove && GlamAction.remove < .block)
    }

    @Test func takesTheConsolesSwitch() throws {
        let on = try JSONDecoder().decode(ServerEngineSettings.self,
                                          from: Data(#"{"configured":false,"glamFastLane":true}"#.utf8))
        #expect(on.glamFastLane == true)
        #expect(on.managed.isEmpty)
        #expect(EngineSettings().applying(on).reviewsFastLane)
        #expect(!EngineSettings().reviewsFastLane)
        let before = try JSONDecoder().decode(ServerEngineSettings.self, from: Data(#"{"configured":true}"#.utf8))
        #expect(!EngineSettings().applying(before).reviewsFastLane)
    }

    @Test func knowsAnOutputsCursor() {
        #expect(ModerationFeedFrame.glamOutput(output(.reply)).feedCursor == "9")
        #expect(ModerationFeedFrame.gap.feedCursor == nil)
    }
}
