# Changelog

One changelog for the whole SDK from 0.22.0 on. Earlier releases are in [swift/CHANGELOG.md](swift/CHANGELOG.md)
(through 0.21.0) and [kotlin/CHANGELOG.md](kotlin/CHANGELOG.md) (through 0.19.0).

## 0.22.0 (2026-10-20)

The Swift and Kotlin SDKs now live in one repository, lwm-luminx/audience-kit-sdk (formerly audience-kit-sdk-swift;
audience-kit-sdk-android is merged in with its history), and share one version. Kotlin jumps from 0.19.0 to 0.22.0 to
meet Swift; there are no API changes on either side beyond the fix below.

### Breaking (for builds, not code)

- Swift Package Manager: the package's URL is now `https://github.com/lwm-luminx/audience-kit-sdk.git` (the old URL
  redirects) and its identity is `audience-kit-sdk`, so `.product(name:package:)` references change to
  `package: "audience-kit-sdk"`. The sources moved to `swift/Sources`.
- Gradle: the build moved to `kotlin/`, so composite builds point at `<checkout>/kotlin`.

### Fixed

- Swift: `tribes()` asks for `tags(tribes: true)`, as the Kotlin SDK does; `Audience.tribes` is no longer in the API's
  schema.

### Added

- `graphql/schema.graphql`, and CI checks both SDKs' GraphQL documents against it (Swift's weren't checked before).
