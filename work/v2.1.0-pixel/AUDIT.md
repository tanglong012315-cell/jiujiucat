# V2.1.0 像素审计（Figma `134:7230`，共 44 frame）

方法：`get_design_context` 拉节点，拿设计数值和实现里的字面量逐项比对，不靠截图目测；
截图只用来定位「该查哪一屏」和验证改完的效果。

## 覆盖情况

**逐节点拉取并比对：24 帧。**
`154:9705`、`164:20724`、`154:10668`、`154:11051`、`154:10164`、`154:10468`、`154:10266`、
`154:10535`、`154:10896`、`154:11562`、`158:17517`、`155:14154`、`155:14852`、`154:13018`、
`154:12625`、`158:18144`、`155:13936`、`155:13816`、`158:16698`、`158:18023`、`155:16379`、
`155:16262`、`154:12261`，以及组件库侧的 Outline Button 全套变体。

**按「同组件的状态变体」核对：20 帧。**
这些帧的内部节点 id 和上面某一帧完全同源（同一个 authored component 的不同状态/内容），
逐项比对已在其母版上完成：

- 单选弹层变体 ×4：`158:18491`、`155:16083`、`155:16160`、`158:18414`（母版 `154:10896` / `154:11562`）
- 总览变体 ×2：`155:13348`、`154:11181`（母版 `154:10668` / `154:12625`）
- 流水页变体 ×4：`155:14807`、`155:14976`、`158:16990`、`159:20126`（母版 `158:18144`）
- 交易复核变体 ×1：`155:14097`（母版 `155:14154`）
- 卖出表单变体 ×1：`154:11963`（母版 `154:12261`）
- Earn 变体 ×2：`155:13496`、`155:15544`（母版 `154:13018`）
- 申购/赎回变体 ×2：`158:17298`、`158:17968`（母版 `155:13936` / `155:13816`）
- 理财产品表单 ×3：`155:15425`、`155:15867`、`155:15932`（母版 `155:16262` + Earn 产品表单）
- 明细变体 ×2：`158:17137`、`158:17375`（母版 `158:16698`）

## 已修（11 项，全部通过构建与测试）

| # | 节点 | 问题 |
|---|------|------|
| 1 | `164:20724` | 空态文案缺 `.multilineTextAlignment(.center)`，设计是 text-center 满宽 |
| 2 | `154:10535` | Add 复核右列取值应为 **T-G Medium**(14/20/0.21)，实现把 `bodyMedium` 挂在整个 HStack 上，两列都成了 B-M Regular |
| 3 | `154:13022` | Earn 列表卡片间距 12 → **16**（设计整列都是 gap 16） |
| 4 | `154:12840` | Trading 区块头部收益率把 Market Buy 绿钉死，亏损态也是绿的；改为按符号取 Buy/Sell/Gray |
| 5 | `158:19094` | 流水明细行应为 **B-M Regular**(14/22/0.14)，实现是 12pt；且 `tone` 染到了 label 上（`Fees` 左边也变红），改成只染右列 |
| 6 | `158:19103` | 流水条目分隔线应两侧各留 16（宽 342），实现是通栏 |
| 7 | `158:17628` | 申购弹层缺「<频率> Profits」行；补上，并把估算规则写进 Domain + 4 个单测 |
| 8 | `154:10266` | **资产选择器缺整套结构**：首字母分组、A–Z 索引条、行分隔线、32pt 圆标 0.5pt 描边、End 收尾 |
| 9 | `154:10896` 等 | **单选弹层被换成了原生 `Menu`**（4 处：Account / Type / Currency / Payout Frequency） |
| 10 | `158:16698`、`158:18023` | **两个明细页完全没实现**：Earn 产品明细、Trading 资产明细 |
| 11 | `155:16262` | Edit 弹层标题应为 `Edit` 而非 `Edit APY`，且缺 **Name** 字段、APY 缺尾部 `%` |

另外顺手修掉两处数值格式：法币/稳定币余额和 Total Values 用 `amount()`（2…8 位）渲染，
会把浮点残差整串打出来（`424,792.22907264`），改用固定两位的 `MoneyFormat`；
新明细页的行情坐标轴在五位数价格下会换行，压成 `81.8K` 并锁一行。

### 8 和 9 的做法

两处都不是「再写一遍」，而是把已有实现收敛：

