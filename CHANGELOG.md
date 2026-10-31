# Changelog

One changelog for the whole SDK from 0.24.0 on. Earlier releases are in [swift/CHANGELOG.md](swift/CHANGELOG.md)
(through 0.23.0) and [android/CHANGELOG.md](android/CHANGELOG.md) (through 0.19.0).

## 0.34.0 (2026-10-31)

A lineup lists who's on, not an act's billing (Rick, 2026-10-31: Hot Mess showed "First Set"). Additive.

- Swift `LineupEntry.scenes` (each with its performers and when it went on and came off) and `afterSceneID` (a
  break inside an act). `VenueLineup.entries` lists an act with scenes as its scenes in turn (`LineupEntry.inTurn`),
  each with its performers and its own state and followed by the breaks after it; `onStageID` and `upNextID` name the
  scene (`LineupEntry.turnID`).
- `graphql/schema.graphql` is the API's consumer schema as of next.

## 0.33.0 (2026-10-31)

Keeping a production sign-in on Next (Rick, 2026-10-31). Additive; needs audience_kit_api #253 with
`TRUSTED_API_ORIGIN` set on the next API.

- Swift `AudienceKitConfiguration.trustedCredentialOrigins`: the API instances whose sign-ins `baseURL` takes. A
  credential one of them issued is sent to `baseURL` (GraphQL and `AudienceCable`) instead of its own instance;
  `apiBase(for:)` says where a credential goes. Empty by default, which keeps today's behaviour.

## 0.32.0 (2026-10-26)

The lineup's "+" and host-only lineups (Rick, 2026-10-26). Additive; the signup cutoff needs audience_kit_api #191,
and an API without it is asked again without those fields.

- Swift `SongRequestWindow`: `cutOff`, `reopened` and `closesAt` (signups and requests close by themselves near the
  end of the event or night, unless the venue reopens them), and `closed` (closed early or past the cutoff).
- AudienceKitUI `VenueLineupStrip(additions:)`: a "+" at the end of the lineup, on an empty lineup too, mirroring the
  lineup editor. `LineupAddition.karaoke(_:action:)` opens the signup and `.songRequests(_:action:)` a song request.
  It is greyed with the reason while nobody's on to take them, and becomes a "Signups closed" / "Requests closed"
  marker once they're closed for the night.
- A lineup of only hosts drops the running-order cards: "Hosted by A and B", side by side in billing order, avatars
  tapping through (`onSelectPerson`).
- `KaraokeQueue(showsSignUp:)` and `SongRequestsSection(showsRequestButton:)` leave their buttons out when the "+"
  takes over. Their closed lines say "Signups closed" / "Requests closed".

## 0.31.1 (2026-10-26)

- Swift: `AudienceSession.graphQL` checks `errors` before it decodes `data`, as Android has since 0.29.1. A refused
  mutation (`{"errors":[…],"data":{"field":null}}`) used to throw `AudienceKitError` with code `DECODING` and hide
  the refusal (Hot Mess iOS Quickie, terms not yet agreed).

## 0.31.0 (2026-10-25)

- Kotlin: `AudienceKitClient.signInWithReviewCode(code, device)` signs in with an App Review code (`POST
  /v1/token/review`), as Hot Mess for iOS does, and stores the session. A wrong or expired code throws
  `SignInRejected` with the API's reason.

## 0.30.0 (2026-10-24)

