# PawFolio 原生 iOS 功能迁移清单

本文件是跨代理的功能总账。状态以 iOS 原生实现和可验证结果为准，不以“已有文件”为完成标准。

## 技术边界

- 纯 SwiftUI，不使用 `WKWebView`、网页嵌入或 JavaScript bridge。
- iOS 17+、Swift 6、SwiftUI、Swift Charts。
- 领域计算保持纯 Swift；界面只通过 ViewModel 和 Repository/Service 访问数据。
- Web 版继续独立运行，`public/app.js` 只作为行为契约参考。
- 所有可能进入 Supabase 的持仓 payload 使用 `schemaVersion`；删除使用 `deletedAt` 墓碑。

## 功能清单与状态

### 1. 收益计算器 — 已完成基础版本

- [x] 本金、年化利率、单利/复利输入。
- [x] 日/月/年收益结果。
- [x] 日/月/年预测曲线和 Web 公式一致性测试。
- [ ] 在结果中同步显示 CNY 估值。
- [ ] 保存用户最近一次输入偏好。

### 2. 汇率换算 — 已完成基础版本

- [x] CNY、USD、THB、MYR 四币种换算。
- [x] 原生 `URLSession` 请求和本地缓存降级。
- [x] 下拉刷新、更新时间和离线状态。
- [ ] 将第三方汇率请求收口到自有 Worker `/api/fx`。

### 3. 投资组合 — 本地基础版本已完成

- [x] 兼容 `market`、`interest`、`hybrid`、`dividend` 四种持仓 JSON。
- [x] 原生持仓总览、空状态、列表、添加、编辑、左滑删除。
- [x] 市场资产、稳定生息、混合收益、分红字段表单。
- [x] Application Support 内原子 JSON 持久化。
- [x] 旧裸数组迁移读取、损坏文件不静默覆盖。
- [x] `schemaVersion = 2` 和 `deletedAt` 删除墓碑。
- [x] Yahoo 标的搜索，复用 Worker `/api/search`，包含防抖与离线常用标的。
- [x] 最新行情和 12 小时失败降级缓存，复用 Worker `/api/quote`。
- [x] 无行情时的持仓估值、确认分红和已结算利息领域模型。
- [x] 北京时间次日 16:00 结息、跳过结息日和本金分段计算。
- [x] 接入美元实时价后的市值、持仓盈亏与组合总盈亏。
- [x] 加仓、减仓、加权成本；卖出资金按精确时间戳转入 0% APR 的 USDT。
- [ ] 同代码持仓合并展示和分批展开。
- [x] 原生持仓详情、调整历史、盈亏明细、分红记录与逐日利息记录。
- [x] 24 小时、7 天、30 天、1 年原生 Swift Charts 组合走势图。
- [x] 从调整记录倒推历史数量与本金，清仓持仓继续参与清仓前历史。
- [x] 短期行情随报价缓存；月/年使用独立的一年日线与 12 小时磁盘缓存。
- [x] 走势图末点与顶部总资产同口径，前向填充和缺少历史的标的明确提示。
- [x] 清仓使用 `closedAt`，当前内存历史窗口保留 400 天且不转为删除墓碑。
- [ ] 快捷添加 VOO、AAPL、BTC。

### 4. 账号、资料与跨端同步 — 持仓生产同步已验证，资料云端接线待完成

