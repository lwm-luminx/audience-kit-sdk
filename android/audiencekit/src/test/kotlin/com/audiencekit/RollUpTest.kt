package com.audiencekit

import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

private fun rollUpClient(stub: StubTransport): AudienceKitClient = AudienceKitClient(
    AudienceKitConfiguration(baseUrl = StubTransport.BASE_URL, audienceId = "00000000-0000-4000-8000-000000000728"),
    InMemoryTokenStore("session-token"),
    stub,
)

private const val ROLL_UP_JSON = """
{"data":{"node":{"rollUp":[
 {"id":"link-1","status":"LINKED","origin":"FUZZY","score":0.9,
  "event":{"id":"e-1","name":"Dirty Pop","startAt":"2025-12-18T04:00:00Z"},
  "item":{"__typename":"Track","id":"t-1","title":"DIRTY POP 12/17/25 LIVE AT THE DALLAS EAGLE",
   "providerUrl":"https://officialdirtypop.podomatic.com/episodes/1","streamUrl":"https://cdn.example/1.mp3",
   "artworkUrl":null,"releasedAt":"2025-12-18T10:02:11Z"}},
 {"id":"link-2","status":"LINKED","origin":"MANUAL","score":null,"event":null,
  "item":{"__typename":"MediaTitle","id":"m-1","filmTitle":"Paris Is Burning","year":1990,
   "filmImdbUrl":"https://www.imdb.com/title/tt0100332/"}},
 {"id":"link-3","status":"LINKED","origin":"MANUAL","score":null,"event":null,
  "item":{"__typename":"Hologram","id":"h-1"}}
]}}}
"""

class RollUpTest {
    @Test
    fun rollUpDecodesEachKindOfItemFlat() = runTest {
        val stub = StubTransport { StubTransport.json(200, ROLL_UP_JSON) }

        val items = rollUpClient(stub).rollUp("venue-1", kinds = listOf(RolledUpItemKind.TRACK))

        assertEquals(listOf("link-1", "link-2", "link-3"), items.map { it.id })
        val episode = items.first()
        assertEquals(RolledUpItemKind.TRACK, episode.kind)
        assertEquals("https://cdn.example/1.mp3", episode.streamUrl)
        assertEquals("https://officialdirtypop.podomatic.com/episodes/1", episode.url)
        assertEquals("Dirty Pop", episode.subtitle)
        assertEquals("2025-12-18T10:02:11Z", episode.publishedAt)
        assertTrue(episode.isMatched)
        assertEquals(0.9, episode.score)
        assertEquals(EntityLinkStatus.LINKED, episode.status)

        val film = items[1]
        assertEquals(RolledUpItemKind.MEDIA_TITLE, film.kind)
        assertEquals("1990", film.subtitle)
        assertEquals("https://www.imdb.com/title/tt0100332/", film.url)
        assertFalse(film.isMatched)
        assertNull(items[2].kind)

        val body = stub.requests.first().jsonBody()
        assertEquals("RollUp", (body["operationName"] as JsonPrimitive).content)
        val variables = body["variables"] as JsonObject
        assertEquals(JsonArray(listOf(JsonPrimitive("TRACK"))), variables["kinds"])
        assertTrue((body["query"] as JsonPrimitive).content.contains("... on Venue { rollUp("))
    }

    @Test
    fun rollUpLeavesOutTypesTheSchemaHasNot() {
        val shape = SchemaShape(
            mapOf("Venue" to setOf("rollUp"), "Event" to setOf("rollUp"), "Track" to setOf("streamUrl")),
        )
        val document = RollUpQueries.rollUp(shape)
        assertTrue(document.contains("... on Event {"))
        assertFalse(document.contains("... on Locale {"))
        assertFalse(document.contains("MediaTitle"))
        assertEquals("query RollUp { id }", RollUpQueries.rollUp(SchemaShape(mapOf("Venue" to setOf("name")))))
    }

    @Test
    fun rollUpFromAnAPIWithoutItIsEmpty() = runTest {
        val stub = StubTransport { StubTransport.json(200, """{"data":{"node":null}}""") }

        assertTrue(rollUpClient(stub).rollUp("venue-1", statuses = listOf(EntityLinkStatus.SUGGESTED)).isEmpty())
    }
}
