#!/bin/bash
# Builds Skuff and prints only compiler diagnostics plus the result line.
# Usage: build.sh [Debug|Release]
set -o pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
CONFIG="${1:-Debug}"
LOG="${TMPDIR:-/tmp}/skuff-build-$CONFIG.log"

xcodebuild \
    -project "$ROOT/Skuff App Launcher.xcodeproj" \
    -scheme "Skuff App Launcher" \
    -configuration "$CONFIG" \
    build > "$LOG" 2>&1
status=$?

# Source diagnostics, plus signing/project errors that have no file prefix.
grep -E "^/.*: (warning|error):|^error:|^xcodebuild: error" "$LOG" | sort -u
grep -E "\*\* BUILD (SUCCEEDED|FAILED) \*\*" "$LOG" | tail -1
if [ $status -ne 0 ]; then
    echo "Full log: $LOG"
fi
exit $status
