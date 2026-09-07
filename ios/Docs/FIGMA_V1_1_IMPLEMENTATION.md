# PawFolio iOS — Figma V1.1 implementation

Source: Pawfolio Design, node `63:7397`.

The Figma file is the visual and copy source of truth for this migration. All
screens remain native SwiftUI, target iOS 17, and use the Nvwa package for
tokens and shared components. User-facing copy is English; wording may be
polished when the source copy is grammatically awkward without changing its
meaning.

## Work queue — keep this current

This is the hand-off record. Update the status column **as each item lands**, not
at the end of a session, so an interrupted run can be picked up by anyone.
Statuses: `todo`, `wip`, `done`, `blocked`.

| # | Screen / task | Node | Status | Notes |
| --- | --- | --- | --- | --- |
| 1 | Currency amounts to Text Primary | `63:7007` | done | Design was changed on 2026-09-02; the node no longer binds any green. |
| 2 | Bottom navigation copy | — | done | `PawFolio / Calculate / Currency`. Control itself untouched. |
| 3 | Add position, 3 states | `29:1427` `40:2369` `68:7629` | done | Batch 5a. |
| 4 | Position confirmation, 3 states | `45:818` `45:819` `68:7817` | done | Batch 5a. |
| 5 | Symbol search, 3 states | `43:2617` `43:2851` `43:3053` | done | Batch 5a. |
| 6 | Populated portfolio list | `47:1090` `73:9277` | done | Chart range control was hand-rolled and sat below the chart; it is now `NvwaSegmentControl` above the chart. |
| 7 | Hidden-assets style | `21:381` | done | Already matched; no change needed. |
| 8 | Cat gallery / avatar easter egg | `47:2336` | done | Native remains; the Web counterpart and long-press viewer were explicitly removed on 2026-09-03. |
| 9 | Edit stock position | `43:3538` | done | Layout and behaviour both confirmed against the product rules of 2026-09-02. |
| 10 | Stock P&L details + price chart | `46:923` | done | New `stockSheet`; the interest kind still uses the legacy sheet until item 11. |
| 11 | Stablecoin P&L details | `68:7943` | done | Shares the stock sheet's field block and record rows. |
| 12 | Interest payout history | `68:8061` | done | Shared `recordsSheet`: month headings, date/amount rows, OK footer. |
| 13 | Position adjustment history | `70:8201` | done (needs populated QA) | Same sheet plus signed amounts and a per-row delete. The QA seed has no adjustment records, so only the empty state was seen on device. |
| 14 | Final copy audit and visual QA | — | done | See the audit below. |
| 15 | Delete the dead legacy detail/editor code | — | done | 1,235 lines removed across the two views. |
| 16 | Translate `Data` / `Domain` error copy | — | todo | ~33 `LocalizedError` strings still in Chinese; they surface in alerts. |

### Open decisions blocking work

| Item | Question |
| --- | --- |
| Search row quotes | Rows now fetch a quote per visible result, which is new network traffic on every search. |


### QA hooks used for screenshots

This machine cannot tap the Simulator, so states are reached with `#if DEBUG`
environment hooks and captured with `xcrun simctl io … screenshot`:
`PAWFOLIO_INITIAL_TAB`, `PAWFOLIO_OPEN_EDITOR`, `PAWFOLIO_QA_ADD_KIND`,
`PAWFOLIO_QA_CONFIRMATION`, `PAWFOLIO_QA_ASSET_SEARCH`, `PAWFOLIO_QA_ACCOUNT`,
`PAWFOLIO_QA_PORTFOLIO`, `PAWFOLIO_OPEN_DETAIL`, `PAWFOLIO_EXPAND_GROUP`.

## Nvwa-first implementation rule

- Match every product-design element to `ios/Nvwa` before writing feature UI.
- Reuse Nvwa geometry, typography, colours, and interaction states without
  feature-level overrides.
- If a PawFolio design instance differs from the latest Nvwa library, log the
  node and exact properties below and ask for product confirmation. Nvwa remains
  authoritative until the conflict is resolved.
- Add a PawFolio-only composition only when no Nvwa component exists. General
  icons remain host-injected Remix Icon assets. The nine Key Feature glyphs are
  the explicit exception: Nvwa owns them as Figma-authored illustration artwork.

