// What a signed-in member does in the app, in the order a night out goes: RSVP, add it to their calendar, show the
// cover pass at the door, and report something they saw in chat.
package com.audiencekit.examples

import com.audiencekit.AdmissionStatus
import com.audiencekit.AudienceKitClient
import com.audiencekit.CoverPass
import com.audiencekit.RSVPState
import com.audiencekit.ReportCopy
import com.audiencekit.ReportResult
import com.audiencekit.ReportTarget
import com.audiencekit.createCalendarFeed
import com.audiencekit.followVenueInCalendar
import com.audiencekit.reportContent

/** Says they're going, and returns how many are going now. */
suspend fun goingTo(client: AudienceKitClient, eventId: String): Int = client.rsvp(eventId, RSVPState.ATTENDING).count

/** Links that add every event they're going to (and every event at [venueId]) to their own calendar. */
suspend fun calendarLinks(client: AudienceKitClient, venueId: String? = null): Map<String, String> {
    val feed = if (venueId != null) client.followVenueInCalendar(venueId) else client.createCalendarFeed()
    return mapOf("appleOrOutlook" to feed.links.webcalUrl, "google" to feed.links.googleUrl)
}

/** The door code and how many seconds it's good for. */
data class DoorPass(val code: String, val refreshInSeconds: Long)

/**
 * The code to show at the door for tonight's cover at a venue. It changes every 30 seconds, so draw it as a QR code
 * and draw it again when [DoorPass.refreshInSeconds] runs out. It's made on the phone, so it works with no signal.
 */
suspend fun doorPass(client: AudienceKitClient, venueId: String, now: Long = System.currentTimeMillis() / 1000): DoorPass? {
    val pass = client.venueCover(venueId)?.viewerAdmission ?: return null
    val secret = pass.passSecret ?: return null
    if (pass.status != AdmissionStatus.PAID) return null
    return DoorPass(CoverPass.code(pass.id, secret, now), CoverPass.secondsUntilNextWindow(now))
}

/** Reports a chat message as harassment and blocks whoever sent it. */
suspend fun reportHarassment(client: AudienceKitClient, messageId: String): ReportResult =
    client.reportContent(ReportTarget.MESSAGE, messageId, reason = ReportCopy.REASONS[1], block = true)
