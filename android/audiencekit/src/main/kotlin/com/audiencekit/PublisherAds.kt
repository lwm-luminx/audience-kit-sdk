package com.audiencekit

import kotlinx.serialization.Serializable

// Soapbox publishers' ads on their own content (API doc/SOAPBOX.md "Publisher ads and the media library"): a sponsor's
// card a publication sells and shows after an article in the reader, or on its page. Labelled "Ad" and "Sold by
// <publication>", placed by context only, never shown on a teaser or op-ed, and never to a reader who tipped the
// publication to read it without ads. The publication keeps all of the money. Report it shown with [recordCardViews]
// like any promoted card, so its sponsor gets their one number.

/**
 * The ad to show after an article in the reader, sold by its publication; null when there is none (a teaser, an op-ed,
 * a publication that sells none, a reader reading it without ads, or an API without publisher ads).
 */
public suspend fun AudienceKitClient.publisherAdForArticle(articleId: String): PromoCard? = graphQL(
    SoapboxQueries.TYPES,
    PublisherAdResponse.serializer(),
    graphQLVariables("id" to articleId),
    "ArticleAd",
    PublisherAdQueries::articleAd,
).ad

/** The ad to show on a publication's page, on the same terms. */
public suspend fun AudienceKitClient.publisherAdForPublication(publicationId: String): PromoCard? = graphQL(
    SoapboxQueries.TYPES,
    PublisherAdResponse.serializer(),
    graphQLVariables("id" to publicationId),
    "PublicationAd",
    PublisherAdQueries::publicationAd,
).ad

/** What the apps say on and about a publisher's ad. */
public object PublisherAdCopy {
    /** Under the ad: who sold it. */
    public fun soldBy(publication: String): String = "Sold by $publication"

    /** The card menu's explanation. */
    public const val WHY_TITLE: String = "Why am I seeing this?"

    public fun why(publication: String): String =
        "$publication sold this ad to support its writers. It's shown because of what you're reading, never " +
            "because of anything about you, and $publication keeps all of the money."

    /** The card menu's report action. */
    public const val REPORT: String = "Report this ad"
}

internal object PublisherAdQueries {
    private val FIELDS = "id category label sponsorName soldBy ${LayoutQueries.CARD_CONTENT_FIELDS}"

    fun articleAd(shape: SchemaShape): String =
        if (!shape.has("Audience", "soapbox") || !shape.has("Article", "ad")) SoapboxQueries.noSoapbox("ArticleAd")
        else "query ArticleAd(\$id: ID!) { soapbox { article(id: \$id) { id ad { $FIELDS } } } }"

    fun publicationAd(shape: SchemaShape): String =
        if (!shape.has("Audience", "soapbox") || !shape.has("Publication", "ad")) {
            SoapboxQueries.noSoapbox("PublicationAd")
        } else {
            "query PublicationAd(\$id: ID!) { soapbox { publication(id: \$id) { id ad { $FIELDS } } } }"
        }
}

@Serializable
internal data class PublisherAdResponse(val soapbox: Mixin? = null) {
    @Serializable
    data class Holder(val ad: PromoCardWire? = null)

    @Serializable
    data class Mixin(val article: Holder? = null, val publication: Holder? = null)

    val ad: PromoCard? get() = (soapbox?.article ?: soapbox?.publication)?.ad?.toPromoCard()
}
