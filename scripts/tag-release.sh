#!/usr/bin/env bash
# Publishes the SDK: tags a commit on GitHub with its version (VERSION, no "v"), which is how Swift Package Manager and
# Xcode resolve releases, and opens a GitHub release with that version's CHANGELOG.md entry. The SDK Xcode Cloud workflow
# runs it after the tests pass on main (xcode-cloud/README.md); it also runs by hand.
#
#   scripts/tag-release.sh          # HEAD's version, unless that tag exists already
#   scripts/tag-release.sh --all    # also each earlier version on origin/main that has no tag, at the merge that set it
#
# GITHUB_TOKEN, when set, is a token that can write lwm-luminx/audience-kit-sdk's contents: the tags go up with it and
# the GitHub releases are opened with it. Without one the tags go to origin with your own git credentials and no release
# is opened. Written for macOS's bash 3.2, which Xcode Cloud runs.
set -euo pipefail
cd "$(dirname "$0")/.."

repo=lwm-luminx/audience-kit-sdk
all=no
[[ "${1:-}" == "--all" ]] && all=yes

if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    remote="https://x-access-token:${GITHUB_TOKEN}@github.com/$repo.git"
else
    remote=origin
fi

remote_tag() { git ls-remote --tags "$remote" "refs/tags/$1" | awk '{ print $1 }' | head -1; }

# The CHANGELOG.md entry for a version: the lines under "## <version>" up to the next "## ".
notes() {
    awk -v version="$1" '
        /^## / { if (found) exit; if ($2 == version) { found = 1; next } }
        found { print }
    ' CHANGELOG.md
}

release() {
    local version="$1"
    [[ -n "${GITHUB_TOKEN:-}" ]] || return 0
    local body
    body="$(notes "$version" | python3 -c '
import json, sys
version, notes = sys.argv[1], sys.stdin.read().strip()
print(json.dumps({"tag_name": version, "name": version, "body": notes or "See CHANGELOG.md.", "make_latest": "legacy"}))
' "$version")"
    local status
    status="$(curl -sS -o /dev/null -w '%{http_code}' -X POST \
        -H "Authorization: Bearer $GITHUB_TOKEN" -H "Accept: application/vnd.github+json" \
        "https://api.github.com/repos/$repo/releases" -d "$body")"
    case "$status" in
        201) echo "Opened the GitHub release $version." ;;
        422) echo "The GitHub release $version is there already." ;;
        *) echo "warning: GitHub answered $status opening the release $version; the tag is up either way." >&2 ;;
    esac
}

publish() {
    local version="$1" commit="$2" existing
    [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Not a semantic version: $version" >&2; return 1; }
    existing="$(remote_tag "$version")"
    if [[ -n "$existing" ]]; then
        if [[ "$existing" != "$(git rev-parse "$commit")" ]]; then
            echo "$version is tagged already, at ${existing:0:7} (not ${commit:0:7}); leaving it." >&2
        else
            echo "$version is tagged already."
        fi
        return 0
    fi
    if ! git push --quiet "$remote" "$(git rev-parse "$commit"):refs/tags/$version"; then
        # Another destination of the same Xcode Cloud build may have pushed it a moment ago.
        [[ -n "$(remote_tag "$version")" ]] || { echo "Couldn't push the tag $version." >&2; return 1; }
    fi
    echo "Tagged $version at $(git rev-parse --short "$commit")."
    release "$version"
}

if [[ "$all" == yes ]]; then
    git fetch --quiet origin main
    seen=" "
    for commit in $(git log --first-parent --reverse --format=%H origin/main -- VERSION); do
        version="$(git show "$commit:VERSION" | tr -d '[:space:]')"
        case "$seen" in *" $version "*) continue ;; esac
        seen="$seen$version "
        publish "$version" "$commit"
    done
fi

publish "$(tr -d '[:space:]' < VERSION)" HEAD
