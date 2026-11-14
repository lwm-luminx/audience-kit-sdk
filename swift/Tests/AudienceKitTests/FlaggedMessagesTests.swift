import AudienceCore
import Foundation
import Testing

private let flaggedNode = """
    {"id":"fa-1","messageId":"m-1","text":"who wants molly","sentAt":"2026-11-14T03:00:00Z","senderId":"u-9",
     "senderName":"Sam R.","senderRunsRoom":false,"reason":"Offering pills","category":"DRUG_SALES",
     "categoryTitle":"Drug sales","ruling":"private_nudge","confidence":0.9,"suggestedAction":"WARN",
     "doneActions":[],"removed":false,"review":null,"reviewedAt":null,"reviewedByName":null,
     "analyzedAt":"2026-11-14T03:00:01Z"}
    """

private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
    try JSONDecoder().decode(type, from: Data(json.utf8))
}

@Test func flaggedMessagesDecodeTheVenuesQueue() throws {
    let response = try decode(FlaggedMessages.ListResponse.self,
                              #"{"venues":{"venue":{"flaggedMessages":{"totalCount":1,"nodes":["# + flaggedNode + "]}}}}")

    let message = try #require(response.messages.first)
    #expect(message.id == "fa-1")
    #expect(message.suggestedAction == .warn)
    #expect(message.isOpen)
    #expect(message.availableActions == [.dismiss, .remove, .warn, .cooldown, .escalate, .ban])
    #expect(message.suggestionLine == "Suggested: Warn")
}

@Test func aVenueWithoutTheFieldHasNoFlaggedMessages() throws {
    #expect(try decode(FlaggedMessages.ListResponse.self, #"{"venues":{"venue":null}}"#).messages.isEmpty)
    #expect(try decode(FlaggedMessages.ListResponse.self, #"{"venues":{"venue":{"flaggedMessages":null}}}"#).messages.isEmpty)
}

@Test func theQueryAndReviewAskForTheSameFields() {
    #expect(FlaggedMessages.query.contains("flaggedMessages(first: 50, includeReviewed: $includeReviewed)"))
    #expect(FlaggedMessages.query.contains(FlaggedMessages.flaggedMessageFields))
    #expect(FlaggedMessages.reviewMutation.contains("reviewFlaggedMessage(input: $input)"))
    #expect(FlaggedMessages.reviewMutation.contains(FlaggedMessages.flaggedMessageFields))
    #expect(FlaggedMessages.queryVariables(venueID: "v-1")
        == ["id": .string("v-1"), "includeReviewed": .bool(false)])
}

@Test func aReviewSendsTheActionAndItsDetails() throws {
    #expect(FlaggedMessages.reviewVariables(id: "fa-1", action: .cooldown, minutes: 5, text: "  ")["input"]
        == .object(["id": .string("fa-1"), "action": .string("COOLDOWN"), "minutes": .int(5)]))
    #expect(FlaggedMessages.reviewVariables(id: "x", action: .warn, text: " Be kind ")["input"]
        == .object(["id": .string("x"), "action": .string("WARN"), "text": .string("Be kind")]))

    let reviewed = flaggedNode.replacingOccurrences(of: #""review":null"#, with: #""review":"COOLDOWN""#)
    let response = try decode(FlaggedMessages.ReviewResponse.self,
                              #"{"reviewFlaggedMessage":{"flaggedMessage":"# + reviewed + "}}")
    #expect(response.message?.review == .cooldown)
    #expect(response.message?.isOpen == false)
    #expect(try decode(FlaggedMessages.ReviewResponse.self, #"{"reviewFlaggedMessage":null}"#).message == nil)
}

@Test func theRoomsOwnPeopleAreOnlyDismissedOrEscalated() {
    let message = FlaggedMessage(id: "fa-2", messageId: "m-2", senderId: "u-2", senderRunsRoom: true,
                                 reason: "Spam", suggestedAction: .remove, doneActions: [.remove], removed: true,
                                 analyzedAt: "2026-11-14T03:00:00Z")

    #expect(message.availableActions == [.dismiss, .escalate])
    #expect(message.suggestionLine == "Suggested: Remove · Already removed")
}

@Test func withoutATranscriptOnlyDismissApplies() {
    let message = FlaggedMessage(id: "fa-3", reason: "Flagged", suggestedAction: .dismiss, analyzedAt: "")

    #expect(message.availableActions == [.dismiss])
}

@Test func theFlaggedMessageCopyMatchesTheActions() {
    #expect(FlaggedMessageAction.quick == [.dismiss, .remove, .warn, .cooldown])
    #expect(FlaggedMessageAction.ban.needsConfirmation)
    #expect(!FlaggedMessageAction.escalate.actsOnSender)
    #expect(FlaggedMessageAction.allCases.allSatisfy { !$0.title.isEmpty && !$0.doneTitle.isEmpty && !$0.systemImage.isEmpty })
    #expect(FlaggedMessageAction.allCases.map(\.id) == ["DISMISS", "REMOVE", "WARN", "COOLDOWN", "ESCALATE", "BAN"])
    #expect(FlaggedMessageCopy.minutes(10) == "10 min")
    #expect(FlaggedMessageCopy.defaultWarning(venueName: "Purr").contains("staff at Purr"))
    #expect(FlaggedMessageCopy.cooldownOptions.contains(FlaggedMessages.cooldownMinutes))
    #expect(FlaggedMessageCopy.cooldownOptions.allSatisfy { $0 <= FlaggedMessages.cooldownMaxMinutes })
}
