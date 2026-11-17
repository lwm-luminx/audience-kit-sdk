package com.audiencekit

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

private const val SOAPBOX_AD_JSON = """
{"id":"ad-1","adStatus":"IN_REVIEW","spot":"ARTICLE","category":"small_business","sponsorName":"Club Verse",
 "sponsorEmail":"ads@verse.example","headline":"Two-for-one Thursdays","body":null,"imageUrl":null,"imageAlt":null,
 "linkUrl":"https://verse.example","linkLabel":"See the menu","articleIds":["a-1"],"startsOn":"2026-11-20",
 "endsOn":null,"weekdays":[4],"priceCents":5000,"soldOutside":true,"paused":false,"reviewNote":null,
 "publication":{"id":"p-1","name":"QSaltLake"},"weeklyViewers":[{"weekStart":"2026-11-09","viewers":1204,
 "fewerThan":null},{"weekStart":"2026-11-02","viewers":null,"fewerThan":20}]}
"""

private fun data(json: String): JsonObject = Json.parseToJsonElement(json).jsonObject

class SoapboxAdsTest {
    @Test
    fun aPublicationsAdsParseWithTheirReaders() {
        assertTrue(SoapboxAds.ADS_QUERY.trimStart().startsWith("# endpoint: staff"))
        assertTrue(SoapboxAds.ADS_QUERY.contains("weeklyViewers { weekStart viewers fewerThan }"))
        val ads = SoapboxAds.parseAds(
            data(
                """{"soapbox":{"publication":{"id":"p-1","adsEnabled":true,"adsNeedReview":false,
                "rateSheet":{"notes":null,"contactEmail":"ads@q.example","rates":[{"spot":"ARTICLE","weeklyCents":5000,"slots":4}]},
                "ads":[$SOAPBOX_AD_JSON]}}}""",
            ),
        )
        assertTrue(ads.adsEnabled)
        val ad = ads.ads.single()
        assertEquals(PublisherAdStatus.IN_REVIEW, ad.adStatus)
        assertEquals(listOf(4), ad.weekdays)
        assertEquals(1204, ad.lastWeek?.viewers)
        assertEquals("Fewer than 20 readers", ad.weeklyViewers[1].readersLine)
        assertEquals("QSaltLake", ad.publication?.name)
        assertEquals(5000, ads.rateSheet.rateFor(PublisherAdSpot.ARTICLE).weeklyCents)
        assertNull(ads.rateSheet.rateFor(PublisherAdSpot.PUBLICATION).weeklyCents)

        val empty = SoapboxAds.parseAds(data("""{"soapbox":{"publication":null}}"""))
        assertTrue(empty.ads.isEmpty() && !empty.adsEnabled && empty.adsNeedReview)
    }

    @Test
    fun savingAnAdSendsOnlyWhatChanged() {
        val variables = SoapboxAds.saveAdVariables(
            PublisherAdDraft(
                id = "ad-1", spot = PublisherAdSpot.PUBLICATION, headline = "New words", endsOn = "",
                weekdays = listOf(5, 1), priceCents = 0, dryRun = true,
            ),
        )
        assertEquals(
            JsonObject(
                mapOf(
                    "id" to JsonPrimitive("ad-1"), "spot" to JsonPrimitive("PUBLICATION"),
                    "headline" to JsonPrimitive("New words"), "endsOn" to JsonNull,
                    "weekdays" to JsonArray(listOf(JsonPrimitive(1), JsonPrimitive(5))),
                    "priceCents" to JsonPrimitive(0), "dryRun" to JsonPrimitive(true),
                ),
            ),
            variables["input"],
        )
        val saved = SoapboxAds.parseSaveAd(data("""{"savePublicationAd":{"problems":["Add a headline"],"ad":null}}"""))
        assertNull(saved.ad)
        assertEquals(listOf("Add a headline"), saved.problems)
    }

