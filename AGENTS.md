# Repository instructions

## Product direction

- The native app is named **PawFolio**. The repository folder may still be named `jiujiucat`.
- The iOS app must be a fully native SwiftUI implementation. Do not add `WKWebView`, `WebView`, embedded web pages, or a JavaScript bridge.
- Keep the existing website and Cloudflare Worker working. Native iOS work belongs under `ios/` unless a deliberate shared-backend change is required.
- The current deployment target is iOS 17.0 and the language mode is Swift 6.

## Read before changing iOS code

1. Read `ios/HANDOFF.md` for current progress, known issues, and the next task.
2. Read `ios/Docs/MIGRATION_PLAN.md` for the feature inventory and implementation order.
3. Read `ios/Docs/WEB_PARITY.md` before changing financial calculations or persistence models.
4. Treat `public/app.js` as behavior reference only, not as code to embed in the app.

## Architecture constraints

- Keep financial rules in `ios/PawFolio/Domain` as pure Swift with unit tests.
- Keep feature views in `ios/PawFolio/Features`; views must not call remote APIs or Supabase directly.
- Use repository/service boundaries for local storage, market data, authentication, and cloud sync.
- Preserve JSON compatibility with the existing Supabase `holdings.payload` records.
- Add a migration path before changing persisted model fields. A future native payload must include a `schemaVersion`.
- Use semantic/dynamic colors, Dynamic Type, VoiceOver labels, and monospaced digits for changing financial values.

## Design direction

- Continue the existing SnowUI identity: quiet near-monochrome surfaces, Paw Blue (`#007AFF`) as the primary accent, and green/red only for financial meaning.
- Use SF Pro Rounded sparingly for identity/headlines, the system text face for body copy, and monospaced digits for money.
- Prefer native navigation, sheets, controls, haptics, and charts over web-shaped imitations.
- Preserve the cat identity, but keep decoration subordinate to financial clarity.

## Verification

Run the simulator build and unit tests after meaningful changes:

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

Run the XCTest bundle on a named simulator when CoreSimulator is available. Record any environment limitation in `ios/HANDOFF.md`.

## Handoff discipline

- Update `ios/HANDOFF.md` at the end of every meaningful development turn.
- Record what changed, what was verified, any decisions made, and the exact next task.
- Never mark an item complete solely because files exist; record the last successful build/test command.
