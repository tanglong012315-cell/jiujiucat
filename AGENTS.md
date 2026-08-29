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

**The iOS UI replicates the Web UI. Native code, not native look.** This is the user's explicit decision of 2026-08-28, and it reverses the earlier "prefer native controls over web-shaped imitations" rule. Building screens around iOS navigation conventions is what caused the feature gaps recorded in section 6 of `ios/Docs/MIGRATION_PLAN.md`.

- `public/styles.css` and the live site are the visual source of truth, exactly as `public/app.js` is the behavioral one.
- Port the Web design tokens verbatim instead of substituting iOS system equivalents. `PawTheme` mirrors the `:root` and `:root[data-theme="dark"]` blocks of `public/styles.css`, including the ink alpha ramp, the tint pairs, and the market-session colours.
- Reproduce the Web layout structure: the header with account avatar, rotating market ticker and theme toggle, and the three-tab bottom bar. Do not re-cut screens into iOS navigation patterns.
- Do not add furniture the Web does not have. The introduction cards, section subtitles, and decorative paw badges that were added natively are not in the Web app and should be removed as each screen is ported.
- When a stock SwiftUI control cannot match the Web appearance, build a custom one. Matching the Web wins.
- Keep monospaced digits for money, and keep green/red for financial meaning only.
- Preserve the cat identity, including the brand state illustrations in `public/illustrations/`.

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