- [x] Supabase access/refresh token 生命周期与 Keychain 安全存储。
- [ ] Sign in with Apple。
- [x] Google OAuth PKCE、`ASWebAuthenticationSession` 与 `pawfolio://auth/callback` 原生回调。
- [x] Supabase Redirect URLs 已加入 `pawfolio://auth/callback`，模拟器完成登录、回调、Keychain 恢复与退出验证。
- [x] 原生游客本地模式与登录后的显式导入确认界面。
- [x] 游客与不同账号使用独立本地文件，账号目录名使用安全编码。
- [x] 游客数据默认保持独立，仅在显式选择后复制进账号，且不删除游客源数据。
- [x] 纯 Swift 持仓合并引擎：按 `updatedAt`/`createdAt` 决胜，`deletedAt` 墓碑参与冲突且同时间优先。
- [x] 认证会话与云端持仓 Repository 协议边界；云端接口不暴露物理删除。
- [x] `ios/Docs/SYNC_CONTRACT.md` 记录 payload、时间戳、墓碑和 Web 迁移契约。
- [x] 用本地/云端 Repository 和认证会话组装离线可测试的同步协调器与上传失败重试。
- [x] 持久化每个账号的游客导入选择；复制只执行一次，不形成持续关联。
- [x] 账号页、同步状态 ViewModel 与手动重试。
- [x] Web 源码删除流程迁移为墓碑，并补齐与原生一致的确定性合并规则。
- [x] Supabase REST 持仓读取、复合键 upsert、401 强制刷新后单次重试；生产同步已启用并完成端到端验证。
- [x] `(user_id, id)` 复合主键迁移与 Web 墓碑版本已部署；生产测试持仓成功写入 `schemaVersion = 2` 墓碑，原生云仓库已启用。
- [x] 生产 Web → iOS 端到端验证：原生客户端拉取指定墓碑到账号作用域 JSON，活动投资组合保持隐藏，游客测试持仓未上传。
- [x] ViewModel 提供用户名、脱敏账号和登录方式；视图不直接读取完整会话邮箱。
- [x] 本机资料升级为 `schemaVersion = 2`，加入 `updatedAtMilliseconds`，并把旧 6 款占位头像无损迁移到共享头像 ID。
- [x] 将 Web 的 9 张表情头像、9 只真实猫资料和白名单原生化；18 张图片随 App 安装，不经网页加载。
- [x] 资料本地/远端最后写入优先合并规则，以及 `public.profiles` REST 读取、upsert、401 刷新重试的离线测试。
- [x] 独立资料同步协调器与 ViewModel 状态已完成；资料失败不会覆盖成功的持仓同步状态。
- [x] 启用生产 Profile 组合层并完成受控双向验证：iOS → Web、Web → iOS、时间戳决胜、会话刷新与重启持久化均通过。
- [x] 将账号作用域存储接入登录/退出后的组合页数据源切换。

### 5. 产品化与发布 — 启动体验与 Dynamic Type 已完成

- [x] 将品牌图标整理进 Asset Catalog，补齐 App Icon 和启动体验。
- [x] 原生启动屏改用 `LaunchScreen.storyboard`，浅色/深色均已在模拟器实测。
- [x] Dynamic Type 检查：消除全部固定字号，徽章改用可缩放的 `PawBadge`，辅助字号下页首与金额改纵向排列。
- [x] 深色模式检查：颜色全部走动态 trait，启动屏与四个标签页均已实测。
- [x] Reduce Motion 检查：源码不含 `withAnimation` / `.animation` / `.transition`，无需降级路径。
- [ ] VoiceOver 逐页走查（受环境限制，见 `HANDOFF.md`）。
- [ ] 完整本地化（当前为中文硬编码字符串，尚未接入 String Catalog）。
- [ ] 网络失败、空数据、同步冲突等状态设计。
- [ ] 真机签名、隐私说明、App Store Connect、TestFlight。
- [ ] UI 测试、关键迁移 fixture、崩溃与性能检查。

### 6. 本轮审计新发现：Web 已有但清单此前未登记的功能

2026-08-28 用 `public/index.html` 与 `public/app.js` 反向比对原生实现，补登以下条目。它们此前不在本清单里，因此不属于“已知待办”，而是盲区。

