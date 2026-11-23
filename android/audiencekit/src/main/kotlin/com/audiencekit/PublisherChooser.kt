package com.audiencekit

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.text.Normalizer
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

// Choosing which Soapbox publication to work on, the way staff apps choose a locale: search by name or place, the ones
// near the device, and the ones chosen last on this device (Rick, 2026-11-23). These documents run on the staff
// endpoint, which this SDK doesn't call: StaffKit's session sends them and the `parse` functions read the answers. The
// same as the Swift SDK's AudienceCore PublisherChooser, word for word.

/** A publication someone may switch to, with the place it covers. */
public data class PublisherChoice(
    val id: String,
    /** Its masthead, else its person's name. */
    val name: String,
    val masthead: String? = null,
    /** The person listing it publishes as, when its name differs from [name]. */
    val personName: String? = null,
    /** The API's `PublicationTrust` (`TRUSTED`, `PENDING`, `SUSPENDED`); null when the viewer may not see it. */
    val trust: String? = null,
    val localeId: String? = null,
    val localeName: String? = null,
    /** The locales its locale lies within, innermost first: ["Utah", "United States"]. */
    val localeAncestors: List<String> = emptyList(),
    /** Its locale's point, for Nearby. */
    val coordinate: Coordinate? = null,
) {
    /** "Salt Lake City, Utah": the place it covers with the one it lies within. Null when it covers no locale. */
    val place: String?
        get() = localeName?.takeIf { it.isNotEmpty() }?.let { name -> localeAncestors.firstOrNull()?.let { "$name, $it" } ?: name }

    val isPending: Boolean get() = trust == "PENDING"
    val isSuspended: Boolean get() = trust == "SUSPENDED"
}

/** A publication near a position: whether the position lies inside the place it covers, and how far away it is. */
public data class NearbyPublisher(val publisher: PublisherChoice, val inside: Boolean, val distance: Double?)

/**
 * The publications someone may switch to, as a chooser lists them: by name, found by name or place, nearest first from
 * a position, or picked out by ID (the recent ones).
 */
public class PublisherDirectory(publishers: List<PublisherChoice>) {
    /** Every publication, by name. */
    public val entries: List<PublisherChoice> = publishers.sortedBy { fold(it.name) }

    public fun entry(id: String): PublisherChoice? = entries.firstOrNull { it.id == id }

    /** The ones with these IDs, in this order, leaving out any no longer here. */
    public fun entries(ids: List<String>): List<PublisherChoice> = ids.mapNotNull(::entry)

    /**
     * Publications matching [text], best first: a name that is the text, then names starting with it, then a word in
     * the name starting with it, then names containing it, then its masthead or person, then the place it covers.
     * Case and accents are ignored.
     */
    public fun search(text: String): List<PublisherChoice> {
        val query = fold(text)
        if (query.isEmpty()) return entries
        return entries.withIndex().mapNotNull { (offset, entry) ->
            val name = fold(entry.name)
            val rank = when {
                name == query -> 0
                name.startsWith(query) -> 1
                name.split(NOT_WORD).any { it.startsWith(query) } -> 2
                name.contains(query) -> 3
                listOfNotNull(entry.masthead, entry.personName).any { fold(it).contains(query) } -> 4
                entry.place?.let { fold(it).contains(query) } == true -> 5
                entry.localeAncestors.any { fold(it).contains(query) } -> 6
                else -> return@mapNotNull null
            }
            Triple(entry, rank, offset)
        }.sortedWith(compareBy({ it.second }, { it.third })).map { it.first }
    }

    /**
     * Publications near [position], best first: the ones covering a locale it lies in ([containing], from the API's
     * `locales(at:)`, outermost first as it answers), then the closest by their locale's point within [radius] meters.
     */
    public fun nearby(
        position: Coordinate,
        containing: List<String> = emptyList(),
        radius: Double = 150_000.0,
        limit: Int = 8,
    ): List<NearbyPublisher> {
        val depth = containing.withIndex().associate { it.value to it.index }
        val inside = entries.mapNotNull { entry ->
            val level = entry.localeId?.let(depth::get) ?: return@mapNotNull null
            NearbyPublisher(entry, inside = true, distance = entry.coordinate?.let { distance(position, it) }) to level
        }.sortedByDescending { it.second }.map { it.first }
        val insideIds = inside.map { it.publisher.id }.toSet()
        val close = entries.mapNotNull { entry ->
            val point = entry.coordinate
            if (entry.id in insideIds || point == null) return@mapNotNull null
            val meters = distance(position, point)
            if (meters <= radius) NearbyPublisher(entry, inside = false, distance = meters) else null
        }.sortedBy { it.distance ?: 0.0 }
        return (inside + close).take(limit)
    }