    @Test
    fun reviewAndTakeDownCarryATrimmedNote() {
        assertEquals(
            mapOf("id" to JsonPrimitive("ad-1"), "approve" to JsonPrimitive(false), "note" to JsonPrimitive("Too loud")),
            SoapboxAds.reviewVariables("ad-1", approve = false, note = "  Too loud "),
        )
        assertEquals(
            mapOf("id" to JsonPrimitive("ad-1"), "removed" to JsonPrimitive(true)),
            SoapboxAds.removeVariables("ad-1", note = " "),
        )
        assertEquals(mapOf("mode" to JsonPrimitive("REVIEW_ALL")), SoapboxAds.modeVariables(PublisherAdsMode.REVIEW_ALL))
        assertEquals(
            mapOf("id" to JsonPrimitive("p-1"), "enabled" to JsonPrimitive(true)),
            SoapboxAds.enableVariables("p-1", enabled = true),
        )
        val queue = SoapboxAds.parseReviewQueue(
            data("""{"soapbox":{"publisherAds":"REVIEW_ALL","adReviewQueue":[$SOAPBOX_AD_JSON]}}"""),
        )
        assertEquals(PublisherAdsMode.REVIEW_ALL, queue.mode)
        assertEquals("ad-1", queue.queue.single().id)
        assertEquals("ad-1", SoapboxAds.parseModerateAd(data("""{"removePublicationAd":{"ad":$SOAPBOX_AD_JSON}}"""))?.id)
        assertEquals(PublisherAdsMode.REVIEW_PENDING, SoapboxAds.parseReviewQueue(data("""{"soapbox":null}""")).mode)
    }

    @Test
    fun theRateSheetSendsEverySpotAndClearsBlanks() {
        val sheet = PublicationRateSheet(
            notes = " ",
            contactEmail = "ads@q.example",
            rates = listOf(PublicationRate(PublisherAdSpot.ARTICLE, 5000, 3), PublicationRate(PublisherAdSpot.PUBLICATION)),
        )
        assertEquals(
            JsonObject(
                mapOf(
                    "id" to JsonPrimitive("p-1"), "articleWeeklyCents" to JsonPrimitive(5000),
                    "articleSlots" to JsonPrimitive(3), "publicationWeeklyCents" to JsonNull,
                    "publicationSlots" to JsonPrimitive(4), "notes" to JsonNull,
                    "contactEmail" to JsonPrimitive("ads@q.example"),
                ),
            ),
            SoapboxAds.rateSheetVariables("p-1", sheet)["input"],
        )
        val saved = SoapboxAds.parseRateSheet(
            data("""{"savePublicationRateSheet":{"publication":{"id":"p-1","rateSheet":{"notes":null,"contactEmail":null,"rates":[]}}}}"""),
        )
        assertEquals(emptyList(), saved?.rates)
    }

    @Test
    fun mediaIsAddedEditedAndListed() {
        assertEquals(
            JsonObject(
                mapOf(
                    "publicationId" to JsonPrimitive("p-1"), "photo" to JsonPrimitive("https://x.example/a.jpg"),
                    "altText" to JsonPrimitive("A bar"),
                ),
            ),
            SoapboxAds.addMediaVariables("p-1", "https://x.example/a.jpg", altText = " A bar ")["input"],
        )
        assertEquals(
            JsonObject(
                mapOf(
                    "id" to JsonPrimitive("m-1"), "altText" to JsonPrimitive("A bar"), "caption" to JsonPrimitive(""),
                    "credit" to JsonPrimitive(""),
                ),
            ),
            SoapboxAds.updateMediaVariables("m-1", "A bar", null, null)["input"],
        )
        val media = SoapboxAds.parseMedia(
            data(
                """{"soapbox":{"publication":{"id":"p-1","media":[{"id":"m-1","url":"https://x.example/a.jpg",
                "altText":"A bar","caption":null,"credit":"Sam","createdAt":"2026-11-17T19:00:00Z"}]}}}""",
            ),
        )
        assertEquals("Sam", media.single().credit)
        val added = SoapboxAds.parseMediaItem(
            data("""{"addPublicationMedia":{"media":{"id":"m-2","url":"https://x.example/b.jpg"}}}"""),
        )
        assertEquals("m-2", added?.id)
    }

    @Test
    fun moneyReadsAsWeeklyPrices() {
        assertEquals("$50 a week", SoapboxAdsCopy.weekly(5000))
        assertEquals("$12.50", SoapboxAdsCopy.money(1250))
        assertEquals(PublisherAdStatus.RUNNING, PublisherAdStatus.LISTED.first())
        assertEquals(listOf("small_business", "health", "employment", "charity"), SoapboxAds.CATEGORIES.map { it.first })
    }
}
