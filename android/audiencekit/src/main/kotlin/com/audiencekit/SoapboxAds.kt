package com.audiencekit

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull

// Soapbox publishers' ads, rate sheet and media library, managed from the Soapbox app (API doc/SOAPBOX.md "Publisher
// ads and the media library"). These documents run on the staff endpoint, which this SDK doesn't call: StaffKit's
// session sends them with these variables and the `parse` functions read the answers. The same as the Swift SDK's
// AudienceCore SoapboxAds, word for word.

/** Where a publisher's ad shows on its own content: the API's `PublisherAdSpot`. */
public enum class PublisherAdSpot(public val title: String) {
    /** In the article reader, after the body: one ad an article view. */
    ARTICLE("After articles"),

    /** On the publication's page, below its masthead. */
    PUBLICATION("Publication page"),
    ;

    public companion object {
        public fun from(value: String?): PublisherAdSpot? = entries.firstOrNull { it.name == value }
    }
}

/** Where a publisher's ad stands: the API's `PublisherAdStatus`. */
public enum class PublisherAdStatus(public val title: String) {
    IN_REVIEW("In review"),
    REJECTED("Turned down"),
    SCHEDULED("Scheduled"),
    RUNNING("Running"),
    PAUSED("Paused"),
    ENDED("Ended"),
    REMOVED("Taken down"),

    /** A status this SDK doesn't know yet. */
    UNKNOWN("Unknown"),
    ;

    public companion object {
        public fun from(value: String?): PublisherAdStatus = entries.firstOrNull { it.name == value } ?: UNKNOWN

        /** The lists the Soapbox app shows, in order. */
        public val LISTED: List<PublisherAdStatus> = listOf(RUNNING, SCHEDULED, IN_REVIEW, PAUSED, REJECTED, ENDED, REMOVED)
    }
}

/** Whether an audience's publishers sell ads, and which of their ads its admins review first: `PublisherAdsMode`. */
public enum class PublisherAdsMode(public val title: String) {
    OFF("Off"),
    REVIEW_ALL("Review every ad"),
    REVIEW_PENDING("Review pending publications' ads"),
    ;

    public companion object {
        public fun from(value: String?): PublisherAdsMode? = entries.firstOrNull { it.name == value }
    }
}

/** The one number a sponsor gets: different readers who saw the ad in a week (Monday to Sunday, UTC). */
public data class PublisherAdWeek(val weekStart: String, val viewers: Int? = null, val fewerThan: Int? = null) {
    /** "1,204 readers" or "Fewer than 20 readers". */
    public val readersLine: String
        get() = viewers?.let { "%,d reader%s".format(it, if (it == 1) "" else "s") }
            ?: "Fewer than ${fewerThan ?: 20} readers"
}

/** A publication's ad, as its managers and the audience's admins see it. */
public data class PublisherAd(
    val id: String,
    val adStatus: PublisherAdStatus = PublisherAdStatus.RUNNING,
    val spot: PublisherAdSpot? = PublisherAdSpot.ARTICLE,
    val category: String = "small_business",
    val sponsorName: String,
    val sponsorEmail: String? = null,
    val headline: String,
    val body: String? = null,
    val imageUrl: String? = null,
    val imageAlt: String? = null,
    val linkUrl: String? = null,
    val linkLabel: String? = null,
    /** Only on these of the publication's articles; empty is all. */
    val articleIds: List<String> = emptyList(),
    /** `yyyy-MM-dd`. */
    val startsOn: String,
    val endsOn: String? = null,
    /** 0 (Sunday) to 6; empty is every day. */
    val weekdays: List<Int> = emptyList(),
    val priceCents: Int = 0,
    val soldOutside: Boolean = true,
    val paused: Boolean = false,
    val reviewNote: String? = null,
    val publication: PublicationRef? = null,
    val weeklyViewers: List<PublisherAdWeek> = emptyList(),
) {
    public data class PublicationRef(val id: String, val name: String)

    /** The newest closed week's readers, for a list row. */
    public val lastWeek: PublisherAdWeek? get() = weeklyViewers.firstOrNull()
}

