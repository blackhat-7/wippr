# Device testing (Phase 4)

**TL;DR (2026-09-27)**
- Device: iPhone 18 Pro Max (iPhone19,3), iOS 27.0 (24A437). Built with Xcode 27.0 (27A266a), iOS 27.0 SDK, Swift 6.4.
- Signs and installs with automatic signing (team `CRH6P5D9K2`) via `xcodebuild -allowProvisioningUpdates`.
- Results per test are below. Test steps are in `../TODO.md` → Phase 4.

## Build

```sh
cd ios && xcodegen
xcodebuild -project Wippr.xcodeproj -scheme Wippr -configuration Debug \
  -destination 'platform=iOS,id=<UDID>' -derivedDataPath ../.build/dd -allowProvisioningUpdates build
xcrun devicectl device install app --device <UDID> ../.build/dd/Build/Products/Debug-iphoneos/Wippr.app
```

- The first build failed with "Build input file cannot be found: …/Provisioning Profiles/<uuid>.mobileprovision" while the phone was paired but not connected. It built once the phone was connected.
- Xcode 27 SDK deprecation: `GenerationOptions(sampling:)` → `GenerationOptions(samplingMode:)`. The new init is `@backDeployed` to iOS 26. It is gated on `#if compiler(>=6.4)` so the Xcode 26.6 CI still builds.
- Remaining warning: "All interface orientations must be supported unless the app requires full screen." The fix it suggests, `UIRequiresFullScreen`, is deprecated in iOS 26. Left as is.

## Results

| Test | Result | Notes |
|---|---|---|
| Keyboard-driven flow (2026-09-27, iPhone 18 Pro Max, iOS 27.0) | **Works** | Mic on in the app, then hold the button in the wippr keyboard → text typed into the field. User-confirmed; latency not measured yet. |

## Findings on the way

- **Wake word (dropped):** SpeechTranscriber spelled "wipper" as "Whipper" and "Viper". Results arrived in bursts about every 4 s while listening continuously.
- **Darwin notifications app → keyboard never arrived** on iOS 27, with Full Access off. Both sides now poll App Group files (0.1 s in the app, 0.25 s in the keyboard).
- **Keyboard launch crash:** an `@objc func release()` handler overrode NSObject `-release`, causing infinite recursion (from the crash log in `devicectl device copy from --domain-type systemCrashLogs`). Never name ObjC-exposed methods after NSObject selectors.
- **Device logs:** `log collect --device-udid <UDID>` needs sudo. `.info`/`.debug` os_log lines aren't persisted, so use `.notice`. Crash reports copy without sudo (command above).
