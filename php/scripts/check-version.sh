#!/usr/bin/env bash
# The PHP SDK's version lives in src/AudienceKit.php (VERSION) and must have an entry in php/CHANGELOG.md; a change
# to php/ against the base branch needs a new one. CI runs: php/scripts/check-version.sh origin/main
set -euo pipefail
cd "$(dirname "$0")/.."

version="$(sed -n "s/.*public const VERSION = '\([0-9.]*\)';.*/\1/p" src/AudienceKit.php)"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "src/AudienceKit.php has no semantic VERSION." >&2; exit 1; }
grep -q "^## $version " CHANGELOG.md || { echo "CHANGELOG.md has no entry for $version." >&2; exit 1; }

base="${1:-}"
if [[ -n "$base" ]]; then
    if git diff --quiet "$base" -- . ; then
        echo "php/ is unchanged against $base; version $version stays."
        exit 0
    fi
    previous="$(git show "$base:php/src/AudienceKit.php" 2>/dev/null | sed -n "s/.*public const VERSION = '\([0-9.]*\)';.*/\1/p" || true)"
    if [[ "$previous" == "$version" ]]; then
        echo "php/ changed against $base but the version is still $version; bump it in src/AudienceKit.php and CHANGELOG.md." >&2
        exit 1
    fi
fi
echo "PHP SDK version $version."
