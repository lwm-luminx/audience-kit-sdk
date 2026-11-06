package com.audiencekit

import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

private const val FEED_JSON = """{"url":"https://api.example.com/v1/calendar/abc.ics",
 "webcalUrl":"webcal://api.example.com/v1/calendar/abc.ics",
 "googleUrl":"https://calendar.google.com/calendar/render?cid=webcal%3A%2F%2Fapi.example.com%2Fv1%2Fcalendar%2Fabc.ics",
 "venues":[{"id":"v-1"}]}"""

class CalendarTest {
    private fun client(stub: StubTransport) = AudienceKitClient(
        AudienceKitConfiguration(baseUrl = StubTransport.BASE_URL, audienceId = "b0f8b66a-e636-495d-9475-0f5317ea08e1"),
        InMemoryTokenStore("session-token"),
        stub,
    )

    @Test
    fun linksForAFeedAreBuiltAsTheApiMakesThem() {
        val links = CalendarLinks.of("https://api.audiencekit.com/v1/venues/v-1/calendar.ics?key=k_1")

        assertEquals("webcal://api.audiencekit.com/v1/venues/v-1/calendar.ics?key=k_1", links.webcalUrl)
        assertEquals(
            "https://calendar.google.com/calendar/render?cid=" +
                "webcal%3A%2F%2Fapi.audiencekit.com%2Fv1%2Fvenues%2Fv-1%2Fcalendar.ics%3Fkey%3Dk_1",
            links.googleUrl,
        )
    }

    @Test
    fun followingAVenueAddsItToTheOneFeed() = runTest {
        val stub = StubTransport { request ->
            val following = request.jsonBody()["variables"]!!.jsonObject["following"]!!.jsonPrimitive.boolean
            val feed = if (following) FEED_JSON else FEED_JSON.replace("""[{"id":"v-1"}]""", "[]")
            StubTransport.Reply.Json(200, """{"data":{"setCalendarFeedVenue":{"calendarFeed":$feed}}}""")
        }
        val client = client(stub)

        val feed = client.followVenueInCalendar("v-1")
        assertTrue(feed.follows("v-1"))
        assertFalse(feed.follows("v-2"))
        assertEquals("https://api.example.com/v1/calendar/abc.ics", feed.links.url)
        assertFalse(client.followVenueInCalendar("v-1", following = false).follows("v-1"))
        assertEquals("SetCalendarFeedVenue", (stub.requests[0].jsonBody()["operationName"] as JsonPrimitive).content)
        assertEquals("v-1", stub.requests[0].jsonBody()["variables"]!!.jsonObject["venueId"]!!.jsonPrimitive.content)
    }

    @Test
    fun thePersonalFeedIsReadMadeAndDeleted() = runTest {
        val stub = StubTransport { request ->
            when ((request.jsonBody()["operationName"] as JsonPrimitive).content) {
                "CalendarFeed" -> StubTransport.Reply.Json(200, """{"data":{"me":{"calendarFeed":null}}}""")
                "CreateCalendarFeed" ->
                    StubTransport.Reply.Json(200, """{"data":{"createCalendarFeed":{"calendarFeed":$FEED_JSON}}}""")
                else -> StubTransport.Reply.Json(200, """{"data":{"deleteCalendarFeed":{"deleted":true}}}""")
            }
        }
        val client = client(stub)

        assertNull(client.calendarFeed())
        val feed = client.createCalendarFeed(reset = true)
        assertEquals(CalendarLinks.of("https://api.example.com/v1/calendar/abc.ics"), feed.links)
        assertEquals(listOf("v-1"), feed.venueIds)
        assertTrue(client.deleteCalendarFeed())

        assertEquals(
            listOf("CalendarFeed", "CreateCalendarFeed", "DeleteCalendarFeed"),
            stub.requests.map { (it.jsonBody()["operationName"] as JsonPrimitive).content },
        )
        assertTrue(stub.requests[1].jsonBody()["variables"]!!.jsonObject["reset"]!!.jsonPrimitive.boolean)
    }
}
