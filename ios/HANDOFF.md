# PawFolio iOS handoff

Last updated: 2026-09-07

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

## V2.1.0 资金账本重构（2026-09-04 起，基础账本已实现）

用户 2026-09-04 提出核心问题：**总资产总是和现实对不上账**，因为持仓可以凭空创建、
凭空删除，系统里根本没有「钱从哪来、到哪去」的概念。这一整轮重构命名为 **V2.1.0**。

- 产品逻辑全文：`ios/Docs/LEDGER_MODEL.md`（按 2026-09-05 最终确认更新）
- 功能树可视化：Artifact「PawFolio 资金账本 V2.1.0」
- 现状：V2.1.0 已完成本地产品化。schema-v3 账本、余额/成本投影、真实 USD 估值、Earn、
  schema-v2 期初迁移、guest/account 导入和 Figma 对应产品 UI 均已接通；
  `MARKETING_VERSION = 2.1.0`。云端 ledger schema/RLS 仍按已确认范围留到独立阶段设计。

**最终产品决策（用户 2026-09-05 拍板，不要退回旧草案）：**

1. 买卖只发生在 Exchange / Trading；结算币只支持 USD、USDT、USDC。Pay 才能选择
   Bank、Cash、Exchange、Alipay、WeChat 等资金位置。
2. Add asset 是简单外部入金，只收可选备注，不验证真实来源，不计入投资收益。
3. Earn 允许法币、稳定币、Crypto，禁止股票；法币/稳定币从 Spot 进入，Crypto 从 Trading
   进入并赎回 Trading。
4. 定期只做单利；结构化产品只展示参数和简单计息，不做障碍或结算引擎。
5. 什么时候真实派息，什么时候生成利息流水；复利在那一刻复投，单利不进本金。
6. 不做换汇流水、不增加第四个 Tab；Transactions 从右上角 history 进入。
7. 不做股息功能；旧字段只为兼容 schema-v2 数据保留。
8. 当前先完成本地账本，云端 ledger schema/RLS 等本地交互稳定后再设计。

## 行情数据源切换到 Binance（2026-09-07，本轮）

**用户决定：整站放弃 Yahoo / TradingView / CoinGecko，只用 Binance。** Yahoo 是
非官方接口、会 403、没有 SLA。Web 和 iOS 共用同一个 Worker，所以两端必须同时改 ——
**Worker 一上线，旧版 iOS 就会失效**（`/api/search` 已删除，`/api/quote` 的返回
结构也换了）。

⚠️ **Binance 有两套完全不同的股票产品，别搞混：**

| | 现货 bStocks | **Binance Stocks（本项目用的）** |
|---|---|---|
| 代号 | `AAPLB`，交易对 `AAPLBUSDT` | `EQ_VOO`，symbol `VOO` |
| 是什么 | 代币化股票，第三方发行，USDT 计价，7×24 | **真实美股**，真实价格与时段 |
| 覆盖 | 72 个，**没有 VOO** | 7928 个（4805 股票 + 3122 ETF） |
| 接口 | `api.binance.com/api/v3` | `www.binance.com/bapi/equity`（public，无需鉴权） |

用代币盘给持仓估值会把 0.2~0.7% 的跟踪偏差直接变成盈亏里的误差，所以**只用后者**。

### 本轮改了什么

- 新增 `Domain/MarketCatalog.swift`：纯 Swift 的目录 + 解析 + 搜索，可单测。
- `Data/MarketDataClient.swift`：
  - 新增 `MarketCatalogCache` actor（进程内缓存 + 同一时刻只拉一次；磁盘那层交给
    URLSession 协议缓存，Worker 已带 `max-age=21600`）。测试可用 `seeded:` 注入。
  - `search` 不再打 `/api/search`（端点已下线），改为本地目录过滤 —— 零请求、
    零延迟、没有防抖和竞态。
  - `quote` / `oneYearHistory` 改用 `/api/quote?eq=` 或 `?pair=`，解码新的
    `{price, change, series}` 结构。
  - USDT 计价的盘口乘 USDT/USD 得到美元价；**涨跌幅不乘**（分子分母同乘一个数
    比值不变，乘了只会把稳定币自己的抖动混进标的的涨跌）。
- `Domain/LedgerValuation.swift`：稳定币按**真实现价**估值，不再写死 1。
  取不到真实价时完整退回 1:1。`marketQuoteSymbol` 对 `.stablecoin` 返回代号，
  这样报价才会真的被拉取。
- `Docs/WEB_PARITY.md` 新增两节：Market data source、Stablecoin valuation。

### 验证

- `xcrun swift test` —— **232 tests, 0 failures**（2026-09-07 17:20）。
- `xcodebuild ... build-for-testing` —— **TEST BUILD SUCCEEDED**。
- 新增 `PawFolioTests/MarketCatalogTests.swift`（解析/撞号消歧/legacy `-USD`/
  搜索排序/内置兜底表）；`MarketDataTests.swift` 里 Yahoo 形状的用例已改写。
- **模拟器 UI 没跑**（这台机器点不了模拟器，见既有限制），且**Worker 未部署**，
  所以真实端到端还没验过。

### 下一步

1. **部署 Worker 后立刻验这三个端点**，iOS 的所有行情都依赖它们：
   `/api/catalog`、`/api/quote?eq=VOO`、`/api/prices?eq=VOO,AAPL`。
2. ~~iOS 目前是轮询~~ **已完成**：`Data/MarketStreamClient.swift`（actor +
   `URLSessionWebSocketTask`）。只有加密走推送 —— Binance Stocks 没有公开行情流，
   美股仍由 `refreshValuation` 轮询（一次请求覆盖所有标的）。
   - `ticks()` **只能调一次**：每次调用都会结束上一条流，正在 `for await` 的
     循环会随之退出，表现是「价格突然不动了」。加订阅走 `subscribe(symbols:)`，
     那条路不碰流，而且是幂等的，每轮估值刷新都调也没有额外代价。
   - 涨跌幅不重新联网算：上一次完整报价里的 price 和 changePercent 已经隐含了
     北京日基准（base = price / (1 + change/100)），用它算出来的新涨跌和 Worker
     完全一致，既省一次请求也不会两端各算一个数。
   - 静默 30 秒强制重连：切后台回来时 `task.state` 常常还是 running，实际早就
     不通了，光等回调等不到。重连退避带抖动。
3. 稳定币真实估值改变了总资产的显示值，UI 上是否要给一处说明（Web 那边把
   「总利息」改成了「总盈亏」），iOS 侧还没做对应的文案区分。

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
- Every market reduction books its proceeds into a **new** zero-APR USDT holding noted `<代码> 卖出所得`; existing stable holdings are never touched.
- Stable adjustments accept today or a future effective date using the Beijing calendar, and take effect at that date's own 16:00 settlement.
- While the adjustment amount field has a value, the sheet's footer button becomes 确认加仓/确认减仓 instead of 保存.
- Tapping a holding opens a native detail screen; editing remains available from its toolbar.
- The Adjustments segment shows execution time, quantity or principal, price, and effective date.
- Long-pressing an adjustment row deletes it. Deletion is an undo, not a log tidy-up: market records are removed by rewinding every position adjustment to the opening quantity/cost and replaying the survivors, so deleting a middle record stays exact; a deleted full sale reopens the holding. Deleting a reduction also tombstones the USDT it created (matched by identical millisecond `createdAt`), unless that USDT has been edited since — then it is left alone and the dialog says so. Hybrid principal rows are derived from position changes and are not individually deletable.
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
8. `HoldingEditorView`'s draft is a snapshot taken when the sheet opens. Read-only quantity/principal now come from the live holding on save, but `costPerShareText` and the interest fields are still snapshot values — keep dismissing the sheet after an adjustment, or refresh the draft, before adding any flow that adjusts and then saves in one session.
9. Observation, not yet diagnosed: with the current 9 production holdings the week range reports a gain equal to the entire portfolio value, i.e. the window starts at zero. That is consistent with every position having been opened recently, but it should be re-checked once more history accumulates.

## Never use a tuple as a `withTaskGroup` result type (2026-09-02)

Optimized builds crashed a few seconds after launch until this was found. The cause is a
compiler/runtime bug, not application logic:

```
libc++abi: Pure virtual function called!   → SIGABRT
  __cxa_pure_virtual
  swift::AsyncTask::completeFuture(swift::AsyncContext*)
```

`MarketQuoteRepository` used `withTaskGroup(of: (String, MarketQuote?).self)`. Changing **only**
the child result type from that tuple to the named struct `MarketQuoteFetchResult` — same
concurrency, same structured-concurrency shape, same everything else — fixes it. Measured on
Xcode 17F113 / iOS 26.5.2:

| Variant | Crashes |
| --- | --- |
| tuple result type (original) | 8 / 10 |
| named struct result type | 0 / 10, plus 0 / 12 on the final build |
| `-Onone` | none seen |
| `-Osize`, `-O` singlefile, `-O` wholemodule | all crash |
| `COPY_PHASE_STRIP=NO` | no effect |

**The crash is intermittent — roughly 8 runs in 10.** Never conclude anything from a single
launch. Two hypotheses were "confirmed" by one lucky run each and both were wrong: the
`AssetLogoStore` shared-future theory, and the "task groups in general" theory. Each looked fixed
because the probe happened to reduce concurrency. Use
`scratchpad/runN.sh` style repetition (≥10 launches) for any verdict here.

Rule for this repo: **a `withTaskGroup` child result type must be a named `Sendable` struct, never
a tuple.** Those two call sites are the only task groups in the app; `grep -rn "withTaskGroup"`
before adding another.

## Legacy items cleaned up in the same pass

- `COPY_PHASE_STRIP` was `YES` in Release (Xcode's own templates use `NO`, and it is redundant
  with `STRIP_INSTALLED_PRODUCT`). Now `NO`. It was **not** the crash cause; tested separately.
- Release never set `SWIFT_OPTIMIZATION_LEVEL`, so optimization came from an implicit default
  while Debug pinned `-Onone` explicitly. Release now pins `-O`.
- `HoldingDraft.makeHolding` required `annualRate > 0` for interest holdings, so a 0% holding
  could not be saved at all — you could not even fix its name or note, and the error said
  "请输入有效的年化利率". Every market reduction now creates a 0% USDT position, so this was about to
  bite constantly. Now `>= 0`; an empty field is still rejected. **The Web has the same guard at
  `app.js` line ~4009 and was left alone** per the iOS-only rule — fix it there if the Web ever
  needs to edit a sale-proceeds holding.
- `HoldingDraft` is private to `HoldingEditorView.swift` and has no unit tests, which is why the
  guard above survived. Worth extracting if that validation grows.
- Checked and fine: no dangling references to the deleted `PawTheme.swift`, no TODO/FIXME/HACK
  left, no Swift compiler warnings, and the two `points.first!`/`points.last!` force unwraps in
  `PortfolioView.axisLabels` are guarded by `count >= 2` on the preceding line.

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

字数上限的呈现方式后来又改了一轮：不写「最多 20 个字」这类说明文案，也不再边输边裁。
超过 20 个字才报红并禁用保存——截断会让人以为自己打漏了字，而说明文案对正常输入的人
是纯噪音。输入框右侧另挂了一枚清除按钮，有内容才出现。备注的落点跟着持仓类型走：
市场类在单位成本价下面，纯生息没有那一格，改挂在计息方式下面（Web 靠 `app.js` 把同一个
输入框挪到另一个锚点，不做两份 input）。

顺带删掉了持仓列表底部的「行情已更新」。其余几条状态提示（取数失败、走了缓存、非美元
标的）都有信息量，保留；只有「一切正常」那条是在页面底部常驻一行废话。

Five tests cover this (153 total). Verified on the simulator: the note row renders at 20 characters
without wrapping, is absent when there is no note, and the editor field sits under 單位成本價 —
and on the web at 390×844 for single, empty, and merged holdings.

## Loading 换成会跑的猫（2026-08-30）

用户给了一段 APNG（`状态插画/cat_loading_180.apng`，180×180、61 帧、42ms、1.9 MB），
要求 loading 图换成它，iOS 的下拉刷新也一起换。

资产由 `状态插画/build_loading_anim.py` 生成，Web 和 iOS 共用同一个文件：
`public/illustrations/loading-anim.png` 与 `ios/PawFolio/Resources/loading-anim.png`
（180×180、36 帧、42ms、280 KB）。脚本里写了为什么裁 [9,45)、为什么降灰度、
以及**不能用 `Image.quantize()` 的 RGBA 调色板**（Pillow 会写出坏 PLTE，Pillow 自己
读得回来但浏览器渲染成一团反色噪点 —— 这个坑踩过一次）。

- 它**不能进 `Assets.xcassets`**：asset catalog 会把 APNG 的动画块编译掉只留首帧。
  按普通资源文件打包，`PawAnimatedArt`（`DesignSystem/PawStateArt.swift`）用 ImageIO
  拆帧，`PawRunningCat` 负责播放；减少动态开启时退回静帧 `ArtLoading`。
- 搜索弹层的 `.loading` 态用 `PawRunningCat` 替掉了 `Image("ArtLoading")`。
- 下拉刷新自己实现了一个：`DesignSystem/PawPullToRefresh.swift` 的
  `PawRefreshableScrollView`，`PortfolioView` 和 `ExchangeRateView` 的 `.refreshable`
  都换成了它。`.refreshable` 那颗菊花没有任何公开接口能替换。触发时机只看位移、
  不接手势识别器（`.simultaneousGesture(DragGesture())` 会和持仓列表里的按钮抢事件），
  代价写在文件头。补了一个名为「刷新」的 accessibility action 顶替 `.refreshable`
  送给 VoiceOver 的那个。
- 视觉 QA：`SIMCTL_CHILD_PAWFOLIO_PULL_REFRESH=refreshing` 停在刷新态，
  给 0…1 的数则停在下拉到该进度的样子。

已验证（iPhone 17 / iOS 26.5，`xcrun simctl` 截图；模拟器 MCP 工具仍然不可用，见下）：
刷新态指示器逐帧在动、下拉 0.25/0.6/1.0 三档的淡入与缩放、深色下的表现、
以及换成 `PawRefreshableScrollView` 后持仓页布局与之前一致。146 个单元测试通过。

未验证的两处：搜索弹层的 loading 态（要点两下才到得了，模拟器手势工具不可用），
以及真机手指下拉的手感 —— 触发时机、回弹、和列表按钮是否互相干扰都只有推理没有实测。

已知小毛病：`SIMCTL_CHILD_PAWFOLIO_SCROLL_BOTTOM=1` 且内容不满一屏时，
`.defaultScrollAnchor(.bottom)` 会把内容整体压到底部，探针读到的正位移被当成「在下拉」，
指示器因此露出来。只影响这条 QA 路径，生产代码里 anchor 恒为 `.top`。

已装到真机（iPhone 17 Pro Max / `05FAD045-9A8E-536B-8766-CA830DA04D6C`，
Personal Team 签名，`xcrun devicectl device install app`）。

顺手确认了一件容易出事的事：`COMPRESS_PNG_FILES = YES`（Debug 和 Release 都是），
但 Debug 真机包和 Release 包里的 `loading-anim.png` 都还是 287,236 字节、36 帧原样，
Xcode 的 PNG 压缩没有动它。**以后改这个资源要重新核一遍**——如果哪天它被 pngcrush
碾掉动画块，界面不会报错，只会安静地退回一张静图。

`sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` 仍未执行，
Claude Code 的 iOS 模拟器 MCP 工具（attach / tap / swipe）因此一直用不了。

## iOS 26 底部玻璃条宽度限制（2026-08-31）

用户希望系统 Liquid Glass 底栏固定为左右各 24pt，不再按标签内容收拢。运行时量取确认：
402pt 宽的 iPhone 17 Pro 上，`UITabBar` 本身已经是 402pt 全宽，但系统私有的
`_UITabBarPlatterView` 是 `x = 64 / width = 274`，所以截图里可见外框左右各 64pt。

公开 API 实测均不能改变这层 platter：`UITabBar.itemPositioning = .fill`、
`UITabBarAppearance.stackedItemPositioning/Width/Spacing`、SwiftUI 自定义 `Tab` label 的
frame、`.tabViewStyle(.tabBarOnly)`，以及 `UITabBar.layoutMargins`。`TabView` 自身加 frame
只会缩页面内容，不能单独改系统底栏。精确 24pt 目前只有两条路：退回自管底栏（会失去
系统的拖拽选中胶囊、色散与回弹），或操作 `_UITabBarPlatterView` 私有实现（不稳定且不应
用于生产）。本轮所有试验性代码均已撤回，等待用户决定优先保留固定宽度还是系统交互。

## Nvwa design system colour migration（2026-09-01）

Web 与原生 SwiftUI 已从旧色板迁移到新的 **Nvwa** design system。iOS 的
`DesignSystem/PawTheme.swift` 已改名为 `DesignSystem/Nvwa.swift`，类型与调用点同步改为
`Nvwa` / `NvwaThemeController`；`public/styles.css` 的浅色、深色和兼容语义变量也全部由
18 个 `--nvwa-*` primitive 派生。Figma 色值保持原值，唯一的后续修订是用户把
Primary Green 与 Market Buy 一起改为 `#459811`。

本轮业务颜色决定：

- 上涨 / 盈利 = Market Buy `#459811`；下跌 / 亏损 = Market Sell `#C328CE`；
  持平 = Gray Secondary `#868685`。
- 交易时段用 Sentiment：Open = Positive `#2F5711`，Pre / After = Warning
  `#EDC843`，Night / Closed = Negative `#A8200D`。
- 标签底色统一为主题对应的 BG Light（浅色 `#ECEFEB`、深色 `#2A2C29`）。
- 删除与表单错误不是行情下跌，不复用 Market Sell，改用 Sentiment Negative。
- 用户明确要求本轮先忠实换色、暂时忽略对比度；因此没有擅自提亮 Warning、Positive、
  Negative 或标签前景。深色交易时段文字偏暗属于已知且已接受的视觉结果。

迁移覆盖 SwiftUI、自绘 Canvas、Web 运行时 fallback、`theme-color`、AccentColor、启动背景、
照片/头像边框与遮罩。国旗、照片、插画和品牌 Logo 的原始像素没有重染。iOS 26 系统
`TabView`、系统 alert / DatePicker 等系统内部绘制仍不可能逐像素绑定到 Nvwa。

验证结果：

- SwiftPM：152 tests passed，0 failures。
- iPhone 17 Pro / iOS 26.5 的 XCTest：163 tests passed，0 failures；结果包在
  `/tmp/pawfolio-derived/Logs/Test/Test-PawFolio-2026.09.01_01-13-42-+0800.xcresult`。
- 同一模拟器 `build-for-testing` 成功，并安装运行；Portfolio、Calculator、FX 的浅色 / 深色
  共六张截图在 `/tmp/pawfolio-nvwa-qa/`。账户弹层和猫图鉴也通过可见 UI 实际打开检查。
- Web：`node --check public/app.js`、`node --test tests/holding-sync.test.cjs`（5 passed）及
  `git diff --check` 均通过。

## Nvwa 独立组件包与图标边界（2026-09-02）

`Nvwa` 已从 PawFolio 的应用内 DesignSystem 抽为独立 Swift 6 package：`ios/Nvwa`，最低
iOS 17。PawFolio 通过 Xcode local package dependency 引用它；组件库不包含 Web、WebView
或 JavaScript。`ios/Nvwa/README.md` 与 `ios/Nvwa/FIGMA_COMPONENTS.md` 记录了 Figma 文件、
节点和公开组件清单。

本节取代上一节中“Web 与 iOS 共用同一套 Nvwa 色值”的旧描述：当前 iOS Nvwa 规范以最新
Figma 为准，Web 不自动随 iOS 更新。已确认的 iOS 色值包括 Primary Green 浅色
`#0051FE` / 深色 `#2D66F0`、Market Buy 浅色 `#459811` / 深色 `#65C02C`、
Market Sell 浅色 `#CE2632` / 深色
`#F0616D`；它们与当前 Web 的 Buy `#459811`、Sell `#C328CE` 有意分叉，不能按 Web 旧值
回退。