The SDK speaks only to an audience's consumer endpoint (`/graphql`) and knows nothing of staffql. Staff work lives in
StaffKit, which is built on the SDK and adds its staff endpoint itself. Breaking for staff tools that used the SDK's
staff calls directly; Hot Mess never should (a member's token at staffql signed new accounts out in Hot Mess 2.3).

- Swift: `GraphQLEndpoint` is a struct with only `.consumer`; a package adds others as
  `extension GraphQLEndpoint { static let staff = GraphQLEndpoint(rawValue: "staffql") }`. `allCases` is gone.
- Kotlin: `GraphQLEndpoint` is a data class with only `GraphQLEndpoint.CONSUMER`; a package adds others as extensions
  on `GraphQLEndpoint.Companion`. `entries` is gone.
- Swift: removed `doorVenues()`, `door(venueID:night:)`, `scanAdmission(venueID:code:)` and `Credential.isStaff`.
  StaffKit has its own door calls. The `DoorVenue`, `DoorNight` and `ScanResult` models stay.
- Both cables still name any endpoint but the consumer one in the subscription identifier.

## 0.29.1 (2026-10-24)

- Android: `AudienceKitClient.graphQL` checks `errors` before it decodes `data`. A refused mutation comes back as
  `{"errors":[…],"data":{"field":null}}`, and decoding that `data` into a non-null type used to throw
  `AudienceKitException.Decoding` and hide the refusal (Hot Mess Android Quickie, terms not yet agreed).

## 0.29.0 (2026-10-23)

Server-driven cards, for the API's `layout` query (audience_kit_api #45, #53, #62; on production since 2026-10-22). The
server ranks the cards of Now, Venues and People; the app draws them in that order and falls back to its own order when
the layout can't be had.

- `LayoutClient` fetches a screen's `CardLayout` with a 2 second timeout and returns the app's built-in order
  (`CardLayout.fallback`) offline, on an error or past the timeout. Kinds the app didn't list are left out.
- `CardRegistry` maps each card kind the app draws to what it renders; its `kinds` go to the server as `cardKinds`, and
  it skips any kind it doesn't know.
- `LayoutCard` carries the ids of the records it's about (venue, event, locale, venues, events, people), a web card's
  `CardContent`, or a promo slot's `PromoCard` candidates. A card or candidate that doesn't decode is dropped, not the
  layout.
- `CardFilter` picks a promo slot's first candidate whose category the viewer hasn't turned off; categories the
  audience publishes as not hideable (venues, events, announcements) are always shown.
- `CardPreferences` keeps the hidden categories on the device: iCloud key-value store with a `UserDefaults` fallback on
  Apple platforms, private shared preferences on Android (`audiencekit-android`, include it in Auto Backup). Never sent
  to the server.
- `cardCategories()` reads the published categories in the audience's words; `recordCardViews(promoIds, layoutId)`
  and `PromoViewRecorder` report promo cards on screen for a second or more, once per layout, signed in only.

## 0.28.0 (2026-10-22)

Karaoke only on karaoke nights, for the API's `Venue.karaoke.tonight` (audience_kit_api). Deploy that API first: the
lineup query asks for it.

- `VenueKaraoke.tonight` says whether tonight is one of the venue's karaoke nights (nil from an API that doesn't say),
  and `isPartnerSessionTonight` whether a partner's session (KaraFun) is the one to show tonight.
- AudienceKitUI's `KaraokeQueue` shows a partner's Join link and QR code only on karaoke nights. AudienceKit's own
  signups already follow `KaraokeWindow.permitted`, which the API now turns off on the venue's other nights.

## 0.27.0 (2026-10-22)

Show control, for the API's 2026-10-22 release (segments, scenes, curtain calls and group trivia). It's a separate
call from the lineup, so an older API only fails that call.

- `AudienceSession.show(venueID:)` returns a `VenueShow`. It has one `ShowEntry` per lineup entry, with:
  - its kind (`ACT`, `INTERMISSION` or `SEGMENT`) and activity (`TRIVIA`, `PROMPTS`)
  - curtain call minutes
  - scenes (each number of a set, with its performer and length)
  - estimated length, projected start and end, and minutes late

  `VenueShow` also has the next curtain call's readiness counts (`CurtainReadiness`, counts only) and tonight's
  latest trivia round.