- `PawAlphabeticalList`（新增，DesignSystem）从汇率页 `CurrencyPickerView` 抽出，
  两个「Add Currency」弹层共用；`CurrencyPickerView` 同步改为调用它，行为不变。
  **踩到的坑：** `LedgerAssetPicker` 原本套在 `PawSheet` 里，而 `PawSheet` 会把 content
  再包一层 `ScrollView`——嵌套后内层列表拿不到高度，索引条被顶出屏幕、分组表头也不吸顶。
  改成和 `CurrencyPickerView` 一样自己拼 `NvwaModalHeader` + `.pawSheetPresentation(.full)`。
- `PawSingleSelect`（新增，DesignSystem）按 `154:10896` 实现弹层与字段两件套，
  4 处 `ledgerMenuField` 全部替换，`ledgerMenuField` 已删除。

## 待你确认（未改）

1. **Buy/Sell 分段控件的选中色。** 设计 `154:12261` 里选中的 `Sell` 是 Market Sell 红，
   而 Nvwa 的 `NvwaSegmentControl` 把选中色钉死成 `textBlue`。按 AGENTS.md「产品稿和
   Nvwa 组件冲突时以组件为准、先记录待确认」，我没有动组件，现在仍是蓝的。
2. **交易手续费的口径。** 设计 `158:18329` 是**百分比**输入（`手续费`，默认 0.06，尾部 `%`），
   实现存的是绝对金额（`LedgerTradeDetails.fee`）。这是记账口径不是像素，没敢自己改。
   顺带：该字段标签在设计里是中文，全屏其余文案都是英文。
3. **Earn 产品「下架」流程整个没有。** 设计 `155:16379` 是下架确认弹层
   （48pt 警告插画 + Warning 标题 + 说明 + 滑动确认，确认后弹成功 toast），
   文案是「Once delisted, all assets will be returned to your account.」。
   领域层没有 delist 这个操作（只有 redeem），补它等于新增一条资金规则。
4. **赎回的「To Account」选择器。** 设计 `155:13816` 有这个字段（默认 Exchange），
   实现的 `redeem` 没有目标账户参数，赎回固定回原账户。改动涉及钱去哪，留给你定。
5. **Balance 弹层底部的「Add Currency」行。** 设计 `154:11941` 有一行 accent 蓝的
   Add Currency，实现没有。它在 Pay 语境下要跳去哪不明确。
6. **Pay 的 Balance 提示行多了币种代码。** 设计 `155:14912` 是「旗帜 + 数字 + chevron」，
   实现是「旗帜 + 12,000.00 CNY + chevron」，下面输入框尾部已经有一份单位。
7. **总览币种 chip 的排序。** 实现按字母序（CNY 在 USD 前），设计几帧画的都是 USD 在前，
   但设计没写排序规则。
8. **Edit 弹层里的生效时间提示。** 设计没画，实现有一条 `NvwaHint` 说明新 APY 下个付息
   周期生效。删掉会丢信息，我保留了。
9. **`CurrencyPickerView` 的行高。** 设计 `154:10275` 是 `py16` + 48pt 内容 = 80pt，
   汇率页那份钉的是 64pt。新的资产选择器按设计走 `py16`，汇率页那份没动
   （它当初是照自己的节点验收的，不确定要不要一起改）。
10. **卡片描边用的是 `.stroke` 不是 `.strokeBorder`**，线宽有一半画在圆角矩形外面，
    和设计的 inside border 差 0.5pt。全站一致，改要一起改。

## 验证

- PawFolio SwiftPM：**279 tests，0 failures**（新增 4 个 `EarnProjectedPayoutTests`）
- Nvwa SwiftPM：**35 tests，0 failures**
- `xcodebuild build-for-testing`：**TEST BUILD SUCCEEDED**
- iPhone 17e（iOS 26.4）完整 XCTest：**TEST SUCCEEDED**
- `plutil -lint project.pbxproj`、`git diff --check`：通过
- 截图见同目录：`asset-picker.png`、`single-select.png`、`detail-earn.png`、
  `detail-trading.png`、`overview-full.png`

验证期间加过三个临时 `#if DEBUG` 钩子（开资产选择器 / 开产品表单 / 开明细页），
**已全部删除**，`grep PAWFOLIO_QA_LEDGER_SHEET|PAWFOLIO_QA_SELECT_FIELD|PAWFOLIO_QA_LEDGER_DETAIL`
无残留。
