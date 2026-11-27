package com.audiencekit

import kotlinx.serialization.Serializable

// Reviews: written takes on a venue, event or person (no rating, on purpose). Some are a line quoted from a news
// article (City Weekly's guide to Salt Lake's LGBTQ bars, a line on each bar it names): show those as a quote from the
// article's publication and open the article to read the rest. APIs from before reviews have none, and helpers here
// return nothing for them.

/** A review of a venue, event or person. */
@Serializable
public data class Review(
    val id: String,
    /** What it says, in Markdown. */
    val body: String,
    val publishedAt: String? = null,
    /**
     * The news article it's quoted from, when it is a line from one: credit [Article.publication] and open the article
     * (a teaser opens [Article.canonicalUrl]).
     */
    val article: Article? = null,
) {
    /** Whether it's a line quoted from a news article. */
    val isQuote: Boolean get() = article != null

    /** Who to credit it to: the article's publication ("City Weekly") when it is a quote. */
    val sourceName: String? get() = article?.publication?.name
}

/**
 * A venue's, event's or person's published reviews, newest first: quotes from news articles among them
 * ([Review.isQuote]). Empty for a locale, and when the audience's API has no reviews yet.
 */
public suspend fun AudienceKitClient.reviews(topic: ArticleTopic): List<Review> {
    if (topic is ArticleTopic.Locale) return emptyList()
    return graphQL(
        ReviewQueries.TYPES,
        ReviewsResponse.serializer(),
        graphQLVariables("id" to topic.id),
        "Reviews",
    ) { shape -> ReviewQueries.reviews(topic, shape) }.reviews
}

internal object ReviewQueries {
    val TYPES: List<String> = listOf("Venue", "Event", "Person", "Review", "Article", "Publication")

    fun reviews(topic: ArticleTopic, shape: SchemaShape): String {
        val type = when (topic) {
            is ArticleTopic.Venue -> "Venue"
            is ArticleTopic.Event -> "Event"
            is ArticleTopic.Person -> "Person"
            is ArticleTopic.Locale -> "Locale"
        }
        if (!shape.has(type, "reviews")) return SoapboxQueries.noSoapbox("Reviews")
        val article = if (shape.has("Review", "article")) " article { ${SoapboxQueries.articleFields(shape)} }" else ""
        val reviews = "reviews { id body publishedAt$article }"
        val listing = when (topic) {
            is ArticleTopic.Venue -> "venues { venue(id: ${'$'}id) { $reviews } }"
            is ArticleTopic.Event -> "events { event(id: ${'$'}id) { $reviews } }"
            is ArticleTopic.Person -> "people { person(id: ${'$'}id) { $reviews } }"
            is ArticleTopic.Locale -> "locale(id: ${'$'}id) { $reviews }"
        }
        return "query Reviews(${'$'}id: ID!) { $listing }"
    }
}

@Serializable
internal data class ReviewsResponse(
    val venues: Venues? = null,
    val events: Events? = null,
    val people: People? = null,
    val locale: Listing? = null,
) {
    @Serializable
    data class Listing(val reviews: List<Review>? = null)

    @Serializable
    data class Venues(val venue: Listing? = null)

    @Serializable
    data class Events(val event: Listing? = null)

    @Serializable
    data class People(val person: Listing? = null)

    val reviews: List<Review>
        get() = (venues?.venue ?: events?.event ?: people?.person ?: locale)?.reviews.orEmpty()
}
