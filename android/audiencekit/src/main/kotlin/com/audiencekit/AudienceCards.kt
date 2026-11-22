package com.audiencekit

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull

// An audience's own cards (promoted, sponsored, charity and announcement cards in its apps' feeds), managed by its
// admins from a staff app such as Soapbox, the way Olympus Audience › Cards does. These documents run on the staff
// endpoint, which this SDK doesn't call: StaffKit's session sends them with these variables and the `parse`
// functions read the answers. The same as the Swift SDK's AudienceCore AudienceCards, word for word. A Soapbox
// publisher's ads come back in the same list from the API; [AudienceCards.parseCards] leaves them out.

/** A screen of the apps whose cards the server ranks: the API's `LayoutScreen`. */
public enum class AudienceCardScreen(public val title: String) {
    NOW("Now"),
    VENUES("Venues"),
    PEOPLE("People"),
    EVERYWHERE("Everywhere"),
    LOCALE("A city's page"),
    ;

    public companion object {
        public fun from(value: String?): AudienceCardScreen? = entries.firstOrNull { it.name == value }
    }
}

/** How much paid placement an audience's apps carry: the API's `AdvertisingMode`. */
public enum class AudienceCardsLevel(public val note: String) {
    AD_FREE("This audience is ad-free: only free charity cards, announcements and AudienceKit's own cards show."),
    OPEN("Venues, events and local sponsors may be promoted, labelled and at a flat rate."),
    SPONSORSHIPS("Sponsorships only: the audience's own venues and events, labelled Sponsored."),
    TRADITIONAL("Venues, events and local sponsors may be promoted, labelled and at a flat rate."),

    /** A mode this SDK doesn't know yet. */
    UNKNOWN(""),
    ;

    public companion object {
        public fun from(value: String?): AudienceCardsLevel = entries.firstOrNull { it.name == value } ?: UNKNOWN
    }
}

/** A category of card, as the audience publishes it (`CardCategory`). */
public data class AudienceCardCategory(
    val key: String,
    val label: String,
    val description: String? = null,
    val hideable: Boolean = true,
) {
    public companion object {
        /**
         * Categories a card made from a staff app can be: venue and event cards point at a venue or event, and
         * AudienceKit's own cards are booked by AudienceKit's administrators.
         */
        public val WRITABLE: Set<String> = setOf("health", "employment", "small_business", "charity", "announcement")

        /** The published list's defaults (config/promo_cards.yml), for before the audience's own list arrives. */
        public val DEFAULTS: List<AudienceCardCategory> = listOf(
            AudienceCardCategory("announcement", "Announcements", hideable = false),
            AudienceCardCategory("small_business", "Local businesses"),
            AudienceCardCategory("health", "Health"),
            AudienceCardCategory("employment", "Jobs"),
            AudienceCardCategory("charity", "Charities"),
        )
    }
}

/** Where an audience card stands, worked out from its dates and pause. */
public enum class AudienceCardStatus(public val title: String) {
    RUNNING("Running"),
    SCHEDULED("Scheduled"),
    PAUSED("Paused"),
    ENDED("Ended"),
}

/** One of the audience's own cards (`PromoPlacement` without a publication). */
public data class AudienceCard(
    val id: String,
    val category: String = "small_business",
    /** The badge it carries: Promoted, Sponsored, Charity, Announcement or From AudienceKit. */
    val label: String? = "Promoted",
    val sponsorName: String,
    val headline: String,
    val body: String? = null,
    val imageUrl: String? = null,
    val imageAlt: String? = null,
    val linkUrl: String? = null,
    val linkLabel: String? = null,
    /** `yyyy-MM-dd`. */
    val startsOn: String,
    val endsOn: String? = null,
    /** 0 (Sunday) to 6; empty is every night. */
    val weekdays: List<Int> = emptyList(),
    /** Empty is every screen. */
    val screens: List<AudienceCardScreen> = emptyList(),
    /** Empty is everywhere. */
    val localeIds: List<String> = emptyList(),
    val priceCents: Int = 0,
    val paused: Boolean = false,
    val paymentStatus: String? = null,
    val venue: Ref? = null,
    val event: Ref? = null,
    /** Set on a Soapbox publisher's ad, which isn't one of the audience's own cards. */
    val publication: Ref? = null,
    val weeklyViewers: List<PublisherAdWeek> = emptyList(),
) {
    public data class Ref(val id: String, val name: String? = null)

    /** Running, scheduled, paused or ended on [today] (`yyyy-MM-dd`, the audience's day). */
    public fun status(today: String): AudienceCardStatus = when {
        endsOn != null && endsOn < today -> AudienceCardStatus.ENDED
        paused -> AudienceCardStatus.PAUSED
        startsOn > today -> AudienceCardStatus.SCHEDULED
        else -> AudienceCardStatus.RUNNING
    }

    /** Whether a staff app may change it: not a venue's or event's card, and not AudienceKit's own. */
    public val editable: Boolean get() = category in AudienceCardCategory.WRITABLE && venue == null && event == null

    /** The newest closed week's viewers, for a list row. */
    public val lastWeek: PublisherAdWeek? get() = weeklyViewers.firstOrNull()
}