/** One spot on a publication's public rate sheet. [weeklyCents] is null when not listed. */
public data class PublicationRate(val spot: PublisherAdSpot, val weeklyCents: Int? = null, val slots: Int = 4)

/** A publication's public rate sheet: flat weekly prices, never per view or tap. All of the money is the publication's. */
public data class PublicationRateSheet(
    val notes: String? = null,
    val contactEmail: String? = null,
    val rates: List<PublicationRate> = emptyList(),
) {
    public fun rateFor(spot: PublisherAdSpot): PublicationRate = rates.firstOrNull { it.spot == spot } ?: PublicationRate(spot)
}

/** A picture in a publication's media library, for its articles and ads. */
public data class PublicationMediaItem(
    val id: String,
    val url: String,
    val altText: String? = null,
    val caption: String? = null,
    val credit: String? = null,
    val createdAt: String? = null,
)

/** What a new or changed ad says, for [SoapboxAds.saveAdVariables]. Null leaves a field as it is on a change. */
public data class PublisherAdDraft(
    val id: String? = null,
    val publicationId: String? = null,
    val spot: PublisherAdSpot? = null,
    val category: String? = null,
    val sponsorName: String? = null,
    val sponsorEmail: String? = null,
    val headline: String? = null,
    val body: String? = null,
    /** A data: URI upload or an https link; "" removes the picture. */
    val image: String? = null,
    val imageMediaId: String? = null,
    val imageAlt: String? = null,
    val linkUrl: String? = null,
    val linkLabel: String? = null,
    val articleIds: List<String>? = null,
    val startsOn: String? = null,
    /** "" clears the end date. */
    val endsOn: String? = null,
    val weekdays: List<Int>? = null,
    val priceCents: Int? = null,
    val paused: Boolean? = null,
    val dryRun: Boolean = false,
)

/** What [SoapboxAds.ADS_QUERY] answers. */
public data class PublicationAds(
    val ads: List<PublisherAd>,
    val adsEnabled: Boolean,
    val adsNeedReview: Boolean,
    val rateSheet: PublicationRateSheet,
)

/** What [SoapboxAds.REVIEW_QUEUE_QUERY] answers; empty for someone who isn't the audience's admin. */
public data class PublisherAdReviewQueue(val queue: List<PublisherAd>, val mode: PublisherAdsMode)

/** What [SoapboxAds.SAVE_AD_MUTATION] answers: the ad, or why it can't run as it is. */
public data class PublisherAdSaveResult(val ad: PublisherAd?, val problems: List<String>)

/** The GraphQL for Soapbox publishers' ads, rate sheet and media library, the same as the Swift SDK's. */
public object SoapboxAds {
    /** The categories a publisher's ad may be, with their names. */
    public val CATEGORIES: List<Pair<String, String>> = listOf(
        "small_business" to "Local business",
        "health" to "Health",
        "employment" to "Jobs",
        "charity" to "Charity",
    )

    public const val AD_FIELDS: String = "id adStatus spot category sponsorName sponsorEmail headline body imageUrl " +
        "imageAlt linkUrl linkLabel articleIds startsOn endsOn weekdays priceCents soldOutside paused reviewNote " +
        "publication { id name } weeklyViewers { weekStart viewers fewerThan }"
    public const val RATE_SHEET_FIELDS: String = "rateSheet { notes contactEmail rates { spot weeklyCents slots } }"
    public const val MEDIA_FIELDS: String = "id url altText caption credit createdAt"

    public const val ADS_QUERY: String = """
        # endpoint: staff
        query SoapboxAds(${'$'}id: ID!) { soapbox { publication(id: ${'$'}id) { id adsEnabled adsNeedReview $RATE_SHEET_FIELDS ads { $AD_FIELDS } } } }
    """

    public const val MEDIA_QUERY: String = """
        # endpoint: staff
        query SoapboxMedia(${'$'}id: ID!) { soapbox { publication(id: ${'$'}id) { id media { $MEDIA_FIELDS } } } }
    """

