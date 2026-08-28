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

### 5. 产品化与发布 — 未开始

- [ ] 将品牌图标整理进 Asset Catalog，补齐 App Icon 和启动体验。
- [ ] 完整本地化、Dynamic Type、VoiceOver、深色模式和 Reduce Motion 检查。
- [ ] 网络失败、空数据、同步冲突等状态设计。
- [ ] 真机签名、隐私说明、App Store Connect、TestFlight。
- [ ] UI 测试、关键迁移 fixture、崩溃与性能检查。

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
