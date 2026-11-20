package com.audiencekit

import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

private fun singAlongClient(stub: StubTransport): AudienceKitClient = AudienceKitClient(
    AudienceKitConfiguration(baseUrl = StubTransport.BASE_URL, audienceId = "00000000-0000-4000-8000-000000000760"),
    InMemoryTokenStore("session-token"),
    stub,
)

private const val SING_ALONG_JSON = """
{"data":{"events":{"event":{"id":"e-1",
 "karaoke":{"singAlong":true,"providerName":"Sing-along"},
 "playlist":{"provider":"spotify","shuffle":true,"url":"https://open.spotify.com/playlist/24Kl",
  "uri":"spotify:playlist:24Kl","tracks":[
   {"title":"Defying Gravity","artist":"Idina Menzel, Kristin Chenoweth","durationMs":294000,"uri":"spotify:track:1"},
   {"title":"Burn","artist":"Hamilton Cast","durationMs":225000,"uri":"spotify:track:3"}]},
 "venue":{"venue":{"id":"v-1","name":"The SunTrapp","music":{"nowPlaying":{
   "title":"Defying Gravity","artist":"Idina Menzel","album":null,"artworkUrl":"https://i.scdn.co/a.jpg",
   "reportedAt":"2026-11-20T04:00:00Z","expiresAt":"2026-11-20T04:10:00Z",
   "upNext":[{"title":"Burn","artist":"Hamilton Cast"},{"title":"Seasons of Love","artist":null}]}}}}
}}}}
"""

private val REPORT_TIME: Instant = Instant.parse("2026-11-20T04:05:00Z")

class SingAlongTest {
    @Test
    fun singAlongReadsTheNightItsPlaylistAndRotation() = runTest {
        val stub = StubTransport { StubTransport.json(200, SING_ALONG_JSON) }

        val night = assertNotNull(singAlongClient(stub).singAlong("e-1", REPORT_TIME))

        assertTrue(night.isSingAlong)
        assertEquals("Sing-along", night.providerName)
        assertEquals("v-1", night.venueId)
        assertEquals("The SunTrapp", night.venueName)
        assertEquals(2, night.playlist?.tracks?.size)
        val playing = assertNotNull(night.nowPlaying)
        assertEquals("Defying Gravity", playing.title)
        assertEquals(listOf("Burn", "Seasons of Love"), playing.upNext.map { it.title })

        val body = stub.requests.first().jsonBody()
        assertEquals("SingAlong", (body["operationName"] as JsonPrimitive).content)
        val query = (body["query"] as JsonPrimitive).content
        assertTrue(query.contains("karaoke { singAlong providerName }"))
        assertTrue(query.contains("music { nowPlaying {"))
        assertEquals("e-1", ((body["variables"] as JsonObject)["id"] as JsonPrimitive).content)
    }

    @Test
    fun singAlongDropsAStaleReport() = runTest {
        val stub = StubTransport { StubTransport.json(200, SING_ALONG_JSON) }

        val night = assertNotNull(singAlongClient(stub).singAlong("e-1", Instant.parse("2026-11-20T04:30:00Z")))

        assertNull(night.nowPlaying)
        assertNotNull(night.playlist)
    }

    @Test
    fun singAlongIsNullForAnUnknownEvent() = runTest {
        val stub = StubTransport { StubTransport.json(200, """{"data":{"events":{"event":null}}}""") }
        assertNull(singAlongClient(stub).singAlong("e-9"))
    }

    @Test
    fun nowPlayingRefreshesTheRotation() = runTest {
        val json = """{"data":{"node":{"music":{"nowPlaying":{"title":"Burn","artist":"Hamilton Cast",
            "reportedAt":"2026-11-20T04:04:00Z","expiresAt":"2026-11-20T04:12:00Z","upNext":[]}}}}}"""
        val stub = StubTransport { StubTransport.json(200, json) }

        val playing = assertNotNull(singAlongClient(stub).nowPlaying("v-1", REPORT_TIME))

        assertEquals("Burn", playing.title)
        assertTrue(playing.upNext.isEmpty())
        val query = (stub.requests.first().jsonBody()["query"] as JsonPrimitive).content
        assertTrue(query.contains("... on Venue { music { nowPlaying {"))
    }

