# PawFolio V2.1.0 资金账本模型

> 状态：V2.1.0 本地账本、迁移、估值和产品 UI 已于 2026-09-05 完成；云端账本同步按产品决定
> 留待独立协议设计。
> 产品设计：Pawfolio Design `ThlaCizGXDV4puXbtg8Fk0`，版本页 `134:7230`。

## 目标

PawFolio 不再允许资产因直接新增、修改或删除而凭空出现或消失。余额与持仓由交易流水
投影得到；每笔数量变化都必须能说明来源和去向。

账本按每一种原始资产分别守恒，不在账本层做换汇：

```
用户期末余额 = 期初余额 + 外部存入 - 外部支出 + 投资收益 + 内部转移净额
```

行情只改变资产的展示估值，不改变账本数量。V2.1.0 不新增换汇流水，也不实现股息。

## 账户

| 账户 | 用途 | 规则 |
|---|---|---|
| Fiat / Spot | USD、CNY、USDT、USDC 等可用余额，并按 Bank、Cash、Exchange、Alipay、WeChat 等位置区分 | Add asset 从外部进入；Pay 可从这些位置选择 |
| Trading | 股票、ETF、Crypto 投资资产 | 买卖只能使用 Exchange 的 Fiat / Spot 余额结算 |
| Earn | 用户配置的理财产品本金 | 每个产品一个账户，只能通过申购、赎回、派息改变 |
| External | 工资、其他存入、商户、市场、利息等系统外对手方 | 不参与用户余额不足校验 |

`Fiat / Spot` 的位置不是可随意转账的第四类账户。它用于 Pay 的现实资金位置和理财的
可用余额；通用“划转”入口暂不提供。

## 事件全集

| 事件 | 分录 | 关键约束 |
|---|---|---|
| Add asset / Deposit | External → Fiat / Spot | 来源真实性不校验；只提供可选备注；不计为投资收益 |
| Pay / Expense | Fiat / Spot → External | 可选 Bank、Cash、Exchange、Alipay、WeChat 等位置；余额不足失败 |
| Buy | Market → Trading 标的；Exchange Spot 结算币 → Market | 只允许 USD、USDT、USDC 结算；保存实际数量、成交价与手续费 |
| Sell | Trading 标的 → Market；Market → Exchange Spot 结算币 | 同上；卖出数量和结算余额均校验 |
| Earn Subscribe | Fiat / Spot 或 Trading → Earn | 法币/稳定币从 Fiat / Spot 进入；Crypto 从 Trading 进入；股票和 ETF 禁止 |
| Earn Redeem | Earn → 原资金账户 | Fiat / stablecoin 返回 Fiat / Spot；Crypto 返回 Trading |
| Interest payout | External → Earn 或 Fiat / Spot / Trading | 到真实付息时间才入账；复利在该次付息时进入本金，单利不进入本金 |
| Opening balance | External → 对应用户账户 | 升级建账快照，不算收入，不伪造旧交易历史 |
| Reversal | 原流水的逐 posting 精确反向 | 原记录与冲正记录都保留；同一流水只能冲正一次，期初余额不可冲正 |

流水不物理删除。后续删除交互应采用反向冲正，原记录保留。

## Earn 产品

用户先配置产品，再从已有余额申购。配置包含：

- 名称、底层资产、APY、单利/复利、活期/定期/结构化、付息频率、起息时间和可选到期时间。
- 底层资产只允许法币、稳定币、Crypto；不允许股票和 ETF。
- 定期产品只允许单利。
- 结构化产品在本版本只展示用户输入的参数并做基础计息，不实现障碍价或结算引擎。
- APY 修改从下一次付息周期生效；不修改已经入账的利息。
- 复利不是“固定每日复投”。产品何时实际付息，就在何时生成利息分录并复投。
- 申购提交后立即从来源账户转入 Earn 并锁定资金，但计息本金使用每笔申购独立的
  Effective Date：Hourly 从提交后的下一个整点起息；其余产品在当日 16:00 前（不含
  16:00）提交则当日 16:00 起息，16:00 整及之后提交则次日 16:00 起息。等待建仓期间
  不产生收益。
- 起息和派息是两个边界。起息后利息立即开始累计，但必须完整经过一个派息周期才允许生成
  第一笔利息流水：Daily 若今天 16:00 起息，明天 16:00 首派；Hourly 在下一个整点起息，
  到下下个整点满一小时后首派。Weekly / Monthly 同样必须先走满一周 / 一个日历月，再落到
  对应的周五 16:00 / 月度派息点；到期一次性派息仍以到期时刻为准。
- 未派息利息按本金变化与 APY 生效时间分段估算；到期后停止累计，冲正后的申购或派息不参与计算。
- Daily 固定 16:00，Weekly 固定周五 16:00，Monthly 锚定产品起始日的 16:00；月末产品
  经过短月份后不会永久漂移日期。
- 活期、定期和结构化产品均可下架。下架将 Earn 账户的完整余额一次性赎回对应来源账户，并保留产品、申购、赎回与历史收益流水。
- Crypto Earn 的数量与成本需要保留，以便后续展示市场价格盈亏；利息分录独立统计为
  interest yield，不能混入 market P&L。

