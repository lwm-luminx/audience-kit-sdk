#!/usr/bin/env bash
# Tags the PHP SDK's release on GitHub as php/<version> (src/AudienceKit.php's VERSION), at the commit that set it,
# so it doesn't clash with the Swift package's bare "X.Y.Z" tags, which Swift Package Manager resolves from.
# Composer can't read a package out of a subdirectory of a repository, so publishing to Packagist goes through a
# read-only split of php/ (see php/README.md, "Releasing"); this tag marks the source commit.
#
#   php/scripts/tag-release.sh          # HEAD's version, unless the tag exists already
#
# GITHUB_TOKEN, when set, pushes the tag; without one it goes to origin with your own git credentials.
set -euo pipefail
cd "$(dirname "$0")/../.."

repo=lwm-luminx/audience-kit-sdk
version="$(sed -n "s/.*public const VERSION = '\([0-9.]*\)';.*/\1/p" php/src/AudienceKit.php)"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Not a semantic version: $version" >&2; exit 1; }
tag="php/$version"

if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    remote="https://x-access-token:${GITHUB_TOKEN}@github.com/$repo.git"
else
    remote=origin
fi

existing="$(git ls-remote --tags "$remote" "refs/tags/$tag" | awk '{ print $1 }' | head -1)"
if [[ -n "$existing" ]]; then
    echo "The tag $tag is there already ($existing)."
    exit 0
fi
git tag "$tag"
git push "$remote" "refs/tags/$tag"
echo "Tagged $tag."
