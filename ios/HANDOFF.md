# PawFolio iOS handoff

Last updated: 2026-08-28

## Read first

1. `AGENTS.md`
2. `ios/Docs/MIGRATION_PLAN.md`
3. `ios/Docs/WEB_PARITY.md`
4. `ios/Docs/SYNC_CONTRACT.md` before changing authentication or sync code
5. `ios/Docs/PROFILE_SYNC_CONTRACT.md` before changing account profiles or avatars

## Non-negotiable decisions

- Fully native SwiftUI. Never add `WKWebView`, embedded web pages, or a JavaScript bridge.
- Keep the existing Web app intact and use it only as the behavioral reference.
- iOS 17+, Swift 6, SwiftUI, Swift Charts, `ObservableObject`/Combine.
- Keep domain rules in pure Swift and UI behind repository/service boundaries.
- Preserve Supabase `holdings.payload` compatibility.
- New native holdings use `schemaVersion = 2`; deletion uses `deletedAt` tombstones.
- Keep updating this file at the end of every meaningful agent turn.

## Current milestone

Milestone 6 productization is underway. The native launch experience and the Dynamic Type / dark-mode / Reduce Motion pass are complete and verified on a real simulator. VoiceOver walkthrough and localization remain open. Milestone 5 production holding and Profile synchronization stays verified in both directions.

### Completed

