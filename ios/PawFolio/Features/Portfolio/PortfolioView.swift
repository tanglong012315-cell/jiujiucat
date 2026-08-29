import Charts
import SwiftUI

struct PortfolioView: View {
    @StateObject private var model: PortfolioViewModel
    @State private var editorRoute: HoldingEditorRoute?
    @State private var pendingDeletion: Holding?
    @State private var detailRoute: HoldingDetailRoute?

    @Environment(\.pawViewportWidth) private var viewportWidth
    /// 视觉 QA：`SIMCTL_CHILD_PAWFOLIO_OPEN_DETAIL=<代码>` 直接打开该标的的盈亏明细。
    @State private var detailQASymbol: String? = {
        #if DEBUG
        return ProcessInfo.processInfo.environment["PAWFOLIO_OPEN_DETAIL"]?.uppercased()
        #else
        return nil
        #endif
    }()
    /// 视觉 QA：`add` 打开新增，其余值按标的代码打开编辑。
    @State private var editorQATarget: String? = {
        #if DEBUG
        return ProcessInfo.processInfo.environment["PAWFOLIO_OPEN_EDITOR"]
        #else
        return nil
        #endif
    }()

    /// Web 的走势图默认收起，由 `.portfolio-chart-handle` 展开。
    /// 视觉 QA 可用 `SIMCTL_CHILD_PAWFOLIO_EXPAND_CHART=1` 直接展开。
    @State private var isChartExpanded = ProcessInfo.processInfo
        .environment["PAWFOLIO_EXPAND_CHART"] == "1"
    /// Web `portfolioChart.scrubIndex`；仅长按扫描期间有值，松手立即恢复实时摘要。
    @State private var chartScrubIndex: Int?
    /// Web `#merge-holdings`，选择记在本地。
    @AppStorage("pawfolio.portfolio.merge-same") private var mergesSameSymbol = false
    /// 展开的合并组。列表整体重建时状态要留在外面，否则展开的组会自己合上。
    @State private var expandedGroups: Set<String> = {
        #if DEBUG
        // 视觉 QA：展开要点击，用 `SIMCTL_CHILD_PAWFOLIO_EXPAND_GROUP=<代码>` 直接展开一组。
        if let symbol = ProcessInfo.processInfo.environment["PAWFOLIO_EXPAND_GROUP"] {
            return [symbol.uppercased()]
        }
        #endif
        return []
    }()
    /// Web 未登录时显示门禁页；点「先看看」才进本机游客模式，选择同样记在本地。
    @AppStorage("pawfolio.portfolio.guest-acknowledged") private var guestAcknowledged = false

    private let isSignedIn: Bool
    private let onSignIn: () -> Void

