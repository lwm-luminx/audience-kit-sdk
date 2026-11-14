package com.audiencekit

import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

private fun titlesClient(stub: StubTransport): AudienceKitClient = AudienceKitClient(
    AudienceKitConfiguration(baseUrl = StubTransport.BASE_URL, audienceId = "b0f8b66a-e636-495d-9475-0f5317ea08e2"),
    InMemoryTokenStore("session-token"),
    stub,
)

class TitlesTest {
    @Test
    fun readsAPerformersTitlesReigningFirst() = runTest {
        val stub = StubTransport {
            StubTransport.json(
                200,
                """{"data":{"node":{"id":"p-1","offices":[
                  {"id":"o-1","office":"PAGEANT_TITLE","title":"Miss Gay Utah","label":"Miss Gay Utah, Utah","status":"FORMER","termStart":"2023-06-01","termEnd":"2024-06-01","locale":{"id":"l-1","name":"Utah"}},
                  {"id":"o-2","office":"US_HOUSE","title":"U.S. Representative","label":"U.S. Representative, UT-3","status":"INCUMBENT","locale":{"id":"l-2","name":"UT-3"}},
                  {"id":"o-3","office":"COURT_TITLE","title":"Empress XLVII","label":"Empress XLVII, Salt Lake City","status":"INCUMBENT","termStart":"2026-02-01","locale":{"id":"l-3","name":"Salt Lake City"}}
                ]}}}""",
            )
        }

        val titles = titlesClient(stub).titles("p-1")

        assertEquals(listOf("Empress XLVII", "Miss Gay Utah"), titles.map { it.title }, "civic offices left out")
        assertTrue(titles[0].isReigning)
        assertFalse(titles[1].isReigning)
        assertEquals("Salt Lake City · 2026", titles[0].detail)
        assertEquals("Utah · 2023–2024", titles[1].detail)
        val request = stub.requests.single()
        assertEquals("PersonTitles", (request.jsonBody()["operationName"] as JsonPrimitive).content)
        assertEquals("p-1", (request.jsonBody()["variables"]!!.jsonObject["id"] as JsonPrimitive).content)
        assertTrue((request.jsonBody()["query"] as JsonPrimitive).content.contains("offices(status: [INCUMBENT, FORMER])"))
    }

    @Test
    fun noOneHasTitlesWhereTheyAreNotAPerson() = runTest {
        val stub = StubTransport { StubTransport.json(200, """{"data":{"node":null}}""") }
        assertTrue(titlesClient(stub).titles("v-1").isEmpty())
    }
}
