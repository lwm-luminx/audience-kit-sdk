# Building a website with Python

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

```python
from audiencekit import Client

client = Client.from_environment()
```

`from_environment()` also reads `AUDIENCEKIT_BASE_URL`, `AUDIENCEKIT_AUDIENCE_ID` and `AUDIENCEKIT_ENVIRONMENT`
(`staging` for a staging build), takes a mapping in place of `os.environ`, and passes keyword arguments (`http=…`) to
the constructor. `AsyncClient.from_environment()` works the same way. With a token from somewhere else (a secrets
manager, say):

```python
client = Client(Configuration(host="hotmess.social"))
client.use_service_token(secrets.get("audiencekit"))
```

The client trades the token at `POST /v1/token/service` for an hour-long session, trades it again a minute before that
runs out (once, however many asyncio tasks are waiting), and once more if the API refuses the session (after a key
rotation, say). A token an admin revoked raises `AudienceKitError` with `UNAUTHENTICATED`. An application API key works
the same way through `AUDIENCEKIT_TOKEN` or `use_bearer_token()`: it is sent as is.

## The public listings

What the audience shows anyone, as its own websites show it: up to 500 venues, then events, then posts, a page at a
time. Plain text, ready for a template:

```python
from html import escape

for listing in client.public_listings():
    if not listing.is_public:  # "community" listings show in full only to members
        continue
    if listing.kind == "venue":
        html += f"<h2>{escape(listing.title)}</h2><p>{escape(listing.address or '')}</p>"
    elif listing.kind == "event":
        html += f"<h3>{escape(listing.title)}</h3><time>{listing.start_at:%a %b %d, %I:%M %p}</time>"
    elif listing.kind == "post":
        html += f"<article><h3>{escape(listing.title)}</h3><p>{escape(listing.description or '')}</p></article>"
```

`public_listings_page(page)` reads one page (with `next_page` for the next), `public_listing("venue", id)` one listing
(`None` when it's gone), and `public_tonight(venue_id)` what a screen facing the room shows: tonight's event, who's on
and what's next. [`examples/listings_site.py`](../examples/listings_site.py) is a page of listings served with a
five-minute cache.

## The community in one call

For a site that renders from the richer GraphQL models (venues with their locales, points and tags; events with their
venues, hosts and tickets), `community()` reads the audience, its locales, venues, people, upcoming events and event
series together. A part whose module the audience doesn't have comes back empty. (`AsyncClient` reads the parts at
the same time.)

```python
community = client.community()

for venue in community.venues:
    point = venue.location.coordinate if venue.location else None  # latitude and longitude, for a map
    tags = [tag.name for tag in venue.tags or []]
    print(venue.name, point, tags)
for event in community.events:
    print(event.name, event.venue_name, [host.name for host in event.hosts or []])
```

The individual calls are there too: `venues()`, `people()`, `locales()`, `events(window, locale_id, venue_id)`,
`event_series()` and `event(id)`. [`examples/community_export.py`](../examples/community_export.py) writes the
community out as JSON for a static site generator.

Event times are timezone-aware `datetime`s in UTC; show them in the locale's zone with
`event.start_at.astimezone(ZoneInfo("America/Denver"))`. An event may have no end.

## News

Audiences with Soapbox carry local news and op-eds from publications they trust:

```python
# The latest, pinned first, for a locale (or one publication).
for article in client.articles(locale_id=locale.id, first=10):
    html += (
        f'<a href="/news/{article.slug}">{escape(article.title)}</a> <small>{escape(article.publication.name)}</small>'
    )

# "Show more": page through with the cursor.
page = client.articles_page(locale_id=locale.id, after=request.args.get("after"))
if page.has_next_page:
    html += f'<a href="?after={quote(page.end_cursor)}">Show more</a>'

# One article, with its Markdown body and what it is about.
article = client.article(id)
```

Also `national_articles()`, `articles_about("venue" | "event" | "person" | "locale", id)` for "In the news" on a
listing's page, `publications()`, `local_publications(locale_id)` and `publication(id)`. Show `article.disclosure` when
there is one, and link `article.canonical_url` when `article.teaser` is true: the rest of the article is on the
publication's site. A signed-in reader can send a publication that accepts them an op-ed with `submit_op_ed()`, and
follow it with `my_op_eds()`. [`examples/news_digest.py`](../examples/news_digest.py) writes a locale's week of news as
Markdown, for a newsletter.

Every Soapbox call returns nothing, rather than failing, for an audience without Soapbox.

## Things a signed-in visitor can do

Once someone has [signed in](sign-in.md), a site can do what the apps do
([`examples/member_actions.py`](../examples/member_actions.py)):

- RSVP: `rsvp_event(event_id, "ATTENDING")` and `cancel_rsvp(event_id)`.
- Calendar: `create_calendar_feed()` returns links (`url`, `webcal_url`, `google_url`) that add every event they're
  going to to their own calendar, and `follow_venue_in_calendar(venue_id)` adds every event at a venue.
- Cover: `venue_cover(venue_id)` says tonight's charge; `buy_cover(venue_id, amount_cents)` (the amount on a sliding
  scale) or `buy_coat_check(venue_id, coats)` starts paying with the venue's provider. For Stripe, confirm
  `payment_intent_client_secret` with Stripe.js and call `confirm_cover()`; for Square, tokenize with the Web Payments
  SDK and call `pay_cover()`. `cover_pass_code(admission.id, admission.pass_secret)` is the code to show at the door as
  a QR code; it changes every 30 seconds (`audiencekit.cover_pass.seconds_until_next_window()`), so draw it in the page
  and refresh it rather than caching it.
- Chat: `send_chat_message(text, venue_id=…)` or `locale_id=…`, `remove_chat_message()`, and `report_content()`,
  `block_user()` and `unblock_user()` so people can report what they see. Offer `REPORT_REASONS` as the reasons.

## Caching

Listings change a few times a day, so cache what the page renders, not the client's session. Keep the client itself
for the life of the process: it holds the service session and the schema cache.

```python
from django.core.cache import cache

html = cache.get_or_set("audiencekit:listings", lambda: render_page(client), timeout=300)
```

Don't cache anything read as a signed-in person in a cache other people's pages read from.

## asyncio

`AsyncClient` takes every call above, awaited:

```python
from audiencekit import AsyncClient

client = AsyncClient.from_environment()


@app.get("/listings")
async def listings():
    return [listing.raw for listing in await client.public_listings() if listing.is_public]
```
