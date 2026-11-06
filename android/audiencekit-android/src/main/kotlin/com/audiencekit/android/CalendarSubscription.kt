package com.audiencekit.android

import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import com.audiencekit.CalendarLinks

/**
 * Subscribes the person's calendar to [links] (`client.followVenueInCalendar(id).links`): a calendar app that takes
 * webcal:// links does, else Google Calendar's add-by-URL page opens in the browser. Returns false when nothing could
 * open either, so the app can offer [copyCalendarLink].
 */
public fun Context.subscribeToCalendar(links: CalendarLinks): Boolean =
    open(links.webcalUrl) || open(links.googleUrl)

/** Opens Google Calendar's page that adds the subscription. */
public fun Context.addToGoogleCalendar(links: CalendarLinks): Boolean = open(links.googleUrl)

/** Copies the feed's https link, for calendar apps that take a pasted URL. */
public fun Context.copyCalendarLink(links: CalendarLinks, label: String = "Calendar link") {
    val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager ?: return
    clipboard.setPrimaryClip(ClipData.newPlainText(label, links.url))
}

private fun Context.open(url: String): Boolean = try {
    startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    true
} catch (_: ActivityNotFoundException) {
    false
}
