# Changelog

The `audience-kit` npm package keeps its own version, separate from the Swift and Kotlin SDKs' `VERSION`.

## 0.1.0 (2026-11-06)

First release: the consumer GraphQL API as the Swift and Kotlin SDKs speak it (API contract 2026-10-11), for Node 20+
and TypeScript.

- `AudienceKitClient`: sign in with a Facebook token or OAuth code, Google, Apple or an App Review code; refresh,
  adopt and end sessions, with `onSession` events; branding; the audience; venues, people, locales, the nearest locale
  and `reportLocation`; `me` and `node`; RSVPs; tribes; device registration; cover (passes, buying, paying, confirming,
  refunding); events, series and a venue's offers; venue pages; sending and removing chat messages; and `graphQL()`
  and `data()` for an app's own operations and REST calls.
- Queries follow the audience's modules: when the API refuses a field (`undefinedField`), the client asks the schema
  which fields exist and asks again with only those, then remembers the answer.
- `Queries`: every document, so apps can reuse the field lists; `coverPassCode` for the door's QR codes; WKT point and
  theme color parsing. Pluggable `TokenStore` and `HttpTransport` (fetch by default).
