package com.audiencekit.android

import android.content.Context
import android.content.SharedPreferences
import com.audiencekit.PublisherAdsCopy

/**
 * Which signed-in people on this device have acknowledged [PublisherAdsCopy], so the note shows once per person before
 * their first Soapbox story and not again. Kept by user ID in the app's private shared preferences; never sent to the
 * server. Include [preferencesName] in the app's Auto Backup rules so it comes back on a new phone.
 */
public class PublisherAdsAcknowledgement(
    context: Context,
    public val preferencesName: String = "com.audiencekit.soapbox",
) {
    private val preferences: SharedPreferences =
        context.applicationContext.getSharedPreferences(preferencesName, Context.MODE_PRIVATE)

    /** Whether [userId] has acknowledged it. Nobody signed in (null) never has, so a guest sees the note each time. */
    public fun isAcknowledged(userId: String?): Boolean {
        val id = PublisherAdsCopy.normalizedUserId(userId) ?: return false
        return id in read()
    }

    /** Records that [userId] acknowledged it. Does nothing for null. */
    @Synchronized
    public fun acknowledge(userId: String?) {
        val id = PublisherAdsCopy.normalizedUserId(userId) ?: return
        preferences.edit().putStringSet(KEY, read() + id).apply()
    }

    /** Forgets every acknowledgement. */
    public fun reset() {
        preferences.edit().remove(KEY).apply()
    }

    private fun read(): Set<String> = preferences.getStringSet(KEY, null)?.toSet().orEmpty()

    public companion object {
        /** The key the acknowledged user IDs are kept under. */
        public const val KEY: String = "publisherAdsAcknowledged"
    }
}
