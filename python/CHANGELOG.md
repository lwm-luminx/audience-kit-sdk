# Changelog

The Python package's own versions, separate from the Swift and Kotlin SDKs' [CHANGELOG.md](../CHANGELOG.md).

## 0.2.0 (2026-11-26)

Service tokens renewed before they run out and re-traded once after a refusal (`Client.from_environment()`,
`use_service_token()`, `use_bearer_token()`); the public listings (`public_listings()`, `public_listing()`,
`public_tonight()`); `community()`; Soapbox news and op-eds; cover and coat check (`venue_cover()`, `buy_cover()`,
`buy_coat_check()`, `pay_cover()`, `confirm_cover()`, `refund_admission()`, `admissions()`) with `cover_pass_code()`
for the door; chat messages; the calendar feed; reporting and blocking; `cancel_rsvp()`; `delete_account()`; sign-in
with Google and App Review codes, and Sign in with Apple JS's authorization code. Guides in `docs/` and runnable
programs in `examples/`.

## 0.1.0 (2026-11-25)

First release: `Client` and `AsyncClient` on httpx with the shared calls the apps use (audience, venues, people,
locales, closest locale, events, event, event series, me, node, tribes, RSVP, device registration), sign-in with
Facebook, Facebook Login for Business and Sign in with Apple, service-token and saved-credential adoption, branding,
the module-tolerant `undefinedField` retry with a per-session schema cache, and `AudienceKitError` with the API's
error vocabulary.
