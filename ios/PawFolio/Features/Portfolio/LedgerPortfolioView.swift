import Nvwa
import SwiftUI

private enum LedgerRoute: Identifiable {
    case add
    case transactions
    /// 从已持有的资产点进来时带上标的，交易表单直接预填，不用再搜一次
    /// （设计 `158:18023` 的 Trading 按钮连到 `159:19567`，那一帧资产字段是填好的）。
    case trading(preselected: AssetSearchResult?)
    case earn

    var id: String {
        switch self {
        case .add: "add"
        case .transactions: "transactions"
        case let .trading(market): "trading-\(market?.quoteSymbol ?? "")"
        case .earn: "earn"
        }
    }
}

private enum LedgerOverviewReorderItem: Hashable {
    case trading(LedgerAsset)
    case earn(String)
}

/// 两行持仓行的定高：p16 上下 + 主字 B-L Semi Bold 16/24 + 间距 4 + 副字 B-M Regular 14/22。
/// 行内文字都用 `.frame(height:)` 钉死行高，所以这个值不随动态字体变。
private let ledgerHoldingRowHeight: CGFloat = 82

/// 资产 chip 那一排的排版：`HStack(spacing:)` 和拖动换位的判定要用同一个间距，
/// 分开写迟早对不上（chip 宽度不一致时，让位距离 = 被拖 chip 宽 + 间距）。
private enum LedgerSpotChipMetrics {
    static let spacing: CGFloat = 10
}

private struct LedgerSpotWidthPreferenceKey: PreferenceKey {
    static var defaultValue: [LedgerAsset: CGFloat] { [:] }

    static func reduce(value: inout [LedgerAsset: CGFloat], nextValue: () -> [LedgerAsset: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

struct LedgerPortfolioView: View {
    @Environment(\.pawViewportHeight) private var viewportHeight
    @StateObject private var model: LedgerPortfolioViewModel
    @State private var route: LedgerRoute? = {
        #if DEBUG
        // 视觉 QA：`trading:BTC` 直接带着标的进交易表单，否则三个联动字段
        // （价格 / 数量 / 金额）在没选标的之前根本不画出来。
        let raw = ProcessInfo.processInfo.environment["PAWFOLIO_QA_LEDGER_ROUTE"] ?? ""
        let parts = raw.split(separator: ":", maxSplits: 1).map(String.init)
        switch parts.first {
        case "add": return .add
        case "transactions": return .transactions
        case "trading":
            return .trading(preselected: parts.count > 1
                ? AssetSearchResult.offlineFallbacks.first {
                    $0.symbol.caseInsensitiveCompare(parts[1]) == .orderedSame
                }
                : nil)
        case "earn": return .earn
        default: return nil
        }
        #else
        return nil
        #endif
    }()
    @State private var selectedAsset: LedgerAsset?
    /// 点 Trading / Earn 行进的是明细页（设计 `158:18023` / `158:16698`），
    /// 不是直接跳交易或申购表单。
    @State private var detail: LedgerDetailTarget?
    @State private var showsPay = {
        #if DEBUG
        ProcessInfo.processInfo.environment["PAWFOLIO_QA_LEDGER_ROUTE"] == "pay"
        #else
        false
        #endif
    }()
    @State private var hidesBalance = false
    /// 走势图默认收起，点迷你曲线展开、点把手收起（设计 `197:2922`）。
    /// 视觉 QA 用 `SIMCTL_CHILD_PAWFOLIO_QA_LEDGER_EXPAND_CHART=1` 直接展开。
    @State private var isChartExpanded = {
        #if DEBUG
        ProcessInfo.processInfo.environment["PAWFOLIO_QA_LEDGER_EXPAND_CHART"] == "1"
        #else
        false
        #endif
    }()
    @State private var chartScrubIndex: Int?
    @State private var spotReorderState = NvwaReorderState<LedgerAsset>()
    @State private var spotItemWidths: [LedgerAsset: CGFloat] = [:]
    @State private var overviewReorderState = NvwaReorderState<LedgerOverviewReorderItem>()
    @State private var showsSuccessPreview = {
        #if DEBUG
        ProcessInfo.processInfo.environment["PAWFOLIO_QA_LEDGER_SUCCESS"] == "1"
        #else
        false
        #endif
    }()

    private let isSignedIn: Bool
    private let profileInitials: String
    private let profileAvatar: CatAvatar
    private let onOpenAccount: () -> Void
    private let onSignIn: () -> Void

    init(
        model: @autoclosure @escaping () -> LedgerPortfolioViewModel,
        isSignedIn: Bool,
        profileInitials: String,
        profileAvatar: CatAvatar,
        onOpenAccount: @escaping () -> Void,
        onSignIn: @escaping () -> Void
    ) {
        _model = StateObject(wrappedValue: model())
        self.isSignedIn = isSignedIn
        self.profileInitials = profileInitials
        self.profileAvatar = profileAvatar
        self.onOpenAccount = onOpenAccount
        self.onSignIn = onSignIn
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                if !showsInitialLoading {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 32) {
                            balanceHeader
                            if isChartExpanded && hasExpandedChart { chartPanel }
                            if let message = model.valuationStatusMessage {
                                NvwaHint(message, level: .neutral)
                            }
                            if model.spotBalances.isEmpty
                                && model.tradingBalances.isEmpty
                                && model.earnBalances.isEmpty {
                                emptyState
                            } else {
                                accountContent
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 110)
                    }
                    .refreshable { await model.reload() }
                    // 兜底的第二道：主力是长按成立时 `stopScrolling` 掐断这一次滚动，
                    // 这里再把排序期间的滚动（以及 refreshable 的下拉）关掉，挡住
                    // 拿起之后新起的触摸。长按成立之前 `isReordering` 一直是 false，
                    // 滑动照常归 ScrollView。
                    .scrollDisabled(isReordering)
                    // 空资产时内容比视口短。显式钉在顶部，避免 iOS 26 的系统
                    // TabView + 顶部 safe-area inset 组合把整段内容居中。
                    .defaultScrollAnchor(.top)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            if showsInitialLoading {
                GeometryReader { geometry in
                    PawAppLoadingIndicator("Loading portfolio")
                        .position(
                            x: geometry.size.width / 2,
                            y: viewportHeight / 2 - geometry.frame(in: .global).minY
                        )
                }
                .allowsHitTesting(false)
            }
        }
        // 顶栏由 `pawGlassTopBar` 挂成 safe-area inset，内容从它底下滑过去，
        // 那层毛玻璃才有东西可糊（用户 2026-09-06）。
        .pawGlassTopBar {
            topNavigation
                .allowsHitTesting(!showsInitialLoading)
        }
        .background(Nvwa.backgroundMain)
        .sensoryFeedback(.impact(weight: .medium), trigger: spotReorderState.feedbackTrigger)
        .sensoryFeedback(.impact(weight: .medium), trigger: overviewReorderState.feedbackTrigger)
        .task { await model.loadIfNeeded() }
        .fullScreenCover(item: $route) { route in
            destination(route)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(Nvwa.backgroundMain)
        }
        .sheet(isPresented: $showsPay) {
            LedgerPaySheet(model: model)
        }
        .sheet(isPresented: $showsSuccessPreview) {
            PawSuccessSheet()
        }
        .fullScreenCover(item: $detail) { target in
            switch target {
            case let .trading(asset, quantity):
                LedgerTradingDetailView(
                    model: model,
                    asset: asset,
                    quantity: quantity,
                    onTrade: { route = .trading(preselected: $0) }
                )
            case let .earn(product):
                LedgerEarnDetailView(model: model, product: product)
            }
        }
        .alert("Transaction Error", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(LocalizedStringKey(model.errorMessage ?? "Unknown error"))
        }
    }

    private var showsInitialLoading: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["PAWFOLIO_QA_LEDGER_LOADING"] == "1" {
            return true
        }
        #endif
        return !model.hasCompletedInitialLoad
    }

    private var topNavigation: some View {
        PawTopNavigation(
            isSignedIn: isSignedIn,
            profileInitials: profileInitials,
            profileAvatar: profileAvatar,
            trailingIcon: Image("IconFileHistory"),
            trailingTone: .neutral,
            showsTrailing: isSignedIn,
            trailingAccessibilityLabel: "Transactions",
            onOpenAccount: onOpenAccount,
            onSignIn: onSignIn,
            onTrailing: { route = .transactions }
        )
    }

    private var selectedBalance: (asset: LedgerAsset, quantity: Double)? {
        if let selectedAsset,
           let found = model.spotBalances.first(where: { $0.asset == selectedAsset }) {
            return found
        }
        return model.spotBalances.first
    }

    private var balanceHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 2) {
                    Text("Total Balance")
                    Button { hidesBalance.toggle() } label: {
                        Image(hidesBalance ? "IconEyeClosed" : "IconEyeOpen")
                            .resizable().frame(width: 14, height: 14)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(hidesBalance ? "Show balance" : "Hide balance")
                }
                .nvwaTextStyle(Nvwa.Typography.bodySmall, linesFillLineHeight: false)
                .foregroundStyle(Nvwa.textSecondary)

                Text(hidesBalance ? "••••••" : model.portfolioSummary.totalValueUSD.map(MoneyFormat.usd) ?? "—")
                    .nvwaTextStyle(Nvwa.Typography.titleSection, linesFillLineHeight: false)
                    .monospacedDigit()
                (Text(LocalizedStringKey(pnlLabel)) + Text(verbatim: hidesBalance ? " ••••" : " \(pnlText)"))
                    .nvwaTextStyle(Nvwa.Typography.bodySmall, linesFillLineHeight: false)
                    .monospacedDigit()
                    .foregroundStyle(displayedProfitTone)
            }
            Spacer()
            // 展开后这一格让位给大图（设计 `197:2928` 里这枚缩略图是 hidden）。
            if !isChartExpanded && hasCompactChart {
                PawSparkline(values: model.portfolioSummary.historyUSD, tone: profitTone, height: 70.5)
                    .frame(width: 124)
                    .contentShape(Rectangle())
                    // 用 onTapGesture 而不是 Button：ScrollView 里的 Button 要先等
                    // 系统判定这一下是不是滚动，手感上就是「按下去半天才动」。
                    .onTapGesture {
                        withAnimation(PawMotion.expand) { isChartExpanded = true }
                    }
                    .accessibilityLabel("Total assets trend")
                    .accessibilityHint("Double-tap to expand")
                    .accessibilityAddTraits(.isButton)
            }
        }
        .frame(height: 76)
    }

    private var hasCompactChart: Bool {
        LedgerPortfolioChartPolicy.shouldShow(
            totalValueUSD: model.portfolioSummary.totalValueUSD,
            values: model.portfolioSummary.historyUSD
        )
    }

    private var hasExpandedChart: Bool {
        LedgerPortfolioChartPolicy.shouldShow(
            totalValueUSD: model.portfolioSummary.totalValueUSD,
            values: chartValues
        )
    }

    /// 设计 `197:2922`：区间在图上方（28），中间是 188 的图与坐标，
    /// 底下 24 高的把手负责收起，三段之间各 8。
    private var chartPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            chartRangeControl
            chartContent
            collapseChartHandle
        }
        .transition(.opacity)
    }

    /// 设计 `197:6779`：一排等宽 Section，选中是浅蓝药丸。
    private var chartRangeControl: some View {
        HStack(spacing: 4) {
            ForEach(PortfolioHistoryRange.allCases) { range in
                NvwaSection(
                    range.title,
                    isSelected: model.historyRange == range,
                    expandsHorizontally: true
                ) {
                    chartScrubIndex = nil
                    model.selectHistoryRange(range)
                }
            }
        }
        .frame(height: 28)
    }

    @ViewBuilder
    private var chartContent: some View {
        if chartValues.count >= 2 {
            VStack(alignment: .leading, spacing: 12) {
                PawPortfolioChart(
                    values: chartValues,
                    tone: chartTone,
                    peakLabel: MoneyFormat.usd,
                    scrubIndex: $chartScrubIndex,
                    height: 160
                )

                // 设计 `197:6793`：两端对齐的起止时刻。
                HStack(spacing: 4) {
                    Text(chartAxisLabel(model.chartSeries.first?.timestampMilliseconds))
                    Spacer(minLength: 4)
                    Text(chartAxisLabel(model.chartSeries.last?.timestampMilliseconds))
                }
                .nvwaTextStyle(Nvwa.Typography.caption2, linesFillLineHeight: false)
                .foregroundStyle(Nvwa.textSecondary)
                .monospacedDigit()
                .frame(height: 16)
            }
            // 扫描到的时刻画在图上方，用 overlay 而不是占一行：它出现和消失
            // 都不该把下面的坐标和把手推来推去。
            .overlay(alignment: .topLeading) {
                if let point = scrubbedPoint {
                    Text(chartStamp(point.timestampMilliseconds))
                        .nvwaTextStyle(Nvwa.Typography.caption2, linesFillLineHeight: false)
                        .foregroundStyle(Nvwa.textSecondary)
                        .monospacedDigit()
                }
            }
        } else {
            Text("There isn’t enough history to draw the trend yet.")
                .nvwaTextStyle(Nvwa.Typography.bodySmall, linesFillLineHeight: false)
                .foregroundStyle(Nvwa.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .frame(height: 188)
        }
    }

    /// 设计 `197:6797`：收起把手。收起态不画它——那时点迷你曲线就能展开，
    /// 多一个箭头是冗余。
    private var collapseChartHandle: some View {
        Image("IconArrowDownS")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: 24, height: 24)
            .rotationEffect(.degrees(180))
            .foregroundStyle(Nvwa.textSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: 24)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(PawMotion.expand) {
                    isChartExpanded = false
                    chartScrubIndex = nil
                }
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("Collapse total assets chart")
    }

    private var chartValues: [Double] { model.chartSeries.map(\.value) }

    private var chartTone: Color {
        guard let first = model.chartSeries.first?.value,
              let last = model.chartSeries.last?.value else { return Nvwa.textSecondary }
        if last - first > LedgerEntry.balanceTolerance { return Nvwa.marketBuy }
        if last - first < -LedgerEntry.balanceTolerance { return Nvwa.marketSell }
        return Nvwa.textSecondary
    }

    private var scrubbedPoint: PortfolioHistoryPoint? {
        guard let index = chartScrubIndex,
              model.chartSeries.indices.contains(index) else { return nil }
        return model.chartSeries[index]
    }

    /// 扫描时读出的是「相对区间起点的变化」。常驻的 PNL 是相对投入本金算的，
    /// 跟光标停在哪儿没关系，照搬过来会读成一个不随光标动的数。
    private var scrubbedChange: Double? {
        guard let value = scrubbedPoint?.value,
              let base = model.chartSeries.first?.value else { return nil }
        return value - base
    }

    private var pnlLabel: String {
        guard scrubbedPoint != nil else { return "PNL" }
        switch model.historyRange {
        case .day: return "vs. 24 hours ago"
        case .week: return "vs. 7 days ago"
        case .month: return "vs. 30 days ago"
        case .year: return "vs. 1 year ago"
        }
    }

    private var pnlText: String {
        guard let change = scrubbedChange else { return profitText }
        guard let base = model.chartSeries.first?.value, base > 0 else {
            return MoneyFormat.signedDecimal(change)
        }
        return "\(MoneyFormat.signedDecimal(change)) (\(MoneyFormat.percent(change / base * 100)))"
    }

    private var displayedProfitTone: Color {
        guard let change = scrubbedChange else { return profitTone }
        if change > LedgerEntry.balanceTolerance { return Nvwa.marketBuy }
        if change < -LedgerEntry.balanceTolerance { return Nvwa.marketSell }
        return Nvwa.textSecondary
    }

    private func chartAxisLabel(_ timestampMilliseconds: TimeInterval?) -> String {
        guard let timestampMilliseconds else { return "" }
        let date = Date(timeIntervalSince1970: timestampMilliseconds / 1_000)
        return model.historyRange == .day
            ? ledgerChartTimeFormatter.string(from: date)
            : ledgerChartDayFormatter.string(from: date)
    }

    private func chartStamp(_ timestampMilliseconds: TimeInterval) -> String {
        let date = Date(timeIntervalSince1970: timestampMilliseconds / 1_000)
        return model.historyRange == .year
            ? ledgerChartYearStampFormatter.string(from: date)
            : ledgerChartStampFormatter.string(from: date)
    }

    private var profitText: String {
        if model.portfolioSummary.totalValueUSD == 0 {
            return "0.00 (0.00%)"
        }
        guard let profit = model.portfolioSummary.profitUSD else { return "—" }
        let percent = model.portfolioSummary.profitPercent.map { " (\(MoneyFormat.percent($0)))" } ?? ""
        return "\(MoneyFormat.signedDecimal(profit))\(percent)"
    }

    private var profitTone: Color {
        guard let profit = model.portfolioSummary.profitUSD else { return Nvwa.textSecondary }
        if profit > LedgerEntry.balanceTolerance { return Nvwa.marketBuy }
        if profit < -LedgerEntry.balanceTolerance { return Nvwa.marketSell }
        return Nvwa.textSecondary
    }

    private var emptyState: some View {
        VStack(spacing: 24) {
            Image("IconCash")
                .renderingMode(.template).resizable().scaledToFit()
                .frame(width: 36, height: 36).foregroundStyle(Nvwa.ink)
                .frame(width: 72, height: 72).background(Nvwa.backgroundVessel, in: Circle())
            Text("Add your first currency to continue")
                .nvwaTextStyle(Nvwa.Typography.bodyMedium, linesFillLineHeight: false)
                .foregroundStyle(Nvwa.grayPrimary)
                .multilineTextAlignment(.center)
            NvwaButton("Add", size: .huge, expandsHorizontally: true) {
                if isSignedIn {
                    route = .add
                } else {
                    onSignIn()
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Nvwa.line, lineWidth: 1))
    }

    private var fiatSpotSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    action("Add", primary: true) { route = .add }
                    action("Trading") { route = .trading(preselected: nil) }
                    action("Earn") { route = .earn }
                    action("Pay") { showsPay = true }
                }
            }

            VStack(alignment: .leading, spacing: 36) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: LedgerSpotChipMetrics.spacing) {
                        ForEach(model.spotBalances, id: \.asset) { item in
                            spotAssetChip(item.asset)
                        }
                    }
                    .onPreferenceChange(LedgerSpotWidthPreferenceKey.self) {
                        spotItemWidths = $0
                    }
                }
                // 同上，兜底用。
                .scrollDisabled(spotReorderState.isReordering)

                if let item = selectedBalance {
                    VStack(alignment: .leading, spacing: 12) {
                        let locations = model.locationBalances(for: item.asset)
                        HStack(spacing: 10) {
                            ForEach(Array(locations.enumerated()), id: \.element.account) { index, location in
                                if index > 0 {
                                    Rectangle().fill(Nvwa.line).frame(width: 1, height: 10)
                                }
                                HStack(spacing: 4) {
                                    Image(accountIconName(location.account.identifier))
                                        .renderingMode(.template).resizable().frame(width: 16, height: 16)
                                        .accessibilityHidden(true)
                                    Text(LocalizedStringKey(location.account.identifier.capitalized))
                                }
                                .nvwaTextStyle(Nvwa.Typography.bodySmall, linesFillLineHeight: false)
                                // 单一账户没有“选中/未选中”的比较关系，统一用 secondary；
                                // 只有多个账户并列时，才用主文字色突出当前（首个）账户。
                                .foregroundStyle(
                                    LedgerAccountLabelTonePolicy.usesPrimaryTone(
                                        isSelected: index == 0,
                                        accountCount: locations.count
                                    )
                                        ? Nvwa.ink
                                        : Nvwa.textSecondary
                                )
                            }
                        }
                        // 法币/稳定币余额固定两位小数（设计 `154:12656`）。
                        // `amount()` 的 2...8 位是给 BTC 这种数量用的，
                        // balance 走它会把浮点残差整串打出来。
                        Text(MoneyFormat.decimal(item.quantity))
                            .nvwaTextStyle(Nvwa.Typography.titleSection, linesFillLineHeight: false)
                            .monospacedDigit()
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Nvwa.line, lineWidth: 1))
        }
    }

    private func spotAssetChip(_ asset: LedgerAsset) -> some View {
        let balances = model.spotBalances

        // 这一排就是 Nvwa 的 Currency Section（`2282:248`）：36 高的药丸、20pt 图标、
        // 选中铺 `BG/Vessel`。这里只注入国旗/币种图，几何和配色由组件说了算，
        // 不在业务页里重描一套。
        let content = NvwaSection(
            asset.code,
            style: .currency,
            isSelected: asset == selectedBalance?.asset,
            icon: {
                assetMark(asset)
                    .overlay(Circle().stroke(Nvwa.line, lineWidth: 0.5))
            },
            action: {
                guard spotReorderState.allowsSelection() else { return }
                selectedAsset = asset
            }
        )
        .background {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: LedgerSpotWidthPreferenceKey.self,
                    value: [asset: geometry.size.width]
                )
            }
        }
        .nvwaReorderable(
            item: asset,
            items: balances.map(\.asset),
            state: $spotReorderState,
            layout: .horizontal(
                itemExtents: balances.map { spotItemWidths[$0.asset] ?? 80 },
                spacing: LedgerSpotChipMetrics.spacing
            ),
            style: .chip,
            onTap: {
                selectedAsset = asset
            },
            onLift: preserveSpotSelection,
            onMove: { model.moveSpotAsset($0, to: $1) }
        )

        return content
            .accessibilityHint("Double-tap to select. Touch and hold, then drag to reorder.")
            .accessibilityAction(named: "Move left") {
                preserveSpotSelection()
                moveSpotAsset(asset, by: -1, in: balances.map(\.asset))
            }
            .accessibilityAction(named: "Move right") {
                preserveSpotSelection()
                moveSpotAsset(asset, by: 1, in: balances.map(\.asset))
            }
    }

    private func moveSpotAsset(_ asset: LedgerAsset, by delta: Int, in assets: [LedgerAsset]) {
        guard let move = spotReorderState.accessibilityMove(asset, by: delta, in: assets) else {
            return
        }
        model.moveSpotAsset(move.item, to: move.destinationIndex)
    }

    /// 任意一个列表拿起了项，就整页锁滚动。这是兜底的第二道——主力是组件在
    /// 长按成立时掐断这一次滚动；这里挡的是拿起之后新起的触摸。
    private var isReordering: Bool {
        spotReorderState.isReordering || overviewReorderState.isReordering
    }

    /// 第一次进入页面时选中态由“第一项”隐式提供。排序前把它固化下来，避免仅仅
    /// 把别的资产移到最前面，就连当前正在看的余额一起切走。
    private func preserveSpotSelection() {
        if selectedAsset == nil { selectedAsset = selectedBalance?.asset }
    }

    private var accountContent: some View {
        VStack(alignment: .leading, spacing: 32) {
            // 法币 / 稳定币还没有余额时，这一整组（动作 pill + 法币卡）换成设计
            // `154:9705` 的空态入口卡：不画空框，也不显示那排 pill——它们要么需要
            // 法币余额才能用，要么本来就是空态卡上那颗 Add。Trading / Earn 区块
            // 仍照常显示；标题只展示汇总，不再承担导航。
            if model.spotBalances.isEmpty {
                emptyState
            } else {
                fiatSpotSection
            }

            if !model.tradingBalances.isEmpty {
                portfolioSection(
                    title: "Trading",
                    summary: tradingSummary,
                    summaryTone: tradingSummaryTone
                ) {
                    VStack(spacing: 0) {
                        ForEach(model.tradingBalances, id: \.asset) { item in
                            tradingOverviewRow(item.asset, quantity: item.quantity)
                        }
                    }
                }
            }

            if !model.earnBalances.isEmpty {
                portfolioSection(
                    title: "Earn",
                    summary: model.totalEarnPaidInterestUSD.map(MoneyFormat.signedDecimal),
                    summarySuffix: " USD"
                ) {
                    VStack(spacing: 0) {
                        ForEach(model.earnBalances, id: \.product.id) { item in
                            earnOverviewRow(item.product, quantity: item.quantity)
                        }
                    }
                }
            }
        }
    }

    private var tradingSummary: String? {
        model.totalTradingProfitPercent.map(MoneyFormat.percent).map { value in
            let prefix = (model.totalTradingProfitUSD ?? 0) > 0 ? "+" : ""
            return prefix + value
        }
    }

    /// 设计 `154:12840` 画的是盈利态的绿。亏损要走 Market Sell、持平走 Gray Secondary
    /// （AGENTS.md 的涨跌配色规则），不能把绿钉死。
    private var tradingSummaryTone: Color {
        guard let profit = model.totalTradingProfitUSD else { return Nvwa.textSecondary }
        if profit > LedgerEntry.balanceTolerance { return Nvwa.marketBuy }
        if profit < -LedgerEntry.balanceTolerance { return Nvwa.marketSell }
        return Nvwa.textSecondary
    }

    private func portfolioSection<Content: View>(
        title: String,
        summary: String?,
        summarySuffix: String = "",
        summaryTone: Color = Nvwa.marketBuy,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 0) {
                Text(LocalizedStringKey(title))
                    .nvwaTextStyle(Nvwa.Typography.titleBody, linesFillLineHeight: false)
                Spacer()
                if let summary {
                    Text(summary + summarySuffix)
                        .nvwaTextStyle(Nvwa.Typography.bodyMediumSemibold, linesFillLineHeight: false)
                        .monospacedDigit()
                        .foregroundStyle(summaryTone)
                }
            }
            .foregroundStyle(Nvwa.ink)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    private func tradingOverviewRow(_ asset: LedgerAsset, quantity: Double) -> some View {
        let item = LedgerOverviewReorderItem.trading(asset)
        let ids = model.tradingBalances.map { LedgerOverviewReorderItem.trading($0.asset) }

        let content = HStack(spacing: 10) {
            PawAssetLogo(
                quoteSymbol: asset.marketQuoteSymbol ?? asset.code,
                assetType: ledgerAssetType(asset),
                name: asset.code,
                fallbackText: String(asset.code.prefix(1)),
                diameter: 32,
                fallbackFontSize: 12
            )
            VStack(alignment: .leading, spacing: 4) {
                Text(asset.code)
                    .nvwaTextStyle(Nvwa.Typography.bodyLargeSemibold, linesFillLineHeight: false)
                    .frame(height: Nvwa.Typography.bodyLargeSemibold.lineHeight)
                Text(amount(quantity))
                    .nvwaTextStyle(Nvwa.Typography.bodyMedium, linesFillLineHeight: false)
                    .frame(height: Nvwa.Typography.bodyMedium.lineHeight)
                    .foregroundStyle(Nvwa.textSecondary)
                    .monospacedDigit()
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 4) {
                Text(model.valueUSD(of: asset, quantity: quantity).map(MoneyFormat.usd) ?? "—")
                    .nvwaTextStyle(Nvwa.Typography.bodyLargeSemibold, linesFillLineHeight: false)
                    .frame(height: Nvwa.Typography.bodyLargeSemibold.lineHeight)
                Text(tradingProfitText(asset))
                    .nvwaTextStyle(Nvwa.Typography.bodyMedium, linesFillLineHeight: false)
                    .frame(height: Nvwa.Typography.bodyMedium.lineHeight)
                    .foregroundStyle(tradingProfitTone(asset))
            }
            .monospacedDigit()
        }
        .foregroundStyle(Nvwa.ink)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .nvwaReorderable(
            item: item,
            items: ids,
            state: $overviewReorderState,
            layout: .vertical(itemExtent: ledgerHoldingRowHeight),
            onTap: { detail = .trading(asset: asset, quantity: quantity) },
            onMove: moveOverviewItem
        )

        return content
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            detail = .trading(asset: asset, quantity: quantity)
        }
        .accessibilityHint("Double-tap to open. Touch and hold, then drag to reorder.")
        .accessibilityAction(named: "Move up") { moveOverviewItem(item, by: -1, in: ids) }
        .accessibilityAction(named: "Move down") { moveOverviewItem(item, by: 1, in: ids) }
    }

    private func earnOverviewRow(_ product: EarnProduct, quantity: Double) -> some View {
        let item = LedgerOverviewReorderItem.earn(product.id)
        let ids = model.earnBalances.map { LedgerOverviewReorderItem.earn($0.product.id) }

        let content = HStack(spacing: 10) {
            LedgerEarnProductMark(product: product, circleSize: 32, glyphSize: 16)
            VStack(alignment: .leading, spacing: 4) {
                Text(product.name)
                    .nvwaTextStyle(Nvwa.Typography.bodyLargeSemibold, linesFillLineHeight: false)
                    .frame(height: Nvwa.Typography.bodyLargeSemibold.lineHeight)
                    .lineLimit(1)
                Text("APY \(amount(model.effectiveRate(for: product)))%")
                    .nvwaTextStyle(Nvwa.Typography.bodyMedium, linesFillLineHeight: false)
                    .frame(height: Nvwa.Typography.bodyMedium.lineHeight)
                    .foregroundStyle(Nvwa.marketBuy)
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 4) {
                Text(model.earnValueUSD(for: product, quantity: quantity).map(MoneyFormat.usd) ?? "—")
                    .nvwaTextStyle(Nvwa.Typography.bodyLargeSemibold, linesFillLineHeight: false)
                    .frame(height: Nvwa.Typography.bodyLargeSemibold.lineHeight)
                Text(model.accruedInterestUSD(for: product).map(MoneyFormat.signedDecimal).map { $0 + " USD" } ?? "—")
                    .nvwaTextStyle(Nvwa.Typography.bodyMedium, linesFillLineHeight: false)
                    .frame(height: Nvwa.Typography.bodyMedium.lineHeight)
                    .foregroundStyle(Nvwa.marketBuy)
            }
            .monospacedDigit()
        }
        .foregroundStyle(Nvwa.ink)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .nvwaReorderable(
            item: item,
            items: ids,
            state: $overviewReorderState,
            layout: .vertical(itemExtent: ledgerHoldingRowHeight),
            onTap: { detail = .earn(product: product) },
            onMove: moveOverviewItem
        )

        return content
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            detail = .earn(product: product)
        }
        .accessibilityHint("Double-tap to open. Touch and hold, then drag to reorder.")
        .accessibilityAction(named: "Move up") { moveOverviewItem(item, by: -1, in: ids) }
        .accessibilityAction(named: "Move down") { moveOverviewItem(item, by: 1, in: ids) }
    }

    private func moveOverviewItem(
        _ item: LedgerOverviewReorderItem,
        by delta: Int,
        in items: [LedgerOverviewReorderItem]
    ) {
        guard let move = overviewReorderState.accessibilityMove(item, by: delta, in: items) else {
            return
        }
        moveOverviewItem(move.item, to: move.destinationIndex)
    }

    private func moveOverviewItem(_ item: LedgerOverviewReorderItem, to destination: Int) {
        switch item {
        case let .trading(asset): model.moveTradingAsset(asset, to: destination)
        case let .earn(productID): model.moveEarnProduct(productID, to: destination)
        }
    }

    private func tradingProfitText(_ asset: LedgerAsset) -> String {
        guard let profit = model.tradingProfitUSD(for: asset),
              let percent = model.tradingProfitPercent(for: asset) else { return "—" }
        return "\(MoneyFormat.signedDecimal(profit)) (\(MoneyFormat.percent(percent)))"
    }

    private func tradingProfitTone(_ asset: LedgerAsset) -> Color {
        guard let profit = model.tradingProfitUSD(for: asset) else { return Nvwa.textSecondary }
        if profit > LedgerEntry.balanceTolerance { return Nvwa.marketBuy }
        if profit < -LedgerEntry.balanceTolerance { return Nvwa.marketSell }
        return Nvwa.textSecondary
    }

    private func accountIconName(_ identifier: String) -> String {
        ledgerAccountIconName(identifier)
    }

    private func action(_ title: String, primary: Bool = false, action: @escaping () -> Void) -> some View {
        NvwaButton(LocalizedStringKey(title), kind: primary ? .primary : .outline, size: .small, action: action)
    }

    @ViewBuilder
    private func destination(_ route: LedgerRoute) -> some View {
        switch route {
        case .add: LedgerAddForm(model: model)
        case .transactions: LedgerTransactionsView(model: model)
        case let .trading(market): LedgerTradeForm(model: model, preselected: market)
        case .earn: LedgerEarnView(model: model)
        }
    }
}

