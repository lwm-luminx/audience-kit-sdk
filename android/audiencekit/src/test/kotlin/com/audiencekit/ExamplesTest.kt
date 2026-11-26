package com.audiencekit

import com.audiencekit.examples.calendarLinks
import com.audiencekit.examples.digest
import com.audiencekit.examples.doorPass
import com.audiencekit.examples.goingTo
import com.audiencekit.examples.nights
import com.audiencekit.examples.reportHarassment
import com.audiencekit.examples.whatsOn
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.time.ZoneId
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** Runs the programs in android/examples against a stub API. */
class ExamplesTest {
    private fun client(answers: Map<String, (RecordedRequest) -> String>): Pair<AudienceKitClient, StubTransport> {
        val stub = StubTransport { request ->
            val name = (request.jsonBody()["operationName"] as JsonPrimitive).content
            val answer = answers[name] ?: return@StubTransport StubTransport.Reply.Json(200, """{"errors":[{"message":"no $name"}]}""")
            StubTransport.Reply.Json(200, answer(request))
        }
        val client = AudienceKitClient(
            AudienceKitConfiguration(baseUrl = StubTransport.BASE_URL, audienceId = "b0f8b66a-e636-495d-9475-0f5317ea08e1"),
            InMemoryTokenStore("session-token"),
            stub,
        )
        return client to stub
    }

    private fun article(id: String, title: String) = """{"id":"$id","slug":"news","title":"$title","byline":"Sam",
        "summary":"It's big.","teaser":true,"canonicalUrl":"https://paper/news","disclosure":"Sam tends bar there.",
        "publication":{"id":"p1","name":"Paper"}}"""

    @Test
    fun theNewsDigest() = runTest {
        val (client, _) = client(
            mapOf(
                "Locales" to { _ -> """{"data":{"locales":[{"id":"L1","name":"Boulder"},{"id":"L2","name":"Denver"}]}}""" },
                "Articles" to { _ -> """{"data":{"soapbox":{"articles":{"nodes":[${article("a1", "Bar opens")}]}}}}""" },
                "NationalArticles" to { _ ->
                    """{"data":{"soapbox":{"articles":{"nodes":[${article("a1", "Bar opens")},${article("a2", "Pride")}]}}}}"""
                },
            ),
        )
        val text = digest(client, "Denver")
        assertTrue(text.startsWith("# Denver this week"), text)
        assertTrue("- **Bar opens**, Sam for Paper ([read on Paper](https://paper/news))\n  It's big.\n  _Sam" in text, text)
        assertTrue("## Around the country\n\n- **Pride**" in text, text)
        assertTrue(digest(client).startsWith("# Boulder"))

        val (quiet, _) = client(
            mapOf(
                "Locales" to { _ -> """{"data":{"locales":[{"id":"L1"}]}}""" },
                "Articles" to { _ -> """{"data":{"soapbox":null}}""" },
                "NationalArticles" to { _ -> """{"data":{"soapbox":null}}""" },
            ),
        )
        assertEquals("", digest(quiet))
        val (empty, _) = client(mapOf("Locales" to { _ -> """{"data":{"locales":[]}}""" }))
        assertEquals("", digest(empty))
    }

    @Test
    fun whatsOnGroupsEventsByNightInTheLocalesZone() = runTest {
        val events = """[
            {"id":"e2","name":"Bingo","startAt":"2026-12-07T02:30:00Z","isCanceled":true},
            {"id":"e1","name":"Brunch","startAt":"2026-12-06T18:00:00Z","venue":{"name":"Club"}},
            {"id":"e3","name":null,"startAt":"2026-12-08T03:00:00Z"},
            {"id":"e4","name":"Someday"}
        ]"""
        val (client, stub) = client(mapOf("Events" to { _ -> """{"data":{"events":{"list":{"nodes":$events}}}}""" }))
        val nights = whatsOn(client, "L1")
        assertEquals(listOf("Sunday, December 6", "Monday, December 7"), nights.map { it.title })
        assertEquals(listOf("Brunch", "Bingo"), nights[0].events.map { it.name })
        assertEquals("11:00 AM", nights[0].events[0].time)
        assertEquals("Club", nights[0].events[0].where)
        assertTrue(nights[0].events[1].canceled)
        assertEquals("Untitled", nights[1].events[0].name)
        assertEquals("L1", stub.requests[0].jsonBody()["variables"]!!.jsonObject["localeId"]!!.jsonPrimitive.content)
        assertTrue(nights(emptyList(), ZoneId.of("UTC")).isEmpty())
    }

    @Test
    fun memberActions() = runTest {
        val feed = """{"url":"https://f.ics","webcalUrl":"webcal://f","googleUrl":"https://g","venues":[]}"""
        val admission = """{"id":"adm-1","status":"PAID","night":"2026-12-06","passSecret":"c2VjcmV0"}"""
        val (client, stub) = client(
            mapOf(
                "RSVPEvent" to { _ -> """{"data":{"rsvpEvent":{"event":{"id":"e1","rsvp":{"count":4,"mine":"ATTENDING"}}}}}""" },
                "CreateCalendarFeed" to { _ -> """{"data":{"createCalendarFeed":{"calendarFeed":$feed}}}""" },
                "SetCalendarFeedVenue" to { _ -> """{"data":{"setCalendarFeedVenue":{"calendarFeed":$feed}}}""" },
                "VenueCover" to { request ->
                    val id = request.jsonBody()["variables"]!!.jsonObject["id"]!!.jsonPrimitive.content
                    if (id == "v1") {
                        """{"data":{"venues":{"venue":{"id":"v1","tickets":{"cover":{"viewerAdmission":$admission}}}}}}"""
                    } else {
                        """{"data":{"venues":{"venue":null}}}"""
                    }
                },
                "ReportContent" to { _ -> """{"data":{"reportContent":{"reported":true,"blocked":true}}}""" },
            ),
        )
        assertEquals(4, goingTo(client, "e1"))
        assertEquals(mapOf("appleOrOutlook" to "webcal://f", "google" to "https://g"), calendarLinks(client))
        calendarLinks(client, "v1")
        val pass = doorPass(client, "v1", now = 1_000_005)!!
        assertTrue(pass.code.startsWith("HMC1.adm-1.33333."))
        assertEquals(15, pass.refreshInSeconds)
        assertNull(doorPass(client, "gone"))
        val result = reportHarassment(client, "m1")
        assertTrue(result.reported && result.blocked)
        val report = stub.requests.last().jsonBody()["variables"]!!.jsonObject
        assertEquals("Harassment or hate", report["reason"]!!.jsonPrimitive.content)
    }
}