用户明确决定 Nvwa **不维护功能图标库**。Button、Tag、Checkbox、Input、ModalHeader、
Calendar 等只提供图标插槽，由宿主从 [Remix Icon](https://remixicon.com/) 注入。原先的
Checkbox 内置 SVG 已删除；DEBUG Catalog 当前由 PawFolio 注入 `IconCheck`、`IconSearch`、
`IconClose`、`IconMoneyDollarCircle`、Checkbox 两态、Calendar 与左右箭头。包内唯一图像
资源是 package-private 的 Tooltip pointer，它属于组件结构而不是功能图标。静态扫描确认
`ios/Nvwa` 中没有 `Image(systemName:)`、旧 Checkbox 资源或旧两参数 initializer。

Calendar 已补齐宿主契约：外部 `selection` 改变会同步可见日期，月份标题、月份缩写、星期
顺序与周末判定统一使用传入的 `Calendar` / `Locale`，不再按 `s` / `日` / `六` 猜周末；
Year / Decades 模式多出的 8pt 底部间距也已移除。纯 Foundation model/state 让这些行为可
稳定测试。Catalog 已扩展为 18 色 token、主要状态、输入、ModalHeader、Tooltip 与 Calendar
的调试入口；启动环境变量仍为 `PAWFOLIO_SHOW_NVWA_CATALOG=1`。

本轮验证：

- `xcrun swift test --disable-sandbox --package-path ios/Nvwa`：7 tests passed，0 failures，
  无 warning/error。
- 仓库根 `xcrun swift test --disable-sandbox --package-path ios`：152 tests passed，
  0 failures；仍有一条既有 warning，`AssetLogoStore.swift` 未在 SwiftPM target 中声明为
  resource 或 exclude。
- PawFolio generic iOS Simulator `build-for-testing`：exit 0，`TEST BUILD SUCCEEDED`。
- iPhone 17 Pro / iOS 26.5 XCTest：163 tests passed，0 failures；结果包为
  `/tmp/pawfolio-nvwa-final-derived/Logs/Test/Test-PawFolio-2026.09.02_00-41-37-+0800.xcresult`。
- iPhone 17 Pro / iOS 26.5 上已实际启动 Catalog，并检查浅色/深色及下半部分的输入、
  Remix 图标、ModalHeader、Tooltip 和 Calendar；截图位于 `/tmp/nvwa-component-catalog-light.png`、
  `/tmp/nvwa-catalog-lower-dark.png`。
- `git diff --check` 与 `ios/Nvwa` 额外尾随空白扫描均通过。注意 `ios/Nvwa/` 目前整体仍为
  未跟踪目录，普通 `git diff` 不会列出其内容。

## Nvwa Figma token rescan（2026-09-02）

已通过官方 Figma API 完整扫描 Nvwa 文件 `B7QSpRFNAt2tZ6S2JiG3Ij` 的四个页面、变量、
文字样式与组件绑定。当次扫描只有一个 Light / Dark 变量集合：25 个变量全部是颜色；另有
15 个 `NVWA` 文字样式。没有 spacing、radius、motion 等数值变量，也没有本地 Effect 或
Grid Styles。完整快照写在 `ios/Nvwa/FIGMA_TOKENS.md`。

与本地包相比，19 个既有颜色变量没有漂移；背景角色有更新：`BG/Main` 为
`#FFFFFF / #000000`，`BG/Vessel` 为 `#EFEFEF / #212121`，`BG/Input` 为
`#EFEFEF / #1D1D1D`，并新增 `BG/Card`（`#F6F6F6 / #121212`）。`NvwaColors` 现在公开
明确的 `backgroundMain`、`backgroundVessel`、`backgroundInput`、`backgroundCard`，旧背景
命名保留为兼容别名，避免 PawFolio 宿主断裂。

组件已按 Figma 实际绑定拆分背景角色：Input、灰 Tag 与 Slider 使用 `BG/Input`；Avatar、
Navigation、Segment、Hint、Section 与 Calendar active controls 使用 `BG/Vessel`。
Secondary Button 后续改绑独立的 `Button/Gray`，见 2026-09-03 记录。`BG/Card` 虽然已经发布，
但四个页面中没有任何组件实例绑定它，因此只暴露为 token 并加入 Catalog，没有猜测其组件
用途。README、`FIGMA_COMPONENTS.md` 和 token tests 已同步。

本轮验证：

- Nvwa SwiftPM：11 tests passed，0 failures。
- PawFolio SwiftPM：161 tests passed，0 failures；仍只有既有的 `AssetLogoStore.swift`
  resource / exclude warning。
- PawFolio generic iOS Simulator `build-for-testing`：exit 0，`TEST BUILD SUCCEEDED`。
- iPhone 17 Pro / iOS 26.5 XCTest：172 tests passed，0 failures；结果包为
  `/tmp/pawfolio-nvwa-token-derived/Logs/Test/Test-PawFolio-2026.09.02_12-15-30-+0800.xcresult`。
- Catalog 已在同一模拟器分别以浅色、深色启动，四个背景角色及相关组件目检通过；截图为
  `/tmp/nvwa-token-light.png` 与 `/tmp/nvwa-token-dark.png`。
- `git diff --check` 与 `ios/Nvwa` 额外尾随空白扫描均通过。

## Figma V1.1 stablecoin editor（2026-09-02）

稳定币编辑稿已 Ready，视觉源是 Pawfolio Design 节点 `72:9065`。现在纯生息持仓走独立的
SwiftUI 编辑弹层，不再出现旧的通用中文表单：`Edit <SYMBOL> Earn`、Add/Reduce Amount、
Amount、APR、Effective Date、Note、Est. Dividend、Save 与 Delete 均使用设计稿英文文案和
Nvwa 组件/token。375pt 最终截图为 `/tmp/pawfolio-stablecoin-375-final.png`，Figma 导出为
`/tmp/pawfolio-edit-stablecoin-v11.png`。

一次 Save 会通过 `StablecoinEditRequest` 原子提交金额、APR、生效日期与备注：

- 金额为 0 时只编辑 APR/备注；减仓仍不允许把本金减到 0。
- APR 不覆盖初始利率，而是追加 `RateAdjustment`。历史日期从该日结算起重算，之前仍按旧
  APR；未来日期到期后生效。
- 本金调整同样允许历史/未来日期，并从所选日期当天的 16:00 结算起生效。
- 编辑器没有单利/复利控件，也不会修改原持仓的 `interestMode`。
- `HoldingDraft.makeHolding` 保留已有 `rateAdjustments`，避免其他编辑路径丢失利率历史。
- 自定义日期壳下方的系统 `DatePicker` 已在 Simulator 实际点按，日历正常弹出。

最终验证：

- Nvwa SwiftPM：11 tests passed，0 failures。
- PawFolio SwiftPM：164 tests passed，0 failures。
- `PawFolio Stablecoin QA`（iPhone 13 mini / iOS 26.5）XCTest：175 tests passed，
  0 failures；结果包为
  `/tmp/pawfolio-stablecoin-final-derived/Logs/Test/Test-PawFolio-2026.09.02_13-42-48-+0800.xcresult`。
- 同一命名模拟器 `build-for-testing` 成功。
- 验收结束后已删除临时设备 `PawFolio Stablecoin QA`
  （`10F3FA5B-4807-40E5-8C40-AA02BAB80DDC`）；截图与 xcresult 仍保留在 `/tmp`。
- 用户明确冻结底部导航：本功能没有修改或按 Figma 对照任何底栏代码；后续也继续排除。

## Nvwa iOS component-system refresh（2026-09-02）

本轮按用户要求通过官方 Figma MCP 继续细化 `ios/Nvwa`。共享 URL 的 `2106:1212` 已失效，
读取改用 Components `2014:7053`、Input `2052:7149` 与 Navigation `2102:1075` 等有效节点。
`get_variable_defs` 会把组件内部隐藏 Boolean 路径的旧色一起摊平，因此 Key Feature 的最终
颜色以 `use_figma` 读取到的可见层 `boundVariables` 和 `get_screenshot` 结果为准。

- Key Feature actions 已从旧固定绿迁到 `Primary Green` / `ColorOnBlue`；新增
  `informational`（`BG/Vessel` / `Text/Primary`），并把 `interactive` 修为 Figma 的
  56 / 28 与 `BG/Vessel` / `Primary Green`。
- 48 / 24 status 已改为动态 token：Upload=`BG/Main` / `Text/Primary`，
  Close=`Sentiment Negative` / literal white，Tick=`Primary Green` / literal white，
  Warning=`Sentiment Warning` / `Text/Primary`。旧 `#163300` / `#9FE870` helper、公开别名与
  测试断言均已移除；`Alpha/Green 20%` 仍是当前正式变量，继续保留。
- Catalog 当时完整展示 25 个颜色 token 与八种 Key Feature 角色；后续新增 token 见下节。
  功能图标仍由 PawFolio 宿主注入 Remix Icon；新增的 `IconUpload` 与 `IconInfoI` 不进入
  Nvwa 包。
- 文档已修正两个 live-binding 细节：Section 的 Icon 属性只有 `No`；Toast surface 实际为
  `Text/Primary`，文字为 `BG/Main`。`FIGMA_V1_1_IMPLEMENTATION.md` 中旧绿与 Currency 暗色
  待决描述也已清理。
- Web 与底部导航均未在本轮修改。

最终验证：

- Nvwa SwiftPM：24 tests passed，0 failures。
- PawFolio SwiftPM：166 tests passed，0 failures。
- generic iOS Simulator `build-for-testing`：`TEST BUILD SUCCEEDED`。
- iPhone 17 Pro / iOS 26.5 XCTest：177 tests passed，0 failures；结果包为
  `/tmp/pawfolio-derived/Logs/Test/Test-PawFolio-2026.09.02_23-45-54-+0800.xcresult`。
- Catalog 已在一次性 iPhone 17 Pro / iOS 26.5 模拟器完成浅色与深色 G5 目检；Key Feature、
  Toast 与动态 token 均正确。截图为 `/tmp/nvwa-g5-light.png`、`/tmp/nvwa-g5-dark.png`、
  `/tmp/nvwa-g5-colors-light.png`；临时模拟器随后已删除。
- `git diff --check`、`ios/Nvwa` 尾随空白扫描、新增 Asset Catalog JSON 与 SVG XML 校验均通过。

## Nvwa Secondary Button 与 Tag 颜色更新（2026-09-03）

通过官方 Figma MCP 重新读取组件与变量后确认：

- Secondary Button set `2030:9627` 仍为 5 个 Size / Icon variants，没有 Color 或 Blue
  variant。它的背景已从通用 `BG/Input` 独立为 `NVWA/Button/Gray`：Light `#DEDEDD`、
  Dark `#3C3C3C`；前景继续使用 `Text/Primary`。画布上相邻的蓝色按钮属于 Primary Button
  set `2014:7979`。
- Tag set `2015:8035` 新增 `Color=Blue`，现在是 Gray / Green / Red / Blue 各自配 leading、
  trailing、none 三种图标组合，共 12 variants。Blue 节点为 `2136:1291`、`2136:1294`、
  `2136:1297`，使用 `Alpha/Blue 10%` 背景与 `Primary Green` 前景。
- Green Tag 的 live binding 是 `Alpha/Green 20%` 背景与 `Market Buy` 前景；本轮同时修正了
  本地此前误用 `Primary Green` 的前景映射。

`NvwaColors` 新增独立 `buttonGray` token，`NvwaButton.secondary` 改绑该角色；
`NvwaTagTone` 新增 `.blue`。Catalog、token/component tests、README、`FIGMA_TOKENS.md` 与
`FIGMA_COMPONENTS.md` 已同步，当前 Figma 颜色变量总数为 27。Web 与底部导航未修改。

最终验证：

- Nvwa SwiftPM：28 tests passed，0 failures。
- PawFolio SwiftPM：166 tests passed，0 failures。
- generic iOS Simulator `build-for-testing`：`TEST BUILD SUCCEEDED`。
- iPhone 17 Pro Max / iOS 26.5 XCTest：177 tests passed，0 failures；结果包为
  `/tmp/pawfolio-button-tag-test-derived/Logs/Test/Test-PawFolio-2026.09.03_00-40-12-+0800.xcresult`。
- iPhone 17 Pro / iOS 26.5 Catalog 已完成 Light / Dark 目检；截图为
  `/tmp/nvwa-button-tag-qa/catalog-light.png` 与 `/tmp/nvwa-button-tag-qa/catalog-dark.png`。
  验收后已恢复 Light，并保持 Catalog 打开在 Button / Tag 区域。
- `git diff --check`、`ios/Nvwa` 行尾空白与旧 Secondary / Tag 色彩映射扫描均通过。

## PawFolio 登录态与 surface 收口（2026-09-03）

本轮按 Pawfolio Design 的登录前后态与页面规范完成以下收口；参考节点为 `73:9277`、
`73:9388`、`90:11162`、`92:13272`、`55:6466`、`92:12826`、`90:11481`。

- Portfolio 顶栏已登录时继续显示账户 initials avatar；未登录时改为宿主 Remix 资源
  `IconShining`。点击未登录图标会由 `PortfolioView` 直接触发 `RootTabView` 的全屏
  `LoginView`，旧中间登录 sheet 已移除。
- 登录页继续使用原生 Google OAuth 流程，授权成功后自动关闭并回到产品页；Light / Dark
  两种外观均已在 Simulator 验收。
- Account 已登录态也完成 Light / Dark 视觉验收：右上主题按钮可正常切换，正文不再保留旧
  Theme 分段。
- PawFolio 自定义 bottom sheet 的根 surface、`presentationBackground` 与
  `NvwaModalHeader` 均统一使用 `Nvwa.backgroundDialogue`：Light `#FFFFFF`、Dark
  `#262626`。全屏页面仍使用 `backgroundMain`；Cat Information 作为 sheet 使用
  Dialogue。系统 `alert` / `confirmationDialog` 与底部导航没有改动。
- PawFolio 内所有 `NvwaHint` 默认统一为 Level 1；Stablecoin 的估算说明也已换为标准
  `NvwaHint`，不再保留局部自制提示样式。
- Daily Yield 合并卡背景改为 `Nvwa.backgroundCard`，不再借用其他背景角色。

最终验证：

- Nvwa SwiftPM：28 tests passed，0 failures。
- PawFolio SwiftPM：166 tests passed，0 failures。
- `AccountViewModelTests`：14 tests passed，0 failures。
- generic iOS Simulator `build-for-testing`：`TEST BUILD SUCCEEDED`。
- iPhone 17 Pro / iOS 26.5 XCTest：180 tests passed，0 failures；结果包为
  `/tmp/pawfolio-login-ui-derived/Logs/Test/Test-PawFolio-2026.09.03_01-17-44-+0800.xcresult`。
- 最终截图为 `/tmp/pawfolio-login-light-final.png`、`/tmp/pawfolio-login-dark-final.png`、
  `/tmp/pawfolio-home-signed-out-light.png`、`/tmp/pawfolio-home-signed-in-light.png`、
  `/tmp/pawfolio-account-signed-in-light.png`、`/tmp/pawfolio-account-signed-in-dark.png`、
  `/tmp/pawfolio-daily-card-light.png`、`/tmp/pawfolio-dialogue-dark.png`。

## Nvwa Toast 自适应宽度（2026-09-03）

官方 Figma MCP 复核了 Nvwa Toast set `2070:814` 与 variant `2070:815`：最新源组件为
Hug / Hug、水平 8pt / 垂直 6pt padding、10pt 圆角和 12/20 Inter。Figma 尚未定义
max-width 或长文案换行；Pawfolio 远端 master 仍显示旧的固定 190pt，而画布实例已经是 Hug，
属于未发布 / 未同步差异。本轮按用户明确规则补足运行时约束：可见 Toast 随短文案收拢，
总宽最多 300pt；超过 284pt 的正文可用宽度后自动换行，左右 padding 始终各 8pt。

- `NvwaToast` 用 `ViewThatFits` 在单行 Hug 与 284pt 多行正文之间切换，移除固定 190pt 和
  `lineLimit(1)` 截断；高度随换行自然增长。
- Catalog 的 Messages 区新增长文案样例；组件规格测试覆盖 8 / 6 padding、20pt 最小正文高、
  300pt 最大总宽、284pt 最大正文宽与 10pt 圆角；`FIGMA_COMPONENTS.md` 已记录这条规则。
- Light / Dark 均在 iPhone 17 Pro / iOS 26.5 实际渲染验收。像素检查确认长 Toast 为
  900px，即 @3x 下 300pt；短 Toast 可见 surface 小于 300pt，两种主题均无截断。

最终验证：

- Nvwa SwiftPM：29 tests passed，0 failures。
- PawFolio SwiftPM：166 tests passed，0 failures，无 warning / error。
- generic iOS Simulator `build-for-testing`：`TEST BUILD SUCCEEDED`。
- iPhone 17 Pro / iOS 26.5 XCTest：180 tests passed，0 failures / skipped；结果包为
  `/tmp/pawfolio-named-xctest-aDjDXa/PawFolioTests.xcresult`。编译仍有一条与本轮无关的既有
  `HoldingDetailView.swift:884` result-builder warning。
- 浅色 / 深色截图为 `/tmp/pawfolio-toast-light.png` 与
  `/tmp/pawfolio-toast-dark-final.png`。

## Architecture quality audit and Supabase REST consolidation（2026-09-03）

本轮先按入口、状态、Domain、Repository/Service、持久化与同步链路完成架构审计，结果记录在
`ios/Docs/QUALITY_AUDIT.md`。审计确认 Domain 与数据边界总体清晰，当前主要质量风险是
Portfolio 刷新任务可能交错、SwiftUI 渲染期间重复排序/估值、走势图按持仓×采样点×调整记录
重复回放，以及三个 Portfolio 视图文件过大。为避免无基准时改写金融算法，这些风险只记录了
分阶段重构策略，本轮没有改动金融规则、UI、底部导航或持久化格式。

已完成一项低风险重构：`SupabaseCloudHoldingRepository` 与
`SupabaseCloudProfileRepository` 原先各自复制的 PostgREST URL/Header 构造、token 获取、
401 后强制刷新并重试一次、状态码检查与错误 payload 解析，现统一收口到文件内私有的
`SupabaseRESTClient`。两个 repository 的公开 initializer、协议、请求路径、query、JSON payload
与重试次数保持不变。新增回归测试确认第二次 401 不会继续重试，并会返回最终 `details`。

最终验证：

- SwiftPM：167 tests passed，0 failures。
- generic iOS Simulator `build-for-testing`：`TEST BUILD SUCCEEDED`。
- iPhone 17 Pro / iOS 26.5 XCTest：181 tests passed，0 failures / skipped；结果包为
  `/tmp/pawfolio-derived/Logs/Test/Test-PawFolio-2026.09.03_10-02-12-+0800.xcresult`。

## PawFolio v1.1.0 version baseline（2026-09-03）

PawFolio 当前产品版本正式整理为 **v1.1.0 (build 1)**。App target 的 Debug / Release
`MARKETING_VERSION` 均已从 `0.1.0` 更新为 `1.1.0`；`Info.plist` 继续通过
`CFBundleShortVersionString = $(MARKETING_VERSION)` 与
`CFBundleVersion = $(CURRENT_PROJECT_VERSION)` 读取 Xcode 配置。没有修改持仓 schema、缓存版本、
资源 catalog 版本或 Web cache-buster。

新增 `ios/Docs/VERSIONING.md` 作为后续版本整理规则。未来版本号以用户明确提供的值为准，不从
提交内容自动推断；build number 独立管理。Git tag 及 App Store 上传仍需用户明确要求，本轮均未执行。

最终验证：

- Release build settings 解析为 `MARKETING_VERSION = 1.1.0`、
  `CURRENT_PROJECT_VERSION = 1`、Bundle ID `com.jiujiucat.pawfolio`。
- 构建产物 `Info.plist` 为 `CFBundleShortVersionString = 1.1.0`、`CFBundleVersion = 1`。
- SwiftPM：167 tests passed，0 failures。
- generic iOS Simulator `build-for-testing` 成功；仅保留既有的
  `HoldingDetailView.swift:888` result-builder warning。
- iPhone 17 Pro / iOS 26.5 XCTest：181 tests passed，0 failures / skipped；结果包为
  `/tmp/pawfolio-version-derived/Logs/Test/Test-PawFolio-2026.09.03_10-42-20-+0800.xcresult`。

## v1.2.0：三页统一顶栏与 Currency 改造（2026-09-03）

产品版本从 1.1.0 提到 **v1.2.0 (build 1)**（用户指定，Debug/Release 两处
`MARKETING_VERSION` 均已更新）。

**顶栏统一。** 新增 `PawFolio/DesignSystem/PawTopNavigation.swift`，把
`NvwaNavigationBar` 的登录 / 访客两个分支收在一处，PawFolio、Calculate、Currency
三页共用。左侧账号入口三页一致；右侧主操作各页不同：PawFolio 与 Calculate 都是
「新增持仓」，Currency 是「添加货币」。Calculate 的「+」并不自己持有编辑器——它把
`selection` 切到 PawFolio 并置起 `newPositionRequest`，由 `PortfolioView` 接住后弹
编辑器并自行复位，避免第二个 `PortfolioViewModel` 实例和主页面数据脱节。

**币种表放开到 70 种法币。** `CurrencyCode` 从四个 case 的枚举改成包一层 `String`
的值类型（附 `CodingKeyRepresentable`，缓存仍编成 JSON 对象），支持的币种改由新增的
`Domain/CurrencyCatalog.swift` 这张静态表决定。**只收录有国旗图的法币**（用户要求），
国旗全部取自 Nvwa 设计库 Flags section `2013:5416`，欧元区各国合并成 `EUR` 一条配欧盟旗。
`LiveExchangeRateClient` 不再因为单个冷门币缺价就整页报错，改成跳过那一条。汇率缓存
key 升到 `...snapshot.v2`；用户选的币种列表存在 `pawfolio.exchange-rate.currencies.v1`。

**Figma 的 SVG 导出有两个坑，都已处理。** 一是 `download_assets` 对 symbol 节点是
「就地渲染」，Section 的灰底和白框会一起进来，脚本按「`<g id="Flags">` 里第一个子 `<g>`
才是国旗本体」剥掉。二是 CoreSVG 只吃得下两层嵌套 mask，AU / JM / NZ / OM 是三层，
整面旗渲染成空白圆；这四面里的 `mask1` 是个 r=32 的圆，和最外层 `clip0_0_1`（rx=32）
完全等价，去掉即可。**以后再从这个 Flags section 拉图，这两步都要重做一遍。**

**Currency 页交互。** 基准行的数字是 `Nvwa.primaryGreen`（蓝），其余行是黑；点进另一
行时保留现有数字并改成 `Nvwa.textSecondary` 灰色，表示正在等待新输入，**其余行原样不动**。
第一次按退格会整段清零但仍保持等待态；第一次输入数字会覆盖旧值、把该行切成蓝色基准，
此时才重算其他行。输入期间禁用右滑删除。货币仍支持右滑删除和上下拖动排序，但排序过程中
不再边拖边改数组：只让被拖行跟手、相邻行预览让位，松手后才一次性提交顺序。

**下拉刷新与拖拽怎么分（用户 2026-09-03 两次定稿，以后一条为准）。** 排序要
**按住 300ms 且手指不动**才拿得起来：`LongPressGesture(minimumDuration: 0.3,
maximumDistance: 0)` 再 `.sequenced(before:)` 一个 `DragGesture`。`maximumDistance: 0`
就是那句「没有位移」——这 300ms 里只要动过，长按直接作废，这一次手势自始至终只是滚动，
跑步猫的下拉刷新照常拉得出来。长按成立之后才用 `scrollDisabled(isReordering)` 把滚动
停掉，所以两套手势**都用 `simultaneousGesture`**：用 `highPriorityGesture` 的话整段
列表都滚不动（那是第一版的做法，已推翻）。右滑删除是独立的一段 `DragGesture`，起手
方向判成纵向的那一次整段不接，留给滚动。

**行版式照设计稿还原**，设计文件换了一个：**PawFolio 的产品稿在
`ThlaCizGXDV4puXbtg8Fk0`（Pawfolio Design），汇率页是 `110:3141`**，不在 Nvwa 库
（`B7QSpRFNAt2tZ6S2JiG3Ij`）里——HANDOFF 早先记的 `63:7007` 在 Nvwa 库里已经查无此节点。

一行的构成：左边**只有国旗**（42，1px line 描边），右边是右对齐的两行——第一行是
金额加一个空格再加**灰色的币种代码**（`Nvwa.textSecondary` / #868685），两者同为
30/Semibold/tracking -0.75/行高 34；第二行是 12/Regular 的副标题，间距 4。币种代码
**跟在金额后面**，不在左侧（这是这一轮改的重点）。实现上让输入框吃掉剩余宽度并右对齐、
代码贴在它右边，各行代码的右缘就自然对齐了。行内容上下各留 24，行高固定
`max(34 + 4 + 20, 42) + 24 * 2 = 106`（拖动排序按整数格数换位，行高必须是定值）。

副标题去掉了 `1 CNY = ` 前缀，改成「单位汇率 + 货币全名」，例如 `0.1484 US Dollar`；
基准行仍然只显示货币全名。列表末尾补回了 `Updated HH:mm`（`110:3679`）：10/Regular、
居中、上下 12，颜色是 `Nvwa.line` —— 比副标题还淡，设计上就是这么定的。

**「添加货币」弹层不跟这一套**（用户明确要求保持 32 国旗 / 64 行高）——七十多条的
列表行矮一点一屏能多看几条。弹层的行只显示货币全名，**不显示国家名**；右侧字母索引的
热区是 20×20。

**右上角的「+」两页不同色，是故意的（用户 2026-09-03 确认）。** Currency 页用中性灰的
`Add-Interactive`（`bg/vessel` 底、`grayPrimary` 图标），PawFolio 与 Calculate 用蓝色
primary——**为的是把「添加货币」和「新增持仓」两个功能区分开**，不是漏改，别再「顺手
统一」。为此给 `NvwaNavigationBar` 的 profile / signedOut 两档加了 `addTone`
（`NvwaNavigationBarActionTone.primary / .neutral`，默认 primary），没有在业务页里就地
重描样式。

**新规则：设计稿是像素级的验收标准。** 已写进 `AGENTS.md` 的 Design direction。要点：
产品稿在 `ThlaCizGXDV4puXbtg8Fk0`、组件库在 `B7QSpRFNAt2tZ6S2JiG3Ij`，动手前先
`get_design_context` 拉节点按实际数值写，不许照截图目测；写完截图逐项比对；和设计稿
不一致的地方一律先问，别自作主张统一。

**字母索引只有当前分组是蓝的**，其余 Text Secondary。当前分组靠 `SectionOffsetKey`
这个 PreferenceKey 量出来：表头是 pinned 的，贴在顶上的那个 `minY` 停在 0，划过去的是
负数，取「`minY` ≤ 0 里最靠下的那个」。

**QA 钩子**（模拟器上点不了，沿用既有做法）：`PAWFOLIO_QA_CURRENCY_PICKER=1` 直接打开
添加货币弹层，`PAWFOLIO_QA_CURRENCY_QUERY=<关键词>` 预填搜索词，
`PAWFOLIO_QA_CURRENCY_SWIPE=<代码>` 停在右滑露出删除的样子。

验证：

- SwiftPM：174 tests passed，0 failures。
- iPhone 17 Pro / iOS 26.5 `xcodebuild test`：**TEST SUCCEEDED**。
- 截图核对：Currency 默认态（与 `110:3141` 逐项对过）、右滑删除态、添加货币弹层
  （含搜索 `dollar`、字母索引当前分组高亮）、Calculate 顶栏。
- 70 面国旗先在浏览器里逐面核过一遍造型，再在设备上确认 AUD / JMD / NZD / NAD 等
  高风险项渲染正常；`CurrencyCatalog` 的 `flagAssetName` 与 `Assets.xcassets` 一一对上，
  只多出一张兜底的 `FlagUnknown`。

尚未做：Currency 页没有「更新时间」这行说明文字（V1.1 的 `pageHeader` 本来就是没被渲染
的死代码，这次一并删掉了）；拖动排序时没有做靠近上下边缘的自动滚动。`maximumDistance: 0`
是照字面实现的，真机上手指微抖会不会拿不起来还没有在实机验证过——真出问题就把它放宽到
2~4pt。

## NvwaModalHeader 去掉 close 语义（2026-09-03）

**产品里所有弹层都不放 close 图标**（用户 2026-09-03 的决定）：设计稿
`2052:7350` 里那个 ✕ 只是**占位图形**，不是要求每个弹层都带关闭按钮。弹层一律靠
抓手下滑关闭，抓手由 `NvwaModalHeader` 自己画（40×4）。

组件相应改了 API：原来的 `variant: .trailingClose(...) / .leadingDestructive(...)`
把「关闭」「删除」这些语义焊死在组件里，现在换成两个通用插槽——

```swift
NvwaModalHeader("Title", leading: NvwaModalHeaderAction?, trailing: NvwaModalHeaderAction?)
```

`NvwaModalHeaderAction` 带 `icon` / `accessibilityLabel` / `tone`
（`.normal` / `.destructive`）/ `action`，对上设计稿的 `icon: No | Left | Right`
三档。几何一点没动（66 / 抓手区 16 / 标题行 50 / 左右 15 / 图标 16 / 热区 44），
`NvwaComponentSpecTests` 里那几条尺寸断言照旧通过。

调用点：`CurrencyPickerView` 的 ✕ 删掉，只剩标题；`HoldingEditorView` 的编辑态
去掉右上角 ✕，**左上角的删除保留**并改用 `.destructive` tone。别再往任何弹层上加 ✕。

验证：Nvwa 包 29 tests、SwiftPM 174 tests、iPhone 17 Pro / iOS 26.5 `xcodebuild test`
全部通过；添加货币弹层截图确认标题居中、抓手在、无 ✕。

## 代码质量审计与五阶段重构（2026-09-03）

一次只读审计 + 按优先级实施的五个切片。**没有改任何观感、文案、持久化格式或外部
接口形状**；唯一动到持久化的是走势图区间的 key 改名，带迁移。

**阶段 1｜金额格式化与输入解析收口。** 新增 `Domain/AmountFormatting.swift`：
`MoneyFormat.decimal/dollars/usd/percent` 和 `AmountInput.parse/text`。此前
`$ + 千分位 + 两位小数` 这条规则在 6 个文件里写了 **14 遍**，输入解析写了 **6 遍**
且语义已经分叉。合并前先写了 `AmountFormattingTests` 把当时的行为钉住（断言写成
「结构」而不是具体字符串，因为 `.formatted` 跟随 `Locale.current`）。

**正负号故意没有合并**：`PortfolioView.signedCurrency` 负数显示 `-`，而图表卡片里
那个同名方法负数**不显示符号**。两者行为本来就不同，合并会改观感，所以只收口数字
部分，符号留在各自调用点。**这一条差异还在，需要你确认是不是 bug。**

**阶段 2｜拖动排序的换位运算搬进 Domain。** `Domain/ReorderDrag.swift` +
`ReorderDragTests`（12 条，含「拖到头再拖回来」这个最容易错位的路径）。原来它是
`ExchangeRateView` 里的一段纯整数运算，算错的表现是列表顺序错乱并写坏用户存的排序。

**阶段 3｜行情刷新与汇率刷新加合流器。** `PortfolioViewModel.refreshQuotes()` 和
`ExchangeRateViewModel.refresh()` 现在把并发调用**并进同一个在途任务**。原来两次
并发刷新会互相踩：`isRefreshingQuotes` 的 `defer` 由先结束的那个复位（转圈提前消失），
后写入的结果无条件覆盖先写入的（价格回退）。`upsert` 里那个 fire-and-forget
`Task { }` 改为受持有。**不做取消**——任务是共享的，取消它会连带取消另一个调用者
等的那份。`testConcurrentRefreshesShareOneRequest` 数接口调用次数，三个并发刷新只
打一次。

**阶段 4｜本地偏好下沉到 Data 边界。** 新增 `Data/PreferencesStore.swift`
（`ExchangeRatePreferencesStoring` / `PortfolioPreferencesStoring` +
`UserDefaultsPreferencesStore`）。`Features/` 里现在**没有任何 `UserDefaults` 直接
调用**。顺带把漏了前缀的 `"portfolio.historyRange"` 改成
`"pawfolio.portfolio.history-range"`，**带迁移**：读到旧 key 就搬到新 key 再清掉，
`PreferencesStoreTests` 里有一条专测这个，另有一条测「新 key 有值时不被旧 key 顶回去」。
`PortfolioViewModel` 从此可以注入沙盒（它此前因为硬编码 `.standard` 而零测试）。

**阶段 5｜持仓编辑器的校验规则搬进 Domain。** `Domain/HoldingDraftValidation.swift`
+ 18 条测试。管的是「减仓会不会把本金减成负数」「年化 300% 让不让存」这类真会算错钱
的判断，此前全埋在 `saveStablecoin` 里且零覆盖。**判定与文案分离**：同一条规则在
输入框下面写「currently N」、在弹窗里写「up to N」，文案留在视图层。测试里专门钉住了
**报错的先后顺序**（金额 → 减仓 → 年化 → 备注），因为用户一次只看到一条消息。

一个被实测推翻的猜测记在这里免得后人再走一遍：`HoldingValuation.beijingDateString`
每次调用新建 `Calendar` + `TimeZone`，看着像热路径浪费，**实测只差 1.1×**
（2.9 µs vs 2.6 µs），开销在 `dateComponents` + `String(format:)`，不在分配。没有改。
`principalSegments` 也确认是按 boundary 迭代而非按天，是 O(调整笔数)。

验证：SwiftPM `ios` **216 passed**（审计前 174）、Nvwa **29 passed**、
iPhone 17 Pro / iOS 26.5 `xcodebuild test` **TEST SUCCEEDED**；
`build-for-testing` 只剩既有的 `HoldingDetailView.swift:888` 警告，没有新增。

### 收尾（同日，把上面留的尾巴逐条做完）

**走势图卡片的负号是真 bug，已修。** 那份 `signedCurrency` 写的是
`dollars(abs(value))` 再只给正数补 `+`，于是 `-5` 渲染成 `$5`——涨跌看不出来。用户
确认负号必须显示，两处遂并成 `MoneyFormat.signedDollars` / `signedDecimal`，测试钉死
「负数带 `-`、正数带 `+`、0 不带」。**这是本轮唯一一处观感变化，其余全部行为保持。**

**`PortfolioViewModel` 补上 12 条测试**（`PortfolioViewModelTests.swift`，Xcode-only）。
覆盖：仓库报错落到 `errorMessage` 而不是崩、总值/总盈亏/百分比的组合、
**`e1603be` 那条「价格忽有忽无」的回归守卫**（本轮取价失败的标的保留上一轮的价）、
报价按当前持仓裁剪、并发刷新只打一次接口、`upsert` 落盘并盖 `schemaVersion`、
区间偏好的读回写透、`openHoldings` 排除已删除。

**`try? saveCache` 换成计数 + 日志。** `CachedMarketQuoteRepository` 新增
`cacheWriteFailureCount` 和 `os.Logger`。写盘失败仍然不影响本次刷新（报价已经在手里），
但不再无声无息——磁盘满或数据保护未解锁会让缓存永久写不进去，表现是每次都要重新联网、
离线一片空白，原来完全查不到。测试把缓存目录的位置先占成一个**文件**逼 `createDirectory`
失败，断言刷新照常返回且失败被计数（原来的 `try?` 根本没有可断言的东西）。

**`HoldingDraft` 搬进 Domain 并补 17 条测试。** `HoldingEditorView` 从 1449 行降到
**1181 行**；搬走的 268 行没有一句 SwiftUI，却因为是视图文件里的 `private` 类型而零
覆盖，而 `makeHolding` 管的是八条「这笔持仓合不合法」的判断。测试里专门钉住了两条踩过
坑的规则：**0% 年化必须合法**（减仓换来的 USDT 就是 0 年化，曾经要求 `> 0` 导致那种
持仓一打开就存不回去），以及**编辑态忽略草稿里的数量、以持仓现值为准**（草稿是打开弹层
那一刻的快照，写回会抹掉期间的加减仓）。

**审计里的一条判断被推翻，记下来免得后人再改：`refreshQuotes` 那两次
`rebuildPortfolioHistory()` 不是浪费。** 它们分处网络 `await` 的两侧——先用本地缓存把
图画出来，等新数据回来再重画一次，是有意的渐进渲染。合并会让图在整个请求期间空着。
`refreshOneYearHistories` 同理。**不要「优化」掉。**

验证（收尾后）：SwiftPM `ios` **236 passed**、Nvwa **29 passed**、
iPhone 17 Pro / iOS 26.5 `xcodebuild test` **271 个用例通过、0 失败**；
`build-for-testing` 仍只有既有的 `HoldingDetailView.swift:888` 警告。

留给下一轮：`HoldingEditorView` 还有 1181 行（版式没动，只搬走了模型和校验）；
`PortfolioView` 1300 行、`HoldingDetailView` 1184 行同样只做了格式化收口，没有拆。

## Currency 输入与拖拽交互收尾（2026-09-03）

- `ExchangeRateViewModel` 新增独立的 waiting 状态：切换到非基准币种时保留原数字并显示
  Secondary 灰色；第一次退格整段清空，第一次输入字符覆盖旧值并切换成蓝色基准。额外保留
  原生键盘文本基线，避免 SwiftUI `TextField` 的旧内部字符串在 Binding 归一化后重新写回。
- `TextField` 的文字改由模型覆盖层确定性渲染，原控件只保留原生光标和 decimalPad；输入框
  自身不接触摸，由整行短按聚焦，所以长按排序不会先激活输入或弹出键盘。
- 输入聚焦或排序期间，右滑删除手势不参与命中。
- 排序从“拖动中持续修改数组”改为“固定原数组 + 邻行位移预览 + 松手一次提交”。
  `ReorderDrag.projectedDestination` 是纯 Swift，并补了边界、跨多行和回拖测试。
- 模拟器实测：USD 灰色 `0` 的等待态输入 `5` 后立即显示蓝色 `5`，继续输入得到 `56`，
  CNY/MYR/THB 同步重算；聚焦状态横向拖动没有露出删除按钮。自动化鼠标拖拽无法注入
  SwiftUI 所需的 300ms 静止长按，因此长按本身由手势结构和纯逻辑测试覆盖，真机仍应做一次
  最终手感确认。
- 设计基线仍为产品稿 `ThlaCizGXDV4puXbtg8Fk0` / `110:3141`；本轮没有新增资产或改动
  42pt 国旗几何，继续使用现有 Nvwa `primaryGreen`、`textSecondary`、`grayPrimary`。

最终验证：

- SwiftPM：237 tests passed，0 failures。
- generic iOS Simulator `build-for-testing`：`** TEST BUILD SUCCEEDED **`。
- iPhone 17 Pro / iOS 26.4.1（`C46D7DBB-AB14-453E-9BF1-0A80F9357E94`）：
  275 XCTest cases passed，0 failures / skipped；结果包为
  `/tmp/pawfolio-derived/Logs/Test/Test-PawFolio-2026.09.03_16-57-23-+0800.xcresult`。

## Currency / Calculator 禁止下拉与边缘回弹（2026-09-03）

- Currency 移除 `PawRefreshableScrollView` / `.refreshable`，不再响应下拉刷新，也不会显示
  刷新猫；超出屏幕的货币列表仍可正常纵向滚动。
- Currency 与 Calculator 的滚动内容增加局部 `pawScrollBounceDisabled()`：通过嵌入式 UIKit
  探针只关闭所属 `UIScrollView` 的 `bounces` 和 `alwaysBounceVertical`，不会影响 Portfolio
  等其他页面，也没有改动页面布局、颜色、字体、几何或资产。
- 设计核对仍使用 Pawfolio Design：Currency `110:3141`、Calculator `46:1483`；本轮只改
  滚动交互，原有设计几何保持不变，G5 PASS。

验证与交付：

- SwiftPM：237 tests passed，0 failures。
- generic iOS Simulator `build-for-testing`：通过。
- iPhone 17 Pro / iOS 26.4.1：275 XCTest cases passed，0 failures / skipped；结果包为
  `/tmp/pawfolio-derived/Logs/Test/Test-PawFolio-2026.09.03_18-23-42-+0800.xcresult`。
- signed physical-device build：`BUILD SUCCEEDED`。
- 已通过 `devicectl` 覆盖安装并成功启动到真机“龙”（iPhone 17 Pro Max / iOS 26.5.2，
  bundle id `com.jiujiucat.pawfolio`）；安装更新保留应用数据。
- `git diff --check`：通过。

## 底部弹层高度统一与防回归（2026-09-03）

- 根因是多个业务弹层直接写死 `.presentationDetents([.large])`，另一些依赖系统默认高度，
  绕过了原先的内容自适应逻辑，所以同一种弹窗在不同入口会突然变成近全屏。
- `DesignSystem/PawControls.swift` 新增唯一高度策略 `PawSheetSizing` 与
  `.pawAdaptiveSheetHeight(...)`：短内容按当前内容收住，长内容最多到视口减 92pt，之后只让
  弹层内部的 `ScrollView` 滚动。`PawSheet` 首帧未量到内容时从最小高度起步，不再先全屏再缩回。
- Currency Picker、Asset Search、Add/Edit Position、Stablecoin Editor、Position Confirmation、
  PnL Details、记录列表和 Cat Information 全部接入统一策略；业务 `Features/` 下已无 `.large`
  detent。Account、Login、My Cats 是带导航栏的完整页面，继续使用设计明确要求的
  `fullScreenCover`，不属于底部弹窗。
- Currency Picker 的理想高度随筛选结果数量实时变化：完整列表到上限后内部滚动，`yen` 单结果
  会明显缩矮。模拟器截图：`/tmp/pawfolio-adaptive-currency-sheet.png` 与
  `/tmp/pawfolio-adaptive-currency-sheet-short.png`。
- `AGENTS.md` 新增持久规则；`SheetPresentationPolicyTests` 扫描全部 Feature Swift 源码，任何
  人重新写入 `.presentationDetents([.large])` 都会让测试失败。

验证：

- SwiftPM：238 tests passed，0 failures。
- generic iOS Simulator `build-for-testing`：`TEST BUILD SUCCEEDED`。
- iPhone 17 Pro / iOS 26.4.1：276 XCTest cases passed，0 failures / skipped；结果包为
  `/tmp/pawfolio-derived/Logs/Test/Test-PawFolio-2026.09.03_19-56-25-+0800.xcresult`。
- signed physical-device build：`BUILD SUCCEEDED`；已覆盖安装并启动到真机“龙”。
- `plutil -lint ios/PawFolio.xcodeproj/project.pbxproj` 与 `git diff --check`：通过。

## NvwaModalHeader 底色改用 bg/dialogue（2026-09-03）

设计把 `2052:7350` 的底色从 `nvwa/bg/main` 换成了 `nvwa/bg/dialogue`（根节点和
Sheet Header 两处），组件跟着改。token 的**数值**本来就是对的
（`bg/dialogue` = `#FFFFFF` / `#262626`），错的只是组件引用了哪一枚。

**这是个在浅色下完全看不出来的 bug。** `bg/main` 与 `bg/dialogue` 在浅色下都是
`#FFFFFF`，深色下才分叉：`bg/main` 是纯黑 `#000000`，而全 App 的弹层都用
`.presentationBackground(Nvwa.backgroundDialogue)` = `#262626`——于是深色模式下每个
弹层顶部都压着一条黑带。截图取像素核对过：

| | 抓手行 | 标题行 | 列表区 |
|---|---|---|---|
| 改前（深色） | `#000000` | `#000000` | `#262626` |
| 改后（深色） | `#262626` | `#262626` | `#262626` |
| 改后（浅色） | `#FFFFFF` | `#FFFFFF` | `#FFFFFF` |

`NvwaTokenTests` 加了一条
`testDialogueSurfaceOnlyDivergesFromTheMainBackgroundInDarkMode`，断言两枚 token
**浅色相同、深色不同**——把「这俩看着一样，随便用一个」这条会踩的坑钉死。组件注释里
也写了不要换回 `bg/main`。

一个教训记下来：验证颜色时**先确认取样点真的落在目标控件上**。第一次取像素时我按
浅色截图的坐标去取，结果 iOS 26 的弹层在深色下浮动留边、顶边下移了 340px，取到的
是弹层背后的页面，两次读数一模一样，差点得出「改了没生效」的错误结论。稳妥做法是
先从上往下扫出弹层顶边，再按相对偏移取样。

验证：Nvwa **30 passed**、SwiftPM `ios` **238 passed**、
iPhone 17 Pro / iOS 26.5 `xcodebuild test` **TEST SUCCEEDED**；深浅两色各截图核对。

## V1.2.2：个人中心/登录/语言切换/持仓页/详情页批注全量落地（2026-09-03）

对着 `ThlaCizGXDV4puXbtg8Fk0`（Pawfolio Design）的 V1.2.2 画布，逐屏 `get_design_context`
拿注释，逐条落地。产品版本改成 **v1.2.2 (build 1)**。这轮开工前先问了用户四个会改变
实现方式的问题（语言切换的真实范围、登录后要不要真的等云端同步、主题图标显示当前还是
目标模式、总资产大数字 22 还是 26px），全部有答案才动手，答案见下文各节。

**`NvwaModalHeader` 背景色核查（`2052:7350`）：确认已经是对的，没有改代码。**
两次设计稿之间唯一的结构性差异是 sheet 背景 token 从 `bg/main` 改成 `bg/dialogue`，
而 `Nvwa.backgroundDialogue` 早就是现在的实现（这条改动发生在更早的一轮，不是这次)。
`get_variable_defs` 核对过三个 token 的实际取值都对得上，不是照 CSS 兜底色猜的。

### Nvwa 组件库

- **`NvwaTag` 新增 `iconRotationDegrees`**（默认 0，向后兼容）。合并持仓卡的展开箭头
  从「两张图之间切换」改成「一张图旋转 90°」——SwiftUI 能对角度插值，两张不同的贴图
  之间没有交叉淡入淡出，原来的切图看着会跳一下（`120:2552` 批注：想要平滑动画）。
- **`NvwaNavigationBar` 的 `.secondary` 变体新增第二个尾随图标槽**
  （`secondTrailingIcon` / `secondTrailingAccessibilityLabel` / `onSecondTrailing`，
  全部默认 nil，向后兼容）。两个尾随图标之间的间距是 15pt，是 `97:15277` 单独给的
  一个间距，不能借用外层 HStack 的 0 间距凑。**第二个图标专门给国旗用**，走一个新的
  `flagButton`——不能复用 `iconButton` 那套单色模板渲染，模板化的国旗只剩一个纯色轮廓，
  分不出是哪国旗了。

### 新增：语言切换（V1.2.2 明确要求「先做 UI 骨架，不接翻译」）

- `PawChrome.swift` 新增 `AppLanguage`（`.chinese` / `.english`，各自带标题和
  `FlagCN`/`FlagGB` 国旗资源名——国旗和货币页共用同一批资源）和
  `LanguagePreferenceStore`（`ObservableObject`，选中态存 `pawfolio.language`，
  **默认英文**：界面文案本来就还是英文，默认指向中文会显得选错了却没生效）。
- 新增 `Features/Account/LanguagePickerSheet.swift`：`NvwaModalHeader("Language")` +
  两行（国旗 24pt 圆 + 标题 + 选中打勾），点一行立刻写回并关闭，跟 `CurrencyPickerView`
  选中即返回同一套手感。
- **仓库里现在仍然没有任何本地化基础设施**（没有 `.xcstrings`，没有
  `NSLocalizedString`）。选中「中文」只是把偏好存起来、把导航栏的国旗图标换掉，
  **界面文案不会变**。真正的双语文案是一个独立的大工程，用户已经明确说了「先不做」，
  不要因为这个开关的存在就以为翻译已经接好。
- `RootTabView` 持有一个 `LanguagePreferenceStore` 实例（`@StateObject`，跟
  `themeController`同级），下发给 `AccountView` 和 `LoginView`。

### 顶栏与主题图标（个人中心 `106:2391`、登录页 `107:2589`/`133:6921`）

- `AccountView`/`LoginView` 的二级导航：返回箭头 → **关闭 X**（`IconClose`，全屏模态
  该用关不用返回）；主题图标改成**显示目标模式**——浅色下显示月亮（点它变深色），
  深色下显示太阳（点它变浅色），这是用户在这四选一里选的读法，实现在
  `NvwaThemeController.targetAppearanceIconName(systemScheme:)`；第二个尾随图标是
  当前选中语言的国旗，点开 `LanguagePickerSheet`。
- 头像 hero 尺寸 72pt → **120pt**（`106:2398`）。Nvwa Avatar 组件本身仍是 42pt 那档
  权威定义，继续只在这个产品页面覆盖尺寸。
- 选中头像的描边 1pt → **2pt**（`106:2405`），颜色本来就是 primary 没变。

### 登录页重画（`107:2589` 空闲态 / `133:6921` 登录中态）