- [x] Native Xcode project with Calculator, Portfolio, and FX tabs.
- [x] Investment calculator with simple/compound return summaries and Swift Charts forecast.
- [x] Native FX converter with live `URLSession` fetch and cached fallback.
- [x] Versioned `Holding` model for `market`, `interest`, `hybrid`, and `dividend` payloads.
- [x] Legacy Web payload decoding, safe defaults, and unknown-kind fallback.
- [x] Native portfolio summary, empty state, holdings list, add/edit sheet, and swipe deletion.
- [x] Local Application Support JSON repository with atomic writes.
- [x] Migration read path for a legacy bare holdings array.
- [x] Corrupt local files are reported instead of silently replaced during load.
- [x] Tombstone deletion is persisted through `deletedAt` for future cross-device sync.
- [x] Repository and compatibility tests are part of the SwiftPM test harness.
- [x] Pure-Swift holding valuation covers Beijing 16:00 settlements, skipped dates, principal segments, compound interest, and confirmed dividends.
- [x] Production API base confirmed as `https://www.jiujiucat.win/` through `APIConfiguration.production`.
- [x] Native Yahoo asset search through Worker `/api/search`, with 350 ms debounce and explicit offline/manual fallbacks.
- [x] Native quote decoding through Worker `/api/quote`, including Beijing-day change and up to 240 timestamped points.
- [x] Unique holding symbols load concurrently and fall back to a 12-hour disk cache after request failure.
- [x] Portfolio total value, total profit, percentage, and rows now use live USD quotes.
- [x] Pure-Swift position adjustment engine for market, interest, hybrid, and dividend holdings.
- [x] Market adds use weighted-average cost; reductions keep unit cost unchanged.
- [x] Market-sale proceeds create or increase a zero-APR USDT holding at the exact sale timestamp.
- [x] Full market sales set `closedAt` and remain available to historical calculations for 400 days.
- [x] Stable principal adjustments use an effective Beijing date and do not rewrite settled interest.
- [x] Hybrid quantity changes record the corresponding interest-principal adjustment.
- [x] Future dividend records follow quantity changes while confirmed records remain frozen.
- [x] Existing holdings open through an item-driven SwiftUI sheet route, avoiding stale add-form state.
- [x] Native holding detail route with Overview, Adjustments, and Income segments.
- [x] Market quantity and stable/hybrid principal adjustments render as immutable chronological history.
- [x] Daily interest records are derived from the same principal-segment engine as portfolio valuation.
- [x] Settled interest dates can be marked unpaid through `interestSkips` and restored later.
- [x] Native dividend-record list, create, edit, and delete flows preserve frozen record quantities.
- [x] Interest and dividend lists show the newest 15 records while totals include the full history.
- [x] Pure-Swift portfolio history reconstruction for 24-hour, 7-day, 30-day, and 1-year ranges.
- [x] Historical market quantities rewind position adjustments; stable principal rewinds precise timestamps or Beijing effective dates.
- [x] Closed holdings remain in pre-sale history, while sale proceeds enter USDT at the exact sale timestamp.
- [x] Short quote history persists with quote cache; one-year daily history has a separate 12-hour disk cache.
- [x] Native Swift Charts card with range picker, current endpoint parity, and explicit estimated-coverage disclosures.
- [x] Pure-Swift holding reconciliation keyed by ID, with local/remote delta planning.
- [x] Conflict timestamps use `updatedAt`, fall back to `createdAt`, and include `deletedAt` for tombstones.
- [x] Tombstones win exact timestamp ties so simultaneous deletion cannot resurrect an active copy.
- [x] Legacy merge winners upgrade to `schemaVersion = 2` before local persistence or remote upload.
- [x] Authentication-session and cloud-holding repository protocols keep credentials and Supabase out of views.
- [x] Account-scoped local holding files isolate guest data and each authenticated user without changing the legacy guest path.
- [x] Offline-testable sync coordinator validates the session, pulls cloud state, reconciles, saves locally, and upserts only the remote delta.
- [x] Failed remote uploads preserve the merged local winner set and are recomputed safely on the next synchronization attempt.
- [x] Guest holdings remain separate by default and are copied into an account only after an explicit import choice; copying never deletes the guest source.
- [x] Per-account guest-import decisions persist locally; a completed copy becomes a one-time migration rather than a continuing guest/account link.
- [x] Native Account tab exposes session restoration, sign-in, explicit guest import, syncing, pending-upload retry, error, and sign-out states.
- [x] Portfolio storage switches between guest and account scopes through the app composition layer; sign-out returns to the guest scope.
- [x] Web source now creates and syncs deletion tombstones, hides them from valuation/UI/quote work, and uses the same deterministic conflict rules as native.
- [x] Supabase schema source now defines `(user_id, id)` as the holdings primary key, and Web upserts use that conflict target.
- [x] User confirmed the final iOS Bundle ID is `com.jiujiucat.pawfolio`.
- [x] User reported the updated `supabase/schema.sql` migration was executed on 2026-08-28; the production structure and native sync path were subsequently verified end to end.
- [x] Native Supabase Google OAuth uses PKCE through `ASWebAuthenticationSession`; the registered callback is `pawfolio://auth/callback`.
- [x] Supabase access and refresh tokens persist only in a Keychain item scoped to PawFolio.
- [x] Native token restoration, expiry refresh, sign-out, REST holding fetch, composite-key upsert, and one-time 401 retry are implemented behind protocols.
- [x] Google sign-in is connected in `RootTabView`; an explicit paused-sync gate protected production until the Web tombstone deployment was verified.
- [x] Sign in with Apple remains visibly disabled because the user does not yet have an Apple Developer Team.
- [x] User added `pawfolio://auth/callback` to the Supabase redirect allow-list; live simulator Google login returned successfully on 2026-08-28.
- [x] Live simulator verification confirmed Keychain session restoration after process restart and complete session removal after sign-out plus a second restart.
- [x] Web tombstone client deployed to production on 2026-08-28 as Cloudflare Worker version `9efa3115-a007-4b38-876a-ed4b6642c08c`.
- [x] Production Web smoke test created and deleted `SYNC-TOMBSTONE-TEST-20260828-A`; Supabase retained row `h_1787900983061_vpott` with `schemaVersion = 2` and equal `deletedAt`/`updatedAt` (`1787901164683`). No existing holding was edited or deleted.
- [x] The production `SupabaseCloudHoldingRepository` is now injected in `RootTabView`; the paused-sync gate was removed after the Web tombstone was confirmed.
- [x] Fresh native Google authentication pulled the production Web tombstone into account-scoped storage without displaying it in the active portfolio.
- [x] Account views consume a privacy-preserving presentation model instead of reading a full session email directly.
- [x] Supabase Google metadata can provide an optional display name; older Keychain sessions remain decodable and fall back safely.
- [x] Versioned per-account local profiles now use `schemaVersion = 2`, store `updatedAtMilliseconds`, and migrate all six legacy placeholder avatar IDs without losing the saved display name.
- [x] Native profiles use the same closed whitelist as Web: nine `face:*` identifiers and nine `cat:*` identifiers.
- [x] All 18 approved Web avatar images are packaged in the iOS Asset Catalog; the catalog is included in the app target's Resources phase.
- [x] The native profile editor uses real bundled images, a 20-character name limit, accessible avatar selection, and explicit local-only disclosure.
- [x] Pure-Swift profile reconciliation uses last-write-wins timestamps with a local exact-tie winner and avoids uploading an unedited migrated local record when the remote row is missing.
- [x] `SupabaseCloudProfileRepository` implements profile read/upsert, shared-avatar validation, ISO-8601 timestamp conversion, owner-key validation, and one-time 401 refresh/retry behind `CloudProfileRepository`.
- [x] `ProfileSyncCoordinator` independently fetches, reconciles, persists remote winners, uploads local deltas, and preserves retryable local state after an upload failure.
- [x] `AccountViewModel` accepts profile sync as an optional dependency with independent local-only, syncing, synchronized, pending-upload, and failed states. Profile failures cannot replace the holding-sync presentation state.
- [x] `RootTabView` now shares one `UserDefaultsAccountProfileStore` between `AccountViewModel` and a production `ProfileSyncCoordinator` backed by `SupabaseCloudProfileRepository`.
- [x] Controlled production Profile validation passed for iOS → Web, Web → iOS, last-write-wins timestamps, token refresh, and terminate/relaunch persistence.
- [x] `ios/Docs/PROFILE_SYNC_CONTRACT.md` records the existing Web `profiles` shape, completed compatibility foundation, and the remaining gate before native cloud writes.
- [x] `ios/Docs/SYNC_CONTRACT.md` defines the cross-platform payload and required Web tombstone migration.
- [x] `ios/Docs/MIGRATION_PLAN.md` contains the durable feature inventory.
- [x] The native launch screen is provided by `LaunchScreen.storyboard`: `LaunchBackground` colour plus a 148 pt centred `LaunchLogo`, verified in both light and dark on the simulator.
- [x] `LaunchLogo` is generated from `AppIcon-1024.png` as a rounded square at 1x/2x/3x (200/400/600 px).
- [x] The redundant `INFOPLIST_KEY_UILaunchScreen_Generation = YES` build setting was removed; `Info.plist` now declares `UILaunchStoryboardName`.
- [x] App Icon audit: a single 1024x1024 universal image with no alpha, which satisfies current Xcode requirements. iOS 18+ dark and tinted variants are still not supplied, so the system derives them.
- [x] Every fixed `.font(.system(size:))` call site is gone from the sources.
- [x] New `PawBadge` (scales with Dynamic Type, capped at 1.6x) and `PawIntroHeader` (switches to a vertical layout at accessibility sizes) replace six hardcoded 42/52 pt circular badges.
- [x] `CatAvatarBadge` gained an opt-in `scalesWithText`; only the two badges beside body copy scale, so the avatar picker grid keeps its fixed geometry.
- [x] Accessibility-size money truncation in the portfolio is fixed: lower `minimumScaleFactor` for the total and metric tiles, a single-column metric grid, and vertical layouts for total profit and the history card so amounts never break mid-number.
- [x] The purely decorative summary badge is hidden at accessibility sizes so the width goes to the amounts, matching the "decoration subordinate to financial clarity" rule.
- [x] Reduce Motion needs no work: the sources contain no `withAnimation`, `.animation(`, or `.transition(`.
- [x] Dark mode re-verified on the launch screen and all four tabs; all colours already resolve through dynamic traits.
- [x] A DEBUG-only `PAWFOLIO_INITIAL_TAB` environment variable selects the initial tab, which makes per-tab visual QA and future UI tests possible without input injection.

### Current UI behavior