private struct LedgerAddForm: View {
    @ObservedObject var model: LedgerPortfolioViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var asset: LedgerAsset?
    @State private var quantity = ""
    @State private var note = ""
    @State private var location = "exchange"
    @State private var showsAssetPicker = false
    @State private var isSaving = false
    @State private var didAttemptSave = false
    @State private var pendingDeposit: LedgerDepositDraft?

    var body: some View {
        VStack(spacing: 0) {
            NvwaNavigationBar(
                leading: .icon(Image("IconClose"), accessibilityLabel: "Close", action: { dismiss() }),
                title: "Add"
            )
            VStack(spacing: 16) {
                NvwaSelect(
                    label: "Currency",
                    isRequired: true,
                    value: asset?.code ?? "",
                    placeholder: "Ex. USD,CNY",
                    searchIcon: Image("IconSearch2"),
                    dropdownIcon: Image("IconArrowDropDownFill")
                ) { showsAssetPicker = true }

                NvwaInputField(
                    label: "Amounts",
                    isRequired: true,
                    placeholder: "0",
                    text: $quantity,
                    helpText: didAttemptSave && parsedQuantity == nil ? "Enter an amount greater than 0." : nil
                )
                    .keyboardType(.decimalPad)
                if asset != nil {
                    PawSingleSelectField(
                        label: "Account",
                        sheetTitle: "Account",
                        options: LedgerAccountOption.all,
                        selection: $location,
                        optionTitle: { $0.capitalized },
                        icon: { ledgerAccountGlyph($0) }
                    )
                }
                NvwaInputField(label: "Note", placeholder: "Ex. Salary", text: $note)
                Spacer()
            }
            .padding(16)

            NvwaButton("Save", size: .huge, expandsHorizontally: true, isLoading: isSaving) { save() }
                .disabled(isSaving)
                .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .background(Nvwa.backgroundMain)
        .sheet(isPresented: $showsAssetPicker) {
            LedgerAssetPicker(selection: Binding(
                get: { asset ?? LedgerAsset(code: "USD", kind: .fiat) },
                set: { asset = $0 }
            ))
        }
        .sheet(item: $pendingDeposit) { draft in
            LedgerDepositConfirmation(model: model, draft: draft) {
                pendingDeposit = nil
                dismiss()
            }
        }
    }

    private var parsedQuantity: Double? {
        guard let value = Double(quantity.replacingOccurrences(of: ",", with: "")), value > 0 else { return nil }
        return value
    }

    private func save() {
        didAttemptSave = true
        guard let asset else {
            showsAssetPicker = true
            return
        }
        guard let parsedQuantity else { return }
        pendingDeposit = LedgerDepositDraft(
            asset: asset,
            quantity: parsedQuantity,
            location: location,
            note: note
        )
    }
}

private struct LedgerDepositDraft: Identifiable {
    let id = UUID()
    let asset: LedgerAsset
    let quantity: Double
    let location: String
    let note: String
}

private struct LedgerDepositConfirmation: View {
    @ObservedObject var model: LedgerPortfolioViewModel
    let draft: LedgerDepositDraft
    let onSuccess: () -> Void
    @State private var isSaving = false
    @State private var didSucceed = false

    var body: some View {
        Group {
            if didSucceed {
                PawSuccessSheet()
            } else {
                PawSheet(title: "Confirmation", showsCloseButton: false) {
                    VStack(spacing: 16) {
                        detail("Currency", draft.asset.code)
                        detail("Amount", amount(draft.quantity))
                        detail("Note", draft.note.isEmpty ? LedgerFieldPlaceholder.notSet : draft.note)
                    }
                } footer: {
                    NvwaScrollButton("Slide to Confirm", isLoading: isSaving) {
                        confirm()
                    }
                }
            }
        }
        .onDisappear { if didSucceed { onSuccess() } }
    }

    /// 设计 `154:10535`：左边 label 是 B-M Regular，右边取值是 T-G Medium——
    /// 两列**不是**同一个字体样式，别图省事把 style 挂在 HStack 上。
    private func detail(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(LocalizedStringKey(label))
                .nvwaTextStyle(Nvwa.Typography.bodyMedium, linesFillLineHeight: false)
                .foregroundStyle(Nvwa.textSecondary)
            Spacer(minLength: 0)
            Text(LocalizedStringKey(value))
                .nvwaTextStyle(Nvwa.Typography.titleGroup, linesFillLineHeight: false)
                .foregroundStyle(Nvwa.ink)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
        }
    }