    public companion object {
        private val NOT_WORD = Regex("[^\\p{L}\\p{N}]+")
        private val MARKS = Regex("\\p{M}+")

        /** Great-circle distance in meters. */
        public fun distance(from: Coordinate, to: Coordinate): Double {
            val radians = Math.PI / 180
            val dLat = (to.latitude - from.latitude) * radians
            val dLon = (to.longitude - from.longitude) * radians
            val a = sin(dLat / 2) * sin(dLat / 2) +
                cos(from.latitude * radians) * cos(to.latitude * radians) * sin(dLon / 2) * sin(dLon / 2)
            return 6_371_000 * 2 * atan2(sqrt(a), sqrt(1 - a))
        }

        internal fun fold(text: String): String =
            Normalizer.normalize(text, Normalizer.Form.NFD).replace(MARKS, "").lowercase().trim()
    }
}

/** The publications last chosen in an audience on a device, newest first; the first is the one being worked on. */
public object PublisherRecents {
    public const val LIMIT: Int = 6

    /** The preference key to keep them under, one list per audience. */
    public fun key(audienceId: String): String = "AudienceKit.recentPublishers.$audienceId"

    /** [id] moved to the front, without duplicates, at most [LIMIT]. */
    public fun adding(id: String, list: List<String>): List<String> =
        if (id.isEmpty()) list.take(LIMIT) else (listOf(id) + list.filter { it != id }).take(LIMIT)
}

/** The documents a publisher chooser sends, and their answers. */
public object PublisherChooserDocuments {
    public const val PUBLISHER_FIELDS: String =
        "id name masthead trust person { id name } locale { id name ancestors { id name } location { point } }"

    /** The publications the signed-in user runs; every one for the audience's admins. */
    public const val PUBLISHERS_QUERY: String = """
        # endpoint: staff
        query SoapboxPublisherChooser { soapbox { myPublications { $PUBLISHER_FIELDS } } }
    """

    /** The locales a position lies in, outermost first: pass `here` as [Coordinates.toGraphQLValue]. */
    public const val LOCALES_AT_QUERY: String = """
        # endpoint: staff
        query SoapboxLocalesAt(${'$'}here: CoordinatesInput!) { locales(at: ${'$'}here) { id } }
    """

    /** [PUBLISHERS_QUERY]'s `data`. */
    public fun parsePublishers(data: JsonObject): PublisherDirectory =
        PublisherDirectory(data.obj("soapbox")?.array("myPublications").orEmpty().mapNotNull { publisher(it as? JsonObject) })

    /** [LOCALES_AT_QUERY]'s `data`: the locale IDs, outermost first. */
    public fun parseLocalesAt(data: JsonObject): List<String> =
        data.array("locales").orEmpty().mapNotNull { (it as? JsonObject)?.string("id") }

    private fun publisher(obj: JsonObject?): PublisherChoice? {
        obj ?: return null
        val name = obj.string("name") ?: return null
        val locale = obj.obj("locale")
        return PublisherChoice(
            id = obj.string("id") ?: return null,
            name = name,
            masthead = obj.string("masthead"),
            personName = obj.obj("person")?.string("name")?.takeIf { it.isNotEmpty() && it != name },
            trust = obj.string("trust"),
            localeId = locale?.string("id"),
            localeName = locale?.string("name"),
            // The API lists them outermost first.
            localeAncestors = locale?.array("ancestors").orEmpty()
                .mapNotNull { (it as? JsonObject)?.string("name")?.takeIf(String::isNotEmpty) }.reversed(),
            coordinate = locale?.obj("location")?.string("point")?.let(Coordinate::fromWkt),
        )
    }

    private fun JsonObject.obj(key: String): JsonObject? = this[key] as? JsonObject
    private fun JsonObject.array(key: String): JsonArray? = this[key] as? JsonArray
    private fun JsonObject.string(key: String): String? = (this[key] as? JsonPrimitive)?.takeIf { it.isString }?.content
}
