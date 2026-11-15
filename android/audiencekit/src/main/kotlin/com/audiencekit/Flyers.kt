package com.audiencekit

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlin.random.Random

// Digital flyers and community resources (the API's doc/DIGITAL_FLYERS.md).
//
// - A digital flyer is a card for a city, like a flyer on a community board: the server chooses a city's flyers from
//   the city and the time and nothing else, so everyone in the city at that moment sees the same pool. It arrives as
//   the CardKind.FLYERS card of the Now layout (LayoutCard.flyers).
// - Dismissing one flyer or hiding a whole category is kept on this phone only (FlyerDismissals): never sent to the
//   server, never logged, never counted.
// - Show FlyersCardContent.disclosure and the explainer link on every flyer card. Pick one of a flyer's lines per
//   showing with FlyerLinePicker (random, never the same line twice in a row).
// - The community resource directory (AudienceKitClient.communityDirectory) is fetched whole, without sign-in, whenever
//   the app knows the city, and kept on the phone. "I need food", filtering by facet and opening a resource then happen
//   on the phone and send nothing.

/** The resource a flyer points at. [title] is neutral for a DV or stalking resource ([sensitive]). */
@Serializable
public data class FlyerResourceRef(val id: String, val title: String, val sensitive: Boolean = false)

/** One digital flyer. Its tone and category come from its tags, never from who is looking. */
@Serializable
public data class DigitalFlyer(
    val id: String,
    val headline: String,
    val body: String? = null,
    val linkUrl: String? = null,
    val linkLabel: String? = null,
    val tags: List<String> = emptyList(),
    /** gentle, health or playful. */
    val tone: String = "playful",
    /** The category a person can hide it by (FlyerCopy.categories). */
    val category: String = "community",
    /** The tone's lines, one shown at a time (FlyerLinePicker). */
    val lines: List<String> = emptyList(),
    val resource: FlyerResourceRef? = null,
) {
    /** No cheek: crisis, food, housing, health coverage, youth or DV. */
    val isGentle: Boolean get() = tone == "gentle"
}

/** What a CardKind.FLYERS card carries. */
@Serializable
public data class FlyersCardContent(
    /** Show on the card. It is about the flyer, never the app. */
    val disclosure: String,
    val explainerLabel: String,
    val explainerUrl: String,
    /** The pool, in rotation order. Drop what FlyerDismissals says before showing. */
    val flyers: List<DigitalFlyer> = emptyList(),
) {
    public fun visible(dismissals: FlyerDismissals): List<DigitalFlyer> = flyers.filter(dismissals::allows)
}

/**
 * Where FlyerDismissals keeps its lists: on the phone only. audiencekit-android's FlyerDismissalPreferences keeps
 * them in private shared preferences, excluded from backup.
 */
public interface FlyerDismissalStore {
    public fun load(key: String): List<String>
    public fun save(key: String, values: List<String>)
}

/** Keeps the lists in memory, for tests and apps that don't want them to outlive the process. */
public class InMemoryFlyerDismissalStore : FlyerDismissalStore {
    private val values = mutableMapOf<String, List<String>>()
    override fun load(key: String): List<String> = synchronized(values) { values[key].orEmpty() }
    override fun save(key: String, values: List<String>) { synchronized(this.values) { this.values[key] = values } }
}

/**
 * The flyers and categories dismissed on this phone. Never sent to the server, logged, counted or synced, because which
 * kinds of help someone hid is nobody else's business.
 */
public class FlyerDismissals(private val store: FlyerDismissalStore = InMemoryFlyerDismissalStore()) {
    public val dismissedFlyers: List<String> get() = store.load(FLYERS_KEY)
    public val hiddenCategories: Set<String> get() = store.load(CATEGORIES_KEY).toSet()

    public fun allows(flyer: DigitalFlyer): Boolean =
        flyer.category !in hiddenCategories && flyer.id !in dismissedFlyers

    @Synchronized
    public fun dismiss(flyer: DigitalFlyer) {
        store.save(FLYERS_KEY, (dismissedFlyers.filter { it != flyer.id } + flyer.id).takeLast(LIMIT))
    }

    @Synchronized
    public fun setHidden(category: String, hide: Boolean) {
        val hidden = if (hide) hiddenCategories + category else hiddenCategories - category
        store.save(CATEGORIES_KEY, hidden.sorted())
    }

    /** Shows every flyer and category again. */
    @Synchronized
    public fun reset() {
        store.save(FLYERS_KEY, emptyList())
        store.save(CATEGORIES_KEY, emptyList())
    }

    public companion object {
        public const val FLYERS_KEY: String = "audiencekit.flyers.dismissed"
        public const val CATEGORIES_KEY: String = "audiencekit.flyers.hiddenCategories"
        /** How many dismissed flyers it remembers; the oldest go first. */
        public const val LIMIT: Int = 500
    }
}

