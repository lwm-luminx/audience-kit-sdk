# Changelog

The PHP SDK (`php/`) keeps its own version, in `src/AudienceKit.php` (`AudienceKit::VERSION`), apart from the Swift
and Kotlin SDKs' `VERSION` and the Ruby gem's. Releases are tagged `php/<version>`.

## 0.2.0 (2026-11-24)

The PHP SDK catches up with the Swift, Kotlin, Node, Python and Rust SDKs (Rick, 2026-11-24: "build out the PHP sdk
and its documentation").

- **Models.** Every call returns a model (`AudienceKit\Model\Venue`, `Event`, `Person`, `Locale`, `Admission`,
  `Article`, …) with typed, read-only properties: dates as `DateTimeImmutable`, money as `Money`, points as
  `Coordinate`. A model is still readable as the API's JSON (`$venue['locale']['name']`), so code written for 0.1
  keeps working; `raw()` and `json_encode()` give that array. Code that checked `is_array()` on a result needs
  `instanceof` instead.
- **Sign-in.** `signInWithGoogle()` and `connectGoogle()`; `signInWithApple()` takes Sign in with Apple JS's
  authorization code, redirect URI and nonce; `signInWithReviewCode()` for App Review; `signInWithFacebookCode()`
  takes another Facebook app (Facebook Login for Business); `refreshSession()`; `deleteAccount()`.
- **Service tokens.** `useServiceToken('akst_…')` trades an audience service token at `POST /v1/token/service`, trades
  it again a minute before the session expires and once when the API refuses it, and sends calls to the instance that
  issued it. `useBearerToken()` sends an application API key as is. `AudienceSession::fromEnvironment()` reads
  `AUDIENCEKIT_TOKEN`, `AUDIENCEKIT_BASE_URL`, `AUDIENCEKIT_AUDIENCE_ID`, `AUDIENCEKIT_HOST` and
  `AUDIENCEKIT_ENVIRONMENT`. `Credential::$userId` is null for a service session, which carries `scopes` and
  `audience`; a credential with no `role` is a `member`'s.
- **Public listings** for websites (`public:read`): `publicListingsPage()`, `publicListings()`, `publicListing()`,
  `publicTonight()`. `community()` reads the audience, locales, venues, people, events and series in one go.
- **Soapbox news:** `articles()`, `articlesPage()` ("Show more"), `nationalArticles()`, `article()`,
  `articlesAbout()`, `publications()`, `localPublications()`, `publication()`, `myOpEds()`, `submitOpEd()`.
- **Calendar subscriptions:** `calendarFeed()`, `createCalendarFeed()`, `followVenueInCalendar()`,
  `deleteCalendarFeed()`.
- **Moderation:** `reportContent()` with `ReportTarget`'s targets and reasons, `blockUser()`, `unblockUser()`.
- **RSVP and cover:** `cancelRsvp()`, `eventRsvp()` (who's going), `buyCover()` takes a sliding-scale amount,
  `buyCoatCheck()`; admissions carry `kind`, `quantity`, `claimCheckNumber`, `fee` and `createdAt`, a venue's cover
  its coat check and scale, and `venueCover()` the viewer's coat check ticket.
- **Location:** `closestLocale()` takes a `Coordinate` (with a beacon), and `reportLocation()`.
- **Events** carry their KJ, DJ or VJ (`jockeys`, `jockeyLabel`) where the API has them; `Event::effectiveHosts()`
  makes a lone jockey the host.
- **`SessionCredentialStore`** keeps the credential in PHP's session, for websites that sign people in.
- **Docs:** [signing people in](docs/sign-in.md), [building a website](docs/websites.md) and a
  [reference](docs/reference.md) of every call and model.
- **Helpers:** `CoverPass::code()` makes a pass's door QR code (the same codes as the other SDKs), `Color` parses theme
  and tag colors, `Coordinate` parses WKT points and measures distance. `Queries::chatRoom()` is the chat subscription
  for apps with their own Action Cable client.

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
