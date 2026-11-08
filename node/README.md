# AudienceKit Node SDK

Node.js and TypeScript client for the [AudienceKit](https://audiencekit.com) API: sign people in, then read an
audience's venues, people, locales, events, cover and chat over GraphQL, the same calls the Swift and Kotlin SDKs make.

- Node 20+ (uses the global `fetch`), ESM and CommonJS, typed throughout
- No runtime dependencies. The login itself (Facebook, Google, Apple) stays in your app: the SDK takes the token it
  gives you.

## Installation

```sh
npm install audience-kit
```

## Configure a client

```ts
import { AudienceKitClient } from "audience-kit";

const client = new AudienceKitClient({
  configuration: {
    baseUrl: "https://api.audiencekit.com", // the default
    host: "hotmess.admin.audiencekit.com",  // or the audience's verified domain
    facebookAppId: "<your Facebook app ID>", // the Facebook app this build signs in with
  },
});
```

| Setting | What it does |
| --- | --- |
| `baseUrl` | The API. `http://localhost:3000` for a local server. |
| `host` | Names the audience. Sent with sign-in so the API checks the token against the audience's own apps and binds the session to the audience, and used to fetch branding. `<subdomain>.admin.audiencekit.com` works for every audience; the audience's own domain works once it's verified. |
| `audienceId` | The audience's UUID. Optional: the client reads it from the session, or looks it up from `host`. |
| `facebookAppId` | The Facebook app the build uses (production, staging or development). It must be one of the audience's apps. |
| `environment` | `staging` makes the API sign people in with the audience's staging Facebook app (`X-AudienceKit-Environment`). |

Options beside `configuration`: a `tokenStore` (the session's token and audience; `InMemoryTokenStore` by default, so a
server or CLI keeps the session wherever it keeps secrets by implementing `TokenStore`), a `transport` (an
`HttpTransport`; `FetchTransport` by default, which takes its own `fetch` and timeout), and a `monitor` told about
every GraphQL operation.

## Sign in

Run the login in your app, then exchange what it gives you. Every sign-in takes a `DeviceDescription`, which the API
records with the session:

```ts
const device = { identifier: "server-1", model: "MacBookPro18,3", version: "2.0", build: "42" };

const session = await client.signIn(facebookAccessToken, device);
// or
await client.signInWithFacebookCode(code, redirectUri, device);
await client.signInWithGoogle(idToken, device, { accessToken });
await client.signInWithApple({ identityToken, authorizationCode, nonce }, device);
await client.signInWithReviewCode("REVIEW-1", device);

console.log(`Signed in as ${session.userId} in audience ${session.audienceId}`);
```

Each calls `POST /v1/token` (or its variant), which answers with the session's `Credential`: `token`, `userId`,
`audienceId`, `role`, the GraphQL `endpoint` the token was issued for, `venueDeviceId` and `expiresAt`. The SDK stores
it and sends the token on every later call as `Authorization: Bearer <token>`, together with
`X-AudienceKit-API-Version`, the API contract it speaks (`AudienceKitSDK.API_VERSION`). A credential minted elsewhere
becomes the session with `client.adopt(credential)`; `client.refreshSession()` re-issues the token; `client.signOut()`
forgets it.

Sign-in can fail with code `SIGN_IN_REJECTED` (the token is invalid, or from an app the audience doesn't use) or
`SIGN_IN_FAILED` (the message is the API's).

## Session ends

Sessions don't expire, but they end when the person signs out elsewhere or removes the app from Facebook. Then any call
throws an `AudienceKitError` with code `UNAUTHORIZED` (`error.isUnauthenticated`), the client forgets the credential,
and `onSession` listeners get `sessionEnded`, once per session however many calls were refused:

```ts
const stop = client.onSession((event) => {
  if (event === "sessionEnded") showSignIn();
});
```

## Read the audience

```ts
const audience = await client.audience();
const venues = await client.venues();
const people = await client.people();
const locales = await client.locales();
const nearest = await client.closestLocale({ latitude: 37.77, longitude: -122.42 });
const me = await client.me();
const events = await client.events({ window: "UPCOMING", localeId: locales[0]?.id, first: 50 });
const event = await client.event(events[0]!.id);
const series = await client.eventSeries();
const page = await client.venueDetail(venues[0]!.id);
const offers = await client.venueOffers(venues[0]!.id, "2026-12-31");
```

Queries follow the audience's modules. The API leaves a module's fields out of an audience that hasn't installed it
(Facebook Pages, Google Places, Listings, RSVP, People, Ticketing, Cover, Chat), and asking for one fails the whole
query. When the API refuses a field (`undefinedField`), the client asks the schema which fields the types it reads have
(`client.schemaFields()`, cached until sign-out) and runs the query again with only those; later queries go straight to
the right document. An audience with every module makes one call. A part a module adds (`event.rsvp`, `event.tickets`,
`venue.profile`) is absent on an audience without it.

The models are plain JSON as the API sends it, with helpers for the derived bits: `listingName(venue)` falls back to
the Facebook Page's name, `locationCoordinate(location)` parses the API's WKT point, `eventVenue(event)`,
`eventHosts(event)`, `eventTicketOffers(event)`, `connectionItems(connection)` and so on.

## Act

```ts
await client.rsvp(event.id, "ATTENDING");
await client.cancelRSVP(event.id);
const going = await client.eventRSVP(event.id, 50);

const { available, mine } = await client.tribes();
await client.identifyWithTribe(available[0]!.id, true);
await client.leaveTribe(available[0]!.id);

await client.registerDevice(pushToken);
const here = await client.reportLocation({ latitude, longitude }, "venue { id name } locale { id }");

await client.sendChatMessage("hello", { kind: "venue", id: venue.id });
await client.removeChatMessage(message.id);
```

### Cover

```ts
const cover = await client.venueCover(venue.id);   // tonight's charge and the viewer's pass
const purchase = await client.buyCover(venue.id);  // then pay with Stripe's payment sheet…
await client.confirmCover(purchase.admission.id);  // …and confirm, or for Square:
await client.payCover(purchase.admission.id, squareNonce);
const passes = await client.admissions();
const qr = coverPassCode(pass.id, pass.passSecret!); // what the door scans, changes every 30 seconds
await client.refundAdmission(pass.id);
```

## Your own operations

`client.graphQL(query, { variables, operationName })` runs any document against the audience's consumer endpoint and
returns its `data`; errors in the response throw a `GRAPHQL` error, even alongside data (`error.errors`, and
`graphQLErrorCode(entry)`, `graphQLErrorFields(entry)` and `graphQLErrorReason(entry)` read each one). The `Queries`
export has every document and field list the SDK uses, so an app can extend them, and `Queries.chatRoom(room)` is the
chat subscription for an app with its own Action Cable client (this SDK doesn't open sockets).
`client.data({ method, path, query, body })` calls a REST endpoint with the session.

## Errors

Everything throws `AudienceKitError`, with a `code`: `NOT_SIGNED_IN`, `UNAUTHORIZED`, `SIGN_IN_REJECTED`,
`SIGN_IN_FAILED`, `FORBIDDEN`, `NOT_FOUND`, `HTTP` (`status`), `NETWORK` (`cause`), `DECODING`, `GRAPHQL` (`errors`),
`MISSING_CONFIGURATION` or `TOKEN_STORAGE`.

## Development

```sh
cd node
npm install
npm run check   # typecheck, tests with coverage (85% floor), build
```

The tests run offline against a stub transport, and `test/schema.test.ts` validates every document against
[`graphql/schema.graphql`](../graphql/schema.graphql), the API's consumer schema. The package keeps its own version in
`package.json` (and `src/version.ts`, which a test keeps in step), separate from the Swift and Kotlin SDKs' `VERSION`.
To publish, bump both, add a changelog entry and run `npm publish` from `node/`; `.npmrc` stops `npm version` from
pushing a bare version tag, which the Swift package's release tags share.

## License

Source-available under the [AudienceKit SDK License](../LICENSE) 1.1 (`LicenseRef-AudienceKit-SDK-1.1`), © Love Wins
Media, Inc.: use it only in apps that connect to AudienceKit as hosted by Love Wins Media. Every other use is
prohibited without Love Wins Media's written permission and an audience ID or token issued for that use. See the
[root README](../README.md#license) for details.
