package com.audiencekit

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/** What Add with AI fills out: the API's `ListingResearchKind`. The same as the Swift SDK's. */
@Serializable
public enum class ListingResearchKind { PERSON, VENUE }

/** Where an Add with AI request is: the API's `ListingResearchState`. */
@Serializable
public enum class ListingResearchState {
    PENDING, RUNNING, DONE, FAILED;

    /** Whether to stop asking: the draft is ready or it failed. */
    public val isFinished: Boolean get() = this == DONE || this == FAILED
}

/**
 * An Add with AI request and, once [ListingResearchState.DONE], the draft the audience's AI provider filled out
 * (`Audience.listingResearch` on the staff endpoint). Nothing is saved from it: the app opens its editor prefilled
 * with it, and the curator saves with createPerson or createVenue.
 */
@Serializable
public data class ListingResearchDraft(
    val id: String,
    val state: ListingResearchState,
    val kind: ListingResearchKind,
    val query: String,
    val found: Boolean = false,
    val name: String? = null,
    /** For the curator: who or what it is, and what the provider wasn't sure of. */
    val summary: String? = null,
    val description: String? = null,
    val website: String? = null,
    val city: String? = null,
    val address: String? = null,
    val phone: String? = null,
    /** A venue's Google place, for `VenueInput.googlePlaceId`. */
    val googlePlaceId: String? = null,
    /** TALENT or ORGANIZATION, for a person. */
    val personKind: String? = null,
    val homeVenueName: String? = null,
    val homeVenue: Ref? = null,
    val locale: Ref? = null,
    val links: List<Link> = emptyList(),
    val evidence: List<Page> = emptyList(),
    val matches: List<Match> = emptyList(),
    val error: String? = null,
) {
    @Serializable public data class Link(val provider: String, val handle: String, val url: String)
    @Serializable public data class Page(val url: String, val title: String)
    @Serializable public data class Match(val id: String, val name: String? = null)
    @Serializable public data class Ref(val id: String)

    /** Its profile on [provider] (instagram, tiktok…), as a link, or "". */
    public fun link(provider: String): String = links.firstOrNull { it.provider == provider }?.url.orEmpty()

    /** Its links as `socialLinks` takes them. */
    public val socialLinks: JsonArray get() = JsonArray(links.map {
        JsonObject(mapOf("provider" to JsonPrimitive(it.provider), "handle" to JsonPrimitive(it.handle)))
    })
}

/**
 * The GraphQL for Add with AI in Focus, shared by the staff apps (and iOS, word for word). It runs on the staff
 * endpoint, which this SDK doesn't call: StaffKit's session sends [START_MUTATION], then asks [QUERY] every
 * [POLL_INTERVAL_MS] until the request [ListingResearchState.isFinished] or [TIMEOUT_MS] passes.
 */
public object ListingResearch {
    /** How often to ask again while it researches. */
    public const val POLL_INTERVAL_MS: Long = 2_000
    /** When to stop asking: the provider's own limit is three minutes. */
    public const val TIMEOUT_MS: Long = 200_000

    public const val FIELDS: String = "id state kind query found name summary description website city address phone googlePlaceId personKind homeVenueName homeVenue { id } locale { id } links { provider handle url } evidence { url title } matches { id name } error"

    public const val START_MUTATION: String = """
        # endpoint: staff
        mutation FocusResearchListing(${'$'}input: ResearchListingInput!) {
          researchListing(input: ${'$'}input) { listingResearch { $FIELDS } }
        }
    """

    public const val QUERY: String = """
        # endpoint: staff
        query FocusListingResearch(${'$'}id: ID!) { listingResearch(id: ${'$'}id) { $FIELDS } }
    """

    private val json = Json { ignoreUnknownKeys = true; coerceInputValues = true }

    /** The variables for [START_MUTATION]: what the curator typed, and the locale they're curating, if one. */
    public fun startVariables(kind: ListingResearchKind, query: String, localeId: String?): Map<String, JsonElement> =
        mapOf("input" to JsonObject(buildMap {
            put("kind", JsonPrimitive(kind.name))
            put("query", JsonPrimitive(query.trim()))
            localeId?.takeIf { it.isNotEmpty() }?.let { put("localeId", JsonPrimitive(it)) }
        }))

    /** The variables for [QUERY]. */
    public fun queryVariables(id: String): Map<String, JsonElement> = mapOf("id" to JsonPrimitive(id))

    /** [START_MUTATION]'s `data`. */
    public fun parseStart(data: JsonObject): ListingResearchDraft? =
        ((data["researchListing"] as? JsonObject)?.get("listingResearch") as? JsonObject)?.let(::parse)

    /** [QUERY]'s `data`; null when it's gone or someone else's. */
    public fun parseRead(data: JsonObject): ListingResearchDraft? = (data["listingResearch"] as? JsonObject)?.let(::parse)

    public fun parse(node: JsonObject): ListingResearchDraft? =
        runCatching { json.decodeFromJsonElement(ListingResearchDraft.serializer(), node) }.getOrNull()
}

/** Add with AI's words, the same in every staff app. */
public object ListingResearchCopy {
    public const val BUTTON: String = "Add with AI"
    public fun title(kind: ListingResearchKind): String = if (kind == ListingResearchKind.VENUE) "Add a venue with AI" else "Add a person with AI"
    public fun prompt(kind: ListingResearchKind): String =
        if (kind == ListingResearchKind.VENUE) "A venue's name and city, like “Nyne Spokane”" else "A name and city, like “Spokane Pride”"
    public const val DETAIL: String = "AI searches the web and fills out what it finds. You check it before anything is saved."
    public const val START: String = "Research"
    public const val RESEARCHING: String = "Researching on the web…"
    public const val NOT_FOUND: String = "Nothing turned up on the web. Check the spelling or add a city, or fill it out yourself."
    public const val TIMED_OUT: String = "That took too long. Try again, or fill it out yourself."
    public fun alreadyListed(names: List<String>): String = "Already listed: ${names.joinToString(", ")}. Make sure this isn't the same one."
    public const val CHECK_DRAFT: String = "Filled out by AI. Check every field before you save."
    public const val SOURCES: String = "Where it looked"
}
