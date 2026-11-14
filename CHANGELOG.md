# Changelog

One changelog for the whole SDK from 0.24.0 on. Earlier releases are in [swift/CHANGELOG.md](swift/CHANGELOG.md)
(through 0.23.0) and [android/CHANGELOG.md](android/CHANGELOG.md) (through 0.19.0).

## 0.63.0 (2026-11-14)

- Ad-free audiences (Rick, 2026-11-14: "begin building advertising"). `advertising()` reads whether the audience is
  open to sponsors or ad-free (`AudienceAdvertising`, `.open` / `.adFree`, `OPEN` / `AD_FREE` on Android) and who
  pays for it (`adFreeSponsor`). `adFreeNote` gives what "Cards you see" can say ("Ad-free, thanks to …"). An ad-free
  audience's layouts already come without promoted cards, so the apps don't filter anything themselves. Needs
  audience_kit_api #560; older servers throw, so treat a failure as open. An unknown mode reads as open. Same on iOS
  and Android.

## 0.62.0 (2026-11-14)

- Readable text on an audience's accent (Rick, 2026-11-14: "the lime color of hack different has white (low contrast
  text on it)"). `Branding.Theme.onAccent(dark:)` and `foreground(on:dark:)` give the color for text and icons on an
  `accent` (or any `token`) fill: the theme's `on-<token>` when it reaches WCAG AA 4.5:1 on that fill, otherwise
  near-black (#111411, `RGBAColor.inkOnLight` / `INK_ON_LIGHT`) or white, whichever has more contrast. `RGBAColor`
  gains `relativeLuminance`, `contrastRatio(with:)` and `readableForeground`. Apps that skin from `/v1/branding`
  should use these instead of white on the accent: on Hack Different's lime (#c5f467) white is 1.3:1 and the derived
  dark text is 14.6:1. Same on iOS and Android.

## 0.61.0 (2026-11-14)

- Flagged messages for Velvet (Rick, 2026-11-14: "build some amount of the message flag / decision UX into velvet for
  message that are flagged (simplified)"). `FlaggedMessage`, `FlaggedMessageAction` (Dismiss, Remove, Warn, Cooldown,
  Escalate, Ban), the shared GraphQL (`FlaggedMessages.query` / `reviewMutation` with their variables and responses)
  and `FlaggedMessageCopy`, in AudienceCore on iOS and `com.audiencekit` on Android, word for word. They run on the
  staff endpoint, so StaffKit sends them; `availableActions` leaves only Dismiss and Escalate for the room's own
  people. Needs audience_kit_api #544.

## 0.60.0 (2026-11-14)

- Android parity with Hot Mess iOS 2.7 (Rick, 2026-11-14: "fill the gaps"). Kotlin `titles(personId)` reads a
  performer's community titles (pageant crowns, Imperial Court reigns, club titles, chapter leads; the API's
  `PersonOffice::TITLES`), reigning first, as the Swift `titles(personID:)` does; `PersonOffice.detail` is the place
  and years under each. Kotlin `AppCheck` and `GraphQLOperationLog` port "Check the app" from Swift: the same steps,
  OK/EMPTY/FAIL/SKIP marks and plain-text report, with the client's recent failed requests (the log is a
  `GraphQLMonitor` and can pass events on to another; the Android `AudienceKitClient(context, …)` factory now takes a
  `monitor`). Compose apps draw their own screen from `AppCheck.state`.

## 0.59.0 (2026-11-13)

- GitHub and GitHub Projects (Rick, 2026-11-13: "integrate github sdk and projects into hack different"). The API's
  new `github` module reads the community's GitHub organization with the audience's own GitHub App: its public
  repositories and its public Projects (v2) with each item's Status. `gitHubCommunity(repositories:)` reads the
  organization, repositories and projects for a GitHub tab; `gitHubProject(number:)` reads one project's README and
  items, which `GitHubProject.columns` groups into a board by Status; `myGitHubItems()` lists the items assigned to
  the signed-in person's connected GitHub account. `GitHubCopy` has the shared words. Audiences without a GitHub App
  get nil/empty, so apps can call them unconditionally. Needs audience_kit_api with the github module.

