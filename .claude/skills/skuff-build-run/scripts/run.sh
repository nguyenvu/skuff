#!/bin/bash
# Quits any running Skuff, launches the freshly built app, and reports whether it
# is still alive a few seconds later (DEBUG builds crash at launch on bad geometry).
# Usage: run.sh [Debug|Release]

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
CONFIG="${1:-Debug}"
PROCESS="Skuff App Launcher"

APP="$(xcodebuild \
    -project "$ROOT/Skuff App Launcher.xcodeproj" \
    -scheme "Skuff App Launcher" \
    -configuration "$CONFIG" \
    -showBuildSettings 2>/dev/null \
    | awk -F' = ' '/ BUILT_PRODUCTS_DIR = /{dir=$2} / FULL_PRODUCT_NAME = /{name=$2} END{print dir "/" name}')"

if [ ! -d "$APP" ]; then
    echo "No built app at $APP — run build.sh first."
    exit 1
fi

if pgrep -x "$PROCESS" > /dev/null; then
    echo "Quitting the running Skuff…"
    osascript -e 'quit app id "no.voq.skuff"' > /dev/null 2>&1
    for _ in $(seq 1 25); do
        pgrep -x "$PROCESS" > /dev/null || break
        sleep 0.2
    done
    # Still there (e.g. held by the Xcode debugger): stop it.
    pkill -x "$PROCESS" 2> /dev/null
    sleep 0.5
fi

LAUNCHED_AT="$(date '+%Y-%m-%d %H:%M:%S')"
open "$APP"
sleep 3

if pgrep -x "$PROCESS" > /dev/null; then
    echo "Running: $APP (pid $(pgrep -x "$PROCESS" | head -1)), launched $LAUNCHED_AT"
    exit 0
fi

echo "Skuff exited within 3 seconds of launch."
REPORT="$(ls -t "$HOME/Library/Logs/DiagnosticReports/"Skuff* 2> /dev/null | head -1)"
if [ -n "$REPORT" ]; then
    echo "Newest crash report: $REPORT"
fi
exit 1