### Open design conflicts — first-row audit

| PawFolio node | Product design | Latest Nvwa | Interim implementation |
| --- | --- | --- | --- |
| `73:9387` signed-in top navigation | Avatar text 14 pt Medium; add glyph 24 pt | Navigation/Profile `2102:1169`: avatar text 16 pt Semibold; glyph 20 pt | Use `NvwaNavigationBar` values |
| `73:9387` signed-out top navigation | Master is 64 pt with a Large outline button, while screen instance `73:9392` is compressed to 60 pt and overrides the button to Small | Nvwa has no signed-out navigation variant; navigation height is 60 pt and both button sizes are valid components | Add a 60 pt Nvwa signed-out composition using the screen's Small outline button |
| `47:2224` account hero avatar | 72 pt with 30 pt text | Avatar `2014:7932`: 42 pt with 16 pt Semibold text | **Resolved 2026-09-02.** `NvwaAvatar` takes `diameter` / `fontSize` / `tracking` instead of hard-coding one of the two authored sizes. |

The first-row Tag, Checkbox, Section, Input, Modal Header, Secondary Button,
Primary Button, and Outline Warning Button instances otherwise match their
current Nvwa counterparts and must use those components directly.

The refreshed login sheet node `73:9477` now uses the 40 pt Nvwa outline/social
button with a 16 pt Google icon and the label “Login with Google”; the earlier
48 pt primary-button mismatch no longer exists.

## Confirmed product changes

- Remove the rotating market ticker and the header theme toggle.
- Show the profile/add navigation only on PawFolio, not on Calculate or Currency.
- Keep the green header add button as the primary add-position entry point.
- Remove the quick-add recommendation section and its quote requests.
- Currency: every amount is editable; the focused currency becomes the base and
  updates the other rows in real time.
- Currency: the active row shows the currency's full English name; other rows
  show their exchange rate against the active currency.
- Calculator: match the new flat layout and replace the dotted forecast graphic
  with the line-chart card shown in Figma.
- Stock P&L details will gain the annotated market-price chart in a later batch.
- Stablecoin position editing is now ready and is included in the migration.
- The bottom navigation is explicitly out of scope: keep its existing code and
  behavior, and do not use the Figma bottom navigation as an implementation or
  visual-QA reference.
- Anything whose design or behavior remains ambiguous stays unchanged or empty
  until product confirmation; do not invent functionality.

## Token scan — 2026-09-02

The V1.1 screens use the current Nvwa roles already represented by `ios/Nvwa`:

| Role | Value |
| --- | --- |
| Core Bright Blue | `#6999FF / #4782FF` |
| Primary Green | `#0051FE / #2D66F0` |
| Text Primary | `#000000 / #FFFFFF` |
| Text Secondary | `#868685` |
| BG Main | `#FFFFFF / #000000` |
| BG Vessel | `#EFEFEF / #212121` |
| BG Input | `#EFEFEF / #1D1D1D` |
| Line | `#DEDEDD / #2B2B2B` |
| Market Buy | `#459811 / #65C02C` |
| Market Sell | `#CE2632 / #F0616D` |
| Sentiment Negative | `#A8200D / #DC432D` |

The file also exposes a legacy `Background Colors/BG Light` value of `#ECEFEB`.
It is not bound to the confirmed PawFolio V1.1 frames, so it must not replace the
newer `NVWA/BG/Input` or `NVWA/BG/Vessel` value.

## Delivery outline

| Batch | Scope | Status |
| --- | --- | --- |
| 1 | Root shell, PawFolio header, removal of ticker/quick add | In progress |
| 2 | Currency layout and multi-input conversion | In progress |
| 3 | Calculator layout, interaction, and chart | In progress |
| 4 | Account and theme selection | Pending |
| 5 | Portfolio populated states and add/edit flows | Add-position flow complete; populated list and stock editing pending |
| 6 | Stock P&L details and market-price chart | Pending |
| 7 | Stablecoin position editing | Complete |
| 8 | Remaining confirmed screens, copy audit, visual QA | Pending |

## Per-screen source nodes