- The portfolio editor supports all four holding kinds.
- Market holdings require symbol, quantity, and unit cost.
- Interest/hybrid holdings support APR, simple/compound mode, and an Asia/Shanghai date string.
- Dividend holdings create/update compatible dividend records and allow an unknown pay date.
- Stable-interest rows and the summary include settled interest from the native valuation engine.
- Market rows use live quotes only; missing or non-USD quotes show as unavailable instead of silently treating cost as current value.
- Market selection opens a native searchable sheet; online results retain Yahoo `quoteSymbol`, asset type, name, and exchange.
- Search failure exposes curated offline results and an explicit manual-code path.
- Deletes disappear from the active list but remain in the JSON payload as tombstones.
- Existing quantity/principal fields are read-only; changes go through the native adjustment section.
- Market adjustments accept an explicit execution price or the current live USD quote.
- Market reductions expose an “All” action; a full reduction closes rather than deletes the source.
- Stable adjustments accept today or a future effective date using the Beijing calendar.
- Tapping a holding opens a native detail screen; editing remains available from its toolbar.
- The Adjustments segment shows execution time, quantity or principal, price, and effective date.
- The Income segment shows daily interest or dividend records, totals, confirmation state, and native swipe actions.
- The portfolio overview shows a native total-asset chart between the summary and holdings list.
- Day/week use short intraday history; month/year request Worker `/api/quote?symbol=…&range=1y` daily history.
- Chart range selection persists locally. Missing early coverage is flattened only with visible disclosure; missing current USD prices make the chart unavailable just like the summary.
- The Account tab remains fully native. Google opens the iOS system authentication sheet; Apple is visibly disabled pending an Apple Developer Team.
- A successful Google login switches to account-scoped local storage and synchronizes through the production Supabase repository.
- Signed-in identity uses the provider display name or a local override, shows only a masked account label, and offers nine cat-expression avatars plus nine real-cat profiles.
- Native profile edits remain isolated per account in versioned local storage and synchronize through the production Profile repository connected in `RootTabView`.
- A restored account session switches the portfolio to that account's local file. Guest holdings with no saved decision pause synchronization for an explicit copy/keep-separate choice.
- A completed guest copy is remembered per account. Manual retries thereafter use the account data only; signing out switches the portfolio back to the untouched guest file.

## Verification log

Successful on 2026-08-28:

```sh
env SWIFTPM_MODULECACHE_OVERRIDE=/tmp/pawfolio-module-cache \
  CLANG_MODULE_CACHE_PATH=/tmp/pawfolio-clang-cache \
  SWIFT_MODULECACHE_PATH=/tmp/pawfolio-swift-cache \
  xcrun swift test --disable-sandbox \
  --package-path ios --scratch-path /tmp/pawfolio-spm
```

Result after profile sync orchestration: 93 tests passed, 0 failures.

```sh
xcodebuild -quiet \
  -project ios/PawFolio.xcodeproj \
  -scheme PawFolio \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/pawfolio-derived \
  CODE_SIGNING_ALLOWED=NO \
  build-for-testing
```

Result: exit 0; app and XCTest targets compiled. The built simulator app is at `/tmp/pawfolio-derived/Build/Products/Debug-iphonesimulator/PawFolio.app`.

Named-simulator XCTest run also succeeded:

```sh
xcodebuild -quiet \
  -project ios/PawFolio.xcodeproj \
  -scheme PawFolio \
  -destination 'platform=iOS Simulator,id=D4D0F22F-4038-418E-9E58-4B29098AA7FB' \
  -derivedDataPath /tmp/pawfolio-derived \
  CODE_SIGNING_ALLOWED=NO \
  test
```

Result after profile sync orchestration and Asset Catalog target fix: all 104 XCTest cases passed on iPhone 17 Pro (iOS 26.5).

Web sync-contract tests also succeeded:

```sh
/Users/user/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node \
  --test tests/holding-sync.test.cjs
```

Result: 5 tests passed, 0 failures. `node --check` also passed for `public/app.js` and `public/holding-sync.js`.

Also verified:

