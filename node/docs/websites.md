# Building a website with Node

A venue's site, a city guide, a Discord bot or a newsletter job can be built from what an audience lists, with the
same calls the apps make. This page covers reading as the audience (no one signed in), the public listings, Soapbox
news, and what a signed-in visitor can do on a site.

## Read as the audience: service tokens

An admin mints a service token in the audience's console (`akst_<prefix>_<secret>`) with the scopes the site needs,
`public:read` for the public listings. Keep it in the environment, never in the repository:

```sh
AUDIENCEKIT_TOKEN=akst_…
AUDIENCEKIT_HOST=hotmess.social
```

```ts
import { AudienceKitClient } from "audience-kit";

const client = AudienceKitClient.fromEnvironment();
```

`fromEnvironment()` also reads `AUDIENCEKIT_BASE_URL`, `AUDIENCEKIT_AUDIENCE_ID` and `AUDIENCEKIT_ENVIRONMENT`
(`staging` for a staging build), and takes the same `transport` and `monitor` options as the constructor. With a token
from somewhere else (a secrets manager, say):

```ts
const client = new AudienceKitClient({ configuration: { host: "hotmess.social" } });
await client.useServiceToken(await secrets.get("audiencekit"));
```

The client trades the token at `POST /v1/token/service` for an hour-long session, trades it again a minute before that
runs out (once, however many calls are waiting), and once more if the API refuses the session (after a key rotation,
say). A token an admin revoked throws `AudienceKitError` with `UNAUTHORIZED`. An application API key works the same
way through `AUDIENCEKIT_TOKEN` or `useBearerToken()`: it is sent as is.

**What a service token reads today:** the public listings below. The GraphQL reads (`community()`, `events()`,
`venues()`, news and the rest) refuse a service session for now, so a site that renders from them uses an application
API key from the audience's console: set it as `AUDIENCEKIT_TOKEN` (anything not starting `akst_` is sent as is) or
pass it to `useBearerToken()`. Keep it on the server, like a service token.

## The public listings

What the audience shows anyone, as its own websites show it: up to 500 venues, then events, then posts, a page at a
time. Plain text, ready for a template:

```ts
import { isPublicListing } from "audience-kit";

for (const listing of await client.publicListings()) {
  if (!isPublicListing(listing)) continue;   // "community" listings show in full only to members
  switch (listing.kind) {
    case "venue": html += `<h2>${escape(listing.title)}</h2><p>${escape(listing.address)}</p>`; break;
    case "event": html += `<h3>${escape(listing.title)}</h3><time>${listing.start_at}</time>`; break;
    case "post": html += `<article><h3>${escape(listing.title)}</h3><p>${escape(listing.description)}</p></article>`; break;
  }
}
```

