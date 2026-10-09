# T01 implementation report — 2026-10-09

## Delivered

Checked-in native `WristMagic.xcodeproj` with single-target paired watchOS app embedded in the iOS app, Debug/Release configurations, Swift 6, iOS 17/watchOS 10 deployment minima. Four shared schemes: `WristMagic-iOS`, `WristMagic-Watch`, `WristMagic-iOSTests`, `WristMagic-WatchTests`. Local WristMagicCore package imported by both minimal SwiftUI entry screens and both XCTest bundles. Shared fixture and protocol-version import smoke test; no application functionality beyond baseline entry. No team or unused capabilities/permissions configured.

Scripts use strict shell mode; iOS/Watch missing UDID exits nonzero with variable instructions, also accepting legacy `IOS_SIMULATOR_ID` / `WATCH_SIMULATOR_ID`. Valid IDs run xcodebuild test and write unique xcresult bundles. macOS CI runs package tests, Debug and Release app builds, both simulator smoke suites, uploads results.

## Commands and observed outcomes

- `uname -a`, `/etc/os-release`, `command -v swift/xcodegen/xcodebuild`: Ubuntu 24.04 x86_64; Apple tools and Swift initially absent.
- `curl -I https://download.swift.org/swift-6.0.3-release/ubuntu2404/swift-6.0.3-RELEASE/swift-6.0.3-RELEASE-ubuntu24.04.tar.gz`: HTTP 200. Downloaded/extracted official 747MiB archive under scratch `toolchain/`.
- Swift initially failed missing `libncurses.so.6`. apt update failed default sandbox uid changes; root-user apt retry was slow. Downloaded official Ubuntu `libncurses6_6.4+20240113-1ubuntu2_amd64.deb`, extracted into `toolchain/libs/`. `/workspace/scratch/71bc2a276d8b/swift-env.sh` sets PATH and local LD_LIBRARY_PATH.
- `source .../swift-env.sh; swift --version`: Swift 6.0.3, x86_64-unknown-linux-gnu.
- `scripts/test-core.sh`: compiler frontend crashed with Signal 4 / illegal instruction during module emission, with `/proc/.../stat` shown in crash registers. No test passed. Toolchain startup works but this sandbox compile failure is a real blocker; macOS CI is the next compilation authority.
- `scripts/test-ios.sh` and `scripts/test-watch.sh` without IDs: both exit 1 with required simulator variable instruction, as intended.
- `bash -n scripts/test-*.sh`: passed.
- `git diff --check`: passed.
- `git push --dry-run origin HEAD:feat/native-mvp`: failed, GitHub HTTPS credentials unavailable (`could not read Username`). Controller will publish committed snapshot through authorized GitHub connector and observe CI.

## Deferred gates and concerns

No Xcode/macOS compilation, simulator execution, signing, app installation, Watch pairing or physical test has been claimed. M0 is not passed. Physical tests explicitly deferred by user to Mac mini. See Evidence/environment/README.md for installation and evidence checklist. Project file generated directly because XcodeGen/Ruby unavailable; actual xcodebuild parsing and SDK compilation must resolve any project setting problems in CI before software compilation can be called successful. Hosted watchOS XCTest requirements, SDK annotations and pairing remain Apple-tool validation concerns.

Apple project settings consulted: https://developer.apple.com/documentation/watchkit/wkapplication and https://developer.apple.com/documentation/bundleresources/information-property-list/wkcompanionappbundleidentifier (2026-10-09). No AVAssetWriter API in T01, so its actual SDK deprecation check remains with capture work.
