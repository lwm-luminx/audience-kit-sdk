# Changelog

The `audience-kit` npm package keeps its own version, separate from the Swift and Kotlin SDKs' `VERSION`.

## 0.4.0 (2026-11-26)

What a consumer website asks the API, moved here from hotmess.social so its pages use the SDK instead of their own
calls:

- `Website`: `new Website.WebsiteClient(client)` with the website's pages (`now`, `whereAmI`, `venue`, `event`,
  `person`, `post`, `viewerId`), the poster builder (`posterSearch`, `posterNights`, `posterSeries`, `posterVenue`,
  `posterEvent` with its year-long share link, `posterCover`, `printSafetyPoster`), safety alerts (`venueSafety`,
  `sendSafetyAlert`, `updateSafetyAlert`, `remindSafetyAlert`, `cancelSafetyAlert`, `sendSafetyAlertMessage`,
  `safetyAlert`, `mySafetyAlerts`, `supportResources`, `supportRides`) and privacy choices (`privacy`,
  `updatePrivacyChoices`, `startPrivacyPass`). `Website.Queries` holds the documents, validated against the schema
  like every other, and the models type what they select.
- Its public REST calls: `signInMethods`, `shareLink` (status and card), `invitation`, `rateCard`,
  `communityResourceLocales`, `communityResources`, `publicShortLink`, the cover poster (`coverPoster`,
  `startGuestCover`, `confirmGuestCover`) and the safety poster's guest alerts (`safetyPoster`, `sendGuestSafetyAlert`,
  `guestSafetyAlert`, `updateGuestSafetyAlert`, `remindGuestSafetyAlert`, `cancelGuestSafetyAlert`,
  `messageGuestSafetyAlert`).
- `signInWithGoogleAccessToken()`: Google sign-in from a browser's token client, which gives no ID token.
- Fixed: `FetchTransport` called the global `fetch` as a method of the transport, which browsers and Cloudflare Workers
  refuse ("Illegal invocation"); it now works there, where the website runs.
- `"sideEffects": false`, so a browser bundle can leave out the parts it doesn't use.
- A failed REST call's `AudienceKitError` now carries its HTTP `status` for every code, and the API's error body as
  `apiCode`, `faultMessage` (the message), `fields` and `reason`.

## 0.3.0 (2026-11-26)

Everything a website, bot or backend job needs, at the level of the PHP SDK, with guides and examples:

- Service tokens: `useServiceToken()` trades an `akst_…` token at `POST /v1/token/service` for an hour-long session,
  trades it again a minute before it runs out (once, however many calls ask together) and once more when the API
  refuses it. `useBearerToken()` sends an application API key as is. `AudienceKitClient.fromEnvironment()` reads
  `AUDIENCEKIT_TOKEN`, `AUDIENCEKIT_BASE_URL`, `AUDIENCEKIT_HOST`, `AUDIENCEKIT_AUDIENCE_ID` and
  `AUDIENCEKIT_ENVIRONMENT`.
- Public listings (`public:read`): `publicListingsPage()`, `publicListings()`, `publicListing(kind, id)`,
  `publicTonight(venueId)`, and `isPublicListing()`.
- `community()`: the audience, locales, venues, people, upcoming events and event series in one call, a part whose
  module the audience lacks coming back empty.
- Soapbox news: `articles()`, `articlesPage()`, `nationalArticles()`, `article()`, `articlesAbout()`,
  `publications()`, `localPublications()`, `publication()`, `myOpEds()` and `submitOpEd()`; empty, not failing, for an
  audience without Soapbox.
- Calendar subscription: `calendarFeed()`, `createCalendarFeed()`, `followVenueInCalendar()`, `deleteCalendarFeed()`.
- Moderation and the account: `reportContent()` (with `REPORT_REASONS`), `blockUser()`, `unblockUser()` and
  `deleteAccount()`.
- `docs/` (signing people in, building a website, the reference) and `examples/`, which the tests run against a stub
  API. Both are published on developer.audiencekit.com.

## 0.2.0 (2026-11-25)

- `Velvet`: what a Velvet TV screen that runs JavaScript (Samsung TVs on Tizen) needs. `VenueDeviceClient` pairs the
  screen by QR code (`startPairing`, `claimPairing`, platform `tizen`) or a typed code (`redeem`), keeps the sign-in in
  the storage it's given, runs GraphQL on the device's staff endpoint and follows subscriptions over the API's Action
  Cable (`GraphQLCable`, browser WebSocket, reconnecting). `tvBoard` and `applyChatEvent` build the board message the
  Velvet cast receiver draws, ported from the Google TV's `tvBoard` and `TVRoom` with its test cases; `Velvet.Queries`
  holds the screen's GraphQL, checked against the staff schema.
- graphql/staff_schema.graphql updated from the API (adds the `SAMSUNG_TV` display kind).

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
