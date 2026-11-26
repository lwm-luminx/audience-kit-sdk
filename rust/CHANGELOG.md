# Changelog

The Rust crate's own versions, separate from the Swift and Kotlin SDKs' [CHANGELOG.md](../CHANGELOG.md).

## 0.2.0 (2026-11-26)

Soapbox news: `articles()`, `articles_page()` (with the cursor for "Show more"), `national_articles()`, `article()`
with its body and what it is about, `articles_about()` for a venue, event, person or locale, `publications()`,
`local_publications()` and `publication()`, each empty for an audience without Soapbox. Guides in `docs/`, and
`listings_page` and `news_digest` examples that the tests run.

## 0.1.0 (2026-11-25)

First release on crates.io.


First release: an async `Client` on reqwest 0.13 and tokio for reading an audience's community: audience, locales,
closest locale, venues, people, events, event, event series, node and me, plus `community()` for all of them at once.
Credentials: audience service tokens (`akst_…`, traded at `POST /v1/token/service` and renewed before they expire or
when refused), people's sessions (sent to the instance that issued them, forgotten when refused) and bearer values
(application keys). The public listings (`GET /v1/public/listings`, `public:read` tokens). The module-tolerant
`undefinedField` retry with a per-client schema cache, `Client::from_env()` for goose-style configuration,
serializable models, and one `Error` type with the API's error vocabulary.
