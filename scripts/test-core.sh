#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
command -v swift >/dev/null || { echo 'Swift 6 is required. Install Swift or select Xcode.' >&2; exit 2; }
swift test --package-path Packages/WristMagicCore
