import Foundation
import Testing
import AudienceCore
import ArbiterModels
@testable import StaffKitServices

private func json(_ text: String) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
}

@Suite struct ArbiterServiceTests {
    @Test func readsAMessageWithItsContextLast() throws {
        let item = try json(#"""
        {"chatModeration": {"__typename": "ChatModerationMessageCreated", "cursor": "42", "at": "2026-10-26T23:01:05.120Z",
          "room": {"id": "v1", "kind": "VENUE", "name": "Purr"},
          "message": {"subject": "h2", "role": null, "text": "who wants molly", "sentAt": "2026-10-26T23:01:05Z", "kind": "TEXT"},
          "context": [{"subject": "h1", "role": "VENUE", "text": "Doors at 9", "sentAt": null},
                      {"subject": "h3", "role": null, "text": "  ", "sentAt": null}]}}
        """#)
        let frame = try #require(try CableModerationFeed.frame(item))
        guard case .message(let cursor, _, let room, let lines) = frame else { Issue.record("not a message"); return }
        #expect(cursor == "42")
        #expect(room == ChatRoom(id: "v1", name: "Purr", kind: "venue"))
        #expect(lines.map(\.text) == ["Doors at 9", "who wants molly"])
        #expect(lines.first?.role == .venue)
        #expect(lines.last?.handle == "h2")
    }

    @Test func keepsARichMessagesTitleApartFromItsWords() throws {
        let item = try json(#"""
        {"chatModeration": {"__typename": "ChatModerationMessageCreated", "cursor": "43", "at": null,
          "room": {"id": "v1", "kind": "VENUE", "name": "Purr"},
          "message": {"subject": "h2", "role": null, "kind": "TEXT", "title": null, "body": null, "text": "hi", "sentAt": null},
          "context": [{"subject": "venue", "role": "VENUE", "kind": "ANNOUNCEMENT", "title": "Quickie",
                       "body": "Two people just met", "text": "Announcement: Quickie\nTwo people just met", "sentAt": null},
                      {"subject": "venue", "role": "VENUE", "kind": "EVENT", "title": "Sunset Social", "body": null,
                       "text": "Shared an event: Sunset Social", "sentAt": null}]}}
        """#)
        guard case .message(_, _, _, let lines)? = try CableModerationFeed.frame(item) else { Issue.record("not a message"); return }
        #expect(lines.map(\.text) == ["Two people just met", "", "hi"])
        #expect(lines.map(\.title) == ["Quickie", "Sunset Social", nil])
        #expect(lines.map(\.kind) == ["announcement", "event", "text"])
    }

    @Test func leavesOutTheHostsOwnPostsAndOtherEvents() throws {
        let own = try json(#"""
        {"chatModeration": {"__typename": "ChatModerationMessageCreated", "cursor": "7", "at": null,
          "room": {"id": "v1", "kind": "VENUE", "name": "Purr"},
          "message": {"subject": "venue", "role": "VENUE", "text": "Announcement: Glam (AI host)", "sentAt": null},
          "context": []}}
        """#)
        #expect(try CableModerationFeed.frame(own) == nil)
        let titled = try json(#"""
        {"chatModeration": {"__typename": "ChatModerationMessageCreated", "cursor": "8", "at": null,
          "room": {"id": "v1", "kind": "VENUE", "name": "Purr"},
          "message": {"subject": "venue", "role": "VENUE", "kind": "ANNOUNCEMENT", "title": "Glam (AI host)",
                      "body": "Doors at 9", "text": "Announcement: Glam (AI host)\nDoors at 9", "sentAt": null},
          "context": []}}
        """#)
        #expect(try CableModerationFeed.frame(titled) == nil)
        #expect(try CableModerationFeed.frame(json(#"{"chatModeration": {"__typename": "ChatModerationUserBanned"}}"#)) == nil)
        #expect(try CableModerationFeed.frame(json(#"{"chatModeration": {"__typename": "ChatModerationCaughtUp", "caughtUpCursor": "9"}}"#))
                == .caughtUp(cursor: "9"))
        #expect(try CableModerationFeed.frame(json(#"{"chatModeration": {"__typename": "ChatModerationFeedGap"}}"#)) == .gap)
    }

    @Test func readsAFastLaneOutputForReview() throws {
        let item = try json(#"""
        {"chatModeration": {"__typename": "ChatModerationGlamOutput", "cursor": "51", "at": "2026-11-15T23:01:05Z",
          "room": {"id": "v1", "kind": "VENUE", "name": "Purr"}, "outputId": "o1", "kind": "FLAG",
          "category": "body_shaming", "suggestedAction": "REMOVE", "safetyKind": null, "reason": "Mocks 7CE8's body",
          "text": null, "posted": false, "subject": "subj_2",
          "glamMessage": {"subject": "subj_2", "role": null, "text": "look at her", "sentAt": null},
          "target": {"subject": "subj_2", "role": null, "text": "look at her", "sentAt": null},
          "handles": [{"handle": "7CE8", "subject": "subj_3"}]}}
        """#)
        guard case .glamOutput(let output)? = try CableModerationFeed.frame(item) else { Issue.record("not an output"); return }
        #expect(output.outputID == "o1")
        #expect(output.kind == .flag)
        #expect(output.suggestedAction == .remove)
        #expect(output.target?.text == "look at her")
        #expect(output.handles == [GlamOutputEvent.Handle(handle: "7CE8", subject: "subj_3")])
        #expect(output.room == ChatRoom(id: "v1", name: "Purr", kind: "venue"))
        let unknown = try json(#"{"chatModeration": {"__typename": "ChatModerationGlamOutput", "cursor": "52", "room": {"id": "v1"}, "outputId": "o2", "kind": "SING"}}"#)
        #expect(try CableModerationFeed.frame(unknown) == nil)
    }

    @Test func asksForFastLaneOutputsOnlyWhenOn() {
        #expect(!CableModerationFeed.subscription(glamOutputs: false).contains("ChatModerationGlamOutput"))
        #expect(CableModerationFeed.subscription(glamOutputs: true).contains("... on ChatModerationGlamOutput"))
        #expect(CableModerationFeed.subscription == CableModerationFeed.subscription(glamOutputs: false))
    }

    @Test func sendsAReviewAsTheAPITakesIt() {
        let input = CableHostActions.reviewInput(GlamOutputReview(outputID: "o1", outcome: .downgrade, action: .remove,
                                                                  reason: "Removing the line"))
        #expect(input == ["outputId": .string("o1"), "outcome": .string("DOWNGRADE"), "action": .string("REMOVE"),
                          "reason": .string("Removing the line"), "retract": .bool(false)])
        #expect(CableHostActions.reviewInput(GlamOutputReview(outputID: "o2", outcome: .confirm))
                == ["outputId": .string("o2"), "outcome": .string("CONFIRM"), "retract": .bool(false)])
        #expect(CableHostActions.review.contains("reviewGlamOutput(input: $input)"))
    }

    @Test func sendsHostStepsWithoutEmptyFieldsAndWholeNumbersAsInts() {
        let cleaned = CableHostActions.cleaned(["cursor": .string("42"), "minutes": .number(5), "reason": .string(""),
                                                "confidence": .number(0.82), "category": .null])
        #expect(cleaned == ["cursor": .string("42"), "minutes": .int(5), "confidence": .double(0.82)])
        #expect(CableHostActions.mutation("say")?.contains("say(input: $input)") == true)
        #expect(CableHostActions.mutation("deleteEverything") == nil)
    }

    @Test func decodesClaimedWork() throws {
        let work = try ArbiterDates.decode(DecisionWork.self, from: json(#"""
        {"id": "e1", "evaluationType": "submission_research", "lease": "l1", "leaseExpiresAt": "2026-10-26T23:11:05.5Z",
         "attempt": 2, "question": "Is this right?", "decisionKind": "CHOICE", "input": {"phone": "+1 206 555 0100"},
         "options": [{"key": "approve", "label": "Approve", "description": null}]}
        """#))
        #expect(work.id == "e1")
        #expect(work.attempt == 2)
        #expect(work.options.map(\.key) == ["approve"])
        #expect(work.input["phone"]?.string == "+1 206 555 0100")
    }

    @Test func readsTheAPIsErrors() throws {
        #expect(throws: ArbiterServiceError("No such work")) {
            try ArbiterServiceConnection.data(of: Data(#"{"data": null, "errors": [{"message": "No such work"}]}"#.utf8))
        }
        let data = try ArbiterServiceConnection.data(of: Data(#"{"data": {"ok": true}}"#.utf8))
        #expect(data["ok"] == .bool(true))
    }

    @Test func readsWhatGlamMadeOfAMessageOnAnyProvider() throws {
        let page = try JSONDecoder().decode(MessageAnalysisPage.self, from: Data(#"""
        {"totalCount": 2, "pageInfo": {"hasNextPage": false, "endCursor": "MQ"}, "nodes": [
          {"id": "a1", "chatProvider": "audiencekit", "messageId": "m1", "roomName": "Purr", "text": "who wants molly",
           "sentAt": "2026-10-28T01:00:00Z", "ruling": "private_nudge", "category": "DRUG_SALES", "confidence": 0.88,
           "flagged": true, "executionState": "done", "shapeVersion": 1, "analysis": {"model": "Gemma 4"},
           "configuration": null, "version": 1, "current": true,
           "analyzedAt": "2026-10-28T01:00:02Z", "decision": null,
           "actions": [{"action": "warnUser", "label": "Nudge A", "state": "done", "by": "host"}, {"by": "host"}]},
          {"id": "a2", "chatProvider": "discord", "messageId": "1300", "roomName": null, "text": null, "sentAt": null,
           "ruling": "no_action", "category": null, "confidence": null, "flagged": false, "executionState": null,
           "shapeVersion": 2, "analysis": {}, "analyzedAt": null, "decision": null, "actions": [],
           "configuration": "gemma-27b", "version": 3, "current": true}]}
        """#.utf8))
        #expect(page.nodes.map(\.chatProvider) == ["audiencekit", "discord"])
        #expect(page.nodes[0].actions.map(\.action) == ["warnUser"])
        #expect(page.nodes[0].sentAt != nil)
        #expect(page.nodes[0].analysisText.contains("Gemma 4"))
        #expect(page.nodes[1].text == nil)
        #expect(page.nodes[1].shapeVersion == 2)
        #expect(page.nodes[1].configuration == "gemma-27b")
        #expect(page.nodes[1].version == 3)
        #expect(page.nodes[0].configuration == nil)
    }

    @Test func retriesWithoutADeviceIdOnlyForAnOlderAPIsSchemaError() {
        struct Failure: Error, CustomStringConvertible { let description: String }
        let old = Failure(description: "Variable $input of type WorkerTokenIssueInput! was provided invalid value for "
            + "deviceId (Field is not defined on WorkerTokenIssueInput)")
        #expect(WorkerTokens.unknownDeviceID(old))
        #expect(!WorkerTokens.unknownDeviceID(Failure(description: "deviceId is too long")))
        #expect(!WorkerTokens.unknownDeviceID(Failure(description: "Administrator access required")))
    }
}
