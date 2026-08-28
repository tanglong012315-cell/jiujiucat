# PawFolio for iOS

PawFolio is being migrated from the existing web application to a fully native SwiftUI app. The website remains the behavioral reference and continues to run independently.

## Requirements

- Xcode 26 or newer
- iOS 17.0 or newer
- No WebView dependency

## Open and run

Open `PawFolio.xcodeproj`, select the `PawFolio` scheme, and run on an iPhone simulator.

Command-line verification:

```sh
env SWIFTPM_MODULECACHE_OVERRIDE=/tmp/pawfolio-module-cache \
  CLANG_MODULE_CACHE_PATH=/tmp/pawfolio-clang-cache \
  SWIFT_MODULECACHE_PATH=/tmp/pawfolio-swift-cache \
  xcrun swift test --disable-sandbox \
  --package-path ios --scratch-path /tmp/pawfolio-spm

xcodebuild -project ios/PawFolio.xcodeproj \
  -scheme PawFolio \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/pawfolio-derived \
  CODE_SIGNING_ALLOWED=NO \
  build-for-testing
```

The Swift package is a lightweight harness for running domain and local-storage tests without booting an iOS simulator. The application itself remains an Xcode iOS target.

## Source layout

- `PawFolio/App`: application entry point and root navigation
- `PawFolio/DesignSystem`: native PawFolio tokens and reusable surfaces
- `PawFolio/Domain`: pure financial models and calculations
- `PawFolio/Features`: feature-specific SwiftUI screens and state
- `PawFolioTests`: domain and behavior parity tests
- `Docs`: migration specifications
- `Docs/MIGRATION_PLAN.md`: feature inventory and implementation order
- `HANDOFF.md`: live continuation notes for future agents
