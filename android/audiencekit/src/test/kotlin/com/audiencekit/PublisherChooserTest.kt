package com.audiencekit

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

private const val PUBLISHERS_JSON = """
{"soapbox":{"myPublications":[
 {"id":"p-q","name":"QSaltLake","masthead":null,"trust":"TRUSTED","person":{"id":"x-q","name":"QSaltLake"},
  "locale":{"id":"l-slc","name":"Salt Lake City","ancestors":[{"id":"l-us","name":"United States"},{"id":"l-ut","name":"Utah"}],
  "location":{"point":"POINT (-111.891 40.7608)"}}},
 {"id":"p-o","name":"Ogden Outlook","masthead":"Ogden Outlook","trust":"PENDING","person":{"id":"x-o","name":"Weber Media"},
  "locale":{"id":"l-ogden","name":"Ogden","ancestors":[{"id":"l-us","name":"United States"},{"id":"l-ut","name":"Utah"}],
  "location":{"point":"POINT (-111.9738 41.223)"}}},
 {"id":"p-a","name":"The Advocate","masthead":null,"trust":"TRUSTED","person":null,"locale":null},
 {"id":"p-b","name":"Bay Area Reporter","masthead":null,"trust":"SUSPENDED","person":{"id":"x-b","name":""},
  "locale":{"id":"l-sf","name":"San Francisco","ancestors":[],"location":{"point":"POINT (-122.4194 37.7749)"}}},
 {"id":"p-e","name":"Équipe Québec","masthead":null,"trust":null,"person":null,
  "locale":{"id":"l-mtl","name":"Montréal","ancestors":null,"location":null}},
 {"id":null,"name":"No ID"}
]}}
"""

private fun directory(): PublisherDirectory =
    PublisherChooserDocuments.parsePublishers(Json.parseToJsonElement(PUBLISHERS_JSON).jsonObject)

class PublisherChooserTest {
    @Test
    fun publishersParseWithThePlaceTheyCover() {
        assertTrue(PublisherChooserDocuments.PUBLISHERS_QUERY.trimStart().startsWith("# endpoint: staff"))
        assertTrue(PublisherChooserDocuments.LOCALES_AT_QUERY.contains("locales(at: \$here)"))
        val directory = directory()
        assertEquals(listOf("Bay Area Reporter", "Équipe Québec", "Ogden Outlook", "QSaltLake", "The Advocate"), directory.entries.map { it.name })

        val q = directory.entry("p-q")!!
        assertEquals("Salt Lake City, Utah", q.place)
        assertEquals(listOf("Utah", "United States"), q.localeAncestors)
        assertNull(q.personName)
        assertEquals(Coordinate(40.7608, -111.891), q.coordinate)
        assertFalse(q.isPending || q.isSuspended)
        assertEquals("Weber Media", directory.entry("p-o")!!.personName)
        assertTrue(directory.entry("p-o")!!.isPending)
        assertTrue(directory.entry("p-b")!!.isSuspended)
        assertNull(directory.entry("p-b")!!.personName)
        assertEquals("San Francisco", directory.entry("p-b")!!.place)
        assertNull(directory.entry("p-a")!!.place)
        assertNull(directory.entry("p-e")!!.coordinate)
        assertEquals(listOf("p-a", "p-q"), directory.entries(listOf("p-a", "gone", "p-q")).map { it.id })
        assertEquals(0, PublisherChooserDocuments.parsePublishers(JsonObject(emptyMap())).entries.size)
    }

    @Test
    fun searchRanksNamesThenPeopleThenPlaces() {
        val directory = directory()
        assertEquals(5, directory.search("  ").size)
        assertEquals(listOf("p-q"), directory.search("qsaltlake").map { it.id })
        assertEquals("p-a", directory.search("the").first().id)
        assertEquals(listOf("p-a"), directory.search("advocate").map { it.id })
        assertEquals(listOf("p-b"), directory.search("reporte").map { it.id })
        assertEquals(listOf("p-o"), directory.search("weber").map { it.id })
        assertEquals(listOf("p-q"), directory.search("salt lake city").map { it.id })
        assertEquals(listOf("p-o", "p-q"), directory.search("utah").map { it.id })
        assertEquals(listOf("p-e"), directory.search("equipe").map { it.id })
        assertEquals(listOf("p-e"), directory.search("montreal").map { it.id })
        assertEquals(listOf("p-q"), directory.search("lake").map { it.id })
        assertTrue(directory.search("nowhere").isEmpty())
    }

    @Test
    fun nearbyPutsTheLocalesYoureInFirstThenTheClosest() {
        val directory = directory()
        val downtown = Coordinate(40.76, -111.89)
        val near = directory.nearby(downtown, containing = listOf("l-us", "l-ut", "l-slc"))
        assertEquals(listOf("p-q", "p-o"), near.map { it.publisher.id })
        assertTrue(near[0].inside)
        assertFalse(near[1].inside)
        assertTrue((near[1].distance ?: 0.0) in 50_000.0..60_000.0)
        assertEquals(listOf("p-q", "p-o"), directory.nearby(downtown).map { it.publisher.id })
        assertEquals(listOf("p-q"), directory.nearby(downtown, radius = 10_000.0).map { it.publisher.id })
        assertEquals(listOf("p-q"), directory.nearby(downtown, limit = 1).map { it.publisher.id })
        val montreal = directory.nearby(Coordinate(45.5, -73.57), containing = listOf("l-mtl"))
        assertEquals(listOf("p-e"), montreal.map { it.publisher.id })
        assertNull(montreal[0].distance)
        assertEquals(0.0, PublisherDirectory.distance(downtown, downtown))
    }

    @Test
    fun recentsKeepTheLastSixNewestFirst() {
        var list = emptyList<String>()
        for (id in listOf("a", "b", "c", "d", "e", "f", "g")) list = PublisherRecents.adding(id, list)
        assertEquals(listOf("g", "f", "e", "d", "c", "b"), list)
        assertEquals(listOf("d", "g", "f", "e", "c", "b"), PublisherRecents.adding("d", list))
        assertEquals(list, PublisherRecents.adding("", list))
        assertEquals("AudienceKit.recentPublishers.aud-1", PublisherRecents.key("aud-1"))
    }

    @Test
    fun localesAtParsesOutermostFirst() {
        val data = Json.parseToJsonElement("""{"locales":[{"id":"l-us"},{"id":"l-ut"},{}]}""").jsonObject
        assertEquals(listOf("l-us", "l-ut"), PublisherChooserDocuments.parseLocalesAt(data))
    }
}
