# AudienceKit SDK

Open-source client SDKs for the [AudienceKit](https://audiencekit.com) API, for an audience's own apps (like
[Hot Mess](https://hotmess.social)): sign people in, then read the audience's venues, people, locales, events,
lineups and chat. One repository and one version for every platform.

| Directory | What it is | Install |
| --- | --- | --- |
| [`swift/`](swift/README.md) | `AudienceCore`, `AudienceKit`, `AudienceKitUI` for iOS 16+, macOS 13+ and Linux | Swift Package Manager: `https://github.com/lwm-luminx/audience-kit-sdk.git` |
| [`kotlin/`](kotlin/README.md) | `com.audiencekit:audiencekit` (JVM), `audiencekit-android`, and `audiencekit-core` (Kotlin Multiplatform) | Gradle composite build of `kotlin/` (Maven publishing to come) |
| [`graphql/`](graphql/schema.graphql) | The API's consumer GraphQL schema the SDKs are checked against | |

The Swift package's manifest is `Package.swift` at the root, because Swift Package Manager only reads one there; the
Kotlin SDK is the Gradle build in `kotlin/`.

## Versioning

Swift and Kotlin release together under one [semantic version](https://semver.org), kept in [`VERSION`](VERSION).
Gradle reads it; the Swift and Kotlin clients also carry it as a constant, because they send it to the API with every
call and the API refuses versions older than its minimum. So every change to either SDK takes a new version:

```sh
scripts/set-version.sh 0.23.0   # writes VERSION and both constants
scripts/check-version.sh        # CI runs this on every pull request
```

Add the version's entry to [`CHANGELOG.md`](CHANGELOG.md), and tag the release (`0.23.0`, no `v`) so Swift Package
Manager can resolve it.

## License

MIT, © Love Wins Media, Inc. See [LICENSE](LICENSE).
