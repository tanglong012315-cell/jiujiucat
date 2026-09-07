# Figma component map

Source: Nvwa Figma file `B7QSpRFNAt2tZ6S2JiG3Ij`, verified through the
official Figma MCP on 2026-09-03.

## Valid source entry points

| Area | Figma node |
| --- | --- |
| Components canvas | `2014:7053` |
| Input canvas | `2052:7149` |
| Navigation section | `2102:1075` |
| Navigation (component set) | `2224:91` |
| Navigation / Secondary, Icon=Right | `2238:574` |
| Navigation / Secondary, Icon=L+R | `2238:582` |

The previously shared URL targets `2106:1212`. That node is stale or invalid in
the current file and must not be used as the implementation source. Start from
the valid canvas or section nodes above.

## Component sources

| Component | Figma node / stable key |
| --- | --- |
| System Colors | `2013:4824` |
| Tooltip | `2014:7062` |
| Toggle | `2014:7184` |
| Avatar | `2014:7932` |
| Primary Button | `2014:7979` |
| Primary Button / Large | `2182:54` |
| Secondary Button | `2030:9627` |
| Secondary Button / Large | `2182:58` |
| Outline Button | `2078:923` |
| Outline Button / Large | `2182:60` |
| Outline Button / Large + Leading | `2119:1267` |
| Warning Button | `2076:914` |
| Warning Button / Large | `2182:56` |
| Outline Warning Button | `2078:932` |
| Outline Warning Button / Large | `2182:62` |
| Tag | `2015:8035` |
| Key Feature icons | `2029:9063` |
| Segment | `2050:880` |
| Checkbox | `2061:730` |
| Hint | `2062:773` |
| Toast | `2070:814` |
| Section (canvas) | `2070:825` |
| Section / Primary | `2071:843` |
| Section / Sec | `2282:303` |
| Section / Currency | `2282:248` |
| Section / Text | `2282:236` |
| Text Dropdown Button | `2285:342` |
| BG Dropdown Button | `2285:355` |
| Dropdown Menu | `2286:449` |
| Slider | `2072:862` |
| Modal Header | `2052:7350` |
| Text Input | `2014:7294` |
| Search Input | `2052:7628` |
| Date Input | `2058:307` |
| Flag Input | `2074:894` |
| Scroll button | `2243:704` |
| Calendar Dropdown | stable key `7bdce38a4e645b1df3df96624ed189fdae67a8e2` |

Calendar primitives and the dropdown are grouped under the Input canvas. Use
`2052:7149` to inspect them; retain the stable key only when an API needs a
component key.

## Core variant matrix

| Component | Figma-authored variants | Geometry / notes |
| --- | --- | --- |
| Tooltip | Top, Bottom, Right, Left × Button false/true | Pointer direction follows placement |
| Toggle | `On=True`, `On=False` | 50 × 28 |
| Avatar | `Flag=True`, `Flag=False` | 42 × 42; instances resize (nav uses 40) |
| Tag | Gray, Green, Red, Blue × leading dot, trailing close, none | 16 high |
| Segment | Normal with 2, 3, or 4 items; Small with 3 items only | Normal 345 × 40; Small hugs content (current example 89 × 28) |
| Checkbox | `Checked=Yes`, `Checked=No` | No indeterminate variant |
| Hint | Level 1–4 × icon none/right | 32 high; neutral surface uses `BG/Vessel`; every variant carries the 12pt mark |
| Toast | Level 1 | Surface uses `Text/Primary`; text uses `BG/Main` |
| Section / Primary | `Secleted=Yes/No`, `Icon=No` | 28 高药丸；无图标变体 |
| Section / Sec | `Secleted=Yes/No` | 28 高药丸；没有 `Icon` 这根轴 |
| Section / Currency | `Secleted=Yes/No`, `Icon=Yes` | 36 高药丸 + 20pt 图标 |
| Section / Text | `Active=Yes/No` × `Icon=Yes/No` | 无底色，20 高行盒 + 16pt 图标 |
| Text Dropdown Button | `12px`, `12(M)`, `14px`, `16px` | Hug content；文字与箭头间距 2 |
| BG Dropdown Button | `Size=40px`, `Size=24px` | `BG/Input`；圆角分别为 8 / 6 |
| Dropdown Menu | Default | 113 × 172；4 个 38 高选项；`shadow2` |
| Slider | Default | 218 × 16 |
| Scroll button | `Start`, `Scrolling`, `Finish` | 345 × 56 track; 56pt knob |
| Modal Header | Icon No, Left, Right | 373 × 66 |
| Navigation | `添加持仓`, `二级导航`, `个人中心` × `Icon=Left/Right/L+R` (5 authored) | 64 high |