`publicListingsPage(page)` reads one page (with `nextPage` for the next), `publicListing("venue", id)` one listing
(null when it's gone), and `publicTonight(venueId)` what a screen facing the room shows: tonight's event, who's on and
what's next. [`examples/listings-site.ts`](../examples/listings-site.ts) is a page of listings served with a
five-minute cache.

## The community in one call

For a site that renders from the richer GraphQL models (venues with their locales, points and tags; events with their
venues, hosts and tickets), `community()` reads the audience, its locales, venues, people, upcoming events and event
series together, with an application API key or a person's session. A part whose module the audience doesn't have
comes back empty.

```ts
import { eventHostedBy, listingName, locationCoordinate } from "audience-kit";

const { audience, venues, events } = await client.community();

for (const venue of venues) {
  const point = locationCoordinate(venue.location);   // { latitude, longitude }, for a map
  const tags = venue.tags?.map((tag) => tag.name) ?? [];
  console.log(listingName(venue), point, tags);
}
for (const event of events) console.log(event.name, eventHostedBy(event));
```

The individual calls are there too: `venues()`, `people()`, `locales()`, `events({ window, localeId, venueId })`,
`eventSeries()`, `event(id)` and `venueDetail(id)`. [`examples/community-export.ts`](../examples/community-export.ts)
writes the community out as JSON for a static site generator.

Events have their own time zone and may have no end. `event.startAt` is ISO 8601 in UTC; show it in the locale's zone
with `new Date(event.startAt).toLocaleString("en-US", { timeZone: "America/Denver" })`. `eventHostedBy(event)` says who
runs the night: its hosts or, when nobody else is linked to it, its KJ, DJ or VJ.

## News

Audiences with Soapbox carry local news and op-eds from publications they trust:

```ts
// The latest, pinned first, for a locale (or one publication).
for (const article of await client.articles({ localeId: locale.id, first: 10 })) {
  html += `<a href="/news/${article.slug}">${escape(article.title)}</a> <small>${escape(article.publication.name)}</small>`;
}

// "Show more": page through with the cursor.
const page = await client.articlesPage({ localeId: locale.id, after: req.query.after ?? null });
if (page.hasNextPage) html += `<a href="?after=${encodeURIComponent(page.endCursor!)}">Show more</a>`;

// One article, with its Markdown body and what it is about.
const article = await client.article(id);
```

Also `nationalArticles()`, `articlesAbout("venue" | "event" | "person" | "locale", id)` for "In the news" on a
listing's page, `publications()`, `localPublications(localeId)` and `publication(id)`. Show `article.disclosure` when
there is one, and link `article.canonicalUrl` when `article.teaser` is true: the rest of the article is on the
publication's site. A signed-in reader can send a publication that accepts them an op-ed with `submitOpEd()`, and
follow it with `myOpEds()`. [`examples/news-digest.ts`](../examples/news-digest.ts) writes a locale's week of news as
Markdown, for a newsletter.

Every Soapbox call returns nothing, rather than failing, for an audience without Soapbox.

## Things a signed-in visitor can do

Once someone has [signed in](sign-in.md), a site can do what the apps do
([`examples/member-actions.ts`](../examples/member-actions.ts)):

- RSVP: `rsvp(eventId, "ATTENDING")`, `cancelRSVP(eventId)` and `eventRSVP(eventId)` for who's going.
- Calendar: `createCalendarFeed()` returns links (`url`, `webcalUrl`, `googleUrl`) that add every event they're going
  to to their own calendar, and `followVenueInCalendar(venueId)` adds every event at a venue.
- Cover: `venueCover(venueId)` says tonight's charge; `buyCover(venueId, amountCents)` (the amount on a sliding scale)
  or `buyCoatCheck(venueId, coats)` starts paying with the venue's provider. For Stripe, confirm
  `paymentIntentClientSecret` with Stripe.js and call `confirmCover()`; for Square, tokenize with the Web Payments SDK
  and call `payCover()`. `coverPassCode(pass.id, pass.passSecret)` is the code to show at the door as a QR code; it
  changes every 30 seconds (`secondsUntilNextCoverPassWindow()`), so draw it in the page and refresh it rather than
  caching it.
- Chat: `sendChatMessage()`, `removeChatMessage()`, and `reportContent()`, `blockUser()` and `unblockUser()` so people
  can report what they see. Offer `REPORT_REASONS` as the reasons.

## Caching

Listings change a few times a day, so cache what the page renders, not the client's session. The models are plain
JSON, so they go into Redis, a CDN or a file as they are:

```ts
const cached = await redis.get("audiencekit:events");
const events = cached ? JSON.parse(cached) : await client.events();
if (!cached) await redis.set("audiencekit:events", JSON.stringify(events), { EX: 300 });
```

Don't cache anything read as a signed-in person in a cache other people's pages read from.

## Serverless and edge

The package has no dependencies and uses the global `fetch`, so it runs on Cloudflare Workers, Vercel and Deno as well
as Node 20+. There's no `process.env` on Workers: pass the bindings to `fromEnvironment(env)`. A worker can't keep a
service session between requests, so cache the rendered result (the Cache API, KV) rather than calling on every
request.

```ts
export default {
  async fetch(request: Request, env: Record<string, string>): Promise<Response> {
    const client = AudienceKitClient.fromEnvironment(env);
    const listings = await client.publicListings();
    return Response.json(listings, { headers: { "Cache-Control": "public, max-age=300" } });
  },
};
```