- PawFolio empty state: `7:7`
- Calculator: `46:1483`
- Currency: `63:7007`
- Account: `47:2085`
- Stock P&L details: `46:923`
- Stablecoin position editing: `72:9065`

Each batch is complete only after a simulator build, relevant tests, and a
screenshot comparison against its source node.

## Batch 7 — stablecoin position editing

- Added a dedicated native SwiftUI editor matching node `72:9065`: English
  title/copy, add/reduce segment, amount, APR, effective date, note, estimated
  daily dividend, Save, and Delete.
- Amount, APR, effective date, and note are committed atomically. APR changes
  append dated history; historical and future effective dates are supported.
- The editor does not expose or modify the holding's simple/compound mode.
- The custom date field was tapped in Simulator and confirmed to open the
  system calendar while preserving the Figma appearance.
- Final visual QA used the 375 pt layout. The bottom navigation remained out of
  scope and was not used as a comparison target.
- Verification: Nvwa 11/11 tests, PawFolio SwiftPM 164/164 tests, named
  simulator XCTest 175/175 tests, and simulator `build-for-testing` succeeded.


## Batch 5a — add-position flow (second row of `63:7397`)

Covers the nine frames at y=2024: `29:1427`, `40:2369`, `68:7629` (Add Position),
`45:818`, `45:819`, `68:7817` (Position Confirmation), and `43:2617`, `43:2851`,
`43:3053` (symbol search), plus the success toast `46:914`.

- Only the **new-position** path was rewritten. Editing an existing stock
  position still uses the old `standardEditor`; that is node `43:3538` and
  belongs to a later batch, so it was left untouched.
- Save no longer writes straight through. It validates the draft, shows
  `PositionConfirmationView`, and only writes on Confirm, then raises the
  `Successfully added` toast.
- `AssetSearchView` was rebuilt around `NvwaModalHeader` and `NvwaSearchInput`;
  the view model is unchanged apart from per-result quote loading.

### Nvwa additions this batch

All four are Figma-authored shapes the package did not expose yet:

| Addition | Reason |
| --- | --- |
| `Nvwa.bodySmallSemibold` | `B-S Semi Bold` is in the library text-style table but had no token. Used by `Still Use This Symbol`. |
| `isRequired` on `NvwaInputField` / `NvwaSearchInput` | The required-field `*` is Sentiment Negative inside the label. Every PawFolio instance types it into the label text; the package now renders it. |
| `focus` on `NvwaSearchInput` | `.focused` only binds to a real `TextField`, so a host cannot focus the field from outside the component. |
| `highlight` on `NvwaHint` | `Est. Dividend: 12.23 USD` puts the value in Primary Green inside one hint. |

### Open design conflicts — second-row audit

| PawFolio node | Product design | Current app | Interim implementation |
| --- | --- | --- | --- |
| `43:2851` search rows | Each row shows last price and day change | `AssetSearchResult` carries no price; search returned symbol metadata only | Quotes are now fetched per visible result through the existing `MarketDataServing.quote`. This adds network calls on each search; confirm that is wanted before it ships. |
| `68:7629` Interest Calculation | `CI` is selected in the default add state | `HoldingDraft.interestMode` defaults to `.simple` (SI) | Left at SI. Changing it silently changes how new positions accrue, so it needs product confirmation, not a UI-driven default flip. |
| `68:7629` / `68:7817` `Pay Date` | Labelled `Pay Date` | Interest positions have only `interestStartDate`, which batch 7 labels `Effective Date` | Bound to `interestStartDate` with the Figma label. The two screens now call the same field different things; one of the labels should win. |
| `45:818` `Total Assets` | `18,190.48 USD` against `23.449052` shares and a `739.14 USD` cost price — the implied unit price is not the cost price | — | Computed as shares x market price, falling back to cost price when no quote is available. |

### Copy corrections

The source frames contain three typos, corrected under the copy rule at the top
of this document: `Postion Confirmation` and `Postion` to `Position`, and the
button `Confrimation` to `Confirm`.

### Sheet heights

