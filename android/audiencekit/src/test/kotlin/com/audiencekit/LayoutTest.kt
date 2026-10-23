package com.audiencekit

import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.io.IOException
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

private fun layoutClient(stub: StubTransport): AudienceKitClient = AudienceKitClient(
    AudienceKitConfiguration(
        baseUrl = StubTransport.BASE_URL,
        host = "hotmess.admin.audiencekit.com",
        audienceId = "b0f8b66a-e636-495d-9475-0f5317ea08e0",
        facebookAppId = "842337999153841",
        environment = AudienceKitEnvironment.PRODUCTION,
    ),
    InMemoryTokenStore("session-token"),
    stub,
)

private const val PROMO = """
{"id":"pp-1","category":"health","label":"Promoted","sponsorName":"Clinic","headline":"Free testing",
 "body":null,"imageUrl":"https://cdn.example/a.png","imageAlt":"A clinic","linkUrl":"https://clinic.example",
 "linkLabel":"Book","venue":null,"event":null}
"""

private const val LAYOUT = """
{"data":{"layout":{"id":"lay-1","refreshAfter":60,"cards":[
  {"id":"now.chat:v-1","kind":"now.chat","rank":2,"title":null,"event":{"id":"e-1"},"venue":{"id":"v-1"},"locale":null},
  {"id":"now.stage:e-1","kind":"now.stage","rank":1,"title":null,"stageEvent":{"id":"e-1"},"venue":{"id":"v-1"}},
  {"id":"promo.slot:1","kind":"promo.slot","rank":3,"title":null,"candidates":[$PROMO,
    {"id":"pp-2","category":"charity","label":"Charity","sponsorName":"Trevor","headline":"Donate",
     "venue":null,"event":null},{"id":"pp-bad"}]},
  {"id":"venues.nearby","kind":"venues.nearby","rank":4,"title":"Near you","venues":[{"id":"v-2"},{"id":"v-3"}],
   "locale":{"id":"l-1"}},
  {"id":"web:1","kind":"web","rank":5,"title":null,"headline":"Pride weekend","body":"Schedule","imageUrl":null,
   "imageAlt":null,"linkUrl":"https://hotmess.social/pride","linkLabel":"See it"},
  {"id":"future:1","kind":"future.thing","rank":6,"title":null},
  {"kind":"broken"}
]}}}
"""

class LayoutTest {
    @Test
    fun readsTheLayoutInRankOrder() = runTest {
        val stub = StubTransport { StubTransport.json(200, LAYOUT) }
        val layout = layoutClient(stub).layout(
            LayoutScreen.NOW,
            listOf("now.stage", "now.chat"),
            Coordinates(37.7, -122.4),
            localeId = "l-1",
            appVersion = "2.3",
        )

        assertEquals("lay-1", layout.id)
        assertFalse(layout.isFallback)
        assertEquals(
            listOf("now.stage", "now.chat", "promo.slot", "venues.nearby", "web", "future.thing"),
            layout.cards.map { it.kind },
        )
        assertEquals("e-1", layout.cards[0].eventId)
        assertEquals("v-1", layout.cards[0].venueId)
        assertEquals(listOf("v-2", "v-3"), layout.card("venues.nearby")?.venueIds)
        assertEquals("Near you", layout.card("venues.nearby")?.title)
        assertEquals("Pride weekend", layout.card("web")?.web?.headline)
        assertNull(layout.card("now.chat")?.web)
        // The candidate missing its fields is dropped, not the slot.
        assertEquals(listOf("pp-1", "pp-2"), layout.card("promo.slot")?.candidates?.map { it.id })
        assertEquals("Book", layout.card("promo.slot")?.candidates?.first()?.content?.linkLabel)

        val variables = stub.requests.single().jsonBody()["variables"]!!.jsonObject
        assertEquals("NOW", variables["screen"]!!.jsonPrimitive.content)
        assertEquals("l-1", variables["localeId"]!!.jsonPrimitive.content)
        val client = variables["client"]!!.jsonObject
        assertEquals(listOf("now.stage", "now.chat"), client["cardKinds"]!!.jsonArray.map { it.jsonPrimitive.content })
        assertEquals("2.3", client["appVersion"]!!.jsonPrimitive.content)
    }