- **空闲态**：去掉了 V1.1 那块蓝色背景和「Welcome Back」大标题——批注原文「去掉界面
  大蓝色，去掉标题和副标题」。现在是纯白背景 + 新版二级导航 + 居中的 outline 谷歌按钮。
- **登录中态是新增的一屏，不是简单的按钮 disable**：`model.isBusy` 一旦为 true，
  整屏换成「Welcome Back / Your Data is protected.」+ 一枚原生菊花（`PawLoadingIndicator`
  塞进一个描边胶囊里，形状照抄原来的 Outline Button），顶栏这一步**整个收起**——
  这一步不该给用户点关闭或切主题的机会。
- **这一步「等云端同步完成」不是新加的异步逻辑，是把已经存在的等待可视化了**：
  `AccountViewModel.signIn(using:)` 内部本来就一路 `await` 到
  `prepareAuthenticatedSession` 把持仓、资料都同步完（或者停在 `.guestImportRequired`
  / `.syncPaused` 这类需要用户在个人中心页自己做决定的节点）才返回，`isBusy` 全程
  跟着这一整段异步操作。核对过代码路径确认了这一点，所以这次没有改
  `AccountViewModel` 一行代码，只改了 `LoginView` 在等待期间展示什么。
- 新增两个 `#if DEBUG` QA 钩子，跟仓库里一大批同款钩子放在一起长期保留：
  `PAWFOLIO_QA_LANGUAGE_PICKER=1` 直接弹出语言选择，`PAWFOLIO_QA_LOGIN_WAITING=1`
  强制停在登录中态截图。

### Portfolio 持仓页（`107:2561`/`120:2377`/`120:2576`）

- 总资产大数字 22px → **26px**（`Nvwa.font(26, weight: .semibold)`，tracking 改成
  -0.39，和 `HoldingDetailView` 里「Total Yield/Total Profits」那两处 26px 大数字
  完全同一份写法，不是另起一套）。Figma 里两处写 26、一处写 22，用户选了统一 26。
- **修了一个真实的产品行为问题**：隐藏资产时「Total PNL」整行以前是**直接从布局里
  消失**的；批注明确写着这个字段隐藏时也要展示。现在改成整行保留，只把金额和百分比
  换成 `***`——涨跌方向本来不是敏感信息，整行消失反而像是数据丢了。
  `PortfolioViewModel`/`PawFolioTests` 都没有覆盖这段纯 View 逻辑，这次也没有为它
  补文件级测试（判断：这段是布局条件分支，不是独立可测的算法）。
- 持仓行 logo 直径 28pt → **32pt**（`HoldingRow`、`MergedHoldingRow`；`HoldingSubrow`
  那颗单独的现金图标 28pt 没有改，设计里不是同一个元素）。
- 合并卡的展开箭头换成 `IconArrowDropRight` 单图标 + 旋转（见上面 Nvwa 组件一节）。
- 「Group by Asset」复选框**在这轮之前就已经是 `NvwaCheckbox` 了**，没有需要新建的
  UI——审计时曾经以为这是待建功能，读代码后发现已经做完，这次没有动它。

### HoldingDetailView 详情弹层（`120:2988` 股票 PnL / `134:7293` 稳定币 Earn）

- 备注展示：两张详情弹层原来完全不显示 `holding.note`，写了也是白写。新增
  `noteHint(for:)`，`note` 非空时在最上面插一条中性色的 `NvwaHint`
  （批注「增加note显示」）。
- `recordsRow` 从手写的灰底 HStack 改成套 `NvwaHint`（组件本来就有現成的
  `NvwaHintLevel`，V1.2.2 之前这几行完全没吃到这套语义）：利息/分红记录用
  `.positive`（绿），调仓记录用 `.warning`（黄），批注原文「利息/股息的提示用
  level2」「调仓的提示用level3」。股票 PnL 弹层里把分红记录（绿）挪到了调仓记录
  （黄）前面，跟设计稿的行序对齐——这之前反了。
- 两张弹层的自适应高度算法（`earnSheetHeight`/`stockSheetHeight`）加上了备注那一行
  的高度估算（备注最长 20 字，12pt 字号下稳稳一行，按跟其余记录行同样的 48pt 估）。

### 没有动、但读代码时特意确认过的两处

- `HoldingDetailView` 的价格走势卡片（`priceCard`）**在这之前就已经**用
  `padLow: 0, padHigh: 0` 让峰谷贴轴，大概率已经满足 `120:3052` 那条「chart 高度撑满
  Y 轴」的批注，这次没有再改。
- 一处批注写着某个导航圆圈要改成 36px，但那个节点自己导出的标记里其余所有同类圆圈
  （包括它自己）量出来都是 40px，和 `NvwaNavigationBarMetrics.visibleControlSize`
  现有实现一致——按 `AGENTS.md` 的规则，量出来的几何数字和批注文字打架时不瞎猜，
  这处保留 40px 没有改，等用户看到再确认那条批注是不是画布里的笔误。

验证：SwiftPM `ios` **238 passed**、Nvwa **31 passed**、iPhone 17 Pro / iOS 26.5
`xcodebuild test` **TEST SUCCEEDED**；`build-for-testing` 只剩既有的
`HoldingDetailView.swift` 那条 result-builder 警告（行号因为本轮插入代码而挪动，
警告内容没变）。截图核对了：个人中心（新导航三图标、120pt 头像、2pt 选中描边）、
语言弹层、登录空闲态、登录中态（原生菊花）、Portfolio 默认/隐藏/展开三态、
BTC PnL 详情（含备注+黄色调仓提示）、USDC Earn 详情（含绿色利息提示+黄色调仓提示）。

未做、留给下一轮：真正的中英文双语文案（这次明确按用户要求跳过）；

## V1.2.2 收尾：导航图标尺寸、国旗渲染真 bug、头像选中态、Save 菊花、登录 Toast（2026-09-03）

用户看实机截图后追加的五处修正，都已落地并重新截图/跑过全套测试。

**导航栏主题+语言图标改成独立的 20pt**（原来跟关闭图标共用 24pt，两颗挤在一起
显得太大）。`NvwaNavigationBarMetrics` 新增 `secondaryTrailingIconSize = 20`，
只用在 `.secondary` 变体的 `trailingIcon`（主题）和 `secondTrailingIcon`（语言）上，
关闭图标本身仍是 24pt——两者本来就不是同一档。

**揪出一个真实的国旗渲染 bug，波及 11 面旗，不止用户看到的英国那一面。**
`FlagGB.svg` 的圆形裁切用的是 `mask-type:alpha`，但填色填的是国旗自己的深蓝
`#231D9A`（亮度只有 ~15%）——iOS 的 Asset Catalog SVG 渲染器对 `mask-type:alpha`
的支持有限，看起来是退化成按**亮度**而不是**透明度**取值，深色填充的 alpha 遮罩
就把整面旗按那个亮度打了折扣，肉眼看就是「像是加了透明度」。全库过了一遍同样
模式（`mask-type:alpha` 且填色不是白色），一共 **11 面**：`GB`、`MZ`（填深蓝，
最明显）、`AU`、`BH`、`BN`、`NZ`、`PA`、`QA`、`TM`、`TW`、`VN`（填浅灰，
之前不容易被人眼察觉，但同样是这个 bug）。修法是把这些 alpha 遮罩内的填色统一
改成 `white`——遮罩用什么颜色本来就不该影响裁出来的结果（真正的 alpha 语义下
颜色无关，只看有没有覆盖），改成白色只是去凑这个渲染器的隐藏假设，跟其余 56 面
一直没出问题的旗子用的是同一个约定。**没有改任何旗子的可见颜色**，只改了裁切
遮罩内部那一层看不见的填色。

**语言图标不再自己存一份 "FlagGB"/"FlagCN" 字符串**：`AppLanguage.flagAssetName`
现在转一手问 `CurrencyCatalog.info(for:)`，跟货币页共用同一个国旗名的唯一出处
（用户原话「国旗的assets请从汇率页面那边取现成的」）。

**头像选中态两处修正**：描边颜色 `Nvwa.primaryGreen`（蓝）→ `Nvwa.grayPrimary`
（黑/白跟主题走）——原先的批注「颜色为primary」把「primary-green 品牌蓝」和
「text/primary 文字色阶」这两个概念撞了名字，用户澄清是后者。另外在
`selectionRing` 上钉了 `.animation(nil, value: isSelected)`：文件里没有任何显式
`withAnimation`，这层「选中要延迟一下才出现」是 SwiftUI 某个隐式事务带出来的，
不去查是哪一层带的，直接钉死这一个视图不参与动画最省事也最保险。

**Profile 页 Save 按钮进行中不再写「Saving…」，换成菊花。** `NvwaButton` 新增
`isLoading: Bool` 参数（默认 false，向后兼容），为 true 时标题和 leadingIcon
让位给一枚 `ProgressView`（用按钮自己的前景色着色，主色按钮上是白色菊花），
按钮尺寸/形状/颜色不变。这是个通用扩展，不是 AccountView 私有逻辑，以后别的
地方要同款效果可以直接用。

**登录失败提示从「常驻 Hint」改成「一次性 Toast」。** 原来的
`authenticationMessage` 是个挂在按钮下面的 `NvwaHint`，只要 `model.state` 停在
`.failed` 就一直显示——取消登录（或任何失败）之后没有任何路径会把它收回去，
用户报的「一直不消失」就是这个。现在改成 `.onChange(of: authenticationMessage)`
触发 `PawToastCenter.shared.show(...)`，跟 `AccountView` 自己「Logged out」
「Profile saved」用的是同一个全局 toast 出口（`RootTabView` 顶层挂一次
`.pawToast()`，跨 `fullScreenCover` 也能弹，这是已经验证过在用的路径，这次没有
再单独给 `LoginView` 加一份）。

验证：SwiftPM `ios` 239 passed、Nvwa 31 passed、iPhone 17 Pro / iOS 26.5
`xcodebuild test` TEST SUCCEEDED。截图逐项核对了导航图标尺寸、英国国旗颜色
（改前改后对比，改后是正常的藏青/白/红）、头像选中态改成黑色描边。Save 按钮菊花
和登录失败 toast 这两条**没有交互手段验证**（这台机器点不了模拟器），是按代码
路径核对正确性，不是截图证实的——如果实机看着不对，大概率是 `NvwaButton` 的
`ProgressView` 着色或者 toast 没弹出来，从这两处查起。

## Exact next task

V1.2.2 的像素级还原已经全部完成并截图核对过（见上面那一节）。真正要做的下一件事是
**双语文案**——这次明确按用户要求跳过了，仓库里现在完全没有本地化基础设施
（没有 `.xcstrings`，没有任何 `NSLocalizedString`）。启动那项工作前先跟用户确认范围：
是先接入 String Catalog 但只翻译 Portfolio/Calculate/Currency 三个主标签页，还是要求
从第一天起覆盖所有弹层和错误文案。

另外欠着用户一次确认：`120:2382`（隐藏资产样式那张图）批注写着某个导航圆圈要改
36px，但那张图自己导出的标记里所有同类圆圈量出来都是 40px、和现有实现一致，这次
没有照批注文字改，留着等用户看实机效果后拍板是不是画布里的笔误。

用户之前确认过「整体尺寸偏小」是看错了，不做全局缩放，继续保持 Figma 的绝对 point
尺寸。线上 Web 的猫咪彩蛋已经下线；原生 `CatGallerySheet` 本轮刻意未动。如果用户也要
移除 iOS 端，需要删除双击入口、Account 内入口与相关视图/工程引用，并重新安装到真机“龙”。

## 375pt 设计稿与宽屏真机的尺寸诊断（2026-09-03）

- 用户附件把 375pt 的 Figma 画板与 iPhone 17 Pro Max 开发截图并排展示。连接真机“龙”是
  iPhone 17 Pro Max，逻辑宽度 440pt；设计稿节点 `29:1427`、`40:2369`、`68:7629` 均为
  375pt 宽。相同的 14pt 字体或 40pt 输入框在 440pt 画布中占屏比例会缩小约 14.8%，这是
  “所有元素都小”的系统性来源。
- 代码没有根视图整体缩放；`scaleEffect` 只出现在按压、拖拽、tooltip/插画等局部效果。
  Add Position 使用的 Nvwa 数值与设计稿一致：Modal Header 66pt、标题 18/24、Label 12/20、
  输入文字 14/22、Input 40pt、Segment 36pt、页面 padding/section gap 16pt、Save 40pt。
- 字体回退已排除：构建产物包含 `Inter-Regular/Medium/SemiBold/Bold.ttf`，`UIAppFonts` 完整，
  字体文件 PostScript 名称与 `NvwaTypography` 请求的名称一致。
- 用同一构建、默认 Large Dynamic Type 分别在 iPhone 17e（390pt，1170px）和 iPhone 17 Pro
  Max（440pt，1320px）启动 Fiat Earn 状态并截图。两者的 40pt 输入框均渲染为 3x 屏幕上的
  120px 几何，没有运行时缩小；截图为 `/tmp/pawfolio-17e-fiat.png` 与
  `/tmp/pawfolio-pro-max-fiat.png`。
- 用户附件本身还对左右截图采用了不同缩放：设计区域约 579px / 375pt，开发区域约
  620px / 440pt，因此同一个 point 在拼图右侧还会额外显得约 8.8% 更小。附件不是可用于
  逐像素测量的 1:1 同状态叠图。
- 本轮只诊断，没有改动产品代码；未运行测试。模拟器安装和截图仅用于只读视觉验证。

## 线上 Web 猫咪彩蛋下线（2026-09-03）

- 从 `public/index.html` 删除“我们家的猫”弹层和大图查看器 DOM。
- 从 `public/app.js` 删除顶栏头像双击分支、猫咪网格渲染、500ms 长按识别、大图开关、
  选猫与 Escape 关闭分支；头像现在单击立即打开个人资料，不再等待 320ms 双击窗口。
- 从 `public/styles.css` 删除猫咪弹层、大图查看器及专属变量；保留头像图片所需的
  `photo-paper`。旧账号已经同步的 `cat:<id>` 仍通过最小兼容映射正常显示，避免资料损坏。
- 静态资源版本更新为 `styles.css?v=128`、`app.js?v=121`。
- 本地浏览器验证猫弹层、大图查看器、猫格子 DOM 数量均为 0；头像入口仍打开个人资料，
  控制台无错误。`node --check public/app.js`、5 个 Web 同步测试和 `git diff --check` 通过。
- 已部署到 Cloudflare，Worker Version ID：`0016ef56-ba73-420b-a78a-094b1f055b9f`。
  生产站点回读确认加载 `app.js?v=121` / `styles.css?v=128`，已无猫弹层和长按大图代码。
- 本轮“线上”按 Web 处理；iOS 的 `CatGallerySheet`、Account 双击入口和 RootTabView 彩蛋
  未修改。

## 默认安装目标（用户 2026-09-03 指定）

- 后续用户说“安装”“运行到 iOS”等未明确目标时，默认安装到已连接的真机“龙”，不要默认
  使用模拟器；只有真机不可用时才说明原因并询问是否改用模拟器。
- 2026-09-03 已用本机现有 PawFolio provisioning profile 完成 arm64 真机构建，随后通过
  `devicectl` 安装并成功启动 `com.jiujiucat.pawfolio`。安装更新保留应用数据。

The user has explicitly deprioritized accessibility work, so the VoiceOver walkthrough remains on
hold. Keep Sign in with Apple disabled until the user has an Apple Developer Team. Detailed operator
steps live in `ios/Docs/AUTH_SETUP.md`; never request or commit credentials or tokens.

## Nvwa 全组件扫描与 iOS 组件库同步（2026-09-03）

已通过官方 Figma MCP 从 Nvwa 文件 `B7QSpRFNAt2tZ6S2JiG3Ij` 的根节点扫描全部四页：
Style & Assets、Icon、Input、Components。Components 页的 16 个 Component Set 与 10 个独立
组件，以及 Input 页的输入框和 Calendar primitives 均已逐项核对。Remix Icon 继续由宿主
注入；Flags 与九个 Key Feature 插画的既有资源边界不变；Web 未修改。

本轮同步内容：

- 本地颜色变量从 27 个增至 28 个，新增 `Text/Blue`（Light `#0051FE` / Dark `#4782FF`）。
  Market Buy 更新为 `#1D7353 / #2CC094`，Alpha Green 20% 更新为
  `#4AB18B33 / #2CC09433`，BG Card Dark 更新为 `#212121`，Alpha Blue 10% Dark 更新为
  `#4782FF33`。Alpha token 现在支持真正的 Light / Dark 动态 RGBA。
- Button 增加 `.huge` 48pt，保留 `.large` 40pt 兼容现有调用；Small / Tiny 仍为 32 / 28。
  Huge 不带图标，Large 只有 Outline 有 Leading；Outline 两类 stroke 改为 0.5pt。
- Segment 更新为 Normal 40（item 36）与 Small 28（item 24）；Small 改为 Hug content，
  `B-S Semi Bold`，选中态使用 `Text/Blue`。Normal 继续保持 Figma 的 345pt authored width，
  `expandsHorizontally` 仍是明确的代码扩展。
- Tag 改为统一水平 6pt、垂直 2pt、icon/text gap 0、总高 16；Input 四类公共 field height
  改为 48pt。Figma `Flag` 节点 `2074:894` 当前视觉上重复 Date Input 且带 calendar 尾图标，
  本地保留既有宿主注入国旗语义，只同步公共几何，并在 `FIGMA_COMPONENTS.md` 记录异常。
- Modal Header surface 改绑 `BG/Main`；Navigation profile avatar 改为 16pt Semibold / 0.08，
  Add glyph 改为 20pt；Hint 的右侧箭头与正文统一使用 `Text/Primary`，仅 Level 1 绘制
  `Line` 边框。
- Toggle、Avatar、Checkbox、Tooltip、Toast、Section、Slider、Calendar 与 Key Feature
  逐项复核后无需结构改动；相关 token 变化会自动传递。Catalog、README、token 快照、
  component map 与回归测试已同步。

验证结果：

- Nvwa SwiftPM：29 tests passed，0 failures。
- PawFolio SwiftPM：238 tests passed，0 failures。
- generic iOS Simulator `build-for-testing`：`TEST BUILD SUCCEEDED`。
- iPhone 17 Pro Max / iOS 26.5：276 XCTest cases passed，0 failures / skipped；结果包为
  `/tmp/pawfolio-derived/Logs/Test/Test-PawFolio-2026.09.03_21-20-41-+0800.xcresult`。
- Catalog 已在同一模拟器核对 Light / Dark token、四档 Button、两档 Segment、Tag、Hint、
  48pt Inputs、Modal Header 和 Key Feature。截图在 `/tmp/nvwa-refresh-qa/colors-light.png`、
  `/tmp/nvwa-refresh-qa/controls-light.png`、`/tmp/nvwa-refresh-qa/inputs-dark.png`、
  `/tmp/nvwa-refresh-qa/colors-dark.png`。

Exact next task: 在后续产品页面开发中使用这版 Nvwa，不要在 feature view 覆盖组件几何；
若设计师修正 `Flag` 节点 `2074:894`，先重新读取该节点，再决定是否扩展 `NvwaFlagInput`。

## V1.2.1 产品页 Button Huge 迁移（2026-09-03）

- 产品设计基线为 Pawfolio Design `ThlaCizGXDV4puXbtg8Fk0` / `116:3744`；组件几何继续以
  Nvwa `B7QSpRFNAt2tZ6S2JiG3Ij` 为准。该版 Nvwa 的 Huge Button 高度为 48pt。
- V1.2.1 节点内 11 个主操作按钮已统一改用 `NvwaButton(size: .huge)`：Account 的 Save / Log
  Out、Calculate、Add Position Save、Stock Edit Save、Stablecoin Edit Save、Position
  Confirmation Back / Confirm、股票及生息详情 Edit、Interest / Adjustment Records OK。
- 范围只覆盖 `116:3744` 实际出现的主操作与底部按钮；登录、同步恢复、列表快捷按钮等未在
  该节点出现的控件保持原尺寸。Web 未修改，Feature View 也没有覆盖 Nvwa 的按钮几何。
- iPhone 17e / iOS 26.5 模拟器完成视觉核对：Huge 均为 48pt，Add Position 与 Account
  底部按钮未被安全区裁切，Position Confirmation 两颗 Huge 按钮没有横向溢出。截图：
  `/tmp/pawfolio-v121-screens/calculator.png`、`add-position.png`、
  `position-confirmation.png`、`account.png`。

验证结果：

- PawFolio SwiftPM：238 tests passed，0 failures。
- generic iOS Simulator `build-for-testing`：`TEST BUILD SUCCEEDED`；构建目录为
  `/tmp/pawfolio-v121-derived`。
- iPhone 17e / iOS 26.5：276 XCTest cases passed，0 failures / skipped；结果包为
  `/Users/user/Library/Developer/Xcode/DerivedData/PawFolio-goztoavikxuptofbamuifqrpmijy/Logs/Test/Test-PawFolio-2026.09.03_21-30-34-+0800.xcresult`。
- `git diff --check`：通过。

Exact next task: V1.2.1 的 Huge Button 迁移已完成；继续开发 `116:3744` 的下一项产品改动时，
先读取对应子节点并逐页做模拟器截图对比，不要把 Nvwa 组件几何写回业务页面。

## Nvwa Top Nav 与二级导航尺寸更新（2026-09-03）

- 重新读取产品稿 Top Nav `ThlaCizGXDV4puXbtg8Fk0` / `73:9387`，并用 Nvwa 最新的
  Profile `B7QSpRFNAt2tZ6S2JiG3Ij` / `2102:1169` 与 Secondary `2102:1102` 交叉确认。
- `NvwaNavigationBar` 两类导航统一更新为：总高 64pt、可见圆形控件 40pt、图标 24pt、
  可见水平边距 16pt、垂直边距 12pt。SwiftUI 继续保留 44pt 点击区域，因此内部布局 inset
  为 14pt，让不可见的 2pt 扩展不改变 Figma 的可见位置。
- Profile 字母更新为 Inter Medium 14pt、tracking 0.21；宿主注入的 Add、Shining、Close
  Remix 图标 path 已与本次 Figma 导出逐条比对一致，无需替换资产。产品页没有局部覆盖尺寸，
  PawFolio、Calculate、Currency、Account 和 My Cats 会自动继承新版 Nvwa 几何。
- `FIGMA_COMPONENTS.md` 与 `NvwaTokenTests` 已同步；组件目录模拟器截图为
  `/tmp/pawfolio-nav-screens/catalog-navigation.png`，Profile / Guest / Secondary 均无裁切。

验证结果：

- Nvwa SwiftPM：30 tests passed，0 failures。
- PawFolio SwiftPM：238 tests passed，0 failures。
- generic iOS Simulator `build-for-testing`：`TEST BUILD SUCCEEDED`；构建目录为
  `/tmp/pawfolio-nav-derived`。
- iPhone 17e / iOS 26.5：276 XCTest cases passed，0 failures / skipped；结果包为
  `/Users/user/Library/Developer/Xcode/DerivedData/PawFolio-divdktxpqnruonehkljabvtknpzr/Logs/Test/Test-PawFolio-2026.09.03_21-50-49-+0800.xcresult`。
- `git diff --check`：通过。
- 全量当前工作区已使用本地 Team `HGTMKU5HMG` 与既有 provisioning profile 完成 arm64
  真机构建（`BUILD SUCCEEDED`），随后覆盖安装并成功启动到“龙”（iPhone 17 Pro Max /
  iOS 26.5.2，bundle id `com.jiujiucat.pawfolio`）；覆盖安装保留应用数据。构建产物位于
  `/tmp/pawfolio-device-deploy/Build/Products/Debug-iphoneos/PawFolio.app`。

Exact next task: 继续 V1.2.1 后续页面改动；涉及导航时直接复用新版 `NvwaNavigationBar`，
不要在 Feature View 重新设置 40pt 圆形、24pt 图标或 64pt 总高。

## Nvwa 分段控件切换加速（2026-09-03）

- `NvwaSegmentControl` 的选中块位移动画由 0.16 秒缩短为 0.12 秒；继续使用可中断的
  `snappy` 动画并保持 `extraBounce = 0`，快速连续切换时会直接追随最新选项，不增加回弹。
- 本轮只调整切换速度，Segment 的 Normal / Small 几何、文字、颜色与选中状态均未改变。
- 动画时长收口到 `NvwaSegmentMetrics.selectionAnimationDuration`，组件规格测试锁定为
  0.12 秒，避免后续无意回退。

验证结果：

- Nvwa SwiftPM：30 tests passed，0 failures。
- PawFolio SwiftPM：238 tests passed，0 failures。
- generic iOS Simulator `build-for-testing`：`TEST BUILD SUCCEEDED`；构建目录为
  `/tmp/pawfolio-segment-derived`。
- signed physical-device build：`BUILD SUCCEEDED`；已覆盖安装并成功启动到真机“龙”
  （iPhone 17 Pro Max / iOS 26.5.2，bundle id `com.jiujiucat.pawfolio`），应用数据保留。

Exact next task: 请用户在真机上体验 0.12 秒的 Segment 切换；若仍嫌慢，只调整
`NvwaSegmentMetrics.selectionAnimationDuration`，不要改 Feature View 或组件几何。

## iOS 全局 Loading 改为系统菊花（2026-09-03）

- 按用户新决定，iOS 所有可见加载动画统一为 SwiftUI 原生圆形 `ProgressView`。
  `PawLoadingIndicator` 只统一系统样式、Nvwa 动态颜色与 VoiceOver 文案，不自绘动画。
- Asset Search 的加载态、持仓首屏加载、走势图更新、持仓保存和分红记录保存均已接入
  `PawLoadingIndicator`。
- Portfolio 下拉刷新从自定义位移探针和跑步猫恢复为系统 `.refreshable`，使用 iOS 原生
  下拉手感与菊花动画。
- 删除 iOS 的 `PawRunningCat` / `PawAnimatedArt` 播放代码、`PawRefreshableScrollView`
  以及 `ArtLoading` 资源；`loading-anim.png` 已从工程和真机 App 包移除，减少约 280 KB。
  Web 端的 loading 资源与行为没有修改。
- `AGENTS.md` 已记录这一全局例外，后续不要重新加入自定义 Loading 或自定义下拉刷新。

验证结果：

- PawFolio SwiftPM：238 tests passed，0 failures。
- `plutil -lint ios/PawFolio.xcodeproj/project.pbxproj`：通过。
- generic iOS Simulator `build-for-testing`：`TEST BUILD SUCCEEDED`；构建目录为
  `/tmp/pawfolio-loading-derived`。
- signed physical-device build：`BUILD SUCCEEDED`；已覆盖安装并成功启动到真机“龙”
  （iPhone 17 Pro Max / iOS 26.5.2，bundle id `com.jiujiucat.pawfolio`），应用数据保留。

Exact next task: 在真机检查 Asset Search 加载与 Portfolio 下拉刷新手感；后续新增异步页面
统一复用 `PawLoadingIndicator`，可刷新列表统一使用 `.refreshable`。

## Segment 0.08s 与 Input 48pt 真机同步修复（2026-09-03）

- `NvwaSegmentControl` 的选中块位移动画由 0.12 秒进一步缩短为 0.08 秒；动画仍使用
  `snappy` 且 `extraBounce = 0`，规格测试同步锁定新时长。
- 重新读取 Nvwa Text Input `B7QSpRFNAt2tZ6S2JiG3Ij` / `2014:7294`：字段本体为
  48pt 高、16pt 水平内边距、10pt 圆角，Normal / Small 共用相同高度。
- 真机未体现 48pt 的原因不是 Nvwa Input 本身：组件实现已经是 48pt，但 Dividend 编辑器
  仍通过旧 `PawInputShell` 使用 52pt，持仓新增/编辑的日期和稳定币字段另有 40pt 硬编码。
- 新增公共 `Nvwa.inputHeight = 48` 作为组件与产品层的单一几何来源；Text/Search/Date/Flag
  Input、旧输入壳、Dividend 只读/频率字段、持仓日期与稳定币输入全部引用该值。旧壳的背景
  和圆角同时对齐 Nvwa `backgroundInput` / `radiusControl`，没有改动键盘或 DatePicker 行为。
- iPhone 17 Pro Max / iOS 26.5 模拟器已打开 Nvwa Catalog Inputs 做视觉检查；Text、Error、
  Search、Date、Flag 五种实例高度一致，截图为 `work/qa/nvwa-input-48.png`。

验证结果：

- Nvwa SwiftPM：30 tests passed，0 failures。
- PawFolio SwiftPM：238 tests passed，0 failures。
- generic iOS Simulator `build-for-testing`：`TEST BUILD SUCCEEDED`；构建目录为
  `/tmp/pawfolio-derived`。
- iPhone 17 Pro Max / iOS 26.5：276 XCTest cases passed，0 failures / skipped；结果包为
  `/tmp/pawfolio-derived/Logs/Test/Test-PawFolio-2026.09.03_22-24-47-+0800.xcresult`。
- signed physical-device build：`BUILD SUCCEEDED`；已覆盖安装并成功启动到真机“龙”
  （iPhone 17 Pro Max / iOS 26.5.2，bundle id `com.jiujiucat.pawfolio`），应用数据保留。

Exact next task: 请在真机复核 Segment 0.08 秒切换手感，以及 Dividend、持仓日期和稳定币
编辑字段的 48pt 高度；后续输入组件统一引用 `Nvwa.inputHeight`，不要在 Feature View 写高度。

## Calculate Input 48pt 补漏（2026-09-03）

- 用户真机复核发现 Calculate 页仍为 40pt。根因是 `CalculatorView` 的 Total Investment 与
  APR 两个字段是页面内的定制输入壳，不在上一轮检出的 Portfolio 输入路径中。
- 两处 `.frame(height: 40)` 已改为 `Nvwa.inputHeight`，圆角同时从字面量 10 改为
  `Nvwa.radiusControl`；输入绑定、键盘、金额格式与计算逻辑均未改变。
- iPhone 17 Pro Max / iOS 26.5 模拟器已直接打开 Calculate 页视觉核验，截图为
  `work/qa/calculator-input-48.png`。

验证结果：

- PawFolio SwiftPM：238 tests passed，0 failures。
- generic iOS Simulator `build-for-testing`：`TEST BUILD SUCCEEDED`。
- iPhone 17 Pro Max / iOS 26.5：276 XCTest cases passed，0 failures / skipped；结果包为
  `/tmp/pawfolio-derived/Logs/Test/Test-PawFolio-2026.09.03_22-33-37-+0800.xcresult`。
- signed physical-device build：`BUILD SUCCEEDED`；已覆盖安装并成功启动到真机“龙”
  （bundle id `com.jiujiucat.pawfolio`），应用数据保留。

Exact next task: 请在真机 Calculate 页复核 Total Investment / APR 的 48pt 高度；新增页面输入
壳必须引用 `Nvwa.inputHeight`，不得再写局部 40pt。

## Segment 0.06s 平滑位移与 Section 全区域热区（2026-09-03）

- 用户反馈 0.08 秒 Segment 切换仍有闪动/卡顿。复查发现旧的父级 `snappy` transaction
  同时驱动 matched-geometry 胶囊位移、文字颜色插值和条件背景的显隐，快速连续切换时三种
  过渡互相竞争，视觉上会像闪一下或停一下。
- `NvwaSegmentControl` 现在只对选中胶囊应用可中断的 0.06 秒 `linear` 位移动画；文字颜色
  transaction 明确禁用动画，胶囊使用 `.transition(.identity)` 禁用默认淡入淡出。Reduce Motion
  开启时仍会关闭位移动画，Segment 的 Normal / Small 几何和颜色 token 均未改变。
- `NvwaSection` 在完整的 28pt frame 与背景之后增加矩形 `contentShape`，因此左右 padding 和
  组件自身占用的全部区域都能触发按钮，不再要求点中文字。
- iPhone 17 Pro Max / iOS 26.5 模拟器的 Nvwa Controls 目录完成高频连续切换；选中胶囊直接、
  平滑地跟随目标项，没有观察到闪白、交叉淡化或停顿。分别点击 Activity 的右侧文字外留白
  与 Overview 的左侧文字外留白，Accessibility 选中态均正确切换。交互录屏为
  `work/qa/nvwa-segment-section-0.06s.mp4`。

验证结果：

- Nvwa SwiftPM：30 tests passed，0 failures；组件规格测试锁定动画时长为 0.06 秒。
- PawFolio SwiftPM：238 tests passed，0 failures。
- generic iOS Simulator `build-for-testing`：`TEST BUILD SUCCEEDED`；构建目录为
  `/tmp/pawfolio-derived`。
- iPhone 17 Pro Max / iOS 26.5：276 XCTest cases passed，0 failures / skipped；结果包为
  `/tmp/pawfolio-derived/Logs/Test/Test-PawFolio-2026.09.03_22-43-58-+0800.xcresult`。
- signed physical-device build：`BUILD SUCCEEDED`；已覆盖安装并成功启动到真机“龙”
  （iPhone 17 Pro Max / iOS 26.5.2，bundle id `com.jiujiucat.pawfolio`），应用数据保留。

Exact next task: 请在真机快速连续切换 Segment，并点击 Section 的文字外 padding 复核手感；
后续不要在 Feature View 叠加动画或缩小 Section 热区。

## Section 跨页面即时选中反馈（2026-09-03）

- 用户发现 Portfolio 首页的时间周期 Section 响应很快，但 Calculator 快捷金额 Section 会受
  输入焦点收起和结果图表刷新影响，继承页面 transaction 后呈现出较慢的选中反馈。
- 统一规范已写入 `NvwaSection`：组件对 `isSelected` 变化明确使用 `nil` animation，选中背景
  与文字颜色即时切换，不再继承宿主页面、键盘或图表的动画。业务页面不需要也不允许重复
  设置 Section 点击动画。
- 新增 `NvwaSectionMetrics`，将 28pt 高度和“无选中动画”共同收口到组件规格；新增单元测试
  防止后续改回隐式或较慢动画。此前修复的整块矩形热区保持不变。
- iPhone 17 Pro Max / iOS 26.5 模拟器在 Calculator 连续切换
  100K → 200K → 500K → 800K → 1,000K → 100K，选中反馈均即时更新。录屏为
  `work/qa/nvwa-section-immediate-calculator.mp4`。

验证结果：

- Nvwa SwiftPM：31 tests passed，0 failures。
- PawFolio SwiftPM：238 tests passed，0 failures。
- generic iOS Simulator `build-for-testing`：`TEST BUILD SUCCEEDED`。
- iPhone 17 Pro Max / iOS 26.5：276 XCTest cases passed，0 failures / skipped；结果包为
  `/tmp/pawfolio-derived/Logs/Test/Test-PawFolio-2026.09.03_22-52-33-+0800.xcresult`。
