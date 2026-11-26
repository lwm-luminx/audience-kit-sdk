# Rust SDK reference

Everything in the `audiencekit` crate, by what it is for. Every call is `async` and returns
`audiencekit::Result<T>`. Every model is `Clone`, `Debug` and `serde::Serialize` (snake_case).

## Client

### Making one

| Call | What it does |
| --- | --- |
| `Client::from_env()` | Configured from `AUDIENCEKIT_TOKEN`, `AUDIENCEKIT_BASE_URL`, `AUDIENCEKIT_AUDIENCE_ID` and `AUDIENCEKIT_HOST`. |
| `Client::builder()` | A `ClientBuilder`: `.base_url()`, `.host()`, `.audience_id()`, `.environment(Environment::Staging)`, `.configuration()`, `.http_client(reqwest::Client)`, then `.build()`. |
| `.service_token(secret)` | An audience service token (`akst_…`), traded for sessions and renewed as needed. |
| `.auth(Auth::Bearer(value))` | An application API key, or a session JWT, sent as is. |
| `.session(credential)` | A session the API issued to a person, sent to the instance that issued it. |
| `Auth::from_token(token)` | A service token when it starts `akst_`, else a bearer value. |
| `client.set_auth(auth)` | Changes the credential. |
| `client.credential()` | The current session, if any. |
| `client.configuration()` | The configuration. |

### The audience and its listings

GraphQL: an application API key or a person's session.

| Call | Returns |
| --- | --- |
| `branding(host)` | `Branding`: the audience's public branding (no credential) |
| `audience_id()` | `String` |
| `audience()` | `Audience`: name, subdomain and theme |
| `me()` | `Option<SelfUser>` (`None` without a person) |
| `venues()`, `people()`, `locales()` | `Vec<Venue>`, `Vec<Person>`, `Vec<Locale>` |
| `closest_locale(Coordinate)` | `Option<Locale>` |
| `community()` | `Community`: the audience, locales, venues, people, upcoming events and series |
| `events(&EventQuery)` | `Vec<Event>`: `EventWindow::Upcoming` soonest first, or `Past` |
| `event(id)` | `Option<Event>` |
| `event_series(locale_id, venue_id)` | `Vec<EventSeries>` |
| `node(id)` | `Option<Node>`: any record's type by its ID |

### Public listings

A service token with `public:read`.

| Call | Returns |
| --- | --- |
| `public_listings()` | `Vec<PublicListing>`, every page |
| `public_listings_page(page)` | `PublicListingsPage`: `listings`, `page_count`, `next_page` |
| `public_listing(ListingKind::{Venue, Event, Post}, id)` | `Option<PublicListing>` |
| `public_tonight(venue_id)` | `serde_json::Value`: tonight at the venue, as a screen facing the room shows it |

`PublicListing::is_public()` says whether anyone may see it in full; `raw` has every field the API sent.

### News (Soapbox)

Every call returns nothing, rather than failing, for an audience without Soapbox.

| Call | Returns |
| --- | --- |
| `articles(&ArticleQuery { locale_id, publication_id, first, .. })` | `Vec<Article>`, pinned first, then newest |
| `articles_page(&ArticleQuery { after, .. })` | `ArticlesPage`: `articles`, `end_cursor`, `has_next_page` (20 a page unless `first` says) |
| `national_articles(locale_id, first)` | `Vec<Article>` |
| `article(id)` | `Option<Article>`, with `body` and what it's about |
| `articles_about(ArticleTopic::{Venue, Event, Person, Locale}, id, first)` | `Vec<Article>` |
| `publications()`, `local_publications(locale_id)` | `Vec<Publication>` |
| `publication(id)` | `Option<Publication>` |

### Your own operations

| Call | What it does |
| --- | --- |
| `graphql(query, variables, operation_name)` | Runs any document and returns its `data`. |
| `run(Operation)` | Runs a typed operation, retrying with the schema's fields after an `undefinedField`. |
| `schema_fields(types)` | The fields each type has in the audience's schema, cached. |
| `request(method, path, params, body)` | Calls a REST endpoint with the credential and returns the body. |

`audiencekit::operations` builds every operation the client runs, and `audiencekit::queries` has the documents, so a
host can run them with its own options; `operations::documents()` lists every document for a schema check.

## Errors

One `audiencekit::Error`, with a `code()` from the API's vocabulary (`UNAUTHENTICATED`, `FORBIDDEN`, `NOT_FOUND`,
`INVALID` with per-field `fields()`, `RATE_LIMITED`, `CONFLICT`, `INTERNAL`) or the SDK's own (`NETWORK`, `DECODING`,
`MISSING_CONFIGURATION`, `NOT_SIGNED_IN`), all in `audiencekit::codes`. It also has a `message()` fit to show, the HTTP
`status()`, and the GraphQL `errors()`. `is_unauthenticated()` and `is_undefined_field()` answer the common questions.
