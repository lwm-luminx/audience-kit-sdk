package com.audiencekit

import kotlinx.serialization.Serializable

// Soapbox: articles from the audience's publications (a newspaper such as QSaltLake, a candidate), and op-eds readers
// send them from the apps. The API's `soapbox` mixin and each venue's, event's, person's and locale's `articles`;
// audiences without the Soapbox module have neither, so every helper here returns nothing for them.

/** Who wrote an article: the publication, or a reader who sent it as an op-ed. */
public enum class ArticleKind { ARTICLE, OP_ED }

/** Where an article stands. Readers only see it on their own op-eds ([myOpEds]). */
public enum class ArticleStatus {
    /** An op-ed waiting for the publication. */
    SUBMITTED,

    /** An op-ed the publication won't run; [Article.reviewNote] says why. */
    DECLINED,
    DRAFT,
    IN_REVIEW,
    PUBLISHED,
    UNPUBLISHED,
}

/** A publication as an article shows it: its name, photo and whether it takes op-eds. */
@Serializable
public data class PublicationSummary(
    val id: String,
    val name: String,
    val photoUrl: String? = null,
    val trusted: Boolean = false,
    val acceptsOpEds: Boolean = false,
    /** Whether readers can tip it to read it without ads ([AdFreeTips]). Null from an API without it. */
    val adFreeOffered: Boolean? = null,
)

/** A venue, event, person or locale an article is about, by name. */
@Serializable
public data class ArticleSubject(val id: String, val name: String? = null)

/** A publication: a person listing that publishes (a newspaper, a candidate), with its masthead. */
@Serializable
public data class Publication(
    val id: String,
    /** Its masthead, else its person's name. */
    val name: String,
    val masthead: String? = null,
    val about: String? = null,
    val websiteUrl: String? = null,
    val photoUrl: String? = null,
    /** Whether the audience trusts it to publish without approving each article. */
    val trusted: Boolean = false,
    /** Whether readers can send it op-eds ([submitOpEd]). */
    val acceptsOpEds: Boolean = false,
    /** What it asks of op-eds: length, topics, how it edits. */
    val opEdGuidelines: String? = null,
    val locale: ArticleSubject? = null,
    val person: ArticleSubject? = null,
    /**
     * Tip to read without ads ([AdFreeTips]): whether readers can now, the least tip that does it, in cents, and for
     * how many days. Null from an API without it.
     */
    val adFreeOffered: Boolean? = null,
    val adFreeTipCents: Int? = null,
    val adFreeDays: Int? = null,
    /** Whether the signed-in reader reads it without ads now, and until when (ISO 8601). */
    val viewerAdFree: Boolean? = null,
    val viewerAdFreeUntil: String? = null,
)

/** An article or op-ed. Lists leave out [body]; [article] reads it. */
@Serializable
public data class Article(
    val id: String,
    val slug: String = "",
    val title: String,
    val summary: String? = null,
    /** What it says, in Markdown; null in lists. */
    val body: String? = null,
    /** Who it shows as written by: its byline, else the publication's name. */
    val byline: String = "",
    val kind: ArticleKind = ArticleKind.ARTICLE,
    /** ISO 8601. */
    val publishedAt: String? = null,
    /** Whether it changed after it was published. */
    val edited: Boolean = false,
    val pinned: Boolean = false,
    /** A summary that links to [canonicalUrl] instead of a body. */
    val teaser: Boolean = false,
    val canonicalUrl: String? = null,
    /** What ties the publication to what it covers (its own gala, a sponsor): show it above the article. */
    val disclosure: String? = null,
    val heroPhotoUrl: String? = null,
    val heroAltText: String? = null,
    val publication: PublicationSummary,
    val venues: List<ArticleSubject>? = null,
    val events: List<ArticleSubject>? = null,
    val people: List<ArticleSubject>? = null,
    val locales: List<ArticleSubject>? = null,
    /** The signed-in writer's own op-eds only: where it stands, and why it was declined. */
    val status: ArticleStatus? = null,
    val reviewNote: String? = null,
    /** ISO 8601. */
    val submittedAt: String? = null,
    /**
     * Whether the signed-in reader tipped its publication to read it without ads: show no ads or sponsored spots with
     * it. Null from an API without it.
     */
    val viewerAdFree: Boolean? = null,
) {
    /** Whether to leave ads and sponsored spots out around it: the reader tipped its publication. */
    val showsWithoutAds: Boolean get() = viewerAdFree == true

    /** Whether to show it as an op-ed ("Op-ed" label, the writer's byline). */
    val isOpEd: Boolean get() = kind == ArticleKind.OP_ED
}