- `TriviaRound` is a collaborative "Myth or Legend" round posted in the venue's chat. It carries the counts, the
  user's vote, and, once revealed, the answer and the room's call. `voteTrivia(roundID:choice:)` votes or changes a
  vote.
- AudienceKitUI adds `TriviaRoundCard`, the round as a chat card. Each choice shows how the room is split, and the
  card shows the answer once it's revealed.
- `graphql/schema.graphql` is the API's consumer schema with show control.

## 0.26.0 (2026-10-22)

- Kotlin: the Action Cable client moves into the SDK from the Hot Mess app, so the consumer and staff apps share it.
  `CableConnection` is the one socket every GraphQL subscription rides on, with reconnects and the silence watchdog;
  `GraphQLCable` builds and reads the frames. `subscribe(endpoint = GraphQLEndpoint.STAFF)` runs an operation in the
  staff view (`"endpoint": "staffql"` in its identifier, as on iOS). The handshake carries the token, the contract
  version, the client and, for staging builds, the environment header (`CableConnection(configuration, token, factory)`).
  The SDK has no websocket of its own: the app passes a `CableSocketFactory` on its HTTP stack (OkHttp's `newWebSocket`).

## 0.25.1 (2026-10-21)

- Kotlin: Sign in with Apple's URL encoding uses the `String` charset overloads of `URLEncoder`/`URLDecoder`. The
  `Charset` ones are Android 13+ only, so older devices crashed with `NoSuchMethodError`.

## 0.25.0 (2026-10-20)

GraphQL operations can be followed in an app's monitoring (New Relic, say), by name, over HTTP and over the cable.

- Every GraphQL request carries `X-APOLLO-OPERATION-TYPE` (`query`, `mutation`, `subscription`) and
  `X-APOLLO-OPERATION-NAME` (the `operationName` passed, else the name in the document). New Relic's mobile agents
  record both with each network request, so HTTP operations show up by name with no app changes.
- `GraphQLMonitor`, an optional hook the app hands the SDK: Swift `AudienceSession(..., monitor:)`, Kotlin
  `AudienceKitClient(..., monitor =)`. It hears about each HTTP operation (`GraphQLOperationEvent`: name, type, endpoint,
  duration, error).
- Swift: the session's cables report to the same monitor. Operations multiplexed over the one WebSocket get their own
  events (subscribed, result with time to first result, ended, rejected), and the socket gets `CableSocketEvent`s
  (connected, disconnected with the reason and whether it reconnects). The agents can't see inside the socket, so
  this is the only record of those operations.
- `GraphQLOperationEvent.describe(query:operationName:)` reads an operation's type and name from its document.
- Swift `APIRequest` and Kotlin `APIRequest` take extra `headers`.

## 0.24.0 (2026-10-20)

The Swift and Kotlin SDKs now live in one repository, lwm-luminx/audience-kit-sdk (formerly audience-kit-sdk-swift;
audience-kit-sdk-android is merged in with its history), laid out as `swift/`, `core/` (Kotlin Multiplatform) and
`android/`, and share one version. Kotlin jumps from 0.19.0 to 0.24.0 to
meet Swift (0.23.0); there are no API changes on either side beyond the fix below.

### Breaking (for builds, not code)

- Swift Package Manager: the package's URL is now `https://github.com/lwm-luminx/audience-kit-sdk.git` (the old URL
  redirects) and its identity is `audience-kit-sdk`, so `.product(name:package:)` references change to
  `package: "audience-kit-sdk"`. The sources moved to `swift/Sources`.
- Gradle: the build is the repository root (`audiencekit-core` in `core/`, `audiencekit` and `audiencekit-android` in
  `android/`), so composite builds point at the checkout itself.

### Fixed

- Swift: `tribes()` asks for `tags(tribes: true)`, as the Kotlin SDK does; `Audience.tribes` is no longer in the API's
  schema.

### Added

- `graphql/schema.graphql`, and CI checks both SDKs' GraphQL documents against it (Swift's weren't checked before).
