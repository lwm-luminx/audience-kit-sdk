package com.audiencekit

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

// Roll-ups (API doc/ROLL_UP.md): items linked to what they are about, shown on that record and everything above it. A
// podcast episode recorded live at a party is linked to that night's event, so it shows on the event and among the
// hosting venue's items; the same goes for a venue's series, a locale's venues and the people billed on an event.
// Links come from fuzzy matching (episode text against venue names and event dates) or from an admin. An API without
// roll-ups returns no items. The same as the Swift SDK's RollUp.swift.

/** What kind of item is linked. */
public enum class RolledUpItemKind(internal val typename: String) {
    /** A podcast episode or music track. */
    TRACK("Track"),

    /** A film or television title. */
    MEDIA_TITLE("MediaTitle"),

    /** An episode of a series. */
    MEDIA_EPISODE("MediaEpisode"),
    ARTICLE("Article"),
    PERSON("Person"),
    ;

    internal companion object {
        fun of(typename: String?): RolledUpItemKind? = entries.firstOrNull { it.typename == typename }
    }
}

/** Where a link stands. Everyone sees [LINKED] items; admins may also ask for the others. */
public enum class EntityLinkStatus {
    LINKED,

    /** Found by matching, but not sure enough to show until an admin confirms it. */
    SUGGESTED,

    /** Turned down: never shown, never suggested again. */
    REJECTED,
}

/** The event an item was linked to: the night an episode was recorded, say. [startAt] is ISO 8601. */
@Serializable
public data class RolledUpEvent(val id: String, val name: String? = null, val startAt: String? = null)

/**
 * One item linked to a record or to something under it ([rollUp]), flattened for a list row: a title, a line under
 * it, a link out and, for an episode, its audio. [id] is the link's; [publishedAt] is ISO 8601.
 */
public data class RolledUpItem(
    val id: String,
    /** Null for a kind this SDK doesn't know yet. */
    val kind: RolledUpItemKind?,
    val itemId: String,
    val title: String? = null,
    /** An episode's event, a film's year, a series episode's code. */
    val subtitle: String? = null,
    /** Where to open it: the episode on its podcast host, the film on IMDb, the article's page. */
    val url: String? = null,
    val artworkUrl: String? = null,
    /** An episode's or track's audio. */
    val streamUrl: String? = null,
    val publishedAt: String? = null,
    val event: RolledUpEvent? = null,
    val status: EntityLinkStatus? = EntityLinkStatus.LINKED,
    /** Whether matching found it (an admin made the others). */
    val isMatched: Boolean = false,
    /** How sure matching is, 0 to 1; null for links people made. */
    val score: Double? = null,
)

/**
 * Items linked to a venue, event, event series, person or locale, or to anything under it, newest first: a venue's
 * include those linked to its events, so a podcast episode recorded live at a party shows among the venue's items.
 * Empty from an API without roll-ups. Only admins get anything but linked items.
 */
public suspend fun AudienceKitClient.rollUp(
    id: String,
    kinds: List<RolledUpItemKind>? = null,
    limit: Int = 50,
    statuses: List<EntityLinkStatus>? = null,
): List<RolledUpItem> = graphQL(
    RollUpQueries.TYPES,
    RollUpResponse.serializer(),
    graphQLVariables(
        "id" to id, "kinds" to kinds?.map { it.name }, "limit" to limit, "statuses" to statuses?.map { it.name },
    ),
    "RollUp",
    RollUpQueries::rollUp,
).items

internal object RollUpQueries {
    /** The record types `rollUp` is on, and the item types its rows read (each module's, when the audience has it). */
    val TYPES: List<String> = listOf(
        "Venue", "Event", "EventSeries", "Person", "Locale", "EntityLink", "Track", "MediaTitle", "MediaEpisode",
        "Article",
    )

    private val RECORDS = listOf("Venue", "Event", "EventSeries", "Person", "Locale")