    @Test
    fun layoutClientSkipsKindsTheAppDidNotList() = runTest {
        val stub = StubTransport { StubTransport.json(200, LAYOUT) }
        val layout = LayoutClient(
            layoutClient(stub),
            LayoutScreen.NOW,
            cardKinds = listOf("now.stage", "now.chat", "promo.slot", "web"),
            fallback = listOf("now.stage"),
        ).load()

        assertEquals(listOf("now.stage", "now.chat", "promo.slot", "web"), layout.cards.map { it.kind })
    }

    @Test
    fun layoutClientFallsBackOffline() = runTest {
        val stub = StubTransport { StubTransport.failure(IOException("offline")) }
        val layout = LayoutClient(
            layoutClient(stub),
            LayoutScreen.VENUES,
            cardKinds = listOf("venues.all"),
            fallback = listOf("venues.all", "venues.thinCity"),
        ).load()

        assertTrue(layout.isFallback)
        assertEquals(listOf("venues.all", "venues.thinCity"), layout.cards.map { it.kind })
        assertTrue(layout.cards.all { it.isFallback })
    }

    @Test
    fun registryDrawsKnownKindsOnly() {
        val registry = CardRegistry<String>()
            .register("now.stage") { "stage" }
            .register("promo.slot") { card -> card.promo(CardFilter.NONE)?.content?.headline }
        val layout = CardLayout(
            "l",
            listOf(
                LayoutCard("a", "now.stage", 1),
                LayoutCard("b", "mystery", 2),
                LayoutCard("c", "promo.slot", 3),
            ),
        )

        assertEquals(listOf("now.stage", "promo.slot"), registry.kinds)
        // An empty slot draws nothing.
        assertEquals(listOf("stage"), registry.render(layout).map { it.second })
    }

    @Test
    fun filterHidesOnlyHideableCategories() {
        val content = CardContent("x")
        val card = LayoutCard(
            "s",
            "promo.slot",
            1,
            candidates = listOf(
                PromoCard("1", "venue", "Promoted", "Bar", content),
                PromoCard("2", "health", "Promoted", "Clinic", content),
            ),
        )
        val categories = listOf(
            CardCategory("venue", "Venues", hideable = false),
            CardCategory("health", "Health", hideable = true),
        )

        assertEquals("1", card.promo(CardFilter(setOf("health"), categories))?.id)
        // Venues can't be turned off, even if they were before the audience said so.
        assertEquals("1", card.promo(CardFilter(setOf("venue"), categories))?.id)
        // Until the categories load, every hidden one is honoured.
        assertEquals("2", card.promo(CardFilter(setOf("venue")))?.id)
        assertNull(card.promo(CardFilter(setOf("venue", "health"))))
    }

    @Test
    fun readsCardCategoriesAndRecordsViews() = runTest {
        val stub = StubTransport { request ->
            if (request.jsonBody()["operationName"]!!.jsonPrimitive.content == "CardCategories") {
                StubTransport.json(
                    200,
                    """{"data":{"cardCategories":[{"key":"health","label":"Health","description":"STI testing","hideable":true}]}}""",
                )
            } else {
                StubTransport.json(200, """{"data":{"recordCardViews":{"recorded":2}}}""")
            }
        }
        val client = layoutClient(stub)

        assertEquals(listOf(CardCategory("health", "Health", "STI testing", true)), client.cardCategories())
        assertEquals(2, client.recordCardViews(listOf("pp-1", "pp-2"), "lay-1"))
        val variables = stub.requests.last().jsonBody()["variables"]!!.jsonObject
        assertEquals(listOf("pp-1", "pp-2"), variables["promoIds"]!!.jsonArray.map { it.jsonPrimitive.content })
        assertEquals("lay-1", variables["layoutId"]!!.jsonPrimitive.content)
    }
}