- `plutil -lint ios/PawFolio.xcodeproj/project.pbxproj` passes.
- `plutil -lint ios/PawFolio/Resources/Info.plist` passes; the built app contains Bundle ID `com.jiujiucat.pawfolio` and URL scheme `pawfolio`.
- Source scan finds no `WebKit`, `WKWebView`, `UIViewRepresentable`, or `SFSafariViewController` usage.
- Live native Google OAuth verification succeeded through the iOS system authentication sheet. The app returned through `pawfolio://auth/callback`, restored the session from Keychain after termination/relaunch, and stayed signed out after logout plus another relaunch. A later production-sync verification signed the simulator back in; no credentials or tokens were recorded.
- Pre-deployment, `wrangler 4.126.0 deploy --dry-run` successfully packaged the Worker and all 50 files from `public/`.
- `wrangler 4.126.0 deploy` uploaded `holding-sync.js`, `index.html`, and `app.js`; 43 unchanged assets were reused. Production reports Worker version `9efa3115-a007-4b38-876a-ed4b6642c08c`.
- Live `https://www.jiujiucat.win/` references `holding-sync.js?v=1` and `app.js?v=113`. The live `holding-sync.js` SHA-256 matches the local source (`9d8a4e40dfa7ba319da56b1850419de77d05d6b6da1e24c54cb9d51706cc7d9f`), and `/api/search?q=AAPL` still returns results.
- Live simulator flow verified: Portfolio → Add Holding → search `AAPL` → select result → save 2 shares at $300 cost. Worker returned a $314.58 quote; UI displayed $629.16 total value and $29.16 / 4.86% profit.
- Native adjustment flow verified on the same local AAPL fixture: adding 1 share at the live $314.58 quote produced 3 shares, $943.74 total value, and the same $29.16 profit. Reducing 1 share then created a $314.58 zero-APR USDT holding and kept total value at $943.74.
- Native detail flow verified: the AAPL Adjustments segment shows both real local add/reduce events; the USDT Income segment shows the correct zero-APR empty state; a local VOO dividend fixture shows a confirmed $2.50 record and opens the frozen-quantity edit form.
- The visual-QA simulator currently may contain 2 AAPL shares at a $304.86 weighted cost, $314.58 USDT, and 1 VOO share with a $2.50 dividend record. This is local simulator data only; it is not source-controlled or attached to a remote account.
- Live Worker verification returned 251 USD daily points for `AAPL&range=1y`.
- Simulator visual QA verified the native chart card, week/month switching, list scrolling, and a chart endpoint equal to the displayed US$1,652.49 total. The one-year cache contained 251 points each for the local AAPL and VOO fixtures.
- Merge tests cover local-only, remote-only, newer local, newer remote, tombstone ties, `deletedAt` without `updatedAt`, legacy missing/zero timestamps, schema upgrades, and session expiration boundaries.
- Sync-coordinator tests cover account/guest file isolation, local/remote winners, upload failure and retry, pull failure without local overwrite, explicit guest copy, signed-out sessions, and expired sessions.
- Account presentation tests cover the import prompt, one-time copy semantics, saved keep-separate decisions, pending-upload retry, and sign-out scope switching.
- Web tests cover local/remote winners, missing records, tombstone timestamps and ties, legacy timestamp fallback, and schema upgrades.
- The normally signed simulator build at `/tmp/pawfolio-run` succeeded with `Sign to Run Locally`, preserving Keychain access.
- The production Web-to-iOS gate passed on 2026-08-28: Google login completed, the three simulator guest fixtures were explicitly kept separate, and the account page reported a successful 10-record sync.
- The active native portfolio did not display `SYNC-TOMBSTONE-TEST-20260828-A`. Its account-scoped JSON retained row `h_1787900983061_vpott` with `schemaVersion = 2` and equal `deletedAt`/`updatedAt` (`1787901164683`). No production holding was edited or deleted during this verification.
- Native profile visual QA passed on the normally signed simulator build. The existing `雪球` profile and masked account label survived the schema-2 migration; legacy `ginger` became `face:love` as specified. All nine face images and all nine real-cat photos rendered from `Assets.car`.
- Visual QA initially found that `Assets.xcassets` was referenced by the project but absent from the app target's Resources phase. The project file was fixed; `assetutil` now reports all 18 `Profile*` assets in the built app.
- Selecting BoBo, saving, terminating, and relaunching preserved the selection. The simulator fixture was then restored to `雪球` / `face:love`; holding sync continued to report 9 synchronized records and no complete email address appeared in the accessibility tree.
- Profile coordinator tests cover remote winners, local winners, unedited migrated records with no remote row, failed-upload retry, pull failure without local overwrite, and signed-out/expired-session rejection.
- Account ViewModel tests prove a remote profile result updates only identity/profile state and a profile-network failure leaves the successful holding state unchanged.
- Production Profile baseline recorded before enabling writes: Web/Supabase was `Long` / `face:horn` at `2026-08-28 03:20:13.077+00`; the simulator local record was `雪球` / `face:love` at `2026-08-28 07:53:12.614+00` and was therefore the expected last-write-wins result.
- After enabling production Profile sync, the normally signed iOS 26.4 simulator build uploaded the newer native value. Supabase showed `雪球` / `face:love` with the identical timestamp; the Account page reported both Profile and 9 holdings synchronized.
- Terminating and relaunching the app restored the Keychain session and `雪球` / `face:love` Profile, and Profile sync again reported success.
- Post-wiring verification passed: SwiftPM tests exited 0, generic simulator `build-for-testing` exited 0, the normally signed simulator build used `Sign to Run Locally`, and all 104 named-simulator XCTest cases passed on simulator `C46D7DBB-AB14-453E-9BF1-0A80F9357E94` (iOS 26.4).
- The Web Profile restore was saved as `Long` / `face:horn` at `2026-08-28 08:19:31.878+00`. Native pulled the same complete record and persisted the identical millisecond timestamp locally; another terminate/relaunch retained the name and `face:horn` avatar while both Profile and 9 holdings reported synchronized.
- The live check exposed that `立即同步` reused an expired in-memory session. `AccountViewModel.retrySync()` now asks the authentication service for a current session first, enabling token refresh without requiring a relaunch; its ViewModel test asserts the additional session read.
- `ios/Docs/MIGRATION_PLAN.md` now marks production Profile synchronization complete, and `ios/Docs/PROFILE_SYNC_CONTRACT.md` records the live two-way verification and active composition.
- After the manual-retry fix, SwiftPM again passed all 93 tests, generic `build-for-testing` succeeded, and the named iOS 26.4 simulator again passed all 104 XCTest cases. The latest normally signed build was installed; its `立即同步` smoke check retained `Long` / `face:horn`, 9 synchronized holdings, and a synchronized Profile state.

Milestone 6 launch experience and accessibility pass, 2026-08-28:

- SwiftPM: 93 tests passed, 0 failures, both before and after the changes.
- Named simulator `C46D7DBB-AB14-453E-9BF1-0A80F9357E94` (iPhone 17 Pro, iOS 26.4): 104 XCTest cases passed, 0 failures, exit 0.
- The normally signed simulator build at `/tmp/pawfolio-run` succeeded; `LaunchScreen.storyboardc` is present in the built app and `assetutil` reports `LaunchLogo` at scales 1/2/3.
- Launch screen verified visually on a cold launch after clearing the SplashBoard cache: light mode renders the rounded logo on `#F2F2F7`, dark mode renders it on black. Before clearing that cache every launch screen change appeared to have no effect.
- Pixel evidence that drove the storyboard decision: with `UILaunchScreen`/`UIImageName` the launch screen background matched `LaunchBackground` exactly (242, 242, 247) while the middle band of the screen contained exactly 1 distinct colour, including with an opaque solid-colour test image.
- Dynamic Type verified at `accessibility-extra-extra-extra-large` on all four tabs through `SIMCTL_CHILD_PAWFOLIO_INITIAL_TAB`. Before the fix the portfolio showed `US$858,8…` and metric tiles reading `US…`; after the fix the total, total profit, and all three metric tiles render in full.
- Default text size re-checked on all four tabs for regressions; the history card total no longer breaks mid-number.
- Source scan confirms no remaining `.font(.system(size:))` and no `withAnimation` / `.animation(` / `.transition(`.
- `plutil -lint` passes for `Info.plist` and `project.pbxproj`; the built `Info.plist` declares `UILaunchStoryboardName = LaunchScreen` and no longer carries a `UILaunchScreen` dictionary.

## Known limitations and risks