/**
 * What a new or changed card says, for [AudienceCards.saveVariables]. The API's `savePromoPlacement` replaces what
 * it's sent, so a change sends the whole card.
 */
public data class AudienceCardDraft(
    val id: String? = null,
    val category: String = "small_business",
    val sponsorName: String = "",
    val headline: String = "",
    val body: String? = null,
    /** An https link; null or "" for none. */
    val imageUrl: String? = null,
    val imageAlt: String? = null,
    val linkUrl: String? = null,
    val linkLabel: String? = null,
    val startsOn: String,
    /** Null is open-ended. */
    val endsOn: String? = null,
    val weekdays: List<Int> = emptyList(),
    val screens: List<AudienceCardScreen> = emptyList(),
    val localeIds: List<String> = emptyList(),
    val priceCents: Int = 0,
    val paused: Boolean = false,
) {
    /** What stops it saving, in words; empty when it can be sent. */
    public val problems: List<String>
        get() = buildList {
            fun blank(text: String?) = text.isNullOrBlank()
            if (blank(sponsorName)) add("Say who placed it.")
            if (blank(headline)) add("Add a headline.")
            for ((name, link) in listOf("picture" to imageUrl, "link" to linkUrl)) {
                if (!blank(link) && !link!!.lowercase().startsWith("https://")) add("The $name needs an https link.")
            }
            if (!blank(imageUrl) && blank(imageAlt)) add("Say what the picture shows.")
            if (endsOn != null && endsOn < startsOn) add("It ends before it starts.")
        }

    public companion object {
        /** A draft of [card] as it stands, to change it. */
        public fun of(card: AudienceCard): AudienceCardDraft = AudienceCardDraft(
            id = card.id, category = card.category, sponsorName = card.sponsorName, headline = card.headline,
            body = card.body, imageUrl = card.imageUrl, imageAlt = card.imageAlt, linkUrl = card.linkUrl,
            linkLabel = card.linkLabel, startsOn = card.startsOn, endsOn = card.endsOn, weekdays = card.weekdays,
            screens = card.screens, localeIds = card.localeIds, priceCents = card.priceCents, paused = card.paused,
        )
    }
}

/** What [AudienceCards.CARDS_QUERY] answers: the audience's own cards, its categories and advertising level. */
public data class AudienceCardList(
    val cards: List<AudienceCard>,
    val categories: List<AudienceCardCategory>,
    val level: AudienceCardsLevel,
)

/** The GraphQL for an audience's own cards, the same as the Swift SDK's. Only the audience's admins may. */
public object AudienceCards {
    public const val CARD_FIELDS: String = "id category label sponsorName headline body imageUrl imageAlt linkUrl " +
        "linkLabel startsOn endsOn weekdays screens localeIds priceCents paused paymentStatus venue { id name } " +
        "event { id name } publication { id name } weeklyViewers { weekStart viewers fewerThan }"

    public const val CARDS_QUERY: String = """
        # endpoint: staff
        query AudienceCards { advertising cardCategories { key label description hideable } promoPlacements { $CARD_FIELDS } }
    """

    public const val SAVE_MUTATION: String = """
        # endpoint: staff
        mutation AudienceSaveCard(${'$'}input: PromoPlacementSaveInput!) { savePromoPlacement(input: ${'$'}input) { promoPlacement { $CARD_FIELDS } } }
    """

    public const val DELETE_MUTATION: String = """
        # endpoint: staff
        mutation AudienceDeleteCard(${'$'}id: ID!) { deletePromoPlacement(input: { id: ${'$'}id }) { deletedId } }
    """

    // Variables

    public fun idVariables(id: String): Map<String, JsonElement> = mapOf("id" to JsonPrimitive(id))

    public fun saveVariables(draft: AudienceCardDraft): Map<String, JsonElement> {
        val input = linkedMapOf<String, JsonElement>(
            "category" to JsonPrimitive(draft.category),
            "sponsorName" to JsonPrimitive(draft.sponsorName.trim()),
            "headline" to JsonPrimitive(draft.headline.trim()),
            "startsOn" to JsonPrimitive(draft.startsOn),
            "endsOn" to (draft.endsOn?.let { JsonPrimitive(it) } ?: JsonNull),
            "weekdays" to JsonArray(draft.weekdays.sorted().map { JsonPrimitive(it) }),
            "screens" to JsonArray(draft.screens.map { JsonPrimitive(it.name) }),
            "localeIds" to JsonArray(draft.localeIds.map { JsonPrimitive(it) }),
            "priceCents" to JsonPrimitive(draft.priceCents),
            "paused" to JsonPrimitive(draft.paused),
        )
        draft.id?.let { input["id"] = JsonPrimitive(it) }
        for ((key, value) in listOf(
            "body" to draft.body, "imageUrl" to draft.imageUrl, "imageAlt" to draft.imageAlt,
            "linkUrl" to draft.linkUrl, "linkLabel" to draft.linkLabel,
        )) {
            input[key] = value?.trim()?.takeIf { it.isNotEmpty() }?.let { JsonPrimitive(it) } ?: JsonNull
        }
        return mapOf("input" to JsonObject(input))
    }