    public const val REVIEW_QUEUE_QUERY: String = """
        # endpoint: staff
        query SoapboxAdReviewQueue { soapbox { publisherAds adReviewQueue { $AD_FIELDS } } }
    """

    public const val SAVE_AD_MUTATION: String = """
        # endpoint: staff
        mutation SoapboxSaveAd(${'$'}input: PublicationAdSaveInput!) { savePublicationAd(input: ${'$'}input) { problems ad { $AD_FIELDS } } }
    """

    public const val DELETE_AD_MUTATION: String = """
        # endpoint: staff
        mutation SoapboxDeleteAd(${'$'}id: ID!) { deletePublicationAd(input: { id: ${'$'}id }) { ad { id } } }
    """

    public const val REVIEW_AD_MUTATION: String = """
        # endpoint: staff
        mutation SoapboxReviewAd(${'$'}id: ID!, ${'$'}approve: Boolean!, ${'$'}note: String) { reviewPublicationAd(input: { id: ${'$'}id, approve: ${'$'}approve, note: ${'$'}note }) { ad { $AD_FIELDS } } }
    """

    public const val REMOVE_AD_MUTATION: String = """
        # endpoint: staff
        mutation SoapboxRemoveAd(${'$'}id: ID!, ${'$'}removed: Boolean!, ${'$'}note: String) { removePublicationAd(input: { id: ${'$'}id, removed: ${'$'}removed, note: ${'$'}note }) { ad { $AD_FIELDS } } }
    """

    public const val ENABLE_ADS_MUTATION: String = """
        # endpoint: staff
        mutation SoapboxEnableAds(${'$'}id: ID!, ${'$'}enabled: Boolean!) { enablePublicationAds(input: { id: ${'$'}id, enabled: ${'$'}enabled }) { publication { id adsEnabled } } }
    """

    public const val SET_MODE_MUTATION: String = """
        # endpoint: staff
        mutation SoapboxSetPublisherAds(${'$'}mode: PublisherAdsMode!) { setSoapboxPublisherAds(input: { mode: ${'$'}mode }) { mode } }
    """

    public const val SAVE_RATE_SHEET_MUTATION: String = """
        # endpoint: staff
        mutation SoapboxSaveRateSheet(${'$'}input: PublicationRateSheetSaveInput!) { savePublicationRateSheet(input: ${'$'}input) { publication { id $RATE_SHEET_FIELDS } } }
    """

    public const val ADD_MEDIA_MUTATION: String = """
        # endpoint: staff
        mutation SoapboxAddMedia(${'$'}input: PublicationMediaAddInput!) { addPublicationMedia(input: ${'$'}input) { media { $MEDIA_FIELDS } } }
    """

    public const val UPDATE_MEDIA_MUTATION: String = """
        # endpoint: staff
        mutation SoapboxUpdateMedia(${'$'}input: PublicationMediaUpdateInput!) { updatePublicationMedia(input: ${'$'}input) { media { $MEDIA_FIELDS } } }
    """

    public const val DELETE_MEDIA_MUTATION: String = """
        # endpoint: staff
        mutation SoapboxDeleteMedia(${'$'}id: ID!) { deletePublicationMedia(input: { id: ${'$'}id }) { media { id } } }
    """

    // Variables

    public fun idVariables(id: String): Map<String, JsonElement> = mapOf("id" to JsonPrimitive(id))

