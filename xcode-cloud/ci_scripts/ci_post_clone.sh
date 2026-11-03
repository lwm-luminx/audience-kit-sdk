#!/bin/sh
# Xcode Cloud runs this right after it clones the SDK. On a pull request it runs the version check GitHub Actions ran
# (scripts/check-version.sh): every change to the SDK's sources needs a new VERSION. On a branch build it fetches the
# whole history, which scripts/tag-release.sh reads after the tests pass on main.
set -eu

cd "${CI_PRIMARY_REPOSITORY_PATH:?}"
[ "$(git rev-parse --is-shallow-repository)" = "false" ] || git fetch --quiet --unshallow origin

if [ -n "${CI_PULL_REQUEST_NUMBER:-}" ]; then
    target="${CI_PULL_REQUEST_TARGET_BRANCH:-main}"
    git fetch --quiet --no-tags origin "+refs/heads/$target:refs/remotes/origin/$target"
    bash scripts/check-version.sh "origin/$target"
fi