1. Non-USD Yahoo quotes are deliberately excluded from USD totals until the persisted model has an explicit currency conversion contract.
2. Quotes refresh on portfolio load, pull-to-refresh, and newly added market holdings; there is no foreground timer yet.
3. Google OAuth, callback allow-list configuration, Keychain storage, Supabase REST, and the production Web-to-iOS tombstone pull are verified. Apple login still requires an Apple Developer Team.
4. A corrupt local file blocks load and is preserved, but there is not yet an in-app export/recovery tool.
5. The Claude Code iOS Simulator MCP tools were unusable on this machine: every action returned "Xcode is installed but not selected" even though `xcode-select -p` is `/Applications/Xcode.app/Contents/Developer` and `xcodebuild` works. All verification this turn went through `xcrun simctl` (install / launch / screenshot) instead. Because that path cannot read the accessibility tree, the VoiceOver walkthrough is still outstanding.
6. Localization has not started. UI strings are hardcoded Chinese literals with no String Catalog.
7. iOS 18+ dark and tinted App Icon variants are not supplied. The brand mark is a monochrome photograph, so a deliberate design decision is needed before adding them.
8. Observation, not yet diagnosed: with the current 9 production holdings the week range reports a gain equal to the entire portfolio value, i.e. the window starts at zero. That is consistent with every position having been opened recently, but it should be re-checked once more history accumulates.

## Launch screen trap (read before touching launch assets)

Two things cost a lot of time this turn and will do so again:

1. `UILaunchScreen`'s `UIImageName` never rendered on the iOS 26 simulator, while `UIColorName` in the same dictionary worked. The project therefore uses `UILaunchStoryboardName`.
2. iOS caches launch screen snapshots in SplashBoard, and uninstalling the app does **not** reliably clear them. Any launch screen change can appear to have no effect. Before concluding a launch screen change failed, run:

```sh
xcrun simctl shutdown <UDID>
rm -rf ~/Library/Developer/CoreSimulator/Devices/<UDID>/data/Library/Caches/SplashBoard
xcrun simctl boot <UDID>
```

Also note that `simctl launch --wait-for-debugger` shows a blank placeholder window, not the launch screen, so it is useless for this check. Take a burst of screenshots during a normal cold launch instead.

## Feature migration audit, 2026-08-28

The user asked what functionality is still unmigrated, so `public/index.html` and `public/app.js` were compared against the native sources. Six Web features turned out to be missing from the native app **and** absent from the migration checklist; they are now recorded as section 6 of `ios/Docs/MIGRATION_PLAN.md`. The largest are the header market ticker (BTC/MSTR/QQQ rotation with US market-session badges) and the "我们家的猫" cat gallery (long-press photo viewer with name, description, sex, and birth date). The brand state illustrations in `public/illustrations/` have also never been added to the Asset Catalog.

Sections 7 and 8 of that file separate the remaining checklist items that the Web app does not have either (so they are new features, not migration gaps) from deliberate platform differences.

## Direction change, 2026-08-28: the UI replicates the Web

The user's instruction: **native code, but not a native-looking UI.** The app should look like the
Web app. `AGENTS.md`'s Design direction has been rewritten accordingly, and the earlier "prefer
native controls over web-shaped imitations" rule is void — following it is what produced the
feature gaps in section 6 of `MIGRATION_PLAN.md`.

`public/styles.css` is now the visual contract, the way `public/app.js` is the behavioral one.
Read its token comments before changing colours; most values were derived from contrast ratios.

What landed this turn:

- `PawTheme` is now a verbatim port of the Web design variables rather than an iOS palette.
- `PawControls.swift` holds the Web component replicas. The slider is hand-drawn because
  SwiftUI's `Slider` cannot produce a 2pt track with a 16pt ringed thumb.
- `PawChrome.swift` holds the Web header and the bottom tab bar.
- The tab bar went from four iOS tabs back to the Web's three. Account moved into the header
  avatar and opens as a sheet, which is why `CatAvatar`'s display extension is no longer
  fileprivate.
- The header market ticker rotates BTC / MSTR / QQQ against live quotes. **Its market-session
  badge is not built yet** — that needs `app.js`'s US Eastern session logic, holiday table and
  half-day table ported as tested domain code.
- Manual light/dark toggle, one of the section 6 blind spots, now works and persists.
- The calculator screen is rebuilt to the Web structure and gained the CNY figures it was
  missing: the live rate line, the `¥` sub-value on each of the three cards, and the `≈¥`
  estimate on the chart. The rate line uses a 24-hour clock like the Web.
- The natively-invented introduction cards and large navigation titles, which the Web does not
  have, were removed from the calculator screen. Do the same on every screen as it is ported.

Then, on the user's feedback that most of the Web is *not* card-shaped:

- Corrected the card rule. `#panel-retirement > .card` and `#panel-fx > .card` strip the card
  appearance entirely; only `.calculator` keeps it. The result section of the calculator was
  wrongly wrapped in a card and is now a bare block. The portfolio panel has no such override,
  so its cards stay.
- Bundled Remix Icon 4.6.0 (Apache-2.0, licence at `ios/PawFolio/Resources/LICENSE-remixicon.txt`)
  at the user's instruction: the three tab glyphs, moon/sun, the avatar placeholder, the swap
  arrow, close and add. They ship as template-rendered SVG assets. Every SF Symbol stand-in in
  the chrome is gone.
- Bundled the four real flags from `public/flags/`, replacing the emoji flags.
- Ported the FX screen: no card surface, real flags, the rounded swap connector, `--ink-4`
  result rows, 24-hour update time.
- Bundled the seven state illustrations from `public/illustrations/` as `Art*` assets, ready for
  the portfolio empty state and the login gate.

The portfolio screen is now ported too — the biggest one, and porting it restored four of the
section 6 gaps at once:

- The login gate: `login` illustration, Google button, and the 「先看看」 guest entry, wired to
  `AccountViewModel.isSignedIn`. The guest choice persists locally, as it does on the Web.
- Quick-add: three cards with live quotes, arrow-coloured change, and a 「一键添加」 button.
  Like the Web, that button opens a holding form **prefilled with the asset** rather than
  creating a position outright, so `HoldingEditorView` gained a `prefilledAsset` parameter.
- The merge-same-symbol checkbox, and the `no_data` empty state with the dashed add button.
- Holding rows in Web shape: 32pt round initial, tinted 生息 / 混合 badges, `--ink-4` fill.

Two clean-ups fell out of it: the old `PortfolioSummaryCard` and `PortfolioMetric` were dead after
the rewrite (130 lines, removed), and the history card was formatting money as the iOS-localized
`US$` instead of the Web's `$`.