- [ ] 顶部实时行情条。Web 头部有一个可点击的行情组件，在 BTC / MSTR / QQQ 之间轮换，显示价格、涨跌与**美股交易时段徽章**（盘前 / 交易中 / 盘后 / 夜间 / 休市），并带 2026–2027 全天休市日表和提前收盘日表；BTC 不参与时段判定。原生完全没有这个模块。注意 iOS `MarketData.offlineFallbacks` 里的 MSTR/QQQ 只是搜索离线备选，与此无关。
- [ ] “我们家的猫”图鉴。Web 有独立弹层展示九只真实猫，可点选设为头像，**长按看大图**，大图带名字、简介、性别与生日。原生只把九只猫做成了头像选择项：`CatAvatar` 仅保留名字，`desc` / `sex` / `birth` 与照片查看器均未迁移。
- [ ] 品牌状态插画。Web 有 `public/illustrations/` 七张黑猫态图（其中六张在用：`search` / `login` / `notfound` / `no_data` / `loading` / `net_fail`），通过 `.state-art[data-art]` 用在未登录、暂无持仓、等待搜索等空状态。原生这些位置用的是 `ContentUnavailableView` 加 SF Symbol，插画资产一张都没有进 Asset Catalog。与下方“网络失败、空数据”状态设计一并处理。
- [ ] 走势图长按扫描。Web 图表有 `pointerdown` 手势配合 `#chart-tooltip`，可按住查看任意时间点的数值。原生走势图只有 `accessibilityValue`，没有任何手势。
- [ ] 手动深色/浅色切换。Web 头部有切换按钮并记忆到 `localStorage`，未设置时才跟随系统。原生只跟随系统。
- [ ] 记住上次所在标签页。Web 用 `jiujiu-active-tab` 记忆，原生每次冷启动固定落在「计算」。

### 7. 清单中的待办里，Web 侧同样没有的项（属新功能，不是迁移缺口）

- 「保存用户最近一次输入偏好」：Web 的 `localStorage` 只存了行情缓存、汇率缓存和当前标签页，并未保存计算器输入。
- 「将第三方汇率请求收口到自有 Worker `/api/fx`」：Web 与原生目前都直连 `https://open.er-api.com/v6/latest/USD`，这是两端共同的架构改进。
- 「Sign in with Apple」：受 Apple Developer Team 阻塞，与 Web 无关。

### 8. 有意的差异，不作为缺口

- Web 持仓页是硬门禁，必须登录；原生保留游客本地模式，登录后再显式导入。
- Web 账号入口在头部；原生是独立的「账户」标签页。
- 分红频率六种取值（`quarterly` / `monthly` / `semimonthly` / `semiannual` / `annual` / `irregular`）两端已核对一致。

### 9. UI 复刻（2026-08-28 方向调整）

> **2026-08-29 收尾盘点。** 按「Web 有哪些弹层和反馈机制」重新对照了一遍，
> 而不只是查原生控件残留，又补上四处：
>
> - 标的搜索弹层（原本是原生 `List` + 导航标题）。右上角是「取消」文字不是 ×，
>   空/错状态用 `search` / `notfound` / `net_fail` 插画。
> - 分红记录编辑（原本是原生 `Form`）。
> - 持仓详情的三个二级记录列表（原本是原生 `List`）。
> - **Toast**：Web 有 33 处 `showToast()`，原生完全没有这套反馈。已补
>   `DesignSystem/PawToast.swift`，在加减仓、删除持仓、删除利息/分红记录后给提示；
>   校验类的错误原生仍走 alert。
> - **分红频率选择**在 Web 是独立弹层（`#dividend-frequency-overlay`，选项行加勾选），
>   原生先做成了按钮网格，已改为弹层，持仓编辑与分红记录编辑共用。
>
> 同时清掉两块死代码（详情页重写后失效的 `overviewList` 80 行、`incomeList` 17 行），
> 把最后 19 处系统语义字体换成 Inter。现在 `Features` 下原生列表、导航标题、
> 系统字体均为零，`Picker` 只剩合理的 `DatePicker`。
>
> 底部导航按用户要求改成贴底浮层：`safeAreaInset` 让滚动内容从导航下穿过，
> 毛玻璃才有东西可糊（先前排在 `VStack` 里，底下没内容，玻璃看不出效果），
> 玻璃铺到屏幕物理边缘、图标留在安全区内。切换标签加一次轻震动。

