package com.audiencekit

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/** Which events [AudienceKitClient.events] lists: the API's `EventWindow`. */
public enum class EventWindow {
    /** Those still to come or under way, soonest first. */
    UPCOMING,

    /** Those that have ended, latest first. */
    PAST,
}

/** A venue an event or series is at: the `venue { venue }` of the API's venues module. */
@Serializable
public data class EventVenue(
    val id: String,
    val name: String? = null,
    val photoUrl: String? = null,
    /** Where it is; [Location.coordinate] parses the API's WKT point. */
    val location: Location? = null,
)

/** The API's `venue` mixin on an event or series: a display name ("To be announced" when there is none) and the venue. */
@Serializable
public data class EventVenueMixin(val name: String? = null, val venue: EventVenue? = null)

/** Someone on an event's bill: a host or a performer on its lineup. */
@Serializable
public data class EventPerson(val id: String, val name: String? = null, val avatarUrl: String? = null)

/** The signed-in user's RSVP to an event and how many are going, as a list shows it: `rsvp { mine count }`. */
@Serializable
public data class EventRSVPSummary(val mine: RSVPState = RSVPState.UNSURE, val count: Int = 0)

@Serializable
public data class EventPeople(
    val hosts: Connection<EventPerson>? = null,
    val lineup: Connection<EventPerson>? = null,
)

@Serializable
public data class EventTickets(val url: String? = null)

/** A connection read as `nodes { … }`. */
@Serializable
public data class Connection<T>(val nodes: List<T?> = emptyList()) {
    val items: List<T> get() = nodes.filterNotNull()
}

/**
 * An event in the audience: a night, a meetup or a conference.
 *
 * The parts modules add are null when the audience hasn't installed that module: [venue] (Venues), [rsvp] (RSVP),
 * [people] (People) and [tickets] (Ticketing). The SDK asks for them and, if the audience's schema doesn't have one,
 * asks again without.
 */
@Serializable
public data class Event(
    val id: String,
    val name: String? = null,
    val description: String? = null,
    /** ISO 8601; null when not scheduled yet. */
    val startAt: String? = null,
    val endAt: String? = null,
    val isFeatured: Boolean = false,
    val isCanceled: Boolean = false,
    val bannerUrl: String? = null,
    /** Where it was listed from (its calendar or website), if it was imported. */
    val sourceUrl: String? = null,
    val locale: AudienceLocale? = null,
    val tags: List<Tag> = emptyList(),
    @SerialName("venue") val venueMixin: EventVenueMixin? = null,
    val rsvp: EventRSVPSummary? = null,
    val people: EventPeople? = null,
    val tickets: EventTickets? = null,
) {
    /** Where it is; null while the venue is still to be announced. */
    val venue: EventVenue? get() = venueMixin?.venue

    /** Its venue's name as the API shows it, e.g. "To be announced". */
    val venueName: String? get() = venueMixin?.name

    val hosts: List<EventPerson>? get() = people?.hosts?.items
    val lineup: List<EventPerson>? get() = people?.lineup?.items
    val ticketUrl: String? get() = tickets?.url
}

/** A recurring event: a weekly meetup or a monthly night. */
@Serializable
public data class EventSeries(
    val id: String,
    val name: String,
    val description: String? = null,
    /** How it repeats, in words, e.g. "Every Tuesday". */
    val recurrenceText: String? = null,
    /** The first night, `yyyy-MM-dd`. */
    val startsOn: String,
    /** When each night starts, `HH:mm`, in [timeZone]. */
    val startTime: String,
    val timeZone: String,
    val durationMinutes: Int? = null,
    val bannerUrl: String? = null,
    val locale: AudienceLocale? = null,
    val tags: List<Tag> = emptyList(),
    @SerialName("venue") val venueMixin: EventVenueMixin? = null,
) {
    val venue: EventVenue? get() = venueMixin?.venue
    val venueName: String? get() = venueMixin?.name
}

/** The types whose fields the event documents depend on. */
internal val EVENT_TYPES: List<String> = Queries.LISTING_TYPES + "EventSeries"