**Superseded again by the adaptive-modal decision on 2026-09-06.** Bottom
dialogs now use one shared content-driven policy through `PawSheet` or
`.pawSheetPresentation()`. Header, intrinsic middle content, and footer determine
the natural height. The native SwiftUI sheet grows smoothly as filtering,
validation, or conditional fields change, up to an 80pt top clearance in the
current window; after that, only the middle `ScrollView` scrolls. Feature views
must not introduce raw detents, `.half` / `.full` choices, screen-literal heights,
or window-level custom overlays.

### Verification

Nvwa 14/14, PawFolio SwiftPM 164/164, simulator `build-for-testing` succeeded,
and all nine frames were screenshot-compared on a 402 pt iPhone 17 Pro. The
add-position sheet measured 651 pt against the 642 pt Figma frame.


## First-row audit after the interrupted session — 2026-09-02

The annotated items on the first row are all in place:

| Annotation | Where it landed |
| --- | --- |
| Default avatar uses initials | `NvwaNavigationBar(profileInitials:)` and the account hero |
| Signed-out shows `Login` | `PortfolioView.topNavigation` |
| Green add entry | Present in both navigation variants |
| 0.5 pt border on every logo | Both position rows and the search row overlay `Circle().strokeBorder(Nvwa.line, lineWidth: 0.5)` |
| Illustrations at 120 pt | `AccountView`, the empty positions state, and the login sheet |
| User name | Account `User Name` field |

No untranslated copy remains in `PortfolioView`, `AccountView`,
`CatGallerySheet`, or `RootTabView`.

### Fixed in this pass

- Bottom navigation titles were still `投资组合 / 计算 / 汇率`. Figma labels them
  `PawFolio / Calculate / Currency` and the rest of the app is English, so
  `PawTab.title` now uses the Figma copy. **The control itself is unchanged**;
  the out-of-scope rule above still applies to how the bar is built.

### Resolved — Currency amount contrast in dark mode

An earlier scan mapped converted amounts to the removed fixed Forest Green.
The current Nvwa library no longer exposes that obsolete token, and
`ExchangeRateView` now uses dynamic `Text/Primary` (`Nvwa.grayPrimary`) for the
amounts. They therefore remain legible in both colour schemes.

### Still outstanding by batch

Batches 4, 6, and 8 remain open. Batch 4's account screen matches `47:2085`
apart from the hero-avatar size conflict already logged in the first-row audit
table (42 pt in Nvwa against 72 pt in the product design).


## Stock position editing — confirmed product rules, 2026-09-02

These came from the product owner and settle the questions the batch had been
carrying. The `Shares` field's stray `USD` unit was a design slip and has been
removed at source.

1. **The edit sheet only adds or reduces the position.** The existing quantity
   and its cost basis are no longer editable. Correcting them means deleting an
   adjustment record or deleting the whole position.
2. **Adjustments take effect immediately.**
3. **`Cost Price` on this sheet is the price of *this* add/reduce**, not the
   position's cost basis. Left blank it falls back to the latest market price,
   which is why the field shows that price as its placeholder.
4. **The note replaces the previous one on every edit**, and is not displayed
   when empty.
5. **Dividend settings can be changed at any time and overwrite the previous
   ones — except for a dividend that has already been paid.** A paid dividend is
   only removable by the user.

### How Save commits

One Save now writes everything, in a fixed order:

1. Save the draft (note and dividend settings). The draft's `quantity` is the
   value the sheet opened with, and rule 1 means nothing on screen can change
   it, so this write leaves the position size alone.
2. Apply the adjustment, if `Shares` was filled.

**The order matters and must not be flipped.** Adjusting first and saving second
would write the sheet's opening `quantity` back over the position that was just
adjusted — the failure the long comment in `HoldingEditorView` describes. If
step 1 fails, step 2 is skipped and the error surfaces.

### Paid dividends

`DividendRecord.isPaid(asOfMilliseconds:)` was added to `Domain`: a record counts
as paid once its pay date has arrived, the pay day itself included, on the same
Beijing-time basis the rest of `HoldingValuation` uses. A record with no pay date
is still planned and stays overwritable.

`HoldingDraft.makeHolding` now only rewrites the tracked dividend record when it
is *not* paid; once it is paid, changing the settings appends a new record and
leaves the paid one alone. Covered by
`HoldingRecordMutationTests.testPaidDividendRecordIsRecognisedByPayDate`.