**A real bug was found and fixed along the way.** `PawThemeController` assigned to an Optional
`@Published` property that has a `didSet` inside its own `init`. Optionals are implicitly
initialized to nil, so that assignment is a *re*-assignment and fires the observer, persisting
"follow the system" as an explicit choice. The effect was that the app locked itself into
whichever appearance was active at first launch and could never return to following the system.
It now initializes the backing store directly. Note when clearing that key by hand: `plutil
-remove` treats the dotted key `pawfolio.theme` as a nested key path and fails silently — use
plistlib, with the simulator shut down.

The account sheet and the cat gallery are ported as well, which finishes the screen-by-screen
pass:

- The account sheet follows the Web profile panel: grabber, centred title, close at the right,
  save/login in the footer; a 20-character name field, the nine face avatars in a 3-wide grid,
  sign-out, and the masked account line. Signed out, the title becomes 「登录」 and only the
  `login` illustration and one sentence remain — the Web's reasoning is that letting someone edit
  a name they cannot save is worse than not offering it.
- Sync status and the guest-import choice are native-only (the Web syncs silently) and sit after
  the Web structure rather than replacing any of it.
- The cat gallery reproduces the photo-print treatment: square corners, 4pt white border and the
  drop shadow that the Web's own comment calls the only shadow in the whole site. Each cat shows
  its name with a pink/blue sex glyph and its one-line description; long-press opens the viewer.
- The Web's easter egg survives: single-tap the header avatar for the profile, **double-tap** for
  the cats. The double-tap gesture must be declared before the single tap or it never fires. The
  profile sheet also carries an explicit entry, since nobody discovers a double-tap.
- New `Domain/CatProfile.swift` holds the nine cats and `CatAgeFormatter`, a port of `app.js`'s
  `catAgeText` / `catBirthText`, with 11 unit tests over the wording rules and the edge cases
  (year-only birth, birthday later this month, a birth date in the future).
- `AccountProfileEditorView` became dead after the rewrite (138 lines, removed): the Web edits
  name and avatar inside the sheet itself rather than on a second screen.

The market-session badge closes the last section 6 gap. `Domain/MarketSession.swift` ports
`app.js`'s `marketSessionKey` along with the 2026–2027 holiday and half-day tables. Time-zone
conversion goes through `TimeZone(America/New_York)` rather than a hand-computed offset, since US
daylight saving switches twice a year. 14 unit tests cover the session boundaries, Friday 20:00
rolling into the weekend, Sunday 20:00 reopening, Monday's small hours continuing Sunday night,
holidays, the morning after a holiday having no night session to continue, the 13:00 half-day
close, and both daylight-saving transitions. The badge only appears for equities — crypto has no
sessions.

Six DEBUG-only environment switches now exist for visual QA, all read via `SIMCTL_CHILD_`:
`PAWFOLIO_INITIAL_TAB`, `PAWFOLIO_FORCE_GATE`, `PAWFOLIO_EXPAND_CHART`, `PAWFOLIO_SHOW_CATS`,
`PAWFOLIO_PREVIEW_CAT=<id>`, and `PAWFOLIO_TICKER_INDEX`. They exist because `simctl` has no
input injection, so anything behind a tap, double-tap or long-press is otherwise unreachable.

Note when verifying the badge: the simulator's clock is on US Eastern, not Beijing time, so a
10:53 reading there is a regular trading session rather than the night session.

Asset logos now resolve for real, in the four places that share the Web's `applyAssetLogo`:
the ticker, quick-add, holding rows and search results. `Domain/AssetLogo.swift` builds the
candidate list (9 unit tests) and `Data/AssetLogoStore.swift` tries them in order, caches the
result in memory, and keeps the CoinMarketCap id table on disk for a day. Points worth keeping:

- Crypto and stable holdings go CMC → CoinCap → cryptoicons; equities go Parqet first and then
  retry the crypto sources, because older holdings never stored the `-USD` suffix and `assetType`
  alone misjudges them.
- The id table comes off the network, so a CMC id is only interpolated into a URL after it
  validates as a positive integer.
- A hand-typed stable name (「活期」) produces no candidates at all rather than two guaranteed
  404s.
- `Regex` cannot be a `static` property under Swift 6 strict concurrency (it is not `Sendable`),
  so the ticker-shape check is written with character arithmetic instead.

Merging same-symbol holdings is finished. `Domain/HoldingGrouping.swift` does the grouping, the
merged summary and the interest summary (10 unit tests); the group row expands into its lots with
the interest summary placed **above** them, because putting it after the lots pushes it off screen
once a group has several. The Web's "don't state what you don't know" rules are ported and tested:
a single lot without a quote invalidates the whole total; a mixed annual rate prints no rate tag;
mixed simple/compound prints no mode tag (picking one would be a misstatement); a group mixing
interest and market lots reports a combined cost instead of a share count.

Verified against real data rather than a fixture: the account's four USDT lots merge into one
group, and because three of them differ in rate (21.09% / 3.75% / 2.7%) and in interest mode, the
group row correctly shows no tags at all.

Two simulator preferences were flipped by hand to reach that screen (`merge-same` and
`recommend-dismissed`) and then restored. Both live in the app's sandbox plist under dotted keys,
so edit them with plistlib while the simulator is shut down — `plutil` reads a dotted key as a
nested path and fails silently.

`PAWFOLIO_EXPAND_GROUP=<symbol>` is the seventh QA switch, for the expanded state.

## Measure the rendered page, don't copy the CSS source

The user pointed out that the native app wrapped things in cards that the Web had removed. Two
systematic errors turned up, both from implementing the desktop values in the stylesheet and
missing the narrow-screen overrides:

1. `#portfolio-app > .card` resets padding, radius and background, so all three portfolio
   sections sit directly on the page surface — the CSS comment says spacing rather than nested
   containers separates them. The earlier sweep found `#panel-retirement > .card` and
   `#panel-fx > .card` but missed this one, because the selector is `#portfolio-app`, not
   `#panel-portfolio`. Only the calculator's 「投资计划」 block is still a card anywhere in the app.
