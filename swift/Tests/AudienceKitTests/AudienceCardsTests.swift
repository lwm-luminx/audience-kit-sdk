import AudienceCore
import Foundation
import Testing

private func decodeCards<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
    try JSONDecoder().decode(type, from: Data(json.utf8))
}

private let cardJSON = """
    {"id":"c-1","category":"health","label":"Promoted","sponsorName":"Utah AIDS Foundation",
     "headline":"Free testing Thursdays","body":"Walk in, no appointment.","imageUrl":"https://cdn.example/t.jpg",
     "imageAlt":"The clinic door","linkUrl":"https://uaf.example","linkLabel":"Find a time","startsOn":"2026-11-20",
     "endsOn":"2026-12-31","weekdays":[4],"screens":["NOW","VENUES"],"localeIds":["l-1"],"priceCents":0,
     "paused":false,"paymentStatus":null,"venue":null,"event":null,"publication":null,
     "weeklyViewers":[{"weekStart":"2026-11-16","viewers":1204,"fewerThan":null},
                      {"weekStart":"2026-11-09","viewers":null,"fewerThan":20}]}
    """

@Test func theAudiencesCardsDecodeWithoutPublishersAds() throws {
    #expect(AudienceCards.cardsQuery.hasPrefix("# endpoint: staff"))
    #expect(AudienceCards.cardsQuery.contains("promoPlacements {"))
    let response = try decodeCards(AudienceCards.CardsResponse.self, """
        {"advertising":"SPONSORSHIPS","cardCategories":[{"key":"health","label":"Health","description":"Clinics",
         "hideable":true}],"promoPlacements":[\(cardJSON),{"id":"ad-1","category":"small_business","label":"Ad",
         "sponsorName":"Club Verse","headline":"Two for one","startsOn":"2026-11-20","weekdays":[],"screens":[],
         "localeIds":[],"priceCents":5000,"paused":false,"publication":{"id":"p-1","name":"QSaltLake"},
         "weeklyViewers":[]}]}
        """)
    #expect(response.level == .sponsorships)
    #expect(!response.level.note.isEmpty)
    #expect(response.categories.map(\.key) == ["health"])
    #expect(response.cards.map(\.id) == ["c-1"])
    let card = try #require(response.cards.first)
    #expect(card.screens == [.now, .venues])
    #expect(card.editable)
    #expect(card.lastWeek?.viewers == 1204)
    #expect(AudienceCardsCopy.viewers(card.weeklyViewers[0]) == "1,204 viewers")
    #expect(AudienceCardsCopy.viewers(card.weeklyViewers[1]) == "Fewer than 20 viewers")

    let empty = try decodeCards(AudienceCards.CardsResponse.self, #"{"advertising":"SOMETHING_NEW"}"#)
    #expect(empty.cards.isEmpty)
    #expect(empty.level == .unknown && empty.level.note.isEmpty)
    #expect(empty.categories == AudienceCardCategory.defaults)
}

@Test func aCardsStatusFollowsItsDatesAndPause() throws {
    let card = try decodeCards(AudienceCard.self, cardJSON)
    #expect(card.status(on: "2026-11-19") == .scheduled)
    #expect(card.status(on: "2026-11-25") == .running)
    #expect(card.status(on: "2027-01-01") == .ended)
    let paused = AudienceCard(id: "c-2", sponsorName: "S", headline: "H", startsOn: "2026-11-01", paused: true)
    #expect(paused.status(on: "2026-11-25") == .paused)
    #expect(AudienceCardStatus.allCases.map(\.title) == ["Running", "Scheduled", "Paused", "Ended"])
    let venueCard = AudienceCard(id: "c-3", category: "venue", sponsorName: "S", headline: "H", startsOn: "2026-11-01",
                                 venue: .init(id: "v-1", name: "The Edge"))
    #expect(!venueCard.editable)
}

@Test func savingACardSendsTheWholeCard() throws {
    var draft = AudienceCardDraft(try decodeCards(AudienceCard.self, cardJSON))
    draft.body = "  "
    draft.weekdays = [5, 1]
    draft.endsOn = nil
    #expect(draft.problems.isEmpty)
    let variables = AudienceCards.saveVariables(draft)
    guard case let .object(input)? = variables["input"] else { Issue.record("no input"); return }
    #expect(input["id"] == .string("c-1"))
    #expect(input["body"] == .null)
    #expect(input["endsOn"] == .null)
    #expect(input["weekdays"] == .array([.int(1), .int(5)]))
    #expect(input["screens"] == .array([.string("NOW"), .string("VENUES")]))
    #expect(input["localeIds"] == .array([.string("l-1")]))
    #expect(input["paused"] == .bool(false))
    #expect(AudienceCards.idVariables("c-1") == ["id": .string("c-1")])

    let fresh = AudienceCards.saveVariables(AudienceCardDraft(sponsorName: " A ", headline: "B", startsOn: "2026-11-22"))
    guard case let .object(newInput)? = fresh["input"] else { Issue.record("no input"); return }
    #expect(newInput["id"] == nil)
    #expect(newInput["sponsorName"] == .string("A"))
}

@Test func aDraftSaysWhatStopsIt() {
    let draft = AudienceCardDraft(sponsorName: "", headline: " ", imageUrl: "http://x.example/a.jpg",
                                  linkUrl: "ftp://x", startsOn: "2026-11-22", endsOn: "2026-11-01")
    #expect(draft.problems == ["Say who placed it.", "Add a headline.", "The picture needs an https link.",
                               "The link needs an https link.", "Say what the picture shows.",
                               "It ends before it starts."])
    #expect(AudienceCardCategory.writable.contains("announcement"))
    #expect(!AudienceCardCategory.writable.contains("audiencekit"))
}

@Test func theAnswersOfSaveAndDeleteDecode() throws {
    let saved = try decodeCards(AudienceCards.SaveResponse.self, #"{"savePromoPlacement":{"promoPlacement":\#(cardJSON)}}"#)
    #expect(saved.card?.id == "c-1")
    let deleted = try decodeCards(AudienceCards.DeleteResponse.self, #"{"deletePromoPlacement":{"deletedId":"c-1"}}"#)
    #expect(deleted.deletedID == "c-1")
    #expect(AudienceCardScreen.allCases.map(\.title).count == 5)
}
