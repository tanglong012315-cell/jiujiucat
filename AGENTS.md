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
- Unless the user explicitly asks otherwise, future frontend work targets iOS only; do not mirror it to the Web app automatically.
- PawFolio parity screens continue to use the Web layout as their reference, but the standalone `ios/Nvwa` package takes its tokens and component geometry from the latest Nvwa Figma library. Do not roll newer Nvwa values back to older Web values, and do not mirror Nvwa-only updates to the Web unless the user explicitly asks.
- In design-led iOS work, every element must first be matched to an existing `ios/Nvwa` token or component. Reuse that implementation instead of recreating or locally restyling it in a feature view. If a product design instance conflicts with the latest Nvwa component, record the Figma node and the exact differing properties for user confirmation; until confirmed, the Nvwa component is authoritative and feature code must not override it. Create or extend a Nvwa component only when the library genuinely has no matching component.
- Reproduce the Web layout structure: the header with account avatar, rotating market ticker and theme toggle, and the three-tab bottom bar. Do not re-cut screens into iOS navigation patterns.
- Do not add furniture the Web does not have. The introduction cards, section subtitles, and decorative paw badges that were added natively are not in the Web app and should be removed as each screen is ported.
- When a stock SwiftUI control cannot match the Web appearance, build a custom one. Matching the Web wins.
- **Exception, the bottom tab bar (user's decision of 2026-08-31).** iOS 26+ uses the system `TabView`, not a hand-built bar. Apple's Liquid Glass tab bar has a drag-scrubbing glass capsule with per-channel chromatic dispersion at the rim and a native release spring; a custom bar cannot reach that, because the dispersion comes from Apple's glass shader sampling the backdrop and is not reachable through any public API. Only the brand tint is overridden (`Nvwa.ink` instead of iOS blue). iOS 17–25 still falls back to `PawTabBar`. This exception covers this one control — everything else still follows the rule above.
- Keep monospaced digits for money. Financial gains/losses use Nvwa Market Buy/Sell, flat values use Gray Secondary, and destructive/error UI uses Sentiment Negative.
- Do not bundle a general icon set in Nvwa. Source UI icons from Remix Icon and inject them into Nvwa components; component-owned structural artwork such as a tooltip pointer may remain internal. The nine Key Feature glyphs in Figma node `2029:9063` are the explicit exception: treat them as component-owned illustrations, bundle their original artwork in Nvwa, and do not substitute Remix icons.
- Preserve the cat identity, including the brand state illustrations in `public/illustrations/`.
- **Loading indicator exception (user's decision of 2026-09-03):** all iOS loading states use the
  native circular SwiftUI `ProgressView`. Pull-to-refresh keeps the native iOS spinner, but the
  Portfolio interaction uses the shared `PawRefreshableScrollView`: it triggers at 80pt, gives one
  medium haptic, and holds the content down until the async refresh finishes. Do not restore the
  animated loading cat or introduce a custom spinner. This exception does not remove the other
  brand state illustrations.
- The Web cat-gallery easter egg and its long-press photo viewer were removed by the user on
  2026-09-03. Do not restore those Web overlays or gestures. Keep legacy `cat:<id>` avatar decoding
  so existing synced profiles continue to render their saved avatar.
- **Adaptive bottom-sheet sizing (user's decision of 2026-09-06, superseding V1.2.3):** bottom
  dialogs use one shared content-driven policy. Header, intrinsic middle content, and footer determine
  the natural height; the sheet grows smoothly until its top is 80pt from the current window's top,
  then only the middle `ScrollView` scrolls while header and footer remain visible. Use the native
  SwiftUI `.sheet` presentation through `PawSheet` or `.pawSheetPresentation()`; do not add raw
  detents, `.half` / `.full` choices, screen-literal heights, or window-level custom overlays.
  `fullScreenCover` remains reserved for explicitly designed full-screen destinations such as Account
  and Login, not dialogs.

### 设计稿是像素级的验收标准（用户 2026-09-03 定的规则）

**从 v1.2.0 起，每一个版本的界面开发都必须照用户提供的设计稿像素级还原。** 用户会为
每个版本给出设计稿链接，那份稿子就是验收标准。

- **产品稿在 `ThlaCizGXDV4puXbtg8Fk0`（Pawfolio Design）**，Nvwa 组件库在
  `B7QSpRFNAt2tZ6S2JiG3Ij`。两个文件不要搞混：产品页面的节点号在前者，组件几何和
  token 在后者。已知节点：汇率页 `110:3141`。
- **动手前先 `get_design_context` 把目标节点拉下来**，按里面的实际数值写间距、字号、
  字重、字距、行高和颜色 token。**不许照着截图目测，更不许按「看起来合理」自己编。**
  拿不到节点就问用户要带 `node-id` 的链接，不要先写再对。
- 写完要在模拟器上截图，和设计稿逐项比一遍（间距、对齐、字号、颜色、状态），差异要么
  改掉，要么写进 `ios/HANDOFF.md` 明确列为待确认项。
- **和设计稿不一致的地方，一律先问，不要自作主张统一。** 看着"不一致"的东西往往是
  设计上故意的区分——例如 Currency 页右上角的「+」是中性灰、持仓页是蓝色 primary，
  那是**为了区分「添加货币」和「新增持仓」两个功能**，不是漏改。
- **排版一律走 `.nvwaTextStyle(token)`，不要只写 `.font(...)`。** 稿子上的字距和行高
  是 token 的一部分，`Nvwa.bodyMedium` 这类简写常量只返回 `Font`，会把两者静默丢掉。
  单行文字放在固定高度容器里时传 `linesFillLineHeight: false`（只关掉首尾的
  half-leading），多行正文保持默认。细节和那两条钉死它的测试见
  `ios/Nvwa/FIGMA_TOKENS.md` 的「行高和字距怎么落到代码里」。
- 这条规则不改变既有约束：元素仍然要先在 `ios/Nvwa` 里找现成的 token 和组件来用；
  库里确实没有的才扩展组件，而不是在业务页里就地重描一套样式。

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
