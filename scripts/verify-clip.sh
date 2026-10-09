#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
command -v xcrun >/dev/null || { echo 'AVFoundation clip verification requires macOS/Xcode.' >&2; exit 2; }
verification_binary="$(mktemp -t wristmagic-verify).bin"
trap 'rm -f "$verification_binary"' EXIT
xcrun swiftc -parse-as-library scripts/verification/ValidateClip.swift -o "$verification_binary"
"$verification_binary" "$@"
