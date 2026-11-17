import AudienceCore
import Foundation
import Testing

private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
    try JSONDecoder().decode(type, from: Data(json.utf8))
}

private let adJSON = """
    {"id":"ad-1","adStatus":"IN_REVIEW","spot":"ARTICLE","category":"small_business","sponsorName":"Club Verse",
     "sponsorEmail":"ads@verse.example","headline":"Two-for-one Thursdays","body":null,"imageUrl":null,"imageAlt":null,
     "linkUrl":"https://verse.example","linkLabel":"See the menu","articleIds":["a-1"],"startsOn":"2026-11-20",
     "endsOn":null,"weekdays":[4],"priceCents":5000,"soldOutside":true,"paused":false,"reviewNote":null,
     "publication":{"id":"p-1","name":"QSaltLake"},"weeklyViewers":[{"weekStart":"2026-11-09","viewers":1204,
     "fewerThan":null},{"weekStart":"2026-11-02","viewers":null,"fewerThan":20}]}
    """

@Test func aPublicationsAdsDecodeWithTheirReaders() throws {
    #expect(SoapboxAds.adsQuery.hasPrefix("# endpoint: staff"))
    #expect(SoapboxAds.adsQuery.contains("weeklyViewers { weekStart viewers fewerThan }"))
    let response = try decode(SoapboxAds.AdsResponse.self, """
        {"soapbox":{"publication":{"id":"p-1","adsEnabled":true,"adsNeedReview":false,
         "rateSheet":{"notes":null,"contactEmail":"ads@q.example","rates":[{"spot":"ARTICLE","weeklyCents":5000,"slots":4}]},
         "ads":[\(adJSON)]}}}
        """)
    #expect(response.adsEnabled)
    #expect(!response.adsNeedReview)
    let ad = try #require(response.ads.first)
    #expect(ad.status == .inReview)
    #expect(ad.lastWeek?.viewers == 1204)
    #expect(ad.weeklyViewers[1].readersLine == "Fewer than 20 readers")
    #expect(response.rateSheet.rate(for: .article).weeklyCents == 5000)
    #expect(response.rateSheet.rate(for: .publication).weeklyCents == nil)

    let empty = try decode(SoapboxAds.AdsResponse.self, #"{"soapbox":{"publication":null}}"#)
    #expect(empty.ads.isEmpty && !empty.adsEnabled && empty.adsNeedReview)
}

@Test func savingAnAdSendsOnlyWhatChanged() throws {
    let variables = SoapboxAds.saveAdVariables(PublisherAdDraft(
        id: "ad-1", spot: .publication, headline: "New words", endsOn: "", weekdays: [5, 1], priceCents: 0,
        dryRun: true))
    #expect(variables == ["input": .object([
        "id": .string("ad-1"), "spot": .string("PUBLICATION"), "headline": .string("New words"), "endsOn": .null,
        "weekdays": .array([.int(1), .int(5)]), "priceCents": .int(0), "dryRun": .bool(true),
    ])])

    let response = try decode(SoapboxAds.SaveAdResponse.self,
                              #"{"savePublicationAd":{"problems":["Add a headline"],"ad":null}}"#)
    #expect(response.ad == nil)
    #expect(response.problems == ["Add a headline"])
}

@Test func reviewAndTakeDownCarryATrimmedNote() throws {
    #expect(SoapboxAds.reviewVariables(id: "ad-1", approve: false, note: "  Too loud ")
        == ["id": .string("ad-1"), "approve": .bool(false), "note": .string("Too loud")])
    #expect(SoapboxAds.removeVariables(id: "ad-1", note: " ") == ["id": .string("ad-1"), "removed": .bool(true)])
    #expect(SoapboxAds.enableVariables(publicationID: "p-1", enabled: true)
        == ["id": .string("p-1"), "enabled": .bool(true)])
    #expect(SoapboxAds.modeVariables(.reviewAll) == ["mode": .string("REVIEW_ALL")])

    let queue = try decode(SoapboxAds.ReviewQueueResponse.self,
                           #"{"soapbox":{"publisherAds":"REVIEW_ALL","adReviewQueue":[\#(adJSON)]}}"#)
    #expect(queue.mode == .reviewAll)
    #expect(queue.queue.first?.publication?.name == "QSaltLake")
    let reviewed = try decode(SoapboxAds.ModerateAdResponse.self, #"{"removePublicationAd":{"ad":\#(adJSON)}}"#)
    #expect(reviewed.ad?.id == "ad-1")
    #expect(try decode(SoapboxAds.ReviewQueueResponse.self, #"{"soapbox":null}"#).mode == .reviewPending)
}

@Test func theRateSheetSendsEverySpotAndClearsBlanks() throws {
    let sheet = PublicationRateSheet(notes: " ", contactEmail: "ads@q.example",
                                     rates: [PublicationRate(spot: .article, weeklyCents: 5000, slots: 3),
                                             PublicationRate(spot: .publication)])
    #expect(SoapboxAds.rateSheetVariables(publicationID: "p-1", sheet: sheet) == ["input": .object([
        "id": .string("p-1"), "articleWeeklyCents": .int(5000), "articleSlots": .int(3),
        "publicationWeeklyCents": .null, "publicationSlots": .int(4), "notes": .null,
        "contactEmail": .string("ads@q.example"),
    ])])
    let saved = try decode(SoapboxAds.RateSheetResponse.self, """
        {"savePublicationRateSheet":{"publication":{"id":"p-1","rateSheet":{"notes":null,"contactEmail":null,"rates":[]}}}}
        """)
    #expect(saved.rateSheet?.rates.isEmpty == true)
}

@Test func mediaIsAddedEditedAndListed() throws {
    #expect(SoapboxAds.addMediaVariables(publicationID: "p-1", photo: "https://x.example/a.jpg", altText: " A bar ")
        == ["input": .object(["publicationId": .string("p-1"), "photo": .string("https://x.example/a.jpg"),
                              "altText": .string("A bar")])])
    #expect(SoapboxAds.updateMediaVariables(id: "m-1", altText: "A bar", caption: nil, credit: nil)
        == ["input": .object(["id": .string("m-1"), "altText": .string("A bar"), "caption": .string(""),
                              "credit": .string("")])])
    let list = try decode(SoapboxAds.MediaResponse.self, """
        {"soapbox":{"publication":{"id":"p-1","media":[{"id":"m-1","url":"https://x.example/a.jpg","altText":"A bar",
         "caption":null,"credit":"Sam","createdAt":"2026-11-17T19:00:00Z"}]}}}
        """)
    #expect(list.media.first?.credit == "Sam")
    let added = try decode(SoapboxAds.MediaItemResponse.self,
                           #"{"addPublicationMedia":{"media":{"id":"m-2","url":"https://x.example/b.jpg"}}}"#)
    #expect(added.media?.id == "m-2")
}

@Test func moneyReadsAsWeeklyPrices() {
    #expect(SoapboxAdsCopy.weekly(5000) == "$50 a week")
    #expect(SoapboxAdsCopy.money(1250) == "$12.50")
    #expect(PublisherAdStatus.listed.first == .running)
    #expect(SoapboxAds.categories.map(\.key) == ["small_business", "health", "employment", "charity"])
}
