// A Markdown digest of a locale's news, for a newsletter, a Discord post or a "This week" card in the app. Empty for
// an audience without Soapbox, rather than failing.
package com.audiencekit.examples

import com.audiencekit.Article
import com.audiencekit.AudienceKitClient
import com.audiencekit.articles
import com.audiencekit.nationalArticles
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope

/** One article as a Markdown list item. A teaser carries only the start: the rest is on the publication's site. */
fun line(article: Article): String = buildString {
    val name = article.publication.name
    append("- **${article.title}**, ${article.byline} for $name")
    if (article.teaser && article.canonicalUrl != null) append(" ([read on $name](${article.canonicalUrl}))")
    article.summary?.let { append("\n  $it") }
    article.disclosure?.let { append("\n  _${it}_") }
}

/** The digest for the locale named [localeName] (or the audience's first): its news, then the national news. */
suspend fun digest(client: AudienceKitClient, localeName: String? = null): String = coroutineScope {
    val locales = client.locales()
    val locale = locales.firstOrNull { it.name == localeName } ?: locales.firstOrNull() ?: return@coroutineScope ""
    val local = async { client.articles(localeId = locale.id, first = 10) }
    val national = async { client.nationalArticles(localeId = locale.id, first = 5) }
    val sections = mutableListOf("# ${locale.name ?: "Your city"} this week")
    val news = local.await()
    if (news.isNotEmpty()) sections += "## Local news\n\n" + news.joinToString("\n", transform = ::line)
    val seen = news.map { it.id }.toSet()
    val elsewhere = national.await().filter { it.id !in seen }
    if (elsewhere.isNotEmpty()) sections += "## Around the country\n\n" + elsewhere.joinToString("\n", transform = ::line)
    if (sections.size > 1) sections.joinToString("\n\n") + "\n" else ""
}
