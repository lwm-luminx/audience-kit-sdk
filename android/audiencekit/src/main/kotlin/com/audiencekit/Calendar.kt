package com.audiencekit

import kotlinx.serialization.Serializable
import java.net.URLEncoder

/**
 * A calendar subscription's links (API doc/CALENDAR_SYNC.md): an iCalendar feed that Google Calendar, Apple Calendar
 * and Outlook poll, so new, moved and canceled events follow on their own.
 *
 * @property url The https feed, to copy or share.
 * @property webcalUrl The same link as webcal://, which calendar apps open as a subscription.
 * @property googleUrl Google Calendar's page that adds the subscription.
 */
@Serializable
public data class CalendarLinks(val url: String, val webcalUrl: String, val googleUrl: String) {
    public companion object {
        /** The links for a feed at [feedUrl]: its webcal:// form and Google Calendar's add-by-URL page. */
        public fun of(feedUrl: String): CalendarLinks {
            val webcal = feedUrl.replaceFirst(Regex("^https?://"), "webcal://")
            val cid = URLEncoder.encode(webcal, "UTF-8").replace("+", "%20")
            return CalendarLinks(feedUrl, webcal, "https://calendar.google.com/calendar/render?cid=$cid")
        }
    }
}

/**
 * The signed-in person's one calendar subscription in the audience (API doc/CALENDAR_SYNC.md): the events they're
 * going to, their talent's slots, their shifts, and every event at the venues they follow. Following a venue adds to
 * this same feed rather than making another calendar.
 *
 * @property venueIds The venues it follows (the ones they may still see).
 */
public data class CalendarFeed(val links: CalendarLinks, val venueIds: List<String> = emptyList()) {
    /** Whether every event at the venue is in it. */
    public fun follows(venueId: String): Boolean = venueId in venueIds
}

@Serializable
private data class CalendarFeedWire(
    val url: String,
    val webcalUrl: String,
    val googleUrl: String,
    val venues: List<VenueRef>? = null,
) {
    @Serializable
    data class VenueRef(val id: String)

    fun feed() = CalendarFeed(CalendarLinks(url, webcalUrl, googleUrl), venues.orEmpty().map { it.id })
}

@Serializable
private data class CalendarFeedResponse(val me: Me? = null) {
    @Serializable
    data class Me(val calendarFeed: CalendarFeedWire? = null)
}

@Serializable
private data class CalendarFeedPayload(val calendarFeed: CalendarFeedWire)

@Serializable
private data class CreateCalendarFeedResponse(val createCalendarFeed: CalendarFeedPayload)

@Serializable
private data class SetCalendarFeedVenueResponse(val setCalendarFeedVenue: CalendarFeedPayload)

@Serializable
private data class DeleteCalendarFeedResponse(val deleteCalendarFeed: Payload? = null) {
    @Serializable
    data class Payload(val deleted: Boolean = false)
}

private const val CALENDAR_FEED_FIELDS = "url webcalUrl googleUrl venues { id }"

/** The signed-in person's calendar subscription, or null before they made one. */
public suspend fun AudienceKitClient.calendarFeed(): CalendarFeed? =
    graphQL("query CalendarFeed { me { calendarFeed { $CALENDAR_FEED_FIELDS } } }",
        CalendarFeedResponse.serializer(), operationName = "CalendarFeed").me?.calendarFeed?.feed()

/** Their subscription, made on first ask; [reset] gives it a new link, so the old one stops working. */
public suspend fun AudienceKitClient.createCalendarFeed(reset: Boolean = false): CalendarFeed =
    graphQL(
        """
        mutation CreateCalendarFeed(${'$'}reset: Boolean) {
          createCalendarFeed(input: { reset: ${'$'}reset }) { calendarFeed { $CALENDAR_FEED_FIELDS } }
        }
        """.trimIndent(),
        CreateCalendarFeedResponse.serializer(), graphQLVariables("reset" to reset), "CreateCalendarFeed",
    ).createCalendarFeed.calendarFeed.feed()

/**
 * Follows a venue in their subscription, so every event there shows up in their calendar (or, with [following] false,
 * stops). Makes the subscription on first ask; subscribe to [CalendarFeed.links] once. The API refuses a venue they
 * may not see ("Venue not found").
 */
public suspend fun AudienceKitClient.followVenueInCalendar(venueId: String, following: Boolean = true): CalendarFeed =
    graphQL(
        """
        mutation SetCalendarFeedVenue(${'$'}venueId: ID!, ${'$'}following: Boolean) {
          setCalendarFeedVenue(input: { venueId: ${'$'}venueId, following: ${'$'}following }) {
            calendarFeed { $CALENDAR_FEED_FIELDS }
          }
        }
        """.trimIndent(),
        SetCalendarFeedVenueResponse.serializer(),
        graphQLVariables("venueId" to venueId, "following" to following),
        "SetCalendarFeedVenue",
    ).setCalendarFeedVenue.calendarFeed.feed()

/** Ends their subscription: calendars subscribed to it stop updating. */
public suspend fun AudienceKitClient.deleteCalendarFeed(): Boolean =
    graphQL("mutation DeleteCalendarFeed { deleteCalendarFeed(input: {}) { deleted } }",
        DeleteCalendarFeedResponse.serializer(), operationName = "DeleteCalendarFeed").deleteCalendarFeed?.deleted
        ?: false
