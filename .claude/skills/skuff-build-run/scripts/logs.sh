#!/bin/bash
# Prints Skuff's os.Logger output (subsystem no.voq.skuff) from the recent past.
# Usage: logs.sh [window]   e.g. logs.sh 2m, logs.sh 30s  (default 5m)
log show \
    --last "${1:-5m}" \
    --info --debug \
    --style compact \
    --predicate 'subsystem == "no.voq.skuff" OR (process == "Skuff App Launcher" AND messageType == fault)'
