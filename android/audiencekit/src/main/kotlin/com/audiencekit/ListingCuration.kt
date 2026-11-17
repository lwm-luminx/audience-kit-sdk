package com.audiencekit

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull

/**
 * A detail of a venue that a merge can take from the duplicate instead of the venue kept: the API's `VenueMergeField`
 * (`mergeVenue(takeFromSource:)`). Details not taken stay the kept venue's, filled from the duplicate where the kept
 * venue has none. The same as the Swift SDK's.
 */
public enum class VenueMergeField(
    /** A row's label in the merge form. */
    public val title: String,
) {
    NAME("Name"),
    DESCRIPTION("Description"),
    WEBSITE("Website"),
    PHONE("Phone"),
    PHOTO("Photo"),
    PLACE("Location"),
    LOCALE("Locale"),
    FACEBOOK_PAGE("Facebook Page"),
    HIDDEN("Hidden"),
    VISIBILITY("Visibility"),
    ;

    public companion object {
        /** The choices a phone's merge form offers, in its order; the rest stay the kept venue's. */
        public val OFFERED: List<VenueMergeField> = listOf(NAME, DESCRIPTION, WEBSITE, PHOTO, PLACE, LOCALE)
    }
}

/** Why the API thinks two venues are the same place: `VenueDuplicateReason`. */
public enum class VenueDuplicateReason(
    /** In words, for the pair's subtitle. */
    public val title: String,
) {
    SAME_PLACE("Same Google place"),
    SAME_NAME("Same name in the same locale"),
    NEARBY_SIMILAR_NAME("Close by with a similar name"),
    /** A reason this SDK doesn't know yet. */
    UNKNOWN("Looks alike"),
    ;

    public companion object {
        public fun from(value: String?): VenueDuplicateReason = entries.firstOrNull { it.name == value } ?: UNKNOWN
    }
}

/**
 * Two venues the API thinks are one place (`venues { duplicates }` on the staff endpoint, administrators only): the
 * one it suggests keeping and the one to merge into it.
 */
public data class VenueDuplicate(
    /** On Google, with more events, or older. */
    val keep: Venue,
    val merge: Venue,
    val reasons: List<VenueDuplicateReason>,
    /** Meters apart; null when either has no location. */
    val distance: Int? = null,
) {
    public data class Venue(val id: String, val name: String?)

    public val id: String get() = keep.id + ":" + merge.id

    /** "Same Google place · 40 m apart". */
    public val reasonLine: String
        get() = (reasons.map { it.title } + listOfNotNull(distance?.let { "$it m apart" })).joinToString(" · ")
}

/** How many records of a kind moved in a merge (`VenueMergeCount`). */
public data class VenueMergeCount(val kind: String, val count: Int)

/** [ListingCuration.MERGE_MUTATION]'s answer. */
public data class VenueMergeResult(val deletedId: String, val venue: VenueDuplicate.Venue, val moved: List<VenueMergeCount>) {
    /** How many records moved to the kept venue. */
    public val movedCount: Int get() = moved.sumOf { it.count }
}

/**
 * The GraphQL for deleting an audience's venues and people and merging its venues from a staff app (Focus), shared so no app writes its own,
 * and the same as the Swift SDK's. They run on the staff endpoint, which this SDK doesn't call: StaffKit's session
 * sends them with these variables, and the `parse` functions read the answers. The API decides who may: each needs
 * `venues:write:*`.
 */
public object ListingCuration {
    public const val DELETE_MUTATION: String = """
        # endpoint: staff
        mutation FocusDeleteVenue(${'$'}id: ID!) { deleteVenue(input: { id: ${'$'}id }) { deletedId } }
    """

    /** Removes a person (a performer's listing) from the audience; needs `people:write:*`. Read with [parseDelete]. */
    public const val DELETE_PERSON_MUTATION: String = """
        # endpoint: staff
        mutation FocusDeletePerson(${'$'}id: ID!) { deletePerson(input: { id: ${'$'}id }) { deletedId } }
    """

    public const val MERGE_MUTATION: String = """
        # endpoint: staff
        mutation FocusMergeVenue(${'$'}sourceId: ID!, ${'$'}destinationId: ID!, ${'$'}takeFromSource: [VenueMergeField!]) {
          mergeVenue(input: { sourceId: ${'$'}sourceId, destinationId: ${'$'}destinationId, takeFromSource: ${'$'}takeFromSource }) {
            deletedId venue { id name } moved { kind count }
          }
        }
    """

    public const val DUPLICATES_QUERY: String = """
        # endpoint: staff
        query FocusVenueDuplicates { venues { duplicates { distance reasons keep { id name } merge { id name } } } }
    """

    public const val DISMISS_DUPLICATE_MUTATION: String = """
        # endpoint: staff
        mutation FocusDismissVenueDuplicate(${'$'}input: VenueDuplicateDismissInput!) {
          dismissVenueDuplicate(input: ${'$'}input) { clientMutationId }
        }
    """

    /** The variables for [DELETE_MUTATION] and [DELETE_PERSON_MUTATION]. */
    public fun deleteVariables(id: String): Map<String, JsonElement> = mapOf("id" to JsonPrimitive(id))