    static var qaScrollsToBottom: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.environment["PAWFOLIO_SCROLL_BOTTOM"] == "1"
        #else
        return false
        #endif
    }

    init(
        model: @autoclosure @escaping () -> PortfolioViewModel = PortfolioViewModel(),
        isSignedIn: Bool = true,
        onSignIn: @escaping () -> Void = {}
    ) {
        _model = StateObject(wrappedValue: model())
        self.isSignedIn = isSignedIn
        self.onSignIn = onSignIn
    }

    var body: some View {
        NavigationStack {
            Group {
                if showsGate {
                    loginGate
                } else {
                    portfolioContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(PawTheme.bg1)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $detailRoute) { route in
                HoldingDetailView(model: model, holdingID: route.holdingID)
            }
            .sheet(item: $editorRoute) { route in
                HoldingEditorView(
                    holding: route.holding,
                    prefilledAsset: route.prefilledAsset,
                    marketPrice: route.holding.flatMap { model.marketPrice(for: $0) },
                    onSave: { holding in
                        await model.upsert(holding)
                    },
                    onAdjust: { request in
                        try await model.adjust(request)
                    },
                    onDelete: { holding in
                        Task {
                            await model.delete(holding)
                            PawToastCenter.shared.show("\(holding.symbol) 已删除")
                        }
                    }
                )
            }
            .confirmationDialog(
                "删除 \(pendingDeletion?.symbol ?? "")？",
                isPresented: deletionDialogBinding,
                titleVisibility: .visible
            ) {
                Button("删除持仓", role: .destructive) {
                    guard let holding = pendingDeletion else { return }
                    Task {
                        await model.delete(holding)
                        PawToastCenter.shared.show("\(holding.symbol) 已删除")
                    }
                    pendingDeletion = nil
                }
                Button("取消", role: .cancel) {
                    pendingDeletion = nil
                }
            } message: {
                Text("这笔记录将从当前列表中移除。")
            }
            .alert("持仓数据错误", isPresented: errorAlertBinding) {
                Button("知道了", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "发生未知错误。")
            }
        }
    }

    private var showsGate: Bool {
        #if DEBUG
        // 视觉 QA：已登录时也能把门禁页调出来看。
        if ProcessInfo.processInfo.environment["PAWFOLIO_FORCE_GATE"] == "1" { return true }
        #endif
        return !isSignedIn && !guestAcknowledged
    }

    // MARK: 登录门禁（Web `.gate-card`）

    private var loginGate: some View {
        VStack(spacing: 16) {
            Image("ArtLogin")
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .accessibilityLabel("未登录")

            VStack(spacing: 8) {
                Text("登录后管理你的持仓")
                    .font(PawFont.inter(16, weight: .semibold))
                    .foregroundStyle(PawTheme.ink)

                Text("随时随地，查看盈利")
                    .font(PawFont.inter(13))
                    .foregroundStyle(PawTheme.ink40)
            }

            VStack(alignment: .leading, spacing: 10) {
                gatePerk("持仓同步到你的账号，换设备也在")
                gatePerk("随时查看每日盈亏")
            }
            .padding(.top, 4)

            Button(action: onSignIn) {
                HStack(spacing: 10) {
                    Image("IconGoogle")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)

                    Text("使用 Google 登录")
                        .font(PawFont.inter(14, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .foregroundStyle(PawTheme.bg1)
                .background(
                    PawTheme.ink,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
            }
            .buttonStyle(PawPressableButtonStyle())
            .padding(.top, 6)

            Button("先看看") {
                guestAcknowledged = true
            }
            .font(PawFont.inter(13))
            .foregroundStyle(PawTheme.ink40)
            .buttonStyle(PawPressableButtonStyle())
        }
        .frame(maxWidth: 480)
        .padding(.horizontal, 24)
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func gatePerk(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image("IconCheck")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
                .foregroundStyle(PawTheme.accent)

            Text(text)
                .font(PawFont.inter(13))
                .foregroundStyle(PawTheme.ink80)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: 持仓内容

    private var portfolioContent: some View {
        ScrollView {
            VStack(spacing: PawLayout.blockGap) {
                summaryBlock

                if !model.isRecommendDismissed {
                    recommendBlock
                }

                listBlock
            }
            .padding(.horizontal, PawLayout.pageHorizontal)
            .padding(.top, 16)
            .padding(.bottom, PawLayout.pageHorizontal)
        }
        // 贴底导航是浮层，滚动内容要自己留出它的高度。
        .contentMargins(.bottom, PawLayout.tabBarHeight, for: .scrollContent)
        // 视觉 QA：`SIMCTL_CHILD_PAWFOLIO_SCROLL_BOTTOM=1` 让页面直接停在底部，
        // 否则「滚到底会不会被导航挡住」这件事在模拟器上截不到。
        .defaultScrollAnchor(Self.qaScrollsToBottom ? .bottom : .top)
        .refreshable { await model.reload() }
        .task {
            await model.loadIfNeeded()
            await model.loadRecommendQuotes()

            #if DEBUG
            if let target = editorQATarget {
                editorQATarget = nil
                let holding = target.lowercased() == "add"
                    ? nil
                    : model.openHoldings.first(where: { $0.symbol.uppercased() == target.uppercased() })
                editorRoute = HoldingEditorRoute(holding: holding, prefilledAsset: nil)
            }
            if let symbol = detailQASymbol,
               let holding = model.openHoldings.first(where: { $0.symbol.uppercased() == symbol }) {
                detailQASymbol = nil
                detailRoute = HoldingDetailRoute(holdingID: holding.id)
            }
            #endif
        }
    }

    // MARK: 概览（Web `.portfolio-summary`）

    /// Web：`#portfolio-app > .card { padding: 0; background: transparent }`——
    /// 「投资组合的各区块共用同一个页面表面，用间距而不是嵌套容器来分隔」。
    /// 这三块都不要包 `PawBlock`。
    private var summaryBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Web `.portfolio-overview`：左边大数字，右边迷你曲线；展开后曲线让位，
            // 数字那一列自己撑满整行。
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(chartScrubIndex == nil ? "总资产" : "当时总资产")
                        .font(PawFont.inter(12))
                        .foregroundStyle(PawTheme.ink40)

                    Text(scrubbedPoint.map { currency($0.value) } ?? model.totalValue.map(currency) ?? "$—")
                        .font(PawFont.inter(32, weight: .semibold).monospacedDigit())
                        .foregroundStyle(PawTheme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)

                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(chartScrubIndex == nil ? "总盈亏" : historyComparisonLabel)
                            .foregroundStyle(PawTheme.ink40)

                        Text(scrubbedChange.map(signedCurrency) ?? model.totalProfit.map(signedCurrency) ?? "$0.00")
                            .foregroundStyle(displayedProfitTone)

                        Text(
                            (scrubbedChangePercent ?? model.totalProfitPercent)
                                .map { "(\(signedPercentText($0)))" } ?? "(0.00%)"
                        )
                        .foregroundStyle(displayedProfitTone)
                    }
                    .font(PawFont.inter(12, weight: .semibold))
                    .accessibilityElement(children: .combine)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if !isChartExpanded, !model.openHoldings.isEmpty {
                    PawSparkline(values: historyValues, tone: chartTone)
                        .contentShape(Rectangle())
                        // 同样避开 ScrollView 里 Button 的手势判定延迟。
                        .onTapGesture { withAnimation(PawMotion.expand) { isChartExpanded = true } }
                        .accessibilityAddTraits(.isButton)
                    // Web 的迷你曲线列是 clamp(104px, 36%, 200px)。
                    .frame(width: min(max(104, (viewportWidth - PawLayout.pageHorizontal * 2) * 0.36), 200))
                    .accessibilityLabel("近 7 天总资产走势，点按展开走势图")
                }
            }
            .frame(minHeight: 88)
            .padding(.vertical, 4)

            if !model.openHoldings.isEmpty {
                if isChartExpanded {
                    chartPanel
                        .transition(.opacity)
                }

                // 收起时不显示把手——那时点迷你曲线就能展开，多一个箭头是冗余；
                // 展开后才需要一个收起入口。
                if isChartExpanded {
                    // 和图表一起淡入淡出：先前它是瞬间出现的，图还没展开完把手就已经在了。
                    Image("IconArrowDownS")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                        .rotationEffect(.degrees(180))
                        .foregroundStyle(PawTheme.ink20)
                        .frame(maxWidth: .infinity)
                        .frame(height: 24)
                        .contentShape(Rectangle())
                        // 用 onTapGesture 而不是 Button：ScrollView 里的 Button 要先等
                        // 系统判定这一下是不是滚动，手感上就是「按下去半天才动」。
                        .onTapGesture {
                            withAnimation(PawMotion.expand) {
                                isChartExpanded = false
                                chartScrubIndex = nil
                            }
                        }
                        .padding(.top, 2)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityLabel("收起总资产走势图")
                        .transition(.opacity)
                }
            }
        }
    }

    /// Web `.portfolio-chart-panel`：时间戳、画布、X 轴、范围选择。
    private var chartPanel: some View {
        VStack(spacing: 0) {
            // 时间戳常驻占位，否则一出现整块图会往下跳两行。
            Text(chartStamp)
                .font(PawFont.inter(12).monospacedDigit())
                .foregroundStyle(PawTheme.ink20)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 6)

            if historyValues.count >= 2 {
                PawPortfolioChart(
                    values: historyValues,
                    tone: chartTone,
                    peakLabel: currency,
                    scrubIndex: $chartScrubIndex
                )

                // Web `.portfolio-chart-axis`：独立一行，两端对齐。
                HStack {
                    ForEach(Array(axisLabels.enumerated()), id: \.offset) { index, label in
                        if index > 0 { Spacer(minLength: 4) }
                        Text(label)
                            .font(PawFont.inter(11).monospacedDigit())
                            .foregroundStyle(PawTheme.ink20)
                    }
                }
                .padding(.top, 2)
            } else {
                Text(model.historyStatusMessage ?? "还没有足够的历史行情，等行情多攒一会儿再看")
                    .font(PawFont.inter(13))
                    .foregroundStyle(PawTheme.ink40)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            }

            // Web `.portfolio-chart-ranges`：四等分，选中块用 --segment-active。
            HStack(spacing: 0) {
                ForEach(PortfolioHistoryRange.allCases) { range in
                    let isActive = model.historyRange == range

                    Button {
                        chartScrubIndex = nil
                        Task { await model.selectHistoryRange(range) }
                    } label: {
                        Text(range.title)
                            .font(PawFont.inter(13, weight: .semibold))
                            .foregroundStyle(isActive ? PawTheme.ink : PawTheme.ink40)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 32)
                            .background(
                                isActive ? PawTheme.ink20 : Color.clear,
                                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
                }
            }
            .padding(4)
            .background(PawTheme.ink4, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.top, 12)
        }
        .padding(.top, 4)
    }

    private var historyValues: [Double] {
        model.portfolioHistory?.points.map(\.value) ?? []
    }

    private var chartTone: Color {
        guard let history = model.portfolioHistory, let change = history.change else {
            return PawTheme.flat
        }
        if change > 0 { return PawTheme.gain }
        if change < 0 { return PawTheme.loss }
        return PawTheme.flat
    }

    /// Web `chartRangeCaption()`；正在拉历史时换成加载提示。
    private var chartStamp: String {
        if let point = scrubbedPoint { return chartStamp(for: point.timestampMilliseconds) }
        if model.isLoadingHistory { return "加载历史行情…" }
        switch model.historyRange {
        case .day: return "近 24 小时"
        case .week: return "近 7 天"
        case .month: return "近 30 天"
        case .year: return "近 1 年"
        }
    }

    private var scrubbedPoint: PortfolioHistoryPoint? {
        guard let index = chartScrubIndex,
              let points = model.portfolioHistory?.points,
              points.indices.contains(index) else { return nil }
        return points[index]
    }

    private var scrubbedChange: Double? {
        guard let value = scrubbedPoint?.value,
              let base = model.portfolioHistory?.points.first?.value else { return nil }
        return value - base
    }

    private var scrubbedChangePercent: Double? {
        guard let change = scrubbedChange,
              let base = model.portfolioHistory?.points.first?.value,
              base > 0 else { return nil }
        return change / base * 100
    }

    private var historyComparisonLabel: String {
        switch model.historyRange {
        case .day: "较 24 小时前"
        case .week: "较 7 天前"
        case .month: "较 30 天前"
        case .year: "较 1 年前"
        }
    }

    private func chartStamp(for timestampMilliseconds: TimeInterval) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = model.historyRange == .year ? "yyyy/MM/dd" : "MM/dd HH:mm"
        return formatter.string(from: Date(timeIntervalSince1970: timestampMilliseconds / 1_000))
    }

    private var axisLabels: [String] {
        guard let history = model.portfolioHistory, history.points.count >= 2 else { return [] }
        let first = history.points.first!
        let last = history.points.last!
        return [axisLabel(for: first.timestampMilliseconds), axisLabel(for: last.timestampMilliseconds)]
    }

    private func axisLabel(for timestampMilliseconds: TimeInterval) -> String {
        let date = Date(timeIntervalSince1970: timestampMilliseconds / 1_000)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = model.historyRange == .day ? "HH:mm" : "M月d日"
        return formatter.string(from: date)
    }

    // MARK: 快捷添加（Web `#portfolio-recommend`）

    private var recommendBlock: some View {
        VStack(alignment: .leading, spacing: PawLayout.blockSpacing) {
            HStack {
                Text("快捷添加")
                    .font(PawFont.inter(14, weight: .bold))
                    .foregroundStyle(PawTheme.ink)

                Spacer(minLength: 0)

                Button {
                    model.isRecommendDismissed = true
                } label: {
                    Image("IconClose")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                        .foregroundStyle(PawTheme.ink40)
                        .frame(width: 44, height: 24, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PawPressableButtonStyle())
                .accessibilityLabel("关闭快捷添加")
            }

            HStack(spacing: 8) {
                ForEach(PortfolioViewModel.recommendedAssets) { asset in
                    RecommendCard(
                        asset: asset,
                        quote: model.recommendQuote(for: asset)
                    ) {
                        editorRoute = HoldingEditorRoute(holding: nil, prefilledAsset: asset)
                    }
                }
            }
        }
    }

    // MARK: 持仓明细（Web `.portfolio-list-card`）

    private var listBlock: some View {
        VStack(alignment: .leading, spacing: PawLayout.blockSpacing) {
            HStack {
                Text("持仓明细")
                    .font(PawFont.inter(14, weight: .bold))
                    .foregroundStyle(PawTheme.ink)

                Spacer(minLength: 0)

                Button {
                    withAnimation(PawMotion.expand) { mergesSameSymbol.toggle() }
                } label: {
                    HStack(spacing: 7) {
                        Image(mergesSameSymbol ? "IconCheckboxFill" : "IconCheckboxBlank")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 18, height: 18)
                            .foregroundStyle(mergesSameSymbol ? PawTheme.ink : PawTheme.ink40)

                        Text("合并同资产")
                            .font(PawFont.inter(12))
                            .foregroundStyle(PawTheme.ink40)
                    }
                    // 不给它额外高度：一旦把这一行撑到 44，标题到下面列表的视觉间距
                    // 就变成 16 + 12，看着就不是 16 了。Web 那边是用 margin-block: -6px
                    // 把 44 抵消掉，iOS 这边负 padding 会让 ScrollView 少算高度，
                    // 所以直接让它与标题同高。
                    .contentShape(Rectangle())
                }
                .buttonStyle(PawPressableButtonStyle())
                .accessibilityAddTraits(mergesSameSymbol ? [.isButton, .isSelected] : .isButton)
            }

            if model.isLoading && model.openHoldings.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else if model.openHoldings.isEmpty {
                emptyState
            } else if mergesSameSymbol {
                VStack(spacing: 8) {
                    ForEach(HoldingMerging.groups(for: model.openHoldings), id: \.symbol) { group in
                        if group.holdings.count > 1 {
                            mergedGroup(symbol: group.symbol, holdings: group.holdings)
                        } else if let holding = group.holdings.first {
                            holdingLink(holding)
                        }
                    }
                }
                // 增删一笔持仓时，其余行滑到新位置而不是整块跳一下。
                .animation(PawMotion.expand, value: model.openHoldings)
            } else {
                VStack(spacing: 8) {
                    ForEach(model.openHoldings) { holding in
                        holdingLink(holding)
                    }
                }
                .animation(PawMotion.expand, value: model.openHoldings)
            }

            // Web 的添加按钮在空状态之外，始终显示。
            Button {
                editorRoute = HoldingEditorRoute(holding: nil, prefilledAsset: nil)
            } label: {
                HStack(spacing: 6) {
                    Image("IconAdd")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)

                    Text("添加持仓")
                        .font(PawFont.inter(13, weight: .medium))
                }
                .foregroundStyle(PawTheme.ink40)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(
                    RoundedRectangle(cornerRadius: PawTheme.radiusCard, style: .continuous)
                        .strokeBorder(
                            PawTheme.ink20,
                            style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                        )
                )
            }
            .buttonStyle(PawPressableButtonStyle())

            if let quoteStatusMessage = model.quoteStatusMessage, model.hasMarketHoldings {
                Text(quoteStatusMessage)
                    .font(PawFont.inter(12))
                    .foregroundStyle(PawTheme.ink40)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image("ArtNoData")
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .accessibilityLabel("暂无持仓")

            Text("还没有持仓记录，点下面添加第一笔")
                .font(PawFont.inter(13))
                .foregroundStyle(PawTheme.ink40)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    // MARK: 行与合并组

    private func holdingLink(_ holding: Holding) -> some View {
        // Web 的持仓详情是底部弹层（`#profit-sheet-overlay`），不是二级页面。
        Button {
            detailRoute = HoldingDetailRoute(holdingID: holding.id)
        } label: {
            HoldingRow(holding: holding, metrics: model.metrics(for: holding))
        }
        .buttonStyle(PawPressableButtonStyle())
        .contextMenu {
            Button("删除", role: .destructive) { pendingDeletion = holding }
        }
        .accessibilityHint("点按查看持仓详情与记录")
    }

    /// 合并卡点开是展开这一组的明细，不再是持仓详情：合并后用户想看的是
    /// 「这几笔分别是什么」，单笔的详情在展开后的子行上照样点得到。
    @ViewBuilder
    private func mergedGroup(symbol: String, holdings: [Holding]) -> some View {
        let isExpanded = expandedGroups.contains(symbol)

        VStack(alignment: .leading, spacing: 4) {
            if let summary = HoldingMerging.summary(for: holdings, metrics: { model.metrics(for: $0) }) {
                Button {
                    withAnimation(PawMotion.expand) {
                        if isExpanded {
                            expandedGroups.remove(symbol)
                        } else {
                            expandedGroups.insert(symbol)
                        }
                    }
                } label: {
                    MergedHoldingRow(summary: summary, isExpanded: isExpanded)
                }
                .buttonStyle(PawPressableButtonStyle())
                .accessibilityHint(isExpanded ? "点按收起这一组" : "点按展开这一组的每一笔")
            }

            if isExpanded {
                VStack(spacing: 4) {
                    // 合并卡本身只有一个总数。展开后在子行**上面**补这一组的利息小结——
                    // 放在子行之后的话，笔数一多就被挤出屏幕。
                    if let interest = HoldingMerging.interestSummary(
                        for: holdings,
                        at: Date().timeIntervalSince1970 * 1_000
                    ), !interest.isEmpty {
                        GroupInterestSummary(symbol: symbol, summary: interest)
                    }

                    ForEach(holdings) { holding in
                        Button {
                            detailRoute = HoldingDetailRoute(holdingID: holding.id)
                        } label: {
                            HoldingSubrow(holding: holding, metrics: model.metrics(for: holding))
                        }
                        .buttonStyle(PawPressableButtonStyle())
                        .contextMenu {
                            Button("删除", role: .destructive) { pendingDeletion = holding }
                        }
                    }
                }
                .padding(.leading, 20)
            }
        }
    }

    // MARK: 格式化

    private var profitTone: Color {
        guard let profit = model.totalProfit else { return PawTheme.ink40 }
        if profit > 0 { return PawTheme.gain }
        if profit < 0 { return PawTheme.loss }
        return PawTheme.flat
    }

    private var displayedProfitTone: Color {
        guard let change = scrubbedChange else { return profitTone }
        if change > 0 { return PawTheme.gain }
        if change < 0 { return PawTheme.loss }
        return PawTheme.flat
    }

    private func currency(_ amount: Double) -> String {
        "$" + amount.formatted(.number.grouping(.automatic).precision(.fractionLength(2)))
    }

    private func signedCurrency(_ amount: Double) -> String {
        (amount > 0 ? "+" : amount < 0 ? "-" : "") + currency(abs(amount))
    }

    private func signedPercentText(_ percent: Double) -> String {
        (percent > 0 ? "+" : "")
            + percent.formatted(.number.precision(.fractionLength(2))) + "%"
    }

    private var deletionDialogBinding: Binding<Bool> {
        Binding(
            get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } }
        )
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )
    }
}

