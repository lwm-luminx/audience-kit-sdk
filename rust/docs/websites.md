# Building a website with Rust

A venue's site, a city guide, a Discord bot, a newsletter job or an agent such as goose can be built from what an
audience lists, with the same documents the apps send. The crate reads as the audience: it doesn't sign people in.
This page covers its credentials, the public listings, the community and Soapbox news.

## Credentials

An admin mints the credential in the audience's console. Keep it in the environment, never in the repository:

```sh
AUDIENCEKIT_TOKEN=…
AUDIENCEKIT_HOST=hotmess.social      # or AUDIENCEKIT_AUDIENCE_ID
```

```rust
let client = audiencekit::Client::from_env()?;
```

`from_env()` also reads `AUDIENCEKIT_BASE_URL`. A token starting `akst_` is a **service token**: the client trades it
at `POST /v1/token/service` for an hour-long session, trades it again before that runs out, and once more if the API
refuses the session. Anything else is a **bearer value**, sent as is: an application API key, or a person's session
JWT minted elsewhere. With the builder:

```rust
use audiencekit::{Auth, Client};

let client = Client::builder().host("hotmess.social").service_token(secret).build()?;
let client = Client::builder().host("hotmess.social").auth(Auth::Bearer(api_key)).build()?;
let client = Client::builder().session(saved_credential).build()?;   // sent to the instance that issued it
```

**What each reads today:** a service token with the `public:read` scope reads the public listings. The GraphQL reads
(`community()`, `venues()`, `events()`, news and the rest) refuse a service session for now, so a site that renders
from them uses an application API key or a person's session.

`Client` is cheap to clone and safe to share across tasks: make one at startup and hold it in your server's state (an
axum `State`, an actix `Data`).

## The public listings

What the audience shows anyone, as its own websites show it: up to 500 venues, then events, then posts, a page at a
time. Plain text, ready for a template:

```rust
for listing in client.public_listings().await? {
    if !listing.is_public() {
        continue; // "community" listings show in full only to members
    }
    match listing.kind.as_str() {
        "venue" => println!("{} at {}", listing.title.unwrap_or_default(), listing.address.unwrap_or_default()),
        "event" => println!("{} on {:?}", listing.title.unwrap_or_default(), listing.start_at),
        _ => {}
    }
}
```

`public_listings_page(page)` reads one page (with `next_page` for the next), `public_listing(ListingKind::Venue, id)`
one listing (`None` when it's gone), and `public_tonight(venue_id)` what a screen facing the room shows: tonight's
event, who's on and what's next. [`examples/listings_page.rs`](../examples/listings_page.rs) writes a static page of
listings, for a scheduled job to publish.

## The community in one call

For a site that renders from the richer GraphQL models (venues with their locales, points and tags; events with their
venues, hosts and tickets), `community()` reads the audience, its locales, venues, people, upcoming events and event
series at the same time. A part whose module the audience doesn't have comes back empty.

```rust
let community = client.community().await?;
for venue in &community.venues {
    let point = venue.location.as_ref().and_then(|location| location.coordinate); // for a map
    println!("{} {:?}", venue.name, point);
}
```

The individual calls are there too: `venues()`, `people()`, `locales()`, `closest_locale(coordinate)`,
`events(&EventQuery { window, locale_id, venue_id, first })`, `event(id)` and `event_series(locale_id, venue_id)`.
Every model is `serde::Serialize`, so it goes into a template context, a cache or an agent's tool result as JSON.
[`examples/community.rs`](../examples/community.rs) prints the community as JSON.

Event times are `chrono::DateTime<Utc>`; show them in the locale's zone with `chrono-tz`. An event may have no end.

## News

Audiences with Soapbox carry local news and op-eds from publications they trust:

```rust
use audiencekit::{ArticleQuery, ArticleTopic};

// The latest, pinned first, for a locale (or one publication).
let query = ArticleQuery { locale_id: Some(locale.id.clone()), first: Some(10), ..Default::default() };
for article in client.articles(&query).await? {
    println!("{} ({})", article.title, article.publication.name);
}

// "Show more": page through with the cursor.
let page = client.articles_page(&ArticleQuery { after: cursor, ..query }).await?;
if page.has_next_page { /* link to ?after={page.end_cursor} */ }

// One article, with its Markdown body and what it is about; and "In the news" on a venue's page.
let article = client.article(&id).await?;
let about = client.articles_about(ArticleTopic::Venue, &venue.id, Some(5)).await?;
```

Also `national_articles(locale_id, first)`, `publications()`, `local_publications(locale_id)` and `publication(id)`.
Show `article.disclosure` when there is one, and link `article.canonical_url` when `article.teaser` is true: the rest
of the article is on the publication's site. [`examples/news_digest.rs`](../examples/news_digest.rs) writes a locale's
week of news as Markdown, for a newsletter.

Every news call returns nothing, rather than failing, for an audience without Soapbox.

## Caching

Listings change a few times a day, so cache what the page renders (in memory with a timestamp, Redis, or a static file
a scheduled job writes) rather than calling on every request. Keep the `Client` for the life of the process: it holds
the service session and the schema cache.
