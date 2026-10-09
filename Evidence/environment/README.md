# Environment evidence — 2026-10-09

Implementation host: Linux x86_64, Ubuntu 24.04.3. Xcode, xcrun and XcodeGen are absent. `xcodebuild -version`, `xcodebuild -showsdks`, `xcrun simctl list devices available`, and `xcrun devicectl list devices` cannot run here. Xcode project deployment and paired-device status have not been checked. M0 is **not passed**; all physical testing is deferred to the user's Mac mini.

Identifiers use the repository owner's public GitHub namespace, not an invented organization: `io.github.geekjourneyx.wristmagic`, companion `io.github.geekjourneyx.wristmagic.watchkitapp`. No development team, certificate or device ID is configured. No unused capabilities or permissions are enabled.

## Mac setup

Open `WristMagic.xcodeproj` in Xcode 16 or newer (Swift 6). Select your actual development team for both apps. Ensure the paired iPhone/Watch OS versions are supported by that Xcode. Run the iOS app on the iPhone and the Watch scheme on its paired Watch. Record actual model, OS, team category, signing errors, foreground launch and pairing outcome here. Personal Team failures remain hardware blockers; never substitute simulator results for them.

Run `xcodebuild -version`, `xcodebuild -showsdks`, `xcrun simctl list devices available`, `xcrun devicectl list devices`. Set `IOS_SIMULATOR_UDID` and `WATCH_SIMULATOR_UDID` from the simulator inventory, then run `scripts/test-ios.sh` and `scripts/test-watch.sh`. These produce timestamped xcresult bundles under `Evidence/test-results/`. `scripts/test-core.sh` runs platform-neutral Swift package tests. Four shared schemes: WristMagic-iOS, WristMagic-Watch, WristMagic-iOSTests, WristMagic-WatchTests.

CI builds both app schemes on macOS and runs both simulator smoke bundles plus package tests. CI status must be observed before asserting Apple compilation success. Watch smoke tests verify module linkage only, not connectivity or sensor behavior.

## Official project references

Checked 2026-10-09: Apple WKApplication documentation describes single-target watchOS apps supported since Xcode 14; WKCompanionAppBundleIdentifier must match the iOS bundle ID.

- https://developer.apple.com/documentation/watchkit/wkapplication
- https://developer.apple.com/documentation/bundleresources/information-property-list/wkcompanionappbundleidentifier

No AVAssetWriter APIs are used at this baseline; deprecation evaluation belongs to capture implementation and actual Apple SDK compilation.
