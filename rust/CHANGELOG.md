# Changelog

The Rust crate's own versions, separate from the Swift and Kotlin SDKs' [CHANGELOG.md](../CHANGELOG.md).

## 0.1.0 (2026-11-25)

First release on crates.io.


First release: an async `Client` on reqwest 0.13 and tokio for reading an audience's community: audience, locales,
closest locale, venues, people, events, event, event series, node and me, plus `community()` for all of them at once.
Credentials: audience service tokens (`akst_…`, traded at `POST /v1/token/service` and renewed before they expire or
when refused), people's sessions (sent to the instance that issued them, forgotten when refused) and bearer values
(application keys). The public listings (`GET /v1/public/listings`, `public:read` tokens). The module-tolerant
`undefinedField` retry with a per-client schema cache, `Client::from_env()` for goose-style configuration,
serializable models, and one `Error` type with the API's error vocabulary.
