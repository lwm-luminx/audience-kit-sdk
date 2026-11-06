#!/usr/bin/env bash
# Fails when the Swift SDK's line coverage drops below a floor. Run after `swift test --enable-code-coverage` (CI's
# swift job does). Only what builds on Linux is measured: the SwiftUI views and StoreKit prompts aren't.
#
#   scripts/swift-coverage.sh [minimum percent, default 85]
set -euo pipefail
cd "$(dirname "$0")/.."

minimum="${1:-85}"
bin="$(swift build --show-bin-path)"
report="$(llvm-cov report "$bin/AudienceKitPackageTests.xctest" -instr-profile="$bin/codecov/default.profdata" \
    -ignore-filename-regex='(/Tests/|/\.build/|/checkouts/)')"
echo "$report"
# TOTAL's columns: regions, missed, cover, functions, missed, executed, lines, missed, cover, …
lines="$(awk '$1 == "TOTAL" { gsub("%", "", $10); print $10 }' <<< "$report")"
if awk -v lines="$lines" -v minimum="$minimum" 'BEGIN { exit !(lines + 0 < minimum + 0) }'; then
    echo "Swift line coverage is ${lines}%, under the ${minimum}% floor: add tests with the change." >&2
    exit 1
fi
echo "Swift line coverage is ${lines}% (floor ${minimum}%)."