## 0.58.0 (2026-11-12)

- Local news on Now (Rick, 2026-11-12: "a few articles from publishers cards into now for your locale").
  `CardKind.articlesLocale` (`ARTICLES_LOCALE` on Android) is the API's new `articles.locale` card: when the viewer's
  locale has recent articles from its publishers (Soapbox, including teasers from publishers' RSS feeds), the Now
  layout ranks a "Local news" card after Coming up. It arrives as a `PostsCard` with the locale's id
  (`LayoutCard.localeID`), so the layout query is unchanged and works against any API; load the articles with
  `articles(about: .locale(id), first: 3)` (`articlesAbout(ArticleTopic.Locale(id), first = 3)` on Android). An API without the kind never sends it.

## 0.57.0 (2026-11-11)

- `StaffApp.velvet(venueID:audienceID:eventID:)` (and `velvet(venueId, audienceId, eventId)` on Android) links to an
  event at a venue: `audiencekit-velvet://venue?id=<venue>&audience=<audience>&event=<event>`. Velvet 1.10 opens the
  venue and then the event's page, so Hot Mess can say "Open in Velvet" on events at venues the person manages.

## 0.56.0 (2026-11-11)

- Community titles (Rick, 2026-11-11: titles reuse offices, audience_kit_api #518). `OfficeKind` gains
  `pageantTitle`, `courtTitle`, `clubTitle` and `chapterLead`, with `isTitle`: a Hot Mess crown or Imperial Court
  reign, a club title (Mr. Leather), a Hack Different chapter lead. `offices(at:localeID:status:titles:)` keeps only
  titles (true) or only civic offices (false), filtered in the SDK so it works against an API from before titles;
  `OfficeHolder.titles` and `civicOffices` split a person's page; `[PersonOffice].only(titles:)`.
  `titles(personID:)` reads just someone's titles (a `PersonTitles` query), for a performer's page in Hot Mess.
- graphql/schema.graphql is copied again from the API's next (the title kinds and `titles:` arguments).

## 0.55.0 (2026-11-11)

- Community chats (Rick, 2026-11-11: link Hack Different's hackerspaces and conferences to the chats they use).
  `SocialLink.isCommunityChat` picks out `discord`, `matrix`, `irc` and `mailing_list` links, `networkName` names the
  network ("Matrix", "IRC", "Mailing list"), and `communityChats` on `Event` and `VenueDetail` lists them. Events
  carry their own links (`Event.socialLinks`, the API's new `Event.socialLinks`, such as DEF CON's Discord or 40C3's
  Matrix space): `event(id:)` asks for them, lists leave them out to keep their cost down, and an API without the
  field gets the query again without it.
- `CommunityChatLinks` (AudienceKitUI): "Join on Discord", "Join on Matrix", "Join on IRC" and "Mailing list" buttons
  that open each chat.
- `graphql/schema.graphql` updated from the API.

## 0.54.0 (2026-11-11)

- AudienceKit's own cards and credit (Rick, 2026-11-10: "I'm my own first advertising client"). Promo cards in the new
  `audiencekit` category are labelled "From AudienceKit", can't be hidden, and carry `staffApp` (velvet, backstage or
  focus) when they're about getting a staff app. `CardFilter.installedStaffApps` skips those on a phone that already
  has the app, checked on the device, so the server never learns. On an API without `PromoCard.staffApp` the layout
  asks again without it.
- `StaffApp` (AudienceCore, and `com.audiencekit.StaffApp` on Android): Focus, Velvet and Backstage with their names,
  App Store and Android IDs, URL schemes, download links (audiencekit.com/apps/<app>/) and deep links
  (`StaffApp.velvet(venueID:audienceID:)`, `StaffApp.backstage(personID:audienceID:)`). `StaffAppLink`
  (AudienceKitUI) opens the app when it's installed and its download page when it isn't ("Open in Velvet", "Join the
  Velvet beta", "Get Backstage"); `StaffApps.installed(context)` in audiencekit-android checks the packages.
- `PlatformCredit` and `PlatformCreditFooter` (AudienceKitUI): "Powered by AudienceKit", "A Love Wins Media product",
  audiencekit.com's Privacy, Terms, Child safety and Contact pages, "Bring AudienceKit to your venue" and the
  copyright line, with links tagged `utm_source=<bundle>&utm_medium=app`. The same words and links on Android.

## 0.53.0 (2026-11-11)

- "Check the app", moved out of the DNC demo app so every app gets it (Rick, 2026-11-11: shared features belong in the
  SDK). `GraphQLOperationLog` (AudienceCore) is a `GraphQLMonitor` that keeps the last 100 operations and their errors,
  writes failures to the unified log (category `graphql`), and passes everything on to the app's own monitoring.
  `AppCheck` runs the app's steps (each one OK, empty, failed or skipped, timed) and builds a plain-text report;
  `AppCheckView` (AudienceKitUI) is the screen, with "Copy report" and the recent failed requests. Empty screens
  caused by a refused query, which apps hid behind `try?` (DNC's events, Hack Different's catalog), now show up there.
- New `AudienceKitTesting` library for apps' unit tests: `GraphQLStub` answers an audience's GraphQL from a closure,
  records each request, hands out a signed-in member `AudienceSession`, and `withinComplexityBudget(perItem:)`
  refuses an over-budget page with the API's own error, so a page size the server would turn away fails in a test.
- CI checks the documents the SDK builds from a `SchemaShape` (events, locales, offices, Soapbox and others) against
  the API schema too: `RenderedDocumentsTests` writes them out and the graphql job validates them. The source check
  skipped all 16 of them, including every query the DNC demo app reads.
- License 1.2 (Rick, 2026-11-08): no license of any kind is granted beyond the express grant (no implied, estoppel or
  trademark rights); misrepresenting the SDK or Love Wins Media's work (authorship, origin, notices, endorsement) is
  expressly prohibited and a material breach; Modifications may be made only in a fork of the repository, after
  written notice to Love Wins Media (a "Derived work notice" issue). The Earlier versions section now points to the
  README's list, so the same text can be used in StaffKit. Package metadata says `LicenseRef-AudienceKit-SDK-1.2`.
- License: the SDK moves from the MIT License to the [AudienceKit SDK License](LICENSE) (Rick, 2026-11-06), now
  version 1.1 (Rick, 2026-11-08). The SDK is source-available, not open source: it may be used only in apps that
  connect to AudienceKit as hosted by Love Wins Media, and every other use is prohibited unless Love Wins Media, Inc.
  permits it in a signed written agreement and issues an audience ID or token for that use. 1.1 also adds patent
  terms and a 30-day cure on notice, and lists exactly which releases stay MIT (Swift tags through 0.41.0, source
  through 0.42.0, the `audience-kit` gem 0.1.0 and 0.1.1). Package metadata now says so: `LicenseRef-AudienceKit-SDK-1.1`
  in the gemspec, `composer.json` and `pyproject.toml` (with the `License :: Other/Proprietary License` classifier),
  `SEE LICENSE IN LICENSE` in the npm package (which now ships the file, as the Python release does), and a POM
  `<licenses>` entry on every Maven publication.

## 0.52.0 (2026-11-10)

- Civic organizing in Swift, for the DNC demo app (Rick, 2026-11-10; the API's `PersonOffice`, audience_kit_api #477).
  `AudienceSession.offices(at:localeID:status:)` gives someone's representatives and candidates, most local first (the
  API's root `offices`), each with its holder and their `DonationTarget`; `officeHolder(id:)` reads one person's page
  (offices, Donate target, website, social accounts, upcoming events, and the voter issues they share with the
  signed-in person). New models: `OfficeKind` (unknown kinds kept), `OfficeStatus`, `PersonOffice`, `OfficeLocale`,
  `OfficeHolderSummary`, `OfficeHolder`, `DonationTarget`, `SocialAccount`. An audience without offices gets none back
  (the documents drop fields its schema lacks). Kotlin follows.
- graphql/schema.graphql is copied again from the API's next (offices, nested locales, donation targets).

## 0.51.0 (2026-11-10)

- App Review sign-in is never offered in an App Store install (Rick, 2026-11-10). Swift: `InstallSource.offersReviewCode`
  (false only for `.appStore`; App Review runs builds in StoreKit's sandbox like TestFlight, so reviewers still see it),
  `InstallSource.signedAppTransaction` (the AppTransaction JWS), `AudienceSession.reviewCodeAvailable()` (install source
  plus `GET /v1/token/review`) and `signIn(reviewCode:device:)`, which sends the AppTransaction as `app_transaction` so
  the API refuses the code for an App Store install (403, reason `store_install`). Android is unchanged: Play can't tell
  a reviewer's install from anyone else's, so the code stays gated by App Review mode there.

## 0.50.0 (2026-11-10)

- Device attestation at sign-in (Rick, 2026-11-10; the API's doc/DEVICE_ATTESTATION.md, audience_kit_api #459). Every
  sign-in now asks `POST /v1/token/attestation` for a one-use challenge and sends proof over it as `attestation`, so an
  audience can refuse tokens minted anywhere but its genuine app on a genuine device. Apps change nothing beyond
  updating the SDK:
  - Swift: `AppAttestAttestor` (App Attest / DeviceCheck), on by default on iOS (`AudienceSession`'s new
    `deviceAttestor:` parameter, `AppAttestAttestor.platformDefault`). The first sign-in from an install attests a
    Secure Enclave key; later ones send an assertion. The key ID is kept in `UserDefaults`
    (`UserDefaultsAttestationKeyStore`). Simulators send `unsupported` without a challenge round trip.
  - Kotlin: `DeviceAttestor` and `AudienceKitClient(deviceAttestor = …)`; `audiencekit-android` adds
    `PlayIntegrityAttestor` (Play Integrity, `com.google.android.play:integrity`), on by default in
    `AudienceKitClient(context, configuration)`.
  - When the audience enforces attestation and the device fails, sign-in throws `AudienceKitError` code
    `DEVICE_NOT_TRUSTED` (Swift) or `AudienceKitException.DeviceNotTrusted` (Kotlin, a new subclass). When the API
    doesn't know an App Attest key (a restored backup), the SDK makes a new one and retries once. When the audience has
    attestation off, or the API is older, nothing extra is sent.

## 0.49.0 (2026-11-10)

- Swift: read-only chat rooms. A room that mirrors a provider's channel (the API's read-only Discord bridge) sends
  `ChatRoomEvent.readOnly(replyURL:)` right after `.joined`: signed-in people read and report its messages, sending
  fails, and `replyURL` opens the channel on Discord to reply there. The subscription now asks for `ChatJoined`'s
  `readOnly` and `replyUrl`, so it needs an API with them (audience_kit_api #428). `.readOnly` is a new case, so
  exhaustive switches over `ChatRoomEvent` need it. Kotlin follows.

## 0.48.0 (2026-11-09)

- Soapbox (Swift and Kotlin): articles from the audience's publications (a newspaper such as QSaltLake, a candidate)
  and op-eds readers send them. `articles(localeID:publicationID:first:)` is a locale's or a publication's news,
  `article(id:)` reads one with its Markdown body and what it's about, `articles(about:)` (Kotlin `articlesAbout`)
  lists a venue's, event's, person's or locale's "In the news", `publications()` / `publication(id:)` back a
  publication page, `myOpEds()` shows where the signed-in person's op-eds stand, and `submitOpEd(...)` sends one.
  Articles carry the publication's `disclosure` (show it above the article) and `teaser` (link to `canonicalUrl`
  instead of a body). Audiences without the Soapbox module get empty lists and nil, never an error. `SoapboxCopy`
  keeps the apps' words the same. Needs audience_kit_api #436 (on next).
- `graphql/schema.graphql` is the API's consumer schema as of next, with Soapbox.

## 0.47.0 (2026-11-09)

- Connect Discord (Swift and Kotlin): someone who signed in another way (Sign in with Apple, say) connects their
  Discord account so the audience's Discord bridge knows them as the same person. `DiscordConnection` makes the
  verifier and the API's authorize URL and reads the `audiencekit-discord://callback` hand-back;
  `connectDiscord(...)` posts it with `connect: true` and stores the session the API returns; `connectedDiscord()`
  reads `me { self { signedInWithDiscord discordUsername } }` (nil on an API older than those fields). iOS also gets
  `AudienceKitUI`'s `ConnectDiscordButton` (iOS 16.4+, ASWebAuthenticationSession); Android apps declare an intent
  filter for scheme `audiencekit-discord`, host `callback`. `ConnectDiscordCopy` keeps both apps' words the same.
  Needs audience_kit_api #427.

## 0.46.2 (2026-11-08)

- The audience-less endpoint's docs and tests name the API's `/v1/staffql`: selfQL (`/v1/selfql`) is gone (Rick,
  2026-11-08). The pathed `/v1/audience/<id>/staffql` stays the same sign-in scoped to one audience. No code change.

## 0.46.1 (2026-11-08)

- `DeleteAccountCopy` warning (Swift and Kotlin) now says deleting removes the account in this app only, with any
  staff or admin role in it, and leaves the person's accounts in other AudienceKit apps alone. Account deletion is per
  audience (Rick, 2026-11-08): an app built on AudienceKit can't wipe what someone did in another app. Needs
  audience_kit_api's per-audience `deleteAccount`; this replaces 0.45.1's "every app" wording.

## 0.46.0 (2026-11-08)

- `GraphQLEndpoint` can be audience-less (`GraphQLEndpoint(rawValue:audienceless:)` in Swift, `audienceless = true`
  in Kotlin): its path is `/v1/<segment>` and calls to it need no audience. StaffKit uses it for the API's
  audience-less `/v1/staffql`: one staff sign-in's audiences and the listings it manages, in no audience or any
  number of them (Rick, 2026-11-08); `/v1/audience/<id>/staffql` stays the same sign-in scoped to one audience. `path(audienceID:)` takes an optional ID.

## 0.45.1 (2026-11-07)

- `DeleteAccountCopy` warning (Swift and Kotlin) now says deleting removes the account in every AudienceKit app,
  including Hot Mess and Hack Different, and any staff or admin roles, since accounts are shared across apps.

## 0.45.0 (2026-11-07)

Report and block in the SDK (Rick, 2026-11-07, for Hack Different's Google Play and App Store review: Play's
user-generated content policy and App Store guideline 1.2), so apps stop hand-writing them as Hot Mess did.

- `reportContent` (Swift `reportContent(_:id:reason:block:)`, Kotlin `reportContent(targetType, targetId, reason,
  block)`) with `ReportTarget` and `ReportResult`: files a report with the audience's admins, and can block the person
  behind it in the same call.
- `blockUser` / `unblockUser` for a member's user id.
- `ReportCopy` (Swift and Kotlin): the same report and block wording, and report reasons, on both platforms.

## 0.44.0 (2026-11-07)

Delete account in the SDK (Rick, 2026-11-07, for Hack Different's App Store review: guideline 5.1.1(v) and Google
Play's account deletion rule), so apps stop hand-writing it as Hot Mess did.

- `deleteAccount()` on the client (Swift and Kotlin): `deleteAccount(input: { confirm: true })`. When the API says the
  account is gone, the session is forgotten on this device and `signedOut` is sent; otherwise they stay signed in.
- SwiftUI: `DeleteAccountButton(client:appName:onDeleted:)` asks first, shows progress and errors.
- `DeleteAccountCopy` (Swift and Kotlin): the same confirmation and failure wording on both platforms.

## 0.43.0 (2026-11-06)

Calendar sync in the SDK (Rick, 2026-11-06: "sync one venue to my calendar like 801labs" in Hack Different), so apps
stop hand-writing it as staff-kit did. Needs the API's `setCalendarFeedVenue` and `CalendarFeed.venues`
(audience_kit_api #398).

- `CalendarFeed` (links plus the venues it follows) and `CalendarLinks` (https, webcal:// and Google Calendar links).
- `calendarFeed()`, `createCalendarFeed(reset:)`, `deleteCalendarFeed()`: the person's one private subscription.
- `followVenueInCalendar(venueID:following:)`: adds every event at a venue to that same feed (one subscription, not a
  calendar per venue). The feed reads as the person, so a venue that bans them drops out.
- SwiftUI: `VenueCalendarButton` (Add to Calendar on a venue, then offers to subscribe), `CalendarSubscribeMenu` and
  `CalendarSubscribeButtons`. Android: `Context.subscribeToCalendar`, `addToGoogleCalendar`, `copyCalendarLink` in
  audiencekit-android.
- `graphql/schema.graphql` is the API's next schema with those fields.

## 0.42.0 (2026-11-06)

Tests for the shared calls apps are moving onto, with a Fable review for gaps line coverage hides, and fixes for what
they found (Rick, 2026-11-06: "build out this testing"). Line coverage is 86.8% on Swift (Linux) and 90.7% on Kotlin,
up from 81.7% and 82.3%, and CI now fails under 85% on either (`scripts/swift-coverage.sh`, Kover's `koverVerify`).

- Android: a chat room the server refuses (`ChatRoomUpdate.Refused`) now ends the flow, as documented; it stayed open.
- One chat message or roster entry that doesn't decode (a bad date, a missing id) is left out of a join instead of
  losing the whole `joined` event (Swift) or failing the flow with a raw serialization error (Android).
- Swift: the cable ends the session on an `unauthorized` disconnect even when the frame doesn't say `reconnect: false`
  (it reconnected with the dead token), runs an operation once however often the channel is confirmed, and ignores
  results for an operation the current socket hasn't confirmed, as Android already did.
- WKT points that aren't on Earth (NaN, infinity, out of range, often latitude and longitude swapped) decode as no
  coordinate on both platforms.
- The promo view recorder reports one promo seen in two layouts in each of them (the second overwrote the first).
- Android: `venueDetail` reports a venue that doesn't decode as `AudienceKitException.Decoding`, like every other call.

## 0.41.1 (2026-11-06)

Hack Different's events came back empty: `events()` and `eventSeries()` asked for `first: 100`, and the API costs a
page as `first` times an event (about 75 with every module), far over its 1000 complexity budget, so the query was
refused. Fixed.

- `events(window:localeID:venueID:first:)` and `eventSeries(localeID:venueID:first:)` take `first` as optional and
  leave it out by default, so the API returns every upcoming event at the cost of one.
- `venueDetail` shows the venue's next five events (was twenty, also over budget with the chat history).

## 0.41.0 (2026-11-06)

What Hack Different still queried itself after moving to 0.40, so the app can drop its last ticketing queries.
Additive.

- Events carry their offers: `Event.ticketOffers` (every way in on sale, whichever module sells it: tickets on partner
  listings and the night's cover, as `AdmissionOffer` with price, URL and seller) and `Event.coverCharge` (the Cover
  module's charge for that night). Both are nil where the audience doesn't have the module.
- `venueOffers(venueID:night:)` lists every way into a venue on a night (tonight by default).
- `venueCover(venueID:)` follows the audience's modules too: without Ticketing or Cover it returns the venue with no
  charge instead of failing.
- `venueDetail(id:recentMessages:)` takes how many chat messages to load (20 by default, the API's most).

## 0.40.0 (2026-11-06)

Apps no longer write their own GraphQL for what every AudienceKit app shows (Rick, 2026-11-06: "apps should be easily
built with little custom code"). Hack Different's hand-written event queries decoded a venue's point as numbers rather
than WKT and showed no events; these come from the SDK now, on Swift and Android. Additive.

- Queries follow the audience's modules. The API leaves a module's fields out of an audience that hasn't installed it
  (Facebook Pages, Google Places, Listings, RSVP, People, Ticketing, Friends), and asking for one failed the whole
  query, so `venues()`, `locales()`, `people()` and `closestLocale()` came back as errors for Hack Different. When the
  API refuses a field (`undefinedField`), the SDK asks the schema which fields the types it reads have
  (`schemaFields(of:)`, introspection, cached for the session) and runs the query again with only those; later
  queries go straight to the right document. An audience with every module still makes one call.
- Events: `events(window:localeID:venueID:first:)`, `event(id:)` and `eventSeries(localeID:venueID:first:)`, with
  `Event` (its venue with a decoded location, RSVP, hosts and lineup, ticket URL; nil without the module),
  `EventSeries`, `EventVenue`, `EventPerson` and `EventWindow`. Android: `EventRSVPSummary` and `Connection<T>`.
- Venue pages: `venueDetail(id:)` returns `VenueDetail` (description, address, phone, website, social links, whether
  chat is open and its recent messages, upcoming events).
- Chat: `ChatMessage`, `ChatRoom` (`.venue`/`.locale`), `sendChatMessage(_:in:promptID:)`, `removeChatMessage(id:)`,
  and the room's subscription: `AudienceCable.chat(_:watch:audienceID:)` (Swift) and `CableConnection.chat(…)`
  (Android) stream `ChatRoomEvent`s (joined with roster, history and pin; posted, updated, removed, pin changed,
  cleared, presence, range, left).

## 0.39.0 (2026-11-04)

Update prompts compare build numbers only within the branch that made them (Rick, 2026-11-04): main and next builds
share Xcode Cloud's counter, so main's TestFlight installs were offered next's betas. Additive.

- `AppRelease.testFlightBeta` (`testflight_beta`): the TestFlight channel for betas (next and feature branches);
  `testFlight` is main's archives. `AppRelease.forBeta()` reads the beta channel as TestFlight's.
- `AudienceUpdates(isBeta:)` and `AudienceUpdates.configure(…, isBeta:)`: a beta build is compared with the beta
  channel, and gets no TestFlight prompt when there is none.

## 0.38.0 (2026-11-02)

Coat check on Android, as Hot Mess iOS has it (Android parity, 2026-11-02). Additive.

- `AudienceKitClient.buyCoatCheck(venueId, quantity)`: starts paying tonight's coat check, paid the same way as
  cover (Stripe's payment sheet then `confirmCover`, or Square's token then `payCover`).
- `CoverCharge.coatCheck` (`CoatCheck`: amount, fee, total, night, payable) and `VenueCover.viewerCoatCheck`.
- `Admission.kind` (`AdmissionKind.COVER` / `COAT_CHECK`, `isCoatCheck`), `quantity`, `tier` and `claimCheckNumber`;
  `Queries.ADMISSION_FIELDS` asks for them.

## 0.37.0 (2026-11-02)

The Venues screen's Everywhere view lists locales, each with some of its venues in turn, and opens a locale's own
screen (Rick, 2026-11-02). Additive.

- `LayoutScreen.everywhere` / `EVERYWHERE`: a `locales.showcase` card per locale (`CardKind.localesShowcase` /
  `LOCALES_SHOWCASE`), carrying the locale and a few of its venues to rotate through. The viewer's locale comes first.
- `LayoutScreen.locale` / `LOCALE`: one locale's screen (pass its id as the locale id): `events.upcoming`,
  `venues.tonight`, `venues.all`, plus announcements and promo slots.

## 0.36.0 (2026-10-31)

A Mac app keeps its sign-in across rebuilds (Rick, 2026-10-31: Arbiter's keychain items didn't match the M4 build's
signature). Additive.

- `KeychainCredentialStore(dataProtection:)` keeps the item in the data protection keychain on the Mac, which goes by
  the app's team and bundle ID, instead of the file keychain, whose items open only for the exact signature that saved
  them. Off by default; the app must be signed with a provisioning profile. No change on iOS.

## 0.35.0 (2026-10-31)

The lineup strip snaps to who's on (Rick, 2026-10-31).

- `VenueLineupStrip` snaps card by card (iOS 17 and macOS 14 on) and rests on the act on now, with a hint of the one
  done before it at the leading edge (`VenueLineupStrip.peek`, 64 points), following as the venue advances. Earlier
  systems keep scrolling freely to the act on now.
- Blank space after the last card lets the act on now reach that spot even when little or nothing follows it.

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
