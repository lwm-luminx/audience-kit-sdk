# AudienceKit shared core prototype

This module extracts existing SDK code into Kotlin Multiplatform `commonMain`:

- `graphQLValueOf` and `graphQLVariables`: recursive GraphQL variable conversion.
- `Coordinate`: WKT parsing and JSON serialization.
- `Coordinates`: GraphQL input construction, including beacon omission rules.
- `GraphQLEndpoint`: member and staff endpoint routing.

The JVM `audiencekit` module exposes this module as an `api` dependency. Existing
Kotlin imports and class names stay the same; StaffKit consumes it transitively
through AudienceKit. The extracted implementations preserve existing behavior,
including permissive WKT parsing and map key stringification. This is an extraction,
not a validation-policy change.

Targets are JVM (Java 17 bytecode, also used by Android), iOS arm64 devices,
iOS arm64 simulators, and macOS arm64 for native host tests. No Android SDK is
needed for the shared module. Source sets follow the
[Kotlin Multiplatform structure](https://kotlinlang.org/docs/multiplatform-set-up-targets.html).

## Validation

From the SDK root:

```sh
./gradlew :audiencekit-core:jvmTest :audiencekit:test
# On an Apple Silicon Mac with Xcode:
./gradlew :audiencekit-core:macosArm64Test
./gradlew :audiencekit-core:iosSimulatorArm64Test
./gradlew :audiencekit-core:linkDebugFrameworkIosArm64 :audiencekit-core:linkDebugFrameworkIosSimulatorArm64
```

`commonTest` contains eight contract tests covering nested values, nulls, enums,
unsupported values, map keys, duplicate variable names, beacon handling, WKT,
coordinate serialization and endpoint separation. The same tests run on JVM and
native targets. Existing client tests exercise the JVM integration.

From the monorepo, also run `./gradlew :staffkit:test` in `sdk/staff/android` to
verify its composite-build dependency resolves the shared JVM variant.

## Apple adoption boundary

Framework builds produce `AudienceKitCore.framework` under
`build/bin/<target>/debugFramework/`. These are separate device and simulator
frameworks, not a distributable XCFramework. The Swift SDK and apps are not yet
wired to them. Kotlin JSON types and generic variable conversion need a deliberate
Swift facade before replacing Swift's `GraphQLValue` API. The framework is a
compilation/interoperability prototype, not a drop-in Swift SDK replacement.

HTTP, credentials, platform storage, coroutines-based clients, QR cryptography,
and UI remain in their existing SDKs. Next steps are a Swift adapter with parity
tests, XCFramework packaging, and then selecting another shared API slice.
Publishing the JVM SDK now also requires publishing `audiencekit-core` and its
JVM variant; Gradle's multiplatform publishing tasks create those publications.