/// Web `.recommend-card`。
private struct RecommendCard: View {
    let asset: AssetSearchResult
    let quote: MarketQuote?
    let onAdd: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            PawAssetLogo(
                quoteSymbol: asset.quoteSymbol,
                assetType: asset.assetType,
                name: asset.name,
                fallbackText: String(asset.symbol.prefix(1)),
                diameter: 22,
                fallbackFontSize: 9
            )
            .padding(.bottom, 2)

            Text(asset.symbol)
                .font(PawFont.inter(12, weight: .semibold))
                .foregroundStyle(PawTheme.ink)

            if let quote {
                Text("$" + quote.price.formatted(.number.grouping(.automatic).precision(.fractionLength(2))))
                    .font(PawFont.inter(13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(PawTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            } else {
                Text("获取中")
                    .font(PawFont.inter(13))
                    .foregroundStyle(PawTheme.ink40)
            }

            changeLabel

            Button(action: onAdd) {
                Image("IconAdd")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                    .foregroundStyle(PawTheme.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PawPressableButtonStyle())
            .padding(.top, 8)
            .accessibilityLabel("一键添加 \(asset.symbol)")
        }
        .padding(.top, 14)
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(
            PawTheme.ink4,
            in: RoundedRectangle(cornerRadius: PawTheme.radiusCard, style: .continuous)
        )
    }

    @ViewBuilder
    private var changeLabel: some View {
        if let quote {
            let percent = quote.changePercent

            HStack(spacing: 2) {
                Image(percent > 0 ? "IconArrowUp" : percent < 0 ? "IconArrowDown" : "IconSubtract")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 12, height: 12)

                Text(abs(percent).formatted(.number.precision(.fractionLength(2))) + "%")
                    .font(PawFont.inter(11).monospacedDigit())
            }
            .foregroundStyle(
                percent > 0 ? PawTheme.gain : percent < 0 ? PawTheme.loss : PawTheme.flat
            )
            .accessibilityLabel(
                "\(percent > 0 ? "上涨" : percent < 0 ? "下跌" : "持平") "
                    + abs(percent).formatted(.number.precision(.fractionLength(2))) + "%"
            )
        } else {
            Text("—")
                .font(PawFont.inter(11))
                .foregroundStyle(PawTheme.ink40)
        }
    }
}

private struct HoldingDetailRoute: Identifiable {
    let id = UUID()
    let holdingID: String
}

private struct HoldingEditorRoute: Identifiable {
    let id = UUID()
    let holding: Holding?
    /// 快捷添加会带一个预选标的进来。
    var prefilledAsset: AssetSearchResult?
}

private struct PortfolioHistoryCard: View {
    @Environment(\.dynamicTypeSize) private var typeSize