- signed physical-device build：`BUILD SUCCEEDED`；已覆盖安装并成功启动到真机“龙”
  （iPhone 17 Pro Max / iOS 26.5.2，bundle id `com.jiujiucat.pawfolio`），应用数据保留。

Exact next task: 请在真机对比 Calculator 快捷金额与 Portfolio 时间周期的 Section 点击反馈；
后续 Section 选中态保持组件级即时切换，不要在 Feature View 添加局部动画。

## Section 计算页慢响应二次修正（2026-09-03）

- 上一轮仅用 `.animation(nil, value:)` 阻止组件自身创建动画，但 Calculator 点击 Section 时
  会同时收起输入焦点并刷新计算结果，已经存在的宿主 transaction 仍可传入组件，所以真机上
  仍能看到较慢反馈。
- `NvwaSection` 现在在按钮 action 与组件渲染两端都通过 `Transaction` 明确设置
  `animation = nil` 和 `disablesAnimations = true`。这是组件级强制规范，所有调用方都会获得
  与 Portfolio 首页时间周期一致的即时选中反馈。
- Calculator 内遗留的 D/M/Y 自绘 Button 也已替换为 `NvwaSection`，不再保留第二套点击行为。
- 模拟器按真实路径验证：先点击 Total Investment 唤起数字键盘，再点击 800K；键盘退出与
  结果刷新同时发生时，Section 选中态仍即时更新。录屏为
  `work/qa/nvwa-section-calculator-keyboard-immediate.mp4`。

验证结果：

- Nvwa SwiftPM：31 tests passed，0 failures。
- PawFolio SwiftPM：238 tests passed，0 failures。
- fresh derived-data iPhone 17 Pro Max / iOS 26.5：276 XCTest cases passed，0 failures；结果包为
  `/tmp/pawfolio-section-xctest/Logs/Test/Test-PawFolio-2026.09.03_23-06-17-+0800.xcresult`。
- signed physical-device build：`BUILD SUCCEEDED`；已覆盖安装并成功启动到真机“龙”
  （bundle id `com.jiujiucat.pawfolio`），应用数据保留。

Exact next task: 请在真机再次复核 Calculator 快捷金额 Section；后续新增 Section 必须直接使用
`NvwaSection`，禁止在 Feature View 手写同形控件或附加 selection animation。

## V1.2.3 两档弹窗与行情提示位置（2026-09-03）

- 用户确认 V1.2.3 为新的弹窗高度规范：所有底部弹窗只允许 `.half` / `.full` 两种相对设备
  高度，不再按内容、搜索结果数量、持仓类型或字段显隐动态计算高度。每个弹窗只有一个 detent，
  超出内容在弹窗内部滚动。
- `PawSheetSize` 与 `.pawSheetPresentation(...)` 成为唯一共享入口；`PawSheet` 必须显式传入
  `size`。旧 `PawSheetSizing`、运行时内容测量、视口高度注入和所有页面级 409 / 516 / 520 /
  642 / 744 / 827 / 844 等高度计算均已删除。
- 长内容固定 `.full`：Add/Edit Position、Stablecoin Editor、Asset Search、Currency Picker、
  PnL Details、利息/分红记录、Dividend Editor。短内容固定 `.half`：Position Confirmation、
  Language、Dividend Frequency、Cat Information、Adjustment Records。
- `SheetPresentationPolicyTests` 现在扫描 `Features/`，禁止重新加入原始
  `.presentationDetents(...)` 或已废弃的 `.pawAdaptiveSheetHeight(...)`。
- Portfolio 列表底部不再显示 `Using the latest available quotes`；该状态仍保留在
  `PortfolioViewModel.quoteStatusMessage`。需要用户处理的行情异常改用 Negative `NvwaHint`，
  放在 Total Assets 与 Positions 之间，列表 `End` 下方不再出现任何状态提示。

验证结果：

- PawFolio SwiftPM：238 tests passed，0 failures。
- generic iOS Simulator `build-for-testing`：`TEST BUILD SUCCEEDED`；构建目录为
  `/tmp/pawfolio-v123-derived`。仅保留既有的 `HoldingDetailView.swift` result-builder warning。
- iPhone 17 Pro / iOS 26.5：276 XCTest cases passed，0 failures。
- 模拟器实测 `.full` Add Position 与 `.half` Position Confirmation 均保持固定高度；截图为
  `work/qa/v123-full-sheet.png` 与 `work/qa/v123-half-sheet.png`。
- `git diff --check`：通过。

Exact next task: 在真机“龙”上复核 V1.2.3 的半屏/全屏弹窗切换和 Portfolio 行情异常 Hint；
用户要求安装时再进行签名构建与覆盖安装。

### V1.2.3 真机安装（2026-09-03）

- 使用本机 Team `HGTMKU5HMG` 与既有 provisioning profile 完成 Debug arm64 真机构建，
  `BUILD SUCCEEDED`；产物位于 `/tmp/pawfolio-v123-device/Build/Products/Debug-iphoneos/PawFolio.app`。
- 已通过 `devicectl` 覆盖安装到真机“龙”（iPhone 17 Pro Max / iOS 26.5.2），并成功启动
  `com.jiujiucat.pawfolio`；覆盖安装保留现有应用数据。

Exact next task: 在真机“龙”上体验 V1.2.3 的半屏/全屏弹窗和 Portfolio 行情异常 Hint，按实机
反馈继续微调。

## Portfolio 下拉刷新 80pt 触发与刷新期间驻留（2026-09-03）

- Portfolio 从系统 `.refreshable` 切换到共享 `PawRefreshableScrollView`；刷新图标仍使用
  iOS 原生 `UIRefreshControl` 菊花，没有恢复自定义 loading 动画。
- 下拉达到 80pt 时立即正式开始刷新，不再需要继续拉到系统默认的更长距离。
- 手势开始时预热 `UIImpactFeedbackGenerator`，跨过阈值时给一次 `.medium` 震动；同一次
  刷新不会重复触发。
- 刷新任务执行期间给滚动容器保留 80pt 顶部 inset，松手后内容与菊花保持在刷新位置；仅在
  `model.reload()` 完成后结束菊花并用 0.2 秒收回 inset。
- VoiceOver 增加 `Refresh` accessibility action，仍进入同一套刷新与驻留流程。
- `AGENTS.md` 的 loading 规则同步更新：继续使用原生菊花，但 Portfolio 的触发距离、震动和
  驻留行为以后必须由共享组件维护。
- `SheetPresentationPolicyTests` 增加源码策略断言，锁定 80pt 阈值、共享组件接入，并防止
  Portfolio 退回 `.refreshable`。

验证结果：

- PawFolio SwiftPM：239 tests passed，0 failures。
- generic iOS Simulator `build-for-testing`：`TEST BUILD SUCCEEDED`；构建目录为
  `/tmp/pawfolio-derived`。
- iPhone 17 Pro / iOS 26.5：277 XCTest cases passed，0 failures / skipped；结果包为
  `/tmp/pawfolio-refresh-xctest/Logs/Test/Test-PawFolio-2026.09.03_23-45-24-+0800.xcresult`。
- signed physical-device build：`BUILD SUCCEEDED`；最终产物位于
  `/tmp/pawfolio-refresh-device/Build/Products/Debug-iphoneos/PawFolio.app`。
- 已通过 `devicectl` 覆盖安装并成功启动到真机“龙”（iPhone 17 Pro Max，bundle id
  `com.jiujiucat.pawfolio`）；覆盖安装保留现有应用数据。
- `git diff --check`：通过。

Exact next task: 请在真机“龙”的 Portfolio 顶部下拉约 80pt，复核阈值震动、刷新期间内容驻留
和完成后的回弹手感；如需微调，只修改共享 `PawRefreshableScrollView`。

## V1.2.2 Figma 遗漏修复与语言半弹窗（2026-09-04）

- 按产品稿 `ThlaCizGXDV4puXbtg8Fk0` 重新核对 V1.2.2 重点节点：语言弹窗
  `107:2574`、同步失败 `136:7951`、Portfolio `107:2561`、持仓行 `120:2576`、
  登录等待 `133:6921`、股票详情 `120:2988`、生息详情 `134:7293`。
- Language 固定使用 `.pawSheetPresentation(.half)`；根容器填满 detent 并顶部对齐，修复短内容
  被系统垂直居中、标题和选项落在弹窗中部的问题。继续复用 `NvwaModalHeader`、Nvwa typography /
  color token、现有圆形国旗和 Remix `IconCheck`，没有在业务页重描组件。
- 用户已删除新增持仓 36pt 批注；以后以最新版 Nvwa Navigation Bar 的 40pt 动作按钮为准，
  不再记录或实现 36pt 产品稿覆盖。
- 登录等待态胶囊从整行宽收回为设计稿的 64×40pt；同步失败提示从 Account 移到 Portfolio，
  顺序为 Hint → Total Assets → Positions，`Retry` 是 `NvwaHint` 的行内可点击操作，重试完成后
  会重新加载 Portfolio。
- Portfolio 的 Total Assets / PNL 标签改为 14pt，`Total PNL` 改为 `PNL`；持仓代码和右侧金额
  使用 B-L 16pt。股票详情走势图与 Y 轴间距改为 10pt；记录入口文案对齐设计稿：
  `Dividends Records`、`interest Payout Records`、`Investment Adjust Records`。
- Account 的双击猫头像入口、Root QA 猫图鉴路由已移除；`CatGallerySheet.swift` 仍留作无入口的
  历史实现，旧 `cat:<id>` 头像解码保持兼容。
- `NvwaHint` 增加可选 `actionTitle/action`；`SheetPresentationPolicyTests` 锁定语言页必须使用半屏
  且顶部对齐；新增 `PAWFOLIO_QA_SYNC_FAILURE=1` 仅用于视觉验收。

验证结果：

- Nvwa SwiftPM：31 tests passed，0 failures。
- PawFolio SwiftPM：240 tests passed，0 failures。
- iPhone 17e / iOS 26.5：278 XCTest cases passed，0 failures / skipped；结果包为
  `/tmp/pawfolio-derived/Logs/Test/Test-PawFolio-2026.09.04_00-23-51-+0800.xcresult`。
- generic iOS Simulator `build-for-testing`：成功；构建目录为
  `/tmp/pawfolio-final-derived`。仅保留既有的 `HoldingDetailView.swift` result-builder warning。
- `git diff --check`：通过。
- 模拟器逐项复核了语言半弹窗、同步失败顺序和股票详情；截图为
  `/tmp/pawfolio-language-half-final.png`、`/tmp/pawfolio-sync-failure-final.png`、
  `/tmp/pawfolio-stock-detail-final.png`。

Exact next task: 在真机“龙”上复核语言半弹窗、登录等待态和同步失败提示；如产品稿没有新增批注，
V1.2.2 本轮已知遗漏无需再改。真正的中英文界面本地化仍是独立需求，本轮只实现语言选择器。

## Portfolio 持仓主次文字间距 6pt（2026-09-04）

- 按用户标注，仅修改 iOS Portfolio 持仓列表：普通/稳定生息 `HoldingRow` 与合并汇总
  `MergedHoldingRow` 左右两列的主文字和下方辅助文字间距由 4pt 统一为 6pt。
- 展开后的合并子行没有改动；Web `public/` 未修改。
- 模拟器分别用 `PAWFOLIO_QA_PORTFOLIO=positions` 与 `expanded` 检查普通、稳定生息、
  合并汇总及展开状态，没有金额截断或左右错位。

验证结果：

- PawFolio SwiftPM：240 tests passed，0 failures。
- generic iOS Simulator `build-for-testing`：`TEST BUILD SUCCEEDED`。
- signed physical-device build：`BUILD SUCCEEDED`；已覆盖安装到真机“龙”
  （iPhone 17 Pro Max / iOS 26.5.2，bundle id `com.jiujiucat.pawfolio`），应用数据保留。
- 安装后自动启动因真机处于锁屏状态被 SpringBoard 拒绝；不影响安装结果，解锁后可直接打开。

Exact next task: 在真机打开 PawFolio，复核普通、稳定生息与合并持仓行的 6pt 主次文字间距。

## V1.2.2 最终视觉收口、Nvwa Button 更新与真机安装（2026-09-04）

- 登录页按产品稿 `ThlaCizGXDV4puXbtg8Fk0 / 107:2589` 删除插画；Google 登录按钮保持
  Hug Content 并以整屏居中，不再写死宽度。导航栏使用顶部覆盖层，不参与中间内容的居中计算。
- Nvwa Button 按组件稿 `B7QSpRFNAt2tZ6S2JiG3Ij / 2014:7954` 更新：所有 Huge 文案统一为
  Inter Semibold 14pt / 0.175pt tracking；Outline Large 也改为 14pt / 0.175pt。
- 新增的 Outline Huge + Leading 变体 `2216:916` 已纳入组件规格矩阵：48pt 高、16pt 图标、
  图文间距 4pt。账号页和独立登录页的 `Login with Google` 均直接使用
  `NvwaButton(kind: .outline, size: .huge)`，没有业务页字体或尺寸覆盖。
- Portfolio 普通持仓与合并汇总左右两列的主/次文字间距最终按用户最新批注由 6pt 改为 4pt；
  本节决定覆盖上一节的 6pt 记录。
- Account 底部按 `136:8286` 收口：Save 为 343×40pt Outline Button，保存中使用原生
  `ProgressView`；Log Out 为 12pt Semibold 纯红文字，二者间距 16pt。
- Portfolio / Holding Detail 的手绘点阵走势图已让点阵底边与 Y 轴底部对齐，顶部曲线与 Y 轴
  顶部数字对齐。动态文案胶囊保持 Hug Content，避免长文案被定宽裁切。

验证结果：

- Nvwa SwiftPM：32 tests passed，0 failures。
- PawFolio SwiftPM：240 tests passed，0 failures。
- iPhone 17e / iOS 26.5：278 XCTest cases passed，0 failures / skipped；结果包为
  `/tmp/pawfolio-derived/Logs/Test/Test-PawFolio-2026.09.04_01-06-51-+0800.xcresult`。
- 登录页模拟器视觉复核通过；截图为 `/tmp/pawfolio-login-huge-final.png`。按钮由组件提供 48pt
  高度、14pt 文案、16pt 本地 `IconGoogle` 与 4pt 图文间距，整体保持 Hug Content 并居中。
- signed physical-device build：`BUILD SUCCEEDED`；产物位于
  `/tmp/pawfolio-device-derived/Build/Products/Debug-iphoneos/PawFolio.app`。
- 已通过 `devicectl` 覆盖安装并成功启动到真机“龙”（iPhone 17 Pro Max / iOS 26.5.2，
  bundle id `com.jiujiucat.pawfolio`）；覆盖安装保留现有应用数据。

Exact next task: 请在真机“龙”复核 48pt Google 登录按钮与其 14pt 文案；本轮 V1.2.2 已知视觉
遗漏均已收口，后续按新的产品稿批注继续。

## Button 字号规范按最新组件稿重取（2026-09-04）

本节的字号结论覆盖上一节的记录（上一节写的「所有 Huge 统一 14pt」已不成立）。

- 重新读取组件稿 `B7QSpRFNAt2tZ6S2JiG3Ij / 2014:7954` 的全部 32 个变体，文字样式只有四种：
  Huge = `B-L Semi Bold` 16/24（0.5%）、Large 与 Small = `B-M Semi Bold` 14/22（1.25%）、
  Outline Warning / Small = `B-M Regular` 14/22（1%）、Tiny = `B-S Regular` 12/20（1%）。
  没有任何按 family 的偏差。
- `NvwaButtonMetrics` 因此改为先取一个排版 token（`typography(kind:size:)`），
  `fontSize` / `usesSemibold` / `tracking` 都从该 token 推导，不再各维护一张手写表。
  修正了两处与设计稿不符的值：Huge 由 14pt/0.175 改为 16pt/0.08，
  Secondary Large 由 16pt/0.08 改为 14pt/0.175。
- Outline Large + Leading `2119:1267` 一度是稿子里唯一的 16pt Large，已由用户在 Figma 修回 14pt，
  代码与文档均不再保留该例外说明。
- Account 底部按产品稿 `ThlaCizGXDV4puXbtg8Fk0 / 139:1297` 修正：Save 改用 Outline **Huge**
  （48pt 高、16pt 文案，实例 `139:1324` 的 Size 属性即 Huge）；Log Out 文字改用
  `T-G Medium`（14/20，1.5% 字距，即 `Nvwa.Typography.titleGroup`），此前是 12pt Semibold。
  两者间距 16pt、容器内距 16/12pt 与稿子一致，颜色 `#A8200D` 与 `Nvwa.sentimentNegative` 一致。

验证结果：

- Nvwa SwiftPM：32 tests passed，0 failures。
- PawFolio SwiftPM：240 tests passed，0 failures。
- generic iOS Simulator `build-for-testing`：`TEST BUILD SUCCEEDED`。
- 本轮未做真机安装与模拟器视觉复核。

Exact next task: 在设备或模拟器上复核 Account 底部——Save 是否为 48pt 高、16pt 文案，
Log Out 是否为 14pt Medium。

## 导航组件按 `2224:91` 统一收口（2026-09-04）

- 组件稿现在是一个组件集 `2224:91`（导航），三个变体：`添加持仓` `2102:1169`、
  `二级导航` `2102:1102`、`个人中心` `2224:66`。旧文档里「Navigation / Profile」
  「Navigation / Secondary」两条独立条目已合并。
- 稿子的新增点：`二级导航` 现在有居中标题（`2224:62`，`B-M Semi Bold`），代码此前
  完全没有标题槽位；`个人中心` 是新变体，对应代码里原来用「二级导航 + 两个尾随图标」
  拼出来的账号页顶栏。
- `NvwaNavigationBar` 从三个初始化器 + 三分支枚举改成槽位化的单一初始化器：
  `init(leading:title:trailing:)`，槽位由 `NvwaNavigationBarItem`
  （`.avatar` / `.icon` / `.artwork`）描述。图标尺寸按槽位推导——一侧一枚是 24pt，
  一侧两枚降到 20pt，与三个变体逐一吻合。
- 合并的相似实现：导航栏原本自己画了一遍头像圆（首字母 + 图片 + 底色），已改为直接用
  `NvwaAvatar`。为此 `NvwaAvatar` 的 `fontSize`/`tracking` 两个参数合并成一个
  `typography: NvwaTypographyToken`——三处用法本来就分别对应
  `B-L Semi Bold`（42）、`T Semi Bold`（120）、`T-G Medium`（导航 40），拆开给容易写歪。
- `NvwaModalHeader` **没有**并入导航：它是另一枚组件（`2052:7350`，66pt、带拖拽条、
  18pt 标题、16pt 图标、15pt 内距），只是外形相近，合并会把两套几何搅在一起。
- 调用方随之收口：`PawTopNavigation` 的登录/未登录两个分支合成一条（只换左槽位），
  `AccountView` 两处顶栏、`CatGallerySheet` 均改为槽位写法。目录页补上了
  `个人中心` 变体，新增 `navigationTheme` 图标入参。

验证结果：

- Nvwa SwiftPM：32 tests passed，0 failures。
- PawFolio SwiftPM：240 tests passed，0 failures。
- generic iOS Simulator `build-for-testing`：`TEST BUILD SUCCEEDED`。
- iPhone 17e 模拟器视觉复核：Nvwa 目录页四条导航（三个稿子变体 + 未登录态）、
  账号页顶栏、Portfolio 顶栏均正常；标题居中、尾随两枚图标为 20pt、国旗保持原色。
  截图在 scratchpad 的 `nav-catalog.png` / `account.png` / `portfolio.png`。

Exact next task: 若要让 `CatGallerySheet` 用上新的标题槽位（现在标题还画在列表里的
「My Cats」），需要产品确认是否把它挪进顶栏，避免同一句话出现两次。

## Hint 补上提示插画，并查了英文下的上下留白（2026-09-04）

- 稿子 `2062:773` 的八个变体每一个都带一枚 12×12 的提示插画（Key Feature 的
  `Warning` `2029:9149` 缩小版），代码此前完全没画。现在补上，且**不做成可选项**——
  稿子里没有「不带插画」的变体。
- 插画底色四个等级不是一套规则，是稿子里就这么画的：level 1 实色 `Line`、
  level 3 实色 `Sentiment/Warning`、level 2 / 4 用和胶囊底色同一枚 20% 色板
  （两层叠加比背景深一点）。别顺手统一。
- 插画复用 `NvwaKeyFeatureIcon`，新增一个内部初始化器接受容器尺寸与底色；字形与容器
  的比例按稿子锁死（24/48 = 6/12），不另画一套。
- **上下 padding 的结论**：胶囊的内距本身是对称的 6/6，32pt 高度也和稿子一致，
  量出来「上多下少」的是**字形**不是内距——带下伸部的英文（Warning/Negative 里的
  `g`）字面顶到 11.33pt、下伸到 9.00pt；不带下伸部的（Neutral/Positive）是
  11.33/11.67。中文走 PingFang 回退、字面在字身框里居中，所以只有英文能看出来。
  这一档差异 Figma 里同样存在，属于字体本身，不是实现偏差。
- **但确实查出一处真的偏差**：SwiftUI 的 `Text` 只有字体自带的行盒（Inter 12pt 约
  14.5），不是稿子的 20，而 `lineSpacing` 又够不着首尾两端。结果两行的提示行距只有
  14.5pt（稿子 20pt），整块比稿子矮一圈。已在 `NvwaTypographyToken` 补上
  `naturalLineHeight` / `halfLeading`，`lineSpacing` 改成按真实字体度量算，
  `nvwaTextStyle` 同时补首尾的 half-leading。两行提示实测从 41.33pt 变成 52pt
  （= 6 + 20×2 + 6），与稿子一致。
- 实测对齐（iPhone 17e 截图逐像素量）：圆片 12×12、距胶囊顶 10pt（= 6 内距 + 4 让位），
  与稿子完全一致；单行胶囊仍是 32pt。

验证结果：

- Nvwa SwiftPM：34 tests passed，0 failures（新增 hint 几何与行盒两条）。
- PawFolio SwiftPM：240 tests passed，0 failures。
- generic iOS Simulator `build-for-testing`：`TEST BUILD SUCCEEDED`。
- iPhone 17e 模拟器：目录页 Messages 一节改动前后各截一张，见 scratchpad 的
  `hint-before.png` / `hint-after.png`。

Exact next task: 若产品觉得带下伸部的英文仍偏「上松下紧」，那是字体度量决定的，
要改只能整体下移基线（不建议）或改用更小的行高，需要设计确认后再动。

## 本轮组件改动装到真机（2026-09-04）

- Nvwa 是工程里的本地包（`XCLocalSwiftPackageReference`），按钮字号、导航槽位化、
  Hint 提示插画与行盒这几项改动无需额外接线，工程构建即生效。
- 真机构建：`xcodebuild -destination 'generic/platform=iOS' -configuration Debug
  DEVELOPMENT_TEAM=HGTMKU5HMG -allowProvisioningUpdates`，
  derivedData 在 `/tmp/pawfolio-device-derived`，签名走 Apple Development
  (`long012315@icloud.com`) + `iOS Team Provisioning Profile: com.jiujiucat.pawfolio`。
  **注意该 profile 的到期时间是 2026-09-04 16:00 UTC**，之后再构建会触发重新签发。
- 已用 `devicectl` 覆盖安装并启动到真机“龙”（iPhone 17 Pro Max /
  `05FAD045-9A8E-536B-8766-CA830DA04D6C`），覆盖安装保留应用数据。

验证结果：

- signed physical-device build：`BUILD SUCCEEDED`。
- `devicectl device install app` / `process launch`：均成功，App 已在设备上启动。

Exact next task: 在真机上核这三处——Huge 按钮文案是否为 16pt、账号页顶栏与 Save/Log Out、
以及各处 Hint 左侧新加的提示插画（尤其两行提示的行距）。

## 导航新增 Icon=Right / L+R 两个变体（2026-09-04）

- 组件集 `2224:91` 多了第二个属性 `Icon`（Left / Right / L+R），`二级导航` 因此从
  一个变体扩成三个：`Icon=Left` `2102:1102`、`Icon=Right` `2238:574`、
  `Icon=L+R` `2238:582`。整套现在是五个变体。
- **槽位化的 API 不需要改**：这三档本质就是「左槽位给不给」×「右槽位给不给」的排列，
  `init(leading:title:trailing:)` 原样就能表达。`Icon=Right` 走 `leading: nil` +
  `title:`，此时组件会保留一个 44pt 的空占位，标题仍落在整条导航的正中——这正是上一轮
  留占位的原因，现在被稿子用上了。
- **标题字号变了**：`2224:62` 从 `B-M Semi Bold` 14/22 上调为 `T-B Semi Bold` 18/24
  （-1% 字距），三个 Icon 变体同一档。`NvwaNavigationBarMetrics.titleTypography`
  已跟着改，测试断言同步。
- 目录页补上 `Icon=Right` 与 `Icon=L+R` 两条示例，文档表格补全五个变体与节点号。

验证结果：

- Nvwa SwiftPM：34 tests passed，0 failures。
- generic iOS Simulator `build-for-testing`：`TEST BUILD SUCCEEDED`。
- iPhone 17e 模拟器：目录页六条导航（五个稿子变体 + 未登录态）全部正常，`Icon=Right`
  的标题与 `L+R` 的标题在同一条中线上；截图 scratchpad 的 `nav-variants.png`。
- signed physical-device build：`BUILD SUCCEEDED`，已 `devicectl` 覆盖安装到真机“龙”。
  **自动启动被拒（`RequestDenied`，设备处于锁屏）**，安装本身成功，解锁后手动打开即可。

Exact next task: 在真机上解锁后打开，核 18pt 的二级导航标题在窄屏上会不会和两侧图标挤到一起
（目前是单行截断）。

## 新组件：Scroll button 滑动确认条（2026-09-04）

- 新增 `NvwaScrollButton`（`ios/Nvwa/Sources/Nvwa/Components/NvwaScrollButton.swift`），
  对应组件稿 `2243:704` 的 Start / Scrolling / Finish 三个变体——它们是同一个手势的
  三个瞬间，不是三个独立状态，所以做成一个组件而不是三个。
- 几何：345×56 胶囊轨道（`BG/Vessel`），56pt 圆形滑块，行程 = 宽度 − 56（稿子上是 289）。
  文案 `B-M Regular` + `Text/Secondary` 居中在整条轨道上。已滑过的轨迹是 `Alpha Blue 10`，
  **右端对齐滑块的右沿而不是中心**（稿子里滑块在 138、轨迹宽 194 = 138 + 56）。
- 滑块直接复用 Key Feature 的 `Send`（56 容器 / 28 字形），稿子把整枚实例转了 -90° 让
  箭头指向滑动方向——代码里对应 `.rotationEffect(.degrees(90))`。第一版忘了转，截图里
  箭头朝上，已修。Finish 态把箭头换成 24pt 白色菊花（原生 `ProgressView`）。
- 稿子没画、由代码定的两条：拖过 90% 行程才算确认；确认后滑块**留在右端**不弹回——
  不可撤销的操作弹回去会让人以为没生效。宿主把 `isLoading` 置回 `false` 才回到 Start，
  这条路径是「失败重来」。
- 拖拽对 VoiceOver 不可用，所以整条对外是一个按钮，双击等价于滑到底。
- 目前只进了组件库和目录页，**没有接到任何产品页面**——需要它确认哪个操作请告诉我。

验证结果：

- Nvwa SwiftPM：35 tests passed，0 failures（新增 scroll button 几何一条）。
- generic iOS Simulator `build-for-testing`：`TEST BUILD SUCCEEDED`。
- iPhone 17e 模拟器：目录页新增 “Scroll button” 一节，Start / Finish / Disabled 三态
  与稿子一致；截图 scratchpad 的 `scroll-button.png`。Scrolling 中间态无法用 simctl
  注入手势，靠单元测试锁住轨迹公式（138 + 56 = 194）与 Finish 态的整幅铺满间接验证。
- 本轮未做真机安装（组件尚未出现在任何产品页面，装上去也只能在调试目录页看到）。

Exact next task: 确定 Scroll button 用在哪个操作上（候选：删除持仓、清空数据这类不可撤销的），
再接进产品页面并在真机上试手感。

## V2.1.0 第一阶段：资金账本基础（2026-09-05）

- 新增 `LedgerEntry` schema 3 与按资产平衡的 postings。支持 deposit、expense、buy、sell、
  Earn subscribe/redeem、interest payout、opening balance；所有用户账户禁止负余额。
- 买卖标的固定进出 Trading，结算现金固定从 Exchange Spot 扣除/返回，且仅允许 USD /
  USDT / USDC；实际数量、成交价和手续费进入不可变流水，投影计算 Trading 成本。
- 新增 `EarnProduct`：法币/稳定币从 Exchange Spot 申购，Crypto 从 Trading 申购；股票和
  ETF 被领域层拒绝；定期强制单利；复利利息只有在 payout entry 产生时才加入 Earn 本金。
- 新增 guest/account 隔离的 `ledger-v3.json` 存储和 `LedgerBootstrapService`。旧 schema-v2
  Holding 首次升级生成一次 opening snapshot，保留交易单位成本，不伪造旧流水；迁移标记
  与账本原子保存，重复启动不会重复加钱。旧 Holding schema 仍为 2，云端兼容未改。
- `ios/Docs/LEDGER_MODEL.md` 已按最终设计重写，移除了旧草案里的换汇、股息、第四个 Tab 和
  “Crypto 不能 Earn”等冲突规则。
- Xcode Debug/Release 的 `MARKETING_VERSION` 已更新为 `2.1.0`；新文件已加入 SwiftPM 和
  Xcode targets。

验证结果：

- PawFolio SwiftPM：256 tests passed，0 failures。
- generic iOS Simulator `build-for-testing`：`TEST BUILD SUCCEEDED`。
- iPhone 17e（iOS 26.4）XCTest：`TEST SUCCEEDED`。
- `plutil -lint ios/PawFolio.xcodeproj/project.pbxproj`：OK。

Exact next task: 开始 V2.1.0 第二阶段 UI，先按 Figma 节点拉取 design context，并实现
Fiat / Spot 总览、Add asset、Pay 与 Transactions 入口；接入 `LedgerBootstrapService`，让
Portfolio 启动后真正以 schema-v3 ledger 投影展示余额。完成后在 iPhone 17e 截图逐项验收。

## V2.1.0 本地重构完成（2026-09-05）

- Portfolio 已切换到 schema-v3 投影：总资产汇总 Fiat / Spot、Trading 与 Earn，法币走实时
  汇率、股票/ETF/Crypto 走行情；PNL 按外部净投入与期初成本计算，走势图最后一点严格等于
  顶部总资产。缺行情或汇率时不伪造总数，并显示可恢复的状态提示。
- Figma `134:7230` 对应的 Add、Pay、Transactions、Trading、Earn 产品/持仓/申购/赎回/
  APY/派息路径均已接通 Nvwa。Pay 与申购使用滑动确认；所有弹窗继续遵守 `.full` / `.half`
  两档 `PawSheet` 规则；加载态使用原生圆形 `ProgressView`。
- Add 只允许法币和稳定币进入 Fiat / Spot，并支持 Exchange、Bank、Cash、Alipay、WeChat；
  股票、ETF、Crypto 必须通过 Trading 买入。交易资产类型来自搜索结果，不再猜代码；结算
  严格限制为 fiat USD 或 stablecoin USDT/USDC。
- 流水支持冲正：原记录和 reversal 永久保留，重复冲正、冲正冲正记录、非精确反向和会导致
  后续余额非法的冲正都会失败。Transactions 长按菜单及 VoiceOver action 均可发起并二次确认。
- Crypto Earn 在 Trading 与 Earn 之间按平均成本成比例搬移；APY 修改排到下一派息点生效，
  历史流水继续显示当时 APY。计息器分段处理本金与 APY 变化、冲正、上次真实派息及到期日；
  月付计划锚定产品起始日，不会经过二月后逐月漂移。
- 旧持仓迁移现在是全有或全无：零余额安全忽略，任何正余额迁移失败都不会写完成标记。
  guest 导入会合并不可变 entry/product ID、拒绝冲突且保留 guest 原件；即使 guest 只剩零余额
  历史、没有旧 Holding，也仍会要求用户明确选择。账户 scope 只在同步与 ledger 导入成功后切换。
- VoiceOver 源码与模拟器检查已完成：装饰图标隐藏，交易记录合并为一个可操作元素，金额继续
  使用等宽数字；亮/暗色截图保存在 `work/v2.1.0-qa-final/`，此前完整流程截图保存在
  `work/v2.1.0-qa/`。

验证结果：

- PawFolio SwiftPM：275 tests passed，0 failures。
- Nvwa SwiftPM：35 tests passed，0 failures。
- generic iOS Simulator `build-for-testing`：`TEST BUILD SUCCEEDED`。
- iPhone 17e（iOS 26.4）完整 XCTest：`TEST SUCCEEDED`。
- `plutil -lint ios/PawFolio.xcodeproj/project.pbxproj` 与 `git diff --check`：通过。

V2.1.0 已确认的本地范围没有剩余实现项。下一阶段若启动，是独立的云端 ledger schema、RLS、
冲突协议与 Web/多端兼容设计；不得把 schema-v3 直接塞进现有 Supabase `holdings.payload`。

## V2.1.0 像素审计与修复（2026-09-05）

按 Figma `134:7230` 对 V2.1.0 全部 44 帧做了一轮像素审计：24 帧逐节点拉
`get_design_context` 比对数值，另外 20 帧是同一 authored component 的状态变体，
在其母版上已逐项核对。完整记录见 `work/v2.1.0-pixel/AUDIT.md`。

修复了 11 项，其中三项是结构性的：

- **资产选择器缺整套结构**（`154:10266`）：首字母分组、A–Z 索引条、行分隔线、
  32pt 圆标 0.5pt 描边、End 收尾全没有。新增 `PawAlphabeticalList` 从汇率页
  `CurrencyPickerView` 抽出共用，两处「Add Currency」现在同源。
  注意 `PawSheet` 会把 content 再包一层 `ScrollView`，带索引条的列表不能套在它里面
  （内层拿不到高度，索引条会被顶出屏幕），要像 `CurrencyPickerView` 那样自己拼
  `NvwaModalHeader` + `.pawSheetPresentation(.full)`。
- **设计里的单选弹层被实现成了原生 `Menu`**（Account / Type / Currency /
  Payout Frequency 四处）。新增 `PawSingleSelect`（弹层 + 字段两件套）按 `154:10896`
  实现，`ledgerMenuField` 已删除。**以后别再用 `Menu` 顶这个组件**，系统菜单没有图标、
  没有勾、也不是弹层。
