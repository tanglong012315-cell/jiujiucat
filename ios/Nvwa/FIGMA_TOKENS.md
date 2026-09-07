# Figma token snapshot

Source: Nvwa Figma file `B7QSpRFNAt2tZ6S2JiG3Ij`, read through the
official Figma MCP on 2026-09-03.

## Local variable collection

The file currently exposes one local variable collection with Light and Dark
modes. It contains exactly 28 colour variables. There are no local number,
string, boolean, spacing, radius, motion, or grid variables.

| Variable | Light | Dark |
| --- | --- | --- |
| `NVWA/Core Colors/Bright Blue` | `#6999FF` | `#4782FF` |
| `NVWA/Core Colors/Primary Green` | `#0051FE` | `#2D66F0` |
| `NVWA/Text/Primary` | `#000000` | `#FFFFFF` |
| `NVWA/Text/Secondary` | `#868685` | `#868685` |
| `NVWA/Text/Blue` | `#0051FE` | `#4782FF` |
| `NVWA/Text/ColorOnBlue` | `#FFFFFF` | `#FFFFFF` |
| `NVWA/Text/Black` | `#000000` | `#000000` |
| `NVWA/BG/Main` | `#FFFFFF` | `#000000` |
| `NVWA/BG/Container` | `#FFFFFF` | `#373737` |
| `NVWA/BG/Dialogue` | `#FFFFFF` | `#262626` |
| `NVWA/BG/Vessel` | `#EFEFEF` | `#212121` |
| `NVWA/BG/Card` | `#F6F6F6` | `#212121` |
| `NVWA/BG/Input` | `#EFEFEF` | `#1D1D1D` |
| `NVWA/Button/Gray` | `#DEDEDD` | `#3C3C3C` |
| `NVWA/Line/Line` | `#DEDEDD` | `#2B2B2B` |
| `NVWA/Secondary Colors/Pink` | `#FFD7EF` | `#FFD7EF` |
| `NVWA/Secondary Colors/Bright Orange` | `#FFC091` | `#FFC091` |
| `NVWA/Secondary Colors/Bright Yellow` | `#FFEB69` | `#FFEB69` |
| `NVWA/Secondary Colors/Bright Blue` | `#A0E1E1` | `#A0E1E1` |
| `NVWA/Sentiment Colors/Sentiment Warning` | `#EDC843` | `#EDC843` |
| `NVWA/Sentiment Colors/Sentiment Positive` | `#2F5711` | `#2F5711` |
| `NVWA/Sentiment Colors/Sentiment Negative` | `#A8200D` | `#DC432D` |
| `NVWA/Market Colors/Buy` | `#1D7353` | `#2CC094` |
| `NVWA/Market Colors/Sell` | `#CE2632` | `#F0616D` |
| `NVWA/Alpha/Blue 10%` | `#0051FE1A` | `#4782FF33` |
| `NVWA/Alpha/Green 20%` | `#4AB18B33` | `#2CC09433` |
| `NVWA/Alpha/Red 20%` | `#CE263233` | `#CE263233` |
| `NVWA/Alpha/Yellow 20%` | `#EDC84333` | `#EDC84333` |

`Primary Green` is the retained Figma variable name, but its current values are
blue. Implementations must bind by variable identity rather than infer a green
value from the historic name. `ColorOnBlue` is white in both modes, while
`Text/Black` remains black in both modes.

`NVWA/Core Colors/Bright Green` and `NVWA/Core Colors/Forest Green` are no
longer local variables in this collection. Some hidden Boolean paths still
carry historical `#9FE870` or `#163300` paints, but the visible Key Feature
output is bound to the current variables. Those historical paints are not
exposed as Nvwa tokens.

## Verified component bindings

| Component role | Figma binding |
| --- | --- |
| Primary interaction | `Primary Green`; foreground `ColorOnBlue` |
| Toggle thumb | `BG/Container` |
| Selected Segment surface/content | `BG/Container` / `Text/Blue` |
| Selected Section | `Alpha/Blue 10%` surface with `Primary Green` content |
| Slider inactive track | `BG/Input` |
| Slider active track | `Primary Green` |
| Slider thumb | `BG/Main` with a 2-point `Primary Green` stroke |
| Inputs | `BG/Input` |
| Secondary Button | `Button/Gray` |
| Green Tag | `Alpha/Green 20%` surface with `Market Buy` content |
| Blue Tag | `Alpha/Blue 10%` surface with `Primary Green` content |
| Avatar, Segment, and neutral Hint | `BG/Vessel` |
| Modal surface | `BG/Main` |
| Toast surface / text | `Text/Primary` / `BG/Main` |

