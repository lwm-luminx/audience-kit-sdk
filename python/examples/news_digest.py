"""A Markdown digest of a locale's news, for a newsletter or a Discord post.

    AUDIENCEKIT_TOKEN=akst_… AUDIENCEKIT_HOST=hotmess.social python news_digest.py Denver

Returns nothing for an audience without Soapbox, rather than failing.
"""

from __future__ import annotations

import sys

from audiencekit import Article, Client


def line(article: Article) -> str:
    """One article as a Markdown list item. A teaser carries only the start: the rest is on the publication's site."""
    name = article.publication.name
    link = f" ([read on {name}]({article.canonical_url}))" if article.teaser and article.canonical_url else ""
    summary = f"\n  {article.summary}" if article.summary else ""
    disclosure = f"\n  _{article.disclosure}_" if article.disclosure else ""
    return f"- **{article.title}**, {article.byline} for {name}{link}{summary}{disclosure}"


def digest(client: Client, locale_name: str | None = None) -> str:
    """The digest for the locale named ``locale_name`` (or the audience's first): its news, then the national news."""
    locales = client.locales()
    locale = next((each for each in locales if each.name == locale_name), locales[0] if locales else None)
    if locale is None:
        return ""
    local = client.articles(locale_id=locale.id, first=10)
    national = client.national_articles(locale_id=locale.id, first=5)
    sections = [f"# {locale.name} this week"]
    if local:
        sections.append("## Local news\n\n" + "\n".join(line(article) for article in local))
    seen = {article.id for article in local}
    elsewhere = [article for article in national if article.id not in seen]
    if elsewhere:
        sections.append("## Around the country\n\n" + "\n".join(line(article) for article in elsewhere))
    return "\n\n".join(sections) + "\n" if len(sections) > 1 else ""


if __name__ == "__main__":
    with Client.from_environment() as client:
        print(digest(client, sys.argv[1] if len(sys.argv) > 1 else None))