- **两个明细页此前完全没实现**：Earn 产品明细 `158:16698`、Trading 资产明细 `158:18023`。
  已补 `LedgerEarnDetailView` / `LedgerTradingDetailView`，总览的 Trading / Earn 行
  和 Earn 卡片本体改为进明细页（卡片自己的 Subscribe / Redeem 按钮仍直达弹层）。
  行情卡复用 `MarketQuote.series` + `PawSparkline`，没有新增数据管线。

其余：Add 复核右列字体、Earn 卡片间距、Trading 收益率的涨跌配色、流水明细行字号与
染色范围、流水分隔线内缩、空态文案居中、申购弹层的「<频率> Profits」行（估算规则落在
`EarnInterestCalculator.projectedPayout`，带 4 个单测）、Edit 弹层补 Name 字段与 `%` 单位。
另修两处数值格式：法币余额和 Total Values 之前用 `amount()`（2…8 位）会打出浮点残差。

验证结果：

- PawFolio SwiftPM：279 tests passed，0 failures。
- Nvwa SwiftPM：35 tests passed，0 failures。
- generic iOS Simulator `build-for-testing`：`TEST BUILD SUCCEEDED`。
- iPhone 17e（iOS 26.4）完整 XCTest：`TEST SUCCEEDED`。
- `plutil -lint ios/PawFolio.xcodeproj/project.pbxproj` 与 `git diff --check`：通过。
- 截图在 `work/v2.1.0-pixel/`。验证用的三个临时 DEBUG 钩子已全部删除。

Exact next task: 等用户确认 `AUDIT.md`「待你确认」那 10 条，其中 4 条会动资金规则或
Nvwa 组件，不能自己定：Buy/Sell 分段控件选中色该不该用涨跌色（会改 Nvwa 组件）、
交易手续费是百分比还是绝对额（会改记账口径）、Earn 产品「下架」流程要不要做
（`155:16379`，领域层没有 delist）、赎回要不要支持选目标账户（`155:13816`）。

## V2.1.0 产品规则确认与图标修正（2026-09-05，用户当面定的）

用户回了上一轮 `AUDIT.md` 里的待确认项，按回复落实：

- **账户图标修正。** 设计 `154:10896` 里五个账户各有各的图标，实现却只分了三档、
  还把 Bank 和 Exchange 弄反了。正确映射：Bank=`bank-card-line`、Cash=`cash-line`、
  **Exchange=`bank-line`**、Alipay=`alipay-line`、Wechat=`wechat-pay-line`。
  新增 `IconBankCard` / `IconWechatPay` 两个 imageset，SVG 由设计文件 `exportAsync`
  导出，不是照记忆手写 path。两处重复的映射函数已合并成一个。
- **Buy / Sell 按钮收进 Nvwa。** 新增 `NvwaButtonKind.buy` / `.sell`，底色走
  Market Buy / Market Sell。交易页原本是手搓 `Button` + `Capsule`，已改用组件。
  同时给 `NvwaSegmentControl` 开了 `selectedTint`，交易页的 Buy/Sell 分段按涨跌色显示
  （设计 `154:12261` 选中的 Sell 是红的）。
- **手续费口径：金额 × 费率。** 用户填费率（默认 0.06%，尾部 `%`），绝对额由
  `LedgerTradeDetails.feeAmount(grossValue:ratePercent:)` 算出，输入框下面实时回显，
  账本里仍存绝对额。
- **下架范围（已被本文后续「V2.1.0 活期交互与下架修复」覆盖）。** 当时 `EarnProduct.canDelist` 只对 `.structured` 为真。
  `more` 菜单改成设计 `155:16160` 的「Manage Earn」单选弹层，Delist 只在结构化产品上出现；
  确认走 `155:16379` 的 Warning 弹层（48pt 插画 + 滑动确认 + 成功 toast）。
  下架 = 本金全额退回来源账户 + 打 `delistedAt` 标记；**产品记录不删**，
  历史流水还要靠它显示当时的名字和 APY。`delistedAt` 是可选字段，旧快照照常解码（有测试）。
- **定期只能全额赎回。** `EarnProduct.redeemsFullAmountOnly` 对 `.fixed` 为真，
  赎回态不给输入框和滑杆，直接摆出全额。
- **赎回不给选账户。** 稳定币只在 Exchange 来回、其他数字货币只在交易账户来回，
  账户是推导出来的。设计 `155:13816` 的「To Account」字段**故意不实现**，
  当前行为（固定回来源账户）就是对的。

顺带修掉的：`updateProduct` 之前只搬运 APY，Edit 弹层新加的 Name 会被静默丢弃，
现在名字/备注/结构化参数一起生效（APY 仍走下个付息点排期）；Pay 的 Balance 提示行
去掉多余的币种代码；`CurrencyPickerView` 行高从钉死的 64 改成设计的 `py16`；
账本各卡片的描边从 `.stroke` 改成 `.strokeBorder`，1pt 全画在圆角内侧。

新增测试：`LedgerTradeAndEarnRuleTests`（手续费三例、下架/全额赎回的能力判定、
旧快照解码）、`NvwaTokenTests.testBuyAndSellButtonsUseMarketColours`。

验证结果：

- PawFolio SwiftPM：285 tests passed，0 failures。
- Nvwa SwiftPM：36 tests passed，0 failures。
- generic iOS Simulator `build-for-testing`：`TEST BUILD SUCCEEDED`。
- iPhone 17e（iOS 26.4）完整 XCTest：`TEST SUCCEEDED`。
- `plutil -lint` 与 `git diff --check`：通过。
- 截图：`work/v2.1.0-pixel/account-select.png`、`trade-sell.png`、`trade-fee.png`。
  验证用的临时 DEBUG 钩子已全部删除。

Exact next task: 剩两条小的没定，都不影响功能——总览币种 chip 目前按代码字母序
（CNY 在 USD 前），设计几帧画的是 USD 在前但没写排序规则；以及设计
`155:16083` 的 Payout Frequency 选项带时间锚点（`16:00, Daily`），领域层目前没有
派息时刻的概念，标签只有 `Daily` / `Weekly` / `Monthly`。

## 排版行高的规范核查（2026-09-05）

拉 Nvwa 设计系统的 `getLocalTextStylesAsync()` 和代码里的 token 逐个比对。

**定义层没问题**：Figma 15 个 text style ↔ 代码 15 个 token，字号/行高/字距/字重全部一致。
行高也不是只存着不用——`NvwaTypographyToken` 把它换算成 `lineSpacing`（行间补全额差额）
和 `halfLeading`（首尾各补一半），因为 SwiftUI 没有「行高」这个属性。两条测试钉着：
`testAllFigmaTypographyTokensRemainExact`（逐 token 断言，含行高）和
`testTypographyLineBoxRestoresFigmaLineHeight`（断言行盒换算）。

**缺的是用法规范**：`.nvwaTextStyle(token)` 才给全「字号+字距+行高」三件，而
`Nvwa.bodyMedium` 这类简写常量只返回 `Font`。统计下来 57 处走 modifier、100 处走简写，
简写里 83 处手动补了 `.tracking(...)`，**17 处没补，字距被静默丢掉**（15 处在
`LedgerPortfolioView.swift`，2 处在 `PortfolioView.swift`）。已全部改走 `nvwaTextStyle`。

规则补进了 `AGENTS.md`（设计方向那节）和 `ios/Nvwa/FIGMA_TOKENS.md`
（新增「行高和字距怎么落到代码里」，含 `linesFillLineHeight` 什么时候传 false）。

**记一个坑**：简写 `Nvwa.bodyLarge` 指向的是 `B-L Semi Bold`，不是 `B-L Regular`；
要 Regular 那档得写 `Nvwa.Typography.bodyLarge`。

验证：PawFolio 285 tests、Nvwa 36 tests、iPhone 17e XCTest `TEST SUCCEEDED`、
`git diff --check` 通过。

## V2.1.0 活期交互与下架修复（2026-09-05）

- 活期申购/赎回的金额滑杆会用带千分位的 `amount()` 回填输入框，确认态却直接用
  `Double` 解析；大额会因 `1,000` 解析失败而把 `Slide to Confirm` 锁死。现在改用
  `AmountInput.text` 回填、`AmountInput.parse` 解析，并拒绝非有限数。
- `NvwaScrollButton` 的拖拽改用 global coordinate space，避免滑块本身移动时 local
  translation 抖动。模拟器实际拖动确认：金额滑杆回填 `6998.8621974`，确认条从禁用态
  变为可操作，未到阈值松手后正常回弹。
- 最新产品决策覆盖了稍早的「仅结构化可下架」：活期、定期、结构化三种 Earn
  现在都显示同一套 Delist 流程。下架将当前 Earn 完整余额一次性赎回：法币/稳定币回
  Exchange Spot，Crypto 回 Trading，Crypto 平均成本也按原比例转回。
- 赎回流水和 `delistedAt` 现在在同一次原子保存中落盘，避免「钱已退、产品却没下架」的半成功状态。
  历史申购、赎回、利息流水与产品记录全部保留，已有收益不被删除或重算。

验证结果：

- PawFolio SwiftPM：285 tests passed，0 failures。
- Nvwa SwiftPM：36 tests passed，0 failures。
- generic iOS Simulator `build-for-testing`：`TEST BUILD SUCCEEDED`。
- iPhone 17e（iOS 26.4）XCTest：335 tests passed，0 failures；新增的 Fiat 和 Crypto
  下架回账测试均通过。
- 模拟器视觉/交互复核：活期 Manage Earn 已显示 Delist，申购金额滑杆与确认条可用。
  截图见 `work/v2.1.0-ui-fix/flexible-manage-delist.png` 和
  `work/v2.1.0-ui-fix/flexible-subscribe-enabled.png`。
- `git diff --check`：通过。

Exact next task: 在真机上用一笔可回滚的小额活期完整走一次申购、赎回和下架，
复核滑动手感与账户变化；本轮没有执行真实下架，避免改动现有 QA 数据。

## 法币无余额时的总览空态（2026-09-05）

用户在真机上发现：有 Trading 持仓但法币/稳定币余额为 0 时，总览会画出一个**空的
描边方框**（法币卡没内容），上面那排动作 pill 还在。

`accountContent` 之前只在「法币、Trading、Earn 三者全空」时才走 `emptyState`，
所以只有法币空的情况会掉进有内容的分支。现在把「动作 pill + 法币卡」抽成
`fiatSpotSection`，`model.spotBalances.isEmpty` 时整组换成设计 `154:9705` 的空态
入口卡（72pt 图标圆底 + Add your first currency to continue + 整宽 Add）。

**pill 一起藏掉是用户明确要求的**，设计的空态帧里也确实没有这排 pill。
功能没丢：Trading / Earn 区块照常显示，它们的区块标题本身就是进对应页面的入口。

验证：PawFolio SwiftPM 285 tests、iPhone 17e XCTest 334 cases `TEST SUCCEEDED`、
`git diff --check` 通过；截图 `work/v2.1.0-pixel/no-fiat.png`；已装到真机。

> 跑模拟器 XCTest 前记得先 `xcrun simctl terminate booted com.jiujiucat.pawfolio`。
> 测试会克隆模拟器，手动起着的那个 app 残留会让整轮 `TEST FAILED`，
> 看起来像代码回归，其实不是。

## 从持仓进交易表单要预填标的（2026-09-05）

用户真机上发现：从已买入的资产点进明细页、再点底部「Trading」，开出来的是空的
交易表单，还要再搜一次。

查了设计的原型连线（`158:18023` 的 Primary Button `158:18078`）：它连到的是
**`159:19567`「Buy Assets - 数字货币」——资产字段已经填好 BTC / Bitcoin 的那一帧**，
不是空表单 `154:11181`。所以实现的 `onTrade: { route = .trading }` 丢了标的。

改法：`LedgerRoute.trading` 带上 `preselected: AssetSearchResult?`，明细页的 CTA 把
当前标的还原成搜索结果传进去（账本只存代码不存全名，名字先查 `offlineFallbacks`，
查不到就只显示代码）。`LedgerTradeForm` 新增 `preselected:` 参数初始化 `selectedMarket`。

顺带按 `159:19567` / `154:12261` 把资产字段改成两行：代码 B-M Regular，
全名 C-2 Regular 走 secondary（原来是 `"BTC · Bitcoin"` 一行拼接）。

验证：PawFolio 285 tests、iPhone 17e XCTest `TEST SUCCEEDED`、`git diff --check` 通过；
截图 `work/v2.1.0-pixel/trade-preselected.png`；已装到真机。

> 顺带记：`159:19567` 这帧还露出交易表单其余部分和当前实现的差距——设计是
> Investment（带 Balance 提示）/ Total Investment / Buy Price / Amounts 四个联动字段
> （`154:12261` 注释「sell price 和 sell value 需要联动」），还有 `Balance Inefficient`
> 的报错态，CTA 文案是「Buy BTC」带标的。实现目前是 Amounts / Execution Price /
> Fee / Settlement，CTA 只有「Buy」。**这块没动，等确认。**

## Add Currency 常用稳定币（2026-09-05）

- V2.1.0 账本的 Add Currency 选择器新增独立 `Favorites` 区，固定置顶 USDT / USDC；
  名称按设计分别为 `Tether USD` / `Circle USD`。稳定币不塞进 `CurrencyCatalog.all`，
  因此不会污染只含法币的汇率目录和 A–Z 分组。
- `PawAlphabeticalList` 增加可复用的顶部内容槽；字母索引仍只跳转法币分组，Favorites
  在搜索时保持可见。
- USDT / USDC 原始 96×96 SVG 从用户指定的 Figma Logo 文件
  `1GfyhXAMaIIJhOv2tvL4rU` 中的 `usdt-tether/usdt-icon`、
  `usdc-usd-coin/usdc-icon` 导出，作为 `LogoUSDT` / `LogoUSDC` 随 App 打包。
  账本中的选择器、余额 chip、资产行等统一通过 `assetMark` 使用这两个品牌图。
- 后续数字货币 Logo 可继续把该 Figma 文件作为受控来源：导出、审阅后进入 Asset
  Catalog；App 不在运行时依赖 Figma URL。长尾币仍保留现有远程 Logo 管线。

验证结果：

- PawFolio SwiftPM：286 tests passed，0 failures。
- generic iOS Simulator `build-for-testing`：`TEST BUILD SUCCEEDED`。
- iPhone 17e（iOS 26.5）XCTest：336 tests passed，0 failures。
- 模拟器视觉/交互复核：Favorites、两个品牌 Logo、法币 A–Z 列表均正常；点击 USDT
  能正确回填 Add 表单。截图：`work/qa/v2.1-add-currency-stablecoins.png`。
- 两个 SVG 通过 `xmllint`，Asset Catalog 通过 `actool` 编译，`git diff --check` 通过。

Exact next task: 按用户后续反馈继续修 V2.1.0 UI；新增数字货币时优先从上述 Figma Logo
文件导出并版本化进 Asset Catalog。

## 交易表单按设计注释重做（2026-09-05）

用户指出买卖逻辑和设计对不上。按 `159:19567`（买）和 `154:12261`（卖）里的注释重做了
`LedgerTradeForm` 的字段模型。

**之前**：Amounts / Execution Price / Fee / Settlement（分段控件）四个互不相干的字段。
**现在**：

- 买入：Investment（余额提示带币种切换，注释「可以切换货币来源，购买按照美元换算」）
  → Buy Price → \*Amounts → Fee → Note，CTA「Buy BTC」走 Market Buy。
- 卖出：Sell Amounts（余额提示固定 trading，注释「BTC 只能在 trading 账户」，**不给选**）
  → Sell Price（单位可切 USD / USDT / USDC，注释「可以选择卖出 USD 或者 USDT，USDC」）
  → Sell Value → Fee → Note，CTA「Sell BTC」走 Market Sell。
- **三者联动**（两帧的注释都写着「price 和 value 需要联动」）：数量 × 价格 = 成交额。
  改数量或成交额时补另一个；改价格时按 `anchor`（用户最后手动改的是数量还是成交额）
  保住那一个、重算另一个——这样「我要 1.2 个 BTC」和「我要花 8 USD」两种意图都不会被
  改价格冲掉。`isSyncing` 挡住互相触发的回环。
- 结算币选择从原来的分段控件改成设计里的位置：买入在余额行的 chevron，卖出在价格单位的
  chevron，弹层复用 `PawSingleSelectSheet`。
- 余额不足时输入框走 `.error` 并提示。设计上那行文案是 `Balance Inefficient`，
  应该是 Insufficient 的笔误，实现用的是 `Insufficient balance.`。
- 余额格式按资产分：结算币两位小数，持仓数量走 2…8 位（`2.343523` 不能显示成 `2.34`）。

账本没动：`LedgerEntry.buy/sell` 仍然只吃 quantity + unitPrice + fee，成交额是表单层
推导出来的输入辅助，不进流水。

验证：PawFolio SwiftPM 286 tests、iPhone 17e XCTest `TEST SUCCEEDED`、`git diff --check`
通过；截图 `work/v2.1.0-pixel/trade-buy.png`、`trade-sell.png`；已装到真机。

> 仍和设计不同的一处：手续费字段的 label 设计里写的是中文「手续费」，
> 而同屏其余文案都是英文，实现保持 `Fee`。

## 交易表单的图标、结算币弹层与两个交互 bug（2026-09-05）

用户在真机上提的四项，全部按设计改掉：

- **下拉箭头用错了资源。** 设计里是 `arrow-down-s-fill`（实心三角），仓库里只有
  `arrow-down-s-line`（细箭头）。新增 `IconArrowDownSFill`（SVG 从设计文件导出），
  V2.1.0 的四处下拉换过去：`PawSingleSelectField` 和交易表单的三处。
  V1 的 `HoldingEditorView` / `PortfolioView` **没动**，它们是照各自节点验收的。
- **结算币弹层缺 logo 和金额。** 设计 `158:18414` 标题是 `Currency`，每行是
  24pt 资产 logo + 「余额 + 代码」（B-L Semi Bold），选中带勾。之前只列了币种代码。
- **卖出余额提示的 logo 不对。** `assetMark` 只认法币旗帜和稳定币 logo，BTC 这类
  加密资产会掉进首字母圆点的兜底。改用 `PawAssetLogo`（走 CMC 那套解析）。
  余额数字也从两位小数改成 2…8 位，`2.343523` 不再显示成 `2.34`。
- **BUG：切换买卖时数据被带过去。** 买入的 Investment 和卖出的 Sell Amounts 是完全
  不同的量，之前 `side` 变了但三个联动字段原样留着。加 `resetAmounts(for:)`：
  清空数量/价格/成交额/滑杆，锚点回到这一侧默认先填的那个（买入先填钱，卖出先填币）。
  手续费率和备注与买卖无关，保留。
- **BUG：余额不足仍然能下单。** `exceedsBalance` 之前只驱动输入框标红，`submit()`
  和 CTA 都没拦，于是能一路走到滑动确认。现在 CTA 直接 `.disabled`，`submit()` 里
  也兜一层并把焦点移到出问题的字段。买入侧比的是「成交额 + 手续费」而不是成交额本身——
  账本禁止负余额，卡在边界上会被账本拒绝，不如在表单就拦住。

验证：PawFolio SwiftPM 286 tests、iPhone 17e XCTest `TEST SUCCEEDED`、
`git diff --check` 通过；截图 `work/v2.1.0-pixel/settlement-picker.png`、`sell-over.png`；
已装到真机。

## Top 100 Crypto / 股票 Logo 本地化（2026-09-05）

按用户要求，将 2026-09-05 市值快照中的 Crypto 前 100 与全球上市公司市值前 100
写死进 App Bundle，共 200 个 Asset Catalog imageset。股票榜排除了未上市的 SpaceX，
并顺延补入第 101 名 `TMUS`，确保仍为 100 家可交易上市公司。

- 新增 `Domain/AssetLogoCatalog.swift`，集中记录资产类型、排名、快照日期、代码、资源名、
  来源和可用的 Figma node ID，避免排名和图片来源散落在 UI 层。
- 81 个资源直接来自用户提供的 Figma Logo 文件 `1GfyhXAMaIIJhOv2tvL4rU`
  （Crypto 72、股票 9）；Figma 教育版 MCP 随后达到调用额度，其余缺口使用 CoinGecko
  与 CompaniesMarketCap 的公开品牌资源补齐并随 App 打包。运行时不依赖 Figma。
- `AssetLogoStore` 的解析顺序改为：本地 Top 100 → 既有远程源 → 首字母占位。
  缓存键加入资产类型，避免同代码的股票和 Crypto 串图；支持 `GOOGL → GOOG`、
  `BRK.B → BRK-B`、`RNDR → RENDER` 等常见别名。
- Yahoo Finance 没有稳定、公开、可直接按 symbol 获取公司 Logo 的 API，因此长尾股票
  继续使用现有 Parqet 兜底；长尾 Crypto 继续使用 CMC / CoinCap。行情数据的 Yahoo
  管线不受影响。
- QA 联系表：`work/qa/v2.1-top100-crypto-logos.png`、
  `work/qa/v2.1-top100-stock-logos.png`。

验证结果：

- PawFolio SwiftPM：289 tests passed，0 failures。
- generic iOS Simulator `build-for-testing`：`TEST BUILD SUCCEEDED`。
- iPhone 17e 完整 XCTest：340 tests passed，0 failures。
- Logo 专项 XCTest：14 tests passed；200 个资源均可从 App Bundle 加载，BTC 本地命中时
  网络请求数为 0。
- `project.pbxproj`、Asset Catalog JSON 和 `git diff --check` 均通过。

Exact next task: 按用户后续反馈继续修 V2.1.0 UI；以后增加主流资产 Logo 时优先从上述
Figma 文件导出并更新 `AssetLogoCatalog`，市值排名变化时按新的明确快照整体更新。

## MSTR / STRC 本地 Logo（2026-09-05）

用户提供 `mstr-icon.svg` 与 `strc-icon.svg`，已原样加入 Asset Catalog：
`AssetLogoStock_MSTR`、`AssetLogoStock_STRC`。两者不属于既有 Top 100 市值快照，因此登记在
`AssetLogoCatalog.supplementalStocks`，不会改变 100 条快照的排名与数量语义。

- MSTR、STRC 现在都走本地 Bundle 优先，不再等待 Parqet 远程兜底。
- SVG 保留 96×96 viewBox、原始品牌配色和 vector representation；与用户下载文件逐字对比
  一致，并通过 `xmllint`。
- 测试覆盖代码映射、Asset Catalog 实际加载，以及本地命中不产生网络请求。

验证：SwiftPM 292 tests passed；generic iOS Simulator `build-for-testing` 成功；iPhone 17e
Logo 专项 XCTest 15 tests passed；`git diff --check` 通过。

Exact next task: 按用户后续反馈继续补充本地资产 Logo 或修复 V2.1.0 UI。

## 卖出 logo 透明 + Add Earn 表单按设计重做（2026-09-05）

- **卖出资产 logo 发灰**：余额提示行整个包在 `Button` 里，卖出侧来源固定（`onPickSource`
  为 nil）就 `.disabled`，**SwiftUI 会把禁用按钮的整个 label 调暗**，logo 跟着半透明。
  改成没有 picker 时不套 Button，直接画内容（`balanceHint(_:mark:showsChevron:)`）。
- **Add Earn 表单**按 `155:15425`（Flexible）/ `155:15867`（Fixed）/ `155:15932`（固定票息）
  三帧重做，之前是一套字段硬套三种类型：
  - 标题 `Add Earn Product` → **`Add Earn`**；APY 补 `%` 单位。
  - **定期填的是天数**（`*Days` + `D`），不是选到期日；到期日由「今天 + 天数」推出来。
  - 「定期只有单利」「固定票息只有单利」——这两类**根本不显示** Interest Calculation，
    之前是显示出来再置灰。定期也不显示 Payout Frequency（到期一次性付息）。
  - **固定票息的条款拆成两个必填价格**：`*Strike Price` / `*Knock-Out Price`，
    之前是一个自由文本 `Product Parameters`。`EarnProduct` 新增
    `strikePrice` / `knockOutPrice` 两个可选字段；卡片和明细页也改成两行分别显示
    （设计 `154:13078` / `154:13088`），旧记录仍读那段自由文本。
  - `validate()` 对固定票息改成「两个价格」或「旧自由文本」二选一——
    只认新字段会让第一版写下的账本在 `load` 时整个读不出来。

新增测试：`EarnStructuredPriceTests`（价格字段往返、缺字段的旧快照仍能解码并通过校验）。

验证：PawFolio SwiftPM 291 tests、iPhone 17e XCTest `TEST SUCCEEDED`、
`git diff --check` 通过；截图 `work/v2.1.0-pixel/earn-form-{flexible,fixed,structured}.png`；
已装到真机。

> 仍和设计不同、待确认的文案：设计里 Type 这一档在表单上叫 **Fixed Coupon Rate**，
> 在选择弹层 `158:17517` 里叫 **Structured Products**，实现统一用 `Structured`；
> Name 的占位符设计写的是中文「Ex. USD固定票息」；Payout Frequency 的选项设计带
> **Hourly** 和时间锚点（`16:00 Friday, Weekly`），领域层目前没有小时档、也没有派息时刻。

## 理财资产选择改成 Assets（2026-09-05）

用户把设计里的 Currency 改成 **Assets**（能理财的不只稳定币），选项和逻辑按
`173:21473`「Select Assets」。

- 表单字段 `Currency` → **`Assets`**，点开新的 `LedgerEarnAssetPicker`。
- 弹层按注释「样式复用 currency 的弹窗」：标题 `Select Assets`、顶部搜索、
  首字母分组 + A–Z 索引条 + End，复用 `PawAlphabeticalList`。
- 选项 = **`AssetLogoCatalog.crypto` 市值前 100** + **全部法币**。
  USDT / USDC 在那份清单里算 crypto，但领域层当稳定币（申购账户不同），
  这里按领域层分类。logo 走 `PawAssetLogo` → `AssetLogoStore` → `AssetLogoCatalog`，
  本地命中不发网络请求。
- 之前保存时靠 `["USDT","USDC","DAI"]` / `["BTC","ETH","SOL"]` 两个写死数组判资产类型，
  换成从选项清单里查。

**股票不收进来——用户 2026-09-05 已确认。** 设计 `173:21473` 的注释要求
「数字货币和股票前 100 名以及所有法币」，但股票 / ETF 继续被 `LedgerAsset.canEnterEarn`
拒绝（`LEDGER_MODEL.md` 的资金规则 + `testStocksCannotEnterEarn`）。这条已作为
**已确认的设计注释覆盖**记进 `LEDGER_MODEL.md`。`AssetLogoCatalog.stocks` 那 100 只
logo 已打包，将来放开的话改的是资金规则和那条测试，不是 UI。

验证：PawFolio SwiftPM 292 tests、iPhone 17e XCTest `TEST SUCCEEDED`、
`git diff --check` 通过；截图 `work/v2.1.0-pixel/earn-assets-picker.png`；已装到真机。

> 协作提示：`PawAlphabeticalList` 这轮被另一个会话加了 `topContent` 槽
> （Add Currency 用来放常用币），签名多了一个泛型。我是**适配**它而不是回退，
> 新调用点要传 `showsTopContentWhenSectionsEmpty:` 和 `topContent:`。

## Earn 申购 / 赎回 / 明细按新设计重做（2026-09-05）

设计更新后重新拉了 `155:13936`、`158:17298`、`155:13816`、`158:17968`、
`158:16698`、`158:17137`、`158:17375`。这轮改的主要是**逻辑**：

- **定期和结构化不能加仓。** 注释：「定期产品不能加仓，只能单独申购」「结构产品不能加仓」。
  新增 `EarnProduct.allowsAdditionalSubscription`（只有活期为真），明细页据此决定
  底部是「Subscribe More + Redeem」还是只有一颗 Redeem。**Redeem 单独出现时仍是
  Secondary 按钮**（查过 `158:17375` / `158:16698` 的填充色，不是 Primary）。
- **赎回要过确认弹层**（设计 `158:17968`）：标题 `Redeem Confirmation`、26/32 的金额、
  一段说明、滑动确认。新增 `LedgerRedeemConfirmationSheet`。
  文案按资产实际去向说：法币/稳定币回 Exchange、数字货币回 Trading
  （设计写死的是 Exchange，那只是法币那一档，见 `158:17375` 注释）。
- **定期提前赎回没有收益。** 新增 `EarnProduct.forfeitsInterestOnEarlyRedemption`，
  确认弹层对定期显示「Redeeming before maturity forfeits the interest for this term.」，
  其余显示「Accrued interest will remain unaffected.」。
- **明细页字段按三类分开**：定期是 Term / Maturity Date → APY / Days /
  **Total Profits After Maturity** / Total Investments（没有派息频率和 Next Time Payout）；
  活期和结构化保持 Payout Frequency + `<频率> Profits` + Next Time Payout。
- **申购弹层**：活期多了 Time / Investment 两行开头、Next Time Payout 收尾
  （设计 `155:13936`）；定期是 APY / Total Profits After Maturity / Days / Maturity Date
  且标题为 `Subscribe <产品名>`（`158:17298`）；赎回态不显示这组汇总（`155:13816`）。
- **Select Assets 把 USDT / USDC 置顶**（用户要求 + 设计的 Favorites 组），
  复用 codex 加的 `topContent` 槽，和 Add Currency 同一套写法。搜索时不置顶。
  稳定币全名以 `StablecoinCatalog` 为准（Tether USD / Circle USD）。
  行尾**不画选中勾**——设计没有，而且会和右侧 A–Z 索引条叠在一起。

新增测试：`testOnlyFlexibleProductsAllowAdditionalSubscription`、
`testOnlyFixedProductsForfeitInterestOnEarlyRedemption`。

验证：PawFolio SwiftPM 294 tests、iPhone 17e XCTest `TEST SUCCEEDED`、
`git diff --check` 通过；截图 `work/v2.1.0-pixel/earn-assets-favorites.png`；已装到真机。

> 关于 `155:13936` 那条 Hint 的「币价盈亏和利息收益分开计算」：用户 2026-09-05 明确了
> 口径——**申购什么资产，利息就是什么资产**，所以理财只管 APY、不管币价，两者天然分开。
> 核对下来实现已经符合：`interestPayout` 记在 `product.asset` 上，
> `EarnInterestCalculator` 只吃「数量 × 年化 × 时间」，没有行情入参。
> **明细页不需要专门展示价格**（用户确认），但币价波动要体现在总资产上——
> Earn 账户是 user-controlled，`LedgerValuation` 已按行情计价并计入总额。
> 规则写进了 `LEDGER_MODEL.md`，并补了两组测试钉住
> （`EarnInterestIsDenominatedInProductAssetTests` /
> `EarnPrincipalIsValuedAtMarketTests`，后者含「缺行情时总额为 nil」）。

## 三处视觉/交互微调（2026-09-05）

- **两个确认弹层的说明文字改成 `text/secondary`**（下架 Warning、赎回确认）。
- **首页 Trading / Earn 行的 logo 从 20pt 改成 24pt**；Earn 那颗圆底里的字形按比例
  从 12 跟到 14。明细页 Name 行那颗 20pt 的没动（那是另一处设计）。
- **计算页去掉右上角的「新增持仓」操作**（用户 2026-09-05）。

去掉计算页那个入口以后，`newPositionRequest` 整条链路就没有生产者了，一并清掉：
`RootTabView` 的 state、传给 `LedgerPortfolioView` 的 `addAssetRequest` 绑定、
`CalculatorView.onAddPosition`，以及 `LedgerPortfolioView` 里那个
`.onChange(of: addAssetRequest)`。Add 流程仍然可以从总览的 Add pill 和空态卡进入。

顺带把 `PawTopNavigation` 的右上角操作改成**可选**：`trailingIcon` 现在是 `Image?`，
没有右上角操作的页面直接不传，不用再为了隐藏而硬塞一个图标。原来的 `showsTrailing`
保留给「有图标但当前状态要藏」的情况（未登录的 PawFolio 页）。

验证：PawFolio SwiftPM 300 tests、Nvwa 36 tests、iPhone 17e XCTest `TEST SUCCEEDED`、
`plutil -lint` 与 `git diff --check` 通过；截图 `work/v2.1.0-pixel/overview-logos-24.png`、
`calculator-no-trailing.png`；已装到真机。

## Earn 的 Holding 页（2026-09-05）

之前 Holding 页只是把 Product 页的产品大卡片换个数据源渲染，和设计 `155:13496` 完全不是
一回事。按设计重做：

- **USD 汇总条**（`Frame 17`，注释「这里统一换算成USD」）：两块统计，
  `Daily (USD)` 和 `Total (USD)`，标签 12 Regular secondary、数值 18 Semi Bold 走 Market Buy。
- **紧凑持仓行**（343×80，p16 / 圆角 16 / 1pt 描边）：左边产品名 + APY，
  右边 USD 估值 + 已计提利息；点进去是明细页。不再用产品大卡片。
- **底部 CTA 两个页签都有**（`155:13496` 的 Bottom Action 同样是 Add Earn Products），
  之前只在 Product 页显示。

新增 `EarnInterestCalculator.dailyInterest`（本金 × APY / 365）和
`LedgerPortfolioViewModel.totalEarnDailyInterestUSD`。**注意它和 `projectedPayout` 不是
一回事**：后者算的是一个派息周期，周付产品的一天和一期差七倍。

顺带按 `155:13496` 的另一条注释「结构化理财只能全部赎回全部金额，不能赎回一部分或加仓」
把 `redeemsFullAmountOnly` 从「只有定期」扩到「定期 + 结构化」，只有活期能部分赎回。

### 本地化

这轮发现另一个会话新增了 `Localizable.xcstrings`（368 条），所以中文环境下界面已经是中文。
补了 5 条缺失的：`Holding` / `Product` / `Daily (USD)` / `Total (USD)` / `Next Time Payout`。

> **坑：`Text(someStringVariable)` 不走本地化**，只有字面量或 `LocalizedStringKey` 才会
> 去查目录。汇总条的 label 一开始是 `String` 参数，结果分段控件已经是中文、
> 它俩还是英文。把参数类型改成 `LocalizedStringKey` 才生效。以后往组件里传文案，
> 参数类型要用 `LocalizedStringKey`。

验证：PawFolio SwiftPM 301 tests、iPhone 17e XCTest `TEST SUCCEEDED`、
`git diff --check` 通过；截图 `work/v2.1.0-pixel/earn-holding.png`；已装到真机。

## 简体中文本地化首轮落地（2026-09-05）

