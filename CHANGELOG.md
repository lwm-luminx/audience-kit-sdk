# Changelog

One changelog for the whole SDK from 0.24.0 on. Earlier releases are in [swift/CHANGELOG.md](swift/CHANGELOG.md)
(through 0.23.0) and [android/CHANGELOG.md](android/CHANGELOG.md) (through 0.19.0).

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