> **总资产走势图是手绘 canvas，不是图表库画的。** 2026-08-29 用户在真机上指出四处偏差，
> 根源是原生用 Swift Charts 画了一条普通折线，而 Web 的图有它自己的形状：
>
> 1. **收起态有迷你曲线**（`.portfolio-sparkline`，72 高，跟在总资产右边，
>    列宽 `clamp(104px, 36%, 200px)`），原生做成了完全隐藏。展开后这一列让位，
>    大数字自己撑满整行——「展开后宽度不对」就是缺了这一步。
> 2. **曲线下方铺的是点阵**（`fillDotMatrix`），不是实心或渐变色块。
>    大图 6px 网格、1.4px 方点、34% 透明；迷你图 4px 网格、1.1px 方点、30% 透明
>    ——迷你图那块只有 120×72，用 6px 会只剩稀稀拉拉几颗。
> 3. **区间最高值标在它自己的位置上方**，11px，不写「最高」二字。
> 4. 展开把手的图标是 `rotate(180deg)` 配 200ms 过渡，不是位移。
>
> 已改为 SwiftUI `Canvas` 自绘（`Features/Portfolio/PortfolioChartCanvas.swift`），
> 刻度、留白比例（padLo 0.30 / padHi 0.12，迷你图 0.26 / 0.10）、`CHART_PAD`
> 与大图高度 188 全部照搬。X 轴是画布外的独立一行，时间戳常驻占位（否则一出现整块图会往下跳）。
>
> 尚未实现：长按扫描（游标虚线、右侧压到 32%、顶部数字换成当时值）。

> **量取实际渲染值，不要照抄 CSS 源码。** 2026-08-28 用户指出原生「用了很多卡片包住元素，
> 而 Web 那边很多地方都去掉了」。核对后确认有两处系统性偏差，根源都是照着 CSS 源码里的
> 桌面值实现、漏了窄屏覆盖：
>
> 1. `#portfolio-app > .card { padding: 0; border-radius: 0; background: transparent }`
>    把投资组合页三个区块的卡片外观全部去掉——CSS 注释写着「投资组合的各区块共用同一个
>    页面表面，用间距而不是嵌套容器来分隔」。先前只找到了 `#panel-retirement > .card`
>    和 `#panel-fx > .card` 那一条，漏了这条（选择器是 `#portfolio-app` 不是 `#panel-portfolio`）。
>    现在全 App 只剩计算页的「投资计划」还是卡片。
> 2. `@media (max-width: 767px)` 把页面边距、头部内边距和保留下来的卡片内边距一律降到 16，
>    并把 `.metric` 压到 `10px 12px` / 20px 字号。**所有 iPhone 都在这个断点内**，
>    先前实现的是 28 / 24 的桌面值。
>
> 随后把所有尺寸相关的媒体查询整块提出来逐条核对，又补上四条此前完全没实现的：
>
> - `max-width: 485px` 隐藏行情条的标的名；`max-width: 415px` 隐藏涨跌；`max-width: 347px`
>   整条行情隐藏。**402 宽的 iPhone 上，行情条只剩 logo、价格和交易时段徽章**，
>   先前把名字和涨跌都画了出来。
> - `max-width: 560px` 把 `.metric` 压到 padding 10、主数字 17/24、辅助文字 11，
>   但 `max-width: 389px` 排在它后面，塌成一列时又回到 padding 10px 12px、主数字 20/28。
>   三档都要按视口宽度判断。
> - `max-width: 380px` 把快捷金额的间距收到 4、总投资输入框字号降到 20。
> - ~~`max-width: 560px` 把计算页图表高度定为 200~~ —— 2026-08-29 起计算页图表统一 150，
>   这条断点已从 `styles.css` 删除，两端都不再按宽度改高度。
>
> Web 的媒体查询按**视口**宽度生效，所以原生用 `RootTabView` 在根部量一次视口宽度、
> 经 `\.pawViewportWidth` 注入，各组件据此判断断点，而不是各自去看容器宽度。
>
> 汇率页与各弹层逐项量过，没有偏差。
>
> 以后对齐样式一律用浏览器取 computed style 核对，并且要在多个宽度下量，别只读 CSS 源码。

用户明确要求：**原生代码，但界面完全复刻 Web**。`AGENTS.md` 的 Design direction 已按此重写，
先前「优先原生控件」那条作废——正是它导致了第 6 节那批功能被「重新设计」掉。

已完成：

