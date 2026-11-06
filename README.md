# AudienceKit SDK

Open-source client SDKs for the [AudienceKit](https://audiencekit.com) API, for an audience's own apps (like
[Hot Mess](https://hotmess.social)): sign people in, then read the audience's venues, people, locales, events,
lineups and chat. One repository and one version for every platform.

| Directory | What it is | Install |
| --- | --- | --- |
| [`swift/`](swift/README.md) | `AudienceCore`, `AudienceKit`, `AudienceKitUI` for iOS 16+, macOS 13+ and Linux | Swift Package Manager: `https://github.com/lwm-luminx/audience-kit-sdk.git` |
| [`core/`](core/README.md) | `com.audiencekit:audiencekit-core`, the Kotlin Multiplatform code shared by every platform (JVM, Android, Apple) | Gradle |
| [`android/`](android/README.md) | `com.audiencekit:audiencekit` (the Kotlin client, plain JVM) and `audiencekit-android` | Gradle composite build of the repository (Maven publishing to come) |
| [`ruby/`](ruby/README.md) | The `audience-kit` gem: Ruby bindings for the API (Ruby 3.2+), versioned on its own | RubyGems: `gem "audience-kit"` |
| [`node/`](node/README.md) | The `audience-kit` npm package: a Node.js and TypeScript client for the consumer GraphQL API (Node 20+), versioned on its own | npm: `npm install audience-kit` |
| [`graphql/`](graphql/schema.graphql) | The API's consumer GraphQL schema the SDKs are checked against | |

Both builds sit at the root, because Swift Package Manager only reads a root manifest: `Package.swift` builds `swift/`,
and the Gradle build (`settings.gradle.kts`) builds `core/` and `android/`.

## Versioning

The Ruby gem keeps its own version in [`ruby/lib/audience-kit/version.rb`](ruby/lib/audience-kit/version.rb), and the
npm package in [`node/package.json`](node/package.json); neither is part of the release below. Swift and Kotlin release together under one [semantic version](https://semver.org), kept in [`VERSION`](VERSION).
Gradle reads it; the Swift and Kotlin clients also carry it as a constant, because they send it to the API with every
call and the API refuses versions older than its minimum. So every change to either SDK takes a new version:

```sh
scripts/set-version.sh 0.25.0   # writes VERSION and both constants
scripts/check-version.sh        # CI runs this on every pull request
```

Add the version's entry to [`CHANGELOG.md`](CHANGELOG.md). Once it merges to `main` and CI passes, the `release` job in
[`.github/workflows/ci.yml`](.github/workflows/ci.yml) tags the release (`0.25.0`, no `v`) so Swift Package Manager can
resolve it, and opens its GitHub release from the changelog entry. The Xcode Cloud workflow runs the same script
([`xcode-cloud/`](xcode-cloud/README.md)); whichever finishes second finds the tag there already.

## License

[AudienceKit SDK License](LICENSE), © Love Wins Media, Inc. You may use, change and redistribute the SDK and build
it into your apps, on one condition: the SDK and anything derived from it may only be used with the AudienceKit
service that Love Wins Media operates (audiencekit.com, the audiences' own domains, and the development instances it
provides). Using it with another implementation of the API, self-hosted or otherwise, isn't allowed. Versions released
under the MIT License before this license was adopted (through 0.42.0) stay MIT.