## Batch 6 — P&L details and record lists

- `HoldingDetailView` now has three sheets: `stockSheet` (`46:923`), `earnSheet`
  (`68:7943`), and the legacy sheet, which nothing routes to any more but is
  kept until the dividend list has its own design.
- The price card takes its numbers from `model.quotes`, which already carries
  price, day change, series, and the market timestamp, so no new fetching was
  added. The design annotation on that card asked for the market price to be
  shown, which is the `1 BTC = …` line.
- Interest and adjustment records share one `recordsSheet`. Month buckets come
  from the record dates; the adjustment variant adds signed amounts and a
  per-row delete.

**Bug found and fixed while doing this.** The editor, records, and confirmation
sheets were all attached to the *legacy* detail sheet's modifier chain. Once the
new sheets took over routing, the record rows and the Edit button had nothing to
present — tapping them did nothing. The chain is now hoisted into
`withDetailRoutes(_:content:)` and applied to whichever sheet is showing.


## Batch 8 — copy audit, 2026-09-02

Swept every user-visible string, VoiceOver labels included, across the app.

### Translated

- Bottom navigation, five VoiceOver labels (`PawSheet` close/delete, the clear
  button, pull-to-refresh, the portfolio chart), the dividend record list, the
  dividend record editor, and the frequency picker.
- `DividendFrequencySheet` lost its `usesEnglish` flag; the whole app is English,
  so the Chinese branch had no callers left.

### Regression found and fixed

The new detail sheets routed only to interest and adjustment records, so the
**dividend records list and its editor became unreachable** — an existing
feature silently dropped. `46:923` has no dividend-records entry and there is no
Figma screen for that list, so the design would not have caught it. A
`N Dividend records` row now appears on the detail sheet for dividend holdings,
in the same style as the other record rows, pending a design.

### Defect found in someone else's concurrent change

`HoldingPositionAdjustment` had its sale note translated to
`"Proceeds from \(symbol) sale"`. Notes are capped at
`Holding.noteCharacterLimit` (20) and `normalizedNote` **truncates silently**, so
every sale produced `"Proceeds from AAPL s"`. Shortened to `"Sold \(symbol)"`,
and the test now also asserts the note stays within the limit so a long
replacement cannot reintroduce it.

### Still Chinese, and why

The remaining Chinese sits entirely in code nothing routes to any more: the
legacy `sheet(for:)` cluster in `HoldingDetailView` (`summary`, `breakdown`,
`latestDividendCard`, `recordEntries`, `recordButton`, `interestIncomeList`,
`activityList`, `recordSummary`, `recordEmptyState`, `frequencyText`,
`webLabel`) and `standardEditor` with its helpers in `HoldingEditorView`
(`identityFields`, `valueFields`, `adjustmentPanel`, `rateChangePanel`,
`incomeToggle`, `interestFields`, `dividendPanel`, `yieldPreview`), plus
`DividendFrequency.controlTitle`, which only those views still reference.

Removing them is item 15. It is kept separate on purpose: it is roughly a
thousand lines across two files and deserves its own reviewable diff rather than
being folded into a copy audit.


## Product decisions closed — 2026-09-02

All three questions this batch had been carrying are settled.

### Avatar size is no longer pinned to one authored value

`NvwaAvatar` hard-coded the 42 pt / 16 pt pair from `2014:7932`, so the account
hero could not be the 72 pt / 30 pt avatar `47:2224` actually calls for. It now
takes `diameter`, `fontSize`, and `tracking`, defaulting to the 42 pt pair so
existing call sites are unchanged; the flag badge scales with the diameter and
still lands on 16 pt at 42. The account hero passes 72 / 30 / -0.75 and measures
72 pt on device.

The rule going forward: **the component must not force one size on every
caller.** Where the product design uses a different size, pass it.

### The date field is `Pay Date` everywhere

The design was updated, so `72:9065` now labels it `Pay Date` too. The
stablecoin editor's `Effective Date` label, its picker accessibility title, and
the `invalidEffectiveDate` message were renamed to match. The two screens no
longer call the same field different things.