- [x] `PawTheme` 改为 `public/styles.css` 设计变量的原样移植：`--bg-*`、ink alpha 阶梯、
      三组染色标签、`--accent` / `--gain` / `--loss` / `--flat`、五种交易时段色、
      `--radius-block` / `--radius-card`。
- [x] `PawControls.swift`：`.card` / `.field-label` / `.input-shell` / `.quick-amounts` /
      `input[type=range]` / `.segmented` / `.calculate-btn` / `.metric` / `.period-tabs`
      的 SwiftUI 复刻件，数值照搬 CSS。滑杆是自绘的，SwiftUI 的 `Slider` 做不出 2pt 轨道
      加 16pt 描边圆钮的外观。
- [x] `PawChrome.swift`：Web 的 `.topbar` 与贴底 `.tabbar`。
- [x] 标签页从 iOS 的四个改回 Web 的三个；账号入口移到头部头像，点击弹出面板。
- [x] 头部行情条：BTC / MSTR / QQQ 轮换，接真实报价，涨跌染色。
- [x] 手动深色/浅色切换（第 6 节的盲区之一），选择存本地，未选择时跟随系统。
- [x] 计算器页按 Web 结构重做，并补上第 6 节缺的 CNY 估值：标题旁的实时汇率行、
      三张收益卡的 `¥` 副值、走势图上的 `≈¥` 估值。汇率行按 Web 用 24 小时制。
- [x] 移除原生自行添加、Web 没有的介绍卡与页面大标题。

- [x] 修正卡片用法。Web 在计算页和汇率页把 `.card` 的外观整体去掉了
      （`#panel-retirement > .card, #panel-fx > .card { padding: 0; background: transparent }`），
      只有「投资计划」那一块保留卡片。原生先前把「收益预估」也包进了卡片，已改为裸区块。
      投资组合页没有这条覆盖，卡片外观保留。
- [x] 打包 Remix Icon 4.6.0（Apache-2.0，许可证存 `ios/PawFolio/Resources/LICENSE-remixicon.txt`）：
      标签栏三枚、主题切换的月亮/太阳、头像占位、交换箭头、关闭与新增，共九枚，
      以 template 模式染色。SF Symbol 代用已全部撤掉。
- [x] 打包 `public/flags/` 的四面真实国旗，替换掉原生的 emoji 国旗。
- [x] 汇率页复刻：无卡片外观，真实国旗，圆角交换连接符，结果行 `--ink-4` 填充，
      24 小时制更新时间。
- [x] 把 `public/illustrations/` 的七张状态插画装入 Asset Catalog（`Art*`），供空状态与门禁页使用。

- [x] 打包 Inter 4.1 四个字重（SIL OFL 1.1，许可证见 `ios/PawFolio/Resources/LICENSE-inter.txt`），
      对应 Web 的 `font-family: Inter, "PingFang SC", ...`。Inter 不含中文字形，中文由系统回退到
      PingFang SC，与 Web 行为一致。已复刻界面的 29 处字号全部改用 `PawFont.inter`。
      字号用 `fixedSize` 不随 Dynamic Type 缩放——Web 是固定 px，且输入壳 52、按钮 40、
      分段 36 都是固定高度，跟着缩放会撑破盒子。
- [x] 预先打包投资组合页要用的图标：勾选、Google 标记（保留品牌原色，不染色）、复选框空/实、下箭头。

待办：
- [x] 投资组合页复刻：登录门禁（`login` 插画 + Google 按钮 + 「先看看」游客入口，已接上账号状态）、
      概览区、可展开的走势图、快捷添加三卡、合并同资产复选框、`no_data` 空状态插画、
      虚线添加按钮、Web 样式的持仓行（32pt 圆形首字母、生息/混合的染色标签）。
      「一键添加」与 Web 一致，是打开预填该标的的表单，不是直接建仓。
- [x] 顺带清掉重写后无人引用的旧 `PortfolioSummaryCard` 与 `PortfolioMetric`（130 行死代码），
      并把走势图卡的金额从 iOS 本地化的 `US$` 改回 Web 的 `$`。