    public fun saveAdVariables(draft: PublisherAdDraft): Map<String, JsonElement> {
        val input = linkedMapOf<String, JsonElement>()
        fun put(key: String, value: String?) { value?.let { input[key] = JsonPrimitive(it) } }
        put("id", draft.id)
        put("publicationId", draft.publicationId)
        put("spot", draft.spot?.name)
        put("category", draft.category)
        put("sponsorName", draft.sponsorName)
        put("sponsorEmail", draft.sponsorEmail)
        put("headline", draft.headline)
        put("body", draft.body)
        put("image", draft.image)
        put("imageMediaId", draft.imageMediaId)
        put("imageAlt", draft.imageAlt)
        put("linkUrl", draft.linkUrl)
        put("linkLabel", draft.linkLabel)
        put("startsOn", draft.startsOn)
        draft.endsOn?.let { input["endsOn"] = if (it.isEmpty()) JsonNull else JsonPrimitive(it) }
        draft.articleIds?.let { ids -> input["articles"] = JsonArray(ids.map { JsonPrimitive(it) }) }
        draft.weekdays?.let { days -> input["weekdays"] = JsonArray(days.sorted().map { JsonPrimitive(it) }) }
        draft.priceCents?.let { input["priceCents"] = JsonPrimitive(it) }
        draft.paused?.let { input["paused"] = JsonPrimitive(it) }
        if (draft.dryRun) input["dryRun"] = JsonPrimitive(true)
        return mapOf("input" to JsonObject(input))
    }

    public fun reviewVariables(id: String, approve: Boolean, note: String? = null): Map<String, JsonElement> = buildMap {
        put("id", JsonPrimitive(id))
        put("approve", JsonPrimitive(approve))
        trimmed(note)?.let { put("note", JsonPrimitive(it)) }
    }

    public fun removeVariables(id: String, removed: Boolean = true, note: String? = null): Map<String, JsonElement> = buildMap {
        put("id", JsonPrimitive(id))
        put("removed", JsonPrimitive(removed))
        trimmed(note)?.let { put("note", JsonPrimitive(it)) }
    }

    public fun enableVariables(publicationId: String, enabled: Boolean): Map<String, JsonElement> =
        mapOf("id" to JsonPrimitive(publicationId), "enabled" to JsonPrimitive(enabled))

    public fun modeVariables(mode: PublisherAdsMode): Map<String, JsonElement> = mapOf("mode" to JsonPrimitive(mode.name))

    /** A spot's weekly price (null unlists it) and slots, for [SAVE_RATE_SHEET_MUTATION]. */
    public fun rateSheetVariables(publicationId: String, sheet: PublicationRateSheet): Map<String, JsonElement> {
        val input = linkedMapOf<String, JsonElement>("id" to JsonPrimitive(publicationId))
        sheet.rates.forEach { rate ->
            val prefix = if (rate.spot == PublisherAdSpot.ARTICLE) "article" else "publication"
            input["${prefix}WeeklyCents"] = rate.weeklyCents?.let { JsonPrimitive(it) } ?: JsonNull
            input["${prefix}Slots"] = JsonPrimitive(rate.slots)
        }
        input["notes"] = trimmed(sheet.notes)?.let { JsonPrimitive(it) } ?: JsonNull
        input["contactEmail"] = trimmed(sheet.contactEmail)?.let { JsonPrimitive(it) } ?: JsonNull
        return mapOf("input" to JsonObject(input))
    }

    /** [photo] is a data: URI upload or an https link. */
    public fun addMediaVariables(
        publicationId: String,
        photo: String,
        altText: String? = null,
        caption: String? = null,
        credit: String? = null,
    ): Map<String, JsonElement> = mapOf(
        "input" to JsonObject(
            buildMap {
                put("publicationId", JsonPrimitive(publicationId))
                put("photo", JsonPrimitive(photo))
                trimmed(altText)?.let { put("altText", JsonPrimitive(it)) }
                trimmed(caption)?.let { put("caption", JsonPrimitive(it)) }
                trimmed(credit)?.let { put("credit", JsonPrimitive(it)) }
            },
        ),
    )

    public fun updateMediaVariables(id: String, altText: String?, caption: String?, credit: String?): Map<String, JsonElement> =
        mapOf(
            "input" to JsonObject(
                mapOf(
                    "id" to JsonPrimitive(id),
                    "altText" to JsonPrimitive(altText.orEmpty()),
                    "caption" to JsonPrimitive(caption.orEmpty()),
                    "credit" to JsonPrimitive(credit.orEmpty()),
                ),
            ),
        )