    private func confirm() {
        guard !isSaving else { return }
        isSaving = true
        Task { @MainActor in
            let saved = await model.deposit(
                asset: draft.asset,
                quantity: draft.quantity,
                location: draft.location,
                note: draft.note
            )
            isSaving = false
            if saved {
                didSucceed = true
            }
        }
    }
}

private struct LedgerPaySheet: View {
    @ObservedObject var model: LedgerPortfolioViewModel
    @State private var selection: LedgerSpendableBalance?
    @State private var quantity = ""
    @State private var note = ""
    @State private var fraction = 0.0
    @State private var showsBalancePicker = false
    @State private var isSaving = false
    @State private var didSucceed = false

    private var chosen: LedgerSpendableBalance? {
        if let selection, model.spendableBalances.contains(selection) { return selection }
        return model.spendableBalances.first
    }

    private var parsedQuantity: Double? {
        guard let value = Double(quantity.replacingOccurrences(of: ",", with: "")),
              value > 0,
              let chosen,
              value <= chosen.quantity + LedgerEntry.balanceTolerance else { return nil }
        return value
    }

    var body: some View {
        Group {
            if didSucceed {
                PawSuccessSheet()
            } else {
                PawSheet(title: "Pay", showsCloseButton: false) {
                    VStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Pay Amounts")
                                Spacer()
                                Button { showsBalancePicker = true } label: {
                                    HStack(spacing: 4) {
                                        Text("Balance").foregroundStyle(Nvwa.textSecondary)
                                        if let chosen {
                                            assetMark(chosen.asset, diameter: 12)
                                            Text(MoneyFormat.decimal(chosen.quantity))
                                                .foregroundStyle(Nvwa.ink)
                                                .monospacedDigit()
                                            Image("IconArrowDownSFill")
                                                .renderingMode(.template).resizable().frame(width: 12, height: 12)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                            .nvwaTextStyle(Nvwa.Typography.bodySmall, linesFillLineHeight: false)

                            NvwaInputField(
                                placeholder: "0",
                                text: $quantity,
                                unit: chosen?.asset.code
                            )
                            .keyboardType(.decimalPad)

                            NvwaSlider(value: $fraction)
                                .onChange(of: fraction) { _, value in
                                    guard let chosen else { return }
                                    quantity = amount(chosen.quantity * value)
                                }
                        }

                        NvwaInputField(label: "Note", placeholder: "Ex. Auto-Invest Account", text: $note)
                    }
                } footer: {
                    NvwaScrollButton("Slide to Confirm", isLoading: isSaving) { submit() }
                        .disabled(parsedQuantity == nil || isSaving)
                }
                .onAppear { if selection == nil { selection = model.spendableBalances.first } }
                .sheet(isPresented: $showsBalancePicker) {
                    LedgerBalancePicker(model: model, selection: $selection)
                }
            }
        }
    }

    private func submit() {
        guard let chosen, let parsedQuantity else { return }
        isSaving = true
        Task { @MainActor in
            let success = await model.pay(
                asset: chosen.asset,
                quantity: parsedQuantity,
                location: chosen.account.identifier,
                note: note
            )
            isSaving = false
            if success {
                didSucceed = true
            }
        }
    }
}

private struct LedgerBalancePicker: View {
    @ObservedObject var model: LedgerPortfolioViewModel
    @Binding var selection: LedgerSpendableBalance?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        PawSheet(title: "Balance", showsCloseButton: false) {
            LazyVStack(spacing: 0) {
                ForEach(model.spendableBalances) { item in
                    Button {
                        selection = item
                        dismiss()
                    } label: {
                        HStack(spacing: 8) {
                            assetMark(item.asset, diameter: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(MoneyFormat.decimal(item.quantity)) \(item.asset.code)")
                                    .font(Nvwa.font(16, weight: .semibold).monospacedDigit())
                                Text(LocalizedStringKey(item.account.identifier.capitalized))
                                    .nvwaTextStyle(Nvwa.Typography.bodySmall, linesFillLineHeight: false).foregroundStyle(Nvwa.textSecondary)
                            }
                            Spacer()
                            if selection?.id == item.id {
                                Image("IconCheck").renderingMode(.template).foregroundStyle(Nvwa.ink)
                            }
                        }
                        .foregroundStyle(Nvwa.ink)
                        .padding(.vertical, 16)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct LedgerAssetPicker: View {
    @Binding var selection: LedgerAsset
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var query = ""

    /// `LedgerAsset` 是 Hashable 不是 Identifiable，包一层给列表用。
    private struct Entry: Identifiable {
        let asset: LedgerAsset
        var id: String { "\(asset.kind.rawValue)-\(asset.code)" }
    }

    private var entries: [Entry] {
        let all = CurrencyCatalog.all
            .map { LedgerAsset(code: $0.code.rawValue, kind: .fiat) }
            .map(Entry.init)
        guard !query.isEmpty else { return all }
        return all.filter {
            $0.asset.code.localizedCaseInsensitiveContains(query)
                || assetDescription($0.asset, locale: locale).localizedCaseInsensitiveContains(query)
        }
    }

    private var favorites: [LedgerAsset] {
        StablecoinCatalog.favorites.map { LedgerAsset(code: $0.code, kind: .stablecoin) }
    }

    /// 不用 `PawSheet`：它把 content 裹在自己的 `ScrollView` 里，再套一层带索引条的
    /// 滚动列表会让内层拿不到高度——字母索引条会被顶到屏幕外、分组表头也不再吸顶。
    /// 所以这里和汇率页的 `CurrencyPickerView` 一样自己拼 header + `.pawSheetPresentation`。
    var body: some View {
        VStack(spacing: 0) {
            NvwaModalHeader("Add Currency")
                .pawSheetMeasuredPart()

            VStack(spacing: 16) {
                NvwaSearchInput(
                    placeholder: "Ex. USD,CNY",
                    text: $query,
                    searchIcon: Image("IconSearch2"),
                    clearIcon: Image("IconCloseCircleFill"),
                    onClear: { query = "" }
                )
                .autocorrectionDisabled()
                .submitLabel(.search)
                .pawSheetMeasuredPart()

                PawAlphabeticalList(
                    sections: PawAlphabeticalList.sections(
                        from: entries,
                        letter: { String($0.asset.code.prefix(1)) },
                        sortKey: { $0.asset.code }
                    ),
                    showsTopContentWhenSectionsEmpty: true,
                    topContent: { favoritesSection },
                    row: { row($0.asset) },
                    emptyState: { emptyState }
                )
            }
            .padding(16)
            .pawSheetHeightContribution(48)
        }
        .background(Nvwa.backgroundDialogue)
        .pawSheetPresentation()
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(16)
        .presentationBackground(Nvwa.backgroundDialogue)
    }

    private var favoritesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Favorites")
                .nvwaTextStyle(Nvwa.Typography.bodySmallSemibold, linesFillLineHeight: false)
                .foregroundStyle(Nvwa.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 28)

            ForEach(favorites, id: \.code) { asset in
                row(asset)
            }
        }
    }

    /// 设计 `154:10275`：整行 `py16`、gap 12；32pt 圆标带 0.5pt line 描边；
    /// 代码 B-L Semi Bold(16/24/0.08)，名称 B-S Regular(12/20/0.12) 走 secondary。
    private func row(_ asset: LedgerAsset) -> some View {
        Button {
            selection = asset
            dismiss()
        } label: {
            HStack(spacing: 12) {
                assetMark(asset, diameter: 32)
                    .overlay(Circle().strokeBorder(Nvwa.line, lineWidth: 0.5))

                VStack(alignment: .leading, spacing: 4) {
                    Text(asset.code)
                        .nvwaTextStyle(Nvwa.Typography.bodyLargeSemibold, linesFillLineHeight: false)
                        .foregroundStyle(Nvwa.grayPrimary)

                    Text(LocalizedStringKey(assetDescription(asset, locale: locale)))
                        .nvwaTextStyle(Nvwa.Typography.bodySmall, linesFillLineHeight: false)
                        .foregroundStyle(Nvwa.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(NvwaPressButtonStyle())
        .overlay(alignment: .bottom) { PawDivider() }
        .accessibilityLabel(Text("Add \(assetDescription(asset, locale: locale))"))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image("ArtNotFound")
                .resizable()
                .scaledToFit()
                .frame(width: 120, height: 120)

            Text("No currency matches “\(query)”.")
                .nvwaTextStyle(Nvwa.Typography.bodySmall)
                .foregroundStyle(Nvwa.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct LedgerEarnProductMark: View {
    let product: EarnProduct
    let circleSize: CGFloat
    let glyphSize: CGFloat

    var body: some View {
        Image(product.term == .structured ? "IconQuillPen" : "IconLeaf")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .foregroundStyle(Nvwa.colorOnBlue)
            .frame(width: glyphSize, height: glyphSize)
            .frame(width: circleSize, height: circleSize)
            .background(
                product.term == .structured ? Nvwa.sentimentNegative : Nvwa.sentimentPositive,
                in: Circle()
            )
            .accessibilityHidden(true)
    }
}

/// Earn 产品明细（设计 `158:16698`）。点理财卡片进来的落地页：顶部总收益、
/// 产品参数、分隔线、计息参数，底部「Subscribe / Redeem」两颗按钮。
private struct LedgerEarnDetailView: View {
    @ObservedObject var model: LedgerPortfolioViewModel
    let product: EarnProduct
    @Environment(\.dismiss) private var dismiss
    @State private var showsTransactions = false
    @State private var action: LedgerEarnAction?
    @State private var pendingRedemption: EarnProduct?

    private var holding: Double {
        model.projection.balance(in: .earn(productID: product.id), asset: product.asset)
    }

    private var totalProfit: Double { model.accruedInterest(for: product) }

    var body: some View {
        VStack(spacing: 0) {
            NvwaNavigationBar(
                leading: .icon(Image("IconClose"), accessibilityLabel: "Close", action: { dismiss() }),
                trailing: [
                    .icon(
                        Image("IconFileHistory"),
                        tone: .neutral,
                        accessibilityLabel: "Transactions",
                        action: { showsTransactions = true }
                    )
                ]
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    profitHeader

                    VStack(spacing: 12) {
                        nameRow
                        ledgerDetailRow("Assets", product.asset.code)
                        if product.term == .fixed {
                            ledgerDetailRow("Term", "Fixed")
                            if let maturity = product.maturesAt {
                                ledgerDetailRow("Maturity Date", maturityTimestamp(maturity))
                            }
                        } else if product.term == .flexible {
                            ledgerDetailRow("Interest Calculation", product.interestMode.title)
                            ledgerDetailRow("Term", "Flexible")
                        } else {
                            if let strike = product.strikePrice {
                                ledgerDetailRow("Strike Price", "\(amount(strike)) \(product.asset.code)")
                            }
                            if let knockOut = product.knockOutPrice {
                                ledgerDetailRow("Knock-Out Price", "\(amount(knockOut)) \(product.asset.code)")
                            }
                            if product.strikePrice == nil, product.knockOutPrice == nil,
                               let parameters = product.structuredParameters, !parameters.isEmpty {
                                ledgerDetailRow("Product Parameters", parameters)
                            }
                            if let maturity = product.maturesAt {
                                ledgerDetailRow("Maturity Date", maturityTimestamp(maturity))
                            }
                        }
                    }

                    Rectangle().fill(Nvwa.line).frame(height: 0.5)

                    VStack(spacing: 12) {
                        ledgerDetailRow("APY", "\(amount(model.effectiveRate(for: product)))%", tone: Nvwa.marketBuy)

                        if product.term == .fixed {
                            // 定期到期一次性付息，没有派息频率；这一行是「持有到期能拿多少」
                            // （设计 `158:17375`）。提前赎回拿不到，见下面按钮区的提示。
                            if let maturity = product.maturesAt {
                                ledgerDetailRow("Days", "\(max(0, Calendar.current.dateComponents([.day], from: product.startsAt, to: maturity).day ?? 0))D")
                            }
                            ledgerDetailRow("Total Profits After Maturity", projectedProfitText, tone: Nvwa.marketBuy)
                        } else {
                            ledgerDetailRow("Payout Frequency", payoutTitle(product.payoutFrequency))
                            ledgerDetailRow(
                                "\(payoutCadenceTitle(product.payoutFrequency)) Profits",
                                projectedProfitText,
                                tone: Nvwa.marketBuy
                            )
                        }

                        ledgerDetailRow("Total Investments", "\(amount(holding)) \(product.asset.code)")
                        if product.term != .fixed, let next = model.nextPayoutDate(for: product) {
                            ledgerDetailRow("Next Time Payout", nextPayoutTimestamp(next))
                        }
                    }
                }
                .padding(16)
            }

            // v2.1.1 `212:25485` 把主按钮文案改为 Subscribe；
            // 而 `158:17375`（定期）和 `158:16698`（结构化）只有一颗 Redeem——
            // 这两类不能加仓，注释写得很明确。Redeem 单独出现时仍是 Secondary。
            VStack(spacing: 15) {
                if product.allowsAdditionalSubscription {
                    NvwaButton("Subscribe", size: .huge, expandsHorizontally: true) {
                        action = LedgerEarnAction(product: product, redeems: false)
                    }
                }
                NvwaButton("Redeem", kind: .secondary, size: .huge, expandsHorizontally: true) {
                    if product.redeemsFullAmountOnly {
                        pendingRedemption = product
                    } else {
                        action = LedgerEarnAction(product: product, redeems: true)
                    }
                }
                .disabled(holding <= LedgerEntry.balanceTolerance)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Nvwa.backgroundMain)
        // Transactions is a full-screen destination with its own navigation
        // bar, not a dialog. Keeping it on a raw system sheet bypassed the
        // shared adaptive-dialog policy and opened at an arbitrary detent.
        .fullScreenCover(isPresented: $showsTransactions) { LedgerTransactionsView(model: model) }
        .sheet(item: $action) {
            LedgerEarnSubscriptionView(model: model, product: $0.product, startsRedeeming: $0.redeems)
        }
        .sheet(item: $pendingRedemption) { product in
            LedgerRedeemConfirmationSheet(model: model, product: product, quantity: holding)
        }
    }

    /// 设计 `158:16705`：标签是 B-L Regular(16/24/-0.08)，取值 26/32/-0.39 走涨跌色。
    private var profitHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Total Profits")
                .nvwaTextStyle(Nvwa.Typography.bodyLarge, linesFillLineHeight: false)
                .foregroundStyle(Nvwa.textSecondary)
            Text("\(MoneyFormat.signedDecimal(totalProfit)) \(product.asset.code)")
                .nvwaTextStyle(Nvwa.Typography.titleSection, linesFillLineHeight: false)
                .monospacedDigit()
                .foregroundStyle(totalProfit > LedgerEntry.balanceTolerance ? Nvwa.marketBuy : Nvwa.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Name 行右边是「20pt 圆底 + 10pt 字形 + 产品名」（设计 `158:17231`）。
    private var nameRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Name").foregroundStyle(Nvwa.textSecondary)
            Spacer(minLength: 12)
            HStack(spacing: 4) {
                LedgerEarnProductMark(product: product, circleSize: 20, glyphSize: 10)
                Text(product.name)
                    .foregroundStyle(Nvwa.ink)
                    .multilineTextAlignment(.trailing)
            }
        }
        .nvwaTextStyle(Nvwa.Typography.bodyMedium, linesFillLineHeight: false)
    }

    private var projectedProfitText: String {
        guard holding > LedgerEntry.balanceTolerance,
              let projected = EarnInterestCalculator.projectedPayout(
                  product: product,
                  principal: holding,
                  asOf: Date()
              ) else { return "--" }
        return "\(MoneyFormat.signedDecimal(projected)) \(product.asset.code)"
    }
}

/// Trading 资产明细（设计 `158:18023`）。顶部总收益、一张行情卡、持仓字段，
/// 底部一颗「Trading」按钮。
private struct LedgerTradingDetailView: View {
    @ObservedObject var model: LedgerPortfolioViewModel
    let asset: LedgerAsset
    let quantity: Double
    let onTrade: (AssetSearchResult) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showsTransactions = false

    private var quote: MarketQuote? {
        model.quotes[asset.marketQuoteSymbol ?? asset.code]
    }

    private var profit: Double? { model.tradingProfitUSD(for: asset) }

    private var profitTone: Color {
        guard let profit else { return Nvwa.textSecondary }
        if profit > LedgerEntry.balanceTolerance { return Nvwa.marketBuy }
        if profit < -LedgerEntry.balanceTolerance { return Nvwa.marketSell }
        return Nvwa.textSecondary
    }

    var body: some View {
        VStack(spacing: 0) {
            NvwaNavigationBar(
                leading: .icon(Image("IconClose"), accessibilityLabel: "Close", action: { dismiss() }),
                trailing: [
                    .icon(
                        Image("IconFileHistory"),
                        tone: .neutral,
                        accessibilityLabel: "Transactions",
                        action: { showsTransactions = true }
                    )
                ]
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Total Profits")
                            .nvwaTextStyle(Nvwa.Typography.bodyLarge, linesFillLineHeight: false)
                            .foregroundStyle(Nvwa.textSecondary)
                        Text(profit.map { MoneyFormat.signedDecimal($0) + " USD" } ?? "—")
                            .nvwaTextStyle(Nvwa.Typography.titleSection, linesFillLineHeight: false)
                            .monospacedDigit()
                            .foregroundStyle(profitTone)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if let quote { priceCard(quote) }

                    VStack(spacing: 12) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Name").foregroundStyle(Nvwa.textSecondary)
                            Spacer(minLength: 12)
                            HStack(spacing: 4) {
                                PawAssetLogo(
                                    quoteSymbol: asset.marketQuoteSymbol ?? asset.code,
                                    assetType: ledgerAssetType(asset),
                                    name: asset.code,
                                    fallbackText: String(asset.code.prefix(1)),
                                    diameter: 20,
                                    fallbackFontSize: 9
                                )
                                Text(asset.code).foregroundStyle(Nvwa.ink)
                            }
                        }
                        .nvwaTextStyle(Nvwa.Typography.bodyMedium, linesFillLineHeight: false)
                    }

                    VStack(spacing: 12) {
                        ledgerDetailRow("Amounts", amount(quantity))
                        ledgerDetailRow(
                            "Total Values",
                            model.valueUSD(of: asset, quantity: quantity).map(MoneyFormat.usd) ?? "—"
                        )
                        ledgerDetailRow("Note", latestNote ?? LedgerFieldPlaceholder.notSet)
                    }
                }
                .padding(16)
            }

            NvwaButton("Trading", size: .huge, expandsHorizontally: true) {
                dismiss()
                onTrade(searchResult)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Nvwa.backgroundMain)
        .fullScreenCover(isPresented: $showsTransactions) { LedgerTransactionsView(model: model) }
    }

    /// 行情卡（设计 `158:18107`）：`bg/card` 底、圆角 15、内距 12、内部 gap 16。
    private func priceCard(_ quote: MarketQuote) -> some View {
        let series = quote.series.map(\.price)
        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("1 \(asset.code) = \(amount(quote.price)) \(quote.currency)")
                        .nvwaTextStyle(Nvwa.Typography.bodyLargeSemibold, linesFillLineHeight: false)
                        .monospacedDigit()
                    Spacer(minLength: 8)
                    Text(MoneyFormat.percent(quote.changePercent))
                        .nvwaTextStyle(Nvwa.Typography.bodyMedium, linesFillLineHeight: false)
                        .monospacedDigit()
                        .foregroundStyle(quote.changePercent >= 0 ? Nvwa.marketBuy : Nvwa.marketSell)
                }
                Text("Update \(quoteUpdateFormatter.string(from: Date(timeIntervalSince1970: quote.fetchedAtMilliseconds / 1000)))")
                    .nvwaTextStyle(Nvwa.Typography.bodySmall, linesFillLineHeight: false)
                    .foregroundStyle(Nvwa.textSecondary)
            }

            HStack(spacing: 10) {
                PawSparkline(
                    values: series,
                    tone: quote.changePercent >= 0 ? Nvwa.marketBuy : Nvwa.marketSell,
                    padLow: 0,
                    padHigh: 0,
                    height: 100
                )
                .frame(maxWidth: .infinity)

                // 设计 `158:18120`：右侧 24pt 宽的三档刻度，10/16 C-2 Regular。
                VStack(alignment: .trailing) {
                    ForEach(axisLabels(series), id: \.self) { label in
                        Text(label)
                            .nvwaTextStyle(Nvwa.Typography.caption2, linesFillLineHeight: false)
                            .foregroundStyle(Nvwa.textSecondary)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        if label != axisLabels(series).last { Spacer(minLength: 0) }
                    }
                }
                .frame(width: 24, height: 100, alignment: .trailing)
            }

            HStack {
                Text(firstPointLabel(quote))
                Spacer(minLength: 8)
                Text("Today")
            }
            .nvwaTextStyle(Nvwa.Typography.caption2, linesFillLineHeight: false)
            .foregroundStyle(Nvwa.textSecondary)
            .padding(.top, 12)
            .overlay(alignment: .top) { Rectangle().fill(Nvwa.line).frame(height: 0.5) }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Nvwa.backgroundCard, in: RoundedRectangle(cornerRadius: 15))
    }

    /// 设计 `158:18120` 给刻度只留了 24pt 宽，画的是三位数的例子。
    /// BTC 这种五位数价格直接写会换行，所以上万的压成 `81.8K`。
    private func axisLabels(_ series: [Double]) -> [String] {
        guard let low = series.min(), let high = series.max(), high > low else { return [] }
        return [high, (high + low) / 2, low].map(Self.axisLabel)
    }

    private static func axisLabel(_ value: Double) -> String {
        let magnitude = abs(value)
        if magnitude >= 1_000_000 {
            return (value / 1_000_000).formatted(.number.precision(.fractionLength(1))) + "M"
        }
        if magnitude >= 10_000 {
            return (value / 1_000).formatted(.number.precision(.fractionLength(1))) + "K"
        }
        return value.formatted(.number.precision(.fractionLength(0...2)))
    }

    private func firstPointLabel(_ quote: MarketQuote) -> String {
        guard let first = quote.series.first else { return "" }
        return quoteAxisFormatter.string(from: Date(timeIntervalSince1970: first.timestampMilliseconds / 1000))
    }

    /// 把持仓里的标的还原成交易表单认识的搜索结果，让表单直接预填。
    /// 账本只存代码，不存资产全名，所以名字尽量从内置清单里找；找不到就只显示代码。
    private var searchResult: AssetSearchResult {
        let quoteSymbol = asset.marketQuoteSymbol ?? asset.code
        if let known = AssetSearchResult.offlineFallbacks.first(where: { $0.quoteSymbol == quoteSymbol }) {
            return known
        }
        return AssetSearchResult(
            symbol: asset.code,
            quoteSymbol: quoteSymbol,
            name: asset.code,
            assetType: ledgerAssetType(asset),
            exchange: ""
        )
    }

    private var latestNote: String? {
        model.entries
            .filter { entry in
                [.buy, .sell].contains(entry.kind)
                    && entry.postings.contains { $0.account == .trading && $0.asset == asset }
            }
            .max { $0.occurredAt < $1.occurredAt }?
            .note
    }
}

private let quoteUpdateFormatter = ledgerDateFormatter("HH:mm MMM d")
private let quoteAxisFormatter = ledgerDateFormatter("MMdd")

/// 总览上「点一行进明细」的两个落地页。
private enum LedgerDetailTarget: Identifiable {
    case trading(asset: LedgerAsset, quantity: Double)
    case earn(product: EarnProduct)

    var id: String {
        switch self {
        case let .trading(asset, _): "trading-\(asset.kind.rawValue)-\(asset.code)"
        case let .earn(product): "earn-\(product.id)"
        }
    }
}

/// 赎回确认（设计 `158:17968`）：标题 + 26/32 的金额 + 一段说明 + 滑动确认。
private struct LedgerRedeemConfirmationSheet: View {
    @ObservedObject var model: LedgerPortfolioViewModel
    let product: EarnProduct
    let quantity: Double
    @State private var isSaving = false
    @State private var didSucceed = false

    var body: some View {
        Group {
            if didSucceed {
                PawSuccessSheet()
            } else {
                PawSheet(title: "Redeem Confirmation", showsCloseButton: false) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(amount(quantity)) \(product.asset.code)")
                            .nvwaTextStyle(Nvwa.Typography.titleSection, linesFillLineHeight: false)
                            .monospacedDigit()
                            .foregroundStyle(Nvwa.ink)

                        redemptionNotice
                            .nvwaTextStyle(Nvwa.Typography.bodyMedium, linesFillLineHeight: false)
                            .foregroundStyle(Nvwa.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } footer: {
                    NvwaScrollButton("Slide to Confirm", isLoading: isSaving) { confirm() }
                        .disabled(quantity <= LedgerEntry.balanceTolerance || isSaving)
                }
            }
        }
    }

    /// 资金去向与定期提前赎回规则都属于金融语义，写成四条完整句子，避免把英文账户名
    /// 作为插值塞进中文句子后出现半中半英。
    @ViewBuilder
    private var redemptionNotice: some View {
        if product.asset.kind == .cryptocurrency {
            if product.forfeitsInterestOnEarlyRedemption {
                Text("Once redeemed, all assets will be returned to your Trading account. Redeeming before maturity forfeits the interest for this term.")
            } else {
                Text("Once redeemed, all assets will be returned to your Trading account. Accrued interest will remain unaffected.")
            }
        } else if product.forfeitsInterestOnEarlyRedemption {
            Text("Once redeemed, all assets will be returned to your Exchange account. Redeeming before maturity forfeits the interest for this term.")
        } else {
            Text("Once redeemed, all assets will be returned to your Exchange account. Accrued interest will remain unaffected.")
        }
    }

    private func confirm() {
        guard !isSaving else { return }
        isSaving = true
        Task { @MainActor in
            let success = await model.redeem(product: product, quantity: quantity)
            isSaving = false
            if success {
                didSucceed = true
            }
        }
    }
}

/// 下架确认弹层（设计 `155:16379`）。这个弹层**没有标题栏**，抓手下面直接是内容，
/// 所以没走 `PawSheet`（它固定有一行 50pt 的标题）。
private struct LedgerDelistWarningSheet: View {
    @ObservedObject var model: LedgerPortfolioViewModel
    let product: EarnProduct
    @State private var isSaving = false
    @State private var didSucceed = false

    var body: some View {
        if didSucceed {
            PawSuccessSheet()
        } else {
            VStack(spacing: 0) {
                Capsule()
                    .fill(Nvwa.ink10)
                    .frame(width: 40, height: 4)
                    .padding(.vertical, 6)
                    .pawSheetMeasuredPart()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Image("ArtWarning")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 48, height: 48)
                            .frame(maxWidth: .infinity)
                            .accessibilityHidden(true)

                        Text("Warning")
                            .nvwaTextStyle(Nvwa.Typography.titleBody, linesFillLineHeight: false)
                            .foregroundStyle(Nvwa.ink)
                            .frame(maxWidth: .infinity)

                        Text("Once delisted, all assets will be returned to your account. Accrued interest will remain unaffected.")
                            .nvwaTextStyle(Nvwa.Typography.bodyMedium, linesFillLineHeight: false)
                            .foregroundStyle(Nvwa.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(16)
                    .pawSheetMeasuredPart()
                }
                .scrollBounceBehavior(.basedOnSize)

                // 设计 `155:16388` 这里是 px15，不是别处的 16。
                NvwaScrollButton("Slide to Confirm", isLoading: isSaving) { confirm() }
                    .padding(.horizontal, 15)
                    .padding(.vertical, 12)
                    .pawSheetMeasuredPart()
            }
            .background(Nvwa.backgroundDialogue)
            .pawSheetPresentation()
            .presentationDragIndicator(.hidden)
            .presentationCornerRadius(16)
            .presentationBackground(Nvwa.backgroundDialogue)
            .accessibilityLabel("Delist \(product.name)")
        }
    }

    private func confirm() {
        guard !isSaving else { return }
        isSaving = true
        Task { @MainActor in
            let success = await model.delist(product: product)
            isSaving = false
            if success {
                didSucceed = true
            }
        }
    }
}

/// 理财的资产选择（设计 `173:21473`）：样式复用 Add Currency 那个弹层——
/// 顶部搜索 + 首字母分组 + 末尾 End——但选项是**所有法币 + 稳定币 + 数字货币**，
/// 不再只有写死的几个稳定币。
///
/// **股票和 ETF 不收进来**：设计 `173:21473` 的注释写的是「数字货币和股票前 100 名
/// 以及所有法币」，但用户 2026-09-05 明确决定暂不放开股票。股票 / ETF 继续被
/// `LedgerAsset.canEnterEarn` 拒绝（`LEDGER_MODEL.md` 的资金规则 +
/// `testStocksCannotEnterEarn`）。这是**已确认的注释覆盖**，不是待办。
private struct LedgerEarnAssetPicker: View {
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var query = ""

    struct Option: Identifiable, Hashable {
        let code: String
        let name: String
        let kind: LedgerAsset.Kind
        var id: String { code }
    }

    static let all: [Option] = {
        // 数字货币走 `AssetLogoCatalog.crypto` 的市值前 100（logo 随 App 打包，
        // 不用发网络请求）。USDT / USDC 在那份清单里也算 crypto，但领域层把它们
        // 当稳定币——申购账户不一样，这里按领域层的分类走。
        let digital = AssetLogoCatalog.crypto.map { entry -> Option in
            // 稳定币的全名以 `StablecoinCatalog` 为准（Tether USD / Circle USD），
            // 和 Add Currency 那张表一致；crypto 清单里写的是 Tether / USDC。
            if StablecoinCatalog.isKnown(entry.symbol) {
                let stable = StablecoinCatalog.info(for: entry.symbol)
                return Option(
                    code: entry.symbol,
                    name: stable?.name ?? entry.name,
                    kind: .stablecoin
                )
            }
            return Option(code: entry.symbol, name: entry.name, kind: .cryptocurrency)
        }
        let fiat = CurrencyCatalog.all.map {
            Option(code: $0.code.rawValue, name: $0.name, kind: .fiat)
        }
        // 设计注释还要求收录「股票前 100 名」，用户 2026-09-05 决定暂不放开。
        // 这里统一按 `canEnterEarn` 过滤兜底，将来要放开是改资金规则而不是改这里。
        var seen = Set<String>()
        return (digital + fiat).filter { option in
            guard LedgerAsset(code: option.code, kind: option.kind).canEnterEarn else { return false }
            return seen.insert(option.code).inserted
        }
    }()

    static func kind(for code: String) -> LedgerAsset.Kind {
        all.first { $0.code == code }?.kind ?? .fiat
    }

    private var matches: [Option] {
        guard !query.isEmpty else { return Self.all }
        return Self.all.filter {
            $0.code.localizedCaseInsensitiveContains(query)
                || localizedName($0).localizedCaseInsensitiveContains(query)
        }
    }

    private func localizedName(_ option: Option) -> String {
        guard option.kind == .fiat,
              let info = CurrencyCatalog.info(for: CurrencyCode(option.code)) else {
            return option.name
        }
        return info.localizedName(locale: locale)
    }

    var body: some View {
        VStack(spacing: 0) {
            NvwaModalHeader("Select Assets")
                .pawSheetMeasuredPart()

            VStack(spacing: 16) {
                NvwaSearchInput(
                    placeholder: "Search",
                    text: $query,
                    searchIcon: Image("IconSearch2"),
                    clearIcon: Image("IconCloseCircleFill"),
                    onClear: { query = "" }
                )
                .autocorrectionDisabled()
                .submitLabel(.search)
                .pawSheetMeasuredPart()

                PawAlphabeticalList(
                    sections: PawAlphabeticalList.sections(
                        from: matches,
                        letter: { String($0.code.prefix(1)) },
                        sortKey: { $0.code }
                    ),
                    // 常用的两个稳定币置顶，和 Add Currency 用同一套写法。
                    // 搜索时不再置顶——那时用户是在找具体某个。
                    showsTopContentWhenSectionsEmpty: false,
                    topContent: { favoritesSection },
                    row: { row($0) },
                    emptyState: { emptyState }
                )
            }
            .padding(16)
            .pawSheetHeightContribution(48)
        }
        .background(Nvwa.backgroundDialogue)
        .pawSheetPresentation()
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(16)
        .presentationBackground(Nvwa.backgroundDialogue)
    }

    private var favorites: [Option] {
        StablecoinCatalog.favorites.compactMap { info in
            Self.all.first { $0.code == info.code }
        }
    }

    @ViewBuilder
    private var favoritesSection: some View {
        if query.isEmpty, !favorites.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("Favorites")
                    .nvwaTextStyle(Nvwa.Typography.bodySmallSemibold, linesFillLineHeight: false)
                    .foregroundStyle(Nvwa.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 28)

                ForEach(favorites) { row($0) }
            }
        }
    }

    private func row(_ option: Option) -> some View {
        Button {
            selection = option.code
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Group {
                    if option.kind == .fiat {
                        assetMark(LedgerAsset(code: option.code, kind: option.kind), diameter: 32)
                    } else {
                        PawAssetLogo(
                            quoteSymbol: option.code,
                            assetType: option.kind == .stablecoin ? .stable : .cryptocurrency,
                            name: option.name,
                            fallbackText: String(option.code.prefix(1)),
                            diameter: 32,
                            fallbackFontSize: 13
                        )
                    }
                }
                .overlay(Circle().strokeBorder(Nvwa.line, lineWidth: 0.5))

                VStack(alignment: .leading, spacing: 4) {
                    Text(option.code)
                        .font(Nvwa.bodyLarge)
                        .tracking(0.08)
                        .foregroundStyle(Nvwa.grayPrimary)
                    Text(localizedName(option))
                        .font(Nvwa.bodySmall)
                        .tracking(0.12)
                        .foregroundStyle(Nvwa.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
                // 这里不画选中勾：设计 `173:21473` 的行里没有，而且行尾正好被
                // 右侧的 A–Z 索引条盖住，勾和字母会叠在一起。当前选中的资产
                // 在表单字段上已经显示了。
            }
            .padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(NvwaPressButtonStyle())
        .overlay(alignment: .bottom) { PawDivider() }
        .accessibilityLabel(localizedName(option))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image("ArtNotFound")
                .resizable().scaledToFit()
                .frame(width: 120, height: 120)
            Text("No asset matches \u{201C}\(query)\u{201D}.")
                .font(Nvwa.bodySmall)
                .tracking(0.12)
                .foregroundStyle(Nvwa.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private enum LedgerTransactionFilter: String, CaseIterable, Hashable {
    case all = "All"
    case earn = "Earn"
    case trading = "Buy Assets"
    case pay = "Pay"
}

private struct LedgerTransactionsView: View {
    @ObservedObject var model: LedgerPortfolioViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var filter = LedgerTransactionFilter.all
    @State private var pendingReversal: LedgerEntry?
    @State private var showsSuccess = false

    private var filteredEntries: [LedgerEntry] {
        model.entries.filter { entry in
            switch filter {
            case .all: true
            case .earn: [.earnSubscribe, .earnRedeem, .interest].contains(entry.kind)
            case .trading: [.buy, .sell].contains(entry.kind)
            case .pay: entry.kind == .expense
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            NvwaNavigationBar(
                leading: .icon(Image("IconClose"), accessibilityLabel: "Close", action: { dismiss() }),
                title: "Transactions"
            )
            if model.entries.isEmpty {
                VStack(spacing: 8) {
                    Image("ArtNoRecords")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 120, height: 120)
                    Text("No Records")
                        .nvwaTextStyle(Nvwa.Typography.bodySmall, linesFillLineHeight: false)
                        .foregroundStyle(Nvwa.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 12)
            } else {
                HStack(spacing: 10) {
                    ForEach(LedgerTransactionFilter.allCases, id: \.self) { option in
                        NvwaSection(option.rawValue, isSelected: filter == option) {
                            filter = option
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                ScrollView {
                    LazyVStack(spacing: 0) {
                        if filteredEntries.isEmpty {
                            VStack(spacing: 8) {
                                Image("ArtNoRecords")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 120, height: 120)
                                Text("No Records")
                                    .nvwaTextStyle(Nvwa.Typography.bodySmall, linesFillLineHeight: false)
                                    .foregroundStyle(Nvwa.textSecondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 12)
                        } else {
                            ForEach(filteredEntries) { entry in
                                transaction(entry)
                                    .accessibilityElement(children: .combine)
                                    .contextMenu {
                                        if model.canReverse(entry) {
                                            Button("Reverse transaction", role: .destructive) {
                                                pendingReversal = entry
                                            }
                                        }
                                    }
                                    .accessibilityAction(named: "Reverse transaction") {
                                        if model.canReverse(entry) { pendingReversal = entry }
                                    }
                                // 设计 `158:19103` 的分隔线宽 342，两侧各留 16，不是通栏。
                                Rectangle().fill(Nvwa.line).frame(height: 0.5)
                                    .padding(.horizontal, 16)
                            }
                            Text("End")
                                .nvwaTextStyle(Nvwa.Typography.bodySmall, linesFillLineHeight: false)
                                .foregroundStyle(Nvwa.textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                    }
                }
            }
        }
        .background(Nvwa.backgroundMain)
        .alert("Reverse this transaction?", isPresented: Binding(
            get: { pendingReversal != nil },
            set: { if !$0 { pendingReversal = nil } }
        )) {
            Button("Reverse transaction", role: .destructive) {
                guard let entry = pendingReversal else { return }
                pendingReversal = nil
                Task { @MainActor in
                    if await model.reverse(entry) { showsSuccess = true }
                }
            }
            Button("Cancel", role: .cancel) { pendingReversal = nil }
        } message: {
            Text("The original record stays in history and a balancing reversal is added.")
        }
        .sheet(isPresented: $showsSuccess) {
            PawSuccessSheet()
        }
    }

    private func transaction(_ entry: LedgerEntry) -> some View {
        VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                localizedTitle(for: entry)
                    .nvwaTextStyle(Nvwa.Typography.bodyMediumSemibold, linesFillLineHeight: false)
                Spacer()
                if let posting = entry.primaryUserPosting {
                    Text("\(posting.quantity >= 0 ? "+" : "")\(amount(posting.quantity)) \(posting.asset.code)")
                        .nvwaTextStyle(Nvwa.Typography.bodyMediumSemibold, linesFillLineHeight: false).monospacedDigit()
                        .foregroundStyle(posting.quantity > 0 ? Nvwa.marketBuy : Nvwa.ink)
                }
            }

            if [.earnSubscribe, .earnRedeem, .interest].contains(entry.kind),
               let product = model.snapshot.earnProducts.first(where: { $0.id == entry.earnProductID }) {
                detail("APY", "\(amount(product.annualRate(at: entry.occurredAt)))%", tone: Nvwa.marketBuy)
                if product.term == .flexible {
                    detail("Interest Calculation", product.interestMode.title)
                }
            }
            detail("Time", ledgerTimestamp(entry.occurredAt))
            transactionSpecificDetails(entry)
        }
        .padding(16)
    }

    @ViewBuilder
    private func transactionSpecificDetails(_ entry: LedgerEntry) -> some View {
        switch entry.kind {
        case .buy, .sell:
            if let trade = entry.trade,
               let assetPosting = entry.postings.first(where: { $0.account == .trading }) {
                detail(entry.kind == .buy ? "Investment" : "Sell Value", "\(amount(abs(entry.primaryUserPosting?.quantity ?? 0))) \(trade.settlementAsset.code)")
                detail(entry.kind == .buy ? "Buy Amounts" : "Sell Amounts", "\(amount(abs(assetPosting.quantity))) \(assetPosting.asset.code)")
                detail(entry.kind == .buy ? "Cost Price" : "Sell Price", "\(amount(trade.unitPrice)) \(trade.settlementAsset.code)")
                detail("From to", entry.kind == .buy ? "Fiat→Trading" : "Trading→Fiat")
                if let note = entry.note { detail("Note", note) }
                detail("Fees", "-\(amount(trade.fee)) \(trade.settlementAsset.code)", tone: trade.fee > 0 ? Nvwa.marketSell : Nvwa.textSecondary)
            }
        case .expense:
            if let source = entry.postings.first(where: { $0.account.isUserControlled && $0.quantity < 0 }) {
                detail("From Account", accountName(source.account.kind))
            }
            if let note = entry.note { detail("Note", note) }
        case .earnSubscribe, .earnRedeem, .interest:
            detail("From to", accountRoute(entry))
            detail("Type", earnType(entry.kind))
        case .deposit:
            if let destination = entry.postings.first(where: {
                $0.account.isUserControlled && $0.quantity > 0
            }) {
                detail("To Account", destination.account.identifier.capitalized)
            }
            if let note = entry.note { detail("Note", note) }
        case .openingBalance:
            if let posting = entry.primaryUserPosting {
                detail("To Account", posting.account.identifier.capitalized)
            }
            if let note = entry.note { detail("Note", note) }
        case .reversal:
            if let targetID = entry.reversesEntryID,
               let target = model.snapshot.entries.first(where: { $0.id == targetID }) {
                detail("Reverses", title(for: target))
            }
            if let note = entry.note { detail("Note", note) }
        }
    }

    /// 设计 `158:19094`：流水明细行是 B-M Regular(14/22/0.14)，不是 12pt；
    /// 而且 tone 只染右边的取值，label 恒定 text/secondary——`Fees` 那行左边不是红的。
    private func detail(_ label: String, _ value: String, tone: Color = Nvwa.textSecondary) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(LocalizedStringKey(label)).foregroundStyle(Nvwa.textSecondary)
            Spacer(minLength: 12)
            Text(LocalizedStringKey(value))
                .foregroundStyle(tone)
                .multilineTextAlignment(.trailing)
        }
        .nvwaTextStyle(Nvwa.Typography.bodyMedium, linesFillLineHeight: false)
    }

    private func title(for entry: LedgerEntry) -> String {
        switch entry.kind {
        case .buy, .sell:
            let asset = entry.postings.first(where: { $0.account == .trading })?.asset.code ?? "Asset"
            return "\(entry.kind == .buy ? "Buy" : "Sell") \(asset)"
        case .deposit: return "Add"
        case .expense: return "Pay"
        case .openingBalance: return "Opening Balance"
        case .reversal: return "Reversal"
        case .earnSubscribe, .earnRedeem, .interest:
            return model.snapshot.earnProducts.first(where: { $0.id == entry.earnProductID })?.name ?? "Earn"
        }
    }

    private func localizedTitle(for entry: LedgerEntry) -> Text {
        switch entry.kind {
        case .buy, .sell:
            let asset = entry.postings.first(where: { $0.account == .trading })?.asset.code ?? "Asset"
            return entry.kind == .buy ? Text("Buy \(asset)") : Text("Sell \(asset)")
        case .earnSubscribe, .earnRedeem, .interest:
            // 产品名由用户填写，不能当本地化 key 解释。
            return Text(verbatim: title(for: entry))
        default:
            return Text(LocalizedStringKey(title(for: entry)))
        }
    }

    private func accountRoute(_ entry: LedgerEntry) -> String {
        let userPostings = entry.postings.filter(\.account.isUserControlled)
        let source = userPostings.first(where: { $0.quantity < 0 })?.account.kind
        let destination = userPostings.first(where: { $0.quantity > 0 })?.account.kind
        return "\(accountName(source))→\(accountName(destination))"
    }

    private func accountName(_ kind: LedgerAccountKind?) -> String {
        switch kind {
        case .fiat: "Fiat"
        case .trading: "Trading"
        case .earn: "Earn"
        case .external: "External"
        case nil: "Interest"
        }
    }

    private func earnType(_ kind: LedgerEntryKind) -> String {
        switch kind {
        case .earnSubscribe: "Subscribe"
        case .earnRedeem: "Redeem"
        case .interest: "Interest Release"
        case .reversal: "Reversal"
        default: ""
        }
    }

}

// 流水页和申购弹层的 Time 行共用同一个格式（设计 `158:19096` / `155:13936`）。
private func ledgerTimestamp(_ date: Date) -> String {
    ledgerSecondsFormatter.string(from: date)
}

private let ledgerSecondsFormatter = ledgerDateFormatter("yyyy-MM-dd HH:mm:ss")

private enum LedgerTradeSide: String, CaseIterable, Hashable {
    case buy = "Buy"
    case sell = "Sell"
}

private struct LedgerTradeOrder: Identifiable {
    let id = UUID()
    let side: LedgerTradeSide
    let market: AssetSearchResult
    let quantity: Double
    let unitPrice: Double
    let fee: Double
    let settlement: String
    let note: String
    let occurredAt = Date()
}

private enum LedgerTradeField: Hashable {
    case quantity, price, grossValue, fee
}

/// 交易表单里价格 / 数量 / 金额的联动，单向、只走一跳：
///
/// - **价格**谁都改不动。它只有两个来源：选中标的时填进去的最新价，和用户手输。
/// - **金额 = 价格 × 数量**，价格或数量被改时重算。数量为空则金额为空，
///   数量为 0 则金额为 0。
/// - **数量 = 金额 ÷ 价格**，只有金额被改时重算。
/// - 价格为空或为 0 时两条等式都不成立，这时改金额或改数量都不会波及对方。
///
/// 金额和数量互相影响是对的——**前提是价格固定**。价格本身变化时只能推金额，
/// 不能反过来动数量。「只走一跳」就是为此：从前那套锚点是双向的，改价格会连带
/// 改数量，于是填完数量再去点金额，数量就被改掉了（用户 2026-09-06 报的）。
enum LedgerTradeLinkage {
    /// 数量或价格变了之后的金额。
    static func grossValue(quantity: String, price: String, current: String) -> String {
        // 价格不成立，等式就不成立：金额一个字都不动。
        guard let p = Double(price.trimmingCharacters(in: .whitespaces)), p > 0 else { return current }
        let typed = quantity.trimmingCharacters(in: .whitespaces)
        if typed.isEmpty { return "" }
        // `1.` 这种还没输完的，先按原样留着，等它变成能读的数再算。
        guard let q = Double(typed) else { return current }
        return editable(q * p)
    }

    /// 金额变了之后的数量。同样，价格不成立时直接把 `current` 还回去。
    static func quantity(grossValue: String, price: String, current: String) -> String {
        guard let p = Double(price.trimmingCharacters(in: .whitespaces)), p > 0 else { return current }
        let typed = grossValue.trimmingCharacters(in: .whitespaces)
        if typed.isEmpty { return "" }
        guard let v = Double(typed) else { return current }
        return editable(v / p)
    }

    /// 回填进输入框的数不能带千分位，也不能跟着地区换小数点：`amount()` 给出的
    /// `1,234.56` 再被 `Double(_:)` 读回来是 nil，联动会在下一跳整个断掉，
    /// 提交时还会判成「数量不合法」。
    static func editable(_ value: Double) -> String {
        value.formatted(
            .number
                .locale(Locale(identifier: "en_US_POSIX"))
                .grouping(.never)
                .precision(.fractionLength(0...8))
        )
    }
}

private struct LedgerTradeForm: View {
    @ObservedObject var model: LedgerPortfolioViewModel
    @Environment(\.dismiss) private var dismiss

    init(model: LedgerPortfolioViewModel, preselected: AssetSearchResult? = nil) {
        self.model = model
        _selectedMarket = State(initialValue: preselected)
    }

    @State private var side = LedgerTradeSide.buy
    @State private var selectedMarket: AssetSearchResult?
    @State private var showsAssetSearch = false
    @State private var quantity = ""
    @State private var price = ""
    /// 设计 `159:19567` 的 Investment / `154:12261` 的 Sell Value：成交额。
    @State private var grossValue = ""
    /// 视觉 QA：`SIMCTL_CHILD_PAWFOLIO_QA_LEDGER_TRADE_PICKER=1` 直接把
    /// 余额 / 结算币种那个弹层打开（这台机器点不了模拟器）。
    @State private var showsSettlementPicker = {
        #if DEBUG
        ProcessInfo.processInfo.environment["PAWFOLIO_QA_LEDGER_TRADE_PICKER"] == "1"
        #else
        false
        #endif
    }()
    /// 滑杆：买入是「花掉余额的百分之多少」，卖出是「卖掉持仓的百分之多少」。
    @State private var fraction = 0.0
    /// 设计 `158:18329`：填的是费率，默认 0.06%。
    @State private var feeRate = "0.06"
    @State private var settlement = LedgerEntry.defaultSettlementCode
    @State private var note = ""
    @State private var isSaving = false
    @State private var pendingOrder: LedgerTradeOrder?
    @FocusState private var focusedField: LedgerTradeField?

    var body: some View {
        VStack(spacing: 0) {
            NvwaNavigationBar(
                leading: .icon(Image("IconClose"), accessibilityLabel: "Close", action: { dismiss() }),
                title: "Trading"
            )

            ScrollView {
                VStack(spacing: 16) {
                    NvwaSegmentControl(
                        options: LedgerTradeSide.allCases,
                        selection: $side,
                        expandsHorizontally: true,
                        selectedTint: side == .buy ? Nvwa.marketBuy : Nvwa.marketSell,
                        title: { $0.rawValue }
                    )
                    // 买和卖的三个字段含义完全不同（Investment vs Sell Amounts……），
                    // 切换时必须清空，否则卖出填的数量会原样变成买入的数量。
                    .onChange(of: side) { _, _ in resetAmounts() }

                    // 选中之后是两行（代码 + 全名），正是 Select 的
                    // `Status=Aseets`（`2277:912`）。
                    NvwaSelect(
                        label: "Asset Name",
                        isRequired: true,
                        value: selectedMarket?.symbol ?? "",
                        placeholder: "Ex. AAPL, BTC",
                        secondaryText: selectedMarket.flatMap { $0.name == $0.symbol ? nil : $0.name },
                        searchIcon: Image("IconSearch2"),
                        dropdownIcon: Image("IconArrowDropDownFill")
                    ) { showsAssetSearch = true }

                    if !normalizedSymbol.isEmpty {
                        // 买入和卖出都按 价格 → 数量 → 金额 排列：先确认成交价，
                        // 再填交易数量，金额是联动结果；滑杆仍跟随各自的可用余额。
                        if side == .buy {
                            tradePriceField
                            NvwaInputField(
                                label: "Amounts",
                                isRequired: true,
                                placeholder: "0",
                                text: quantityInput,
                                unit: normalizedSymbol
                            )
                            .keyboardType(.decimalPad)
                            .focused($focusedField, equals: .quantity)
                            amountGroup(
                                label: "Investment",
                                text: grossValueInput,
                                unit: settlement,
                                field: .grossValue,
                                available: availableSettlement,
                                // 结算币是法币/稳定币，两位小数。
                                availableText: MoneyFormat.decimal(availableSettlement),
                                availableMark: settlementMark,
                                // 「可以切换货币来源，购买按照美元换算」
                                onPickSource: { showsSettlementPicker = true }
                            )
                        } else {
                            tradePriceField
                            amountGroup(
                                label: "Sell Amounts",
                                text: quantityInput,
                                unit: normalizedSymbol,
                                field: .quantity,
                                available: availableHolding,
                                // 持仓是币的数量，2 位截断会把 2.343523 变成 2.34。
                                availableText: amount(availableHolding),
                                // `assetMark` 只认法币旗帜和稳定币，BTC 这类会退化成首字母圆点。
                                availableMark: selectedMarket.map { market in
                                    AnyView(
                                        PawAssetLogo(
                                            quoteSymbol: market.quoteSymbol,
                                            assetType: market.assetType,
                                            name: market.symbol,
                                            fallbackText: String(market.symbol.prefix(1)),
                                            diameter: 12,
                                            fallbackFontSize: 7
                                        )
                                    )
                                },
                                // 「BTC 只能在 trading 账户」——来源固定，不给选。
                                onPickSource: nil
                            )
                            NvwaInputField(
                                label: "Sell Value",
                                placeholder: "0",
                                text: grossValueInput,
                                unit: settlement
                            )
                            .keyboardType(.decimalPad)
                            .focused($focusedField, equals: .grossValue)
                        }

                        NvwaInputField(
                            label: "Fee",
                            placeholder: "0",
                            text: $feeRate,
                            unit: "%",
                            helpText: feeHelpText
                        )
                        .keyboardType(.decimalPad)
                        .focused($focusedField, equals: .fee)

                        NvwaInputField(label: "Note", placeholder: "Ex. Auto-Invest Account", text: $note)
                    }
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)

            NvwaButton(
                submitTitle,
                kind: side == .buy ? .buy : .sell,
                size: .huge,
                expandsHorizontally: true,
                isLoading: isSaving,
                action: submit
            )
            .disabled(isSaving || exceedsBalance)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Nvwa.backgroundMain)
        // 换标的等于换价格：旧标的的价对新标的没有意义，直接填新的最新价。
        .task { await fillLatestPrice(for: selectedMarket) }
        .onChange(of: selectedMarket) { _, market in
            Task { await fillLatestPrice(for: market) }
        }
        .sheet(isPresented: $showsAssetSearch) {
            AssetSearchView(initialQuery: selectedMarket?.symbol ?? "", title: "Select asset") { result in
                selectedMarket = result
                showsAssetSearch = false
            }
        }
        .sheet(isPresented: $showsSettlementPicker) {
            // 每行是 24pt logo + 「余额 + 代码」（B-L Semi Bold），选中行带勾——
            // 不是只列个币种代码（设计 `158:18414`）。
            PawSingleSelectSheet(
                title: settlementPickerTitle,
                options: LedgerEntry.allowedSettlementCodes.sorted(),
                selection: settlement,
                optionTitle: { code in
                    let asset = Self.settlementAsset(for: code)
                    let balance = model.projection.balance(in: .fiat("exchange"), asset: asset)
                    return "\(MoneyFormat.decimal(balance)) \(code)"
                },
                onSelect: { settlement = $0 },
                icon: { code in assetMark(Self.settlementAsset(for: code), diameter: 24) }
            )
        }
        .sheet(item: $pendingOrder) { order in
            LedgerTradeConfirmation(model: model, order: order) {
                pendingOrder = nil
                dismiss()
            }
        }
    }

    private var submitTitle: LocalizedStringKey {
        guard !normalizedSymbol.isEmpty else {
            return LocalizedStringKey(side.rawValue)
        }
        switch side {
        case .buy: return "Buy \(normalizedSymbol)"
        case .sell: return "Sell \(normalizedSymbol)"
        }
    }

    // MARK: - 设计 `159:19567` / `154:12261` 的字段

    static func settlementAsset(for code: String) -> LedgerAsset {
        LedgerAsset(code: code, kind: code == "USD" ? .fiat : .stablecoin)
    }

    private var settlementAsset: LedgerAsset { Self.settlementAsset(for: settlement) }

    private var tradedAsset: LedgerAsset? {
        selectedMarket.map { LedgerAsset(code: $0.symbol, kind: ledgerKind(for: $0.assetType)) }
    }

    /// 结算现金固定从 Exchange Spot 出入（`LEDGER_MODEL.md`）。
    private var availableSettlement: Double {
        model.projection.balance(in: .fiat("exchange"), asset: settlementAsset)
    }

    /// 「BTC 只能在 trading 账户」（设计 `158:16481` 的注释）。
    private var availableHolding: Double {
        guard let tradedAsset else { return 0 }
        return model.projection.balance(in: .trading, asset: tradedAsset)
    }

    private var settlementMark: AnyView? {
        AnyView(assetMark(settlementAsset, diameter: 12))
    }

    /// 买入时这个弹层是从 Investment 上面那行余额点开的，列的是各币种的余额，
    /// 标题就该是 Balance（设计 `197:6880` 右边那张）。卖出时它是从 Sell Price
    /// 的单位点开的，那才是在选结算币种。
    private var settlementPickerTitle: String {
        side == .buy ? "Balance" : "trade.settlementCurrency"
    }

    @ViewBuilder
    private func balanceHint(_ text: String, mark: AnyView?, showsChevron: Bool) -> some View {
        HStack(spacing: 4) {
            if let mark { mark }
            Text(text)
                .foregroundStyle(Nvwa.ink)
                .monospacedDigit()
            if showsChevron {
                Image("IconArrowDownSFill")
                    .renderingMode(.template).resizable().scaledToFit()
                    .frame(width: 12, height: 12)
                    .foregroundStyle(Nvwa.ink)
            }
        }
    }

    /// 「金额 + 余额提示 + 滑杆」这一组：买入是 Investment（余额可切换币种），
    /// 卖出是 Sell Amounts（来源固定在 trading，不给选）。
    @ViewBuilder
    private func amountGroup(
        label: String,
        text: Binding<String>,
        unit: String,
        field: LedgerTradeField,
        available: Double,
        availableText: String,
        availableMark: AnyView?,
        onPickSource: (() -> Void)?
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(LocalizedStringKey(label)).foregroundStyle(Nvwa.textSecondary)
                Spacer(minLength: 4)
                Text("Balance").foregroundStyle(Nvwa.textSecondary)
                // 卖出侧来源固定在 trading，没有可点的东西。这里**不能**套一个
                // disabled 的 Button——SwiftUI 会把禁用按钮的整个 label 调暗，
                // 资产 logo 会跟着变成半透明。没有 picker 时直接画内容。
                if let onPickSource {
                    Button(action: onPickSource) {
                        balanceHint(availableText, mark: availableMark, showsChevron: true)
                    }
                    .buttonStyle(.plain)
                } else {
                    balanceHint(availableText, mark: availableMark, showsChevron: false)
                }
            }
            .nvwaTextStyle(Nvwa.Typography.bodySmall, linesFillLineHeight: false)

            NvwaInputField(
                label: nil,
                placeholder: "0",
                text: text,
                unit: unit,
                helpText: exceedsBalance ? "Insufficient balance." : nil
            )
            .keyboardType(.decimalPad)
            .focused($focusedField, equals: field)

            NvwaSlider(value: $fraction)
                .onChange(of: fraction) { _, value in
                    guard available > 0 else { return }
                    // 走同一个 Binding，联动跟手输一模一样。写的是不带千分位的
                    // 纯数字，否则下一跳 `Double(_:)` 直接读成 nil。
                    text.wrappedValue = LedgerTradeLinkage.editable(available * value)
                }
        }
    }

    /// Buy Price / Sell Price。卖出那一档的单位可以点开换 USD / USDT / USDC
    /// （设计 `158:19232` 的注释）——那正是 Text Input Field 的 `Dropdown=Yes`
    /// （`2276:635`），不用再在 trailing 里手搓一遍；买入的币种在上面余额那行切。
    private var tradePriceField: some View {
        NvwaInputField(
            label: side == .buy ? "Buy Price" : "Sell Price",
            isRequired: true,
            placeholder: "0",
            text: priceInput,
            unit: settlement,
            dropdownIcon: side == .sell ? Image("IconArrowDropDownFill") : nil,
            onUnitTap: side == .sell ? { showsSettlementPicker = true } : nil
        )
        .keyboardType(.decimalPad)
        .focused($focusedField, equals: .price)
    }

    /// 买入真正扣的是「成交额 + 手续费」，所以按这个数比余额，
    /// 免得刚好卡在边界上表单说没问题、账本却因为禁止负余额而拒绝。
    private var settlementCost: Double? {
        guard let (q, p, f) = values else { return nil }
        return q * p + f
    }

    private var exceedsBalance: Bool {
        switch side {
        case .buy:
            let cost = settlementCost ?? Double(grossValue) ?? 0
            guard cost > 0 else { return false }
            return cost > availableSettlement + LedgerEntry.balanceTolerance
        case .sell:
            guard let qty = Double(quantity), qty > 0 else { return false }
            return qty > availableHolding + LedgerEntry.balanceTolerance
        }
    }

    /// 切换买卖时清掉数量和成交额、滑杆归零；价格重新填这一侧的最新价。
    /// 手续费率和备注与买卖无关，保留。这里写的是裸 state，不走联动的 Binding——
    /// 清空是重置，不该顺手把另一个字段也算一遍。
    private func resetAmounts() {
        quantity = ""
        price = ""
        grossValue = ""
        fraction = 0
        focusedField = nil
        Task { await fillLatestPrice(for: selectedMarket) }
    }

    /// 选中标的后把最新价填进价格框（设计 `159:19567`「默认填入最新价」）。
    /// 这是价格唯一的自动来源——填完之后它只认用户手输。
    private func fillLatestPrice(for market: AssetSearchResult?) async {
        guard let market, let latest = await model.latestPrice(for: market.quoteSymbol) else { return }
        priceInput.wrappedValue = LedgerTradeLinkage.editable(latest)
    }

    // MARK: - 三个数的联动
    //
    // 传播写在 Binding 的 setter 里，不用 `onChange`：`onChange` 是下一轮更新才
    // 送到的，回写触发的那一跳分不清是用户敲的还是自己刚写的，得靠一个
    // 「正在同步」的标志位去挡，而那个标志位在下一轮早就复位了。setter 里改的是
    // 裸 state，压根不会二次进来。

    private var quantityInput: Binding<String> {
        Binding(
            get: { quantity },
            set: { typed in
                quantity = typed
                grossValue = LedgerTradeLinkage.grossValue(
                    quantity: typed, price: price, current: grossValue
                )
            }
        )
    }

    /// 价格只影响金额，不碰数量。
    private var priceInput: Binding<String> {
        Binding(
            get: { price },
            set: { typed in
                price = typed
                grossValue = LedgerTradeLinkage.grossValue(
                    quantity: quantity, price: typed, current: grossValue
                )
            }
        )
    }

    private var grossValueInput: Binding<String> {
        Binding(
            get: { grossValue },
            set: { typed in
                grossValue = typed
                quantity = LedgerTradeLinkage.quantity(
                    grossValue: typed, price: price, current: quantity
                )
            }
        )
    }

    private var values: (Double, Double, Double)? {
        guard let q = Double(quantity), q > 0, let p = Double(price), p > 0,
              let rate = Double(feeRate), rate >= 0,
              let f = LedgerTradeDetails.feeAmount(grossValue: q * p, ratePercent: rate) else { return nil }
        return (q, p, f)
    }

    /// 用户填的是费率，这里把算出来的绝对额回显在输入框下面。
    private var feeHelpText: String? {
        guard let q = Double(quantity), q > 0, let p = Double(price), p > 0,
              let rate = Double(feeRate), rate >= 0,
              let f = LedgerTradeDetails.feeAmount(grossValue: q * p, ratePercent: rate) else { return nil }
        return "Fee \(amount(f)) \(settlement)"
    }

    private func submit() {
        guard let selectedMarket else {
            showsAssetSearch = true
            return
        }
        guard let q = Double(quantity), q > 0 else {
            focusedField = .quantity
            return
        }
        guard let p = Double(price), p > 0 else {
            focusedField = .price
            return
        }
        guard let rate = Double(feeRate), rate >= 0,
              let f = LedgerTradeDetails.feeAmount(grossValue: q * p, ratePercent: rate) else {
            focusedField = .fee
            return
        }
        // 余额不足直接挡在这里，别让它走到滑动确认那一步。
        guard !exceedsBalance else {
            focusedField = side == .buy ? .grossValue : .quantity
            return
        }
        pendingOrder = LedgerTradeOrder(
            side: side,
            market: selectedMarket,
            quantity: q,
            unitPrice: p,
            fee: f,
            settlement: settlement,
            note: note
        )
    }

    private var normalizedSymbol: String {
        selectedMarket?.symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
    }

    private func ledgerKind(for type: AssetType) -> LedgerAsset.Kind {
        switch type {
        case .equity: .equity
        case .etf: .etf
        case .cryptocurrency: .cryptocurrency
        case .stable: .stablecoin
        }
    }
}

private struct LedgerTradeConfirmation: View {
    @ObservedObject var model: LedgerPortfolioViewModel
    let order: LedgerTradeOrder
    let onSuccess: () -> Void
    @State private var isSaving = false
    @State private var didSucceed = false

    var body: some View {
        Group {
            if didSucceed {
                PawSuccessSheet()
            } else {
                PawSheet(
                    title: "\(order.side.rawValue) \(order.market.symbol)",
                    showsCloseButton: false
                ) {
                    VStack(spacing: 16) {
                        detail("Time", Self.timestampFormatter.string(from: order.occurredAt))
                        detail(order.side == .buy ? "Investment" : "Sell Value", "\(amount(order.quantity * order.unitPrice)) \(order.settlement)")
                        detail("\(order.side.rawValue) Amounts", "\(amount(order.quantity)) \(order.market.symbol)")
                        detail(order.side == .buy ? "Cost Price" : "Sell Price", "\(amount(order.unitPrice)) \(order.settlement)")
                        detail("From to", order.side == .buy ? "Fiat→Trading" : "Trading→Fiat")
                        detail("Note", order.note.isEmpty ? LedgerFieldPlaceholder.notSet : order.note)
                        detail("Fees", "-\(amount(order.fee)) \(order.settlement)", tone: order.fee > 0 ? Nvwa.marketSell : Nvwa.ink)
                    }
                } footer: {
                    NvwaScrollButton("Slide to Confirm", isLoading: isSaving) {
                        confirm()
                    }
                }
            }
        }
        .onDisappear { if didSucceed { onSuccess() } }
    }

    private func detail(_ label: String, _ value: String, tone: Color = Nvwa.ink) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(LocalizedStringKey(label)).foregroundStyle(Nvwa.textSecondary)
            Spacer(minLength: 0)
            Text(LocalizedStringKey(value))
                .foregroundStyle(tone)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
        }
        .nvwaTextStyle(Nvwa.Typography.bodyMedium, linesFillLineHeight: false)
    }

    private func confirm() {
        guard !isSaving else { return }
        let asset = LedgerAsset(code: order.market.symbol, kind: ledgerKind(for: order.market.assetType))
        let settlementAsset = LedgerAsset(
            code: order.settlement,
            kind: order.settlement == "USD" ? .fiat : .stablecoin
        )
        isSaving = true
        Task { @MainActor in
            let success = order.side == .buy
                ? await model.buy(
                    asset: asset,
                    quantity: order.quantity,
                    unitPrice: order.unitPrice,
                    settlementAsset: settlementAsset,
                    fee: order.fee,
                    note: order.note
                )
                : await model.sell(
                    asset: asset,
                    quantity: order.quantity,
                    unitPrice: order.unitPrice,
                    settlementAsset: settlementAsset,
                    fee: order.fee,
                    note: order.note
                )
            isSaving = false
            if success {
                didSucceed = true
            }
        }
    }

    private func ledgerKind(for type: AssetType) -> LedgerAsset.Kind {
        switch type {
        case .equity: .equity
        case .etf: .etf
        case .cryptocurrency: .cryptocurrency
        case .stable: .stablecoin
        }
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}

private enum LedgerEarnTab: String, CaseIterable, Hashable {
    case holding = "Holding"
    case product = "Product"
}

/// `more` 打开的「Manage Earn」弹层（设计 `155:16160`）。
/// 设计只画了 Delist / Edit；`Record Interest` 是实现里独有的入口，别的地方没有，
/// 删了就没法登记真实派息，所以保留。
private enum LedgerEarnManageOption: String, Hashable {
    case edit = "Edit"
    case recordInterest = "Record Interest"
    case delist = "Delist"
}

private struct LedgerEarnManageTarget: Identifiable {
    let product: EarnProduct
    let holding: Double?
    var id: String { product.id }
}

private struct LedgerEarnAction: Identifiable {
    let product: EarnProduct
    let redeems: Bool
    var id: String { "\(product.id)-\(redeems)" }
}

private struct LedgerEarnView: View {
    @ObservedObject var model: LedgerPortfolioViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showsProduct = false
    @State private var tab = LedgerEarnTab.holding
    @State private var action: LedgerEarnAction?
    @State private var interestProduct: EarnProduct?
    @State private var apyProduct: EarnProduct?
    /// 点卡片本体进明细页（设计 `158:16698`）；卡片自己那颗 Subscribe / Redeem
    /// 按钮仍然直达申购/赎回弹层。
    @State private var detailProduct: EarnProduct?
    @State private var manageProduct: LedgerEarnManageTarget?
    @State private var delistProduct: EarnProduct?
    @State private var showsDailyBreakdown = {
        #if DEBUG
        ProcessInfo.processInfo.environment["PAWFOLIO_QA_EARN_DAILY"] == "1"
        #else
        false
        #endif
    }()
    @State private var reorderState = NvwaReorderState<String>()

    var body: some View {
        VStack(spacing: 0) {
            NvwaNavigationBar(
                leading: .icon(Image("IconClose"), accessibilityLabel: "Close", action: { dismiss() }),
                title: "Earn"
            )
            ScrollView {
                VStack(spacing: 16) {
                    NvwaSegmentControl(
                        options: LedgerEarnTab.allCases,
                        selection: $tab,
                        expandsHorizontally: true,
                        title: { $0.rawValue }
                    )

                    // 设计 `154:13022` 整列是 gap 16——分段控件、每张产品卡、End 之间都一样。
                    // Holding 页（设计 `155:13496`）和 Product 页不是同一套：
                    // 它是「USD 汇总条 + 紧凑持仓行」，不是产品大卡片。
                    if tab == .holding, !model.earnBalances.isEmpty {
                        holdingSummary
                    }

                    LazyVStack(spacing: tab == .holding ? 0 : 16) {
                        if tab == .product {
                            ForEach(visibleProducts) { product in
                                earnCard(product: product, holding: nil)
                            }
                        } else {
                            ForEach(model.earnBalances, id: \.product.id) { item in
                                earnHoldingRow(product: item.product, quantity: item.quantity)
                            }
                        }
                        if displayedProductsAreEmpty {
                            VStack(spacing: 8) {
                                Image("ArtNoRecords")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 120, height: 120)
                                Text("No Records")
                                    .nvwaTextStyle(Nvwa.Typography.bodySmall, linesFillLineHeight: false)
                                    .foregroundStyle(Nvwa.textSecondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 24)
                        } else {
                            Text("End")
                                .nvwaTextStyle(Nvwa.Typography.bodySmall, linesFillLineHeight: false)
                                .foregroundStyle(Nvwa.textSecondary)
                                .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                        }
                    }
                    // 两个页签的数据都以 product.id 标识；LazyVStack 会跨条件分支复用
                    // 相同 identity 的旧卡片。将页签纳入容器 identity，切换到 Holding
                    // 时才能按设计重建为 82pt 持仓行。
                    .id(tab)
                }
                .padding(16)
            }
            // 同上，兜底用。
            .scrollDisabled(reorderState.isReordering)
            // 两个页签底部都是这颗（设计 `154:13018` 和 `155:13496` 的 Bottom Action 一致）。
            NvwaButton("Add Earn Products", size: .huge, expandsHorizontally: true) {
                showsProduct = true
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Nvwa.backgroundMain)
        .sensoryFeedback(.impact(weight: .medium), trigger: reorderState.feedbackTrigger)
        .sheet(isPresented: $showsProduct) { LedgerEarnProductForm(model: model) }
        .sheet(isPresented: $showsDailyBreakdown) { LedgerEarnDailySheet(model: model) }
        .fullScreenCover(item: $detailProduct) { product in
            LedgerEarnDetailView(model: model, product: product)
        }
        .sheet(item: $manageProduct) { target in
            // 设计 `155:16160`：more 打开的是「Manage Earn」单选弹层，不是系统菜单。
            PawSingleSelectSheet(
                title: "Manage Earn",
                options: manageOptions(for: target),
                selection: nil,
                optionTitle: { $0.rawValue },
                onSelect: { option in perform(option, on: target) }
            )
        }
        .sheet(item: $delistProduct) { product in
            LedgerDelistWarningSheet(model: model, product: product)
        }
        .sheet(item: $action) {
            LedgerEarnSubscriptionView(model: model, product: $0.product, startsRedeeming: $0.redeems)
        }
        .sheet(item: $interestProduct) { LedgerInterestPayoutView(model: model, product: $0) }
        .sheet(item: $apyProduct) { LedgerEarnAPYEditor(model: model, product: $0) }
    }

    /// 汇总条（设计 `155:13496` 的 `Frame 17`）：两块统计，注释写着「这里统一换算成USD」。
    private var holdingSummary: some View {
        HStack(spacing: 10) {
            Button { showsDailyBreakdown = true } label: {
                earnSummaryBlock("Daily (USD)", value: model.totalEarnDailyInterestUSD)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows the daily profit breakdown")
            earnSummaryBlock("Total (USD)", value: model.totalEarnPaidInterestUSD)
        }
        .padding(10)
        .background(Nvwa.backgroundCard, in: RoundedRectangle(cornerRadius: 12))
    }

    /// `label` 必须是 `LocalizedStringKey`：`Text(someString)` 不走本地化，
    /// 只有字面量（或这个类型）才会去查字符串目录。
    private func earnSummaryBlock(_ label: LocalizedStringKey, value: Double?) -> some View {
        VStack(alignment: .center, spacing: 4) {
            Text(label)
                .nvwaTextStyle(Nvwa.Typography.bodySmall)
                .foregroundStyle(Nvwa.textSecondary)
            Text(value.map(MoneyFormat.signedDecimal) ?? "—")
                .nvwaTextStyle(Nvwa.Typography.titleBody)
                .monospacedDigit()
                .foregroundStyle(Nvwa.marketBuy)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .accessibilityElement(children: .combine)
    }

    /// 用户在 `211:24982` 上调整后的两行排版为 82pt：p16、文字间距 4；
    /// 主字 B-L Semi Bold 16/24，副字 B-M Regular 14/22。
    /// 左边产品名 + APY，右边估值 + 已计提利息。点进去是明细页。
    private func earnHoldingRow(product: EarnProduct, quantity: Double) -> some View {
        let content = HStack(spacing: 10) {
            LedgerEarnProductMark(product: product, circleSize: 32, glyphSize: 16)

            VStack(alignment: .leading, spacing: 4) {
                Text(product.name)
                    .nvwaTextStyle(Nvwa.Typography.bodyLargeSemibold, linesFillLineHeight: false)
                    .frame(height: Nvwa.Typography.bodyLargeSemibold.lineHeight)
                    .lineLimit(1)
                Text("APY \(amount(model.effectiveRate(for: product)))%")
                    .nvwaTextStyle(Nvwa.Typography.bodyMedium, linesFillLineHeight: false)
                    .frame(height: Nvwa.Typography.bodyMedium.lineHeight)
                    .foregroundStyle(Nvwa.marketBuy)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 4) {
                Text(model.earnValueUSD(for: product, quantity: quantity).map(MoneyFormat.usd) ?? "—")
                    .nvwaTextStyle(Nvwa.Typography.bodyLargeSemibold, linesFillLineHeight: false)
                    .frame(height: Nvwa.Typography.bodyLargeSemibold.lineHeight)
                Text(
                    model.accruedInterestUSD(for: product)
                        .map { MoneyFormat.signedDecimal($0) + " USD" } ?? "—"
                )
                .nvwaTextStyle(Nvwa.Typography.bodyMedium, linesFillLineHeight: false)
                .frame(height: Nvwa.Typography.bodyMedium.lineHeight)
                .foregroundStyle(Nvwa.marketBuy)
            }
            .monospacedDigit()
            .fixedSize(horizontal: true, vertical: false)
        }
        .foregroundStyle(Nvwa.ink)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .nvwaReorderable(
            item: product.id,
            items: model.earnBalances.map { $0.product.id },
            state: $reorderState,
            layout: .vertical(itemExtent: ledgerHoldingRowHeight),
            onTap: { detailProduct = product },
            onMove: { model.moveEarnProduct($0, to: $1) }
        )

        return content
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { detailProduct = product }
        .accessibilityHint("Double-tap to open. Touch and hold, then drag to reorder.")
        .accessibilityAction(named: "Move up") { moveEarnProduct(product.id, by: -1) }
        .accessibilityAction(named: "Move down") { moveEarnProduct(product.id, by: 1) }
    }

    private func moveEarnProduct(_ productID: String, by delta: Int) {
        let ids = model.earnBalances.map { $0.product.id }
        guard let move = reorderState.accessibilityMove(productID, by: delta, in: ids) else {
            return
        }
        model.moveEarnProduct(move.item, to: move.destinationIndex)
    }

    private func earnCard(product: EarnProduct, holding: Double?) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 10) {
                Button { openDefaultAction(for: product, holding: holding) } label: {
                    HStack(spacing: 10) {
                        LedgerEarnProductMark(product: product, circleSize: 40, glyphSize: 20)
                        Text(product.name)
                            .nvwaTextStyle(Nvwa.Typography.titleBody, linesFillLineHeight: false)
                    }
                    .foregroundStyle(Nvwa.ink)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(product.name)
                Spacer()
                Color.clear
                    .frame(width: 24, height: 40)
                    .overlay {
                        Button {
                            manageProduct = LedgerEarnManageTarget(product: product, holding: holding)
                        } label: {
                            Image("IconMore2")
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .foregroundStyle(Nvwa.ink)
                                .frame(width: 24, height: 24)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("More actions for \(product.name)")
                    }
            }

            VStack(spacing: 12) {
                earnDetail("Assets", product.asset.code)
                earnDetail("APY", "\(amount(model.effectiveRate(for: product)))%", tone: Nvwa.marketBuy)
                if product.term == .flexible {
                    earnDetail("Interest Calculation", product.interestMode.title)
                    earnDetail("Term", "Flexible")
                    earnDetail("Payout Frequency", payoutTitle(product.payoutFrequency))
                    if let next = model.nextPayoutDate(for: product) {
                        earnDetail("Next Time Payout", nextPayoutTimestamp(next))
                    }
                } else if product.term == .fixed {
                    if let maturity = product.maturesAt {
                        earnDetail("Days", "\(max(0, Calendar.current.dateComponents([.day], from: product.startsAt, to: maturity).day ?? 0))D")
                        earnDetail("Maturity Date", maturityTimestamp(maturity))
                    }
                } else {
                    // 设计 `154:13078` / `154:13088`：行权价和敲出价是两行，不是一段文本。
                    if let strike = product.strikePrice {
                        earnDetail("Strike Price", "\(amount(strike)) \(product.asset.code)")
                    }
                    if let knockOut = product.knockOutPrice {
                        earnDetail("Knock-Out Price", "\(amount(knockOut)) \(product.asset.code)")
                    }
                    // 旧记录还是那段自由文本，读出来照常显示。
                    if product.strikePrice == nil, product.knockOutPrice == nil,
                       let parameters = product.structuredParameters, !parameters.isEmpty {
                        earnDetail("Product Parameters", parameters)
                    }
                    earnDetail("Payout Frequency", payoutTitle(product.payoutFrequency))
                    if let next = model.nextPayoutDate(for: product) {
                        earnDetail("Next Time Payout", nextPayoutTimestamp(next))
                    }
                    if let maturity = product.maturesAt {
                        earnDetail("Maturity Date", maturityTimestamp(maturity))
                    }
                }
                if let holding {
                    earnDetail("Total Investments", "\(amount(holding)) \(product.asset.code)")
                    earnDetail("Accrued Interest", "\(amount(model.accruedInterest(for: product))) \(product.asset.code)", tone: Nvwa.marketBuy)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { openDefaultAction(for: product, holding: holding) }

            NvwaButton(
                holding == nil ? "Subscribe" : "Redeem",
                kind: .secondary,
                size: .small,
                expandsHorizontally: true
            ) {
                action = LedgerEarnAction(product: product, redeems: holding != nil)
            }
        }
        .padding(16)
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Nvwa.line, lineWidth: 1))
    }

    private func manageOptions(for target: LedgerEarnManageTarget) -> [LedgerEarnManageOption] {
        var options: [LedgerEarnManageOption] = [.edit]
        if target.holding != nil, model.isInterestPayoutDue(for: target.product) {
            options.append(.recordInterest)
        }
        // 活期、定期和结构化产品共用同一套下架流程。
        if target.product.canDelist { options.append(.delist) }
        return options
    }

    private func perform(_ option: LedgerEarnManageOption, on target: LedgerEarnManageTarget) {
        switch option {
        case .edit: apyProduct = target.product
        case .recordInterest: interestProduct = target.product
        case .delist: delistProduct = target.product
        }
    }

    private func openDefaultAction(for product: EarnProduct, holding: Double?) {
        detailProduct = product
    }

    private func earnDetail(_ label: String, _ value: String, tone: Color = Nvwa.ink) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(LocalizedStringKey(label)).foregroundStyle(Nvwa.textSecondary)
            Spacer(minLength: 12)
            Text(LocalizedStringKey(value)).foregroundStyle(tone).multilineTextAlignment(.trailing)
        }
        .nvwaTextStyle(Nvwa.Typography.bodyMedium, linesFillLineHeight: false)
    }

    /// 到期的自动下架（设计 `154:13126` 的注释「到期后自动下架」），
    /// 手动下架的也不再出现在 Product 里。
    private var visibleProducts: [EarnProduct] {
        model.snapshot.earnProducts.filter { product in
            guard !product.isDelisted else { return false }
            guard let maturity = product.maturesAt else { return true }
            return maturity > Date()
        }
    }

    private var displayedProductsAreEmpty: Bool {
        tab == .product ? visibleProducts.isEmpty : model.earnBalances.isEmpty
    }

}

/// v2.1.1 `211:24603`：Holding 汇总条点 Daily 后展示逐产品的一日收益。
private struct LedgerEarnDailySheet: View {
    @ObservedObject var model: LedgerPortfolioViewModel
    @Environment(\.dismiss) private var dismiss

    private let columns = [
        GridItem(.flexible(), spacing: 16, alignment: .topLeading),
        GridItem(.flexible(), spacing: 16, alignment: .topLeading),
    ]

    var body: some View {
        PawSheet(title: "Daily", showsCloseButton: false) {
            VStack(spacing: 32) {
                VStack(spacing: 2) {
                    Text("\(model.totalEarnDailyInterestUSD.map(MoneyFormat.signedDecimal) ?? "—") USD")
                        .nvwaTextStyle(Nvwa.Typography.titleSection, linesFillLineHeight: false)
                        .foregroundStyle(Nvwa.marketBuy)
                        .monospacedDigit()
                    Text(
                        verbatim: "\(ledgerDailyPayoutFormatter.string(from: nextDailyPayoutDate)) "
                            + String(localized: "Payout")
                    )
                        .nvwaTextStyle(Nvwa.Typography.bodySmall, linesFillLineHeight: false)
                        .foregroundStyle(Nvwa.textSecondary)
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity)

                LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                    ForEach(model.earnBalances, id: \.product.id) { item in
                        dailyProduct(item.product)
                    }
                }
            }
        } footer: {
            NvwaButton("OK", size: .huge, expandsHorizontally: true) { dismiss() }
        }
    }

    private func dailyProduct(_ product: EarnProduct) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                LedgerEarnProductMark(product: product, circleSize: 16, glyphSize: 12)
                Text(product.name)
                    .nvwaTextStyle(Nvwa.Typography.bodyMedium, linesFillLineHeight: false)
                    .foregroundStyle(Nvwa.ink)
                    .lineLimit(1)
            }

            NvwaTag("APY \(amount(model.effectiveRate(for: product)))%", tone: .green)

            Text(model.dailyInterestUSD(for: product).map(MoneyFormat.signedDecimal) ?? "—")
                .nvwaTextStyle(Nvwa.Typography.bodyMediumSemibold, linesFillLineHeight: false)
                .foregroundStyle(Nvwa.sentimentPositive)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, minHeight: 68, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }

    private var nextDailyPayoutDate: Date {
        let calendar = Calendar.current
        let now = Date()
        guard let today = calendar.date(
            bySettingHour: EarnProduct.payoutHour,
            minute: 0,
            second: 0,
            of: now
        ) else { return now }
        if now < today { return today }
        return calendar.date(byAdding: .day, value: 1, to: today)
            ?? today.addingTimeInterval(86_400)
    }
}

// Earn 卡片和 Earn 明细页共用同一套时间格式，别各写一份。
private func nextPayoutTimestamp(_ date: Date) -> String {
    ledgerNextPayoutFormatter.string(from: date)
}

private func maturityTimestamp(_ date: Date) -> String {
    ledgerMaturityFormatter.string(from: date)
}

private let ledgerChartTimeFormatter = ledgerDateFormatter("HH:mm")
private let ledgerChartDayFormatter = ledgerDateFormatter("MMM d")
private let ledgerChartStampFormatter = ledgerDateFormatter("MM/dd HH:mm")
private let ledgerChartYearStampFormatter = ledgerDateFormatter("yyyy/MM/dd")
private let ledgerNextPayoutFormatter = ledgerDateFormatter("HH:mm MMM d yyyy")
private let ledgerDailyPayoutFormatter = ledgerDateFormatter("HH:mm dd MMM yyyy")
private let ledgerMaturityFormatter = ledgerDateFormatter("yyyy-MM-dd HH:mm")

private func ledgerDateFormatter(_ format: String) -> DateFormatter {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = .current
    formatter.dateFormat = format
    return formatter
}

private struct LedgerEarnAPYEditor: View {
    @ObservedObject var model: LedgerPortfolioViewModel
    let product: EarnProduct
    @State private var rate: String
    @State private var name: String
    @State private var isSaving = false
    @State private var didSucceed = false

    init(model: LedgerPortfolioViewModel, product: EarnProduct) {
        self.model = model
        self.product = product
        _rate = State(initialValue: amount(product.annualRatePercent))
        _name = State(initialValue: product.name)
    }

    /// 设计 `155:16262`：标题就叫 Edit，两个必填字段 Name + APY，APY 输入框尾部带 `%`。
    var body: some View {
        if didSucceed {
            PawSuccessSheet()
        } else {
            PawSheet(title: "Edit", showsCloseButton: false) {
                VStack(alignment: .leading, spacing: 16) {
                    NvwaInputField(label: "Name", isRequired: true, placeholder: "Ex. USD Flexible Term", text: $name)
                    NvwaInputField(
                        label: "APY",
                        isRequired: true,
                        placeholder: "0",
                        text: $rate,
                        unit: "%"
                    )
                    .keyboardType(.decimalPad)

                    // 设计没画这条提示，但「下一次付息周期才生效」是用户定的规则，
                    // 去掉等于让人看不出改完什么时候起效——保留，并在 HANDOFF 里记为差异。
                    if let effectiveAt = product.nextPayout(after: Date()) {
                        NvwaHint(
                            localizedText: "The new APY takes effect on \(effectiveAt.formatted(date: .abbreviated, time: .shortened)).",
                            level: .neutral
                        )
                    }
                }
            } footer: {
                NvwaButton("Save", size: .huge, expandsHorizontally: true, isLoading: isSaving) {
                    save()
                }
                .disabled(parsedRate == nil || trimmedName.isEmpty || isSaving)
            }
        }
    }

    private var parsedRate: Double? {
        guard let value = Double(rate), value.isFinite, (0...1_000).contains(value) else { return nil }
        return value
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        guard let parsedRate, !trimmedName.isEmpty else { return }
        var updated = product
        updated.name = trimmedName
        updated.annualRatePercent = parsedRate
        isSaving = true
        Task { @MainActor in
            let success = await model.updateProduct(updated)
            isSaving = false
            if success { didSucceed = true }
        }
    }
}

private struct LedgerEarnProductForm: View {
    /// 能进理财的资产：法币/稳定币从 Fiat 账户申购，Crypto 从 Trading 申购；
    /// 股票和 ETF 被领域层拒绝（`LEDGER_MODEL.md`）。
    static let currencyOptions = ["USD", "CNY", "USDT", "USDC", "BTC", "ETH"]

    @ObservedObject var model: LedgerPortfolioViewModel
    @Environment(\.locale) private var locale
    @State private var name = ""
    @State private var code = "USDT"
    @State private var rate = ""
    @State private var term = EarnProductTerm.flexible
    @State private var mode = InterestMode.simple
    @State private var payout = EarnPayoutFrequency.hourly
    @State private var maturity = Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()
    @State private var structuredParameters = ""
    @State private var strikePrice = ""
    @State private var knockOutPrice = ""
    @State private var days = ""
    @State private var showsAssetPicker = false
    @State private var showsMaturityPicker = false
    @State private var isSaving = false
    @State private var didSucceed = false

    var body: some View {
        if didSucceed {
            PawSuccessSheet()
        } else {
            PawSheet(title: "Add Earn", showsCloseButton: false) {
            VStack(spacing: 16) {
                PawSingleSelectField(
                    label: "Type",
                    sheetTitle: "Type",
                    options: EarnProductTerm.allCases,
                    selection: $term,
                    optionTitle: { $0.rawValue.capitalized }
                )
                // 设计改成 Assets（用户 2026-09-05：能理财的不只稳定币）。
                // 选项走 `173:21473`：法币 + 稳定币 + 数字货币，样式复用 Add Currency 弹层。
                NvwaSelect(
                    label: "Assets",
                    value: code,
                    dropdownIcon: Image("IconArrowDropDownFill")
                ) { showsAssetPicker = true }
                .accessibilityLabel("Assets")
                .accessibilityValue(code)
                NvwaInputField(label: "Name", isRequired: true, placeholder: "Ex. USD Flexible Term", text: $name)

                // 定期的期限设计 `155:15867` 填的是**天数**，不是选到期日。
                if term == .fixed {
                    NvwaInputField(
                        label: "Days",
                        isRequired: true,
                        placeholder: "0",
                        text: $days,
                        unit: "D"
                    )
                    .keyboardType(.numberPad)
                }

                NvwaInputField(
                    label: "APY",
                    isRequired: true,
                    placeholder: "0",
                    text: $rate,
                    unit: "%"
                )
                .keyboardType(.decimalPad)

                // 「定期只有单利」「固定票息只有单利」——这两类根本不出现这一行，
                // 不是显示出来再置灰（设计 `155:15867` / `155:15932`）。
                if term == .flexible {
                    HStack {
                        Text("Interest Calculation")
                            .nvwaTextStyle(Nvwa.Typography.bodyMedium, linesFillLineHeight: false).foregroundStyle(Nvwa.textSecondary)
                        Spacer()
                        NvwaSegmentControl(
                            options: [InterestMode.simple, .compound],
                            selection: $mode,
                            size: .small,
                            expandsHorizontally: false,
                            title: { $0 == .simple ? "SI" : "CI" }
                        )
                    }
                }

                // 固定票息把条款拆成两个必填价格（设计 `155:15940` / `155:16010`）。
                if term == .structured {
                    NvwaInputField(
                        label: "Strike Price",
                        isRequired: true,
                        placeholder: "0",
                        text: $strikePrice,
                        unit: code
                    )
                    .keyboardType(.decimalPad)

                    NvwaInputField(
                        label: "Knock-Out Price",
                        isRequired: true,
                        placeholder: "0",
                        text: $knockOutPrice,
                        unit: code
                    )
                    .keyboardType(.decimalPad)
                }

                // 定期到期一次性付息，设计里没有这一行。
                if term != .fixed {
                    PawSingleSelectField(
                        label: "Payout Frequency",
                        sheetTitle: "Payout Frequency",
                        // 设计 `155:16083` 只给了这三档（月付不在选项里）。
                        options: [.hourly, .daily, .weekly],
                        selection: $payout,
                        optionTitle: { payoutTitle($0) }
                    )
                }

                if term == .structured {
                    // 只选日子：钟点由 `atPayoutHour` 钉成 16:00，留着时分选择器等于
                    // 让用户填一个存不进去的值。
                    // 直接使用 Nvwa 的可点击 Date Input。旧实现把系统 compact DatePicker
                    // 垫在下面，系统自己的胶囊会从中间透出来，且只有日期文字区域能点。
                    NvwaDateInput(
                        label: "Maturity Date",
                        value: maturityDateText,
                        calendarIcon: Image("IconCalendar"),
                        action: { showsMaturityPicker = true }
                    )
                }
            }
            } footer: {
                NvwaButton("Save", size: .huge, expandsHorizontally: true, isLoading: isSaving) { save() }
                    .disabled(isSaving)
            }
            .sheet(isPresented: $showsAssetPicker) {
                LedgerEarnAssetPicker(selection: $code)
            }
            .sheet(isPresented: $showsMaturityPicker) {
                LedgerEarnMaturityDatePicker(selection: $maturity)
            }
            .onChange(of: term) { _, value in
                if value == .fixed {
                    mode = .simple
                    payout = .atMaturity
                } else if payout == .atMaturity {
                    payout = .monthly
                }
            }
        }
    }

    private var maturityDateText: String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = locale.identifier.hasPrefix("zh") ? "yyyy年M月d日" : "MMM d yyyy"
        return formatter.string(from: maturity)
    }

    private func save() {
        guard let apy = Double(rate) else { return }
        // 定期填的是天数，到期日由「今天 + 天数」推出来（设计 `155:15867`）。
        var fixedMaturity: Date?
        if term == .fixed {
            guard let dayCount = Int(days), dayCount > 0,
                  let due = Calendar.current.date(byAdding: .day, value: dayCount, to: Date()) else { return }
            fixedMaturity = atPayoutHour(due)
        }
        // 固定票息的两个价格都是必填（设计 `155:15940` / `155:16010`）。
        var strike: Double?
        var knockOut: Double?
        if term == .structured {
            guard let s = Double(strikePrice), s > 0, let k = Double(knockOutPrice), k > 0 else { return }
            strike = s
            knockOut = k
        }
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let kind = model.preferredEarnAsset(
            code: normalized,
            fallbackKind: LedgerEarnAssetPicker.kind(for: normalized)
        ).kind
        do {
            let product = try EarnProduct(
                name: name,
                asset: LedgerAsset(code: normalized, kind: kind),
                annualRatePercent: apy,
                interestMode: term == .fixed || term == .structured ? .simple : mode,
                term: term,
                payoutFrequency: term == .fixed ? .atMaturity : payout,
                startsAt: Date(),
                maturesAt: term == .fixed ? fixedMaturity : (term == .structured ? atPayoutHour(maturity) : nil),
                strikePrice: strike,
                knockOutPrice: knockOut
            )
            isSaving = true
            Task { @MainActor in
                let success = await model.createProduct(product)
                isSaving = false
                if success { didSucceed = true }
            }
        } catch { model.errorMessage = error.localizedDescription }
    }
}

private struct LedgerEarnMaturityDatePicker: View {
    @Binding var selection: Date
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    var body: some View {
        PawSheet(title: "Maturity Date", showsCloseButton: false) {
            // 组件库自己的日历（`2014:7583`）。这里原先是系统 `.graphical`
            // DatePicker——`AGENTS.md` 里系统控件只有底部 TabView 一个例外，
            // 它是最后一处漏网的。到期日不能选到过去，交给 `minimumDate`。
            NvwaCalendar(
                selection: $selection,
                minimumDate: Date(),
                locale: locale,
                previousIcon: Image("IconArrowLeftS"),
                nextIcon: Image("IconArrowRightS")
            )
            .frame(maxWidth: .infinity)
        } footer: {
            NvwaButton("Done", size: .huge, expandsHorizontally: true) { dismiss() }
        }
    }
}

private struct LedgerEarnSubscriptionView: View {
    @ObservedObject var model: LedgerPortfolioViewModel
    let product: EarnProduct
    @State private var quantity = ""
    @State private var redeems: Bool
    @State private var fraction = 0.0
    @State private var isSaving = false
    @State private var didSucceed = false

    init(model: LedgerPortfolioViewModel, product: EarnProduct, startsRedeeming: Bool) {
        self.model = model
        self.product = product
        _redeems = State(initialValue: startsRedeeming)
    }

    private var available: Double {
        if redeems {
            return model.projection.balance(in: .earn(productID: product.id), asset: product.asset)
        }
        return model.availableBalance(for: product)
    }

    /// 定期赎回锁死全额（用户 2026-09-05）。
    private var lockedToFullAmount: Bool {
        redeems && product.redeemsFullAmountOnly
    }

    private var parsedQuantity: Double? {
        if lockedToFullAmount {
            return available > LedgerEntry.balanceTolerance ? available : nil
        }
        guard let value = AmountInput.parse(quantity), value.isFinite, value > 0,
              value <= available + LedgerEntry.balanceTolerance else { return nil }
        return value
    }

    var body: some View {
        if didSucceed {
            PawSuccessSheet()
        } else {
            PawSheet(
                localizedTitle: subscriptionTitle,
                showsCloseButton: false
            ) {
                VStack(spacing: 16) {
                if product.term != .fixed {
                    NvwaSegmentControl(
                        options: [false, true],
                        selection: $redeems,
                        expandsHorizontally: true,
                        title: { $0 ? "Redeem" : "Subscribe" }
                    )
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(LocalizedStringKey(redeems ? "Amounts" : "Investment"))
                        Spacer()
                        Text(LocalizedStringKey(redeems ? "Subscribed" : "Balance")).foregroundStyle(Nvwa.textSecondary)
                        Text("\(amount(available)) \(product.asset.code)")
                    }
                    .nvwaTextStyle(Nvwa.Typography.bodySmall, linesFillLineHeight: false)

                    if lockedToFullAmount {
                        // 定期只能全额赎回（用户 2026-09-05），所以不给输入框和滑杆，
                        // 直接把全额摆出来，免得用户以为能填一部分。
                        HStack(spacing: 8) {
                            Text("\(amount(available)) \(product.asset.code)")
                                .nvwaTextStyle(Nvwa.Typography.bodyMedium, linesFillLineHeight: false)
                                .monospacedDigit()
                                .foregroundStyle(Nvwa.ink)
                            Spacer(minLength: 8)
                            Text("Full amount")
                                .nvwaTextStyle(Nvwa.Typography.bodySmall, linesFillLineHeight: false)
                                .foregroundStyle(Nvwa.textSecondary)
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 48)
                        .background(Nvwa.backgroundInput, in: RoundedRectangle(cornerRadius: 10))
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Redeeming the full amount, \(amount(available)) \(product.asset.code)")
                    } else {
                        NvwaInputField(placeholder: "0", text: $quantity, unit: product.asset.code)
                        .keyboardType(.decimalPad)

                        NvwaSlider(value: $fraction)
                            .onChange(of: fraction) { _, value in
                                // 输入框回填不能带千分位。`amount()` 会生成 `1,000`，
                                // 旧实现又用 `Double` 解析，于是大额活期会把确认条锁死。
                                quantity = AmountInput.text(available * value)
                            }
                    }
                }

                // 赎回态没有这组汇总（设计 `155:13816`），申购态按类型分两套。
                if !redeems {
                    VStack(spacing: 8) {
                        if product.term == .fixed {
                            // 设计 `158:17298`：定期看的是「持有到期能拿多少」+ 天数 + 到期日。
                            ledgerDetailRow("APY", "\(amount(model.effectiveRate(for: product)))%", tone: Nvwa.marketBuy)
                            ledgerDetailRow("Total Profits After Maturity", projectedPayoutText, tone: Nvwa.marketBuy)
                            if let maturity = product.maturesAt {
                                ledgerDetailRow("Days", "\(max(0, Calendar.current.dateComponents([.day], from: product.startsAt, to: maturity).day ?? 0))D")
                                ledgerDetailRow("Maturity Date", maturityTimestamp(maturity))
                            }
                        } else {
                            // 设计 `155:13936`：Time / Investment 在最前，Next Time Payout 收尾。
                            ledgerDetailRow("Time", ledgerTimestamp(Date()))
                            ledgerDetailRow("Investment", investmentText)
                            ledgerDetailRow("APY", "\(amount(model.effectiveRate(for: product)))%", tone: Nvwa.marketBuy)
                            ledgerDetailRow("Payout Frequency", payoutTitle(product.payoutFrequency))
                            ledgerDetailRow(
                                "\(payoutCadenceTitle(product.payoutFrequency)) Profits",
                                projectedPayoutText,
                                tone: Nvwa.marketBuy
                            )
                            if let next = model.nextPayoutDate(for: product) {
                                ledgerDetailRow("Next Time Payout", nextPayoutTimestamp(next))
                            }
                        }
                    }
                }
                }
            } footer: {
                NvwaScrollButton("Slide to Confirm", isLoading: isSaving) { submit() }
                    .disabled(parsedQuantity == nil || isSaving)
            }
        }
    }

    private var subscriptionTitle: LocalizedStringKey {
        product.term == .fixed && !redeems
            ? "Subscribe \(product.name)"
            : LocalizedStringKey(product.name)
    }

    /// 设计 `155:13936` 的 Investment 行：回显用户填的金额，没填显示 `--`。
    private var investmentText: String {
        guard let value = parsedQuantity else { return "--" }
        return "\(amount(value)) \(product.asset.code)"
    }

    private var projectedPayoutText: String {
        guard let principal = parsedQuantity,
              let projected = EarnInterestCalculator.projectedPayout(
                  product: product,
                  principal: principal,
                  asOf: Date()
              ) else { return "--" }
        return "\(MoneyFormat.signedDecimal(projected)) \(product.asset.code)"
    }

    private func submit() {
        guard let value = parsedQuantity else { return }
        isSaving = true
        Task { @MainActor in
            let success = redeems
                ? await model.redeem(product: product, quantity: value)
                : await model.subscribe(product: product, quantity: value)
            isSaving = false
            if success {
                didSucceed = true
            }
        }
    }
}

private struct LedgerInterestPayoutView: View {
    @ObservedObject var model: LedgerPortfolioViewModel
    let product: EarnProduct
    @State private var quantity = ""
    @State private var isSaving = false
    @State private var didSucceed = false