已将 App 从“语言选项只换国旗”改成真正的运行时语言切换，当前覆盖 418 个
String Catalog 词条，其中 403 个可翻译词条均有简体中文；剩余 15 个是占位符、
金额格式、`PawFolio` 品牌名、`USD` 币种代码等故意保留的不可译项。

- `LanguagePreferenceStore` 继续使用旧偏好值 `zh` / `en`，对界面注入标准
  `zh-Hans` / `en` Locale；选择后立即切换，重启后保留。
- 新增 `Resources/Localizable.xcstrings` 和
  `Docs/LOCALIZATION_GLOSSARY.json`。术语表是后续新增词条的唯一中文基准，已覆盖
  持仓、交易、理财、申购、赎回、冲正、下架、派息、结算币种和账户去向。
- 金融口径固定为：Subscribe / Redeem = 申购 / 赎回，Reversal = 冲正，
  Settlement Currency = 结算币种，Fixed / Flexible / Structured = 定期 / 活期 /
  结构化产品，Exchange / Trading Account = 交易所账户 / 交易账户。
- 赎回和下架说明按资产类型表达真实资金去向；定期提前赎回明确“不享受
  本期利息”，活期和结构化产品明确“历史累计收益不受影响”，不再拼接半中半英的句子。
- 法币名称使用系统 ISO 4217 本地化名称，中文环境可直接用“美元”、“日元”等搜索。
- 修复动态字符串绕过 String Catalog 的问题：首页 `PNL` 标签与数值分离渲染，
  中文环境现显示“盈亏”，英文环境仍显示 `PNL`。
- 资产代码、产品名和用户输入内容按数据原值展示，不会被界面本地化擅自改写。

视觉检查覆盖了总览、计算、汇率、添加币种和语言选择弹层；截图位于
`/tmp/pawfolio-l10n-home.png`、`/tmp/pawfolio-l10n-calculator.png`、
`/tmp/pawfolio-l10n-currency.png`、`/tmp/pawfolio-l10n-currency-picker.png`、
`/tmp/pawfolio-l10n-language-sheet.png`。

验证：SwiftPM 308 tests passed；最终 generic iOS Simulator `build-for-testing` 成功；
`xcstringstool compile` 成功，并从编译后的 `zh-Hans.lproj/Localizable.strings`
确认 `PNL = 盈亏`、`Subscribe = 申购`、`Reverse transaction = 冲正交易`；
`git diff --check` 通过。最终 PNL 修复前的 iPhone 17e 全量 XCTest 成功；修复后重跑时
同时有另一个 `xcodebuild test-without-building` 占用 CoreSimulator，测试运行器启动失败
（`NSMachErrorDomain -308, server died`），并非测试断言失败。

Exact next task: CoreSimulator 空闲后重跑 iPhone 17e 全量 XCTest，再按交易、理财申购/赎回/
下架、持仓记录和账户设置做一遍中英文双语场景化视觉回归；动态产品名和用户数据
继续保持原文，不纳入 UI 词条翻译。

## 派息时刻钉成 16:00 + Hourly 档（2026-09-05）

设计 `155:16083`，用户：「派息时间要固定下午四点」。之前 `nextPayout` 是拿 `startsAt`
往后加周期，派息点因此继承了**按下保存那一刻的时分秒**——明细页的 `Next Time Payout`
每个产品都落在不同钟点，这就是用户说的「派息时间在 details 里变来变去」。

- `EarnProduct.payoutHour = 16` / `weeklyPayoutWeekday = 6`（Gregorian 里周五）。
  `nextPayout` 改成整点匹配：Hourly 落在下一个整点，Daily 落在下一个 16:00，
  Weekly 落在下一个周五 16:00。**月付仍走加月份的循环**——`Calendar.nextDate(matching:)`
  会直接跳过没有 31 号的月份，做不到「1 月 31 日 → 2 月 28 日 → 3 月 31 日」这条非漂移规则。
- 新增 `EarnPayoutFrequency.hourly`（设计的第一项，也是新建产品的默认值）。
- **设计的选项里没有月付**（只有 Hourly / Daily / Weekly），所以 `monthly` 从选择列表里
  拿掉了，但枚举、文案和计息都保留——旧账本里已有的月付产品照常解码、展示、派息。
  要不要把月付放回选项，等用户定。
- `projectedPayout` 改成量「**第一次派息到第二次派息**」。派息钉死在 16:00 之后，首期
  几乎总是残缺的（上午十点建的日付产品第一期只有 6 小时），继续拿首期当周期会把每期收益
  低估成一个随创建时刻变化的数。产品在第二次派息前就到期时退回用到期日收尾。
- 到期日同样钉 16:00（设计写的是 `2022-12-12 16:00`）：结构化的 `DatePicker` 去掉时分档
  只选日子，定期的「天数」也换算到当天 16:00；当天 16:00 已过则顺延一天，
  避免存下一个立刻过期的到期日。
- 文案两套，别混用：`payoutTitle` 是带钟点的完整标签（`16:00 Friday, Weekly`），
  给 Payout Frequency 行和选择弹层；`payoutCadenceTitle` 只有节奏词，给
  「`<频率>` Profits」那一行——否则会读成「16:00 Friday, Weekly Profits」。
  设计原文是 `16:00 , Daily`，逗号前那个空格当作稿子手误，没有照抄。
- 补 8 条本地化：`Hourly` / `16:00, Daily` / `16:00 Friday, Weekly` / `16:00, Monthly`
  和四条 `<频率> Profits`——后者原先根本没有词条，中文环境下一直露英文。

同轮顺手：总览的动作 pill、币种 chip、账户行三处间距按用户标注从 15 / 15 / 12 统一到 **10**。

验证：SwiftPM **308 tests, 0 failures**（新增 `EarnPayoutIsAnchoredToFourPMTests` 6 个，
含一条「起息时刻的分秒不该泄漏到派息钟点」的回归锁）；iPhone 17e 全量 XCTest
**TEST EXECUTE SUCCEEDED**；`git diff --check` 通过；已装到真机并启动。
截图：`work/v2.1.0-pixel/payout-frequency.png`、`earn-payout-clock.png`、`overview-gap10.png`。
截图用的两个临时 DEBUG 钩子（`PAWFOLIO_QA_EARN_FORM`、`PAWFOLIO_QA_SELECT_FIELD`）
**已删除**，`grep` 无残留。

Exact next task: 等用户定月付要不要回到选项列表；总览币种 chip 的排序（实现按字母序，
设计几帧画的是 USD 在前）仍未定。

## Earn Holding 页按设计 `155:13496` 修复（2026-09-05）

模拟器复核确认了此前「Holding 仍显示 Product 大卡片」的真实原因：两个页签的
`ForEach` 都使用相同的 `product.id`，`LazyVStack` 在条件分支之间复用了旧子视图。
现在列表容器把 `LedgerEarnTab` 纳入 identity，切换到 Holding 会稳定重建为设计要求的
紧凑持仓行。

- USD 汇总卡补齐 `backgroundCard`、12pt 圆角、10pt 内边距、双列等宽居中；文字保留
  Nvwa 20/24pt 完整行高，最终卡高 68pt。
- 持仓行锁定 343×80 的版式（页面 16pt 边距）、16pt 内边距、16pt 圆角、1pt
  `Nvwa.line` 描边；左侧为产品名/APY，右侧为 USD 估值/累计收益。
- 类型图标复用 Remix 资源：活期/定期为 `IconLeaf` + Sentiment Positive，结构化产品为
  `IconQuillPen` + Sentiment Negative；持仓行圆底 24pt、glyph 12pt。产品卡原有的
  40/20pt 版本也改为复用同一个 helper，避免两处视觉规则漂移。
- 未改理财计息、申购、赎回、下架或历史收益逻辑。

验证：SwiftPM 全量测试成功（exit 0）；generic iOS Simulator `build-for-testing` 成功；
iPhone 17e XCTest `test-without-building` 成功（exit 0）；已在 iPhone 17e 模拟器实际切换
Product → Holding 并确认旧卡片被移除。最终截图：`work/earn-holding-155-13496.png`。

Exact next task: 等用户继续指定 v2.1.0 下一个设计节点；若继续做 Earn，优先验收结构化产品
持仓行的红色 `IconQuillPen` 实际数据状态。

## Add Earn 到期日字段按设计 `155:15932` 修复（2026-09-05）

结构化产品 Add Earn 最底部原来直接渲染系统 compact `DatePicker`，因此没有设计稿中的
label、整行输入底、圆角和尾部箭头。现改成项目既有的双层实现：底层原生 DatePicker
继续负责系统日历交互，上层复用 `NvwaDateInput` 呈现 Figma 外观。

- 48pt `backgroundInput` 输入框、10pt 圆角、16pt 横向内边距。
- 日期左对齐，右侧复用 Remix `IconArrowDownSFill`，固定 20×20pt。
- 到期日字段整体 72pt（20pt label + 4pt gap + 48pt input），与其它 Add Earn 字段保持
  16pt 纵向间距。
- 英文日期按设计显示 `MMM d yyyy`；简体中文显示 `yyyy年M月d日`。
- 点击整行仍打开原生日期日历，保存时仍由 `atPayoutHour` 固定为 16:00，未改变业务逻辑。

验证：SwiftPM 308 tests、0 failures；generic iOS Simulator `build-for-testing` 成功；
iPhone 17e XCTest `test-without-building` 成功（exit 0）。已在中文结构化产品场景实测字段
外观和日期弹层。截图：`work/add-earn-maturity-155-15932.png`。

Exact next task: 等用户指定 v2.1.0 下一个需要按 Figma 修复的节点。

## Nvwa Slider 轨道倒角（2026-09-06）

按 Nvwa 组件稿 `2072:862`（内部 Default 变体 `2072:865`）同步 Slider 新增的轨道倒角：

- `NvwaSliderMetrics.trackCornerRadius` 从 0 更新为 **2pt**；4pt 背景轨和进度轨均改用
  `RoundedRectangle(..., style: .continuous)`，对应 Figma SVG 的 `rx=2`。
- 其余几何不变：组件高 16pt、轨道高 4pt、thumb 外径 12pt、描边 2pt。
- `NvwaTokenTests.testSliderGeometryMatchesFigma` 增加 2pt 圆角断言，避免组件回退成直角。

验证：Nvwa SwiftPM **36 tests, 0 failures**；PawFolio SwiftPM **308 tests, 0 failures**；
generic iOS Simulator `build-for-testing` 成功。随后在 iPhone 17e（iOS 26.4.1）运行
named-simulator XCTest，**364 tests, 0 failures**，`TEST EXECUTE SUCCEEDED`；并在活期产品
「追加申购」金额表单实际渲染确认两条轨道端点均为 2pt 圆角。截图：
`work/nvwa-slider-rounded-2072-862.png`。

Exact next task: 等用户指定下一个 Nvwa 或 v2.1.0 产品节点；Slider 本次改动已完成。

## 交易 Investment 默认结算币改为 USDT（2026-09-06）

用户指定交易表单的 Investment 默认币种统一改为 USDT。新增
`LedgerEntry.defaultSettlementCode = "USDT"`，所有新打开的买入/卖出交易表单共用这一默认值；
USD、USDC 仍保留在 Currency 选择弹层中，用户主动切换后交易记账逻辑不变。

补充 `LedgerTradeAndEarnRuleTests.testTradesDefaultToUSDTSettlement`，同时断言默认值属于允许的
结算币集合。验证：SwiftPM **309 tests, 0 failures**；generic iOS Simulator
`build-for-testing` 成功；iPhone 17e（iOS 26.4.1）named-simulator XCTest
**365 tests, 0 failures**，`TEST EXECUTE SUCCEEDED`。已在买入 BTC 表单实测 Investment 余额、
Investment 输入单位及 Buy Price 单位首次进入均为 USDT。截图：
`work/trading-investment-default-usdt.png`。

Exact next task: 等用户指定 v2.1.0 下一个界面或规则调整；交易默认结算币任务已完成。

## 总览账户名的单/多账户颜色逻辑（2026-09-06）

用户指定总览法币卡的账户名不能在只有一个账户时误用“选中态”：

- 单一账户时，账户图标和名称固定使用 `Nvwa.textSecondary`。
- 同币种存在两个及以上账户时，才用 `Nvwa.ink` 突出当前（现有实现中的首个）账户，
  其余账户继续使用 `Nvwa.textSecondary`。
- 抽出 `LedgerAccountLabelTonePolicy`，并增加三种分支回归：单账户即使 selected 也不强调、
  多账户 selected 强调、多账户未选中不强调。

验证：SwiftPM **309 tests, 0 failures**；generic iOS Simulator `build-for-testing` 成功；
iPhone 17e（iOS 26.4.1）named-simulator XCTest **366 tests, 0 failures**，
`TEST EXECUTE SUCCEEDED`。单账户 USD / Exchange 状态已在模拟器确认呈 Secondary 色；截图：
`work/single-account-secondary-tone.png`。

Exact next task: 等用户指定 v2.1.0 下一个界面或规则调整；账户名颜色逻辑已完成。

## 冷启动登录状态门禁（Figma `173:22196`，2026-09-06）

按产品稿新增「进入 App 先确认登录状态」的根级等待态，解决 Keychain / Supabase 会话恢复
期间先短暂露出游客数据、且页面仍可点击的问题：

- `RootTabView` 在 `AccountViewModel.state == .restoringSession` 时只显示不可交互的 App 骨架；
  会话恢复成功、确认未登录，或失败进入可重试状态后，才放出真实页面。
- 等待态复用 `PawTopNavigation`、iOS 26 系统 `TabView` / iOS 17–25 `PawTabBar`，并复用
  `NvwaButton` 的 outline loading 态；没有新增另一套认证状态或改动 OAuth、Keychain、游客
  数据隔离、资料同步及持仓同步契约。
- 中央控件按安全区差值校正到物理屏幕中心，尺寸为 64×48pt，内部为 16pt 原生
  `ProgressView`。共享 `NvwaButton` 的 loading spinner 同步约束为 16pt。
- 产品稿把 Outline Button 边框标成 0.5pt；用户于 2026-09-06 明确确认该标注错误，正确值
  是 **1pt**，实现已保留 1pt，不应再按该稿回退。
- 增加 DEBUG 视觉验收入口 `PAWFOLIO_QA_SESSION_RESTORING=1`，以及 VoiceOver 文案
  `Checking login status` / `正在确认登录状态`。

验证：PawFolio SwiftPM **309 tests, 0 failures**；Nvwa SwiftPM **36 tests, 0 failures**；
generic iOS Simulator `build-for-testing` 成功；iPhone 17e（iOS 26.4.1）named-simulator
XCTest **366 tests, 0 failures**，`TEST EXECUTE SUCCEEDED`。已在模拟器逐项复核顶部访客入口、
中央 loading、底部原生 Liquid Glass TabView；最终截图：
`work/login-session-restoring-173-22196.png`。

Exact next task: 等用户指定 v2.1.0 下一个界面或登录流程调整；冷启动登录状态门禁已完成。

## Earn 申购起息分界（2026-09-06）

按用户确认的「16:00 过点顺延」规则落地：

- 每笔申购独立计算 Effective Date：16:00 之前（不含 16:00）提交的在当日
  16:00 起息；16:00 整及之后提交的在次日 16:00 起息。
- 申购流水仍保留真实提交时间，资金会立即从 Exchange / Trading 转入 Earn；
  未延迟账户转账，因此「提交即锁资」和交易历史时间不变。
- `EarnInterestCalculator` 不再直接把 Earn 账户余额当计息本金；申购只在
  Effective Date 进入计息事件，赎回仍按实际发生时间减少本金。多次追加申购各自起息，
  冲正的待生效申购不会在之后产生收益。
- Holding 页 `Daily (USD)` 同步改为只使用已起息本金；待建仓金额仍属于
  Earn 持仓和总资产，但不会被误报为当日正在产息。

新增 `EarnSubscriptionEffectiveDateTests` 7 个回归场景，覆盖 15:59:59.999、
16:00:00、16:00 之后、锁资与起息分离、起息时点、多笔追加和待生效申购冲正。

验证：PawFolio SwiftPM **316 tests, 0 failures**；generic iOS Simulator
`build-for-testing` **TEST BUILD SUCCEEDED**；iPhone 17e（iOS 26.4.1）named-simulator XCTest
**373 tests, 0 failures**，`TEST EXECUTE SUCCEEDED`。

Exact next task: 继续 v2.1.0 的下一项规则或 UI 验收；申购起息分界已落地。

## Earn Product 卡片 More 图标对齐（Figma `154:13126`，2026-09-06）

产品卡标题行原先让 44×44pt 点击框直接参与 `HStack` 排版，导致可见的 24×24pt
`IconMore2` 相对设计向左偏 10pt，并把设计的 40pt 标题行撑到 44pt。现将设计几何与
点击热区分离：24×40pt 占位参与排版，44×44pt Button 通过 overlay 覆盖，因而图标右边缘
重新贴齐卡片 16pt 内容边距、和左侧 40pt 类型图标垂直居中，同时保留无障碍点击面积。

没有更换图标资源、Nvwa token、理财业务逻辑或卡片其它尺寸。模拟器截图：
`work/earn-more-icon-154-13126.png`。

验证：PawFolio SwiftPM **316 tests, 0 failures**；generic iOS Simulator
`build-for-testing` **TEST BUILD SUCCEEDED**；iPhone 17e（iOS 26.4.1）named-simulator XCTest
**373 tests, 0 failures**，`TEST EXECUTE SUCCEEDED`；`git diff --check` 通过。

Exact next task: 等用户指定 v2.1.0 下一个界面或规则调整；Earn Product 卡片 More 图标已对齐。

## 底部弹窗统一为内容驱动自适应高度（2026-09-06）

按用户确认的新规则移除旧的 half / full 分档和各页面自行指定高度，所有对话型底部弹窗
现在统一走 `PawSheet` 或无标题页的 `.pawSheetPresentation()`：

- Header、自然高度的中间内容和 Footer 分段测量；内容较少时弹层贴合内容，内容变化时用
  系统 spring 平滑跟随，Reduce Motion 下不做动画。
- 弹层最高只长到当前 window 顶部以下 80pt；上限由根视图实时传入的 window 高度和底部
  safe area 计算，不读 `UIScreen.main.bounds`，所以旋转和 iPad 多任务不会沿用物理屏幕尺寸。
- 达到上限后只让中间 `ScrollView` 滚动，Header 和 Footer 固定可见；继续使用原生
  SwiftUI `.sheet`，没有引入 window overlay 或 `fullScreenCover` 对话框。
- `LanguagePickerSheet`、猫头像预览、币种/资产选择、持仓编辑与明细、交易确认、Earn 管理等
  原有自定义弹层已补齐分段测量；测试会扫描 Features，阻止 raw detent、旧尺寸枚举或漏量的
  自定义弹层重新混入。
- `SheetPresentationPolicyTests` 增加自然高度、80pt 上限和最小启动高度的 iOS 实值回归。

模拟器视觉验收：iPhone 17e（iOS 26.4.1）中 Language 两行弹层收缩到约 260pt；Add Currency
长列表达到 80pt 顶部留白后仅列表区滚动。截图位于
`/tmp/pawfolio-adaptive-short.png` 和 `/tmp/pawfolio-adaptive-long.png`。

验证：PawFolio SwiftPM **317 tests, 0 failures**；generic iOS Simulator
`build-for-testing` **TEST BUILD SUCCEEDED**；iPhone 17e named-simulator XCTest
**375 tests, 0 failures**，`TEST SUCCEEDED`；`git diff --check` 通过。随后使用现有本地开发
证书和 PawFolio provisioning profile 完成真机 Debug 构建，并安装、启动到「龙」
（iPhone 17 Pro Max）；未把 Development Team 写入工程。

Exact next task: 等用户指定下一个 v2.1.0 界面或规则调整；底部弹窗自适应高度策略已完成。

## 新增理财弹窗折叠与全局弹窗回归修复（2026-09-06）

统一自适应高度后出现了一个首帧布局死锁：`PawSheet` 的 98pt 初始 detent 会被 header 和
footer 完全占满，中间 `ScrollView` 得到 0 高度；原先放在滚动内容 background 里的
`GeometryReader` preference 因此不会上报，长表单永久停在只剩标题和保存按钮的高度。
「新增理财」是第一个稳定暴露该问题的页面。

- `PawSheetMeasuredPartModifier` 改为通过可回部署到 iOS 16 的 `onGeometryChange` 保存实际高度，
  再从被测视图自身的分支发出 preference，避免零 viewport 时 background preference 被裁掉。
- `PawSheet` 中间内容保持横向约束，但用 `fixedSize(horizontal: false, vertical: true)` 获取完整
  固有高度；新增 320pt 的一次性 bootstrap detent，让带 header + footer 的弹窗首帧也有真实
  的中间布局空间。bootstrap 不是最小高度，测量完成后短弹窗仍会收缩到自然高度。
- 实测 Add Earn 活期表单恢复完整显示；切换结构化产品后测量值会从 622pt 更新到 842pt，
  最终按共享规则封顶，header/footer 固定且只滚动中间表单。Type 二级单选和 Select Assets /
  Add Currency 长列表也能正确测量、弹出和滚动。
- 全量检查 `.sheet` 入口时发现 Earn / Trading 明细里的 Transactions 是带独立导航栏的全屏
  目的页，却仍由 raw `.sheet` 打开。两处均改为 `fullScreenCover`，与主入口的 Transactions
  路由一致，也不再绕过共享对话框策略。
- `SheetPresentationPolicyTests` 增加首帧固有高度测量和 Transactions 全屏路由回归。

验证结果：PawFolio SwiftPM **319 tests, 0 failures**；generic iOS Simulator
`build-for-testing` 成功；iPhone 17e（iOS 26.4.1）named-simulator XCTest
**377 tests, 0 failures**，`TEST SUCCEEDED`；`git diff --check` 通过。最终模拟器截图：
`work/add-earn-sheet-fixed-2026-09-06.png`。

Exact next task: 按用户后续反馈继续检查 v2.1.0 UI；本轮已覆盖短弹窗、长表单、动态字段、
二级单选、长列表和全屏 Transactions 路由。

## 资产走势图恢复展开/收起，输入框字体跟版（2026-09-06）

用户指出「资产的图表展开收起」在账本页被删掉了，且没有人要求删。按设计
`197:2922`（展开资产走势）补回，收起态维持现状：

- 收起时总资产右边仍是 124×70.5 的迷你曲线，点它展开；展开后这枚缩略图让位
  （设计 `197:2928` 里它是 hidden），下面依次是 1D/1W/1M/1Y 的 Section 排（28）、
  160 的画布 + 12 间距 + 16 的起止时刻（合 188）、24 高的收起把手，三段各隔 8。
  与上下两块之间的 32 由外层 `VStack(spacing: 32)` 给，正好对上稿子的 108 / 396。
- 收起态不画把手：那时点迷你曲线就能展开，多一个箭头是冗余。没有 `IconArrowUpS`
  这个资源，沿用 `IconArrowDownS` 旋转 180°。
- 新增 `LedgerValuation.series(...)`：按区间取 48 个带时间戳的采样点。取样数不跟
  `PortfolioHistoryRange.sampleCount`（48～183）——那套数是给「一次算好整条价格序列
  再乘数量」的持仓图用的，账本这边每个采样点都要重放一遍分录再估值。
- 起点是 `max(第一笔分录, 区间起点)`。建账之前那一段恒为 0，不裁掉的话 1Y 上会先
  躺一条贴底的长横线。**代价是**：刚从旧持仓迁移过来的账本，所有期初分录的
  `occurredAt` 都是首次启动那一刻（`HoldingLedgerMigration` 不倒推历史），四个区间
  会画出同一张图，要等流水攒够天数才分得开。
- 区间选择存本地（`PortfolioPreferencesStoring`，与旧持仓页共用 key），默认 1D。
  `LedgerPortfolioViewModel` 为此多收一个 `portfolioPreferences` 依赖。
- 长按扫描保留：光标右侧压到 32%，PNL 那一行改报「相对区间起点的变化」——常驻的
  PNL 是相对投入本金算的，跟光标停在哪儿无关，照搬过去会读成一个不动的数。
- `PawPortfolioChart` 的峰值标注按 `197:6792` 从 11pt/ink40 改成 C-2 Regular
  （10/16，Text Secondary）。该组件目前只剩这一处在用（旧 `PortfolioView` 已不在 tab 上）。

同一轮按 Nvwa `2052:7150` 更新输入框字体：框内那行字（占位符和已输入的值）由
B-M Regular（14/22，字距 1%）改成 **T-G Medium**（14/20，字距 1.5%，即 tracking 0.21）。
Text / Search / Date / Flag 四个变体逐个核对过，都是同一个 token；`Nvwa` 补了
`titleGroup` 字体别名。账本「添加」页里手搓的 Currency 搜索框一并跟上，否则它和下面
的 Amounts 会一个 Regular 一个 Medium。**没有动** `PawSingleSelect`：那是 Select，
不在这次的 Input Fields 段里，等确认它自己的规格。

验证：iPhone 17e（iOS 26.4）named-simulator XCTest **TEST SUCCEEDED**（新增
`testChartSeriesWindowFollowsTheSelectedRange`、
`testChartSeriesStartsAtTheFirstEntryRatherThanTheFullWindow`）。
视觉验收用临时账本夹具（`ledger-v3.json`，8 笔跨 26 天的 USD/USDT 流水）配合
`SIMCTL_CHILD_PAWFOLIO_QA_LEDGER_EXPAND_CHART=1` 直接展开：1D 与 1M 的曲线、点阵、
峰值标注、起止时刻、把手位置均符合稿子；把 `pawfolio.portfolio.history-range` 写成
`month` 重启后停在 1M，区间持久化生效。夹具验收后已从模拟器容器删除。

Exact next task: 等用户指认下一处 v2.1.0 界面差异；`PawSingleSelect` 的字体是否跟随
Input Fields 待确认。

## 首页首次加载中间态与零资产图表修复（2026-09-06）

用户指出账本首页首次加载时会先闪出「0.00 USD + 空态卡 + 右侧点阵图」，要求加载严格
使用产品稿 `173:22196`，且总资产为 0 时右侧完全不显示图表。

- `LedgerPortfolioViewModel` 增加一次性 `hasCompletedInitialLoad`：首次账本读取完成前只显示
  等待态；后续下拉刷新仍保留当前页面和原生 pull-to-refresh，不会重新切回整页 loading。
- `LedgerPortfolioView` 的初始分支不再创建余额、PNL、图表、估值提示或空态卡，仅保留顶栏、
  底部系统 TabView 和整屏正中的 loading；顶栏在此阶段不可点击。
- 新增共享 `PawAppLoadingIndicator`，启动会话恢复和账本首次加载共同复用 Nvwa Huge Outline
  Button：自然尺寸 64×48pt、1pt Line 描边，内部为 16pt iOS 原生圆形 `ProgressView`。
- `LedgerPortfolioChartPolicy` 统一约束迷你图与展开图：只有总资产为正、数值有限、且至少有
  两个有限历史点时才可出现。零资产、估值未知、历史不足和坏数据都直接留空。
- 删除 `ArtPortfolioSparkline.imageset` 点阵占位资源及其全部引用；该状态样式不再保留。
- DEBUG 可用 `SIMCTL_CHILD_PAWFOLIO_QA_LEDGER_LOADING=1` 固定账本加载态，便于后续回归。

视觉验收在临时 iPhone 13 mini（375×812 逻辑画布，iOS 26.5）完成：loading 的 64×48
Outline 容器位于整块物理屏幕中心，顶栏/底栏保持原位；加载完成后的空账本只显示左侧
0.00 USD 与空态卡，右侧没有点阵、迷你图或展开图。证据：
`work/loading-state-qa/ledger-loading.png`、`work/loading-state-qa/zero-assets.png`。

验证：PawFolio SwiftPM **322 tests, 0 failures**；generic iOS Simulator
`build-for-testing` **TEST BUILD SUCCEEDED**；iPhone 13 mini（iOS 26.5）named-simulator XCTest
**381 tests, 0 failures**；`git diff --check` 通过。

Exact next task: 等用户确认首页 loading / 零资产效果，或继续处理下一处 v2.1.0 UI 差异。

## 交易表单：价格 / 数量 / 金额改成单向联动（2026-09-06）

用户报「输入数量、再去输入金额，数量总是被联动改」。旧实现是一套**双向锚点**：
记住用户最后手动改的是数量还是成交额，改价格时重算另一个——于是价格也能改数量，
两个字段还会互相回写。按用户 2026-09-06 定的规则重做：

- **价格**谁都改不动，只有两个来源：选中标的时填入的最新价，和用户手输。
- **金额 = 价格 × 数量**，价格或数量被改时重算；数量为空→金额为空，数量为 0→金额为 0。
- **数量 = 金额 ÷ 价格**，只有金额被改时重算。
- 价格为空或为 0 时两条等式都不成立：这时改金额或改数量都**不会波及对方**。
  注意「不生效」指的只是联动——三个输入框本身照常能自由输入，用户敲进去的字永远
  原样落在自己那一格里，被挡住的只有推给对方的那一步。

用户 2026-09-06 确认的口径：**金额和数量互相影响是对的，前提是价格固定**；价格本身
变化时只能推金额，不能反过来动数量。

实现要点：

- 规则抽成文件级的 `LedgerTradeLinkage`（可被 `@testable` 直接调），
  `LedgerTradeLinkageTests` 覆盖上面每一条，含「半截输入不动对方」。
- 传播写在 `Binding` 的 setter 里，**不用 `onChange`**。`onChange` 是下一轮更新才送到，
  回写触发的那一跳分不清是用户敲的还是自己刚写的，只能靠一个「正在同步」标志位挡，
  而那个标志位在下一轮早就复位了。setter 里改的是裸 state，压根不会二次进来。
- 回填的数改用不带千分位、锁 `en_US_POSIX` 的写法。旧代码回填 `amount()` 的
  `1,234.56`，下一跳 `Double(_:)` 读回来是 nil——联动直接断掉，数量大到出现千分位时
  提交还会判成「数量不合法」。
- 买入侧字段顺序按设计 `197:6880` 改成 价格 → 数量 → 金额（滑杆跟着金额）。
  卖出侧维持 `154:12261` 的「先填卖多少币」，联动规则同上。
- 买入时 Investment 上面那行余额点开的弹层标题改成 **Balance**；卖出时它是从
  Sell Price 的单位点开的，仍是结算币种。两个入口按 `side` 区分。
- 选中标的（含从持仓页带标的进来）后自动填最新价：新增
  `LedgerPortfolioViewModel.latestPrice(for:)`，先看手上的行情，再走缓存，最后才联网；
  `refreshQuotes` 自己会落缓存，下次开表单不必再联网。

**已知取舍**：数量按 8 位小数回填，所以「先填金额」时最终入账的投资额是 数量×价格，
与输入框里那个数会差不到 0.001 USD。

视觉验收（这台机器 `xcode-select` 没指向 Xcode，模拟器点不动，全部走 DEBUG 环境钩子）：
新增 `PAWFOLIO_QA_LEDGER_ROUTE=trading:<代码>` 直接带标的进交易表单、
`PAWFOLIO_QA_LEDGER_TRADE_PICKER=1` 直接打开余额弹层。iPhone 17e 实测：买入价自动
填入 79749.65 USDT、字段顺序为 价格/数量/金额、弹层标题为「余额」并列出三种结算币的
余额与勾选。iPhone 17e named-simulator XCTest **TEST SUCCEEDED**。

Exact next task: 等用户指认下一处差异；卖出侧字段顺序未动，联动规则与买入一致。

## 计算器结果字段、滑动确认反馈与资产 Logo 修复（2026-09-06）

本轮按用户截图把 Calculator 的 Results 六格改为两行：Daily / Weekly / Monthly 与
Yearly / 5 Year / 10 Year。Weekly 使用 `7 / 365` 年，5 年和 10 年复用现有单利/复利公式；
旧 20 Year 结果不再计算或展示。iPhone 17e 截图确认两行顺序正确，金额没有换行或截断。

随后按产品稿 `155:13936` 和 Nvwa `2243:704` 修复所有滑动确认流程：

- `NvwaScrollButton` 的 Scrolling / Finish 覆盖层从错误的 Alpha Blue 10 改为设计绑定的
  `BG/Vessel`（`Nvwa.backgroundVessel`）；56pt 轨道/滑块、28pt Send 图形、24pt spinner
  和 90% 确认阈值保持不变。
- 账本内 7 个 `Slide to Confirm` 入口全部核对。原本已有成功反馈的赎回、下架继续保留；
  入账、支出、买卖、申购/赎回、记录派息补齐成功 toast，并补了简中翻译。失败仍由现有
  `Transaction Error` alert 兜底，不会误报成功。
- USDG 不是 `StablecoinCatalog.favorites`，旧 `assetMark` 因此退化成蓝底字母 U。现在常用
  USDT/USDC 仍用专用品牌资源，其余稳定币、Crypto、股票和 ETF 统一回落到
  `AssetLogoCatalog` 的随包资源；USDG 命中 `AssetLogoCrypto_USDG`。
- 全量检查了 202 个 `AssetLogo*.imageset`：没有缺少 `Contents.json` 或实际图片文件；
  `AssetLogoTests` 增加 USDG 映射断言，模拟器 XCTest 也验证所有快照资源可由 UIKit 加载。

验证：PawFolio SwiftPM **322 tests, 0 failures**；Nvwa SwiftPM **36 tests, 0 failures**；
generic iOS Simulator `build-for-testing` 成功；iPhone 17e（iOS 26.5）named-simulator XCTest
**388 tests, 0 failures**；`git diff --check` 与 `Localizable.xcstrings` JSON 校验通过。

Exact next task: 等用户在实际数据中复核滑动成功 toast 和 USDG 图标；本轮所列交互、颜色、
Calculator 字段与 Logo 映射已完成。

## 首页币种手动拖动排序（2026-09-06）

用户希望资产卡顶部的 CNY / USDG / USDT 等币种可以手动换位置。本轮只改 iOS：

- 币种 chip 保留原有外观与短按选择；按住 0.28 秒后可横向拖动，拿起项轻微抬升并加阴影，
  其余项实时让位，松手后一次性提交排序，避免拖动中频繁写存储。
- 换位按每个 chip 的真实宽度与中心点计算，不假设 CNY、USDG 等标签等宽；支持一次跨多格、
  拖到边界和反向拖回。拖动本身使用 global 坐标，避免 chip 随手指位移后 local translation 抖动。
- 排序写入 `PortfolioPreferencesStoring`，App 重启后仍保留；新出现的币种按代码追加，暂时归零
  的旧币种偏好保留在末尾。读取时去重损坏/重复的偏好，避免字典建表崩溃。
