#!/usr/bin/env bash
# The SDK has one version for Swift and Kotlin, in VERSION. This fails when the Swift or Kotlin constant doesn't match
# it, or when the SDK's sources changed since BASE but VERSION didn't: apps send the SDK version with every call, and
# the AudienceKit API refuses ones older than its minimum, so each change needs its own version.
#
#   scripts/check-version.sh origin/main
set -euo pipefail
cd "$(dirname "$0")/.."

base="${1:-origin/main}"
swift_file=swift/Sources/AudienceCore/AudienceKitSDK.swift
kotlin_file=android/audiencekit/src/main/kotlin/com/audiencekit/AudienceKitSDK.kt
sources=(Package.swift swift/Sources core/src/commonMain android/audiencekit/src/main android/audiencekit-android/src/main)

constant() { grep -Eo '"[0-9]+(\.[0-9]+)+"' "$1" | head -1 | tr -d '"'; }
version="$(tr -d '[:space:]' < VERSION)"
for file in "$swift_file" "$kotlin_file"; do
    if [[ "$(constant "$file")" != "$version" ]]; then
        echo "$file says $(constant "$file"), but VERSION is $version: run scripts/set-version.sh $version." >&2
        exit 1
    fi
done

if ! git rev-parse --verify --quiet "$base" > /dev/null; then
    echo "The SDK is $version (no $base to compare with)."
    exit 0
fi
if git diff --quiet "$base"...HEAD -- "${sources[@]}"; then
    echo "The SDK's sources are unchanged; it's $version."
    exit 0
fi

before="$(git show "$(git merge-base "$base" HEAD):VERSION" 2>/dev/null | tr -d '[:space:]' || true)"
if [[ -z "$before" ]]; then
    echo "The combined SDK is new at $version."
    exit 0
fi
if [[ "$before" == "$version" ]]; then
    echo "The SDK changed but is still $version: run scripts/set-version.sh with the next version." >&2
    exit 1
fi
echo "The SDK changed, and went from $before to $version."
