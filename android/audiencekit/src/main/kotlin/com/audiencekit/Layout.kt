package com.audiencekit

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlin.coroutines.cancellation.CancellationException

// Server-driven cards (the API's doc/plans/SERVER_DRIVEN_CARDS_PLAN.md). The server ranks the cards of a screen (Now,
// Venues, People) for this moment and the app draws them in that order. A card points at records the app already loads
// (by id), so the layout call stays small and the app's own queries stay the source of the content.
//
// - The app says which kinds it can draw (CardRegistry.kinds); the server never sends another kind, and the client
//   skips one it doesn't know anyway.
// - When the layout can't be fetched (offline, an error, past LayoutClient.timeoutMillis), LayoutClient returns the
//   app's built-in order instead, so the screen fills either way.
// - Promoted cards come in slots with ranked candidates. The app draws the first one whose category the viewer hasn't
//   turned off (CardFilter); what they turned off stays on the device and is never sent.

/** A screen whose cards the server ranks. */
public enum class LayoutScreen { NOW, VENUES, PEOPLE }

/** The card kinds the API knows of today. `kind` is a string, so a newer API can add kinds; an app lists the ones it draws. */
public object CardKind {
    public const val NOW_STAGE: String = "now.stage"
    public const val NOW_CHAT: String = "now.chat"
    public const val NOW_SMALL_TALK: String = "now.smallTalk"
    public const val POSTS_TONIGHT: String = "posts.tonight"
    public const val POSTS_LOCALE: String = "posts.locale"
    public const val EVENTS_UPCOMING: String = "events.upcoming"
    public const val VENUES_NEARBY: String = "venues.nearby"
    public const val VENUES_FRIENDS: String = "venues.friends"
    public const val VENUES_TONIGHT: String = "venues.tonight"
    public const val VENUES_ALL: String = "venues.all"
    public const val VENUES_THIN_CITY: String = "venues.thinCity"
    public const val PEOPLE_PLAYING_THIS_WEEK: String = "people.playingThisWeek"
    public const val PEOPLE_BASED_HERE: String = "people.basedHere"
    public const val PEOPLE_EVERYONE: String = "people.everyone"
    public const val PINGS: String = "pings"
    public const val WEB: String = "web"
    public const val PROMO_SLOT: String = "promo.slot"
}

/**
 * The words, picture and link of a web card (the audience's own announcement) or a promoted card. Links and images are
 * https; open the link in a Custom Tab, never an embedded web view.
 */
@Serializable
public data class CardContent(
    val headline: String,
    val body: String? = null,
    val imageUrl: String? = null,
    /** What the picture shows, for screen readers. */
    val imageAlt: String? = null,
    val linkUrl: String? = null,
    /** The link's button text. */
    val linkLabel: String? = null,
)

/**
 * A promoted or charity card, one of a promo slot's candidates. Show [label] and the category's name as the server
 * sends them: they can change without an app release.
 */
public data class PromoCard(
    /** The placement, as [recordCardViews] takes it. */
    val id: String,
    /** One of [cardCategories]' keys: venue, event, health, employment, small_business, charity. */
    val category: String,
    /** Its badge, e.g. "Promoted" or "Charity". */
    val label: String,
    /** Who placed it. */
    val sponsorName: String,
    val content: CardContent,
    /** The venue it promotes, for a venue card. */
    val venueId: String? = null,
    /** The event it promotes, for an event card. */
    val eventId: String? = null,
)

/**
 * One card of a screen, in rank order. It carries the ids of the records it's about (load them as before), a web
 * card's content, or a promo slot's candidates.
 */
public data class LayoutCard(
    /** Stable for this card in its place, e.g. `now.chat:<venue id>`. */
    val id: String,
    /** What it is ([CardKind]). */
    val kind: String,
    /** Its place, from 1 at the top. */
    val rank: Int,
    /** A heading to use instead of the app's own, when the server sends one. */
    val title: String? = null,
    val venueId: String? = null,
    val eventId: String? = null,
    val localeId: String? = null,
    /** A venues card's venues, in the order to show them. */
    val venueIds: List<String> = emptyList(),
    /** An events card's events, soonest first. */
    val eventIds: List<String> = emptyList(),
    /** A people card's people, in the order to show them. */
    val personIds: List<String> = emptyList(),
    /** A web card's announcement. */
    val web: CardContent? = null,
    /** A promo slot's candidates, in the order to try them. */
    val candidates: List<PromoCard> = emptyList(),
    /**
     * True for a card of the app's built-in order, used when the layout couldn't be fetched: it carries no ids, so
     * draw it from the app's own data.
     */
    val isFallback: Boolean = false,
) {
    /** The candidate to draw in a promo slot: the first the filter allows, or null to draw nothing. */
    public fun promo(filter: CardFilter): PromoCard? = candidates.firstOrNull { filter.allows(it.category) }

    public companion object {
        /** A card of the built-in order: nothing but its kind. */
        public fun fallback(kind: String, rank: Int): LayoutCard =
            LayoutCard(id = "fallback:$kind", kind = kind, rank = rank, isFallback = true)
    }
}

