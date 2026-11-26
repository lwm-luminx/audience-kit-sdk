# Node SDK reference

Everything in the `audience-kit` npm package, by what it is for. Every call returns a promise and can throw
`AudienceKitError`. The models are plain JSON as the API sends it, typed; the helpers below read the derived bits.

## AudienceKitClient

### Making one

| Call | What it does |
| --- | --- |
| `new AudienceKitClient({ configuration, tokenStore, transport, monitor })` | A client for one audience. Every option is optional. |
| `AudienceKitClient.fromEnvironment(env?, options?)` | Configured from `AUDIENCEKIT_TOKEN`, `AUDIENCEKIT_BASE_URL`, `AUDIENCEKIT_HOST`, `AUDIENCEKIT_AUDIENCE_ID` and `AUDIENCEKIT_ENVIRONMENT` (`process.env` unless given `env`). A token starting `akst_` is a service token; anything else is sent as a bearer token. |

`configuration` takes `baseUrl` (`https://api.audiencekit.com`), `host` (the host that names the audience),
`audienceId`, `facebookAppId` and `environment` (`production` or `staging`). `tokenStore` is a `TokenStore`
(`InMemoryTokenStore` by default), `transport` an `HttpTransport` (`FetchTransport`, which takes its own `fetch` and a
timeout), and `monitor` a function told about every GraphQL operation (`GraphQLOperationEvent`: name, type, endpoint,
duration, error).

### Signing in and out

| Call | Returns | What it does |
| --- | --- | --- |
| `signIn(facebookAccessToken, device)` | `Credential` | Trades a Facebook user access token. |
| `signInWithFacebookCode(code, redirectUri, device, facebookAppId?)` | `Credential` | Trades the code from Facebook's OAuth dialog. |
| `signInWithGoogle(idToken, device, { name, accessToken }?)` | `Credential` | Trades a Google ID token. |
| `signInWithApple({ identityToken, authorizationCode, redirectUri, nonce, firstName, lastName }, device)` | `Credential` | Trades a Sign in with Apple credential. |
| `signInWithReviewCode(code, device)` | `Credential` | Signs an App Reviewer in while the audience is in review. |
| `connectGoogle(idToken, device)` | `Credential` | Adds Google to the signed-in account. |
| `useServiceToken(token)` | `Credential` | Acts as the audience with a service token, renewed as needed. |
| `useBearerToken(token)` | | Sends an application API key (or a session JWT) as is. |
| `adopt(credential)` | | Uses a credential minted elsewhere. |
| `refreshSession()` | `Credential` | Re-issues the token for the same session. |
| `signOut()` | | Forgets the session. |
| `deleteAccount()` | `boolean` | Deletes the signed-in person's account for good, and signs out. |
| `isSignedIn()`, `sessionToken()` | | The stored session. |
| `onSession(listener)` | `() => void` | Hears `signedIn`, `signedOut` and `sessionEnded`; returns a function that stops listening. |
| `sessionRejected(token)` | `boolean` | Ends the session after a connection the SDK didn't make itself was refused. |

A `DeviceDescription` is `{ identifier, type?, model?, version?, build? }`: a stable identifier for the install or
server, and `node` (the default), `web`, `ios` or `android`.

### The audience and its listings

| Call | Returns |
| --- | --- |
| `branding(host?)` | `Branding`: the audience's public branding (no sign-in) |
| `audienceId()` | `string` |
| `audience()` | `Audience` |
| `me()` | `SelfUser \| null` |
| `venues()`, `people()`, `locales()` | `Venue[]`, `Person[]`, `AudienceLocale[]` |
| `closestLocale({ latitude, longitude })` | `AudienceLocale \| null` |
| `community()` | `Community`: the audience, locales, venues, people, upcoming events and series |
| `events({ window, localeId, venueId, first })` | `Event[]`, `UPCOMING` soonest first or `PAST` |
| `event(id)` | `Event \| null` |
| `eventSeries({ localeId, venueId, first })` | `EventSeries[]` |
| `venueDetail(id, recentMessages?)` | `VenueDetail \| null`: the venue's page, chat and upcoming events |
| `node(id)` | `Node \| null`: any record by its ID |
| `reportLocation(position, fields)` | what you selected: where the person is |

### Public listings

Needs a service token with `public:read`.

| Call | Returns |
| --- | --- |
| `publicListings()` | `PublicListing[]`, every page |
| `publicListingsPage(page)` | `PublicListingsPage`: `listings`, `pageCount`, `nextPage` |
| `publicListing("venue" \| "event" \| "post", id)` | `PublicListing \| null` |
| `publicTonight(venueId)` | tonight at the venue, as a screen facing the room shows it |

### Members

| Call | Returns | What it does |
| --- | --- | --- |
| `rsvp(eventId, state?)` | `EventRSVP` | `ATTENDING` (the default), `MAYBE`, `DECLINED` or `UNSURE`. |
| `cancelRSVP(eventId)` | `EventRSVP` | Takes the answer back. |
| `eventRSVP(eventId, first?)` | `EventRSVP \| null` | Who's going. |
| `tribes()`, `identifyWithTribe(tagId, isPrivate?)`, `leaveTribe(tagId)` | | The tribes people identify with. |
| `registerDevice(notificationToken)` | | Push notifications for this session's device. |
| `calendarFeed()`, `createCalendarFeed(reset?)` | `CalendarFeed` | The calendar subscription. |
| `followVenueInCalendar(venueId, following?)` | `CalendarFeed` | Every event at a venue in their calendar. |
| `deleteCalendarFeed()` | `boolean` | Ends the subscription. |
| `sendChatMessage(text, room, promptId?)` | `ChatMessage` | `room` is `{ kind: "venue" \| "locale", id }`. |
| `removeChatMessage(id)` | | Takes back their own message. |
| `reportContent(targetType, id, { reason, block }?)` | `ReportResult` | Reports to the audience's admins; offer `REPORT_REASONS`. |
| `blockUser(userId)`, `unblockUser(userId)` | | |

