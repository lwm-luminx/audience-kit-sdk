# PHP SDK reference

Everything in the `audiencekit/audiencekit` package, by what it is for. Classes are in the `AudienceKit` namespace;
models in `AudienceKit\Model`. Every call can throw `AudienceKitException`.

## AudienceSession

### Making one

| Call | What it does |
| --- | --- |
| `new AudienceSession(Configuration $configuration, CredentialStore $store, ?ClientInterface $http, ?RequestFactoryInterface, ?StreamFactoryInterface)` | A session for one audience. HTTP goes through any PSR-18 client; without one, `php-http/discovery` finds what's installed. |
| `AudienceSession::fromEnvironment(?array $environment)` | Configured from `AUDIENCEKIT_TOKEN`, `AUDIENCEKIT_BASE_URL`, `AUDIENCEKIT_AUDIENCE_ID`, `AUDIENCEKIT_HOST` and `AUDIENCEKIT_ENVIRONMENT`. A token starting `akst_` is a service token; anything else is sent as a bearer token. |

`Configuration` takes `baseUrl` (`https://api.audiencekit.com`), `host` (the host that names the audience),
`audienceId`, `facebookAppId`, `environment` (`Environment::PRODUCTION` or `Environment::STAGING`) and
`trustedCredentialOrigins`.

### Signing in and out

| Call | Returns | What it does |
| --- | --- | --- |
| `signInWithFacebookToken($accessToken, $device)` | `Credential` | Trades a Facebook user access token. |
| `signInWithFacebookCode($code, $redirectUri, $device, ?$facebookAppId)` | `Credential` | Trades the code from Facebook's OAuth dialog. |
| `signInWithGoogle($idToken, $device, ?$name, ?$accessToken)` | `Credential` | Trades a Google ID token. |
| `signInWithApple($identityToken, $device, ?$authorizationCode, ?$redirectUri, ?$nonce, ?$firstName, ?$lastName)` | `Credential` | Trades a Sign in with Apple credential. `signInWithAppleIdentityToken()` is the shorter form. |
| `signInWithReviewCode($code, $device)` | `Credential` | Signs an App Reviewer in while the audience is in review. |
| `connectFacebook($code, $redirectUri, $device)`, `connectGoogle($idToken, $device)` | `Credential` | Adds a provider to the signed-in account. |
| `useServiceToken($token)` | `Credential` | Acts as the audience with a service token, renewed as needed. |
| `useBearerToken($token)` | | Sends an application API key (or a session JWT) as is. |
| `adopt(Credential $credential)` | | Uses a credential minted elsewhere, or one you stored. |
| `refreshSession()` | `Credential` | Re-issues the token for the same session. |
| `switchAudience($audienceId)` | `Credential` | Moves a platform-console session to another audience. |
| `signOut()` | | Forgets the credential and revokes the token. |
| `deleteAccount()` | `bool` | Deletes the signed-in person's account for good. |
| `isSignedIn()`, `credential()`, `sessionToken()` | | The stored session. |
| `sessionRejected($token)` | `bool` | Forgets the session after a connection the SDK didn't make itself was refused. |

`DeviceDescription($identifier, $type = 'web', ?$model, ?$version, ?$build)` describes the browser or server signing
in.

### The audience and its listings

| Call | Returns |
| --- | --- |
| `branding(?$host, ?$app)` | `array`: the audience's public branding (no sign-in) |
| `audienceId()` | `string` |
| `audience()` | `Audience` |
| `me()` | `?SelfUser` |
| `venues()` | `list<Venue>` |
| `venueDetail($id, $recentMessages = 20)` | `?Venue`, with its profile, chat and upcoming events |
| `people()` | `list<Person>` |
| `locales()` | `list<Locale>` |
| `closestLocale(Coordinate $near)` or `closestLocale($latitude, $longitude)` | `?Locale` |
| `reportLocation(Coordinate $position, string $fields)` | `array` of the fields you select |
| `events($window = 'UPCOMING', ?$localeId, ?$venueId, $first = 100)` | `list<Event>`; `'PAST'` for what has ended |
| `event($id)` | `?Event` |
| `eventSeries(?$localeId, ?$venueId, $first = 100)` | `list<EventSeries>` |
| `community()` | `Community`: the audience, locales, venues, people, events and series |
| `nodeType($id)` | `?string`: which type a global ID names |

### Public listings (service token with `public:read`)

| Call | Returns |
| --- | --- |
| `publicListings()` | `list<PublicListing>`: every page |
| `publicListingsPage($page = 1)` | `PublicListingsPage` (`listings`, `pageCount`, `nextPage`) |
| `publicListing('venue' \| 'event' \| 'post', $id)` | `?PublicListing` |
| `publicTonight($venueId)` | `array`: tonight at a venue, as a room screen shows it |

### RSVP, tribes and notifications