/** A screen's cards, top first. */
public data class Layout(
    /** This ranking, for [recordCardViews]. Null for the built-in order. */
    val id: String?,
    val cards: List<LayoutCard>,
    /** Seconds until the app should ask again. */
    val refreshAfter: Int = 60,
) {
    /** Whether this is the built-in order rather than the server's. */
    val isFallback: Boolean get() = id == null

    /** The first card of a kind. */
    public fun card(kind: String): LayoutCard? = cards.firstOrNull { it.kind == kind }

    public companion object {
        /** The app's built-in order, used when the server's can't be had. */
        public fun fallback(kinds: List<String>, refreshAfter: Int = 60): Layout =
            Layout(null, kinds.mapIndexed { index, kind -> LayoutCard.fallback(kind, index + 1) }, refreshAfter)
    }
}

/**
 * A category of promoted card, from the audience's published list, for the app's "Cards you see" settings. Show the
 * label and description as sent.
 */
@Serializable
public data class CardCategory(
    /** The category cards carry: venue, health, charity, ... */
    val key: String,
    /** Its name, e.g. "Health". */
    val label: String,
    /** Examples, e.g. "STI testing, PrEP clinics". */
    val description: String = "",
    /** Whether people can turn it off. Never announcements; not by default venues and events. */
    val hideable: Boolean = false,
)

/**
 * Which promoted cards the viewer will see: every category but the hideable ones they turned off. Built on the device
 * from what they chose; it never leaves the device.
 */
public data class CardFilter(
    val hidden: Set<String> = emptySet(),
    /**
     * The published categories, when they've loaded. A category it lists as not hideable is always shown, even if it
     * was hidden before the audience changed that; until they load, every hidden category is honoured.
     */
    val categories: List<CardCategory>? = null,
) {
    public fun allows(category: String): Boolean {
        if (category !in hidden) return true
        val categories = categories ?: return false
        return categories.firstOrNull { it.key == category }?.hideable == false
    }

    public companion object {
        /** Shows everything. */
        public val NONE: CardFilter = CardFilter()
    }
}

/**
 * The cards an app can draw, and what each becomes: for Compose, a sealed type the screen switches on is a good [R].
 * Register every kind the app draws; its [kinds] go to the server, and [render] skips the rest.
 */
public class CardRegistry<R : Any> {
    private val renderers = LinkedHashMap<String, (LayoutCard) -> R?>()

    /** Draws [kind] with [render]; returning null leaves the card out (a promo slot whose candidates are all hidden). */
    public fun register(kind: String, render: (LayoutCard) -> R?): CardRegistry<R> = apply { renderers[kind] = render }

    /** Every kind registered, in the order registered. */
    public val kinds: List<String> get() = renderers.keys.toList()

    public fun canRender(kind: String): Boolean = kind in renderers

    /** The card drawn, or null for a kind this app doesn't know or a card it leaves out. */
    public fun render(card: LayoutCard): R? = renderers[card.kind]?.invoke(card)

    /** The layout's cards drawn in order, leaving out unknown kinds. */
    public fun render(layout: Layout): List<Pair<LayoutCard, R>> =
        layout.cards.mapNotNull { card -> render(card)?.let { card to it } }
}

/** Fetches a screen's layout, falling back to the app's built-in order when it can't. */
public class LayoutClient(
    private val client: AudienceKitClient,
    public val screen: LayoutScreen,
    /** Every kind the app draws ([CardRegistry.kinds]). */
    public val cardKinds: List<String>,
    /** The app's built-in order for this screen, used offline, on an error, or past [timeoutMillis]. */
    public val fallback: List<String>,
    /** The app's marketing version, for the server's logs. */
    public val appVersion: String? = null,
    public val timeoutMillis: Long = 2_000,
) {
    /**
     * The server's layout for where the device is (or the app's locale when there's no position), with any kind the
     * app didn't list left out; the built-in order when that fails. Never throws but on cancellation: the screen fills
     * either way.
     */
    public suspend fun load(position: Coordinates? = null, localeId: String? = null): Layout {
        val fetched = (
            try {
                withTimeoutOrNull(timeoutMillis) { client.layout(screen, cardKinds, position, localeId, appVersion) }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                null
            }
            ) ?: return Layout.fallback(fallback)
        val known = cardKinds.toSet()
        return fetched.copy(cards = fetched.cards.filter { it.kind in known })
    }
}

