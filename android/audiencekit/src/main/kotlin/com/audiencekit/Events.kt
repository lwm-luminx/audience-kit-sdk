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

/**
 * A way into an event or a venue night (the API's `IAdmissionOffer`): tickets on a ticketing partner, or the cover
 * AudienceKit takes.
 */
@Serializable
public data class AdmissionOffer(
    /** What it costs the buyer, all in (the lowest price for tickets); null when the seller doesn't say. */
    val price: Money? = null,
    /** Where to buy it on the web; null when it's bought in the app (the cover) or at the door. */
    val url: String? = null,
    val seller: Seller,
) {
    /** Who sells it (the API's `IProvider`): a ticketing partner, or AudienceKit itself. */
    @Serializable
    public data class Seller(val key: String, val name: String)
}

/** The Cover module's part of an event's tickets: the cover at its venue that night. */
@Serializable
public data class EventCover(val charge: CoverCharge? = null)

/** The Ticketing module's part of an event: where to buy tickets, every offer and (with Cover) the night's cover. */
@Serializable
public data class EventTickets(
    val url: String? = null,
    val offers: Connection<AdmissionOffer>? = null,
    val cover: EventCover? = null,
)

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
    @SerialName("socialLinks") val links: Connection<SocialLink>? = null,
) {
    /**
     * Its links out, such as a conference's own Discord or Matrix space: asked for by [AudienceKitClient.event] only,
     * null from lists and on APIs without `Event.socialLinks`.
     */
    val socialLinks: List<SocialLink>? get() = links?.items

    /** Its community chats elsewhere ([SocialLink.isCommunityChat]), to offer as Join buttons. */
    val communityChats: List<SocialLink> get() = socialLinks.communityChats

    /** Where it is; null while the venue is still to be announced. */
    val venue: EventVenue? get() = venueMixin?.venue

    /** Its venue's name as the API shows it, e.g. "To be announced". */
    val venueName: String? get() = venueMixin?.name

    val hosts: List<EventPerson>? get() = people?.hosts?.items
    val lineup: List<EventPerson>? get() = people?.lineup?.items
    val ticketUrl: String? get() = tickets?.url

    /** Every way in on sale, whichever module sells it; null without the Ticketing module. */
    val ticketOffers: List<AdmissionOffer>? get() = tickets?.offers?.items

    /** The cover at its venue that night: null when there's none, when it sells tickets, or without the Cover module. */
    val coverCharge: CoverCharge? get() = tickets?.cover?.charge
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
internal val EVENT_TYPES: List<String> = Queries.LISTING_TYPES + "EventSeries" + "EventTickets"

/** An [AdmissionOffer]. */
public const val ADMISSION_OFFER_FIELDS: String = "price { ${Queries.MONEY_FIELDS} } url seller { key name }"

/** The Ticketing module's part of an event, with the Cover module's charge when the audience has it. */
public fun Queries.eventTicketsFields(shape: SchemaShape): String {
    val cover = if (shape.has("EventTickets", "cover")) " cover { charge { ${Queries.COVER_CHARGE_FIELDS} } }" else ""
    return "tickets { url offers { nodes { $ADMISSION_OFFER_FIELDS } }$cover }"
}

/** An event: its own fields, then those of the Venues, RSVP, People and Ticketing modules the audience has. */
public fun Queries.eventFields(shape: SchemaShape): String = buildString {
    append("id name description startAt endAt isFeatured isCanceled bannerUrl sourceUrl ")
    append("locale { ${localeFields(shape)} } tags { $TAG_FIELDS }")
    if (shape.has("Event", "venue")) append(" ").append(eventVenueFields(shape))
    if (shape.has("Event", "rsvp")) append(" rsvp { mine count }")
    if (shape.has("Event", "people")) {
        append(" people { hosts { nodes { id name avatarUrl } } lineup { nodes { id name avatarUrl } } }")
    }
    if (shape.has("Event", "tickets")) append(" ").append(eventTicketsFields(shape))
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

/** One event's page: its fields and, where the API has them, its links out (lists leave those out to keep cost down). */
public fun Queries.event(shape: SchemaShape): String {
    val links = if (shape.has("Event", "socialLinks")) " socialLinks { nodes { ${SocialLink.FIELDS} } }" else ""
    return """
        query Event(${'$'}id: ID!) {
          events { event(id: ${'$'}id) { ${eventFields(shape)}$links } }
        }
    """.trimIndent()
}

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
 * or at a venue when given: every one of them, or up to [first]. A page costs [first] times an event in the API's
 * complexity budget (1000), so leave it null unless you page: `first = 100` alone is over budget.
 */
public suspend fun AudienceKitClient.events(
    window: EventWindow = EventWindow.UPCOMING,
    localeId: String? = null,
    venueId: String? = null,
    first: Int? = null,
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

/** The audience's recurring events by name, in a locale or at a venue when given: all of them, or up to [first]. */
public suspend fun AudienceKitClient.eventSeries(
    localeId: String? = null,
    venueId: String? = null,
    first: Int? = null,
): List<EventSeries> = graphQL(
    EVENT_TYPES,
    EventsResponse.serializer(),
    graphQLVariables("localeId" to localeId, "venueId" to venueId, "first" to first),
    "EventSeries",
) { Queries.eventSeries(it) }.events?.series?.items.orEmpty()

/** The types [AudienceKitClient.venueCover] and [venueOffers] depend on. */
internal val VENUE_TICKET_TYPES: List<String> = listOf("Venue", "VenueTickets")

/** Every way into a venue on a night, or just the venue where the audience doesn't have the Ticketing module. */
public fun Queries.venueOffers(shape: SchemaShape): String {
    // A variable the document doesn't use is an error, so night goes with the field.
    val hasTickets = shape.has("Venue", "tickets")
    val offers = if (hasTickets) " tickets { offers(night: \$night) { nodes { $ADMISSION_OFFER_FIELDS } } }" else ""
    val night = if (hasTickets) ", \$night: ISO8601Date" else ""
    return """
        query VenueOffers(${'$'}id: ID!$night) {
          venues { venue(id: ${'$'}id) { id$offers } }
        }
    """.trimIndent()
}

@Serializable
internal data class VenueOffersResponse(val venues: Venues? = null) {
    @Serializable internal data class Venues(val venue: Venue? = null)
    @Serializable internal data class Venue(val tickets: Tickets? = null)
    @Serializable internal data class Tickets(val offers: Connection<AdmissionOffer>? = null)
}

/**
 * Every way into a venue on a night (tonight when [night] is null, `yyyy-MM-dd` otherwise): its cover and tickets on
 * its events' partner listings. Empty when there are none, or without the Ticketing module.
 */
public suspend fun AudienceKitClient.venueOffers(venueId: String, night: String? = null): List<AdmissionOffer> =
    graphQL(
        VENUE_TICKET_TYPES,
        VenueOffersResponse.serializer(),
        graphQLVariables("id" to venueId, "night" to night),
        "VenueOffers",
    ) { Queries.venueOffers(it) }.venues?.venue?.tickets?.offers?.items.orEmpty()