    private fun trimmed(text: String?): String? = text?.trim()?.takeIf { it.isNotEmpty() }

    // Answers

    /** [ADS_QUERY]'s `data`. */
    public fun parseAds(data: JsonObject): PublicationAds {
        val publication = data.obj("soapbox")?.obj("publication")
        return PublicationAds(
            ads = publication?.array("ads").orEmpty().mapNotNull { ad(it as? JsonObject) },
            adsEnabled = publication?.bool("adsEnabled") ?: false,
            adsNeedReview = publication?.bool("adsNeedReview") ?: true,
            rateSheet = rateSheet(publication?.obj("rateSheet")) ?: PublicationRateSheet(),
        )
    }

    /** [MEDIA_QUERY]'s `data`. */
    public fun parseMedia(data: JsonObject): List<PublicationMediaItem> =
        data.obj("soapbox")?.obj("publication")?.array("media").orEmpty().mapNotNull { media(it as? JsonObject) }

    /** [REVIEW_QUEUE_QUERY]'s `data`. */
    public fun parseReviewQueue(data: JsonObject): PublisherAdReviewQueue {
        val soapbox = data.obj("soapbox")
        return PublisherAdReviewQueue(
            queue = soapbox?.array("adReviewQueue").orEmpty().mapNotNull { ad(it as? JsonObject) },
            mode = PublisherAdsMode.from(soapbox?.string("publisherAds")) ?: PublisherAdsMode.REVIEW_PENDING,
        )
    }

    /** [SAVE_AD_MUTATION]'s `data`. */
    public fun parseSaveAd(data: JsonObject): PublisherAdSaveResult {
        val payload = data.obj("savePublicationAd")
        return PublisherAdSaveResult(
            ad = ad(payload?.obj("ad")),
            problems = payload?.array("problems").orEmpty().mapNotNull { (it as? JsonPrimitive)?.contentOrNull },
        )
    }

    /** [REVIEW_AD_MUTATION]'s or [REMOVE_AD_MUTATION]'s `data`. */
    public fun parseModerateAd(data: JsonObject): PublisherAd? =
        ad((data.obj("reviewPublicationAd") ?: data.obj("removePublicationAd"))?.obj("ad"))

    /** [SAVE_RATE_SHEET_MUTATION]'s `data`. */
    public fun parseRateSheet(data: JsonObject): PublicationRateSheet? =
        rateSheet(data.obj("savePublicationRateSheet")?.obj("publication")?.obj("rateSheet"))

    /** [ADD_MEDIA_MUTATION]'s or [UPDATE_MEDIA_MUTATION]'s `data`. */
    public fun parseMediaItem(data: JsonObject): PublicationMediaItem? =
        media((data.obj("addPublicationMedia") ?: data.obj("updatePublicationMedia"))?.obj("media"))

    private fun ad(obj: JsonObject?): PublisherAd? {
        obj ?: return null
        return PublisherAd(
            id = obj.string("id") ?: return null,
            adStatus = PublisherAdStatus.from(obj.string("adStatus")),
            spot = PublisherAdSpot.from(obj.string("spot")),
            category = obj.string("category") ?: "small_business",
            sponsorName = obj.string("sponsorName").orEmpty(),
            sponsorEmail = obj.string("sponsorEmail"),
            headline = obj.string("headline").orEmpty(),
            body = obj.string("body"),
            imageUrl = obj.string("imageUrl"),
            imageAlt = obj.string("imageAlt"),
            linkUrl = obj.string("linkUrl"),
            linkLabel = obj.string("linkLabel"),
            articleIds = obj.array("articleIds").orEmpty().mapNotNull { (it as? JsonPrimitive)?.contentOrNull },
            startsOn = obj.string("startsOn").orEmpty(),
            endsOn = obj.string("endsOn"),
            weekdays = obj.array("weekdays").orEmpty().mapNotNull { (it as? JsonPrimitive)?.intOrNull },
            priceCents = obj.int("priceCents") ?: 0,
            soldOutside = obj.bool("soldOutside") ?: true,
            paused = obj.bool("paused") ?: false,
            reviewNote = obj.string("reviewNote"),
            publication = obj.obj("publication")?.let { pub ->
                pub.string("id")?.let { PublisherAd.PublicationRef(it, pub.string("name").orEmpty()) }
            },
            weeklyViewers = obj.array("weeklyViewers").orEmpty().mapNotNull { row ->
                val week = row as? JsonObject ?: return@mapNotNull null
                PublisherAdWeek(week.string("weekStart") ?: return@mapNotNull null, week.int("viewers"), week.int("fewerThan"))
            },
        )
    }