| Call | Returns |
| --- | --- |
| `rsvpEvent($eventId, 'ATTENDING' \| 'MAYBE' \| 'DECLINED' \| 'UNSURE')` | `string`: the answer as stored |
| `cancelRsvp($eventId)` | `EventRSVP` |
| `eventRsvp($eventId, $first = 50)` | `?EventRSVP`, with the first attendees |
| `tribes()` | `['tribes' => list<Tag>, 'mine' => list<TribeIdentification>]` |
| `identifyWithTribe($tagId, ?$isPrivate)`, `leaveTribe($tagId)` | `list<TribeIdentification>` |
| `registerDevice($notificationToken, ?$appId, ?$sandbox)` | `bool` |

### Cover and coat check

| Call | Returns |
| --- | --- |
| `venueCover($venueId)` | `?VenueCover`: tonight's charge, and the viewer's pass and coat check ticket |
| `venueOffers($venueId, ?$night)` | `list<AdmissionOffer>`: every way in on a night |
| `buyCover($venueId, ?$amountCents, $currency = 'usd')` | `CoverPurchase` |
| `buyCoatCheck($venueId, $quantity = 1)` | `CoverPurchase` |
| `payCover($admissionId, $sourceId, ?$verificationToken)` | `Admission` (Square) |
| `confirmCover($admissionId)` | `Admission` (Stripe) |
| `refundAdmission($admissionId)` | `Admission` |
| `admissions()` | `list<Admission>` |

### News (Soapbox)

| Call | Returns |
| --- | --- |
| `articles(?$localeId, ?$publicationId, ?$first)` | `list<Article>` |
| `articlesPage(?$localeId, ?$publicationId, $first = 20, ?$after)` | `ArticlesPage` (`articles`, `endCursor`, `hasNextPage`) |
| `nationalArticles(?$localeId, ?$first)` | `list<Article>` |
| `article($id)` | `?Article`, with its body and subjects |
| `articlesAbout('venue' \| 'event' \| 'person' \| 'locale', $id, ?$first)` | `list<Article>` |
| `publications()`, `localPublications($localeId)` | `list<Publication>` |
| `publication($id)` | `?Publication` |
| `myOpEds()` | `list<Article>`, with `status` and `reviewNote` |
| `submitOpEd($publicationId, $title, $body, ?$summary, ?$byline)` | `Article` |

### Calendar subscriptions

| Call | Returns |
| --- | --- |
| `calendarFeed()` | `?CalendarFeed` |
| `createCalendarFeed($reset = false)` | `CalendarFeed` |
| `followVenueInCalendar($venueId, $following = true)` | `CalendarFeed` |
| `deleteCalendarFeed()` | `bool` |

### Chat and moderation

| Call | Returns |
| --- | --- |
| `sendChatMessage($message, ['venueId' => …] or ['localeId' => …], ?$promptId)` | `ChatMessage` |
| `removeChatMessage($messageId)` | `string`: the removed ID |
| `reportContent(ReportTarget::…, $id, ?$reason, $block = false)` | `ReportResult` (`reported`, `blocked`) |
| `blockUser($userId)`, `unblockUser($userId)` | |

`ReportTarget` has the targets (`MESSAGE`, `PERSON`, `PHOTO`, `PING`, `PRIVATE_MESSAGE`, `POST`, `POST_COMMENT`,
`VENUE`) and `REASONS`, the reasons the apps offer. Keep `ReportTarget::INTIMATE_IMAGE`'s wording: the API gives
those reports a 48-hour deadline.

### Your own operations

| Call | Returns |
| --- | --- |
| `graphQL($query, ?$variables, ?$operationName, $endpoint = GraphQLEndpoint::CONSUMER)` | `array`: the response's `data` |
| `shapedGraphQL($types, callable $document, ?$variables, $operationName)` | `array`: built for the audience's modules |
| `schemaFields($types)`, `cachedSchemaFields($types)` | `array<string, list<string>>` |
| `request(ApiRequest $request)` | `string`: a REST response's body |
| `url($string)` | `?string`: a URL the API sent, made absolute |

`Queries` has every document the SDK sends, and the field lists to build your own from (`Queries::eventFields()`,
`Queries::ADMISSION_FIELDS`, `Queries::chatRoom()` for an Action Cable client…).

## Models

Each model has typed, read-only properties and is also readable as the API's JSON (`$model['field']`, `raw()`,
`json_encode()`). `Model::from($json)` and `Model::list($json)` build them from arrays you cached.

