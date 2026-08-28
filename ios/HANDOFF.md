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

Milestone 5 production holding and Profile synchronization is verified in both directions. The original Web Profile has been restored, native relaunch persistence passed, and production Profile networking remains enabled.

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

## Known limitations and risks

1. Non-USD Yahoo quotes are deliberately excluded from USD totals until the persisted model has an explicit currency conversion contract.
2. Quotes refresh on portfolio load, pull-to-refresh, and newly added market holdings; there is no foreground timer yet.
3. Google OAuth, callback allow-list configuration, Keychain storage, Supabase REST, and the production Web-to-iOS tombstone pull are verified. Apple login still requires an Apple Developer Team.
4. A corrupt local file blocks load and is preserved, but there is not yet an in-app export/recovery tool.

## Exact next task

Begin Milestone 6 productization without blocking on Apple Developer enrollment:

1. Audit and complete the App Icon and native launch experience in the Asset Catalog.
2. Run the localization, Dynamic Type, VoiceOver, dark-mode, and Reduce Motion checklist across all tabs.
3. Keep Sign in with Apple disabled until the user has an Apple Developer Team, then perform real-device signing and TestFlight preparation.

Detailed operator steps live in `ios/Docs/AUTH_SETUP.md`. Never request or commit a user password, access token, refresh token, Google client secret, or Apple private key.
