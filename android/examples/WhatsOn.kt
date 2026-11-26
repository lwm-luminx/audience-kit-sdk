// The "What's on" screen: a locale's upcoming events grouped by night, the way a list or a widget shows them. The
// models are plain data, so the same function feeds a Compose LazyColumn, a RecyclerView or a server-rendered page.
package com.audiencekit.examples

import com.audiencekit.AudienceKitClient
import com.audiencekit.Event
import com.audiencekit.EventWindow
import com.audiencekit.events
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

/** One night's events, soonest first. */
data class Night(val date: LocalDate, val title: String, val events: List<Row>)

/** What a row shows: the event, where, and when, in the locale's time zone. */
data class Row(val id: String, val name: String, val where: String?, val time: String, val canceled: Boolean)

private val dayTitle = DateTimeFormatter.ofPattern("EEEE, MMMM d", Locale.US)
private val timeOfDay = DateTimeFormatter.ofPattern("h:mm a", Locale.US)

/** Groups [events] by the night they start on in [zone]; events with no start yet are left out. */
fun nights(events: List<Event>, zone: ZoneId): List<Night> =
    events
        .mapNotNull { event -> event.startAt?.let { event to Instant.parse(it).atZone(zone) } }
        .sortedBy { (_, start) -> start }
        .groupBy({ (_, start) -> start.toLocalDate() }) { (event, start) ->
            Row(event.id, event.name ?: "Untitled", event.venueName, timeOfDay.format(start), event.isCanceled)
        }
        .toSortedMap()
        .map { (date, rows) -> Night(date, dayTitle.format(date), rows) }

/** The locale's upcoming events, by night. */
suspend fun whatsOn(client: AudienceKitClient, localeId: String, zone: ZoneId = ZoneId.of("America/Denver")): List<Night> =
    nights(client.events(window = EventWindow.UPCOMING, localeId = localeId), zone)