### Interest calculation defaults to SI

The design was updated to match the model: `72:9178` now shows **SI first and
selected**, and `HoldingDraft.interestMode` already defaulted to `.simple`. The
only code change was the segment order, which had `CI` first.

Note the annotations on `72:9065` confirm behaviour batch 7 already implements:
the edit sheet must not expose the simple/compound switch, a changed APR applies
going forward while past interest keeps the old rate, and a past pay date
recomputes interest from that date while earlier days keep the old figures.


## Item 15 — removing the dead legacy code

`HoldingDetailView` 1,742 to 1,154 lines, `HoldingEditorView` 2,143 to 1,461.
Roughly 1,235 lines gone.

Reachability was computed from the live roots rather than eyeballed, which
mattered: a first pass that matched member names anywhere in the file reported
almost nothing dead, because `.sheet(` looked like a reference to the member
named `sheet` and a doc comment mentioning `sheet(for:)` counted as a call.
Excluding dot-prefixed matches, allowing `Self.x`, and stripping comments turned
2 dead members into 12 in the detail view. Swift does not warn on unused private
members, so the compiler can only confirm a deletion is safe, never find one.

Removed: the `sheet(for:)` cluster (`summary`, `breakdown`, `latestDividendCard`,
`recordEntries`, `recordButton`, `interestIncomeList`, `activityList`,
`eventCell`, `frequencyText`, `latestDividendRecord`, `signedCurrency`), the
`standardEditor` cluster (27 members), the row types only they used
(`BreakdownRow`, `DetailValueRow`, `HoldingActivityRow`, `InterestRecordRow`),
and the Chinese label extensions on `HoldingKind` and `DividendFrequency`.

### A second dropped entry point, same cause as the dividend one

`pendingInterestSkip` was only ever read, never set: the new interest list had no
**Mark as Unpaid** action, so that feature was unreachable exactly like the
dividend records were. `68:8061` draws the interest rows with no affordance
(unlike `70:8201`, which does show a delete), so the design may well intend
interest payouts to be read-only — but the skip and restore paths exist in the
domain, and silently dropping them is not a call to make while tidying code. The
action is back as a long-press, which adds nothing the design did not draw.
**Open question:** should an interest row be actionable at all?

### Copy audit correction

The Batch 8 sweep matched only user-visible call sites (`Text(`, `title:`, and
friends). Broadening it to every string literal found ~33 Chinese
`LocalizedError` descriptions across `Data/` (`SupabaseServices`,
`HoldingRepository`, `MarketDataClient`, `ExchangeRateClient`, the sync
coordinators, the stores) that do reach the user through alerts. `Features/`,
`DesignSystem/`, and `App/` are now fully English. `Domain/MarketSession`'s ten
labels are Chinese but currently render nowhere, since the ticker was removed.
Item 16 covers the rest.


## Feedback round — 2026-09-02

| Item | Status |
| --- | --- |
| Add Position symbol field did not respond to taps | Fixed |
| Remove the Calculate / Currency page titles | Done |
| Status bar background while scrolling | Done, as the native top scroll-edge effect |
| Section component restyle (`2071:843`) | Done |
| Calculator and portfolio screenshot changes | Done |
| Bottom navigation icon/label centring | Investigated, see below |

### The symbol field bug

It was written as `Button { } label: { NvwaSearchInput(...).allowsHitTesting(false) }`.
A `Button` derives its hit region from its label, so disabling hit testing on the
whole label left the button with no hit area at all — the entire row was dead.
The input is now plain, with a transparent overlay outside that subtree carrying
the tap. The overlay uses `onTapGesture` rather than a `Button` for the reason
already documented in `PortfolioView`: a `Button` inside a `ScrollView` waits for
the scroll-vs-tap decision and feels sluggish.

### Status bar

Not a painted strip — iOS 26's `scrollEdgeEffectStyle(.soft, for: .top)`, the
same soft gradient the floating tab bar already produces at the bottom, so both
edges match. Older systems fall back to a zero-height `safeAreaInset` painting an
opaque colour into the safe area.

### Section restyle

