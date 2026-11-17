package com.audiencekit

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class ListingCurationTest {
    private fun data(json: String): JsonObject = Json.parseToJsonElement(json).jsonObject

    @Test
    fun deletingAVenueSendsItsId() {
        assertTrue(ListingCuration.DELETE_MUTATION.contains("deleteVenue(input: { id: \$id }) { deletedId }"))
        assertEquals(mapOf("id" to JsonPrimitive("v-1")), ListingCuration.deleteVariables("v-1"))
        assertEquals("v-1", ListingCuration.parseDelete(data("""{"deleteVenue":{"deletedId":"v-1"}}""")))
        assertNull(ListingCuration.parseDelete(data("""{"deleteVenue":null}""")))
        assertTrue(ListingCuration.DELETE_PERSON_MUTATION.contains("deletePerson(input: { id: \$id }) { deletedId }"))
        assertEquals("p-1", ListingCuration.parseDelete(data("""{"deletePerson":{"deletedId":"p-1"}}""")))
    }

    @Test
    fun aMergeSendsTheFieldsToTakeInTheSchemasOrder() {
        val variables = ListingCuration.mergeVariables("a", "b", listOf(VenueMergeField.WEBSITE, VenueMergeField.NAME))
        assertEquals(JsonArray(listOf(JsonPrimitive("NAME"), JsonPrimitive("WEBSITE"))), variables["takeFromSource"])
        assertEquals(JsonPrimitive("a"), variables["sourceId"])
        assertEquals(JsonArray(emptyList()), ListingCuration.mergeVariables("a", "b")["takeFromSource"])

        val result = ListingCuration.parseMerge(data("""
            {"mergeVenue":{"deletedId":"a","venue":{"id":"b","name":"The Edge"},
             "moved":[{"kind":"events","count":3},{"kind":"taggings","count":2}]}}
        """.trimIndent()))!!
        assertEquals("a", result.deletedId)
        assertEquals(VenueDuplicate.Venue("b", "The Edge"), result.venue)
        assertEquals(5, result.movedCount)
        assertNull(ListingCuration.parseMerge(data("""{"mergeVenue":null}""")))
    }

    @Test
    fun duplicatesReadWithTheirReasons() {
        val pair = ListingCuration.parseDuplicates(data("""
            {"venues":{"duplicates":[{"distance":40,"reasons":["SAME_PLACE","SOMETHING_NEW"],
             "keep":{"id":"k","name":"The Edge"},"merge":{"id":"m","name":"Edge NYC"}}]}}
        """.trimIndent())).single()
        assertEquals("k:m", pair.id)
        assertEquals(listOf(VenueDuplicateReason.SAME_PLACE, VenueDuplicateReason.UNKNOWN), pair.reasons)
        assertEquals("Same Google place · Looks alike · 40 m apart", pair.reasonLine)
        assertTrue(ListingCuration.parseDuplicates(data("""{"venues":{"duplicates":null}}""")).isEmpty())

        assertEquals(
            JsonObject(mapOf("venueIds" to JsonArray(listOf(JsonPrimitive("k"), JsonPrimitive("m"))))),
            ListingCuration.dismissVariables(pair, "  ")["input"],
        )
        assertEquals(JsonPrimitive("Two floors"), (ListingCuration.dismissVariables(pair, " Two floors ")["input"] as JsonObject)["note"])
    }

    @Test
    fun theCopyNamesTheVenues() {
        assertEquals("Delete The Edge?", ListingCurationCopy.deleteTitle("The Edge"))
        assertTrue(ListingCurationCopy.deleteDetail("The Edge").startsWith("The Edge and all of its events will be deleted."))
        assertEquals("Merge Edge NYC into The Edge?", ListingCurationCopy.mergeTitle("Edge NYC", "The Edge"))
        assertEquals("A is merged into B.", ListingCurationCopy.merged("A", "B"))
        assertEquals("A is deleted.", ListingCurationCopy.deleted("A"))
        assertEquals(listOf("Name", "Description", "Website", "Photo", "Location", "Locale"), VenueMergeField.OFFERED.map { it.title })
    }
}
