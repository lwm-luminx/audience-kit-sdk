// A Markdown digest of a locale's news, for a newsletter or a Discord post.
//
//   AUDIENCEKIT_TOKEN=akst_… AUDIENCEKIT_HOST=hotmess.social node --experimental-strip-types news-digest.ts "Denver"
//
// Returns nothing for an audience without Soapbox, rather than failing.
import { AudienceKitClient, type Article } from "audience-kit";

function line(article: Article): string {
  // A teaser carries only the start of the article: the rest is on the publication's site.
  const link = article.teaser && article.canonicalUrl ? ` ([read on ${article.publication.name}](${article.canonicalUrl}))` : "";
  const disclosure = article.disclosure ? `\n  _${article.disclosure}_` : "";
  return `- **${article.title}**, ${article.byline} for ${article.publication.name}${link}${article.summary ? `\n  ${article.summary}` : ""}${disclosure}`;
}

/** The digest for the locale named `localeName` (or the audience's first): its news, then the national news. */
export async function digest(client: AudienceKitClient, localeName?: string): Promise<string> {
  const locales = await client.locales();
  const locale = locales.find((l) => l.name === localeName) ?? locales[0];
  if (!locale) return "";
  const [local, national] = await Promise.all([
    client.articles({ localeId: locale.id, first: 10 }),
    client.nationalArticles({ localeId: locale.id, first: 5 }),
  ]);
  const sections = [`# ${locale.name} this week`];
  if (local.length > 0) sections.push(`## Local news\n\n${local.map(line).join("\n")}`);
  const seen = new Set(local.map((article) => article.id));
  const elsewhere = national.filter((article) => !seen.has(article.id));
  if (elsewhere.length > 0) sections.push(`## Around the country\n\n${elsewhere.map(line).join("\n")}`);
  return sections.length > 1 ? `${sections.join("\n\n")}\n` : "";
}

if (import.meta.url === `file://${process.argv[1]}`) {
  console.log(await digest(AudienceKitClient.fromEnvironment(), process.argv[2]));
}