- [x] 修掉主题持久化的 bug：`PawThemeController` 原先在 `init` 里给带 `didSet` 的 Optional
      属性赋值，触发观察器把「跟随系统」误写成一次显式选择，导致 App 首次启动后就被锁在当时的
      外观上、再也回不到跟随系统。改为直接初始化底层存储。

待办（投资组合页剩余）：

- [x] 合并同资产完成：新增 `Domain/HoldingGrouping.swift`（分组、合并汇总、利息小结，
      10 个单元测试），组行可点开展开子行，利息小结按 Web 的做法排在子行**上面**——
      放在子行之后的话，笔数一多就被挤出屏幕。
      Web 那几条「不确定就不显示」的规则一并复刻并测试：组内任意一笔缺行情则合计不给；
      年化不一致不标年化；计息方式不一致不标单利/复利（挑一个当代表是谎报）；
      生息与市场类混在一组时改说「综合成本」而不是份数。
      实机验证：账号里的 4 笔 USDT 合并成一组，因三笔年化（21.09% / 3.75% / 2.7%）
      与计息方式都不一致，组行确实没有标签。
- [x] 资产 logo：新增 `Domain/AssetLogo.swift`（候选地址生成，9 个单元测试）与
      `Data/AssetLogoStore.swift`（按序试、内存缓存、CMC 映射表磁盘缓存一天）。
      四处共用同一套解析：行情条、快捷添加、持仓行、搜索结果，取不到才退首字母。
      候选顺序照搬 Web：加密与稳定生息先走 CMC → CoinCap → cryptoicons，股票先走 Parqet
      再补试加密源（旧持仓里的加密货币没存 `-USD` 后缀，只看 `assetType` 会漏判）。
      映射表来自网络，CMC 的数字 ID 校验成正整数才拼进地址；手打的标的名（「活期」这类）
      不像代码就一个候选都不给，避免白打 404。
- [x] 持仓详情改为底部弹层，并按 Web 的「盈亏明细」重做：顶部是代码加总盈亏大数字，
      下面是一张 `--bg-2` 明细清单（行高 64、行间发丝线），字段按持仓类型条件显隐——
      生息类不显示份数/成本价/最新价，市场类不显示 APR 与利息三行。
      再往下是「最近一次分红」卡（四个字段固定 2×2，Web 注释说 auto-fit 在窄屏会把第四个吊到第二行）
      和记录入口，底部是「编辑持仓」。
      分红频率按 Web 写成「季度分红」这种形式。
- [x] 记录列表改为二级弹层，和 Web 一样从明细弹层再推一层。

差异（需用户确认）：

- Web **没有**调整历史的列表界面——调整在那边是一次性操作，记录只存在数据里。
  原生此前把它做成了详情页的一个分段，现在降级成与分红/利息并列的第三个记录入口。
  要严格对齐 Web 的话应当整个去掉，但那会丢掉一个用户能看到自己加减仓历史的功能，
  所以先保留，等用户定夺。
- [x] 行情条的美股交易时段徽章：新增 `Domain/MarketSession.swift`，移植 `app.js` 的
      `marketSessionKey`，含 2026–2027 全天休市日表与提前收盘日表。时区换算交给
      `TimeZone(America/New_York)`，不手算偏移——夏令时一年切两次。
      14 个单元测试覆盖各时段边界、周五 20:00 进周末、周日 20:00 夜盘开市、周一凌晨延续周日夜盘、
      假日全天休市、假日次日凌晨无夜盘可延续、提前收盘日 13:00 收盘，以及两个夏令时切换后的边界。
      徽章只对股票类标的显示，加密货币没有时段可言。
- [x] 账号面板复刻：Web 的资料弹层结构（抓手、居中标题、右上关闭、底部保存/登录），
      用户名 20 字上限、九张表情头像网格、退出登录、脱敏账号行；未登录时标题变「登录」，
      只留 `login` 插画和一句说明——Web 的理由是「改了名字头像却存不下来，比不给改更糟」。
      同步状态与游客导入选择是原生特有的（Web 的同步静默自动），排在 Web 结构之后保留。