### Cover

| Call | Returns | What it does |
| --- | --- | --- |
| `venueCover(venueId)` | `VenueCover \| null` | Tonight's charge and the viewer's pass and coat check. |
| `venueOffers(venueId, night?)` | `AdmissionOffer[]` | Every way in on a night: cover and partner tickets. |
| `buyCover(venueId, amountCents?)` | `CoverPurchase` | Starts paying; `amountCents` on a sliding scale. |
| `buyCoatCheck(venueId, quantity?)` | `CoverPurchase` | Starts paying for coat check. |
| `confirmCover(admissionId)` | `Admission` | After Stripe. |
| `payCover(admissionId, sourceId, verificationToken?)` | `Admission` | With a Square payment token. |
| `refundAdmission(admissionId)` | `Admission` | Until it's scanned in or the night ends. |
| `admissions()` | `Admission[]` | Their passes, newest first. |

### News (Soapbox)

Every call returns nothing, rather than failing, for an audience without Soapbox.

| Call | Returns |
| --- | --- |
| `articles({ localeId, publicationId, first })` | `Article[]`, pinned first, then newest |
| `articlesPage({ localeId, publicationId, first, after })` | `ArticlesPage`: `articles`, `endCursor`, `hasNextPage` |
| `nationalArticles({ localeId, first })` | `Article[]` |
| `article(id)` | `Article \| null`, with `body` and what it's about |
| `articlesAbout("venue" \| "event" \| "person" \| "locale", id, first?)` | `Article[]` |
| `publications()`, `localPublications(localeId)` | `Publication[]` |
| `publication(id)` | `Publication \| null` |
| `myOpEds()` | `Article[]` with `status` and `reviewNote` |
| `submitOpEd({ publicationId, title, body, summary, byline })` | `Article` |

### Your own operations

| Call | What it does |
| --- | --- |
| `graphQL(query, { variables, operationName, endpoint, signal })` | Runs any document and returns its `data`. |
| `graphQLForShape(types, document, options)` | Runs a document built for the audience's modules, retrying with the schema's fields after an `undefinedField`. |
| `schemaFields(types, endpoint?)` | The fields each type has in the audience's schema, cached until sign-out. |
| `data({ method, path, query, body, authenticated, headers, signal })` | Calls a REST endpoint with the session and returns the body. |
| `url(string)` | Resolves a URL the API sent against the base URL. |

`Queries` exports every document and field list the client sends, so an app can extend them; `Queries.chatRoom(room)`
is the chat subscription for an app with its own Action Cable client.

## Helpers

| Function | What it does |
| --- | --- |
| `listingName(listing)`, `listingPage(listing)` | A venue's or person's name, falling back to its Facebook Page; the Page. |
| `locationCoordinate(location)`, `coordinateFromWkt(wkt)`, `coordinatesInput(coordinates)` | Points as `{ latitude, longitude }`, from and to the API's forms. |
| `localeGooglePlaceId(locale)` | A locale's Google place ID. |
| `eventVenue(event)`, `eventHosts(event)`, `eventLineup(event)`, `eventJockeys(event)` | An event's parts. |
| `eventHostedBy(event)`, `eventJockeyTitles(event)`, `jockeyTitle(label, name)` | Who runs the night, in words. |
| `eventTicketOffers(event)`, `eventCoverCharge(event)` | Its tickets and cover. |
| `isAdmissionPaid(admission)`, `isPurchasePaid(purchase)`, `isSquarePurchase(purchase)` | |
| `coverPassCode(admissionId, passSecret, epochSeconds?)` | The door code the apps show (`HMC1.…`); `isCoverPassCode()`, `coverPassWindow()`, `secondsUntilNextCoverPassWindow()`. |
| `colorFromHex(hex)`, `colorToCss(color)`, `themeColor(brandingTheme, token, dark?)` | Theme and tag colors. |
| `isPublicListing(listing)` | Whether anyone may see it in full. |
| `connectionItems(connection)` | A GraphQL connection's nodes, without nulls. |
| `REPORT_REASONS`, `INTIMATE_IMAGE_REASON` | The reasons to offer when reporting. |

`AudienceKitSDK` has `VERSION`, `API_VERSION` and `PRODUCTION_BASE_URL`. `Velvet` is for Velvet TV screens that run
JavaScript; see the [overview](../README.md#velvet-screens).

## Errors

`AudienceKitError` has a `code`: `NOT_SIGNED_IN`, `UNAUTHORIZED`, `SIGN_IN_REJECTED`, `SIGN_IN_FAILED`, `FORBIDDEN`,
`NOT_FOUND`, `HTTP` (with `status`), `NETWORK` (with `cause`), `DECODING`, `GRAPHQL` (with `errors`),
`MISSING_CONFIGURATION` or `TOKEN_STORAGE`. `isUnauthenticated` and `isUndefinedField` answer the common questions;
`graphQLErrorCode(entry)`, `graphQLErrorFields(entry)` and `graphQLErrorReason(entry)` read each GraphQL error.