| Model | Properties |
| --- | --- |
| `Audience` | `id`, `name`, `subdomain`, `theme`; `color($token, $dark)` |
| `SelfUser` | `id`, `name`, `firstName`, `lastName`, `emailAddress`, `isAdmin`, `presence` |
| `Profile` | `id`, `name`, `avatarUrl` |
| `Locale` | `id`, `name`, `label`, `cityNames`, `bannerUrl`, `placeId` |
| `Location` | `id`, `coordinate`, `address`, `placeId` |
| `Venue` | `id`, `name`, `hidden`, `order`, `photoUrl`, `bannerUrl`, `locale`, `location`, `tags`, `facebookPage`; on its page `description`, `address`, `phone`, `website`, `socialLinks`, `chatOpen`, `recentMessages`, `upcomingEvents`; `coordinate()` |
| `Person` | `id`, `name`, `avatarUrl`, `bannerUrl`, `order`, `global`, `likeRequired`, `tags`, `locales`, `facebookPage`, `homeVenue`, `involvements` |
| `Event` | `id`, `name`, `description`, `startAt`, `endAt`, `isFeatured`, `isCanceled`, `bannerUrl`, `sourceUrl`, `locale`, `tags`, `venueName`, `venue`, `rsvp`, `rsvpCount`, `hosts`, `lineup`, `jockeys`, `jockeyLabel`, `ticketUrl`, `offers`, `cover`; `effectiveHosts()`, `hasEnded()` |
| `EventSeries` | `id`, `name`, `description`, `recurrenceText`, `startsOn`, `startTime`, `timeZone`, `durationMinutes`, `bannerUrl`, `locale`, `tags`, `venueName`, `venue` |
| `EventRSVP` | `count`, `mine`, `mineSource`, `going`, `interested`, `tickets`, `attendees`; `isGoing()`, `attendeeProfiles()` |
| `Tag` | `id`, `name`, `colorHex`, `tribe`; `color()` |
| `TribeIdentification` | `isPrivate`, `tag` |
| `Money` | `cents`, `currency`; `amount()`, `format($locale)` |
| `CoverCharge` | `amount`, `fee`, `total`, `night`, `from`, `payable`, `event`, `coatCheck`, `scaleMin`, `scaleMax`, `scaleSuggested`; `isSlidingScale()`, `hasCoatCheck()` |
| `Admission` | `id`, `status`, `kind`, `night`, `quantity`, `tier`, `claimCheckNumber`, `amount`, `fee`, `total`, `isRefundable`, `passSecret`, `scanCount`, `checkedInAt`, `createdAt`, `profile`, `venue`, `event`; `isPaid()`, `passCode()` |
| `AdmissionOffer` | `price`, `url`, `sellerKey`, `sellerName` |
| `CoverPurchase` | `admission`, `provider`, `paymentIntentClientSecret`, `publishableKey`, `stripeAccountId`, `squareApplicationId`, `squareLocationId` |
| `VenueCover` | `id`, `name`, `charge`, `viewerAdmission`, `viewerCoatCheck` |
| `ChatMessage` | `id`, `body`, `name`, `userId`, `avatarUrl`, `photoUrl`, `sentAt`, `role`, `kind`, `title`, `pinned` |
| `Article` | `id`, `slug`, `title`, `summary`, `byline`, `kind`, `publishedAt`, `edited`, `pinned`, `teaser`, `canonicalUrl`, `disclosure`, `heroPhotoUrl`, `heroAltText`, `publication`, `body`, `subjects`, `viewerAdFree`, `featuredNationally`, `status`, `reviewNote`, `submittedAt` |
| `Publication` | `id`, `name`, `masthead`, `about`, `websiteUrl`, `photoUrl`, `trusted`, `acceptsOpEds`, `opEdGuidelines`, `locale`, `person`, `adFreeOffered`, `adFreeTipCents`, `adFreeDays` |
| `CalendarFeed` | `url`, `webcalUrl`, `googleUrl`, `venueIds`; `follows($venueId)` |
| `PublicListing` | `kind`, `id`, `path`, `visibility`, `title`, `description`, `address`, `phone`, `website`, `listed`, `image`, `startAt`, `endAt`, `venueName`, `ticketUrl`, `isCanceled`, `coverCents`; `isPublic()` |
| `Page` | A Facebook Page: `id`, `name`, `photoUrl`, `bannerUrl` |

`ArticlesPage`, `PublicListingsPage`, `Community` and `ReportResult` are plain value objects.

## Credentials and stores

`Credential` has `token`, `userId` (null for a service session), `audienceId`, `role` (`member`, `admin`,
`venue_device`, `service`…), `endpoint`, `venueDeviceId`, `expiresAt`, `apiVersion`, `scopes` and `audience`, with
`isExpired()`, `expiresWithin($seconds)`, `isService()`, `hasScope($scope)`, `origin()`, `fromArray()` and
`toArray()`.

`CredentialStore` is the interface (`load()`, `save()`, `delete()`); `InMemoryCredentialStore` lasts as long as the
object and `SessionCredentialStore` keeps the credential in `$_SESSION`.

## Helpers

| Class | What it does |
| --- | --- |
| `Coordinate` | A latitude and longitude, with an optional beacon. `fromWkt()`, `toWkt()`, `toInput()`, `distanceTo()` in meters. |
| `Color` | `fromHex()`, `fromTheme($theme, $token, $dark)`, `toCss()`, `toHex()`. |
| `CoverPass` | `code($admissionId, $passSecret, ?$epochSeconds)` makes a pass's door code (`HMC1.<id>.<window>.<signature>`), the same one the apps show; `isCode()`, `window()`, `secondsUntilNextWindow()`. |
| `AudienceKit` | `VERSION`, `API_VERSION`, the header names and `isOlder()`. |

## Errors

`AudienceKitException` carries `errorCode` (a constant on the class), the HTTP `status`, the GraphQL `errors`, for
`INVALID` per-field messages in `fields`, and for `UPDATE_REQUIRED` the `minimumSdkVersion`. `isUnauthenticated()` and
`isUndefinedField()` answer the common questions.
