#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
IOS_SIMULATOR_UDID="${IOS_SIMULATOR_UDID:-${IOS_SIMULATOR_ID:-}}"
: "${IOS_SIMULATOR_UDID:?Set IOS_SIMULATOR_UDID to an available iOS Simulator device UDID.}"
command -v xcodebuild >/dev/null || { echo 'Xcode is required on macOS.' >&2; exit 2; }
mkdir -p Evidence/test-results
result="Evidence/test-results/ios-$(date -u +%Y%m%dT%H%M%SZ)-$$.xcresult"
xcodebuild -project WristMagic.xcodeproj -scheme WristMagic-iOSTests -destination "platform=iOS Simulator,id=$IOS_SIMULATOR_UDID" -resultBundlePath "$result" CODE_SIGNING_ALLOWED=NO test