In Modal Header's current Figma naming, `Left` visually means a trailing close
control with a leading spacer, while `Right` visually means a leading red
logout control with a trailing spacer. Preserve the observed geometry; do not
infer control placement from those property labels.

The three Navigation variants are one component set (`2224:91`) sharing a
375 × 64 frame, 40-point visual controls, and a 16-point visual horizontal
inset. Their 44-point SwiftUI hit targets extend 2 points beyond each visible
circle without changing the authored geometry. They differ only in what sits in
each side slot, so `NvwaNavigationBar` takes slots rather than one initializer
per variant:

| Variant | Source | Leading | Centre | Trailing |
| --- | --- | --- | --- | --- |
| `添加持仓, Icon=Left` | `2102:1169` | Avatar, 40pt, `T-G Medium` initials | — | Add glyph, 24pt |
| `二级导航, Icon=Left` | `2102:1102` | Back / close glyph, 24pt | Title, `T-B Semi Bold` | Empty 40pt slot |
| `二级导航, Icon=Right` | `2238:574` | Empty 40pt slot | Title, `T-B Semi Bold` | Close glyph, 24pt |
| `二级导航, Icon=L+R` | `2238:582` | Back / close glyph, 24pt | Title, `T-B Semi Bold` | Close glyph, 24pt |
| `个人中心, Icon=Left` | `2224:66` | Close glyph, 24pt | — | Theme + language, 20pt, 15pt apart |

The `Icon` property is only the permutation of which side slots are filled, so
it needs no API of its own: pass the slots you want. The title was 14-point
`B-M Semi Bold` until 2026-09-04; all three `二级导航` variants now use 18-point
`T-B Semi Bold`.

Glyph size follows the slot, not the family: a side holding one glyph draws it
at 24 points, a side holding two drops to 20. The language mark is a full-colour
flag and must not be template-rendered. The title's centre slot is why the
`二级导航` trailing slot stays empty rather than absent — the component reserves
the same 44-point box so the title lands on the bar's centre line.

The signed-out bar (guest glyph + add) has no authored variant; it is a code
extension that only swaps the leading slot.

### Scroll button

`2243:704` is a slide-to-confirm control, and its three variants are three
moments of one gesture rather than three independent states:

| Variant | Source | Knob | Trail |
| --- | --- | --- | --- |
| `Start` | `2243:703` | Flush left, `Send` arrow | none |
| `Scrolling` | `2243:702` | Follows the finger (authored at 138) | left edge → knob's trailing edge |
| `Finish` | `2243:701` | Flush right, spinner replaces the arrow | full width |

The knob is the Key Feature `Send` component (`2029:9081`) — 56pt container,
28pt glyph — rotated -90° so the arrow points along the travel. Do not draw a
second arrow. The trail is `Alpha Blue 10` and reaches the knob's *trailing*
edge, not its centre: the authored trail is 194 wide against a knob at 138, and
194 = 138 + 56.

Two things the file does not author, decided in code: the drag must cover 90% of
the travel to count as a confirmation, and after confirming the knob stays at the
end rather than springing back — an irreversible action that visibly rewinds
reads as "it didn't take". The host clearing `isLoading` returns it to `Start`,
which is the retry path.

### Section

`2070:825` 在 2026-09-07 把 Section 拆成了四个组件集。四档共用 12/20 的字号行高
和「选中立刻生效、不吃外层动画」的反馈，差别只在底色、几何和图标槽位：

| 组件 | 节点 | 几何 | 选中 / Active | 未选中 |
| --- | --- | --- | --- | --- |
| Primary | `2071:843` | 28 高，左右 16，上下 3，圆角 24 | `Alpha/Blue 10%` + `Primary Green` | 透明 + `Text/Secondary` |
| Sec | `2282:303` | 同上 | `BG/Vessel` + `Text/Primary` | 透明 + `Text/Secondary` |
| Currency | `2282:248` | 36 高，左右 10，图标 20，间距 5 | `BG/Vessel` | 透明 |
| Text | `2282:236` | 无底色无内边距，图标 16，间距 4 | `Text/Primary` | `Text/Secondary` |

三件要点，都是稿子上写着的，不是实现选择：

- **Currency 两态的文字同色**（都是 `Text/Primary`）。有了图标和底色之后，文字不
  再兼职当选中指示，所以它没有跟着 Primary 那档换成 `Primary Green`。
- **Currency 的圆角写的是 66**，超过半个高度，落到代码里就是一颗胶囊；Primary /
  Sec 的 24 则保留为 `RoundedRectangle`。
- **Text 那档是 `B-S Regular`**，其余三档是 `B-S Semi Bold`。Text 也没有容器高度，
  20 是行盒本身，所以只有它保留首尾的 half-leading。