    /** Each kind of item a row reads, if the schema has it: an audience without the media module has no MediaTitle. */
    private val ITEM_FRAGMENTS = listOf(
        Triple("Track", "streamUrl", "id title providerUrl streamUrl artworkUrl releasedAt"),
        // Titles and IMDb links differ in nullability between types, so all but the track's are aliased.
        Triple("MediaTitle", "imdbUrl", "id filmTitle: title year filmImdbUrl: imdbUrl"),
        Triple("MediaEpisode", "code", "id episodeTitle: title code episodeImdbUrl: imdbUrl"),
        Triple("Article", "canonicalUrl", "id articleTitle: title canonicalUrl heroPhotoUrl publishedAt"),
        Triple("Person", "avatarUrl", "id name avatarUrl"),
    )

    fun itemFields(shape: SchemaShape): String {
        val fragments = ITEM_FRAGMENTS.filter { (type, check) -> shape.has(type, check) }
            .joinToString(" ") { (type, _, fields) -> "... on $type { $fields }" }
        return "id status origin score event { id name startAt } item { __typename $fragments }"
    }

    fun rollUp(shape: SchemaShape): String {
        if (!shape.has("Venue", "rollUp")) return "query RollUp { id }"
        val arguments = "itemKinds: ${'$'}kinds, limit: ${'$'}limit, statuses: ${'$'}statuses"
        val field = "rollUp($arguments) { ${itemFields(shape)} }"
        val records = RECORDS.filter { shape.has(it, "rollUp") }.joinToString(" ") { "... on $it { $field }" }
        return """
            query RollUp(
              ${'$'}id: ID!, ${'$'}kinds: [EntityLinkItemKind!], ${'$'}limit: Int, ${'$'}statuses: [EntityLinkStatus!]
            ) {
              node(id: ${'$'}id) { $records }
            }
        """.trimIndent()
    }
}

@Serializable
internal data class RollUpResponse(val node: Holder? = null) {
    @Serializable
    data class Holder(val rollUp: List<Link?>? = null)

    @Serializable
    data class Item(
        @SerialName("__typename") val typename: String? = null,
        val id: String,
        val title: String? = null,
        val filmTitle: String? = null,
        val episodeTitle: String? = null,
        val articleTitle: String? = null,
        val name: String? = null,
        val providerUrl: String? = null,
        val streamUrl: String? = null,
        val artworkUrl: String? = null,
        val releasedAt: String? = null,
        val filmImdbUrl: String? = null,
        val episodeImdbUrl: String? = null,
        val year: Int? = null,
        val code: String? = null,
        val canonicalUrl: String? = null,
        val heroPhotoUrl: String? = null,
        val publishedAt: String? = null,
        val avatarUrl: String? = null,
    )

    @Serializable
    data class Link(
        val id: String,
        val item: Item,
        val event: RolledUpEvent? = null,
        val status: String? = null,
        val origin: String? = null,
        val score: Double? = null,
    ) {
        fun toItem(): RolledUpItem = RolledUpItem(
            id = id,
            kind = RolledUpItemKind.of(item.typename),
            itemId = item.id,
            title = item.title ?: item.filmTitle ?: item.episodeTitle ?: item.articleTitle ?: item.name,
            subtitle = item.code ?: item.year?.toString() ?: event?.name,
            url = item.providerUrl ?: item.filmImdbUrl ?: item.episodeImdbUrl ?: item.canonicalUrl,
            artworkUrl = item.artworkUrl ?: item.heroPhotoUrl ?: item.avatarUrl,
            streamUrl = item.streamUrl,
            publishedAt = item.releasedAt ?: item.publishedAt,
            event = event,
            status = EntityLinkStatus.entries.firstOrNull { it.name == status },
            isMatched = origin == "FUZZY",
            score = score,
        )
    }

    val items: List<RolledUpItem> get() = node?.rollUp.orEmpty().filterNotNull().map { it.toItem() }
}
