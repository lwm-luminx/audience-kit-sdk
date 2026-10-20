#!/usr/bin/env bash
# Sets the SDK's one version everywhere it's written down: VERSION (which Gradle reads), and the constants the Swift
# and Kotlin clients send with every call.
#
#   scripts/set-version.sh 0.23.0
set -euo pipefail
cd "$(dirname "$0")/.."

version="${1:?usage: scripts/set-version.sh X.Y.Z}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Not a semantic version: $version" >&2; exit 1; }

echo "$version" > VERSION
sed -i.bak -E "s/(public static let version = \")[0-9.]+(\")/\1$version\2/" swift/Sources/AudienceCore/AudienceKitSDK.swift
sed -i.bak -E "s/(public const val VERSION: String = \")[0-9.]+(\")/\1$version\2/" \
    android/audiencekit/src/main/kotlin/com/audiencekit/AudienceKitSDK.kt
rm -f swift/Sources/AudienceCore/AudienceKitSDK.swift.bak android/audiencekit/src/main/kotlin/com/audiencekit/AudienceKitSDK.kt.bak
echo "The SDK is now $version. Add a CHANGELOG.md entry for it."