- 排序开始前会固定当前选中币种，因此把别的币种拖到首位不会顺带切换下方余额；短按选择仍正常。
- Reduce Motion 下关闭让位/落位动画；VoiceOver chip 增加「Move left / Move right」自定义动作及
  长按拖动提示。

视觉验收在 iPhone 17 Pro（iOS 26.5）用临时 CNY / USDG / USDT 账本完成：换位后布局正确，
当前选中的 CNY 余额保持不变，杀掉 App 重启后顺序仍保留。截图：
`work/reorder-qa/spot-asset-reordered.png`。临时账本和排序偏好验收后已恢复/清理。

验证：PawFolio SwiftPM **327 tests, 0 failures**；generic iOS Simulator
`build-for-testing` 成功；iPhone 17 Pro named-simulator 全量 XCTest **394 tests, 0 failures**；
最终增量修改后相关 33 项 XCTest 再次通过；`git diff --check` 通过。

同日已使用本机现有开发证书与 `HGTMKU5HMG` 团队的本地 provisioning profile 完成真机
Debug 构建，并安装到「龙」（iPhone 17 Pro Max）。安装成功；自动启动时手机处于锁定状态，
SpringBoard 拒绝远程拉起，解锁后可从桌面直接打开。团队号仅作为命令行覆盖，没有写回工程。

Exact next task: 等用户在真机上确认长按时长与拖动手感；排序、持久化、选中态和无障碍路径已完成。

## 登录两段等待态与 Input 14 Medium 全局补齐（2026-09-06）

按产品稿 `173:22119` 修复登录时 Welcome 提前出现的问题：

- `LoginView` 不再用一个 `model.isBusy` 同时覆盖 OAuth 和云同步，而是显式分成
  `idle / authenticating / loadingAccount`。`.signingIn` 且身份尚未建立时只显示
  `PawAppLoadingIndicator`；`identity` 建立后以及 `.syncing` 阶段才显示
  `Welcome Back / Your Data is protected.`。
- OAuth 与同步的异步边界没有改。登录失败仍回到按钮页并走原有 toast；恢复会话时身份尚未
  建立也不会误闪 Welcome。
- 新增 `PAWFOLIO_QA_LOGIN_AUTHENTICATING=1` 直达纯菊花状态；原
  `PAWFOLIO_QA_LOGIN_WAITING=1` 明确定义为 Welcome + 云数据加载状态。iPhone 17e 截图分别为
  `work/login-qa/authenticating.png` 和 `work/login-qa/loading-account.png`。
- `AccountViewModelTests` 增加展示阶段边界断言，钉死「身份建立前不能出现 Welcome」。

随后按 Nvwa `2052:7150` 全局复核 Input 字体。Claude 已把 Nvwa Text / Search / Date / Flag
四个标准变体改为 T-G Medium（14/20、1.5% 字距），遗漏来自业务页手工拼的输入框：

- 新增共享 `.nvwaInputTextStyle()`，标准 Nvwa Input 与业务自定义输入统一通过同一入口应用
  `Nvwa.Typography.titleGroup`，包含字号、Medium 字重、0.21pt tracking 和行高规则；金额可选
  monospaced digits，但不改变 Inter Medium 字重。
- 计算页 Total Investment / APR 的输入值和 USD / % 单位已补齐；模拟器截图为
  `work/login-qa/calculator-input-14-medium.png`。
- 旧持仓编辑器的 Amount / APR / Note / Date，以及分红编辑器共用的 `PawTextFieldShell` 也补齐，
  避免从非账本入口打开时仍回退到旧 B-M Regular / 16pt 字体。
- 汇率页的 30pt Semibold 金额编辑器是该页面独立设计，不属于 Nvwa Input Field，保持原稿。
- `NvwaComponentSpecTests` 新增 Input 排版 token 断言。

验证：Nvwa SwiftPM **36 tests, 0 failures**；PawFolio SwiftPM **327 tests, 0 failures**；generic
iOS Simulator `build-for-testing` 成功；iPhone 17e（iOS 26.4.1）named-simulator XCTest
**397 tests, 0 failures**；`git diff --check` 通过。最终 Debug 签名包已使用团队
`HGTMKU5HMG` 构建并覆盖安装到「龙」（iPhone 17 Pro Max）。

Exact next task: 等用户在真机确认 OAuth 期间只有菊花、云同步阶段才显示 Welcome，并复核计算页
输入字重；本轮代码、自动化测试、模拟器视觉验收和真机安装均已完成。

## 滑杆震动反馈 + 顶栏毛玻璃（2026-09-06）

**滑杆**（`NvwaSlider`，设计 `2072:862`）：拖动时按档给 `UISelectionFeedbackGenerator`。
全程 20 档，和无障碍 `adjustableAction` 的步长是同一个数——手指滑过去和用旁白按一下，
走的是同样粗细的刻度。**不是每帧都震**：按住不动或一路滑到底逐帧触发，手感是持续的
嗡嗡声而不是刻度。松手清空档位，下一次从同一处按下去照样有反馈。Nvwa 包还编译到
macOS，所以震动那几行包在 `#if os(iOS)` 里（`swift build` 已验证 macOS 侧能过）。

**顶栏毛玻璃**（`PawTopNavigation`，设计 `2224:91`）：Nvwa 的导航组件本身没有底色，
玻璃是应用层的事，所以加在 `PawTopNavigation` 而不是 `NvwaNavigationBar`。

关键是**光加 `.background(.ultraThinMaterial)` 等于没加**：原来三个标签页都是
`VStack { 顶栏; ScrollView }`，内容永远在顶栏下方，玻璃底下没有东西可糊，只会把
页面底色糊成另一块灰。所以三页都改成把顶栏挂在 `.safeAreaInset(edge: .top)` 上，
内容从它底下滑过去。状态栏那一截由顶栏自己的玻璃 `ignoresSafeArea(edges: .top)`
铺满，`pawStatusBarBackground()` 的实色随之从这三页去掉——留着会盖住滑上去的内容，
正好把玻璃效果挡没。做法与贴底那条玻璃（`PawTabBar`）一致。

**玻璃的染色跟着滚动走**（用户 2026-09-06 两次追加后的定稿，`PawGlassTopBar`）。

第一步只铺 `.ultraThinMaterial`：浅色下偏灰、深色下把纯黑提亮到 `#1E1E1E` 左右，
滚到顶时两头都是一条看得出边界的色带。第二步在材质上盖一层 `Nvwa.backgroundMain`
把它染回去，色带没了——但**常驻的染色会把玻璃一起糊没**，实测顶栏内透出的明暗
跨度从 26/255 掉到浅色 7、深色 3，用户直接问「毛玻璃效果还有吗」。

定稿是让染色随滚动变：

| | 到顶 | 滚动后 |
|---|---|---|
| 染色浓度 | 1.0（顶栏＝纯背景色） | 浅色 0.28 / 深色 0.55 |
| 顶栏与页面底色的差 | **0/255** | —— |
| 顶栏内透出的明暗跨度 | —— | 浅色 **19**/255、深色 **11**/255 |

对照：常驻染色那版是 7 和 3，不染色那版是 26。也就是到顶完全无痕，滚起来拿回
七成以上的玻璃。过渡距离 24pt，太短会在指尖下「啪」地跳色。

滚动偏移走 `onScrollGeometryChange`（iOS 18+），**挂在 ZStack 这种祖先视图上也能
收到内层 ScrollView 的几何**，实测有效。部署目标是 iOS 17，17 上拿不到偏移，
`tint` 里 `guard #available` 回退到常驻染色（0.7 / 0.88）——那头只是玻璃弱些，
不会出现色带。

三个标签页统一改用 `.pawGlassTopBar { PawTopNavigation(...) }`：它同时负责
safe-area inset、玻璃和滚动跟踪。`PawTopNavigation` 自身退回成一条没有底色的导航，
`NvwaNavigationBar` 更是一点没动（设计 `2241:591` 本来就是透明的，玻璃是应用层的事）。

视觉验收：这台机器点不了模拟器，滚动态是临时给账本页加 `.defaultScrollAnchor(.bottom)`
造出来的（截图后已删）——这一手同时验证了 `onScrollGeometryChange` 确实收得到几何，
否则滚动态的染色不会降下来。到顶态和滚动态、浅色和深色四张截图都按像素量过，
数字见上表。
震动本身模拟器不出，只能等真机确认。iPhone 17e XCTest **TEST SUCCEEDED**；
`ios/Nvwa` `swift build`（macOS）通过。

Exact next task: 等用户指认下一处差异；滑杆震动的档位密度只能在真机上确认。

## 卖出页字段顺序调整（2026-09-06）

按用户最新确认，将 Trading 的卖出表单从旧顺序「Sell Amounts → Sell Price → Sell Value」
改为「Sell Price → Sell Amounts → Sell Value」，与买入页同样先确认成交价、再填写数量、
最后显示联动金额。只调整 SwiftUI 视图排列；价格/数量/金额的单向联动、持仓余额滑杆、
结算币选择、手续费和提交逻辑均未改动。

视觉验收在 iPhone 17e（iOS 26.4）通过：Accessibility 顺序和实际截图都确认 Sell Price
位于 Sell Amounts 上方，证据为 `work/trade-order-qa/sell-price-first.png`。

验证：PawFolio SwiftPM **327 tests, 0 failures**；generic iOS Simulator
`build-for-testing` 成功；`git diff --check` 通过。

Exact next task: 等用户在真机复核卖出页字段顺序，或继续处理下一处 v2.1.0 界面差异。

## 空资产首页纵向位置回归修复（2026-09-06）

用户截图显示空资产时「总余额 + 空状态卡」整体被推到页面中下部，顶栏下方留下大块空白。
账本首页的 `ScrollView` 没有像旧 Portfolio / Calculator 一样明确短内容锚点；在 iOS 26
系统 `TabView` 与顶部 `safeAreaInset` 组合下，短内容会被重新居中。

- 给 `LedgerPortfolioView` 的主滚动区补上 `.defaultScrollAnchor(.top)`，空资产和短内容均固定
  从顶栏下方开始；长内容滚动、下拉刷新、顶栏毛玻璃和底部系统 TabView 均未改。
- iPhone 17e（iOS 26.4）复现了修复前的异常位置，并在同设备、同空账本状态确认修复后总余额
  回到页面顶部。修复截图：`work/position-regression-fixed.png`。

验证：PawFolio SwiftPM **327 tests, 0 failures**；generic iOS Simulator
`build-for-testing` 成功；模拟器视觉验收通过。

Exact next task: 等用户复核空资产首页位置，或继续处理下一处界面差异。

## 最新修复覆盖安装到真机（2026-09-06）

包含卖出页「价格 → 数量 → 金额」顺序与空资产首页顶部锚点修复的当前工作区，已使用本机
Team `HGTMKU5HMG` 和既有 PawFolio provisioning profile 完成 Debug 真机构建；
`BUILD SUCCEEDED`。随后通过 `devicectl` 覆盖安装到「龙」（iPhone 17 Pro Max，
`05FAD045-9A8E-536B-8766-CA830DA04D6C`）并成功启动，覆盖安装保留原有应用数据。

Exact next task: 等用户在真机复核卖出字段顺序与空资产首页位置。

## Earn 起息与首次派息分离（2026-09-06）

按用户确认把 Effective Date 和首派时间拆成两个独立边界：申购在 Effective Date 开始累计
利息，但只有完整经过一个派息周期后才能生成派息流水。

- Daily：16:00 前申购当日 16:00 起息、次日 16:00 首派；16:00 整及之后申购次日
  16:00 起息、后日 16:00 首派。
- Hourly：提交后的下一个整点起息，下下个整点满一小时后首派。
- Weekly / Monthly 同样先完整经过一周 / 一个日历月，再对齐周五 16:00 / 月度派息点；
  At Maturity 继续只在到期时派息。
- `Next Time Payout` 改为读取真实申购流水和最后一笔有效派息，而不是只看产品创建时间。
- 未到派息时间时不显示 `Record Interest` 操作；即使绕过 UI 调用 ViewModel，写流水前也会
  再校验并拒绝，错误为 `A full payout cycle has not elapsed yet.`。
- 计息算法不等待派息：Effective Date 之后、首派之前的应计利息仍会持续增加。

验证：PawFolio SwiftPM **330 tests, 0 failures**；generic iOS Simulator
`build-for-testing` 成功；iPhone 17e（iOS 26.4.1）相关领域边界测试与
`LedgerPortfolioViewModelTests.testInterestPayoutCannotBeRecordedBeforeAFullCycle` 均
`TEST SUCCEEDED`。

真机 Debug 包使用 Team `HGTMKU5HMG` 签名构建成功，并已覆盖安装到「龙」（iPhone 17 Pro
Max，`05FAD045-9A8E-536B-8766-CA830DA04D6C`），保留原有应用数据。安装后自动启动因手机
处于锁屏状态被 SpringBoard 拒绝；解锁后可从桌面直接打开。

Exact next task: 等用户在真机确认 Next Time Payout 与 Record Interest 的出现时机。

## Earn 资产账户匹配与结构化到期日输入修复（2026-09-06）

用户已有 USDG 位于 Fiat / Spot，但旧版新增 Earn 时把它存成了 `cryptocurrency`：账本余额键
同时包含资产代码和类型，所以申购弹层随后去 Trading 查询 `USDG + cryptocurrency`，结果显示 0。
根因是旧分类只把 `StablecoinCatalog.favorites`（USDT / USDC）当作稳定币。

- `StablecoinCatalog` 新增独立的稳定币全集；Favorites 仍保持 USDT / USDC，不改变 Add Currency
  的常用项。USDG、USD1、DAI、USDS、USDE、PYUSD、RLUSD、USDD、USDGO、USDF、BFUSD、GHO
  等已知稳定币会按 Fiat / Spot 路由。
- 新建或申购产品时不再只信选择器/旧产品保存的 kind，而是用标准分类并核对实际账户中的同代码
  正余额资产。BTC 等 Crypto 从 Trading 识别；法币和稳定币从 Fiat / Spot Exchange 识别。
- 对已经创建、但因为该 bug 从未产生过产品流水的 USDG 产品，首次申购会在同一次原子保存中纠正
  产品资产类型并写入申购流水，无需用户删除重建。已有正式产品流水的产品不会改写资产类型，避免
  把历史余额拆到两个账本键。
- 申购弹层的 Balance 改走同一套解析，不再直接拿可能错误的 `product.asset` 查余额。
- 新增回归测试覆盖：错误保存为 Crypto 的 USDG 产品能读到 Fiat / Spot 余额、成功申购并持久化
  为 Stablecoin；BTC 能读取 Trading 余额并成功申购；稳定币全集分类不再回退为 Crypto。

结构化产品的 Maturity Date 原来把系统 compact `DatePicker` 垫在不可点击的 Nvwa 输入框下，
系统胶囊从中间透出，点击范围也只剩日期文字。现在直接使用 `NvwaDateInput`：单层
`backgroundInput`、右侧下拉箭头，整行按钮打开使用 `PawSheet` 的 graphical 日期选择器，Done
返回并更新日期。

视觉验收：iPhone 17 Pro（iOS 26.5）确认结构化表单的日期框只有一层背景、箭头可见；通过日期
按钮任意位置打开日历并返回成功。截图保存为 `/tmp/pawfolio-structured-maturity-qa.png`。

验证：PawFolio SwiftPM **330 tests, 0 failures**；generic iOS Simulator
`build-for-testing` 成功；iPhone 17 Pro（iOS 26.5）named-simulator 全量 XCTest
`TEST SUCCEEDED`。为遵守最新“满一个周期才允许派息”的规则，三条旧 ViewModel 用例改为在真实
到期点登记利息，其中 Crypto 下架用例使用已满周期的历史申购，不再生成未来流水后立即下架。

真机 Debug 包使用 Team `HGTMKU5HMG` 签名构建成功，并已覆盖安装到「龙」（iPhone 17 Pro Max，
`05FAD045-9A8E-536B-8766-CA830DA04D6C`），保留原有应用数据。自动启动因手机锁屏被 SpringBoard
拒绝；解锁后可从桌面直接打开。

Exact next task: 等用户在真机确认已有 USDG 产品的 Balance/申购、BTC Trading 余额识别，以及
结构化理财到期日整行点击交互。

## 账本操作成功弹层补齐（2026-09-06）

按产品稿 `134:7230` 中的成功态组件 `154:12605`，新增共享 `PawSuccessSheet`，并把原先成功后
直接关闭或只发 Toast 的账本操作统一切换为成功 Sheet：添加资产/入金、Pay、买入/卖出、添加或
编辑理财产品、申购/赎回、登记利息、产品下架和交易冲正。入金与买卖的全屏表单会等成功 Sheet
关闭后再退出，避免用户看不到结果反馈。

**Figma gate — G5 PASS。** Tick 严格复用 Nvwa 节点 `2029:9063` 的
`NvwaKeyFeatureIcon(.tick)`，没有在业务层重画：48pt 圆形容器、24pt 原始 glyph；Sheet 抓手
40×4pt，内容 padding 16pt、图标与文案间距 16pt，文案走 B-M Regular token。产品稿源文案为
`Succesful`，界面按稿保留该拼法，无障碍标签使用正确的 `Successful`；简体中文分别补为「成功」
和「操作成功」。

视觉验收：iPhone 17 Pro（iOS 26.4）通过 `PAWFOLIO_INITIAL_TAB=portfolio` 与
`PAWFOLIO_QA_LEDGER_SUCCESS=1` 直接打开成功态；浅色、深色截图分别保存为
`tmp/qa-success/success-light.png`、`tmp/qa-success/success-dark.png`。两种外观的动态颜色正确，
原生 Sheet 关闭动作正常。

验证：`swiftc -parse` 通过；PawFolio SwiftPM 全量测试通过；generic iOS Simulator
`build-for-testing` 成功；`git diff --check` 通过。现有 Swift actor warning 与本次改动无关。

Exact next task: 等用户在真机逐项确认买卖、理财添加、申购赎回等成功路径的弹层出现时机；
如产品稿后续修正文案拼写，再同步把 `Succesful` 改为 `Successful`。

## 输入组件按新版设计重做，收到最小单元（2026-09-06）

设计 `2052:7150`（Input Fields）改版后重做了 `ios/Nvwa/.../NvwaInputs.swift`。
原则是用户给的「最小设计单元，去掉冗余」。

**去掉的**（稿子上已经没有）：

- `NvwaInputState` / `NvwaInputValidation` —— **错误态整个删了**。原来余额不足、
  金额必须大于 0 会把 hint 染成 Sentiment Negative，现在统一是普通灰提示。
  这是用户 2026-09-06 明确要求的，不是漏改。
- `NvwaInputSize` —— `Size=Small` 稿子上没有了，而且两档本来就都是 48 高，
  是条一直没生效的轴。
- `NvwaFlagInput` —— 稿子里 Flag 整个换成了 **Select**（`2074:894`）。
- `NvwaSearchInput` 的 `unit` 和 `secondaryText` —— 带单位的格子在稿子上是
  Text Input 的 `Unit=Yes`，带副标题的是 Select 的 `Status=Aseets`，
  都不该由搜索框兼任。
- `NvwaInputField` 的泛型 `leading` / `trailing` 闭包 —— 全部调用点都只用它塞了个
  单位标签，收成 `unit: String?` 之后 27 处调用一起变干净，也堵死了「顺手往
  trailing 里塞点别的」这条口子。

**补上的**：

- `Dropdown=Yes`（`2276:635`）：单位可点开换。卖出价那格原先在 trailing 里手搓
  一遍单位 + 箭头，现在是 `dropdownIcon` + `onUnitTap`。注意可下拉的单位是
  **B-M Regular**，比不可下拉那档（T-G Medium）轻一号——稿子如此，不是笔误。
- `Status=Active`（`2276:630`，批注「一键清除数字」）：有字就出现 close-circle。
  Active 在稿子上不是可选项，所以图标走**环境注入**
  （`\.nvwaInputClearIcon`，`RootTabView` 注一次），而不是每个调用点抄一遍图标名——
  Nvwa 不自带图标集（`AGENTS.md`），但也不该让每个格子自己决定要不要 Active。
- **`NvwaSelect`**（`2074:894`）：三种形态由入参组合，不各画一个变体——
  `Search=Yes` 带搜索图标点开跳搜索、`Status=Aseets` 选中后两行、`Search=No` 普通单选。

**顺带把手搓的格子换成了组件**（上一轮审计列出来的那几处）：

| 位置 | 原来 | 现在 |
|---|---|---|
| 添加页 Currency | 手搓 search 壳 | `NvwaSelect(Search=Yes)` |
| 交易表单 Asset Name | 手搓两行 search 壳 | `NvwaSelect` + `secondaryText` |
| 理财产品表单 Assets | 手搓 select 壳 | `NvwaSelect(Search=No)` |
| `PawSingleSelectField` | 手搓 select 行 | 内部改用 `NvwaSelect` |
| 交易表单 Sell Price 单位 | trailing 里手搓箭头 | `Dropdown=Yes` |
| Pay 弹层 / 赎回数量 | `NvwaSearchInput(unit:)` | `NvwaInputField(unit:)` |

`unitLabel` / `earnUnitLabel` / `addPositionUnit` 三个只为塞单位而存在的小工具随之删除。
新增图标 `IconArrowDropDownFill`（Remix `arrow-drop-down-fill`，路径取自 Figma 导出）。
Date Input 的图标从下拉箭头改回 `IconCalendar`，与 `2058:311` 一致。

剩下三处在同一轮里也换掉了，见下一节。

验证：`ios/Nvwa` `swift build`（macOS）通过；iPhone 17e XCTest **TEST SUCCEEDED**；
模拟器实拍交易表单与添加页，Select 的两行形态、单位、一键清除、下拉三角均正确。

Exact next task: 见下一节。

## 最后三处手搓也换成组件（2026-09-06）

**理财到期日的日历**：系统 `.graphical` DatePicker 换成 `NvwaCalendar`（`2014:7583`）。
这是 `AGENTS.md` 里「系统控件只有底部 TabView 一个例外」最后一处漏网的。
换过来缺一个能力——旧的 `in: Date()...` 会挡住过去的日子，而组件没有这个概念，
所以给 `NvwaCalendar` 补了 `minimumDate`：早于它的日子按稿子的 `State=Past`
（`2014:7553`）整格压到 **45% 透明**并且点不动。年/十年那两屏只翻页、不落选中，
所以只在日格上拦就够了。

**计算页的投资金额 / APR**：裸 `TextField` + 自拼壳换成 `NvwaInputField`，标签也交回
组件，外面的 `fieldLabel` 不再套。两处有坑：

- 金额要等宽数字（`AGENTS.md`），而组件原来没有这个开关，于是给 `NvwaInputField`
  加了 `monospacedDigits`。**这不是稿子上的一根变体轴**，只是排版细节，所以做成开关
  而不是新变体。
- APR 的真值是 `Double`（滑杆和计算都读它），组件收的是文本。桥接规则是「打字时
  文本推模型，滑杆动时模型推文本」，而且**只在没聚焦时回推**——否则用户敲到一半的
  `8.` 会被格式化成 `8`，光标当场跳走。

**死分支里的三个自制壳**：`DividendRecordEditorView` 迁到 Nvwa 组件
（冻结的份额 → `NvwaInputField(unit:)` 且 disabled、每股股息 → `NvwaInputField(unit:)`、
频率 → `NvwaSelect`、两个日期 → `NvwaDateInput` + `NvwaCalendar` 弹层），
之后 `PawInputShell` / `PawTextFieldShell` / `PawDateFieldShell` / `PawEditorField`
四个都没人用了，从 `PawControls.swift` 删掉。

**要提醒的**：`DividendRecordEditorView` 所在的那条分支（`PortfolioView` →
`HoldingDetailView` → `HoldingEditorView` / `DividendRecordEditorView` /
`PositionConfirmationView`）**至今没有任何入口**，Portfolio 标签早就换成
`LedgerPortfolioView` 了。这一轮只是把它迁到新组件上，没有删。真要「去掉冗余」，
删掉整条分支比迁移它更彻底，但那是几千行的删除，等用户点头。

验证：`ios/Nvwa` `swift build`（macOS）通过；iPhone 17e XCTest **TEST SUCCEEDED**。
视觉：计算页两格（等宽数字、单位、一键清除、APR 与滑杆联动）实拍确认；
`NvwaCalendar` 因为埋在理财表单深处点不到，临时挪到添加页截了一张——
表头翻页、周末列配色、1–5 号按 `State=Past` 压到 45% 都对，说明 `minimumDate` 生效。
临时钩子已全部撤掉（`grep QA-TEMP` 为空）。

Exact next task: 见下一节。

## v2.1.1：资产列表重排、Earn Daily 明细与 Details 文案（2026-09-06）

按产品稿 Section `208:24494` 完成四个目标节点：Buy Assets `211:24982`、Earn
`209:24504`、Daily `211:24603`、Details `212:25433`。

- Fiat / Spot 横向币种、Trading 资产、首页 Earn 产品、Earn Holding 产品均支持长按拖动
  排序；拾取时触发一次 medium haptic，并提供 VoiceOver `Move up` / `Move down` 动作。
- 三种顺序都经过 `PortfolioPreferencesStoring` 持久化。当前暂时归零/隐藏的资产或产品仍
  保留在偏好末尾，新出现项目按稳定默认顺序追加；读取时过滤重复和无效 ID。
- Trading 行统一为 76pt、32pt logo、无分隔线；首页 Earn 与 Earn Holding 行统一为
  78pt、32pt 产品标识（16pt glyph）、无分隔线。Trading 标题汇总改为总收益率，Earn
  标题汇总为总利息。
- Earn 默认进入 Holding。`Daily (USD)` 现在是按钮，打开无关闭图标的原生 `PawSheet`：
  展示总日收益、下一次本地时间 16:00、两列产品明细、16/12pt 产品标识、APY tag、逐产品
  USD 日收益和 OK 按钮。日收益口径为「当前有效计息本金 × 当日 APY / 年日数」，统一折算
  USD，不代表实际派息流水。
- Earn Details 的活期主按钮由 `Subscribe More` 改为产品稿要求的 `Subscribe`。
- `Payout` 增加简体中文「派息」；版本号由 2.1.0 升至 2.1.1，build number 保持 1。
- `DEBUG` 增加只读内存 QA fixture：
  `SIMCTL_CHILD_PAWFOLIO_QA_LEDGER_FIXTURE=v2.1.1`。它不读写用户账本，用来稳定验收四项
  Earn 持仓和 Daily 两列布局。
- 买入/卖出、添加资产、添加/编辑理财、申购/赎回等成功路径继续统一使用上一节记录的
  `PawSuccessSheet`；本轮再次用 QA 入口确认成功弹层可见。

**Figma gate — G5 PASS。** 资产 logo 继续走现有 `AssetLogoStore` / catalog 与 Remix
资源；产品标识只复用 `LedgerEarnProductMark`，首页和 Holding 为 32/16pt、Daily 为
16/12pt、Details 为 20/10pt，没有新增业务层自绘图标。浅色与深色模拟器截图已逐项对照
Figma：

- `/tmp/pawfolio-v2.1.1-earn-light.png`
- `/tmp/pawfolio-v2.1.1-daily-light.png`
- `/tmp/pawfolio-v2.1.1-daily-dark.png`
- `/tmp/pawfolio-v2.1.1-details-light.png`
- `/tmp/pawfolio-v2.1.1-success-light.png`

验证：

- `swiftc -parse`（RootTab、Ledger View/ViewModel、两份新增测试）通过；
- `git diff --check` 通过，`Localizable.xcstrings` 通过 `jq empty`；
- SwiftPM 全量测试通过；
- generic iOS Simulator `build-for-testing` 成功；
- iPhone 17 Pro（iOS 26.4.1）全量 XCTest：**406 tests, 0 failures**，结果位于
  `/tmp/pawfolio-derived/Logs/Test/Test-PawFolio-2026.09.06_18-59-40-+0800.xcresult`；新增的
  Trading / Earn 顺序恢复与持久化、偏好 round-trip / 去重测试均在结果中通过。

最后一次复跑构建时，工作区里的无关文件 `Domain/Holding.swift` 在 19:08 被并行改动，删掉了
`DividendFrequency` / `DividendRecord`，但仍有旧页面引用它们，导致当前 HEAD 的全工程构建
停在这些符号缺失；没有覆盖或回退这份用户改动。v2.1.1 本轮文件在该改动发生前已完成上述
构建、测试与模拟器截图。

Exact next task: 先由正在修改旧 Holding / Dividend 分支的工作完成类型迁移或删除引用，再复跑
generic `build-for-testing` 和 named-simulator XCTest；v2.1.1 功能本身无剩余实现项。

## 删掉 DividendRecord（2026-09-06）

用户 2026-09-06 拍板「全删，包括存储字段」。删之前把影响范围摆给他看过：
`Holding.dividendRecords` 是**会落盘也会同步到 Supabase 的字段**，
`HoldingSyncCoordinator` 是活的（登录/同步时 `AccountViewModel` 会调），
所以**老用户存过的股息记录会在下次同步时从本地和云端一起消失，不可逆**。
这些数据本来就已经是孤儿——账本迁移（`HoldingLedgerMigration`）根本不读它，
也没有任何可达界面显示它——用户在知情的前提下选了全删。

删除范围（106 处引用清零）：

- 领域：`DividendRecord`、`DividendFrequency`、`DividendRecordRequest`，
  `Holding` 上的 `dividendPerShare` / `dividendFrequency` / `dividendExDate` /
  `dividendPayDate` / `dividendRecords` / `dividendRecordId` 六个属性连同 CodingKey
  与解码分支，`HoldingRecordMutation` 的 upsert/delete 与五个错误 case，
  `HoldingValuation.confirmedDividendIncome` 与 `HoldingMetrics.confirmedDividends`，
  `HoldingDraft` 的五个字段与整段记录生成，`HoldingPositionAdjustment` 里卖出后
  回填未来记录的那段，`HoldingDraftError.invalidDividend` / `.invalidPayDate`。
- 界面：`DividendRecordEditorView.swift` 整个文件（连同 `project.pbxproj` 里的四行引用），
  `HoldingDetailView` 的股息列表 / 记录入口 / 编辑弹层 / 删除确认框，
  `HoldingEditorView` 的股息字段块、Dividends 勾选框、频率弹层、确认页股息段，
  `PortfolioViewModel` 的两个转发方法。
- 测试：五个文件里的股息用例与夹具。

**保留的两处**，别当成漏删：

- `HoldingKind.dividend`：它是持仓的**分类**，不是股息数据。旧 `holdings-v1.json`
  里存着这个 rawValue，而且 `HoldingLedgerMigration` 还在读它（`.market` / `.hybrid` /
  `.dividend` 一起归到 trading 账户）。删掉它会让老数据解码失败并改变迁移行为。
- `stablecoinInterestPreview` / `stablecoinEstimatedDailyInterest`：这两个原来叫
  `stablecoinDividendPreview` / `stablecoinEstimatedDividend`，画的却是「Daily Interest」，
  跟股息毫无关系。顺手改了名，免得以后又被当成股息残留。

验证：iPhone 17e XCTest **TEST SUCCEEDED**；`ios/Nvwa` `swift build`（macOS）通过；
`grep -r DividendRecord` 全仓为 0。

Exact next task: 见下一节。

## v2.1.1 资产列表排版像素级修正（2026-09-06）

按 Pawfolio Design `208:24494` 内的 Buy Assets 节点 `211:24982` 重新读取完整设计上下文，
修正首页 Trading / Earn 与 Earn Holding 的两行资产列表：主字继续使用 B-M Semi Bold
（14/22），副字继续使用 B-S Regular（12/20），并把两档 token 的设计行盒显式落到 SwiftUI
布局；主副文字间距统一为 4pt。每行只使用上下各 16pt padding，自然高度为
`16 + 22 + 4 + 20 + 16 = 78pt`；Trading 拖动排序步长同步由 76 改为 78。

首页 Trading / Earn 容器保持 `spacing: 0`；Earn 页的 Holding 列表也从额外 16pt 间距改为
0，Product 页卡片之间原设计要求的 16pt 不变。没有修改字号 token、颜色、Logo 或业务逻辑。

验证：generic iOS Simulator `build-for-testing` 成功。iPhone 17e（iOS 26.4）使用只读
`v2.1.1` QA fixture 实拍首页和 Earn Holding；行中心距为 78pt、相邻行没有额外 gap，截图为
`work/list-spacing-qa/portfolio.png` 与 `work/list-spacing-qa/earn-holding.png`。
iPhone 17e named-simulator 全量 XCTest `test-without-building` 成功（exit 0）。
删除旧 Portfolio 分支及其失效源码路径测试后复跑当前工作区 SwiftPM：321 tests，
0 failures。

Exact next task: 用户在真机复核 Trading / Earn 的 12pt 副文字、4pt 文字间距与 0pt 行间距；
如有差异，以真机截图标注继续逐项校准。

## 删掉旧持仓分支，并盘点剩下的死代码（2026-09-06）

用户拍板删。删掉的文件：`PortfolioView.swift`、`HoldingDetailView.swift`、
`HoldingEditorView.swift`、`PositionConfirmationView.swift`、`PortfolioViewModel.swift`、
`CatGallerySheet.swift`，测试侧 `PortfolioViewModelTests.swift`，
以及 `SheetPresentationPolicyTests` 里那条读 `PortfolioView.swift` 源码的用例
（它断言旧页面用 `PawRefreshableScrollView`，页面没了断言也就没了对象）。
`LedgerPortfolioView` 里声明了却从没被构造的 `LedgerTradingView` 一并删除。

删之前要先把三样活着的东西搬出来，否则会连累在用的页面：

- `PortfolioView.qaScrollsToBottom` → 搬进 `CalculatorView`（唯一使用者）。
- `PositionConfirmationSummary.notSet` → 账本页三处在用，改成
  `LedgerFieldPlaceholder.notSet`。
- `CatAvatar.catProfile` → 个人中心的头像详情文案在用，搬到 `Domain/CatProfile.swift`。

**两个坑，记下来免得再踩：**

1. **`project.pbxproj` 按文件名过滤会误伤子串。** 用
   `"PortfolioView.swift" in line` 删条目时，把 `LedgerPortfolioView.swift`、
   `LedgerPortfolioViewModel.swift`、`LedgerPortfolioViewModelTests.swift` 一起删了——
   这三个文件在工程里瞬间失踪，报的却是「cannot find type 'LedgerPortfolioViewModel'」，
   一眼看不出是工程文件的问题。后来靠「磁盘上的 .swift 与 pbxproj 里 `path =` 的差集」
   对出来的，这个差集检查值得留作删文件后的例行校验。