/** What [articlesAbout] lists articles about. */
public sealed class ArticleTopic(public val id: String) {
    public class Venue(id: String) : ArticleTopic(id)
    public class Event(id: String) : ArticleTopic(id)
    public class Person(id: String) : ArticleTopic(id)

    /** A locale's news: about it or anything in it, or by a publication covering it, from the last 30 days. */
    public class Locale(id: String) : ArticleTopic(id)
}

/** The API's answer to [submitOpEd] had no article. */
public class OpEdNotSubmittedException : Exception("The op-ed wasn't sent.")

/**
 * The audience's live articles, pinned first, then newest: a locale's news, or one publication's, when given. Empty
 * when the audience doesn't have Soapbox.
 */
public suspend fun AudienceKitClient.articles(
    localeId: String? = null,
    publicationId: String? = null,
    first: Int? = null,
): List<Article> = graphQL(
    SoapboxQueries.TYPES,
    SoapboxResponse.serializer(),
    graphQLVariables("localeId" to localeId, "publicationId" to publicationId, "first" to first),
    "Articles",
    SoapboxQueries::articles,
).soapbox?.articles?.items.orEmpty()

/**
 * One article with its body and what it's about: a live one, or one the signed-in person may see before it is (their
 * own op-ed). Null when there's no such article, or the audience doesn't have Soapbox.
 */
public suspend fun AudienceKitClient.article(id: String): Article? = graphQL(
    SoapboxQueries.TYPES,
    SoapboxResponse.serializer(),
    graphQLVariables("id" to id),
    "Article",
    SoapboxQueries::article,
).soapbox?.article

/** Live articles about a venue, event or person, newest first, or a locale's news ("In the news"). */
public suspend fun AudienceKitClient.articlesAbout(topic: ArticleTopic, first: Int? = null): List<Article> = graphQL(
    SoapboxQueries.TYPES,
    ArticlesAboutResponse.serializer(),
    graphQLVariables("id" to topic.id, "first" to first),
    "ArticlesAbout",
) { shape -> SoapboxQueries.articlesAbout(topic, shape) }.articles

/** The audience's publications (its admins can ask for other trusts on the staff endpoint). */
public suspend fun AudienceKitClient.publications(): List<Publication> = graphQL(
    SoapboxQueries.TYPES,
    SoapboxResponse.serializer(),
    null,
    "Publications",
    SoapboxQueries::publications,
).soapbox?.publications.orEmpty()

/** One publication, for its page and its "Write an op-ed" button. */
public suspend fun AudienceKitClient.publication(id: String): Publication? = graphQL(
    SoapboxQueries.TYPES,
    SoapboxResponse.serializer(),
    graphQLVariables("id" to id),
    "Publication",
    SoapboxQueries::publication,
).soapbox?.publication

/** The op-eds the signed-in person sent, newest first, with [Article.status] and [Article.reviewNote]. */
public suspend fun AudienceKitClient.myOpEds(): List<Article> = graphQL(
    SoapboxQueries.TYPES,
    SoapboxResponse.serializer(),
    null,
    "MyOpEds",
    SoapboxQueries::myOpEds,
).soapbox?.myOpEds.orEmpty()