`2071:843` went from a dark filled rounded rectangle to a pale green pill: 28
tall, 24 corner radius, `Alpha Green 20%` behind `Primary Green` text when
selected, fully transparent with `Text Secondary` when not, `B-S Semi Bold`.

Its 16-point horizontal padding is now dropped when `expandsHorizontally` is set.
In an evenly divided row the slot width comes from outside, and the padding was
eating the label — `1,000K` rendered as `1,00…`. The Figma instances in that row
are 65.4 points wide with the text filling them, so the padding only applies to a
Section that hugs its content.

### Screens

- Calculator: `SI` first and selected by default (`selectedMode` was
  `.compound`), quick amounts now use `NvwaSection`, results gained a second row
  of `5 Year / 10 Year / 20 Year`, and the forecast chart is gone — `46:1483`
  shrank from 1001 to 812 points and ends after the results.
- `InvestmentSummary` gained `fiveYearProfit`, `tenYearProfit`, and
  `twentyYearProfit`, covered by `testSummaryCoversFiveTenAndTwentyYears` across
  both simple and compound.
- Portfolio range control: `1D / 1W / 1M / 1Y` as Sections instead of a Segment
  Control.

### Bottom navigation centring — resolved, and a correction

**The previous entry in this document was wrong and has been replaced.** It
claimed the ideographic-space padding in `nativeTabTitle` did nothing, on the
strength of a "pixel-identical" screenshot comparison. That comparison was
invalid: the build under test was never installed on the simulator, so both
screenshots came from the same binary. The padding was removed on that basis and
the tab bar silently narrowed.

Measuring the span between the outermost tab labels across every screenshot taken
this session settles it:

| Build | Label span |
| --- | --- |
| With the padding | 250 pt |
| Without it | 193 pt |

The padding is restored. With the bar back at its intended width the icon and
label centres line up **exactly**: 0.0 pt offset on all three tabs. The earlier
"2.7 to 3.7 points" reading came from a dark-mode screenshot measured with a
threshold that selected background rather than glyphs, so it was measuring gaps.

Lesson for the next visual check: confirm the binary actually installed before
trusting a before/after comparison, and match the pixel threshold to the theme.


## Feedback round 2 — 2026-09-02

- `Total P&L` is now `Total PNL`.
- 16-point gap between the assets block and the range selector.
- The standing `Last 24 hours` caption is gone; the range is already stated by
  `1D / 1W / 1M / 1Y`. The slot is still reserved so the chart does not jump when
  a scrub timestamp appears.
- Chart axis and timestamp text moved from `Nvwa.ink20` to `Text Secondary`,
  which was unreadable on the light theme.
- Slider track is square. The export draws both track rects as plain `<rect>`
  with no `rx`; the implementation was using `Capsule`. `NvwaSliderMetrics`
  gained `trackCornerRadius = 0` so a test pins it.
- Status bar: settled on a solid opaque background for Calculate and Currency
  rather than a gradient, because PawFolio's top navigation is already solid and
  a gradient on the other two would read as two different treatments.
  `scrollEdgeEffectStyle(.soft, for: .top)` was tried first — it is the same
  mechanism as the bottom tab bar's fade — but these two screens wrap their
  scroll view in another container and the effect did not reach it.


## Feedback round 3 — 2026-09-02

All of these were fixed in the component rather than at the call sites, per the
request.

| Item | Fix |
| --- | --- |
| Collapse chevron under the chart was invisible | `Nvwa.ink20` to `Text Secondary`, same as the axis labels |
| Search and clear icons were black | Both now `Text Secondary` inside `NvwaSearchInput`; the field's `foregroundStyle` still gives the *text* `Text Primary`, so it is set per icon rather than on the stack |
| Clear icon sat 24 pt from the right edge | Its 36 pt touch target centres a 20 pt icon, adding 8 pt. A `-8` trailing inset moves the button out so the icon lands on 16 pt while the touch target keeps its size |
| Wrong search glyph | The asset was Remix `search-line`; `43:2851` calls for `search-2-line`. Added `IconSearch2` from the Figma export and repointed all three injection sites |

`NvwaSearchInput`'s internal spacing also went from 8 to 4, which is what
`43:2851` specifies.


## Feedback round 4 — 2026-09-02