- [x] 「我们家的猫」图鉴复刻：九只猫的相纸样式（直角、4pt 白边、投影——Web 注释说明这是
      全站唯一用投影的地方）、名字配粉/蓝性别图标、简介，长按打开大图查看器。
- [x] 保留 Web 的彩蛋手势：单击顶栏头像开个人资料，**双击**开猫图鉴。资料弹层里另给了
      一个显式入口，否则没人会发现。
- [x] 新增 `Domain/CatProfile.swift`：九只猫的资料与 `CatAgeFormatter`，是 `app.js` 里
      `catAgeText` / `catBirthText` 的移植，含 11 个单元测试覆盖「不满一岁按月、一两岁带月份、
      再大只说岁」以及未来生日、只有年份、生日未到当月等边界。
- [x] 顺带删掉重写后无人引用的 `AccountProfileEditorView`（138 行死代码）——Web 把用户名和
      头像直接放在资料弹层里，不是二级页。
- [x] 计算页「总资产变化」图表改成与投资组合展开图同款（Web 与 iOS 同步改）：点阵填充、
      峰值标注、长按扫描，但**不用红绿**、画布高度降到 150。顶部涨跌数字也一并去色改
      `--ink-40` / `PawTheme.ink40`——那是按输入利率推出来的预测，不是真实盈亏，染成红绿会误导。
      Web 侧顺带删掉了悬浮气泡（`#chart-tooltip`、`showTooltip`），读数改由顶部数字承担。
      注意 `drawChart` 在顶层初始化阶段就会被调用，引用定义在文件更后面的 `const` 会撞 TDZ 直接白屏。
- [x] 分割线全局统一 0.5pt，收口到 `PawDivider`。卡片/输入框的 `strokeBorder` 是描边不是
      分割线，未动。
- [x] 动效收口到 `PawMotion`（`PawTheme.swift`），一律用 iOS 17 自带的 spring 预设
      （`.snappy` / `.smooth`），不再手写 `.easeOut(duration:)`。弹簧被打断时会从当前速度
      重新收敛，连点展开/连点切换标的不会「弹回起点再来一遍」。覆盖展开收起、列表增删、
      合并开关、两个分段控件、toast、行情轮播、按压反馈。分段控件的选中块改用
      `matchedGeometryEffect` 滑动，两段时的淡入淡出看着像闪了一下。
- [x] 新增持仓备注（Web 与 iOS 同步）：最多 20 个字，只有写了才在盈亏明细里出现。
      云端存的是整份 payload JSON，**不需要跑数据库迁移**。长度按字符/码点数，不按 UTF-16——
      HTML 的 `maxlength` 和 `String.utf16.count` 都会把一个 emoji 算两个，Web 会在第 10 个
      就卡住，还可能把代理对劈开；所以 Web 那个 input 没有 `maxlength`，改用 `input` 事件按
      码点裁。截断而不是拒绝输入，否则中文输入法在拼音候选阶段就被卡住。
- [x] 字体与图标已全部打包，此条完成。原文如下：Web 用 Inter（rsms.me）和 Remix Icon 4.6.0（jsDelivr），两者都没有打包进
      App，目前分别用系统字体和最接近的 SF Symbol 代替。两者均为开源可打包，需用户决定是否引入。

## 推荐实施顺序

1. 完成持仓估值领域逻辑和测试。
2. 接入 Worker 的标的搜索与行情，加入缓存和错误状态。
3. 做加减仓、分红/利息记录与组合走势图。（已完成）
4. 定义并实现带墓碑的 Supabase 双端同步协议。
5. 接入 Apple/Google 登录与个人资料。
6. 完成无障碍、真机、TestFlight 和商店发布。

## 用户介入点

代码阶段默认由代理继续推进。以下事项需要用户提供或确认时再暂停：

- Bundle ID 已确认为 `com.jiujiucat.pawfolio`；仍需 Apple Developer Team 和 App Store Connect 应用。
- Supabase 公开配置和 `pawfolio://auth/callback` Redirect URL 已确认。
- 线上 Worker 基础域名；本地代码不硬编码未经确认的生产域名。
- 隐私政策、商店文案、截图及发布地区。