/**
 * Sends a publication an op-ed under the signed-in person's name ([byline] overrides it). The publication runs it
 * (edited, bylined to the writer) or declines it with a note; [myOpEds] shows which. A writer can have three waiting
 * at once, and only a publication with [Publication.acceptsOpEds] takes them.
 */
public suspend fun AudienceKitClient.submitOpEd(
    publicationId: String,
    title: String,
    body: String,
    summary: String? = null,
    byline: String? = null,
): Article = graphQL(
    SoapboxQueries.SUBMIT_OP_ED,
    SubmitOpEdResponse.serializer(),
    graphQLVariables(
        "publicationId" to publicationId, "title" to title, "body" to body, "summary" to summary, "byline" to byline,
    ),
    "SubmitOpEd",
).submitOpEd?.article ?: throw OpEdNotSubmittedException()

/** The words around Soapbox, the same as the Swift SDK's, so both apps say the same thing. */
public object SoapboxCopy {
    public const val NEWS: String = "News"
    public const val IN_THE_NEWS: String = "In the news"
    public const val OP_ED: String = "Op-ed"
    public const val WRITE_OP_ED: String = "Write an op-ed"
    public const val OP_ED_SENT: String = "Sent. The publication will let you know if it runs it."
    public const val EDITED: String = "Updated"
    public const val READ_MORE: String = "Read on the publication's site"

    public fun status(status: ArticleStatus): String = when (status) {
        ArticleStatus.SUBMITTED -> "Waiting for the publication"
        ArticleStatus.DECLINED -> "Not running"
        ArticleStatus.DRAFT, ArticleStatus.IN_REVIEW -> "Being edited"
        ArticleStatus.PUBLISHED -> "Published"
        ArticleStatus.UNPUBLISHED -> "Taken down"
    }
}

internal object SoapboxQueries {
    /** The types the documents depend on: the root's `soapbox` and each listing's `articles`. */
    val TYPES: List<String> = listOf("Audience", "Venue", "Event", "Person", "Locale", "Article", "Publication")

    const val PUBLICATION_SUMMARY_FIELDS: String = "id name photoUrl trusted acceptsOpEds"
    const val ARTICLE_FIELDS: String = "id slug title summary byline kind publishedAt edited pinned teaser " +
        "canonicalUrl disclosure heroPhotoUrl heroAltText publication { $PUBLICATION_SUMMARY_FIELDS }"
    const val ARTICLE_SUBJECT_FIELDS: String =
        "venues { id name } events { id name } people { id name } locales { id name }"
    const val PUBLICATION_FIELDS: String = "id name masthead about websiteUrl photoUrl trusted acceptsOpEds " +
        "opEdGuidelines locale { id name } person { id name }"

    /** The article fields this audience's API has: tip to read without ads came later ([AdFreeTips]). */
    fun articleFields(shape: SchemaShape): String =
        if (!shape.has("Article", "viewerAdFree") || !shape.has("Publication", "adFreeOffered")) ARTICLE_FIELDS
        else ARTICLE_FIELDS.replace(PUBLICATION_SUMMARY_FIELDS, "$PUBLICATION_SUMMARY_FIELDS adFreeOffered") +
            " viewerAdFree"

    fun publicationFields(shape: SchemaShape): String =
        if (!shape.has("Publication", "adFreeOffered")) PUBLICATION_FIELDS
        else "$PUBLICATION_FIELDS adFreeOffered adFreeTipCents adFreeDays viewerAdFree viewerAdFreeUntil"

    /** The document when the audience has no Soapbox: asks for nothing the helpers decode, under the operation's name. */
    fun noSoapbox(name: String): String = "query $name { id }"

    fun articles(shape: SchemaShape): String = if (!shape.has("Audience", "soapbox")) noSoapbox("Articles") else """
        query Articles(${'$'}localeId: ID, ${'$'}publicationId: ID, ${'$'}first: Int) {
          soapbox {
            articles(localeId: ${'$'}localeId, publicationId: ${'$'}publicationId, first: ${'$'}first) {
              nodes { ${articleFields(shape)} }
            }
          }
        }
    """.trimIndent()