    private fun rateSheet(obj: JsonObject?): PublicationRateSheet? = obj?.let {
        PublicationRateSheet(
            notes = it.string("notes"),
            contactEmail = it.string("contactEmail"),
            rates = it.array("rates").orEmpty().mapNotNull { row ->
                val rate = row as? JsonObject ?: return@mapNotNull null
                PublicationRate(
                    PublisherAdSpot.from(rate.string("spot")) ?: return@mapNotNull null,
                    rate.int("weeklyCents"),
                    rate.int("slots") ?: 4,
                )
            },
        )
    }

    private fun media(obj: JsonObject?): PublicationMediaItem? {
        obj ?: return null
        return PublicationMediaItem(
            id = obj.string("id") ?: return null,
            url = obj.string("url") ?: return null,
            altText = obj.string("altText"),
            caption = obj.string("caption"),
            credit = obj.string("credit"),
            createdAt = obj.string("createdAt"),
        )
    }

    private fun JsonObject.obj(key: String): JsonObject? = this[key] as? JsonObject
    private fun JsonObject.array(key: String): JsonArray? = this[key] as? JsonArray
    private fun JsonObject.string(key: String): String? = (this[key] as? JsonPrimitive)?.takeIf { it.isString }?.content
    private fun JsonObject.int(key: String): Int? = (this[key] as? JsonPrimitive)?.intOrNull
    private fun JsonObject.bool(key: String): Boolean? = (this[key] as? JsonPrimitive)?.booleanOrNull
}

/** The words the Soapbox app shows around ads and media, the same as the Swift SDK's. */
public object SoapboxAdsCopy {
    public const val ADS: String = "Ads"
    public const val NEW_AD: String = "New ad"
    public const val RATE_SHEET: String = "Rate sheet"
    public const val REPORTS: String = "Reports"
    public const val MEDIA: String = "Media"
    public const val ADD_MEDIA: String = "Add pictures"
    public const val AD_REVIEW: String = "Ads to review"
    public const val APPROVE: String = "Approve"
    public const val TURN_DOWN: String = "Turn down"
    public const val TAKE_DOWN: String = "Take down"
    public const val PUT_BACK: String = "Put back"
    public const val SOLD_OUTSIDE_NOTE: String = "You sell this ad yourself. The price is for your own records: " +
        "AudienceKit takes nothing."
    public const val NOT_ENABLED: String = "Ads aren't on for this publication yet. The audience's admins switch them on."
    public const val CONTEXTUAL_NOTE: String = "Ads show with your own articles and page, chosen by what's being read, " +
        "never by anything about the reader. Readers who tip to read without ads see none."
    public const val NEEDS_REVIEW: String = "New ads and changes to their words, picture or link wait for the " +
        "audience's admins before they run."
    public const val NO_ADS: String = "No ads here yet."
    public const val NO_MEDIA: String = "No pictures yet. Add the ones you use in articles and ads."
    public const val READERS_NOTE: String = "Readers: different people who saw the ad each week (Monday to Sunday). " +
        "Under 20 shows as fewer than 20."

    /** "$50 a week". */
    public fun weekly(cents: Int): String = "${money(cents)} a week"

    public fun money(cents: Int): String =
        if (cents % 100 == 0) "\$${cents / 100}" else "\$%.2f".format(java.util.Locale.US, cents / 100.0)
}