/** An event: its own fields, then those of the Venues, RSVP, People and Ticketing modules the audience has. */
public fun Queries.eventFields(shape: SchemaShape): String = buildString {
    append("id name description startAt endAt isFeatured isCanceled bannerUrl sourceUrl ")
    append("locale { ${localeFields(shape)} } tags { $TAG_FIELDS }")
    if (shape.has("Event", "venue")) append(" ").append(eventVenueFields(shape))
    if (shape.has("Event", "rsvp")) append(" rsvp { mine count }")
    if (shape.has("Event", "people")) {
        append(" people { hosts { nodes { id name avatarUrl } } lineup { nodes { id name avatarUrl } } }")
    }
    if (shape.has("Event", "tickets")) append(" tickets { url }")
}

/** The Venues module's part of an event or series. */
public fun Queries.eventVenueFields(shape: SchemaShape): String {
    val place = if (shape.has("Location", "places")) " places { placeId }" else ""
    return "venue { name venue { id name photoUrl location { id point address$place } } }"
}

public fun Queries.eventSeriesFields(shape: SchemaShape): String =
    "id name description recurrenceText startsOn startTime timeZone durationMinutes bannerUrl " +
        "locale { ${localeFields(shape)} } tags { $TAG_FIELDS }" +
        if (shape.has("EventSeries", "venue")) " " + eventVenueFields(shape) else ""

public fun Queries.events(shape: SchemaShape): String = """
    query Events(${'$'}window: EventWindow, ${'$'}localeId: ID, ${'$'}venueId: ID, ${'$'}first: Int) {
      events {
        list(window: ${'$'}window, localeId: ${'$'}localeId, venueId: ${'$'}venueId, first: ${'$'}first) {
          nodes { ${eventFields(shape)} }
        }
      }
    }
""".trimIndent()

public fun Queries.event(shape: SchemaShape): String = """
    query Event(${'$'}id: ID!) {
      events { event(id: ${'$'}id) { ${eventFields(shape)} } }
    }
""".trimIndent()

public fun Queries.eventSeries(shape: SchemaShape): String = """
    query EventSeries(${'$'}localeId: ID, ${'$'}venueId: ID, ${'$'}first: Int) {
      events {
        series(localeId: ${'$'}localeId, venueId: ${'$'}venueId, first: ${'$'}first) { nodes { ${eventSeriesFields(shape)} } }
      }
    }
""".trimIndent()

@Serializable
internal data class EventsResponse(val events: Mixin? = null) {
    @Serializable
    internal data class Mixin(
        val list: Connection<Event>? = null,
        val series: Connection<EventSeries>? = null,
        val event: Event? = null,
    )
}

/**
 * The audience's events, soonest first for [EventWindow.UPCOMING] (latest first for [EventWindow.PAST]), in a locale
 * or at a venue when given. Up to [first] of them.
 */
public suspend fun AudienceKitClient.events(
    window: EventWindow = EventWindow.UPCOMING,
    localeId: String? = null,
    venueId: String? = null,
    first: Int = 100,
): List<Event> = graphQL(
    EVENT_TYPES,
    EventsResponse.serializer(),
    graphQLVariables("window" to window, "localeId" to localeId, "venueId" to venueId, "first" to first),
    "Events",
) { Queries.events(it) }.events?.list?.items.orEmpty()

/** One event, or null when it doesn't exist or belongs to another audience. */
public suspend fun AudienceKitClient.event(id: String): Event? =
    graphQL(EVENT_TYPES, EventsResponse.serializer(), graphQLVariables("id" to id), "Event") { Queries.event(it) }
        .events?.event

/** The audience's recurring events by name, in a locale or at a venue when given. Up to [first] of them. */
public suspend fun AudienceKitClient.eventSeries(
    localeId: String? = null,
    venueId: String? = null,
    first: Int = 100,
): List<EventSeries> = graphQL(
    EVENT_TYPES,
    EventsResponse.serializer(),
    graphQLVariables("localeId" to localeId, "venueId" to venueId, "first" to first),
    "EventSeries",
) { Queries.eventSeries(it) }.events?.series?.items.orEmpty()