    let range: PortfolioHistoryRange
    let history: PortfolioHistoryResult?
    let isLoading: Bool
    let statusMessage: String?
    let onSelectRange: (PortfolioHistoryRange) -> Void

    var body: some View {
        // 外面已经是概览区块，这里不再套一层卡片——对应 Web 把走势图直接放在
        // `.portfolio-summary` 内部展开。
        Group {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("资产走势")
                        .font(PawFont.inter(14, weight: .bold))
                        .foregroundStyle(PawTheme.ink)

                    Spacer(minLength: 0)

                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("正在更新历史行情")
                    }
                }

                PawSegmented(
                    options: PortfolioHistoryRange.allCases,
                    title: \.title,
                    selection: Binding(
                        get: { range },
                        set: { onSelectRange($0) }
                    )
                )

                if let history {
                    historyContent(history)
                } else {
                    VStack(spacing: 9) {
                        Image(systemName: "chart.xyaxis.line")
                            .font(PawFont.inter(20, weight: .semibold))
                            .foregroundStyle(PawTheme.accent)
                        Text(statusMessage ?? "正在准备资产走势…")
                            .font(PawFont.inter(13))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, minHeight: 176)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func historyContent(_ history: PortfolioHistoryResult) -> some View {
        // 两个金额同时很长时不得互相挤断，辅助字号下改为纵向。
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))