    /** The variables for [MERGE_MUTATION]: [sourceId] is merged into [destinationId] and deleted. */
    public fun mergeVariables(
        sourceId: String,
        destinationId: String,
        takeFromSource: Collection<VenueMergeField> = emptyList(),
    ): Map<String, JsonElement> = mapOf(
        "sourceId" to JsonPrimitive(sourceId),
        "destinationId" to JsonPrimitive(destinationId),
        "takeFromSource" to JsonArray(VenueMergeField.entries.filter { it in takeFromSource }.map { JsonPrimitive(it.name) }),
    )

    /** The variables for [DISMISS_DUPLICATE_MUTATION]: the pair isn't one place. */
    public fun dismissVariables(duplicate: VenueDuplicate, note: String? = null): Map<String, JsonElement> = mapOf(
        "input" to JsonObject(
            buildMap {
                put("venueIds", JsonArray(listOf(JsonPrimitive(duplicate.keep.id), JsonPrimitive(duplicate.merge.id))))
                note?.trim()?.takeIf { it.isNotEmpty() }?.let { put("note", JsonPrimitive(it)) }
            },
        ),
    )

    /** [DELETE_MUTATION]'s or [DELETE_PERSON_MUTATION]'s `data`: the deleted record's ID. */
    public fun parseDelete(data: JsonObject): String? =
        ((data["deleteVenue"] ?: data["deletePerson"]) as? JsonObject)?.string("deletedId")

    /** [MERGE_MUTATION]'s `data`. */
    public fun parseMerge(data: JsonObject): VenueMergeResult? {
        val payload = data["mergeVenue"] as? JsonObject ?: return null
        val venue = payload["venue"] as? JsonObject ?: return null
        val deleted = payload.string("deletedId") ?: return null
        val moved = (payload["moved"] as? JsonArray).orEmpty().mapNotNull { row ->
            val obj = row as? JsonObject ?: return@mapNotNull null
            VenueMergeCount(obj.string("kind") ?: return@mapNotNull null, (obj["count"] as? JsonPrimitive)?.intOrNull ?: 0)
        }
        return VenueMergeResult(deleted, venue(venue) ?: return null, moved)
    }

    /** [DUPLICATES_QUERY]'s `data`; empty for someone who isn't allowed to see them. */
    public fun parseDuplicates(data: JsonObject): List<VenueDuplicate> {
        val rows = (data["venues"] as? JsonObject)?.get("duplicates") as? JsonArray ?: return emptyList()
        return rows.mapNotNull { row ->
            val obj = row as? JsonObject ?: return@mapNotNull null
            VenueDuplicate(
                keep = venue(obj["keep"] as? JsonObject) ?: return@mapNotNull null,
                merge = venue(obj["merge"] as? JsonObject) ?: return@mapNotNull null,
                reasons = (obj["reasons"] as? JsonArray).orEmpty().map { VenueDuplicateReason.from((it as? JsonPrimitive)?.contentOrNull) },
                distance = (obj["distance"] as? JsonPrimitive)?.intOrNull,
            )
        }
    }

    private fun venue(obj: JsonObject?): VenueDuplicate.Venue? =
        obj?.string("id")?.let { VenueDuplicate.Venue(it, obj.string("name")) }

    private fun JsonObject.string(key: String): String? =
        (this[key] as? JsonPrimitive)?.takeIf { it.isString }?.content
}

/** The words around deleting venues and people and merging venues, the same as the Swift SDK's and the web console's. */
public object ListingCurationCopy {
    public const val DELETE: String = "Delete venue"
    public const val DELETE_PERSON: String = "Delete person"
    public const val DELETE_CONFIRM: String = "Delete"
    public const val MERGE: String = "Merge with another venue"
    public const val MERGE_CONFIRM: String = "Merge venues"
    public const val MERGE_WITH: String = "Merge with"
    public const val KEEP: String = "Keep"
    public const val MERGE_AWAY: String = "Merge away"
    public const val SWAP: String = "Swap"
    public const val TAKE_FROM_OTHER: String = "Use the merged venue's"
    public const val MERGE_DETAIL: String = "Events, series, lineups, chat and rooms, posts, tags, staff and access " +
        "move to the venue kept. What both have once, like a cover night or a back-of-house room, is combined. The " +
        "venue merged away is deleted."
    public const val DUPLICATES: String = "Possible duplicates"
    public const val NOT_DUPLICATE: String = "Not a duplicate"
    public const val NO_DUPLICATES: String = "No likely duplicates."

    /** The delete confirmation's title. */
    public fun deleteTitle(name: String): String = "Delete $name?"

    /** The delete confirmation's message. */
    public fun deleteDetail(name: String): String =
        "$name and all of its events will be deleted. To keep them, hide the venue instead. This cannot be undone."

    /** The person delete confirmation's message. */
    public fun deletePersonDetail(name: String): String =
        "$name will be removed from the audience. This cannot be undone."

    /** The merge confirmation's title. */
    public fun mergeTitle(from: String, into: String): String = "Merge $from into $into?"

    /** After a delete. */
    public fun deleted(name: String): String = "$name is deleted."

    /** After a merge. */
    public fun merged(from: String, into: String): String = "$from is merged into $into."
}