/**
 * Reports the promoted cards the viewer saw: each on screen for a second or more, once per layout, signed in only.
 * Call [appeared] and [disappeared] as a promo card comes and goes.
 */
public class PromoViewRecorder(
    private val client: AudienceKitClient,
    private val scope: CoroutineScope,
    private val minimumOnScreenMillis: Long = 1_000,
) {
    private val mutex = Mutex()
    private val visible = mutableMapOf<String, Job>()
    private val reported = mutableSetOf<String>()
    private val pending = mutableMapOf<String, String?>()
    private var flushing: Job? = null

    public fun appeared(promoId: String, layoutId: String?) {
        val key = "${layoutId.orEmpty()}:$promoId"
        scope.launch {
            mutex.withLock {
                if (visible.containsKey(promoId) || key in reported) return@launch
                visible[promoId] = scope.launch {
                    delay(minimumOnScreenMillis)
                    seen(promoId, layoutId, key)
                }
            }
        }
    }

    public fun disappeared(promoId: String) {
        scope.launch { mutex.withLock { visible.remove(promoId)?.cancel() } }
    }

    private suspend fun seen(promoId: String, layoutId: String?, key: String) {
        mutex.withLock {
            visible.remove(promoId)
            if (client.sessionToken() == null || !reported.add(key)) return
            pending[promoId] = layoutId
            if (flushing != null) return
            flushing = scope.launch {
                delay(500)
                flush()
            }
        }
    }

    private suspend fun flush() {
        val batch = mutex.withLock {
            flushing = null
            pending.toMap().also { pending.clear() }
        }
        // One call per layout; the API takes ten at a time.
        batch.entries.groupBy({ it.value }, { it.key }).forEach { (layoutId, ids) ->
            ids.chunked(10).forEach { chunk ->
                try {
                    client.recordCardViews(chunk, layoutId)
                } catch (e: CancellationException) {
                    throw e
                } catch (_: Exception) {
                }
            }
        }
    }
}

// Operations

internal object LayoutQueries {
    const val CARD_CONTENT_FIELDS: String = "headline body imageUrl imageAlt linkUrl linkLabel"

    val layout: String = """
        query Layout(${'$'}screen: LayoutScreen!, ${'$'}client: LayoutClientInput!, ${'$'}position: CoordinatesInput, ${'$'}localeId: ID) {
          layout(screen: ${'$'}screen, client: ${'$'}client, position: ${'$'}position, localeId: ${'$'}localeId) {
            id refreshAfter
            cards {
              id kind rank title
              ... on StageCard { stageEvent: event { id } venue { id } }
              ... on ChatCard { event { id } venue { id } locale { id } }
              ... on PostsCard { event { id } venue { id } locale { id } }
              ... on EventsCard { events { id } venue { id } locale { id } }
              ... on VenuesCard { venues { id } locale { id } }
              ... on PeopleCard { people { id } locale { id } }
              ... on WebCard { $CARD_CONTENT_FIELDS }
              ... on PromoSlotCard {
                candidates { id category label sponsorName $CARD_CONTENT_FIELDS venue { id } event { id } }
              }
            }
          }
        }
    """.trimIndent()

    val cardCategories: String = """
        query CardCategories {
          cardCategories { key label description hideable }
        }
    """.trimIndent()

    val recordCardViews: String = """
        mutation RecordCardViews(${'$'}promoIds: [ID!]!, ${'$'}layoutId: ID) {
          recordCardViews(input: { promoIds: ${'$'}promoIds, layoutId: ${'$'}layoutId }) { recorded }
        }
    """.trimIndent()
}

@Serializable
internal data class IdRef(val id: String)

@Serializable
internal data class PromoCardWire(
    val id: String,
    val category: String,
    val label: String,
    val sponsorName: String = "",
    val headline: String,
    val body: String? = null,
    val imageUrl: String? = null,
    val imageAlt: String? = null,
    val linkUrl: String? = null,
    val linkLabel: String? = null,
    val venue: IdRef? = null,
    val event: IdRef? = null,
) {
    fun toPromoCard() = PromoCard(
        id = id,
        category = category,
        label = label,
        sponsorName = sponsorName,
        content = CardContent(headline, body, imageUrl, imageAlt, linkUrl, linkLabel),
        venueId = venue?.id,
        eventId = event?.id,
    )
}

