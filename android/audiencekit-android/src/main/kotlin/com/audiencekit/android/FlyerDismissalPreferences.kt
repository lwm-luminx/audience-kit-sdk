package com.audiencekit.android

import android.content.Context
import android.content.SharedPreferences
import com.audiencekit.FlyerDismissalStore

/**
 * Keeps FlyerDismissals and FlyerLinePicker on the phone, in the app's private shared preferences. Unlike
 * CardPreferences, leave [preferencesName] OUT of the app's Auto Backup rules: which kinds of help someone hid should
 * not follow them to another device or into a backup someone else can open.
 */
public class FlyerDismissalPreferences(
    context: Context,
    public val preferencesName: String = "com.audiencekit.flyers",
) : FlyerDismissalStore {
    private val preferences: SharedPreferences =
        context.applicationContext.getSharedPreferences(preferencesName, Context.MODE_PRIVATE)

    // Kept as one newline-joined string, since a string set loses the order the dismissals were made in.
    override fun load(key: String): List<String> =
        preferences.getString(key, null)?.split('\n')?.filter { it.isNotEmpty() }.orEmpty()

    override fun save(key: String, values: List<String>) {
        preferences.edit().putString(key, values.joinToString("\n")).apply()
    }
}
