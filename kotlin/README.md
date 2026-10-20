# AudienceKit Android SDK

Kotlin client for the AudienceKit API, for Android apps (and any JVM): sign people
in with Facebook, then read an audience's venues, people, locales and events over
GraphQL, and its branding over REST. It matches the [Swift SDK](https://github.com/audience-kit/audience-kit-sdk-swift)
call for call.

- Kotlin coroutines: every call is a `suspend` function that's safe on the main thread
- Facebook Login stays in your app: the SDK takes the access token Facebook gives you
- Three libraries:
  - `com.audiencekit:audiencekit-core`: a Kotlin Multiplatform prototype containing
    GraphQL variables, coordinates and endpoint routing, shared by JVM and Apple targets.
  - `com.audiencekit:audiencekit`: the client, models and GraphQL. Plain JVM, so it
    runs in unit tests without an emulator. Depends only on kotlinx-coroutines and
    kotlinx-serialization, and talks HTTP over `HttpURLConnection`.
  - `com.audiencekit:audiencekit-android`: `KeystoreTokenStore` and
    `DeviceDescription.current(context)`. Android 8.0 (API 26) and up.

## Installation

The SDK isn't published to a Maven repository yet. Build it into your app with a
Gradle composite build: check this repository out next to your app and add to the
app's `settings.gradle.kts`:

```kotlin
includeBuild("../audience-kit-sdk-android")
```

then depend on it as if it were published:

```kotlin
dependencies {
    implementation("com.audiencekit:audiencekit-android:0.19.0")
}
```

Or run `./gradlew publishToMavenLocal` here and add `mavenLocal()` to the
app's repositories.

## Configure a client

```kotlin
import com.audiencekit.AudienceKitConfiguration
import com.audiencekit.android.AudienceKitClient

val client = AudienceKitClient(
    context = applicationContext,
    configuration = AudienceKitConfiguration(
        baseUrl = "https://api.audiencekit.com",   // the default
        host = "hotmess.admin.audiencekit.com",    // or the audience's verified domain
        facebookAppId = "842337999153841",          // the Facebook app this build signs in with
    ),
)
```

Create one client for the app (in your `Application`, or your DI graph) and share it.

| Setting | What it does |
| --- | --- |
| `baseUrl` | The API. `http://10.0.2.2:3000` reaches a local server from the emulator. |
| `host` | Names the audience. Sent with sign-in so the API checks the Facebook token against the audience's Facebook apps and binds the session to the audience, and used to fetch branding. `<subdomain>.admin.audiencekit.com` works for every audience; the audience's own domain works once it's verified. Without a host, the API only accepts tokens from the AudienceKit platform Facebook app. |
| `audienceId` | The audience's UUID. Optional: the client reads it from the session token, or looks it up from `host`. |
| `facebookAppId` | The Facebook app the build uses (production, staging or development). It must be one of the audience's apps. |

`AudienceKitClient(context, configuration)` keeps the session token in a
`KeystoreTokenStore`: encrypted with an AES key held in the Android Keystore, and
usable from background work. Leave its preferences file (`com.audiencekit.session`)
out of your backup rules. The core constructor,
`AudienceKitClient(configuration, tokenStore, transport)`, takes any `TokenStore`
(`InMemoryTokenStore` is for tests and previews) and any `HttpTransport`, so you can
route the SDK through your own OkHttp client.

## Sign in

Run Facebook Login in your app, then exchange its access token:

```kotlin
import com.audiencekit.DeviceDescription
import com.audiencekit.android.current

val device = DeviceDescription.current(context) // ANDROID_ID, model, versionName and versionCode
val result = client.signIn(facebookAccessToken = AccessToken.getCurrentAccessToken()!!.token, device = device)
Log.i("Auth", "Signed in as ${result.userId} (${result.role}) on ${result.audienceId}")
```

This calls `POST /v1/token`, whose JSON says everything about the session (`userId`,
`audienceId`, `role`, `endpoint`, `venueDeviceId`, `expiresAt`), so the app never
decodes the JWT. The SDK stores the token and the audience id and sends the token on
every later call as `Authorization: Bearer <token>`. `refreshSession()` re-issues the
token (`POST /v1/token/refresh`) for the same session.

Sign-in can fail with `AudienceKitException.SignInRejected` (the Facebook token is
invalid, or from an app the audience doesn't use) or `AudienceKitException.SignInFailed`.

### Sign in with Apple

Android has no Sign in with Apple of its own, so `AppleWebSignIn` runs Apple's web sign-in in a Custom Tab with a
Services ID. Apple posts the result to the API (`/v1/token/apple/callback`), which hands it back to your app on
`audiencekit-apple://callback`, so declare that on the activity that takes it:

```xml
<intent-filter>
    <action android:name="android.intent.action.VIEW" />
    <category android:name="android.intent.category.DEFAULT" />
    <category android:name="android.intent.category.BROWSABLE" />
    <data android:scheme="audiencekit-apple" android:host="callback" />
</intent-filter>
```

```kotlin
val apple = AppleWebSignIn(servicesId, AppleWebSignIn.callbackUrl(baseUrl), context.packageName)
// Keep apple.state and apple.nonce until the result comes back.
CustomTabsIntent.Builder().build().launchUrl(context, Uri.parse(apple.authorizationUrl()))

// In onNewIntent:
when (val result = apple.result(intent.data.toString())) {
    is AppleWebSignIn.Result.Credential -> client.signInWithApple(result, apple, device)
    AppleWebSignIn.Result.Cancelled -> Unit
    is AppleWebSignIn.Result.Failed -> showError(result.reason)
}
```

The nonce never leaves the app (Apple gets its SHA-256), and the API signs in with Apple only with it, so a token
picked up in the browser can't be used elsewhere. The Services ID's return URLs must include the callback URL; see
the API's `doc/TOKENS.md`, "Sign in with Apple on Android".

## Session ends

Sessions don't expire, but they end when the person signs out elsewhere or
removes the app from Facebook. Then any call throws
`AudienceKitException.Unauthorized`, the client deletes the token, and
`sessionEvents` emits `SessionEvent.SESSION_ENDED`. Collect it from one place to
send the person back to sign-in:

```kotlin
lifecycleScope.launch {
    client.sessionEvents.collect { event ->
        if (event == SessionEvent.SESSION_ENDED) showSignIn()
    }
}
```

`client.signOut()` forgets the session on the device. Log out of Facebook in
your app as well.

## Read the audience

```kotlin
val venues = client.venues()     // List<Venue>: page name and photos, locale, location
val people = client.people()     // List<Person>
val locales = client.locales()   // List<AudienceLocale>
val me = client.me()             // SelfUser?: me { self }, your own profile
val audience = client.audience() // name, subdomain, theme tokens

for (venue in venues) {
    println("${venue.name} ${venue.location?.coordinate} ${client.url(venue.page?.photoUrl)}")
}
```

Objects' `id` fields are the records' UUIDs, the same IDs the REST endpoints
and `node(id)` take; there is one ID per record everywhere.

Run any other operation and decode it into your own `@Serializable` type:

```kotlin
@Serializable data class VenueNames(val venues: List<Venue>) {
    @Serializable data class Venue(val id: String, val page: Page)
}

val names = client.graphQL<VenueNames>(
    "query VenueNames { venues { id page { ${Queries.PAGE_FIELDS} } } }",
    operationName = "VenueNames",
)
```

Build variables with `graphQLVariables("id" to venueId, "limit" to 10)`, which
converts strings, numbers, booleans, enums, lists, maps and `Coordinates`. If the
response has `errors`, the call throws `AudienceKitException.GraphQL` with each
error's message, path and extensions. Decoding ignores fields the SDK doesn't
know, so new API fields don't break shipped apps; pass `json = …` to decode with
your own settings.

## Branding

Branding is public, so you can skin the app before sign-in:

```kotlin
val branding = client.branding() // GET /v1/branding?host=<host>
branding.audience.name
branding.theme.tagline
branding.theme.color("accent", dark = isSystemInDarkTheme())?.let { Color(it.toArgb()) }
```

`DesignTokens` carries the whole design system: every theme's colours (`DesignTokens.hotMess`,
`.hotMessDark`, `.light`, `.dark`), the presets by key (`DesignTokens.presets["hot_mess"]`), and
`Spacing`, `Radius`, `Size`, `Opacity` and `Typography`. It's generated from
`admin/src/design/tokens.json` by `bun run tokens` in `admin/`, so don't edit it by hand. Overlay the
audience's `branding.theme` overrides on its preset's colours.

## Mobile operations

The calls the Hot Mess apps make for the signed-in member:

```kotlin
val here = Coordinates(latitude = 37.77, longitude = -122.42)
val locale = client.closestLocale(near = here)            // AudienceLocale?
client.setRSVP(RSVPState.ATTENDING, eventId = eventId)    // mirrored to Facebook
client.registerDevice(notificationToken = fcmToken)       // Firebase Cloud Messaging token
```

`reportLocation` records where the member is and says where that is: the
`venue` they're in, else their `locale` and its `nearbyVenues`. Select the
fields you need, including the module mixins the screen reads (such as
`venue { friends { list { name } } }` or `audience { me { ping { friendPings { id } } } }`),
and decode into your own type:

```kotlin
@Serializable data class ReportLocation(val reportLocation: MyNow)

val now = client.graphQL<ReportLocation>(
    Queries.reportLocation("venue { id name } locale { id name } nearbyVenues { id name distance }"),
    variables = graphQLVariables("position" to here),
).reportLocation
```

The API also serves `venue(id:)`, `event(id:)`, `person(id:)` and `locale(id:)`
by UUID, `venues(near:)` nearest first with each `distance`, and each
locale's and venue's upcoming `events`.

## Cover charge

Members can pay a venue's cover in the app and show a pass at the door. A venue's
`coverCharge` (tonight's price; `payable` when it can be paid in the app) and the
member's `viewerAdmission` come with `venueCover`:

```kotlin
val cover = client.venueCover(venueId)                  // VenueCover?: coverCharge, viewerAdmission
val purchase = client.buyCover(venueId)                 // CoverPurchase
```

For a Square venue (`purchase.isSquare`), take a card or Google Pay with Square's
In-App Payments SDK (`InAppPaymentsSdk.squareApplicationId = purchase.squareApplicationId`)
and send its nonce:

```kotlin
val admission = client.payCover(purchase.admission.id, sourceId = nonce)  // AdmissionStatus.PAID
```

For a Stripe venue, take the payment with Stripe's PaymentSheet as a direct charge on the venue's
account, then confirm it so the pass works before Stripe's webhook arrives:

```kotlin
PaymentConfiguration.init(context, purchase.publishableKey!!, purchase.stripeAccountId)
paymentSheet.presentWithPaymentIntent(purchase.paymentIntentClientSecret!!, configuration)
// when the sheet completes:
val admission = client.confirmCover(purchase.admission.id)  // AdmissionStatus.PAID
```

`paymentIntentClientSecret` is `null` when the cover is already paid. The pass's
QR code is made on the phone, so it works with no signal, and changes every 30
seconds:

```kotlin
val code = admission.passCode()   // HMC1.<id>.<window>.<signature>, or null without passSecret
```

`client.admissions()` lists the member's passes and `client.refundAdmission(id)`
refunds one while `isRefundable`. Working a door (scanning passes) is staff work, in
StaffKit for Android.

## REST endpoints

For anything GraphQL doesn't cover, send the request through the client so it
carries the session and handles a rejected session the same way:

```kotlin
val bytes = client.data(APIRequest(path = "/v1/status", authenticated = false))
```

## Errors

Every failure is an `AudienceKitException`:

| `AudienceKitException` | When |
| --- | --- |
| `NotSignedIn` | No stored session for a call that needs one. |
| `Unauthorized` | The API rejected the session (401). The session has ended. |
| `SignInRejected`, `SignInFailed` | `POST /v1/token` refused the Facebook token (401), or failed (400). |
| `Forbidden` | 403, e.g. a session bound to another audience. |
| `NotFound` | 404: no such audience, record or host. |
| `Http` | Any other unsuccessful status. |
| `Network` | No response: offline, timeout, TLS. `cause` is the `IOException`. |
| `Decoding` | The response wasn't what the SDK expected. |
| `GraphQL` | The GraphQL response had errors. |
| `MissingConfiguration`, `TokenStorage` | Setup problems. |

Cancelling the calling coroutine cancels the request.

## Development

With JDK 17 (selected by the monorepo's mise configuration):

```sh
./gradlew build                     # both libraries: compile, unit tests, Android lint
./gradlew :audiencekit:test         # the JVM library's tests
./gradlew publishToMavenLocal
```

`audiencekit-android` is only part of the build when the Android SDK is found
(`ANDROID_HOME`, `ANDROID_SDK_ROOT`, or `sdk.dir` in `local.properties`), so the
JVM library builds with just a JDK. Tests stub HTTP with an `HttpTransport`, plus a
local HTTP server for `UrlConnectionTransport`, so they run offline.
