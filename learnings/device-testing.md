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
