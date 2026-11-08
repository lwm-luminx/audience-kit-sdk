# AudienceKit SDK

Source-available client SDKs for the [AudienceKit](https://audiencekit.com) API, for an audience's own apps (like
[Hot Mess](https://hotmess.social)): sign people in, then read the audience's venues, people, locales, events,
lineups and chat. One repository and one version for every platform.

| Directory | What it is | Install |
| --- | --- | --- |
| [`swift/`](swift/README.md) | `AudienceCore`, `AudienceKit`, `AudienceKitUI` for iOS 16+, macOS 13+ and Linux | Swift Package Manager: `https://github.com/lwm-luminx/audience-kit-sdk.git` |
| [`core/`](core/README.md) | `com.audiencekit:audiencekit-core`, the Kotlin Multiplatform code shared by every platform (JVM, Android, Apple) | Gradle |
| [`android/`](android/README.md) | `com.audiencekit:audiencekit` (the Kotlin client, plain JVM) and `audiencekit-android` | Gradle composite build of the repository (Maven publishing to come) |
| [`ruby/`](ruby/README.md) | The `audience-kit` gem: Ruby bindings for the API (Ruby 3.2+), versioned on its own | RubyGems: `gem "audience-kit"` |
| [`node/`](node/README.md) | The `audience-kit` npm package: a Node.js and TypeScript client for the consumer GraphQL API (Node 20+), versioned on its own | npm: `npm install audience-kit` |
| [`python/`](python/README.md) | The `audiencekit` package: the shared calls for Python 3.10+, blocking and asyncio, versioned on its own | PyPI: `pip install audiencekit` |
| [`graphql/`](graphql/schema.graphql) | The API's consumer GraphQL schema the SDKs are checked against | |

Both builds sit at the root, because Swift Package Manager only reads a root manifest: `Package.swift` builds `swift/`,
and the Gradle build (`settings.gradle.kts`) builds `core/` and `android/`.

## Versioning

The Ruby gem keeps its own version in [`ruby/lib/audience-kit/version.rb`](ruby/lib/audience-kit/version.rb), the
npm package in [`node/package.json`](node/package.json) and the Python package in
[`python/src/audiencekit/_version.py`](python/src/audiencekit/_version.py) (released from `python-<version>` tags,
[python/README.md](python/README.md)); none is part of the release below. Swift and Kotlin release together under one [semantic version](https://semver.org), kept in [`VERSION`](VERSION).
Gradle reads it; the Swift and Kotlin clients also carry it as a constant, because they send it to the API with every
call and the API refuses versions older than its minimum. So every change to either SDK takes a new version:

```sh
scripts/set-version.sh 0.25.0   # writes VERSION and both constants
scripts/check-version.sh        # CI runs this on every pull request
```

Add the version's entry to [`CHANGELOG.md`](CHANGELOG.md). Once it merges to `main` and CI passes, the `release` job in
[`.github/workflows/swift-kotlin.yml`](.github/workflows/swift-kotlin.yml) tags the release (`0.25.0`, no `v`) so Swift Package Manager can
resolve it, and opens its GitHub release from the changelog entry. The Xcode Cloud workflow runs the same script
([`xcode-cloud/`](xcode-cloud/README.md)); whichever finishes second finds the tag there already.

## CI

Each SDK has its own GitHub Actions workflow in [`.github/workflows/`](.github/workflows), filtered to its own paths, so
a change to one language only runs (and only edits) that language's CI: `swift-kotlin.yml` (Swift and Kotlin share
`VERSION` and the release job, so they stay together), `ruby.yml`, `php.yml` and `node.yml`. A new SDK adds its own
`<language>.yml` with a `paths:` filter on its directory (plus `graphql/**` and `scripts/graphql/**` if it checks its
documents against the schema), keeps the repository's 85% line-coverage floor, and tags releases with a prefix
(`php/<version>`, `python-<version>`), never bare, since bare tags are the Swift package's.

## License

Source-available, not open source. The SDK is published under the [AudienceKit SDK License](LICENSE) 1.2,
© Love Wins Media, Inc. You may read, use, change and redistribute it, and build it into your apps, **only** in
applications that connect to AudienceKit as hosted by Love Wins Media (audiencekit.com, the audiences' own domains,
and the development instances it provides). Every other use is prohibited, including using the SDK, or anything
derived from it, with another implementation of the API, self-hosted or otherwise. Any other use needs Love Wins
Media, Inc.'s express permission in a written agreement signed by an officer, and an audience ID or token Love Wins
Media issues for that use, kept configured so the use can be checked for compliance. Because of that restriction the
license is not OSI-approved; package registries list it as `LicenseRef-AudienceKit-SDK-1.2`.

No other license of any kind is granted: no implied, patent (beyond the license's own patent grant) or trademark
rights. Misrepresenting the SDK or Love Wins Media's work, by claiming authorship or origin, stripping notices,
passing a changed version off as the original or implying endorsement, is expressly prohibited and a breach of the
license. Changed versions may be made only in a GitHub fork of this repository, after written notice to Love Wins
Media: open an issue titled "Derived work notice" here, naming yourself and the fork. Apps that only use the SDK
unchanged need no fork or notice.

Copies released under the MIT License stay MIT for those copies: the Swift package tags through 0.41.0, the source
through 0.42.0, and the `audience-kit` Ruby gem 0.1.0 and 0.1.1. Releases 0.41.1 through 0.45.1 carry version 1.0
of this license, and later releases up to this change carry version 1.1.

**Copying is prohibited.** Copying this work beyond what [LICENSE](LICENSE) allows is copyright infringement, and willful copying can be a federal crime (17 U.S.C. §§ 501, 506). Removing, altering or faking copyright or attribution notices is unlawful under 17 U.S.C. § 1202, and a federal crime under § 1204 when done willfully for commercial advantage or private financial gain. Publishing an app built from it without a license also breaks [App Store Review Guideline 5.2.1](https://developer.apple.com/app-store/review/guidelines/#intellectual-property) (Intellectual Property) and [Google Play's Intellectual Property policy](https://support.google.com/googleplay/android-developer/answer/9888072). See [NOTICE.md](NOTICE.md) for the details.
