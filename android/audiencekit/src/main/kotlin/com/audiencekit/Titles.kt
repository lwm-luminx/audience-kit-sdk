package com.audiencekit

import kotlinx.serialization.Serializable

// Community titles on a person's page: a pageant crown, an Imperial Court reign, a club title (Mr. Leather), a
// chapter's lead. The API keeps them with civic offices as `PersonOffice` (its `PersonOffice::TITLES`); the Swift SDK's
// `titles(personID:)` (Civic.swift) reads the same thing. An audience without offices gets none back.

/** Whether someone holds an office or title now, is running for it, or held it. The API's `OfficeStatus`. */
public enum class OfficeStatus { INCUMBENT, CANDIDATE, FORMER }

/** Where an office or title is: its locale. */
@Serializable
public data class OfficeLocale(val id: String, val name: String? = null, val label: String? = null)

/** An office or community title someone holds, held or is running for: the API's `PersonOffice`. */
@Serializable
public data class PersonOffice(
    val id: String,
    /** The API's `OfficeKind`, e.g. `PAGEANT_TITLE` or `US_HOUSE`. */
    val office: String,
    /** How it reads, e.g. "Miss Gay Utah". */
    val title: String,
    /** With where, e.g. "Miss Gay Utah, Utah". */
    val label: String = title,
    val status: OfficeStatus = OfficeStatus.INCUMBENT,
    /** ISO 8601 date. */
    val termStart: String? = null,
    /** ISO 8601 date. */
    val termEnd: String? = null,
    val locale: OfficeLocale? = null,
) {
    /** Whether it's a community title rather than a civic office. */
    val isTitle: Boolean get() = office in TITLE_KINDS

    /** Whether they hold it now (a former title is shown as history). */
    val isReigning: Boolean get() = status != OfficeStatus.FORMER

    /** The place and years under the title, e.g. "Salt Lake City · 2025–2026"; empty when there are neither. */
    val detail: String
        get() {
            val years = listOfNotNull(termStart, termEnd).map { it.take(4) }.distinct()
            return listOfNotNull(locale?.name ?: locale?.label, years.joinToString("–").ifEmpty { null })
                .joinToString(" · ")
        }

    public companion object {
        /** The API's `PersonOffice::TITLES`. */
        public val TITLE_KINDS: Set<String> = setOf("PAGEANT_TITLE", "COURT_TITLE", "CLUB_TITLE", "CHAPTER_LEAD")
    }
}

/**
 * The community titles someone holds or has held, for a performer's or member's page: reigning first, then newest
 * reign first. Empty in an audience without offices, and filtered here so civic offices never show as titles.
 */
public suspend fun AudienceKitClient.titles(personId: String): List<PersonOffice> = graphQL(
    TitleQueries.TYPES,
    PersonTitlesResponse.serializer(),
    graphQLVariables("id" to personId),
    "PersonTitles",
    TitleQueries::personTitles,
).node?.offices.orEmpty().sortedForPage()

/** Titles in page order: reigning before former, newest reign first within each. */
public fun List<PersonOffice>.sortedForPage(): List<PersonOffice> =
    filter { it.isTitle }.sortedWith(compareByDescending<PersonOffice> { it.isReigning }.thenByDescending { it.termStart.orEmpty() })

internal object TitleQueries {
    val TYPES: List<String> = listOf("Person")

    const val OFFICE_FIELDS: String = "id office title label status termStart termEnd locale { id name label }"

    fun personTitles(shape: SchemaShape): String = if (!shape.has("Person", "offices")) "query PersonTitles { id }" else """
        query PersonTitles(${'$'}id: ID!) {
          node(id: ${'$'}id) { ... on Person { id offices(status: [INCUMBENT, FORMER]) { $OFFICE_FIELDS } } }
        }
    """.trimIndent()
}

@Serializable
internal data class PersonTitlesResponse(val node: Holder? = null) {
    @Serializable
    data class Holder(val offices: List<PersonOffice>? = null)
}