2. `@media (max-width: 767px)` drops the page gutter, the header padding and the remaining card
   padding to 16, and compresses `.metric` to `10px 12px` with a 20px figure. **Every iPhone is
   inside that breakpoint**, so the 28/24 desktop values were wrong everywhere.

Extracting every size-related media query afterwards turned up four more rules that had never
been implemented at all:

- `max-width: 485px` hides the ticker's asset name, `415px` hides the change, `347px` hides the
  whole ticker. On a 402-wide iPhone the ticker is therefore **only** the logo, the price and the
  session badge — the name and change were being drawn.
- `max-width: 560px` compresses `.metric` to padding 10, a 17/24 figure and 11px captions, but
  `max-width: 389px` comes after it and restores padding 10px 12px with a 20/28 figure when the
  grid collapses to one column. Three tiers, all keyed to viewport width.
- `max-width: 380px` tightens the quick-amount gap to 4 and drops the principal field to 20px.
- `max-width: 560px` sets the calculator chart to 200px, not 210.

Web media queries key off the **viewport**, so `RootTabView` measures it once and injects it
through `\.pawViewportWidth`; components read that instead of each measuring their own container.

The FX screen and the sheets were measured property by property and matched already.

From now on, verify spacing by reading computed styles in the browser — at more than one width —
rather than reading the stylesheet. The measured values are in section 9 of `MIGRATION_PLAN.md`.

## Concurrent edits are happening in this repo

Several files changed between my own reads during one session: `PortfolioChartCanvas.swift`
gained a complete press-and-scrub implementation I did not write, and `PawLayout`'s measured
16pt gutters were reverted to the 28/24 desktop values (restored again, with the provenance in a
comment). If more than one agent or window is editing this project, expect to overwrite each
other — re-read a file immediately before patching it rather than trusting an earlier read.

## What the final sweep found

Auditing by "which overlays and feedback mechanisms does the Web have" rather than by "which
native controls remain" turned up four more gaps, now closed: the asset-search sheet, the
dividend-record editor, the three secondary record lists in the detail sheet, and — the one with
real behavioural weight — **toasts**. The Web calls `showToast()` in 33 places and native had no
such channel at all; `DesignSystem/PawToast.swift` now covers the success cases (adjustments,
deletions) while validation errors keep using alerts.

Dividend frequency is picked in its own overlay on the Web, not inline; both the holding editor
and the record editor now open the same `DividendFrequencySheet`.

Two dead views were removed (`overviewList`, `incomeList` — 97 lines, orphaned when the detail
screen became a sheet) and the last 19 semantic system fonts became Inter. `Features` now has zero
native lists, zero navigation titles and zero system fonts; the only remaining `Picker`s are
`DatePicker`s.

## The tab bar needed to float for its glass to show

`.ultraThinMaterial` was on the tab bar from the start but invisible, because the bar sat as the
last row of a `VStack` with nothing passing beneath it. It is now a `safeAreaInset(edge: .bottom)`
overlay so each screen's scroll content runs underneath, with the glass extended to the physical
screen edge and the labels held inside the safe area — the arrangement the Web comment describes.
Switching tabs fires one light haptic.

Also: a `Button` inside a `ScrollView` waits for the system to decide whether the touch is a
scroll, which reads as lag on the expand/collapse handle. That control uses `onTapGesture` now,
and its rotation runs at 0.12s rather than the Web's 200ms — that duration was tuned for a mouse.

## The portfolio chart is hand-drawn, not a chart library

Tested on the user's own device, four things were wrong because native drew a plain Swift Charts
line while the Web chart has its own shape:

- The collapsed state carries a **72pt sparkline** beside the total (`clamp(104px, 36%, 200px)`
  wide); native hid the chart entirely. Expanding drops that column so the figures span the row —
  that was the "expanded width is wrong" report.
- The area under the curve is a **dot matrix**, not a fill: 6px grid / 1.4px dots / 34% for the
  large chart, 4px / 1.1px / 30% for the sparkline, because at 120×72 a 6px grid leaves almost
  nothing.
- The period's **peak value is labelled above its own point** at 11px, with no "最高" caption.
- The handle icon rotates 180° over 200ms; it does not translate.

All of this now goes through SwiftUI `Canvas` in `Features/Portfolio/PortfolioChartCanvas.swift`,
with the scale padding (0.30/0.12 large, 0.26/0.10 mini), `CHART_PAD` and the 188pt height copied
over. The x-axis is a separate row outside the canvas, and the timestamp line always occupies its
space — otherwise the whole chart jumps down when it appears.

Press-and-scrub is implemented: a dashed cursor, everything right of it dimmed to 32%, and the
headline figures switching to the value under the finger. Touch waits 180ms before it engages,
otherwise the gesture competes with the page's vertical scroll.

Seeding guest fixtures is the way to exercise the chart without touching the account: write
`Library/Application Support/PawFolio/holdings-v1.json` in the app container. Its envelope key is
`storageVersion`, not `schemaVersion` — `schemaVersion` belongs to each holding. A malformed file
correctly surfaces "本地持仓文件无法读取" instead of being silently replaced.

## Holding detail is now a sheet

This was the last item of the UI port. The detail screen is presented as a bottom sheet rather
than a pushed page, and its content follows the Web 「盈亏明细」 panel: the symbol and a large
signed total on top, then one `--bg-2` list whose rows are 64 tall with hairlines between them.
Rows appear conditionally by holding kind — interest holdings show no share count, unit cost or
last price; market holdings show no APR or interest rows. Below that sit the latest-dividend card
(four fields in a fixed 2×2, because the Web's comment notes auto-fit drops the fourth onto its
own line on narrow screens) and the record entries, with 「编辑持仓」 in the footer. Record lists
open as a second sheet, as they do on the Web.

**One deliberate divergence, awaiting the user's call.** The Web has no adjustment-history list
at all: adjusting a position is a one-off action there and the records only live in the data.
Native had built it as a segment of the detail page; it is now demoted to a third record entry
alongside dividends and interest. Strict parity would delete it, but that removes a feature that
lets someone see their own add/reduce history, so it stays until the user decides.

Inter 4.1 is now bundled too, at the user's request: four static weights under
`ios/PawFolio/Resources/Fonts/`, declared in `UIAppFonts` as `Fonts/Inter-*.ttf` — the
subdirectory must be in that path or the fonts silently fail to register. `PawFont.inter` wraps
them and the 29 font call sites in ported code now use it. The PostScript names were read out of
each ttf's name table rather than guessed.

