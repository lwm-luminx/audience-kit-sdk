package com.audiencekit

import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

private fun bridgeClient(stub: StubTransport): AudienceKitClient = AudienceKitClient(
    AudienceKitConfiguration(baseUrl = StubTransport.BASE_URL, audienceId = "00000000-0000-4000-8000-000000000838"),
    InMemoryTokenStore("session-token"),
    stub,
)

private const val UNDEFINED = """{"errors":[{"message":"Field doesn't exist","extensions":{"code":"undefinedField"}}]}"""

class SpotifyBridgeTest {
    @Test
    fun findsTheSpotifyLinkInSharedText() {
        assertEquals(
            "https://open.spotify.com/track/0GjEhVFGZW8afUYGChu3Rr?si=a",
            SpotifyLink.firstLink("Listen on Spotify: https://open.spotify.com/track/0GjEhVFGZW8afUYGChu3Rr?si=a"),
        )
        assertEquals("spotify:album:4aawyAB9vmqN3uQ7FjRGTy", SpotifyLink.firstLink("spotify:album:4aawyAB9vmqN3uQ7FjRGTy"))
        assertNull(SpotifyLink.firstLink("https://example.com/track/1"))
    }

    @Test
    fun readsALink() = runTest {
        val stub = StubTransport {
            StubTransport.json(
                200,
                """{"data":{"spotifyLink":{"kind":"track","id":"abc","title":"Dancing Queen","artist":"ABBA",
                "thumbnailUrl":null,"uri":"spotify:track:abc","url":"https://open.spotify.com/track/abc",
                "embedUrl":"https://open.spotify.com/embed/track/abc"}}}""",
            )
        }
        val link = assertNotNull(bridgeClient(stub).spotifyLink("https://spotify.link/AbCd"))
        assertTrue(link.isSong)
        assertEquals("ABBA", link.artist)
        val body = stub.requests.first().jsonBody()
        assertEquals("SpotifyLink", (body["operationName"] as JsonPrimitive).content)
        assertEquals("https://spotify.link/AbCd", ((body["variables"] as JsonObject)["url"] as JsonPrimitive).content)
    }

    @Test
    fun readsNothingFromAnOlderAPIButPassesOtherErrors() = runTest {
        val client = bridgeClient(StubTransport { StubTransport.json(200, UNDEFINED) })
        assertNull(client.spotifyLink("https://open.spotify.com/track/x"))
        assertNull(client.setList("e-1"))
        val failing = bridgeClient(
            StubTransport { StubTransport.json(200, """{"errors":[{"message":"no","extensions":{"code":"INVALID"}}]}""") },
        )
        assertFailsWith<AudienceKitException.GraphQL> { failing.spotifyLink("x") }
        assertFailsWith<AudienceKitException.GraphQL> { failing.setList("e-1") }
    }

    @Test
    fun asksForASharedSong() = runTest {
        val stub = StubTransport {
            StubTransport.json(
                200,
                """{"data":{"requestSong":{"request":{"id":"q-1","title":"Dancing Queen","artist":"ABBA",
                "summary":"Dancing Queen by ABBA","state":"QUEUED","position":0,"spotifyUri":"spotify:track:abc"}}}}""",
            )
        }
        val asked = bridgeClient(stub).requestSong("v-1", spotifyUrl = "https://open.spotify.com/track/abc", note = "For Bo")
        assertEquals("Dancing Queen by ABBA", asked.summary)
        val variables = stub.requests.first().jsonBody()["variables"] as JsonObject
        assertEquals(setOf("venueId", "spotifyUrl", "note"), variables.keys)
    }

    @Test
    fun readsASetList() = runTest {
        val stub = StubTransport {
            StubTransport.json(
                200,
                """{"data":{"events":{"event":{"id":"e-1","setList":{"spotifyUri":"spotify:playlist:pl1",
                "spotifyUrl":"https://open.spotify.com/playlist/pl1","songCount":12,"syncedAt":"2026-11-21T21:00:00Z"}}}}}""",
            )
        }
        val list = assertNotNull(bridgeClient(stub).setList("e-1"))
        assertEquals(12, list.songCount)
        assertEquals("spotify:playlist:pl1", list.spotifyUri)
    }
}