/** Picks the line a flyer shows: at random, never the line this phone showed last (unless it's the only one). */
public class FlyerLinePicker(
    private val store: FlyerDismissalStore = InMemoryFlyerDismissalStore(),
    private val random: Random = Random.Default,
) {
    @Synchronized
    public fun line(flyer: DigitalFlyer): String? {
        val picked = pick(flyer.lines, store.load(KEY).firstOrNull(), random)
        if (picked != null) store.save(KEY, listOf(picked))
        return picked
    }

    public companion object {
        public const val KEY: String = "audiencekit.flyers.lastLine"

        /** A random line other than [last], when there is another. */
        public fun pick(lines: List<String>, last: String?, random: Random = Random.Default): String? {
            val choices = if (lines.size > 1) lines.filter { it != last } else lines
            return if (choices.isEmpty()) null else choices[random.nextInt(choices.size)]
        }
    }
}

@Serializable
public data class FlyerCategory(val key: String, val label: String)

/** "I need...": a choice that goes straight to resources with these facets, filtered on the phone. */
@Serializable
public data class ResourceNeed(val key: String, val label: String, val facets: List<String> = emptyList())

/** The words around flyers and resources, from the server (legal review is pending, so none live in the apps). */
@Serializable
public data class FlyerCopy(
    val disclosure: String,
    val explainerLabel: String,
    val explainerUrl: String,
    val quickExit: String,
    val advocacy: List<String> = emptyList(),
    val categories: List<FlyerCategory> = emptyList(),
    val needs: List<ResourceNeed> = emptyList(),
)

/** One entry of a resource's hours or sessions. Days are 0 (Sunday) to 6; times HH:MM in the city's time zone. */
@Serializable
public data class ResourceSlot(
    val days: List<Int> = emptyList(),
    val from: String? = null,
    val until: String? = null,
    val place: String? = null,
    val address: String? = null,
    val note: String? = null,
)

@Serializable
public data class ResourceNextSession(
    val session: ResourceSlot,
    @SerialName("starts_at") val startsAt: String,
    @SerialName("ends_at") val endsAt: String,
)

/** A food pantry, shelter, clinic, STI testing, mental health, crisis or DV service. */
@Serializable
public data class CommunityResource(
    val id: String,
    /** Show this in lists, flyers and screen titles: a neutral title for a DV or stalking resource. */
    val title: String,
    /** Its real name, for its page body only. */
    val name: String,
    /** DV or stalking: show quick exit, keep it out of history, recents and favorites, use [title] for screen titles. */
    val sensitive: Boolean = false,
    val description: String? = null,
    val facets: List<String> = emptyList(),
    val address: String? = null,
    val latitude: Double? = null,
    val longitude: Double? = null,
    val phone: String? = null,
    @SerialName("text_number") val textNumber: String? = null,
    val url: String? = null,
    val hours: List<ResourceSlot> = emptyList(),
    val sessions: List<ResourceSlot> = emptyList(),
    @SerialName("intake_note") val intakeNote: String? = null,
    @SerialName("source_url") val sourceUrl: String? = null,
    /** yyyy-mm-dd; null until someone has checked it, and the app shows no date. */
    @SerialName("checked_at") val checkedAt: String? = null,
    @SerialName("next_session") val nextSession: ResourceNextSession? = null,
) {
    public fun has(facet: String): Boolean = facet in facets
}

@Serializable
public data class DirectoryLocale(val id: String, val name: String)

/** A city's community resource directory, kept on the phone and filtered there. */
@Serializable
public data class CommunityDirectory(
    val locale: DirectoryLocale,
    val resources: List<CommunityResource> = emptyList(),
    val facets: List<String> = emptyList(),
    val needs: List<ResourceNeed> = emptyList(),
    val advocacy: List<String> = emptyList(),
    @SerialName("quick_exit") val quickExit: String = "",
) {
    /** The resources for a need, filtered on the phone: nothing is sent. */
    public fun resourcesFor(need: ResourceNeed): List<CommunityResource> = resourcesWithAnyOf(need.facets)

    /** The resources with any of [facets] (all when empty), and all of [alsoRequiring]. */
    public fun resourcesWithAnyOf(facets: List<String>, alsoRequiring: List<String> = emptyList()): List<CommunityResource> =
        resources.filter { resource ->
            (facets.isEmpty() || facets.any(resource::has)) && alsoRequiring.all(resource::has)
        }
}

internal object FlyerQueries {
    const val FLYER_FIELDS: String = "disclosure explainerLabel explainerUrl " +
        "flyers { id headline body linkUrl linkLabel tags tone category lines resource { id title sensitive } }"

    val flyerCopy: String = """
        query FlyerCopy {
          flyerCopy {
            disclosure explainerLabel explainerUrl quickExit advocacy
            categories { key label } needs { key label facets }
          }
        }
    """.trimIndent()
}

@Serializable
internal data class FlyerCopyResponse(val flyerCopy: FlyerCopy)

/** The words around flyers and resources: settings categories, "I need..." choices, advocacy lines, quick exit. */
public suspend fun AudienceKitClient.flyerCopy(): FlyerCopy =
    graphQL(FlyerQueries.flyerCopy, FlyerCopyResponse.serializer(), operationName = "FlyerCopy").flyerCopy
