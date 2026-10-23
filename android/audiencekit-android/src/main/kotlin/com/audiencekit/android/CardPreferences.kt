package com.audiencekit.android

import android.content.Context
import android.content.SharedPreferences
import com.audiencekit.CardCategory
import com.audiencekit.CardFilter
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * The promoted-card categories the viewer turned off ("Cards you see"), kept in the app's private shared preferences.
 * Never sent to the server, logged, or counted: build a [CardFilter] from it and filter on the device.
 *
 * There's no live sync across devices on Android: include [preferencesName] in the app's Auto Backup rules so the
 * choices come back on a new phone.
 */
public class CardPreferences(
    context: Context,
    public val preferencesName: String = "com.audiencekit.cards",
) {
    private val preferences: SharedPreferences =
        context.applicationContext.getSharedPreferences(preferencesName, Context.MODE_PRIVATE)

    private val state = MutableStateFlow(read())

    /** The categories turned off. */
    public val hidden: StateFlow<Set<String>> = state.asStateFlow()

    public fun isHidden(category: String): Boolean = category in state.value

    /** Turns a category off or back on. */
    public fun setHidden(category: String, hide: Boolean) {
        store(if (hide) state.value + category else state.value - category)
    }

    /** Shows every category again. */
    public fun reset() {
        store(emptySet())
    }

    /** The filter for these preferences and the published categories. */
    public fun filter(categories: List<CardCategory>?): CardFilter = CardFilter(state.value, categories)

    private fun read(): Set<String> = preferences.getStringSet(KEY, null)?.toSet().orEmpty()

    private fun store(hidden: Set<String>) {
        preferences.edit().putStringSet(KEY, hidden.toSet()).apply()
        state.value = hidden
    }

    public companion object {
        /** The key the hidden categories are kept under. */
        public const val KEY: String = "hiddenCategories"
    }
}