Currency 的图标是一枚**国旗组件实例**，不是 Section 自己画的：20pt 圆形、0.5pt
`Line` 描边都跟着国旗走。`NvwaSection` 只提供槽位尺寸和间距，图案由宿主注入——
PawFolio 首页法币账户那排货币选择器（`LedgerPortfolioView.spotAssetChip`）传的就是
本地的国旗 / 币种图。Text 那档的图标要传模板图，它跟着文字色一起变。

Figma 的属性名拼作 `Secleted`（Primary / Sec / Currency）而 Text 用的是 `Active`。
代码里统一成 `isSelected`，不复制这处拼写。

### Dropdown controls

`2070:825` 在四档 Section 下新增了三组下拉组件：

- `2285:342` Text Dropdown Button：四档分别使用 `B-S Regular`、`B-S Semi Bold`、
  `B-M Semi Bold`、`B-L Semi Bold`；前两档箭头 12pt，后两档 14pt，文字与箭头固定间距 2pt。
- `2285:355` BG Dropdown Button：40pt 档为左右 12、间距 8、20pt 箭头、圆角 8；
  24pt 档为左右 8、上下 3、无额外间距、16pt 箭头、圆角 6。两档都使用 `BG/Input`。
- `2286:449` Dropdown Menu：宽 113、圆角 12、上下内距 10；每项是 22pt 行盒加上下各
  8pt，四项总高 172。选中项使用主文字色和 20pt `check-line`，未选中项使用
  `Mobile/Text/SecondaryText`（浅色值 `#757575`）。阴影是 `shadow2` 的两层组合：
  `#181A20` 10%、Y=2、blur=6 与 `#474D57` 8%、Y=8、blur=14。

图标继续遵守 Nvwa 的边界：`arrow-down-s-fill` 与 `check-line` 都由宿主注入，组件库不新增
通用图标资产。PawFolio 现有两枚 Remix Icon 路径与 Figma 导出路径一致。

`2285:355` 是当前 Nvwa 文件里唯一仍绑定旧 `Mobile/subtitle2,14 Medium` / 
`Mobile/subtitle3,12 Medium`（Binance Nova）的新增组件。仓库没有可合法打包的 Binance Nova
字体文件，因此代码保留 14/22、12/18、Medium、零字距的实际度量，并用 Nvwa 已打包的 Inter
渲染；等设计侧把这两个 style 正式迁到 Nvwa 排版 token 后，再同步 token 名，不在业务页覆盖。

### Hint

All eight variants carry a leading 12 × 12 mark — the Key Feature `Warning`
illustration (`2029:9149`) scaled down, sat on a per-level disc — followed by a
4-point gap and the label. The mark's own frame adds a 4-point top inset so the
disc centres on the first line's cap band rather than on the line box's top
edge; with the pill's 6-point top padding it lands 10 points below the pill's
top edge.

The disc colour is not one rule across the four levels, and this is authored,
not an oversight: level 1 uses solid `Line`, level 3 uses solid
`Sentiment/Warning`, while levels 2 and 4 reuse the same 20% swatch as the pill
behind them, so the two layers stack into a slightly deeper tint.

The label is `B-S Regular` on a 20-point line box. Figma's line height is the
whole line box, but SwiftUI's `Text` only reserves the font's own
ascent + descent (about 14.5 points at 12pt), and `lineSpacing` cannot reach the
first and last lines — so the box is restored by adding half the difference
above and below (`NvwaTypographyToken.halfLeading`) and the full difference
between lines. Without it a two-line hint packs its lines 14.5 points apart
instead of 20.

### Buttons

| Family | Huge | Large | Small | Tiny |
| --- | --- | --- | --- | --- |
| Primary | No icon | No icon | No icon or Leading | No icon or Leading |
| Secondary | No icon | No icon | No icon or Leading | No icon or Leading |
| Warning | No icon | No icon | No icon or Leading | No icon or Leading |
| Outline Warning | No icon | No icon | No icon or Leading | No icon or Leading |
| Outline | No icon | No icon or Leading | No icon or Leading | No icon or Leading |

Label text styles by size: Huge uses `B-L Semi Bold` (16/24), Large and Small use
`B-M Semi Bold` (14/22), and Tiny uses `B-S Regular` (12/20). Outline Warning /
Small is the one exception, using `B-M Regular`. Those four styles cover all 32
authored variants with no per-family deviation, so `NvwaButtonMetrics` resolves
size, weight, and tracking from a single typography token per size.

Huge, Large, Small, and Tiny heights are 48, 40, 32, and 28 respectively. Leading glyphs
are 16 × 16 with an 8-point text gap. The Outline Large + Leading source is
`2119:1267`. Outline strokes are 1 point, inside-aligned. No trailing-icon variants are authored in the current Figma set.
Secondary Button has no Color property or blue variant; its five authored
variants use `Button/Gray`. The adjacent blue row on the canvas belongs to the
Primary Button set.