    // Answers

    /** [CARDS_QUERY]'s `data`, with publishers' ads left out. */
    public fun parseCards(data: JsonObject): AudienceCardList {
        val categories = data.array("cardCategories").orEmpty().mapNotNull { row ->
            val obj = row as? JsonObject ?: return@mapNotNull null
            AudienceCardCategory(
                obj.string("key") ?: return@mapNotNull null,
                obj.string("label").orEmpty(),
                obj.string("description"),
                obj.bool("hideable") ?: true,
            )
        }
        return AudienceCardList(
            cards = data.array("promoPlacements").orEmpty().mapNotNull { card(it as? JsonObject) }
                .filter { it.publication == null },
            categories = categories.ifEmpty { AudienceCardCategory.DEFAULTS },
            level = AudienceCardsLevel.from(data.string("advertising")),
        )
    }

    /** [SAVE_MUTATION]'s `data`. */
    public fun parseSave(data: JsonObject): AudienceCard? = card(data.obj("savePromoPlacement")?.obj("promoPlacement"))

    /** [DELETE_MUTATION]'s `data`. */
    public fun parseDelete(data: JsonObject): String? = data.obj("deletePromoPlacement")?.string("deletedId")

    private fun card(obj: JsonObject?): AudienceCard? {
        obj ?: return null
        fun ref(key: String) = obj.obj(key)?.let { ref -> ref.string("id")?.let { AudienceCard.Ref(it, ref.string("name")) } }
        fun strings(key: String) = obj.array(key).orEmpty().mapNotNull { (it as? JsonPrimitive)?.contentOrNull }
        return AudienceCard(
            id = obj.string("id") ?: return null,
            category = obj.string("category") ?: "small_business",
            label = obj.string("label"),
            sponsorName = obj.string("sponsorName").orEmpty(),
            headline = obj.string("headline").orEmpty(),
            body = obj.string("body"),
            imageUrl = obj.string("imageUrl"),
            imageAlt = obj.string("imageAlt"),
            linkUrl = obj.string("linkUrl"),
            linkLabel = obj.string("linkLabel"),
            startsOn = obj.string("startsOn").orEmpty(),
            endsOn = obj.string("endsOn"),
            weekdays = obj.array("weekdays").orEmpty().mapNotNull { (it as? JsonPrimitive)?.intOrNull },
            screens = strings("screens").mapNotNull { AudienceCardScreen.from(it) },
            localeIds = strings("localeIds"),
            priceCents = obj.int("priceCents") ?: 0,
            paused = obj.bool("paused") ?: false,
            paymentStatus = obj.string("paymentStatus"),
            venue = ref("venue"),
            event = ref("event"),
            publication = ref("publication"),
            weeklyViewers = obj.array("weeklyViewers").orEmpty().mapNotNull { row ->
                val week = row as? JsonObject ?: return@mapNotNull null
                PublisherAdWeek(week.string("weekStart") ?: return@mapNotNull null, week.int("viewers"), week.int("fewerThan"))
            },
        )
    }

    private fun JsonObject.obj(key: String): JsonObject? = this[key] as? JsonObject
    private fun JsonObject.array(key: String): JsonArray? = this[key] as? JsonArray
    private fun JsonObject.string(key: String): String? = (this[key] as? JsonPrimitive)?.takeIf { it.isString }?.content
    private fun JsonObject.int(key: String): Int? = (this[key] as? JsonPrimitive)?.intOrNull
    private fun JsonObject.bool(key: String): Boolean? = (this[key] as? JsonPrimitive)?.booleanOrNull
}

/** The words a staff app shows around the audience's cards, the same as the Swift SDK's. */
public object AudienceCardsCopy {
    public const val CARDS: String = "Cards"
    public const val NEW_CARD: String = "New card"
    public const val NO_CARDS: String = "No cards yet. Cards show between the apps' own rows, at most two a screen, " +
        "never first."
    public const val VIEWERS_NOTE: String = "Viewers: different people who saw the card each week (Monday to Sunday). " +
        "Under 20 shows as fewer than 20."
    public const val NOT_EDITABLE: String = "This card is a venue's or event's, or AudienceKit's own: change it in Olympus."
    public const val EVERY_SCREEN: String = "Every screen"
    public const val EVERYWHERE: String = "Everywhere"

    /** "1,204 viewers" or "Fewer than 20 viewers". */
    public fun viewers(week: PublisherAdWeek): String =
        week.viewers?.let { "%,d viewer%s".format(it, if (it == 1) "" else "s") }
            ?: "Fewer than ${week.fewerThan ?: 20} viewers"
}
