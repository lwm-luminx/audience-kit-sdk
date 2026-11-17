package com.audiencekit

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class ListingResearchTest {
    private val node = """
        {"id":"lr-1","state":"DONE","kind":"VENUE","query":"nyne spokane","found":true,"name":"Nyne",
         "summary":"A bar downtown.","description":"Nyne is a bar.","website":"https://nynebar.com","city":"Spokane",
         "address":"232 W Sprague Ave","phone":"(509) 474-1621","googlePlaceId":"ChIJ-nyne","personKind":null,
         "homeVenueName":null,"homeVenue":null,"locale":{"id":"loc-1"},
         "links":[{"provider":"instagram","handle":"nynebar","url":"https://instagram.com/nynebar"}],
         "evidence":[{"url":"https://nynebar.com","title":"Nyne"}],"matches":[{"id":"v-1","name":"Nyne"}],"error":null}
    """

    @Test fun decodesADraft() {
        val data = Json.parseToJsonElement("""{"listingResearch":$node}""").jsonObject
        val draft = ListingResearch.parseRead(data)!!
        assertTrue(draft.state.isFinished)
        assertEquals(ListingResearchKind.VENUE, draft.kind)
        assertEquals("ChIJ-nyne", draft.googlePlaceId)
        assertEquals("https://instagram.com/nynebar", draft.link("instagram"))
        assertEquals("", draft.link("tiktok"))
        assertEquals(listOf("Nyne"), draft.matches.map { it.name })
        assertEquals(JsonArray(listOf(JsonObject(mapOf("provider" to JsonPrimitive("instagram"), "handle" to JsonPrimitive("nynebar"))))),
            draft.socialLinks)
    }

    @Test fun someoneElsesIsNull() {
        assertNull(ListingResearch.parseRead(Json.parseToJsonElement("""{"listingResearch":null}""").jsonObject))
    }

    @Test fun startsWithWhatTheyTyped() {
        assertEquals(
            mapOf("input" to JsonObject(mapOf("kind" to JsonPrimitive("PERSON"), "query" to JsonPrimitive("Spokane Pride"),
                "localeId" to JsonPrimitive("loc-1")))),
            ListingResearch.startVariables(ListingResearchKind.PERSON, " Spokane Pride ", "loc-1"))
        assertTrue(ListingResearch.START_MUTATION.contains("researchListing(input: \$input)"))
        assertTrue(ListingResearch.QUERY.contains(ListingResearch.LISTING_RESEARCH_FIELDS))
        assertFalse(ListingResearchState.RUNNING.isFinished)
    }
}