        layout {
            if let endValue = history.endValue {
                Text(dollars(endValue))
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }

            if !typeSize.isAccessibilitySize {
                Spacer(minLength: 4)
            }

            if let change = history.change {
                VStack(
                    alignment: typeSize.isAccessibilitySize ? .leading : .trailing,
                    spacing: 2
                ) {
                    Text(signedCurrency(change))
                        .font(PawFont.inter(13, weight: .semibold))
                        .foregroundStyle(toneColor(for: change))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    if let percent = history.changePercent {
                        Text("区间 \(signedPercent(percent))")
                            .font(PawFont.inter(11))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                }
            }
        }

        let domain = valueDomain(for: history.points)
        let color = toneColor(for: history.change ?? 0)
        Chart(history.points) { point in
            AreaMark(
                x: .value("时间", Date(timeIntervalSince1970: point.timestampMilliseconds / 1_000)),
                yStart: .value("基线", domain.lowerBound),
                yEnd: .value("总资产", point.value)
            )
            .foregroundStyle(
                LinearGradient(
                    colors: [color.opacity(0.22), color.opacity(0.015)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            LineMark(
                x: .value("时间", Date(timeIntervalSince1970: point.timestampMilliseconds / 1_000)),
                y: .value("总资产", point.value)
            )
            .foregroundStyle(color)
            .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
            .interpolationMethod(.linear)
        }
        .chartYScale(domain: domain)
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { value in
                AxisGridLine()
                    .foregroundStyle(.quaternary)
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(axisLabel(for: date))
                    }
                }
            }
        }
        .frame(height: 176)
        .accessibilityLabel("\(range.title)总资产走势图")
        .accessibilityValue(historyAccessibilityValue(history))

        if let coverage = history.coverageStartsAtMilliseconds {
            Label {
                Text(
                    "真实行情从 \(coverageDate(coverage)) 开始，更早区间使用最早可用价格估算。"
                )
            } icon: {
                Image(systemName: "info.circle")
            }
            .font(PawFont.inter(11))
            .foregroundStyle(.secondary)
        }

        if !history.estimatedSymbols.isEmpty {
            Label {
                Text("\(history.estimatedSymbols.joined(separator: "、")) 缺少完整历史行情，已按当前价估算。")
            } icon: {
                Image(systemName: "exclamationmark.triangle")
            }
            .font(PawFont.inter(11))
            .foregroundStyle(.secondary)
        }

        if let statusMessage {
            Label(statusMessage, systemImage: "clock.arrow.circlepath")
                .font(PawFont.inter(11))
                .foregroundStyle(.secondary)
        }
    }