    private var suggestedInterest: Double {
        model.accruedInterest(for: product)
    }

    var body: some View {
        if didSucceed {
            PawSuccessSheet()
        } else {
            PawSheet(title: "Record Interest", showsCloseButton: false) {
                VStack(spacing: 16) {
                    NvwaInputField(
                        label: "Interest Paid",
                        isRequired: true,
                        placeholder: "0 \(product.asset.code)",
                        text: $quantity
                    )
                    .keyboardType(.decimalPad)
                    if suggestedInterest > LedgerEntry.balanceTolerance {
                        Button {
                            quantity = amount(suggestedInterest)
                        } label: {
                            Text("Use calculated interest: \(amount(suggestedInterest)) \(product.asset.code)")
                                .nvwaTextStyle(Nvwa.Typography.bodySmallSemibold, linesFillLineHeight: false)
                                .foregroundStyle(Nvwa.textBlue)
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    NvwaHint(
                        product.interestMode == .compound
                            ? "This payout will be reinvested into the Earn principal."
                            : "This payout will be credited to the funding account.",
                        level: .neutral
                    )
                }
            } footer: {
                NvwaScrollButton("Slide to Confirm", isLoading: isSaving) { submit() }
                    .disabled(parsedQuantity == nil || isSaving)
            }
        }
    }

    private var parsedQuantity: Double? {
        guard let value = Double(quantity), value > 0 else { return nil }
        return value
    }

    private func submit() {
        guard let parsedQuantity else { return }
        isSaving = true
        Task { @MainActor in
            let success = await model.recordInterestPayout(product: product, quantity: parsedQuantity)
            isSaving = false
            if success {
                didSucceed = true
            }
        }
    }
}

@ViewBuilder
private func assetMark(_ asset: LedgerAsset, diameter: CGFloat = 20) -> some View {
    Group {
        if asset.kind == .fiat, let info = CurrencyCatalog.info(for: CurrencyCode(asset.code)) {
            Image(info.flagAssetName).resizable().scaledToFill()
                .frame(width: diameter, height: diameter).clipShape(Circle())
        } else if asset.kind == .stablecoin, let info = StablecoinCatalog.info(for: asset.code) {
            Image(info.logoAssetName).resizable().scaledToFit()
                .frame(width: diameter, height: diameter)
        } else if let assetName = AssetLogoCatalog.assetName(
            quoteSymbol: asset.code,
            assetType: ledgerAssetType(asset)
        ) {
            Image(assetName).resizable().scaledToFit()
                .frame(width: diameter, height: diameter)
        } else {
            Text(String(asset.code.prefix(1)))
                .font(Nvwa.font(max(10, diameter * 0.4), weight: .semibold))
                .foregroundStyle(Nvwa.colorOnBlue)
                .frame(width: diameter, height: diameter)
                .background(Nvwa.primaryGreen, in: Circle())
        }
    }
    .accessibilityHidden(true)
}

private func assetDescription(
    _ asset: LedgerAsset,
    locale: Locale = Locale(identifier: "en")
) -> String {
    if let info = CurrencyCatalog.info(for: CurrencyCode(asset.code)) {
        return info.localizedName(locale: locale)
    }
    if asset.kind == .stablecoin, let info = StablecoinCatalog.info(for: asset.code) { return info.name }
    switch asset.kind {
    case .stablecoin: return "Stablecoin"
    case .cryptocurrency: return "Cryptocurrency"
    case .equity: return "Stock"
    case .etf: return "ETF"
    case .fiat: return asset.code
    }
}

private func ledgerAssetType(_ asset: LedgerAsset) -> AssetType {
    switch asset.kind {
    case .equity: .equity
    case .etf: .etf
    case .cryptocurrency: .cryptocurrency
    case .stablecoin, .fiat: .stable
    }
}

/// 设计里没填的字段不隐藏，而是显示 Not Set（`45:819`）。原来挂在
/// `PositionConfirmationSummary` 上，那条旧分支删掉之后搬到这里。
enum LedgerFieldPlaceholder {
    static let notSet = "Not Set"
}

@MainActor
/// Fiat / Spot 支持的账户（`LEDGER_MODEL.md`）。顺序按设计 `154:10896` 的弹层排：
/// Bank / Cash / Exchange / Alipay / Wechat。
enum LedgerAccountOption {
    static let all = ["bank", "cash", "exchange", "alipay", "wechat"]
}

/// 单选弹层里账户行左边那枚 24pt 图标（设计 `I154:10900;107:2582`）。
@ViewBuilder
private func ledgerAccountGlyph(_ identifier: String) -> some View {
    Image(ledgerAccountIconName(identifier))
        .renderingMode(.template)
        .resizable()
        .scaledToFit()
        .frame(width: 24, height: 24)
        .accessibilityHidden(true)
}

/// 账户图标按设计 `154:10896` 一一对应。**注意 Bank 和 Exchange 不要弄反**：
/// Exchange 用的是 `bank-line`（那栋有柱子的房子），Bank 用的是 `bank-card-line`。
/// 之前两者都指向 `IconBank`、Cash 和 Wechat 一起退化成 `IconMoneyDollarCircle`。
private func ledgerAccountIconName(_ identifier: String) -> String {
    switch identifier.lowercased() {
    case "bank": return "IconBankCard"
    case "cash": return "IconCash"
    case "exchange": return "IconBank"
    case "alipay": return "IconAlipay"
    case "wechat": return "IconWechatPay"
    default: return "IconMoneyDollarCircle"
    }
}

@MainActor
private func ledgerDetailRow(_ label: String, _ value: String, tone: Color = Nvwa.ink) -> some View {
    HStack(alignment: .firstTextBaseline) {
        Text(LocalizedStringKey(label)).foregroundStyle(Nvwa.textSecondary)
        Spacer(minLength: 12)
        Text(LocalizedStringKey(value)).foregroundStyle(tone).multilineTextAlignment(.trailing)
    }
    .nvwaTextStyle(Nvwa.Typography.bodyMedium, linesFillLineHeight: false)
}

/// `Payout Frequency` 那一行和单选弹层用的完整标签，**带派息钟点**
/// （设计 `155:16083` 的选项、`158:16698` 的明细行都是这个写法）。
/// 设计里写的是 `16:00 , Daily`，逗号前那个空格是稿子的手误，这里没有照抄。
private func payoutTitle(_ payout: EarnPayoutFrequency) -> String {
    switch payout {
    case .hourly: "Hourly"
    case .daily: "16:00, Daily"
    case .weekly: "16:00 Friday, Weekly"
    case .monthly: "16:00, Monthly"
    case .atMaturity: "At Maturity"
    }
}

/// 「<频率> Profits」那一行只能拿节奏词，带上钟点会读成
/// 「16:00 Friday, Weekly Profits」；设计 `158:16698` 写的是 `Weekly Profits`。
private func payoutCadenceTitle(_ payout: EarnPayoutFrequency) -> String {
    switch payout {
    case .hourly: "Hourly"
    case .daily: "Daily"
    case .weekly: "Weekly"
    case .monthly: "Monthly"
    case .atMaturity: "At Maturity"
    }
}

/// 到期日同样钉在 16:00：定期是到期一次性付息，那一次派息就是到期时刻，
/// 不该跟着「按下保存的那一秒」走（设计 `158:16698` 的 `2022-12-12 16:00`）。
/// 当天 16:00 已经过去时顺延一天，免得存下一个立刻就过期的到期日。
private func atPayoutHour(_ date: Date, calendar: Calendar = .current) -> Date {
    var components = calendar.dateComponents([.year, .month, .day], from: date)
    components.hour = EarnProduct.payoutHour
    components.minute = 0
    components.second = 0
    guard let anchored = calendar.date(from: components) else { return date }
    guard anchored <= Date() else { return anchored }
    return calendar.date(byAdding: .day, value: 1, to: anchored) ?? anchored
}

private func amount(_ value: Double) -> String {
    value.formatted(.number.grouping(.automatic).precision(.fractionLength(2...8)))
}
