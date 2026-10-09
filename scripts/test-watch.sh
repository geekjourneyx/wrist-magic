#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
WATCH_SIMULATOR_UDID="${WATCH_SIMULATOR_UDID:-${WATCH_SIMULATOR_ID:-}}"
: "${WATCH_SIMULATOR_UDID:?Set WATCH_SIMULATOR_UDID to an available watchOS Simulator device UDID.}"
command -v xcodebuild >/dev/null || { echo 'Xcode is required on macOS.' >&2; exit 2; }
mkdir -p Evidence/test-results
result="Evidence/test-results/watch-$(date -u +%Y%m%dT%H%M%SZ)-$$.xcresult"
xcodebuild -project WristMagic.xcodeproj -scheme WristMagic-WatchTests -destination "platform=watchOS Simulator,id=$WATCH_SIMULATOR_UDID" -resultBundlePath "$result" CODE_SIGNING_ALLOWED=NO test