    /// Web 一律写 `$`，不是 iOS 本地化出来的 `US$`。
    private func dollars(_ amount: Double) -> String {
        "$" + amount.formatted(.number.grouping(.automatic).precision(.fractionLength(2)))
    }

    private func valueDomain(for points: [PortfolioHistoryPoint]) -> ClosedRange<Double> {
        let values = points.map(\.value)
        guard let minimum = values.min(), let maximum = values.max() else { return 0...1 }
        let padding = max((maximum - minimum) * 0.16, max(abs(maximum), 1) * 0.01)
        return (minimum - padding)...(maximum + padding)
    }

    private func toneColor(for change: Double) -> Color {
        change > 0 ? PawTheme.gain : change < 0 ? PawTheme.loss : PawTheme.accent
    }

    private func signedCurrency(_ value: Double) -> String {
        let formatted = dollars(abs(value))
        return value > 0 ? "+\(formatted)" : formatted
    }

    private func signedPercent(_ value: Double) -> String {
        let formatted = value.formatted(.number.precision(.fractionLength(2)))
        return "\(value > 0 ? "+" : "")\(formatted)%"
    }

    private func axisLabel(for date: Date) -> String {
        switch range {
        case .day:
            date.formatted(.dateTime.hour().minute())
        case .week, .month:
            date.formatted(.dateTime.month(.twoDigits).day(.twoDigits))
        case .year:
            date.formatted(.dateTime.year().month(.abbreviated))
        }
    }

    private func coverageDate(_ timestampMilliseconds: TimeInterval) -> String {
        Date(timeIntervalSince1970: timestampMilliseconds / 1_000)
            .formatted(.dateTime.year().month().day())
    }

