import AudienceCore
import Foundation
import Testing

private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
    try JSONDecoder().decode(type, from: Data(json.utf8))
}

private let queue = """
    {"submissions":{"totalCount":31,"nodes":[
     {"id":"s-1","kind":"SOCIAL_LINK","status":"IN_REVIEW","risk":"normal","createdAt":"2026-11-04T02:10:00Z",
      "decidedAt":null,"proposed":{"provider":"instagram","handle":"murrayhill"},"current":{"handle":"oldhill"},
      "choices":["murrayhill","murrayhillnyc"],
      "choiceProfiles":[{"username":"murrayhill","status":"ready","name":"Murray Hill","pictureUrl":null,
       "biography":"Comedian","followersCount":1200,"postsCount":40,"imageUrls":["https://x/1.jpg"],"error":null}],
      "body":null,"evidence":[],"submitterRole":"system","reporterCount":1,"disputeCount":0,
      "person":{"id":"p-1","name":"Murray Hill"},"venue":null,"event":null,"locale":{"id":"l-1","name":"New York"},
      "research":[],"decisions":[]},
     {"id":"s-2","kind":"CORRECTION","status":"IN_REVIEW","risk":"high","createdAt":"2026-11-04T02:10:00Z",
      "decidedAt":null,"proposed":{"phone":"555-1234","opening_hours":"Daily 4pm","is_open":false},
      "current":{"phone":"555-0000"},"choices":[],"choiceProfiles":[],"body":"Their number changed",
      "evidence":[{"kind":"link","url":"https://wildrose.com/contact"},{"kind":"photo","photoUrl":"https://cdn/p.jpg"}],
      "submitterRole":"attendee","reporterCount":3,"disputeCount":2,"person":null,
      "venue":{"id":"v-1","name":"The Wildrose"},"event":null,"locale":null,
      "research":[{"summary":"The site lists the new number","recommendation":"needs_venue"}],"decisions":[]},
     null]}}
    """

@Test func theQueueDecodesSocialProfilesAndCorrections() throws {
    let response = try decode(ProposedChanges.QueueResponse.self, queue)
    #expect(response.totalCount == 31)
    #expect(response.changes.count == 2)

    let social = response.changes[0]
    #expect(social.isSocialLink && social.isWaiting && !social.canAskVenue)
    #expect(social.title == "Instagram for Murray Hill")
    #expect(social.source == "From an import · New York")
    #expect(social.provider == "instagram" && social.proposedHandle == "murrayhill" && social.currentHandle == "oldhill")
    #expect(social.uncardedChoices == ["murrayhillnyc"])
    #expect(!social.isReadingProfiles)
    #expect(social.profileURL("murrayhill")?.absoluteString == "https://www.instagram.com/murrayhill/")
    #expect(ProposedChangesCopy.socialLine(social) == "Now: @oldhill · Found: @murrayhill, @murrayhillnyc")
    #expect(ProposedChanges.suggestedRejectReason(social) == "Not a match")

    let correction = response.changes[1]
    #expect(correction.title == "Correction: The Wildrose")
    #expect(correction.source == "From 3 people")
    #expect(correction.isHighRisk && correction.canAskVenue)
    #expect(correction.changes == [
        .init(field: "is_open", from: nil, to: "No"),
        .init(field: "opening_hours", from: nil, to: "Daily 4pm"),
        .init(field: "phone", from: "555-0000", to: "555-1234"),
    ])
    #expect(correction.changes[1].title == "Opening hours")
    #expect(correction.evidenceLinks.map(\.absoluteString) == ["https://wildrose.com/contact", "https://cdn/p.jpg"])
    #expect(correction.researchLine == "Research (needs venue): The site lists the new number")
    #expect(correction.decisionLine == nil)
    #expect(ProposedChanges.suggestedRejectReason(correction) == "")
}

@Test func aDecidedChangeSaysWhoDecided() throws {
    let change = try decode(ProposedChange.self, """
        {"id":"s-3","kind":"TRIBE_SUGGESTION","status":"REJECTED","risk":"low","createdAt":"2026-11-04T02:10:00Z",
         "decidedAt":"2026-11-05T02:10:00Z","proposed":{"tribe_name":"Bears"},"current":{},"choices":[],
         "choiceProfiles":[],"body":null,"evidence":null,"submitterRole":"martian","reporterCount":1,"disputeCount":0,
         "person":null,"venue":null,"event":null,"locale":null,"research":[],
         "decisions":[{"action":"REJECT","reason":"Already there","createdAt":"2026-11-05T02:10:00Z",
          "reviewer":{"id":"u-1","name":"Rick M."}}]}
        """)
    #expect(change.title == "Tribe: Bears")
    #expect(change.source == "From someone")
    #expect(!change.isOpen && !change.isWaiting)
    #expect(change.statusTitle == "Rejected")
    #expect(change.decisionLine == "Rejected by Rick M. · Already there")
    #expect(change.evidenceLinks.isEmpty)
}