Two deliberate consequences: Inter has no CJK glyphs, so Chinese falls back to PingFang SC exactly
as the Web font stack does; and sizes use `fixedSize`, so ported screens no longer respond to
Dynamic Type. That matches the Web, whose px sizes and fixed control heights (52 input shell,
40 button, 36 segment) would otherwise break, and the user has deprioritized accessibility.

## The calculator chart is the same chart now (Web + iOS, 2026-08-29)

At the user's request the calculator's 总资产变化 chart was rebuilt to match the expanded portfolio
chart — same dot matrix, same peak label, same press-and-scrub — with two differences they asked
for: **no red/green anywhere**, and a shorter canvas (150 instead of 188/234).

Monochrome is not just the curve. The headline 涨跌 figures under the total used to take
`is-gain`/`is-loss`, and those classes are gone on both platforms: this is a projection from a rate
someone typed, not a real position, and colouring it made it read like actual P&L. Web now paints
`.chart-sub` with `--ink-40`; iOS uses `PawTheme.ink40`.

Both sides share the change:

- iOS — `PawPortfolioChart` grew a `height` parameter; `CalculatorView` passes `tone: PawTheme.ink`
  and `height: 150`, holds the scrub index, and renders its own x-axis row.
- Web — `drawChart()` in `public/app.js` was rewritten onto the same helpers the portfolio chart
  uses (`chartScale` / `tracePath` / `fillDotMatrix` / `columnHeightFn`), the Y-axis ticks are gone,
  and the hover tooltip was replaced by the scrub. `#chart-tooltip` and `showTooltip` are deleted;
  `#chart-scrub-label` in `.chart-sub` shows which point is being read.

**A trap worth remembering.** `drawChart` runs during top-level initialization (`initializeTheme` →
`applyTheme` → `drawChart`), which is *before* `CHART_DOT_STEP` is defined further down the file.
Referencing that `const` there throws a TDZ `ReferenceError` and takes the whole page down — the
function declarations hoist, the `const` does not. The dot step is written as a literal with a
comment saying why. Any other constant pulled from the portfolio-chart section has the same
hazard.

Verified in the browser at 390×844 in both themes, and with synthetic pointer events: release
restores the final value, mouse scrubs on press, touch needs the 180ms hold, and a touch that
drifts vertically before that cancels instead of hijacking the scroll.

## Global pass, 2026-08-29: dividers, motion, and holding notes

Three things the user asked for in one sweep.

**Every divider is 0.5pt.** `PawDivider` in `PawControls.swift` is now the only way to draw one;
the four hand-written `Rectangle().fill(PawTheme.ink10).frame(height:)` call sites had drifted into
two thicknesses (the tab bar at 0.5, everything else at 1) and the difference was visible in dark
mode. Card and input **borders** (`strokeBorder(…, lineWidth: 1)`) were deliberately left alone —
those are outlines, not separators. Say so if the user meant those too.

**Motion goes through `PawMotion`** (in `PawTheme.swift`, next to the other design tokens). It
wraps the iOS 17 system spring presets — `.snappy` / `.smooth` — instead of the hand-written
`.easeOut(duration:)` calls that were scattered around. Springs matter here beyond taste: they
retarget from the current velocity when interrupted, so repeatedly tapping a group open/closed or
cycling the ticker no longer snaps back to the start of a curve. Five tokens: `expand` (0.28),
`selection` (0.22), `appear` (0.3, slight bounce), `disappear` (0.18, faster than entry), `press`
(0.12). Applied to: chart expand/collapse and its handle, merged-group expand, the merge toggle
(the whole list re-sorts, so it needs one), holdings list insert/remove, both segmented controls,
toast, ticker rotation, and `PawPressableButtonStyle`.

The segmented controls got `matchedGeometryEffect` so the selected block *slides* between segments
rather than cross-fading — with only two segments a cross-fade reads as a flicker.

`MarketTickerViewModel.rotationDuration` is deleted; nothing referenced it after the switch.

**Holding notes (both platforms).** `Holding.note`, optional, at most 20 characters, shown in the
profit breakdown only when set. The cloud stores holdings as a whole `payload` JSON blob, so this
needed **no Supabase migration** — no SQL for the user to run.

The length rule is the fiddly part and both sides must agree:

- Count `Character` / code points, never UTF-16. `String.utf16.count` and HTML `maxlength` both
  count a 🐱 as two, which would cap the web at 10 emoji while native allowed 20 — and `maxlength`
  can split a surrogate pair. The web input therefore has **no `maxlength`**; an `input` handler
  truncates by code point instead.
- Trim, and treat blank as absent, so "has a note" is one question with one answer on both sides.
- `Holding.normalizedNote` re-applies the rule on decode: a longer note written straight into the
  cloud gets cut to the same length rather than rendering something the web cannot show in full.
- Truncate rather than reject keystrokes — rejecting traps Pinyin IME mid-composition, where the
  in-progress letters count toward the limit.

Five tests cover this (153 total). Verified on the simulator: the note row renders at 20 characters
without wrapping, is absent when there is no note, and the editor field sits under 單位成本價 —
and on the web at 390×844 for single, empty, and merged holdings.

## Exact next task

The user has explicitly deprioritized accessibility work, so the VoiceOver walkthrough is on hold.

1. Design the network-failure, empty-data, and sync-conflict states. Migrating the brand illustrations belongs to this task.
2. Localization is still untouched; supported languages need a user decision.
3. VoiceOver walkthrough, on hold at the user's request. It also needs the simulator MCP tools repaired or a manual Accessibility Inspector pass.
4. Keep Sign in with Apple disabled until the user has an Apple Developer Team. Device builds
   currently sign with the free Personal Team (`DEVELOPMENT_TEAM=HGTMKU5HMG`, pass
   `-allowProvisioningUpdates`); that certificate expires after 7 days, so a reinstall is needed
   roughly weekly until there is a paid team. TestFlight still needs one.

Detailed operator steps live in `ios/Docs/AUTH_SETUP.md`. Never request or commit a user password, access token, refresh token, Google client secret, or Apple private key.