Key Feature Invest, Keep, Convert, Send, and Receive use `Primary Green` with
`ColorOnBlue`; Add uses `BG/Vessel` with `Text/Primary`; Warning uses
`Sentiment Warning` with fixed `Text/Black`. Close and Tick use token-bound
containers with unbound literal-white glyphs. Only these nine illustrations are
implemented; the exact nodes are in [`FIGMA_COMPONENTS.md`](FIGMA_COMPONENTS.md).

## Text styles

| Style | Font | Size / line height | Letter spacing |
| --- | --- | --- | --- |
| `T Semi Bold` | Inter Semi Bold | 30 / 34 | -2.5% |
| `T-S Semi Bold` | Inter Semi Bold | 26 / 32 | -1.5% |
| `T-Sub Semi Bold` | Inter Semi Bold | 22 / 28 | -1.5% |
| `T-B Semi Bold` | Inter Semi Bold | 18 / 24 | -1% |
| `T-G Medium` | Inter Medium | 14 / 20 | 1.5% |
| `B-L Regular` | Inter Regular | 16 / 24 | -0.5% |
| `B-L Semi Bold` | Inter Semi Bold | 16 / 24 | 0.5% |
| `B-M Regular` | Inter Regular | 14 / 22 | 1% |
| `B-M Semi Bold` | Inter Semi Bold | 14 / 22 | 1.25% |
| `B-S Regular` | Inter Regular | 12 / 20 | 1% |
| `B-S Semi Bold` | Inter Semi Bold | 12 / 20 | 1% |
| `Link L Semi Bold` | Inter Semi Bold, underline | 16 / 24 | 1% |
| `Link M Semi Bold` | Inter Semi Bold, underline | 14 / 22 | 1.25% |
| `C-1 Regular` | Inter Regular | 11 / 18 | 1% |
| `C-2 Regular` | Inter Regular | 10 / 16 | 1% |

### 行高和字距怎么落到代码里

Figma 的行高是**行盒总高**（CSS 语义），SwiftUI 的 `Text` 只给字体自带的行盒
（Inter 12pt 约 14.5，不是稿子标的 20），而且 SwiftUI 根本没有「行高」这个属性。
所以一个 token 要还原成稿子的样子，需要三件事一起：字号字重、字距、行盒补偿。

**`.nvwaTextStyle(token)` 是唯一一次性给全三件的入口**，它做的是：

| 稿子里的属性 | 代码里的落点 |
| --- | --- |
| Size / Weight | `token.font` |
| Letter spacing | `.tracking(token.tracking)` |
| Line height（行与行之间） | `.lineSpacing(token.lineSpacing)` |
| Line height（首行上、末行下的 half-leading） | `.padding(.vertical, token.halfLeading)` |

`linesFillLineHeight: false` 只关掉最后一项。**单行文字放在有固定高度或自带内距的
容器里时要传 `false`**，否则 half-leading 会和容器内距叠加，把行撑高一圈；
多行正文保持默认的 `true`，不然首尾会比稿子少一圈留白。

**`Nvwa.bodyMedium` 这类简写常量只返回 `Font`，不带字距、不带行高。**
用它就必须自己补 `.tracking(...)`，否则字距会被静默丢掉——单行文字上这是看得见的。
能用 `.nvwaTextStyle(...)` 就别用简写。

> 简写里有个坑：**`Nvwa.bodyLarge` 指向的是 `B-L Semi Bold`，不是 `B-L Regular`**。
> 要 Regular 那档得写 `Nvwa.Typography.bodyLarge`。

两条测试钉着这套东西，改 token 会红：
`testAllFigmaTypographyTokensRemainExact` 逐个断言 15 个 token 的名字/字号/**行高**/
字距/字重；`testTypographyLineBoxRestoresFigmaLineHeight` 断言行盒换算——
单行是「字体行盒 + 2×half-leading = 稿子行高」，多行是「字体行盒 + lineSpacing = 稿子行高」。

The file has no local effect styles or grid styles. It has 17 legacy generic
paint styles (`Gray 1` through `Purple 2`) outside the `NVWA/*` variable
namespace; they are not Nvwa package tokens. Tooltip and Calendar instances use
the component-level `box-shadow/small` effect: `#45474533`, zero offset,
40-point blur, and zero spread.
