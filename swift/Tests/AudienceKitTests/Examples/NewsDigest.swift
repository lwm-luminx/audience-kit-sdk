// A Markdown digest of a locale's news, for a newsletter, a share sheet or a "This week" card in the app. Empty for an
// audience without Soapbox, rather than failing.
import AudienceKit
import Foundation

public enum NewsDigest {
    /// One article as a Markdown list item. A teaser carries only the start: the rest is on the publication's site.
    public static func line(_ article: Article) -> String {
        let name = article.publication.name
        var text = "- **\(article.title)**, \(article.byline) for \(name)"
        if article.teaser, let url = article.canonicalUrl { text += " ([read on \(name)](\(url)))" }
        if let summary = article.summary { text += "\n  \(summary)" }
        if let disclosure = article.disclosure { text += "\n  _\(disclosure)_" }
        return text
    }

    /// The digest for the locale named `localeName` (or the audience's first): its news, then the national news.
    public static func digest(_ client: AudienceKitClient, localeName: String? = nil) async throws -> String {
        let locales = try await client.locales()
        guard let locale = locales.first(where: { $0.name == localeName }) ?? locales.first else { return "" }
        async let local = client.articles(localeID: locale.id, first: 10)
        async let national = client.nationalArticles(localeID: locale.id, first: 5)
        let news = try await local
        var sections = ["# \(locale.name ?? "Your city") this week"]
        if !news.isEmpty { sections.append("## Local news\n\n" + news.map(line).joined(separator: "\n")) }
        let seen = Set(news.map(\.id))
        let elsewhere = try await national.filter { !seen.contains($0.id) }
        if !elsewhere.isEmpty { sections.append("## Around the country\n\n" + elsewhere.map(line).joined(separator: "\n")) }
        return sections.count > 1 ? sections.joined(separator: "\n\n") + "\n" : ""
    }
}