@Serializable
internal data class LayoutCardWire(
    val id: String,
    val kind: String,
    val rank: Int = 0,
    val title: String? = null,
    val venue: IdRef? = null,
    val event: IdRef? = null,
    val stageEvent: IdRef? = null,
    val locale: IdRef? = null,
    val venues: List<IdRef>? = null,
    val events: List<IdRef>? = null,
    val people: List<IdRef>? = null,
    val headline: String? = null,
    val body: String? = null,
    val imageUrl: String? = null,
    val imageAlt: String? = null,
    val linkUrl: String? = null,
    val linkLabel: String? = null,
    // Decoded one by one, so one bad candidate (a field a newer API changed) loses that candidate, not the slot.
    val candidates: List<JsonElement>? = null,
) {
    fun toCard() = LayoutCard(
        id = id,
        kind = kind,
        rank = rank,
        title = title,
        venueId = venue?.id,
        eventId = (stageEvent ?: event)?.id,
        localeId = locale?.id,
        venueIds = venues.orEmpty().map { it.id },
        eventIds = events.orEmpty().map { it.id },
        personIds = people.orEmpty().map { it.id },
        web = headline?.let { CardContent(it, body, imageUrl, imageAlt, linkUrl, linkLabel) },
        candidates = candidates.orEmpty().mapNotNull { element ->
            runCatching { AudienceKitClient.json.decodeFromJsonElement(PromoCardWire.serializer(), element) }
                .getOrNull()?.toPromoCard()
        },
    )
}

@Serializable
internal data class LayoutWire(val id: String, val refreshAfter: Int = 60, val cards: List<JsonElement> = emptyList())

@Serializable
internal data class LayoutResponse(val layout: LayoutWire)

@Serializable
internal data class CardCategoriesResponse(val cardCategories: List<CardCategory> = emptyList())

@Serializable
internal data class RecordCardViewsPayload(val recorded: Int = 0)

@Serializable
internal data class RecordCardViewsResponse(val recordCardViews: RecordCardViewsPayload? = null)

/**
 * A screen's cards, ranked by the server for where the device is (or [localeId] when it has no position). Only kinds in
 * [cardKinds] come back. [LayoutClient] adds the timeout and the fallback order.
 */
public suspend fun AudienceKitClient.layout(
    screen: LayoutScreen,
    cardKinds: List<String>,
    position: Coordinates? = null,
    localeId: String? = null,
    appVersion: String? = null,
): Layout {
    val variables = buildMap<String, JsonElement> {
        put("screen", JsonPrimitive(screen.name))
        put(
            "client",
            JsonObject(
                buildMap {
                    put("cardKinds", JsonArray(cardKinds.map(::JsonPrimitive)))
                    appVersion?.let { put("appVersion", JsonPrimitive(it)) }
                },
            ),
        )
        position?.let { put("position", it.toGraphQLValue()) }
        localeId?.let { put("localeId", JsonPrimitive(it)) }
    }
    val wire = graphQL(LayoutQueries.layout, LayoutResponse.serializer(), variables, "Layout").layout
    val cards = wire.cards.mapNotNull { element ->
        runCatching { AudienceKitClient.json.decodeFromJsonElement(LayoutCardWire.serializer(), element) }
            .getOrNull()?.toCard()
    }
    return Layout(wire.id, cards.sortedBy { it.rank }, wire.refreshAfter)
}

/** The published categories of promoted cards, in the audience's words, for "Cards you see". */
public suspend fun AudienceKitClient.cardCategories(): List<CardCategory> =
    graphQL(LayoutQueries.cardCategories, CardCategoriesResponse.serializer(), operationName = "CardCategories")
        .cardCategories

/** Says which promoted cards were on screen (send only those actually shown, at most 10). Signed in only. */
public suspend fun AudienceKitClient.recordCardViews(promoIds: List<String>, layoutId: String?): Int {
    val variables = buildMap<String, JsonElement> {
        put("promoIds", JsonArray(promoIds.map(::JsonPrimitive)))
        layoutId?.let { put("layoutId", JsonPrimitive(it)) }
    }
    return graphQL(LayoutQueries.recordCardViews, RecordCardViewsResponse.serializer(), variables, "RecordCardViews")
        .recordCardViews?.recorded ?: 0
}