| Item | Fix |
| --- | --- |
| Unused search icon | `IconSearch` (Remix `search-line`) deleted; nothing referenced it after switching to `IconSearch2` |
| Search result secondary text was C-2 Regular | Now `Nvwa.bodySmall` (B-S Regular, 12/20 · tracking 1%) |
| Search result two-line gap | 4 to 8, on both the name/symbol column and the price/change column |
| Calculator: input-to-quick-amounts gap | Was 4 (shared with label-to-input inside one `VStack(spacing: 4)`); split into an inner `spacing: 4` (label→input) and an outer `spacing: 8` (input→quick amounts), matching `46:1910`'s `y=72` for the quick-amount row against a 64pt-tall input block |
| Range tabs to chart gap, verified | Measured 16.0pt exactly on device (48px at 3x) from the pill's bottom edge to the chart's own frame; the extra visual space below that is `PawPortfolioChart`'s own internal top padding for its peak label, not part of this gap |
| Record rows showing "0 …" | `adjustRecordsRow`, the interest/adjustment rows in `earnSheet`, and the dividend row now render nothing when their count is 0, instead of an empty entry point |
| Price-card chart didn't fill its axis | `PawSparkline` gained `padLow`/`padHigh` parameters (default 0.26/0.10, matching the existing mini-preview usage unchanged); the P&L detail's price card now passes `0/0` so the line's peak and trough land exactly on the axis's max/min instead of leaving headroom meant for a small thumbnail |
| Price-axis labels wrapped onto two lines | The column had a hardcoded `frame(width: 24)` sized for the Figma sample's 3-digit values; real prices with 5+ digits (e.g. `79,332`) wrapped. Replaced with `.lineLimit(1)` + `.fixedSize()` on each label and let the `VStack` size to its widest child |

### Verification

Nvwa 16/16, Domain 166/166, `build-for-testing` succeeded. The 16pt range-to-chart
gap and the 8pt calculator gap were both measured on-device to sub-point
precision rather than eyeballed. The axis-label wrap fix was validated by
layout reasoning (removing a hardcoded narrow frame and letting `Text` report
its natural width is a standard, low-risk SwiftUI fix) rather than against a
live 5-digit BTC quote — this machine cannot drive the simulator interactively
to add a BTC position through the UI, and no cached BTC quote existed locally
to open directly. Worth a manual look next time BTC is on screen.


## Feedback round 5 — 2026-09-02

### Add Position search results stopped responding to taps

Root cause: each result row's `Button` label conditionally included a whole
extra `VStack` — `if let quote = model.quotes[asset.quoteSymbol] { VStack {...} }`
— and quotes for visible rows arrive asynchronously, independently, often
within the same fraction of a second a user's finger is on the row. UIKit
treats that as the touched view's hierarchy changing shape mid-touch and
cancels the in-progress tap recognition. It would have been broken since the
row redesign that added live per-row quotes, just never caught, because tap
verification here has always relied on this session catching structural bugs
by reading code, not on live taps.

Fixed by making the trailing price/change `VStack` unconditional — always
present, with empty strings when no quote has arrived yet — so a quote landing
only ever changes text content, never the tree shape, regardless of when it
completes relative to a touch.

### Bottom navigation squeeze — could not reproduce

Rebuilt fresh and checked the tab bar on iPhone 17 Pro (402 pt), the narrower
iPhone 17e (390 pt), and iPhone 17 Pro at every Dynamic Type step up to
`accessibility-extra-extra-extra-large`. All show the icon and label centred
with no compression, matching the 250 pt / 0.0 pt-offset result confirmed last
round. The source (`RootTabView.swift`) still has exactly the padding restored
then — `git diff` shows no accidental edit to it since.

Given last round's mistake was trusting a comparison against a binary that was
never actually reinstalled, the most likely explanation this time is the same
kind of staleness on whichever build produced the reported screenshot — it may
not be one of the ones this session installs and screenshots via `simctl`.
**Asked the user to force a clean rebuild and reinstall (delete the app first)
before deciding this needs further work**, rather than declare it fixed or
chase a device/setting this session cannot reproduce.

### Verification

Nvwa 16/16, Domain 166/166, `build-for-testing` succeeded.
