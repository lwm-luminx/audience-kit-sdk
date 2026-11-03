#!/bin/sh
# Xcode Cloud runs this after each xcodebuild. Once the SDK's tests pass on main it publishes VERSION: the tag Swift
# Package Manager resolves and a GitHub release (scripts/tag-release.sh). Pull requests, other branches, failed runs and
# the build-for-testing step publish nothing. The workflow's GITHUB_TOKEN secret pushes the tag (xcode-cloud/README.md).
set -eu

[ "${CI_XCODEBUILD_ACTION:-}" = "test-without-building" ] || exit 0
[ "${CI_XCODEBUILD_EXIT_CODE:-1}" = "0" ] || exit 0
[ -z "${CI_PULL_REQUEST_NUMBER:-}" ] || exit 0
[ "${CI_BRANCH:-}" = "main" ] || exit 0

if [ -z "${GITHUB_TOKEN:-}" ]; then
    echo "warning: no GITHUB_TOKEN secret in this workflow, so VERSION isn't published. See xcode-cloud/README.md."
    exit 0
fi

cd "${CI_PRIMARY_REPOSITORY_PATH:?}"
bash scripts/tag-release.sh