    private func historyAccessibilityValue(_ history: PortfolioHistoryResult) -> String {
        let start = history.startValue.map(dollars) ?? "未知"
        let end = history.endValue.map(dollars) ?? "未知"
        return "区间起点 \(start)，当前 \(end)"
    }
}

/// Web `.holding-group-summary`：合并组的汇总行，右侧带笔数与展开箭头。
private struct MergedHoldingRow: View {
    let summary: MergedHoldingSummary
    let isExpanded: Bool

    var body: some View {
        HStack(spacing: 12) {
            PawAssetLogo(
                quoteSymbol: summary.quoteSymbol,
                assetType: summary.assetType ?? .equity,
                name: summary.name,
                fallbackText: String(summary.symbol.prefix(2)),
                diameter: 32
            )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(summary.symbol)
                        .font(PawFont.inter(14, weight: .semibold))
                        .foregroundStyle(PawTheme.ink)

                    if let modeTag = summary.interestModeTag {
                        PawHoldingTag(text: modeTag, kind: modeTag == "复利" ? .compound : .simple)
                    }

                    // 年化与计息方式只在全组一致时才有值，不一致就不标——挑一个是谎报。
                    if let rateTag = summary.rateTag {
                        PawHoldingTag(text: rateTag, kind: .rate)
                    }

                    // Web 把「N 笔 ›」接在标题行末尾（`titleLine.append(expand)`），
                    // 不放在右边的金额列。箭头是右箭头，展开时转 90°。
                    HStack(spacing: 4) {
                        Text("\(summary.count) 笔")
                            .font(PawFont.inter(11, weight: .medium))

                        Image("IconArrowRightS")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 12, height: 12)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .animation(PawMotion.selection, value: isExpanded)
                    }
                    .foregroundStyle(PawTheme.ink40)
                    // Web 注释：这块不参与收缩，否则窄屏上「3」和「笔」会上下断开。
                    .fixedSize(horizontal: true, vertical: false)
                }

                Text(summary.detail)
                    .font(PawFont.inter(11).monospacedDigit())
                    .foregroundStyle(PawTheme.ink40)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                if let value = summary.totalValue {
                    Text("$" + value.formatted(.number.grouping(.automatic).precision(.fractionLength(2))))
                        .font(PawFont.inter(14, weight: .semibold).monospacedDigit())
                        .foregroundStyle(PawTheme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                } else {
                    Text("$—")
                        .font(PawFont.inter(14, weight: .semibold))
                        .foregroundStyle(PawTheme.ink)
                }

                if let profit = summary.totalProfit {
                    HStack(spacing: 4) {
                        Text(signedCurrency(profit))
                        if summary.profitLabel != "利息" {
                            Text("(\(signedPercent(summary.profitPercent)))")
                        }
                    }
                    .font(PawFont.inter(11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(profit > 0 ? PawTheme.gain : profit < 0 ? PawTheme.loss : PawTheme.flat)
                    .lineLimit(1)
                }
            }

        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            PawTheme.ink4,
            in: RoundedRectangle(cornerRadius: PawTheme.radiusCard, style: .continuous)
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(summary.symbol)，\(summary.count) 笔，"
                + (summary.totalValue.map { "合计 $" + $0.formatted(.number.precision(.fractionLength(2))) }
                    ?? "合计不可用")
        )
    }

    private func signedCurrency(_ amount: Double) -> String {
        let text = abs(amount).formatted(.number.grouping(.automatic).precision(.fractionLength(2)))
        return (amount > 0 ? "+$" : amount < 0 ? "-$" : "$") + text
    }

    private func signedPercent(_ value: Double) -> String {
        (value > 0 ? "+" : "") + value.formatted(.number.precision(.fractionLength(2))) + "%"
    }
}

/// Web `.holding-subrow`：展开后的每一笔，没有 logo，用一圈发丝线代替填充。
private struct HoldingSubrow: View {
    let holding: Holding
    let metrics: HoldingMetrics

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(holding.symbol)
                        .font(PawFont.inter(13, weight: .semibold))
                        .foregroundStyle(PawTheme.ink)
                        .lineLimit(1)

                    holdingTags(for: holding)
                }

