package com.audiencekit

import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.jsonPrimitive
import kotlin.random.Random
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

private const val FLYERS_AUDIENCE = "b0f8b66a-e636-495d-9475-0f5317ea08e0"

private fun flyersClient(stub: StubTransport): AudienceKitClient = AudienceKitClient(
    AudienceKitConfiguration(
        baseUrl = StubTransport.BASE_URL,
        host = "hotmess.admin.audiencekit.com",
        audienceId = FLYERS_AUDIENCE,
        facebookAppId = "842337999153841",
        environment = AudienceKitEnvironment.PRODUCTION,
    ),
    InMemoryTokenStore("session-token"),
    stub,
)

private const val FLYERS_LAYOUT = """
{"data":{"layout":{"id":"lay-9","refreshAfter":60,"cards":[
  {"id":"flyers:l-1","kind":"flyers","rank":1,"title":null,"locale":{"id":"l-1"},
   "disclosure":"Based on your city and the time, nothing else.","explainerLabel":"What's a digital flyer?",
   "explainerUrl":"https://audiencekit.com/digital-flyers/","flyers":[
     {"id":"f-1","headline":"Free food","tags":["food"],"tone":"gentle","category":"food",
      "lines":["Just a flyer for Salt Lake City. No idea who you are. Here if you need it."],
      "resource":{"id":"r-1","title":"Pantry","sensitive":false}},
     {"id":"f-2","headline":"Drag bingo","tags":["events"],"tone":"playful","category":"community","lines":["a","b"]},
     {"headline":"broken"}
   ]}
]}}}
"""

private const val DIRECTORY = """
{"locale":{"id":"l-1","name":"Salt Lake City"},"generated_at":"2026-11-15T22:00:00Z",
 "resources":[
  {"id":"r-1","title":"Utah Food Bank Mobile Pantry","name":"Utah Food Bank Mobile Pantry","sensitive":false,
   "facets":["food","no-id-required"],"phone":"8019782452","hours":[],"sessions":[{"days":[4],"note":"Thursdays"}],
   "intake_note":"No ID needed.","checked_at":null,
   "next_session":{"session":{"days":[4]},"starts_at":"2026-11-19T07:00:00Z","ends_at":"2026-11-20T06:59:59Z"}},
  {"id":"r-2","title":"Support services","name":"YWCA DV","neutral_title":"Support services","sensitive":true,
   "facets":["dv-stalking"],"hours":[],"sessions":[],"next_session":null}
 ],
 "facets":["food","dv-stalking"],
 "needs":[{"key":"food","label":"I need food","facets":["food"]},
          {"key":"safe","label":"I don't feel safe at home","facets":["dv-stalking"]}],
 "advocacy":["No one deserves violence."],"quick_exit":"Leave now"}
"""

class FlyersTest {
    @Test
    fun readsTheFlyersCardAndAsksForItOnlyWhenTheServerHasIt() = runTest {
        val stub = StubTransport { StubTransport.json(200, FLYERS_LAYOUT) }
        val card = flyersClient(stub).layout(LayoutScreen.NOW, listOf(CardKind.FLYERS)).card(CardKind.FLYERS)!!
        val flyers = card.flyers!!
        assertEquals("l-1", card.localeId)
        assertEquals("Based on your city and the time, nothing else.", flyers.disclosure)
        assertEquals(listOf("f-1", "f-2"), flyers.flyers.map { it.id })
        assertTrue(flyers.flyers[0].isGentle)
        assertEquals("Pantry", flyers.flyers[0].resource?.title)
        assertTrue(stub.requests.first().jsonBody()["query"]!!.jsonPrimitive.content.contains("... on FlyersCard"))

        assertFalse(LayoutQueries.layoutFor(SchemaShape(mapOf("PromoCard" to setOf("staffApp")))).contains("FlyersCard"))
        assertTrue(LayoutQueries.layoutFor(SchemaShape(mapOf("FlyersCard" to setOf("flyers")))).contains("on FlyersCard"))
    }

    @Test
    fun keepsDismissalsOnThePhone() {
        val store = InMemoryFlyerDismissalStore()
        val dismissals = FlyerDismissals(store)
        val food = DigitalFlyer(id = "f-1", headline = "Food", category = "food")
        val bingo = DigitalFlyer(id = "f-2", headline = "Bingo")
        val karaoke = DigitalFlyer(id = "f-3", headline = "Karaoke")
        val card = FlyersCardContent("d", "e", "u", listOf(food, bingo, karaoke))

        dismissals.dismiss(bingo)
        assertEquals(listOf("f-1", "f-3"), card.visible(dismissals).map { it.id })
        dismissals.setHidden("food", true)
        assertEquals(listOf("f-3"), card.visible(dismissals).map { it.id })
        assertEquals(setOf("food"), FlyerDismissals(store).hiddenCategories)
        dismissals.setHidden("food", false)
        dismissals.reset()
        assertEquals(3, card.visible(dismissals).size)

        repeat(FlyerDismissals.LIMIT + 5) { dismissals.dismiss(DigitalFlyer(id = "x-$it", headline = "x")) }
        assertEquals(FlyerDismissals.LIMIT, dismissals.dismissedFlyers.size)
        assertFalse("x-0" in dismissals.dismissedFlyers)
    }

    @Test
    fun neverShowsTheSameLineTwiceInARow() {
        val flyer = DigitalFlyer(id = "f", headline = "h", lines = listOf("a", "b", "c"))
        val picker = FlyerLinePicker(random = Random(7))
        var last: String? = null
        repeat(200) {
            val line = picker.line(flyer)
            assertNotEquals(last, line)
            last = line
        }
        assertEquals("only", FlyerLinePicker.pick(listOf("only"), "only"))
        assertNull(FlyerLinePicker.pick(emptyList(), null))
    }

    @Test
    fun fetchesTheDirectoryWithoutTheSessionTokenAndFiltersOnThePhone() = runTest {
        val stub = StubTransport { StubTransport.json(200, DIRECTORY) }
        val directory = flyersClient(stub).communityDirectory("l-1")

        val request = stub.requests.single()
        assertEquals("/v1/audience/$FLYERS_AUDIENCE/community_resources", request.path)
        assertEquals("locale_id=l-1", request.query)
        assertNull(request.header("Authorization"))

        assertEquals(listOf("r-1"), directory.resourcesFor(directory.needs[0]).map { it.id })
        val safe = directory.resourcesFor(directory.needs[1])
        assertEquals(listOf("Support services"), safe.map { it.title })
        assertTrue(safe[0].sensitive)
        assertEquals(listOf("r-1"), directory.resourcesWithAnyOf(emptyList(), listOf("no-id-required")).map { it.id })
        assertEquals("No ID needed.", directory.resources[0].intakeNote)
        assertEquals("2026-11-19T07:00:00Z", directory.resources[0].nextSession?.startsAt)
        assertEquals("Leave now", directory.quickExit)
    }

    @Test
    fun readsTheFlyerCopy() = runTest {
        val stub = StubTransport {
            StubTransport.json(
                200,
                """{"data":{"flyerCopy":{"disclosure":"d","explainerLabel":"e","explainerUrl":"u","quickExit":"Leave now",
                 "advocacy":["You deserve better."],"categories":[{"key":"food","label":"Food"}],
                 "needs":[{"key":"food","label":"I need food","facets":["food"]}]}}}""",
            )
        }
        val copy = flyersClient(stub).flyerCopy()
        assertEquals(listOf("food"), copy.categories.map { it.key })
        assertEquals(listOf("You deserve better."), copy.advocacy)
    }
}
