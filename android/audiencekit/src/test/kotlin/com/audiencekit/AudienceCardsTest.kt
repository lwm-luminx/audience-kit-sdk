package com.audiencekit

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

private const val AUDIENCE_CARD_JSON = """
{"id":"c-1","category":"health","label":"Promoted","sponsorName":"Utah AIDS Foundation",
 "headline":"Free testing Thursdays","body":"Walk in, no appointment.","imageUrl":"https://cdn.example/t.jpg",
 "imageAlt":"The clinic door","linkUrl":"https://uaf.example","linkLabel":"Find a time","startsOn":"2026-11-20",
 "endsOn":"2026-12-31","weekdays":[4],"screens":["NOW","VENUES"],"localeIds":["l-1"],"priceCents":0,
 "paused":false,"paymentStatus":null,"venue":null,"event":null,"publication":null,
 "weeklyViewers":[{"weekStart":"2026-11-16","viewers":1204,"fewerThan":null},
                  {"weekStart":"2026-11-09","viewers":null,"fewerThan":20}]}
"""

private fun cardsData(json: String): JsonObject = Json.parseToJsonElement(json).jsonObject

class AudienceCardsTest {
    @Test
    fun theAudiencesCardsParseWithoutPublishersAds() {
        assertTrue(AudienceCards.CARDS_QUERY.trimStart().startsWith("# endpoint: staff"))
        val list = AudienceCards.parseCards(
            cardsData(
                """{"advertising":"SPONSORSHIPS","cardCategories":[{"key":"health","label":"Health",
                "description":"Clinics","hideable":true}],"promoPlacements":[$AUDIENCE_CARD_JSON,{"id":"ad-1",
                "category":"small_business","sponsorName":"Club Verse","headline":"Two for one","startsOn":"2026-11-20",
                "publication":{"id":"p-1","name":"QSaltLake"}}]}""",
            ),
        )
        assertEquals(AudienceCardsLevel.SPONSORSHIPS, list.level)
        assertEquals(listOf("health"), list.categories.map { it.key })
        assertEquals(listOf("c-1"), list.cards.map { it.id })
        val card = list.cards.first()
        assertEquals(listOf(AudienceCardScreen.NOW, AudienceCardScreen.VENUES), card.screens)
        assertTrue(card.editable)
        assertEquals(1204, card.lastWeek?.viewers)
        assertEquals("1,204 viewers", AudienceCardsCopy.viewers(card.weeklyViewers[0]))
        assertEquals("Fewer than 20 viewers", AudienceCardsCopy.viewers(card.weeklyViewers[1]))

        val empty = AudienceCards.parseCards(cardsData("""{"advertising":"SOMETHING_NEW"}"""))
        assertTrue(empty.cards.isEmpty())
        assertEquals(AudienceCardsLevel.UNKNOWN, empty.level)
        assertEquals(AudienceCardCategory.DEFAULTS, empty.categories)
    }

    @Test
    fun aCardsStatusFollowsItsDatesAndPause() {
        val card = AudienceCards.parseSave(cardsData("""{"savePromoPlacement":{"promoPlacement":$AUDIENCE_CARD_JSON}}"""))!!
        assertEquals(AudienceCardStatus.SCHEDULED, card.status("2026-11-19"))
        assertEquals(AudienceCardStatus.RUNNING, card.status("2026-11-25"))
        assertEquals(AudienceCardStatus.ENDED, card.status("2027-01-01"))
        val paused = AudienceCard(id = "c-2", sponsorName = "S", headline = "H", startsOn = "2026-11-01", paused = true)
        assertEquals(AudienceCardStatus.PAUSED, paused.status("2026-11-25"))
        val venueCard = AudienceCard(
            id = "c-3", category = "venue", sponsorName = "S", headline = "H", startsOn = "2026-11-01",
            venue = AudienceCard.Ref("v-1", "The Edge"),
        )
        assertFalse(venueCard.editable)
        assertEquals("c-1", AudienceCards.parseDelete(cardsData("""{"deletePromoPlacement":{"deletedId":"c-1"}}""")))
        assertNull(AudienceCards.parseSave(cardsData("{}")))
    }

    @Test
    fun savingACardSendsTheWholeCard() {
        val card = AudienceCards.parseSave(cardsData("""{"savePromoPlacement":{"promoPlacement":$AUDIENCE_CARD_JSON}}"""))!!
        val draft = AudienceCardDraft.of(card).copy(body = "  ", weekdays = listOf(5, 1), endsOn = null)
        assertTrue(draft.problems.isEmpty())
        val input = AudienceCards.saveVariables(draft)["input"] as JsonObject
        assertEquals(JsonPrimitive("c-1"), input["id"])
        assertEquals(JsonNull, input["body"])
        assertEquals(JsonNull, input["endsOn"])
        assertEquals(JsonArray(listOf(JsonPrimitive(1), JsonPrimitive(5))), input["weekdays"])
        assertEquals(JsonArray(listOf(JsonPrimitive("NOW"), JsonPrimitive("VENUES"))), input["screens"])
        assertEquals(JsonPrimitive(false), input["paused"])
        assertEquals(mapOf("id" to JsonPrimitive("c-1")), AudienceCards.idVariables("c-1"))

        val fresh = AudienceCards.saveVariables(AudienceCardDraft(sponsorName = " A ", headline = "B", startsOn = "2026-11-22"))
        val newInput = fresh["input"] as JsonObject
        assertNull(newInput["id"])
        assertEquals(JsonPrimitive("A"), newInput["sponsorName"])
    }

    @Test
    fun aDraftSaysWhatStopsIt() {
        val draft = AudienceCardDraft(
            sponsorName = "", headline = " ", imageUrl = "http://x.example/a.jpg", linkUrl = "ftp://x",
            startsOn = "2026-11-22", endsOn = "2026-11-01",
        )
        assertEquals(
            listOf(
                "Say who placed it.", "Add a headline.", "The picture needs an https link.",
                "The link needs an https link.", "Say what the picture shows.", "It ends before it starts.",
            ),
            draft.problems,
        )
        assertTrue("announcement" in AudienceCardCategory.WRITABLE)
        assertFalse("audiencekit" in AudienceCardCategory.WRITABLE)
        assertEquals(5, AudienceCardScreen.entries.size)
        assertEquals(listOf("Running", "Scheduled", "Paused", "Ended"), AudienceCardStatus.entries.map { it.title })
    }
}