    @Test
    fun nowPlayingIsNullWithoutAReport() = runTest {
        val stub = StubTransport { StubTransport.json(200, """{"data":{"node":{"music":{"nowPlaying":null}}}}""") }
        assertNull(singAlongClient(stub).nowPlaying("v-1"))
    }

    @Test
    fun singAlongLeavesOutWhatTheSchemaHasNot() {
        val shape = SchemaShape(mapOf("Event" to setOf("id"), "Venue" to setOf("id")))
        val document = SingAlongQueries.singAlong(shape)
        assertFalse(document.contains("karaoke"))
        assertFalse(document.contains("playlist"))
        assertFalse(document.contains("music"))
        assertTrue(SingAlongQueries.nowPlaying(shape).contains("node(id: \$id) { id }"))
    }

    @Test
    fun singAlongTextFoldsCaseAccentsAndPunctuation() {
        assertEquals("dont rain on my parade", SingAlongText.key("Don’t Rain on My Parade!"))
        assertEquals("cafe society", SingAlongText.key("CAFÉ  Society"))
    }

    @Test
    fun tracksMatchRequestsByTitleAndLooseArtist() {
        val track = SingAlongTrack("Defying Gravity", "Idina Menzel, Kristin Chenoweth", uri = "t:1")
        assertTrue(track.matches("defying gravity", "Idina Menzel"))
        assertTrue(track.matches("Defying Gravity", null))
        assertFalse(track.matches("Defying Gravity", "Cher"))
        assertFalse(track.matches("Gravity", "Idina Menzel"))
        assertTrue(track.matches("idina grav"))
        assertFalse(track.matches("streisand"))
        assertTrue(track.matches("  "))
        assertTrue(SingAlongTrack("Burn", null, uri = "t:3").matches("Burn", "Anyone"))
    }

    @Test
    fun pickerSortsAndBadgesTracks() {
        val tracks = listOf(
            SingAlongTrack("Defying Gravity", "Idina Menzel", uri = "t:1"),
            SingAlongTrack("Don't Rain on My Parade", "Barbra Streisand", uri = "t:2"),
            SingAlongTrack("Burn", "Hamilton Cast", uri = "t:3"),
            SingAlongTrack("Seasons of Love", "Rent Cast", uri = "t:4"),
            SingAlongTrack("cabaret", "Liza Minnelli", uri = "t:5"),
        )
        val night = SingAlongNight(
            eventId = "e-1",
            isSingAlong = true,
            playlist = SingAlongPlaylist(url = "https://open.spotify.com/playlist/1", tracks = tracks),
            nowPlaying = NowPlaying("Defying Gravity", "Idina Menzel", upNext = listOf(UpNextSong("Burn"))),
        )
        val asks = listOf(SingAlongAsk("Seasons of Love", "Rent Cast", mine = true), SingAlongAsk("Cabaret"))

        assertEquals(
            listOf("Burn", "cabaret", "Defying Gravity", "Don't Rain on My Parade", "Seasons of Love"),
            night.pickableTracks().map { it.title },
        )
        assertEquals(listOf("t:4"), night.pickableTracks("love").map { it.uri })
        assertEquals(SingAlongTrackStatus.PLAYING_NOW, night.status(tracks[0], asks))
        assertEquals(SingAlongTrackStatus.UP_NEXT, night.status(tracks[2], asks))
        assertEquals(SingAlongTrackStatus.REQUESTED, night.status(tracks[3], asks))
        assertEquals(SingAlongTrackStatus.IN_QUEUE, night.status(tracks[4], asks))
        assertNull(night.status(tracks[1], asks))
        assertNull(night.status(tracks[4]))
        assertEquals("t:3", night.playlist?.track("burn", null)?.uri)
        assertNull(night.copy(nowPlaying = null).status(tracks[0]))
        assertTrue(SingAlongNight("e-2", isSingAlong = false).pickableTracks().isEmpty())
    }

    @Test
    fun nowPlayingFreshness() {
        val playing = NowPlaying("Burn", expiresAt = "2026-11-20T04:06:00Z")
        assertTrue(playing.isFresh(REPORT_TIME))
        assertFalse(playing.isFresh(Instant.parse("2026-11-20T04:07:00Z")))
        assertTrue(NowPlaying("x").isFresh())
        assertTrue(NowPlaying("x", expiresAt = "not a date").isFresh())
    }
}