## 余额和收益口径

- 每个 `LedgerEntry` 按资产代码的 posting 加总必须为零。
- 投影按时间顺序应用流水，任何用户账户不得出现负余额。
- Trading 成本使用实际成交价和手续费；卖出按当前平均成本释放成本。
- 期初交易持仓保留旧 `costPerShare`，但不伪造成历史买入。
- 总资产仍可复用现有行情和汇率服务换算成 USD 展示；V2.1.0 不新增汇率交易记录。
- Add asset 是外部净流入，Pay 是外部净流出，两者都与投资收益分开。
- 总资产统一换算为 USD：法币使用汇率快照，stablecoin 按 1 USD，股票/ETF/Crypto 使用行情；
  缺任一必要价格时明确报告缺失资产，不展示伪造合计。
- PNL = 当前 USD 总资产 − 外部净投入/期初成本；买卖、Earn 内部划转和利息不会被误计为新增本金。
- Earn Holding 的 `Total (USD)` 只统计已经生成 `.interest` 流水并实际进入 Spot / Earn 的收益；
  未到派息时间的应计利息只显示在逐产品持仓行，不进入 Total。冲正与未来日期流水不计入。

## 数据与迁移

- 旧 `Holding` / Supabase payload 暂时保持 `schemaVersion = 2`，避免破坏 Web 与云端兼容。
- 新 `LedgerEntry` 使用 `schemaVersion = 3`；本地文件为 `ledger-v3.json`。
- Guest 与每个登录账号继续严格分目录保存。
- 用户明确选择导入后，guest ledger 按不可变 ID 合并到 account ledger；ID 内容冲突时整体拒绝，
  guest 原件永不删除。即使余额已经花完，只要仍有流水历史也会提示导入。
- 首次启动 V2.1.0 时，把仍有效的旧持仓迁为建账日 opening balance：
  - market / dividend → Trading；旧股息只保留在历史数据中，不继续发展股息功能。
  - 零利率 interest → Exchange Fiat / Spot。
  - 正利率 interest → 一个迁移生成的 Earn 产品与 Earn 期初余额。
  - hybrid → 一个以原资产计量的 Earn 期初余额，避免同一资产被拆两份后重复计算。
- `legacyMigrationVersion` 与账本原子保存，保证迁移只执行一次。
- 当前只做本地账本；云端 schema / RLS 与多端同步在本地交互稳定后单独设计。

## 利息与币价的关系（用户 2026-09-05）

**申购什么资产，利息就是什么资产。** BTC 活期产生的利息也是 BTC，USD 活期的利息是 USD。
所以理财只需要管 APY，**币价完全不参与利息计算**：
`EarnInterestCalculator` 的输入只有「本金数量 × 年化 × 时间」，签名里没有行情。

由此自然分开了两件事，不需要在产品上专门展示价格：

- **利息收益** = 资产数量的增长，只由 APY 决定；
- **币价盈亏** = 本金和已得利息折算成法币时的估值变化。

**但币价波动必须体现在总资产上。** Earn 账户和 Trading 一样是 user-controlled，
`LedgerValuation` 对它按行情计价并计入总额；拿不到行情时不伪造总数，
而是把资产记进 `missingAssetCodes`。

钉住这三条的测试：`EarnInterestIsDenominatedInProductAssetTests`
（派息 posting 记在产品资产上、利息是数量、和价格无关）与
`EarnPrincipalIsValuedAtMarketTests`（Earn 余额参与报价请求、总资产随币价变动、
缺行情时总额为 nil）。

## V2.1.0 完成边界

本版本的本地资金闭环、旧数据迁移、访客导入、真实估值、冲正、Earn 计息与全部设计页面均已
接通并通过单元测试和 iPhone 17e 模拟器测试。明确不在本版本内的只有云端 ledger schema、RLS、
跨端冲突协议、换汇流水、股息和结构化产品结算引擎；这些是后续独立功能，不是遗漏实现。

## 导航与 UI 范围

- 保持三个底部 tab，不增加第四个 tab。
- Transactions 是从资产页右上角 history 操作进入的轻量页面。
- 所有 V2.1.0 页面以 Figma `134:7230` 为像素级验收标准，并优先复用 Nvwa 组件。
- 本文只定义资金规则；页面几何、文案和状态以对应 Figma node 的 design context 为准。

## 已知设计注释覆盖

历史页节点 `155:14976`、`158:16990` 的旧注释仍写着复利“daily”复投。用户最终决定优先：
**每次真实派息时复投**。实现与验收均按最终决定，不按旧注释。

理财资产选择节点 `173:21473` 的注释写着选项应包含「数字货币和股票前 100 名以及所有法币」。
**用户 2026-09-05 决定：暂不放开股票。** 股票 / ETF 继续被 `LedgerAsset.canEnterEarn`
拒绝，`LedgerEarnAssetPicker` 按它过滤，实际选项是前 100 数字货币 + 全部法币。
`AssetLogoCatalog.stocks` 那 100 只 logo 已经打包在 App 里，将来若放开，
改的是这条资金规则和 `testStocksCannotEnterEarn`，不是 UI。