                if let detail = holding.positionDetail {
                    Text(detail)
                        .font(PawFont.inter(11).monospacedDigit())
                        .foregroundStyle(PawTheme.ink40)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                if let value = metrics.value {
                    Text("$" + value.formatted(.number.grouping(.automatic).precision(.fractionLength(2))))
                        .font(PawFont.inter(13, weight: .semibold).monospacedDigit())
                        .foregroundStyle(PawTheme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                } else {
                    Text("$—")
                        .font(PawFont.inter(13, weight: .semibold))
                        .foregroundStyle(PawTheme.ink)
                }

                if let profit = metrics.profit {
                    HStack(spacing: 4) {
                        Text(
                            (profit > 0 ? "+$" : profit < 0 ? "-$" : "$")
                                + abs(profit).formatted(.number.grouping(.automatic).precision(.fractionLength(2)))
                        )
                        if metrics.kind != .interest {
                            Text("(\(signedPercent(metrics.profitPercent)))")
                        }
                    }
                    .font(PawFont.inter(11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(profit > 0 ? PawTheme.gain : profit < 0 ? PawTheme.loss : PawTheme.flat)
                    .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: PawTheme.radiusCard, style: .continuous)
                .strokeBorder(PawTheme.ink10, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func signedPercent(_ value: Double) -> String {
        (value > 0 ? "+" : "") + value.formatted(.number.precision(.fractionLength(2))) + "%"
    }
}

/// Web `.holding-group-interest`：合并组展开后排在子行上面的利息小结。
private struct GroupInterestSummary: View {
    let symbol: String
    let summary: MergedInterestSummary

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            cell("每日预计利息", summary.daily)
            cell("昨日实现利息", summary.last)
            cell("总实现利息", summary.total)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity)
        .background(
            PawTheme.ink4,
            in: RoundedRectangle(cornerRadius: PawTheme.radiusCard, style: .continuous)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(symbol) 合并后的利息")
    }

    private func cell(_ title: String, _ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(PawFont.inter(11))
                .foregroundStyle(PawTheme.ink40)

            Text(
                (value > 0 ? "+$" : value < 0 ? "-$" : "$")
                    + abs(value).formatted(.number.grouping(.automatic).precision(.fractionLength(2)))
            )
            .font(PawFont.inter(13, weight: .semibold).monospacedDigit())
            .foregroundStyle(value > 0 ? PawTheme.gain : value < 0 ? PawTheme.loss : PawTheme.flat)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Web `.holding-row`：三列（logo / 主信息 / 金额），`--ink-4` 填充。
private struct HoldingRow: View {
    let holding: Holding
    let metrics: HoldingMetrics
    var mergedCount = 1

    var body: some View {
        HStack(spacing: 12) {
            PawAssetLogo(
                quoteSymbol: holding.quoteSymbol,
                assetType: holding.assetType ?? .equity,
                name: holding.name,
                fallbackText: String(holding.symbol.prefix(2)),
                diameter: 32
            )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(holding.symbol)
                        .font(PawFont.inter(14, weight: .semibold))
                        .foregroundStyle(PawTheme.ink)

                    holdingTags(for: holding)
                }

                if let detail = holding.positionDetail {
                    Text(detail)
                        .font(PawFont.inter(11).monospacedDigit())
                        .foregroundStyle(PawTheme.ink40)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                if let value = metrics.value {
                    Text("$" + value.formatted(.number.grouping(.automatic).precision(.fractionLength(2))))
                        .font(PawFont.inter(14, weight: .semibold).monospacedDigit())
                        .foregroundStyle(PawTheme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)

                    if let profit = metrics.profit {
                        HStack(spacing: 4) {
                            Text(signedCurrency(profit))
                            if metrics.kind != .interest {
                                Text("(\(signedPercent(metrics.profitPercent)))")
                            }
                        }
                        .font(PawFont.inter(11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(profit > 0 ? PawTheme.gain : profit < 0 ? PawTheme.loss : PawTheme.flat)
                        .lineLimit(1)
                    }
                } else {
                    Text("$—")
                        .font(PawFont.inter(14, weight: .semibold))
                        .foregroundStyle(PawTheme.ink)

                    Text("盈亏待计算")
                        .font(PawFont.inter(11))
                        .foregroundStyle(PawTheme.ink40)
                }
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            PawTheme.ink4,
            in: RoundedRectangle(cornerRadius: PawTheme.radiusCard, style: .continuous)
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func signedCurrency(_ amount: Double) -> String {
        let text = abs(amount).formatted(.number.grouping(.automatic).precision(.fractionLength(2)))
        return (amount > 0 ? "+$" : amount < 0 ? "-$" : "$") + text
    }

    private func signedPercent(_ value: Double) -> String {
        (value > 0 ? "+" : "") + value.formatted(.number.precision(.fractionLength(2))) + "%"
    }
}

private extension Holding {
    var positionDetail: String? {
        if holdingKind == .interest {
            guard let principal else { return nil }
            return "$" + principal.formatted(.number.grouping(.automatic).precision(.fractionLength(2)))
        }

        guard let quantity else { return nil }
        return "\(quantity.formatted(.number.precision(.fractionLength(0...6)))) 份"
    }
}

private enum PawHoldingTagKind {
    case simple
    case compound
    case rate
}

private struct PawHoldingTag: View {
    let text: String
    let kind: PawHoldingTagKind

    var body: some View {
        Text(text)
            .font(PawFont.inter(10, weight: .semibold).monospacedDigit())
            .foregroundStyle(foreground)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(background, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .fixedSize()
            .accessibilityLabel(kind == .rate ? "年化 \(text)" : text)
    }

    private var background: Color {
        switch kind {
        case .simple: PawTheme.tintBlue
        case .compound: PawTheme.tintOrange
        case .rate: PawTheme.tintGreen
        }
    }

    private var foreground: Color {
        switch kind {
        case .simple: PawTheme.onTintBlue
        case .compound: PawTheme.onTintOrange
        case .rate: PawTheme.onTintGreen
        }
    }
}

@ViewBuilder
private func holdingTags(for holding: Holding) -> some View {
    if holding.holdingKind == .interest {
        let isCompound = holding.interestMode == .compound
        PawHoldingTag(text: isCompound ? "复利" : "单利", kind: isCompound ? .compound : .simple)
    }
    if (holding.holdingKind == .interest || holding.holdingKind == .hybrid),
       let rate = holding.annualRate,
       rate > 0 {
        PawHoldingTag(
            text: rate.formatted(.number.precision(.fractionLength(2))) + "%",
            kind: .rate
        )
    }
}
