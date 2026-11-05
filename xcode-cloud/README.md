# Xcode Cloud

Xcode Cloud builds, tests and publishes the Swift SDK. It can't build a standalone Swift package, only an app project
that uses one as a local package
([Apple](https://developer.apple.com/documentation/xcode/building-swift-packages-or-swift-playground-app-projects-with-xcode-cloud)),
so this folder holds that project:

| Path | What it is |
| --- | --- |
| `AudienceKitHost.xcodeproj` | A one-screen iOS app that links `AudienceCore`, `AudienceKit` and `AudienceKitUI` from the package at the repository root. Its shared **SDK** scheme builds the app and runs the package's `AudienceKitTests`. It is never archived or shipped. |
| `ci_scripts/ci_post_clone.sh` | On a pull request, the version check: a change to the SDK's sources needs a new `VERSION` (`scripts/check-version.sh`). |
| `ci_scripts/ci_post_xcodebuild.sh` | Once the tests pass on `main`, publishes `VERSION` with `scripts/tag-release.sh`: the tag Swift Package Manager resolves (`0.38.0`, no `v`) and a GitHub release with that version's `CHANGELOG.md` entry. |

The project sits in its own folder, not at the root, so `swift build` and `xcodebuild -scheme AudienceKit-Package` at the
root still see the package alone. Xcode Cloud looks for `ci_scripts` beside the project it builds, so they live here too.

## Releasing

Nothing changes in how a version is made: `scripts/set-version.sh X.Y.Z`, a `CHANGELOG.md` entry, and a pull request.
Merging it to `main` starts the workflow; when the tests pass, `X.Y.Z` is tagged at the merge and its GitHub release
opens. Apps then move their `audience-kit-sdk` package requirement to the new version. A run whose version is tagged
already publishes nothing, so merges that don't touch the SDK's sources (docs, CI) are harmless.

To tag by hand, or to tag every earlier version on `main` that has none (each at the merge that set it):

```sh
scripts/tag-release.sh          # VERSION at HEAD
scripts/tag-release.sh --all    # and every untagged version before it
```

## Setting up the workflow (once)

1. Open `xcode-cloud/AudienceKitHost.xcodeproj` in Xcode and choose Integrate > Create Workflow. Create the product
   **AudienceKitHost** (bundle ID `com.audiencekit.SDKHost`, team DWVXMLB45Y) and grant Xcode Cloud access to
   `lwm-luminx/audience-kit-sdk` when it asks. The app needs no App Store Connect record: nothing is archived.
2. Name the workflow **SDK** and give it:
   - Start conditions: *Branch Changes* on `main`, and *Pull Request Changes* into `main`.
   - Environment: the latest release of Xcode, and a **secret** environment variable `GITHUB_TOKEN`: a fine-grained
     GitHub token for `lwm-luminx/audience-kit-sdk` only, with *Contents: Read and write*.
   - One action: *Test*, scheme **SDK**, platform iOS, destination a recent iPhone simulator.
   - No post-actions.
3. Start a build on `main` to see it work; it tags the current `VERSION` if it isn't yet.

Without `GITHUB_TOKEN` the workflow still builds and tests; it just says it didn't publish. Publishing doesn't depend on
it: GitHub Actions' `release` job (`.github/workflows/ci.yml`) tags each version on `main` with the workflow's own token.

The Kotlin and Android libraries aren't built here (Xcode Cloud images carry no Android SDK); Maven publishing is still
to come.