## Input variant matrix

| Component | Figma-authored variants | Geometry |
| --- | --- | --- |
| Text Input | Normal / Default / no error | 318 wide; 48-point field |
| Text Input | Normal / Default / error | 318 wide; 48-point field |
| Text Input | Small / Default / no error | 318 wide; 48-point field |
| Search Input | Default, Unit, Active, Sub Text | 318 wide; 48-point field |
| Date Input | Default | 318 wide; 48-point field |
| Flag Input | Default | 318 wide; 48-point field |

The current `Flag` source at `2074:894` visually duplicates Date Input and ends
with a calendar glyph. `NvwaFlagInput` keeps its established host-injected flag
API while adopting the shared 48-point input geometry; the source anomaly is
recorded rather than silently changing the component's meaning.

## Key Feature icon set

The current Figma frame is a closed set of nine illustration-like components.
Spend, Account, Direct Debits, Scheduled Transfers, Personal Account, Business
Account, Add Interactive, and Upload are not part of the Nvwa SwiftUI catalog.

| Illustration | Node | Container / glyph | Container | Glyph |
| --- | --- | --- | --- | --- |
| Invest | `2029:9064` | 56 / 28 | `Primary Green` | `ColorOnBlue` |
| Keep | `2029:9069` | 56 / 28 | `Primary Green` | `ColorOnBlue` |
| Convert | `2029:9074` | 56 / 28 | `Primary Green` | `ColorOnBlue` |
| Send | `2029:9080` | 56 / 28 | `Primary Green` | `ColorOnBlue` |
| Receive | `2029:9085` | 56 / 28 | `Primary Green` | `ColorOnBlue` |
| Add | `2029:9125` | 56 / 28 | `BG/Vessel` | `Text/Primary` |
| Close | `2029:9143` | 48 / 24 | `Sentiment Negative` | literal white |
| Tick | `2029:9146` | 48 / 24 | `Primary Green` | literal white |
| Warning | `2029:9149` | 48 / 24 | `Sentiment Warning` | `Text/Black` |

The generated SVG/code context can retain historical `#163300` or `#9FE870`
inside hidden Boolean paths. Live `boundVariables` and canvas screenshots show
that those paints do not drive the visible component output.

## Verified token bindings

- Primary interaction uses `Primary Green`, now blue, with white
  `ColorOnBlue` content.
- Toggle thumb uses `BG/Container`; selected Segment uses `BG/Container` with
  `Text/Blue` content.
- Selected Section / Primary uses `Alpha/Blue 10%` and `Primary Green`;
  Sec and Currency use `BG/Vessel`, and Text has no surface at all.
- Slider uses `BG/Input` for the inactive track, `Primary Green` for the active
  track, and `BG/Main` for the thumb with a 2-point `Primary Green` stroke.
- Inputs use `BG/Input`; Secondary Button uses `Button/Gray`.
- Green Tag uses `Alpha/Green 20%` with `Market Buy` content.
- Blue Tag uses `Alpha/Blue 10%` with `Primary Green` content.
- Avatar, Segment, and neutral Hint use `BG/Vessel`.
- Modal surfaces use `BG/Main`.
- Toast uses `Text/Primary` for its surface and `BG/Main` for its text. Its
  horizontal padding is 8 points; short messages hug their content, while the
  surface caps at 300 points and wraps longer messages onto additional lines.
- Key Feature icons use the semantic bindings listed above; only the white
  glyphs on Close and Tick are unbound literal paints.

See [`FIGMA_TOKENS.md`](FIGMA_TOKENS.md) for exact Light and Dark values.

## Icon ownership

Nvwa intentionally bundles no general icon set. Functional icons are
host-injected [Remix Icon](https://remixicon.com/) assets, including button,
input, navigation, calendar, checkbox, and other semantic glyphs. The nine Key
Feature glyphs are a deliberate component-owned illustration exception and are
bundled package-private, as is the structural Tooltip pointer.

## Figma authorship boundary

The current Figma library does not define button pressed, loading, or disabled
variants; toggle-disabled; checkbox-indeterminate; or slider-state variants.

SwiftUI may add runtime capabilities needed by a host, but the following are
code-only extensions and must not be described as Figma-authored:

- generic Segment selection and arbitrary options;
- expanded-width layout modes;
- arbitrary Avatar sizing;
- Hint highlighting;
- arbitrary Modal actions;
- Slider binding, range, and accessibility behavior;
- Calendar localization and external-selection synchronization;
- runtime press handling and accessibility behavior.