@Test func decidingSendsTheActionAndWhatToApply() throws {
    let change = try #require(try decode(ProposedChanges.QueueResponse.self, queue).changes.first)
    #expect(ProposedChanges.queueVariables(open: false) == ["open": .bool(false), "first": .int(24)])
    #expect(ProposedChanges.approveVariables(change)
        == ["id": .string("s-1"), "action": .string("APPROVE"), "proposed": .null, "reason": .null])
    #expect(ProposedChanges.approveVariables(change, handle: "@murrayhill")["action"] == .string("APPROVE"))
    #expect(ProposedChanges.approveVariables(change, handle: "https://www.instagram.com/murrayhillnyc/")
        == ["id": .string("s-1"), "action": .string("EDIT_APPROVE"),
            "proposed": .object(["provider": .string("instagram"), "handle": .string("murrayhillnyc")]), "reason": .null])
    #expect(ProposedChanges.rejectVariables(change, reason: "  Not her  ")["reason"] == .string("Not her"))
    #expect(ProposedChanges.askVenueVariables(change)["action"] == .string("NEEDS_VENUE"))
    #expect(ProposedChanges.idVariables("h-1") == ["id": .string("h-1")])
    #expect(ProposedChanges.handle(from: "tiktok.com/@murray") == "murray")
    #expect(ProposedChanges.handle(from: " @@murray ") == "murray")
    #expect(ProposedChangesCopy.handleApproved(change, handle: "@murrayhillnyc") == "@murrayhillnyc is now Murray Hill’s Instagram.")
    #expect(ProposedChanges.decideMutation.contains("decideSubmission(input: { id: $id, action: $action, proposed: $proposed, reason: $reason })"))
}

@Test func headshotsAndDismissalsDecode() throws {
    let headshots = try decode(ProposedChanges.HeadshotsResponse.self, """
        {"headshotsToReview":[{"id":"h-1","url":"https://cdn/h.jpg","origin":"instagram","sourceUrl":null,
         "person":{"id":"p-1","name":"Murray Hill"}},{"id":"h-2","url":"https://cdn/w.jpg","origin":"worker",
         "sourceUrl":"https://example.com","person":{"id":"p-2","name":null}}]}
        """).headshots
    #expect(headshots.map(\.originTitle) == ["From their Instagram", "Found by a worker"])
    #expect(try decode(ProposedChanges.HeadshotsResponse.self, #"{"headshotsToReview":null}"#).headshots.isEmpty)
    #expect(ProposedChangesCopy.headshotApproved(nil) == "Approved for them. Its cut-out is on the way.")

    let response = try decode(ProposedChanges.DismissedDuplicatesResponse.self, """
        {"venues":{"dismissedDuplicates":[
         {"id":"d-1","active":true,"note":"Two floors","dismissedAt":"2026-11-08T08:00:00Z",
          "dismissedBy":{"id":"u-1","name":"Rick M."},"reasons":["SAME_NAME"],"currentReasons":["SAME_NAME"],
          "venues":[{"id":"a","name":"The Edge"},{"id":"b","name":"Edge NYC"}]},
         {"id":"d-2","active":false,"note":null,"dismissedAt":"2026-11-08T08:00:00Z","dismissedBy":null,
          "reasons":["SAME_PLACE"],"currentReasons":[],"venues":[{"id":"c","name":null}]}]}}
        """)
    #expect(response.dismissals.count == 2)
    #expect(response.active.map(\.id) == ["d-1"])
    #expect(response.active[0].title == "The Edge and Edge NYC")
    #expect(response.active[0].detail == "Dismissed by Rick M. · Two floors · Still: Same name in the same locale")
    #expect(response.dismissals[1].detail == "Dismissed by an admin · No longer look alike")
    #expect(try decode(ProposedChanges.DismissedDuplicatesResponse.self, #"{"venues":null}"#).dismissals.isEmpty)
}

@Test func theCopyCountsWhatIsLeft() {
    #expect(ProposedChangesCopy.showing(24, of: 31, open: true) == "Showing 24 of 31. Decide these to see the rest.")
    #expect(ProposedChangesCopy.showing(24, of: 31, open: false) == "Showing 24 of 31.")
    #expect(ProposedChangesCopy.disputes(2) == "2 say it’s wrong.")
    #expect(ProposedChanges.networkTitle("apple_music") == "Apple Music")
    #expect(ProposedChanges.networkTitle("myspace") == nil)
}