    fun article(shape: SchemaShape): String = if (!shape.has("Audience", "soapbox")) noSoapbox("Article") else """
        query Article(${'$'}id: ID!) {
          soapbox { article(id: ${'$'}id) { ${articleFields(shape)} body $ARTICLE_SUBJECT_FIELDS } }
        }
    """.trimIndent()

    fun publications(shape: SchemaShape): String =
        if (!shape.has("Audience", "soapbox")) noSoapbox("Publications")
        else "query Publications { soapbox { publications { ${publicationFields(shape)} } } }"

    fun publication(shape: SchemaShape): String =
        if (!shape.has("Audience", "soapbox")) noSoapbox("Publication")
        else "query Publication(${'$'}id: ID!) { soapbox { publication(id: ${'$'}id) { ${publicationFields(shape)} } } }"

    fun myOpEds(shape: SchemaShape): String = if (!shape.has("Audience", "soapbox")) noSoapbox("MyOpEds") else """
        query MyOpEds {
          soapbox { myOpEds { $ARTICLE_FIELDS status reviewNote submittedAt } }
        }
    """.trimIndent()

    fun articlesAbout(topic: ArticleTopic, shape: SchemaShape): String {
        val type = when (topic) {
            is ArticleTopic.Venue -> "Venue"
            is ArticleTopic.Event -> "Event"
            is ArticleTopic.Person -> "Person"
            is ArticleTopic.Locale -> "Locale"
        }
        if (!shape.has(type, "articles")) return noSoapbox("ArticlesAbout")
        val articleList = "articles { list(first: ${'$'}first) { nodes { ${articleFields(shape)} } } }"
        val listing = when (topic) {
            is ArticleTopic.Venue -> "venues { venue(id: ${'$'}id) { $articleList } }"
            is ArticleTopic.Event -> "events { event(id: ${'$'}id) { $articleList } }"
            is ArticleTopic.Person -> "people { person(id: ${'$'}id) { $articleList } }"
            is ArticleTopic.Locale -> "locale(id: ${'$'}id) { $articleList }"
        }
        return "query ArticlesAbout(${'$'}id: ID!, ${'$'}first: Int) { $listing }"
    }

    const val SUBMIT_OP_ED: String = """
        mutation SubmitOpEd(${'$'}publicationId: ID!, ${'$'}title: String!, ${'$'}body: String!, ${'$'}summary: String, ${'$'}byline: String) {
          submitOpEd(input: { publicationId: ${'$'}publicationId, title: ${'$'}title, body: ${'$'}body, summary: ${'$'}summary, byline: ${'$'}byline }) {
            article { $ARTICLE_FIELDS status reviewNote submittedAt }
          }
        }
    """
}

@Serializable
internal data class SoapboxResponse(val soapbox: Mixin? = null) {
    @Serializable
    data class Mixin(
        val articles: Connection<Article>? = null,
        val article: Article? = null,
        val publications: List<Publication>? = null,
        val publication: Publication? = null,
        val myOpEds: List<Article>? = null,
    )
}

@Serializable
internal data class ArticlesAboutResponse(
    val venues: Venues? = null,
    val events: Events? = null,
    val people: People? = null,
    val locale: Listing? = null,
) {
    @Serializable
    data class Listing(val articles: Mixin? = null)

    @Serializable
    data class Mixin(val list: Connection<Article>? = null)

    @Serializable
    data class Venues(val venue: Listing? = null)

    @Serializable
    data class Events(val event: Listing? = null)

    @Serializable
    data class People(val person: Listing? = null)

    val articles: List<Article>
        get() = (venues?.venue ?: events?.event ?: people?.person ?: locale)?.articles?.list?.items.orEmpty()
}

@Serializable
internal data class SubmitOpEdResponse(val submitOpEd: Payload? = null) {
    @Serializable
    data class Payload(val article: Article? = null)
}
