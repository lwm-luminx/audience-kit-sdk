# Changelog

The PHP SDK (`php/`) keeps its own version, in `src/AudienceKit.php` (`AudienceKit::VERSION`), apart from the Swift
and Kotlin SDKs' `VERSION` and the Ruby gem's. Releases are tagged `php/<version>`.

## 0.1.2 (2026-11-08)

- License: `composer.json` names `LicenseRef-AudienceKit-SDK-1.2`, the [AudienceKit SDK License](../LICENSE) 1.2. No
  code changes.

## 0.1.1 (2026-11-08)

- License: `composer.json` now names the license, `LicenseRef-AudienceKit-SDK-1.1`. The SDK is source-available under
  the [AudienceKit SDK License](../LICENSE) 1.1: use only in apps that connect to AudienceKit as hosted by Love Wins
  Media, Inc.; any other use needs Love Wins Media's signed written permission and an audience ID or token issued for
  it. No code changes.

## 0.1.0 (2026-11-06)

First release: a PHP 8.1+ client for the AudienceKit consumer GraphQL API, with the same calls the Swift and Kotlin
SDKs make (Rick, 2026-11-06: "build PHP, Node, Python SDKs for audience-kit-sdk").

- `AudienceSession`: sign in with a Facebook token or OAuth code or an Apple identity token, adopt a credential minted
  elsewhere, switch audience, sign out; `graphQL()` runs any operation against `/v1/audience/<id>/graphql` on the API
  instance the credential names, with the SDK, API-version and environment headers every call carries; REST calls
  (`branding()`, `request()`) for what the schema doesn't cover; errors as `AudienceKitException` with the API's codes.
- The shared operations as array-returning helpers: `audience()`, `me()`, `venues()`, `people()`, `locales()`,
  `closestLocale()`, `events()`, `event()`, `eventSeries()`, `venueDetail()`, `venueCover()`, `venueOffers()`,
  `admissions()`, `buyCover()`, `payCover()`, `confirmCover()`, `refundAdmission()`, `rsvpEvent()`, `tribes()`,
  `identifyWithTribe()`, `leaveTribe()`, `registerDevice()`, `nodeType()`, `sendChatMessage()` and
  `removeChatMessage()`. Documents follow the audience's modules: when the API refuses a field (`undefinedField`) the
  SDK asks the schema which fields the types it reads have and runs the query again with only those.
- HTTP through any PSR-18 client and PSR-17 factories (found with php-http/discovery when none is given);
  `CredentialStore` for keeping the session wherever the app keeps secrets.