2. **只按「View 有没有被构造」判死活会漏掉同文件里的扩展。**
   `CatGallerySheet.swift` 的两个 View 确实没人构造，但同一个文件底部的
   `extension CatAvatar { catProfile }` 是活的。删完编译才报出来。

**代价**：`CatGallerySheet.swift` 在工作区里有未提交的改动（相对 HEAD 多了一个
`CatInformationSheet`，且已从 `PawTheme` 迁到 Nvwa token），我在删文件之后才用
`git checkout` 去恢复，拿回来的是 HEAD 那份旧的、还在用 `PawTheme` 的版本，
**工作区那份改动没了**。丢掉的内容全部落在「没有入口的猫图鉴弹层」里，
活着的那段扩展已经完整搬走，所以功能上没有损失，但这是一次可以避免的失误：
删之前应该先备份工作区文件，而不是指望 `git checkout` 能还原未提交的内容。

**剩下的死代码（这一轮只盘点，没动）：**

- 旧设计系统里 15 个 `PawControls` 组件有 10 个、7 个 `PawDesignSupport` 组件有 5 个
  已经没人构造：`PawBlock`、`PawFieldLabel`、`PawMetricCard`、`PawPeriodTabs`、
  `PawPrimaryButton`、`PawQuickAmounts`、`PawRefreshableScrollView`、`PawSegmented`、
  `PawSlider`、`PawToggleRow`、`PawBadge`、`PawCard`、`PawFeatureScaffold`、
  `PawIntroHeader`、`PawSectionHeading`。
- 七个领域类型现在**只剩测试在用**（唯一的产品消费者就是刚删掉的那条分支）：
  `HoldingDraft`、`HoldingDraftValidation`、`HoldingRecordMutation`、
  `HoldingPositionAdjustment`、`HoldingMerging`、`CatAgeFormatter`、
  `MarketSessionCalendar`。删它们等于连同各自的测试一起删，要不要删是产品决定。

验证：iPhone 17e XCTest **TEST SUCCEEDED**；`grep` 确认磁盘文件与 pbxproj 条目一一对应。

Exact next task: 见下一节。

## 两批死代码也清了，现在零残留（2026-09-06）

用户「都删了吧」。

**旧 Paw* 组件（15 个）**：`PawControls.swift` 里的 `PawBlock`、`PawFieldLabel`、
`PawMetricCard`、`PawPeriodTabs`、`PawPrimaryButton`、`PawQuickAmounts`、
`PawRefreshableScrollView`、`PawSegmented`、`PawSlider`、`PawToggleRow`，
`PawDesignSupport.swift` 里的 `PawBadge`、`PawCard`、`PawFeatureScaffold`、
`PawIntroHeader`、`PawSectionHeading`。功能都已被 Nvwa 组件取代。两个文件里
其余类型还活着，所以是**按声明删**而不是删文件。

**只剩测试在用的领域类型**：整文件删掉 `HoldingDraft` / `HoldingDraftValidation` /
`HoldingRecordMutation` / `HoldingPositionAdjustment` / `HoldingGrouping` /
`MarketSession`，连同各自的测试文件。另外两处是**部分删**：
`CatProfile.swift` 只删 `CatAgeFormatter`（`CatProfile` 与 `CatAvatar.catProfile` 还活着，
`CatProfileTests` 相应删掉 9 条、留下 2 条）；`PawChrome.swift` 里的
`extension MarketSession { tone }` 跟着枚举一起走。

删完顺手又暴露一个：`PortfolioHistoryBuilder` 和 `PortfolioHistoryResult` 的唯一消费者
就是刚删的 `PortfolioViewModel`，账本的走势图走的是 `LedgerValuation.series`，
所以这两个连同 `PortfolioHistoryTests` 一并删除。**`PortfolioHistoryRange` 和
`PortfolioHistoryPoint` 留着**——账本图表的区间与采样点都在用。

**这次学乖的两件事**（上一轮踩过）：

1. 删任何文件之前先整份拷到临时目录备份，不再指望 `git checkout` 能还回未提交的改动。
2. 改 `project.pbxproj` 一律用精确匹配（`path = X.swift;` 与 `/* X.swift */`），
   不用子串 `in`。删完照例跑一次「磁盘 .swift ↔ pbxproj `path =`」双向差集，这次两边都空。

另外把「按花括号配平删声明」换掉了原来的正则：正则要求结尾是 `\n}\n\n`，
碰上文件里最后一个声明（后面没有空行）会匹配不到——`PawToggleRow` 就是这么卡住的。

**结果**：产品代码里零引用的类型只剩 `PawFolioApp`（`@main` 入口，误报）；
「只剩测试在用」一栏为空。相对 HEAD 净删约 2000 行，源文件 83 个。

验证：iPhone 17e XCTest **TEST SUCCEEDED**。删除前的 17 个文件备份在
本轮 scratchpad 的 `deleted-2026-09-06/` 下（临时目录，重启即失效，需要留档得自己挪走）。

Exact next task: 等用户指认下一处 v2.1.0 界面或规则调整。

## Portfolio 下拉刷新不再显示缺价横幅（2026-09-06）

用户反馈每次下拉刷新都会出现 `Prices are unavailable for 111NSETEST.NS.`。原因是
`LedgerPortfolioViewModel.refreshValuation()` 在每轮行情请求后，把 `failedSymbols` 或最终
`missingAssetCodes` 重新转换成首页常驻 `NvwaHint`；对于暂时无报价或长期无报价的标的，
重复刷新没有可执行的恢复动作，提示只会反复出现。

现在不再把“某个市场标的缺价”写入 `valuationStatusMessage`。缺价事实和估值规则没有改变：
对应持仓与受影响的汇总仍显示 `—`，`portfolioSummary.missingAssetCodes` 仍完整保留；使用缓存
旧价和汇率服务完全不可用的提示也仍然显示。新增 ViewModel 回归测试，模拟
`111NSETEST.NS` 连续请求失败，确认首次失败与再次 `reload()` 后都不出现横幅，同时缺价集合
仍包含该标的。

验证：PawFolio generic iOS Simulator `build-for-testing` 成功；iPhone 17e（iOS 26.4）定向
回归与全量 XCTest 均 `TEST EXECUTE SUCCEEDED`，全量日志记录 292 个通过用例，结果包为
`/tmp/pawfolio-derived/Logs/Test/Test-PawFolio-2026.09.06_19-50-25-+0800.xcresult`。

Exact next task: 真机下拉刷新确认首页不再出现缺价横幅；若需要改善 `—` 的可理解性，另行设计
资产行内的非阻塞缺价状态，不恢复页面级提示。

## Trading / Earn 列表截图比例复核（2026-09-06）

用户指出开发截图与设计稿的列表间距、绿色副字大小看起来差很多。对用户附图做像素测量后确认，
左侧开发图是修正行盒前的旧截图：两枚 Structured Products 图标中心距约 197px，在 3x 截图中
只有约 65.7pt；Figma `211:24982` 的目标值是 78pt（234px @3x）。当前实现重新构建并在
iPhone 17 Pro 模拟器用 `v2.1.1` QA fixture 实拍后，相邻红色产品图标中心距为精确 234px，
即 78pt；截图保存为 `work/list-spacing-qa-current/portfolio-en.png`。

绿色副字继续严格使用设计稿的 `B-S Regular` 12/20、1% tracking 与 Nvwa Market Buy
Light `#1D7353`；主字为 `B-M Semi Bold` 14/22。没有按旧截图观感擅自缩到 11pt，也没有
修改 Nvwa token。Simulator 当前 Content Size 为 Medium，本次实拍未出现动态字体放大。

验证：iPhone 17 Pro（iOS 26.4）Debug build **BUILD SUCCEEDED**；新截图实测行中心距 78pt。

Exact next task: 用当前构建的新截图替换旧验收图；如真机仍显示不同，先记录真机的
Content Size 设置并按同一 3x 比例截图，再判断是否存在设备侧 Dynamic Type 差异。

## v2.1.1 当前构建安装到真机（2026-09-06）

使用 Personal Team `HGTMKU5HMG` 为当前工作区 Debug 构建签名，目标设备为 iPhone 17 Pro Max
「龙」（iOS 26.6.1）。device build **BUILD SUCCEEDED**，随后通过 CoreDevice 成功覆盖安装
`com.jiujiucat.pawfolio`，并已在真机上启动。

Exact next task: 用户在真机核对 Trading / Earn 列表的 78pt 行高、12pt 绿色副字以及刷新时
不再出现缺价横幅；如真机观感仍不同，记录系统 Content Size 后截图复核。

## Trading / Earn 新字号与滚动误触修复（2026-09-06）

用户在设计稿中把两行资产信息调整为：上行 B-L 16、下行 B-M 14。首页 Trading / Earn 与
Earn Holding 三处列表已统一改为 `bodyLargeSemibold` 16/24 和 `bodyMedium` 14/22，继续通过
`.nvwaTextStyle(...)` 保留 token 的字距与行高。列表间 gap 仍为 0、主副字间距 4pt、上下
padding 各 16pt，因此行高和排序步长同步从 78pt 更新为 82pt。模拟器 3x 截图中相邻行中心距
实测 246px，截图在 `work/list-typography-scroll-qa/portfolio.png`。

修复首页与 Earn Holding 无法正常纵向滚动、滑动会打开详情的问题：可点击行不再用会和
ScrollView / 长按排序竞争的 SwiftUI `Button`，改为内容视图上的独立 `onTapGesture`；
VoiceOver 的 button trait、默认打开 action 和上下移动 actions 均保留。长按拖动排序仍使用
原有 sequenced gesture，只有真正拾起行时才禁用 ScrollView。

验证：SwiftPM 321 tests、0 failures；iPhone 17 Pro（iOS 26.4）`build-for-testing` 与全量
XCTest 均成功；device Debug build 成功，并已覆盖安装和启动到 iPhone 17 Pro Max「龙」
（iOS 26.6.1）。

Exact next task: 用户在真机复核首页及 Earn Holding 的 B-L/B-M 字号、上下滚动、单击详情与
长按排序四种交互。

## 首页汇总箭头移除与滚动优先排序（2026-09-06）

首页 `Trading` 的总收益率和 `Earn` 的总收益额右侧箭头已移除；标题行外层 `Button` 保留，
因此点击汇总标题进入对应页面的行为不变。

针对用户反馈的“资产行无法顺滑滚动、滑动会被排序接管”，查阅了 Apple 当前的手势组合建议及
SwiftUI `ScrollView` 手势冲突案例后，将首页 Trading / Earn、Spot 横向资产，以及 Earn
Holding 的排序手势从 `.simultaneousGesture` 改为普通 `.gesture`，让父级滚动识别优先。
排序仍是 `LongPressGesture.sequenced(before: DragGesture)`，但现在必须静止按住 300ms；
按住期间一旦产生位移，长按立即失败，本次输入完整交给 ScrollView。只有长按成立后才设置
dragging 状态并通过 `.scrollDisabled` 锁住滚动，继续拖动完成排序。

同时修复跨分区让位：`overviewReorderOffset` 现在先确认被拖项目属于当前数组；拖 Trading
资产时 Earn 列表不会再读取 Trading 的 origin/destination 并跟着位移，反之亦然。

验证：`git diff --check` 通过；SwiftPM 229 tests、0 failures；iPhone 17 Pro（iOS 26.4）
全量 XCTest 292 tests、0 failures，结果包为
`/tmp/pawfolio-derived/Logs/Test/Test-PawFolio-2026.09.06_20-21-58-+0800.xcresult`；模拟器与
已签名真机 Debug 构建均成功。真机 iPhone 17 Pro Max「龙」本轮显示 unavailable，因此覆盖
安装未完成，已签名 app 在 `/tmp/pawfolio-device-derived/Build/Products/Debug-iphoneos/PawFolio.app`。

Exact next task: 手机连接并解锁后覆盖安装；真机重点复核快速上下滑、静止长按 300ms 后拖拽，
以及拖 Trading 时 Earn 完全不动。

## 滚动优先版本已安装真机（2026-09-06）

已将上述最新签名构建覆盖安装到 iPhone 17 Pro Max「龙」，并成功启动
`com.jiujiucat.pawfolio`。

Exact next task: 在真机快速上下滑 Trading / Earn 资产行，再静止长按 300ms 后拖动排序，
确认滚动优先且两个分区不会联动。

## 排序改用系统 Drag & Drop 并再次安装真机（2026-09-06）

用户真机验证后确认上一版 `LongPressGesture.sequenced(before: DragGesture)` 即使调整手势优先级，
资产列表仍完全无法上下滑动。现已删除首页 Trading / Earn、Spot 与 Earn Holding 行上的自定义
长按/拖动手势、手动位移状态和拖动期间的 `.scrollDisabled`，统一改用 SwiftUI 系统 `.onDrag`
与 `.onDrop`。快速纵向手势由 `ScrollView` 直接处理；只有系统识别长按提起后才进入排序。

新增通用 `LedgerReorderDropDelegate`，经过目标行时继续调用现有 ViewModel move 方法实时排序。
Trading 与 Earn 使用携带分区信息的 `LedgerOverviewReorderItem`，drop delegate 只接受同分区项目，
因此拖动 Trading 不会再让 Earn 跟随移动。VoiceOver 的打开和移动 actions 保持不变。

验证：`git diff --check` 通过；SwiftPM 229 tests、0 failures；iPhone 17 Pro（iOS 26.4）
`build-for-testing` 与全量 XCTest 均成功，结果包为
`/tmp/pawfolio-derived/Logs/Test/Test-PawFolio-2026.09.06_21-30-16-+0800.xcresult`；已签名真机
Debug build 成功。最新 app 已于 21:31 覆盖安装到 iPhone 17 Pro Max「龙」，但设备处于锁屏，
CoreDevice 无法代为启动；用户解锁后可直接从手机启动 PawFolio。

Exact next task: 用户在真机验证快速上下滑动、长按提起后排序，以及 Trading / Earn 跨分区隔离；
如果原生 `.onDrag` 仍影响滚动，采集真机交互复现并评估改用 iOS 17 `draggable` / `dropDestination`
或 UIKit `UIDragInteraction` 的显式 lift 策略。

## 修正排序拖拽预览并替换 OKB Logo（2026-09-06）

用户确认系统 Drag & Drop 版本的上下滑动已经正常，但系统默认会把整行生成缩小的悬浮卡片。
1×1pt 透明 preview 虽隐藏了卡片，却仍会播放从整行缩到 1pt 的动画；把实体行放回 preview
又会让缩小卡片与动画一起恢复。最终实现把两件事拆开：preview 复用原行尺寸但 `.hidden()`，
因此系统没有可见的浮动卡片且不会发生尺寸收缩；阴影则加在列表中当前 `dragging` 的原行上，
并提高其 z-index，保证拖动全程不会被相邻行盖掉。阴影复用 Nvwa 组件现有的
`box-shadow/small`（`#45474533`、零偏移、40pt blur，对应 SwiftUI `radius: 20`）。Spot、首页
Trading / Earn、Earn Holding 四处行为一致，同时继续使用系统手势仲裁。

`AssetLogoCrypto_OKB.imageset/logo.png` 已按用户附件原文件替换为 1280×1280 RGBA Logo；源附件
与目标资源的 SHA-256 均为
`cc78a190ea216693254ba8e00b22c2da81f7a53c3f77823f21daa4f08db1a501`。

验证：`git diff --check` 通过；SwiftPM 229 tests、0 failures；generic iOS Simulator
`build-for-testing` 成功；Personal Team 真机 Debug build 成功。最终版本已覆盖安装到 iPhone
17 Pro Max「龙」。

Exact next task: 用户真机确认长按提起时没有浮动小卡片或缩小动画，列表中的当前排序行在拖动
全程保持阴影，并检查 OKB 在 32pt 行图标尺寸下的清晰度与圆形边缘。

## 排序完全脱离系统 Drag & Drop（2026-09-06）

用户真机截图确认 `.onDrag` 即使提供同尺寸隐藏 preview，iOS 26 仍强制生成白色 lift 卡片并
播放缩小动画；此外 drop 在目标外结束时不会调用 `performDrop`，导致业务侧 dragging 状态未清理，
原行的圆角背景和阴影永久残留。继续调整 SwiftUI preview 无法解决这两个系统行为。

因此 Spot、首页 Trading / Earn、Earn Holding 已彻底移除 `.onDrag` / `.onDrop`，改用透明的
UIKit `UILongPressGestureRecognizer`：300ms 内快速移动超过 10pt 时长按失败，由祖先
`ScrollView` 的 pan 手势优先滚动；静止长按成立后才追踪位移并调用既有 `ReorderDrag` 投影逻辑
实时换位。没有系统 drag session，因此不会创建 lift 卡片，也没有系统缩放动画。

激活态只画在列表中的原行上：无圆角矩形背景、`box-shadow/small` 阴影和更高 z-index；行本身
跟随手指位移。`.ended`、`.cancelled`、`.failed` 以及 recognizer 视图拆除都会统一清理状态，
松手后背景、阴影和 offset 必定归零。Trading/Earn 仍由枚举类型隔离，不能跨分区重排。

验证：`git diff --check` 通过；SwiftPM 229 tests、0 failures；generic iOS Simulator
`build-for-testing` 成功；Personal Team 真机 Debug build 成功。最终版本已覆盖安装到 iPhone
17 Pro Max「龙」。

Exact next task: 用户在真机验证四点：快速上下滑优先、长按 300ms 后原行无缩放跟手、拖动期间
只有原行的直角阴影、松手后阴影立即消失。

## 修复排序手势层吞掉列表轻点（2026-09-07）

用户反馈货币账户首页的 Trading / Earn 列表无法点进详情。根因是上一轮为排序加入的透明
`UIViewRepresentable` 覆盖了整行：它能接收 UIKit 长按，但也让命中测试不再落到下层 SwiftUI
的 `onTapGesture` / `Button`，所以拖动正常而轻点失效。

现在 `LedgerLongPressDragRecognizer` 在同一透明层内同时安装轻点与长按识别器，并让轻点等待
长按失败：短按会打开对应内容，静止 300ms 后仍只进入原有排序；快速滑动仍因 10pt
`allowableMovement` 让长按失败并交给 `ScrollView`。首页的 Spot 货币 chip、Trading 行、Earn 行，
以及 Earn Holding 行都接入了该轻点回调；原有拖动状态、位移投影、阴影、排序提交和滚动锁定
代码没有改动。

验证：SwiftPM 233 tests、0 failures；generic iOS Simulator `build-for-testing` 成功；
iPhone 17（iOS 26.4.1）全量 XCTest 296 tests、0 failures，结果包为
`/tmp/pawfolio-derived/Logs/Test/Test-PawFolio-2026.09.07_11-41-57-+0800.xcresult`。
最新构建安装到同一模拟器后，用坐标触摸（不是 Accessibility `press`）点 Earn 持仓行，已实际
打开对应 Structured Products 明细页。

同一工作区也使用 Team `HGTMKU5HMG` 完成签名真机构建并覆盖安装到「龙」（iPhone 17 Pro Max）；
设备当时锁屏，SpringBoard 拒绝远程启动，解锁后可直接从桌面打开 PawFolio。

Exact next task: 真机复核首页 Spot chip、Trading / Earn 轻点，以及长按 300ms 排序与快速滚动；
重点确认轻点与长按不会在同一次触摸中同时触发。

## 排序交互提取到 Nvwa，并恢复汇率侧滑删除（2026-09-07）

用户要求把已经验收的列表拖动实现提取进组件库，并反馈汇率页的侧滑删除也被透明长按层破坏。
现已在 `ios/Nvwa` 新增 code-only runtime 组件 `NvwaReorderGestureOverlay`、纯几何工具
`NvwaReorderProjection`、共享抬起态 `.nvwaReorderLift(...)` 与对应回归测试。300ms 长按、
10pt allowable movement、1.02 倍抬起缩放，以及 row/chip 阴影参数保持原值。PawFolio 内原本的
UIKit recognizer、拖动阴影 modifier 与 `ReorderDrag` 副本已删除；首页 Spot、Trading、Earn、
Earn Holding 和 Currency 全部改用 Nvwa 实现。

汇率行现在由同一个 Nvwa 命中层仲裁轻点、横向侧滑和长按排序。该层挂在会随手势左移的
`rowBody` 上，而不是包含删除按钮的外层 `ZStack`；因此行左移后，右侧露出的 88pt 删除区域
不再被透明层覆盖。模拟器用 `PAWFOLIO_QA_CURRENCY_SWIPE=MYR` 固定露出 MYR 删除按钮后，
通过真实 Accessibility 点击删除，MYR 已从界面和可访问性树中消失；轻点金额行也仍能进入输入。

验证：PawFolio SwiftPM 218 tests、0 failures；generic iOS Simulator `build-for-testing`
成功；iPhone 17（iOS 26.4）全量 XCTest 成功。`ios/Nvwa` 源码和新增 reorder tests 均完成编译，
但 Nvwa 整包测试仍被既有 `NvwaComponentSpecTests` 调用已删除的 `NvwaInputField(size:validation:)`
参数挡住，属于本轮之外的测试/API 不一致。

Exact next task: 真机复核 Currency 实际左滑手势、点击删除、短按输入、长按排序，以及首页
Trading / Earn 的短按详情和长按排序；若要恢复 Nvwa 独立测试全绿，先同步
`NvwaComponentSpecTests` 与当前 Input API。

## 调整法币账户入口文案与活期赎回（2026-09-07）

按最新产品稿取消了法币账户页 Trading / Earn 分区标题及汇总金额的点击跳转；标题现在只是
heading，产品资产行仍可点击进入明细，并继续复用 Nvwa 的短按、长按排序和滚动仲裁实现，未改动
已经验收的拖动逻辑。法币快捷操作文案由 `Buy Assets` 改为 `Trading`，当前顺序为
`Add / Trading / Earn / Pay`。

修复了活期 Earn 明细页的赎回入口：活期产品点击 Redeem 后进入带金额输入、余额、比例滑杆和
滑动确认的赎回表单，支持部分赎回；定期和结构化产品继续使用仅允许全额赎回的确认流程。新增
回归测试覆盖订阅 100 USD 后赎回 40 USD，确认 Earn 保留 60 USD 且 Exchange 只转入 40 USD。

验证：`git diff --check` 通过；SwiftPM 218 tests、0 failures；generic iOS Simulator
`build-for-testing` 成功；iPhone 17 上活期部分赎回定向 XCTest 与全量 XCTest 均成功。模拟器
实际检查确认快捷操作显示 `Add / Trading / Earn / Pay`，Earn 汇总为 heading 而非 button，
Earn 产品行仍为可点击 button；从 USD Flexible Term 明细点击 Redeem 已显示部分赎回表单。

Exact next task: 真机复核 Trading / Earn 分区汇总不可点击、资产行短按详情与长按排序互不干扰，
并完成一笔活期部分赎回，确认剩余持仓与 Trading 余额同步更新。

## 修复汇率排序阴影停留在原位（2026-09-07）

用户真机截图显示 Currency 行长按拖走后，抬起阴影仍在原布局位置。根因不是手势组件失效，
而是 Nvwa 先前只封装了抬起态，行位移仍由业务页在外层自行追加；Currency 的 modifier 顺序与
Portfolio 相反，SwiftUI 因而先移动内容、再按未移动的布局边界合成阴影。

`.nvwaReorderLift(...)` 现在新增 `offset:`，在组件内部先完成背景、缩放、阴影与 z-index 合成，
最后统一移动整层。Currency、Spot chip、Trading、Earn 与 Earn Holding 均改为把实时位移传进
同一 Nvwa modifier，业务页不再能通过 modifier 顺序把内容和阴影拆开。长按 300ms、滚动仲裁、
横滑删除、目标投影、排序提交和抬起样式参数均未改变。

验证：`git diff --check` 通过；SwiftPM 218 tests、0 failures；generic iOS Simulator
`build-for-testing` 成功；Personal Team 真机 Debug build 成功，并已覆盖安装到 iPhone 17 Pro Max
「龙」。设备安装时处于锁屏，CoreDevice 无法代为启动，解锁后可直接打开 PawFolio。

Exact next task: 真机验证 Currency 拖动时阴影只跟随当前行且原位置无残影，并顺带复核左滑删除
和短按输入仍正常。

## Section 拆成四个组件，首页货币选择器改用 Currency Section（2026-09-07）

Figma `2070:825` 把原来单个 Section 拆成了四个组件集：Primary（`2071:843`，28 高药丸，
选中 `Alpha/Blue 10%` + `Primary Green`）、Sec（`2282:303`，同几何但选中换成 `BG/Vessel` +
`Text/Primary`）、Currency（`2282:248`，36 高、20pt 图标、5pt 间距，选中 `BG/Vessel`）、
Text（`2282:236`，无底色、16pt 图标、`B-S Regular`）。`NvwaSection` 相应改成
`NvwaSectionStyle` 四档 + 一个宿主注入的泛型图标槽位（沿用 `PawSingleSelectSheet` 的
`where Icon == EmptyView` 写法），旧的 `NvwaSection(_:isSelected:expandsHorizontally:action:)`
调用点不受影响。组件目录补上了四档实例，`ios/Nvwa/FIGMA_COMPONENTS.md` 新增「Section」一节
记录节点、几何和三处稿子上就有的差异。

首页法币账户那排货币选择器（`LedgerPortfolioView.spotAssetChip`）不再手搓药丸，改为
`NvwaSection(style: .currency)`，业务页只注入国旗 / 币种图和 0.5pt `Line` 描边。宽度测量、
`nvwaReorderLift`、拖动位移与 `NvwaReorderGestureOverlay` 的仲裁全部保持原样，组件自带的
`accessibilityAddTraits(.isSelected)` 是净增益。

稿子上三处刻意的差异已按原样落地，不要"顺手统一"：Currency 两态文字同色（都是
`Text/Primary`，不跟 Primary 那档换成蓝色）；Currency 圆角 66 超过半高，落地为胶囊，而
Primary / Sec 的 24 保留 `RoundedRectangle`；只有 Text 那档是 Regular 且保留首尾
half-leading（它没有固定高度容器，20 就是行盒）。Currency 稿子上的文字是 unbound 纯黑，
代码映射到 `Text/Primary`，深色下才会跟着翻白。

顺带修掉了上一轮列为 next task 的测试/API 不一致：`NvwaComponentSpecTests` 里
`NvwaInputField(size:validation:)` 的调用改成当前签名，Nvwa 整包测试恢复可跑。

验证：Nvwa 52 tests、0 failures；PawFolio SwiftPM 218 tests、0 failures；generic iOS
Simulator `build-for-testing` 成功。iPhone 17 Pro 模拟器用临时账本 fixture（CNY/EUR/USD/USDT
四笔入金，验证后已删除）截图复核：选中药丸实测 36.0pt 高，浅色为 `#EFEFEF`、深色为 `#212121`，
未选中透明且文字与选中同色，深色下文字整体翻白。

Exact next task: 真机复核货币 chip 的短按切换与长按排序在换成 `NvwaSection` 后仍互不干扰；
Sec / Text 两档目前只有组件目录里的实例，等产品稿指定用处再接入页面。

## 优化首页排序拖动的逐帧刷新范围（2026-09-07）

用户反馈 Currency 的拖动位移比首页流畅，首页卡片跟手时有卡顿。根因是首页把实时
`translation` 存在 `LedgerPortfolioView` 的父级 `@State`：手指每移动一帧都会让整个首页
重新求值，连带重算余额、估值、利息、图表和 Logo。Currency 页面结构更轻，所以同一套视觉
效果下卡顿不明显。

Nvwa 现新增组合入口 `.nvwaReorderable(...)`，把手势命中层、抬起态和实时位移合到每个可排序
项目自己的 modifier 中；每帧位移只更新当前行的局部 `@State`。业务页仍会接收 translation
用于目标投影，但只有跨过另一行、目标下标确实变化时才更新父级状态。Currency、首页 Spot、
Trading、Earn 与 Earn Holding 已全部迁移到同一入口，旧的父级逐帧 translation 状态已删除。

本轮没有调整已经验收的 300ms 长按、10pt 滚动仲裁、抬起缩放/阴影、让位动画、跨分区隔离、
Currency 右滑删除、短按进入详情或松手后才提交排序的行为。Better Frontend 的高频动效原则用于
限制更新范围，没有新增装饰性动画。

验证：`git diff --check` 通过；Nvwa 52 tests、0 failures；PawFolio SwiftPM 218 tests、
0 failures；generic iOS Simulator `build-for-testing` 成功；Personal Team 真机 Debug build 成功，
并已覆盖安装到 iPhone 17 Pro Max「龙」。设备当时锁屏，CoreDevice 无法代为启动，解锁后可直接
从桌面打开 PawFolio。

Exact next task: 真机对比首页 Spot / Trading / Earn 与 Currency 的拖动跟手度，并回归 Currency
右滑删除、短按输入以及资产行短按详情。

## 排序位移限制在列表主轴（2026-09-07）

用户真机确认局部状态优化明显改善流畅度，同时发现纵向资产行会跟随手指左右漂移。共享
`.nvwaReorderable(...)` 现增加显式 `axis`，默认 `.vertical`：Currency、首页 Trading / Earn
和 Earn Holding 的实时位移及让位位移都会把 x 强制归零，只能上下移动；首页 Spot 横向币种条
显式使用 `.horizontal`，只保留 x 位移并把 y 归零。识别器仍读取完整手指轨迹，因此 300ms 长按、
滚动仲裁和 Currency 右滑删除不受影响。

新增 Nvwa 回归测试覆盖两个轴向的正交位移归零。验证：`git diff --check` 通过；Nvwa 53 tests、
0 failures；PawFolio SwiftPM 218 tests、0 failures；generic iOS Simulator `build-for-testing`
成功；Personal Team 真机 Debug build 成功。最终版本已覆盖安装并成功启动到 iPhone 17 Pro Max
「龙」。

Exact next task: 真机验证 Trading / Earn / Currency / Earn Holding 拖动时完全没有横向漂移，
并确认 Spot 仍只沿横向排序。

## 排序交互完整收口为 Nvwa 公共组件（2026-09-07）

用户确认当前排序手感、位移与视觉已经达到预期，要求把相关交互和样式完整封装，避免后续业务页
复制或重写时再次破坏。Nvwa 现在只向业务层暴露 `NvwaReorderState`、`NvwaReorderLayout`、
`NvwaReorderMove` 和统一入口 `.nvwaReorderable(...)`；300ms 长按、滚动/点击/横滑仲裁、点击抑制、
横纵轴约束、逐帧局部位移、目标投影、相邻项让位、抬起缩放/背景/阴影/z-index、Reduce Motion、
松手动画、分区隔离、VoiceOver 移动计算与反馈计数均由组件内部负责。底层 UIKit 手势层、投影工具、
抬起样式 modifier 和所有交互常量不再作为业务 API 暴露。

Currency、首页 Spot、首页 Trading、首页 Earn 和 Earn Holding 五类调用已全部迁移。每个独立列表只
保留一个 `NvwaReorderState<ID>`，业务页只提供当前顺序、布局以及最终 `onMove`；实时手指位移不会再
逐帧刷新整个首页。Spot 显式使用横向布局，其他列表使用纵向布局；Trading / Earn 虽共用枚举 ID，
仍由各自传入的 items 自动隔离。Currency 的右滑删除继续通过同一入口仲裁，未改变已验收行为。

验证：残留搜索确认旧的 origin/destination、逐帧 translation、tap suppression 和 lift 样式状态均未
留在业务页；`git diff --check` 通过；Nvwa 57 tests、0 failures（其中 reorder 20 tests）；PawFolio
SwiftPM 218 tests、0 failures；generic iOS Simulator `build-for-testing` 成功；Team `HGTMKU5HMG`
签名真机 Debug build 成功。当前包已覆盖安装到 iPhone 17 Pro Max「龙」
（`05FAD045-9A8E-536B-8766-CA830DA04D6C`），安装保留 App 数据；设备处于锁屏，自动启动被
SpringBoard 拒绝，解锁后可直接打开。

Exact next task: 以后新增可排序列表只使用 `.nvwaReorderable(...)`，不得在 Feature 中复制手势、
位移、抬起样式或点击抑制；真机最终抽查 Spot、Trading、Earn、Earn Holding、Currency 排序以及
Currency 右滑删除。

## Nvwa 新增三组 Dropdown 组件（2026-09-07）

用户提供 Nvwa Figma `2070:825` 的最新链接。通过官方 Figma design context 读取后确认，原四档
Section 下新增三组组件：Text Dropdown Button（`2285:342`）、BG Dropdown Button（`2285:355`）
和 Dropdown Menu（`2286:449`）。现已新增 `NvwaDropdown.swift`，公开
`NvwaTextDropdownButton`、`NvwaBackgroundDropdownButton` 与泛型单选 `NvwaDropdownMenu`；
四档文字 trigger、40/24 两档背景 trigger、113×172 菜单、选中勾、主/次文字色、圆角、行盒与
两层 `shadow2` 均按节点实值实现。组件目录、README、`FIGMA_COMPONENTS.md` 和规格测试同步更新。

继续遵守 Nvwa 不打包通用图标的边界：两个 trigger 使用宿主注入的 Remix
`arrow-down-s-fill`，菜单使用宿主注入的 `check-line`。Figma 导出路径已与 PawFolio 现有
`IconArrowDownSFill` / `IconCheck` SVG 核对一致，未新增重复资源。

待设计确认项：`2285:355` 仍绑定旧的 Binance Nova `Mobile/subtitle2,14 Medium` 与
`Mobile/subtitle3,12 Medium`，而当前 Nvwa 的正式排版体系和仓库字体均为 Inter。代码保留了
14/22、12/18、Medium、零字距的精确度量，但使用 Nvwa 已打包的 Inter 渲染；没有引入来源和
授权不明的 Binance Nova。`2286:449` 的旧 Mobile 次文字浅色值 `#757575` 按稿保留，深色回落到
Nvwa `Text/Secondary`；背景映射到动态 `BG/Main`。

验证：`git diff --check` 通过；Nvwa 60 tests、0 failures；PawFolio SwiftPM 218 tests、
0 failures；generic iOS Simulator `build-for-testing` 成功。iPhone 17 Pro Max 模拟器打开 DEBUG
组件目录实拍核对：四档文字 trigger、40/24pt 背景 trigger、113×172pt 菜单、20pt 勾与两层阴影
均正常，截图为 `/tmp/nvwa-dropdown-catalog.png`。

Exact next task: 设计侧确认是否把 `2285:355` 的两枚旧 Binance Nova/Mobile text style 正式改绑
到 Nvwa/Inter token；产品页需要下拉交互时直接复用这三组组件，不要在 Feature 内重画。
