import Charts
import SwiftUI

struct PortfolioView: View {
    @StateObject private var model: PortfolioViewModel
    @State private var editorRoute: HoldingEditorRoute?
    @State private var pendingDeletion: Holding?

    init(model: @autoclosure @escaping () -> PortfolioViewModel = PortfolioViewModel()) {
        _model = StateObject(wrappedValue: model())
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    PortfolioSummaryCard(
                        totalValue: model.totalValue,
                        totalProfit: model.totalProfit,
                        totalProfitPercent: model.totalProfitPercent,
                        marketCostBasis: model.marketCostBasis,
                        interestPrincipal: model.interestPrincipal,
                        accruedInterest: model.accruedInterest,
                        count: model.openHoldings.count
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                if !model.openHoldings.isEmpty {
                    Section {
                        PortfolioHistoryCard(
                            range: model.historyRange,
                            history: model.portfolioHistory,
                            isLoading: model.isLoadingHistory,
                            statusMessage: model.historyStatusMessage,
                            onSelectRange: { range in
                                Task { await model.selectHistoryRange(range) }
                            }
                        )
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    }
                }

                Section {
                    if model.isLoading && model.openHoldings.isEmpty {
                        HStack {
                            Spacer()
                            ProgressView("正在读取持仓…")
                            Spacer()
                        }
                        .frame(minHeight: 140)
                    } else if model.openHoldings.isEmpty {
                        ContentUnavailableView {
                            Label("还没有持仓", systemImage: "pawprint")
                        } description: {
                            Text("添加第一笔市场资产或稳定生息记录，数据只保存在本机。")
                        } actions: {
                            Button("添加持仓") { presentEditor(for: nil) }
                                .buttonStyle(.borderedProminent)
                        }
                        .frame(maxWidth: .infinity, minHeight: 240)
                        .listRowBackground(Color.clear)
                    } else {
                        ForEach(model.openHoldings) { holding in
                            NavigationLink {
                                HoldingDetailView(model: model, holdingID: holding.id)
                            } label: {
                                HoldingRow(
                                    holding: holding,
                                    metrics: model.metrics(for: holding)
                                )
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button("删除", role: .destructive) {
                                    pendingDeletion = holding
                                }
                            }
                            .accessibilityHint("点按查看持仓详情与记录")
                        }
                    }
                } header: {
                    HStack {
                        Text("持仓")
                        Spacer()
                        if !model.openHoldings.isEmpty {
                            Text("\(model.openHoldings.count) 笔")
                                .foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    if !model.openHoldings.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            if let quoteStatusMessage = model.quoteStatusMessage,
                               model.hasMarketHoldings {
                                Label(
                                    quoteStatusMessage,
                                    systemImage: model.isRefreshingQuotes
                                        ? "arrow.trianglehead.2.clockwise.rotate.90"
                                        : "clock.arrow.circlepath"
                                )
                            }
                            Text("左滑可删除。删除会保留同步墓碑，避免未来多设备同步时旧记录复活。")
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("投资组合")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        presentEditor(for: nil)
                    } label: {
                        Label("添加持仓", systemImage: "plus")
                    }
                }
            }
            .refreshable {
                await model.reload()
            }
            .task {
                await model.loadIfNeeded()
            }
            .sheet(item: $editorRoute) { route in
                HoldingEditorView(
                    holding: route.holding,
                    marketPrice: route.holding.flatMap { model.marketPrice(for: $0) },
                    onSave: { holding in
                        await model.upsert(holding)
                    },
                    onAdjust: { request in
                        try await model.adjust(request)
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
                    Task { await model.delete(holding) }
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

    private func presentEditor(for holding: Holding?) {
        editorRoute = HoldingEditorRoute(holding: holding)
    }
}

private struct HoldingEditorRoute: Identifiable {
    let id = UUID()
    let holding: Holding?
}

private struct PortfolioSummaryCard: View {
    let totalValue: Double?
    let totalProfit: Double?
    let totalProfitPercent: Double?
    let marketCostBasis: Double
    let interestPrincipal: Double
    let accruedInterest: Double
    let count: Int

    var body: some View {
        PawCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("总资产")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if let totalValue {
                            Text(totalValue, format: .currency(code: "USD"))
                                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                                .monospacedDigit()
                                .minimumScaleFactor(0.62)
                                .lineLimit(1)
                        } else {
                            Text("$—")
                                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        }

                        if let totalProfit, let totalProfitPercent, count > 0 {
                            Text(
                                "总盈亏 \(totalProfit.formatted(.currency(code: "USD"))) "
                                    + "(\(totalProfitPercent.formatted(.number.precision(.fractionLength(2))))%)"
                            )
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(totalProfit > 0 ? PawTheme.gain : totalProfit < 0 ? PawTheme.loss : .secondary)
                            .monospacedDigit()
                        }
                    }

                    Spacer(minLength: 12)

                    Image(systemName: "pawprint.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(PawTheme.accent)
                        .frame(width: 42, height: 42)
                        .background(PawTheme.quietBlue, in: Circle())
                        .accessibilityHidden(true)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 10)], spacing: 10) {
                    PortfolioMetric(
                        title: "市场成本",
                        value: marketCostBasis,
                        systemImage: "chart.line.uptrend.xyaxis"
                    )
                    PortfolioMetric(
                        title: "生息本金",
                        value: interestPrincipal,
                        systemImage: "percent"
                    )
                    PortfolioMetric(
                        title: "已结利息",
                        value: accruedInterest,
                        systemImage: "clock.badge.checkmark"
                    )
                }

                Label(
                    count == 0
                        ? "数据仅保存在本机"
                        : "实时行情来自 jiujiucat.win · 共 \(count) 笔",
                    systemImage: "iphone"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}

private struct PortfolioMetric: View {
    let title: String
    let value: Double
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value, format: .currency(code: "USD"))
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .padding(12)
        .background(PawTheme.quietBlue.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: PawTheme.controlRadius, style: .continuous))
    }
}

private struct PortfolioHistoryCard: View {
    let range: PortfolioHistoryRange
    let history: PortfolioHistoryResult?
    let isLoading: Bool
    let statusMessage: String?
    let onSelectRange: (PortfolioHistoryRange) -> Void

    var body: some View {
        PawCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("资产走势")
                            .font(.system(.title3, design: .rounded, weight: .semibold))
                        Text("总资产 · USD")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("正在更新历史行情")
                    }
                }

                Picker(
                    "时间范围",
                    selection: Binding(
                        get: { range },
                        set: { selectedRange in
                            onSelectRange(selectedRange)
                        }
                    )
                ) {
                    ForEach(PortfolioHistoryRange.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)

                if let history {
                    historyContent(history)
                } else {
                    VStack(spacing: 9) {
                        Image(systemName: "chart.xyaxis.line")
                            .font(.title2)
                            .foregroundStyle(PawTheme.accent)
                        Text(statusMessage ?? "正在准备资产走势…")
                            .font(.subheadline)
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
        HStack(alignment: .firstTextBaseline) {
            if let endValue = history.endValue {
                Text(endValue, format: .currency(code: "USD"))
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .monospacedDigit()
            }
            Spacer()
            if let change = history.change {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(signedCurrency(change))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(toneColor(for: change))
                        .monospacedDigit()
                    if let percent = history.changePercent {
                        Text("区间 \(signedPercent(percent))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
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
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        if !history.estimatedSymbols.isEmpty {
            Label {
                Text("\(history.estimatedSymbols.joined(separator: "、")) 缺少完整历史行情，已按当前价估算。")
            } icon: {
                Image(systemName: "exclamationmark.triangle")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        if let statusMessage {
            Label(statusMessage, systemImage: "clock.arrow.circlepath")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
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
        let formatted = value.formatted(.currency(code: "USD"))
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
        let start = history.startValue?.formatted(.currency(code: "USD")) ?? "未知"
        let end = history.endValue?.formatted(.currency(code: "USD")) ?? "未知"
        return "区间起点 \(start)，当前 \(end)"
    }
}

private struct HoldingRow: View {
    let holding: Holding
    let metrics: HoldingMetrics

    var body: some View {
        HStack(spacing: 12) {
            Text(String(holding.symbol.prefix(1)))
                .font(.system(.headline, design: .rounded, weight: .bold))
                .foregroundStyle(PawTheme.accent)
                .frame(width: 42, height: 42)
                .background(PawTheme.quietBlue, in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(holding.symbol)
                        .font(.headline)
                    Text(holding.holdingKind.shortTitle)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color(uiColor: .tertiarySystemGroupedBackground), in: Capsule())
                }

                Text(holding.name)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let detail = holding.positionDetail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                if let value = metrics.value {
                    Text(value, format: .currency(code: "USD"))
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)

                    if let profit = metrics.profit {
                        Text(profit, format: .currency(code: "USD").presentation(.narrow))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(profit > 0 ? PawTheme.gain : profit < 0 ? PawTheme.loss : .secondary)
                            .monospacedDigit()
                    }
                } else {
                    Text("$—")
                        .font(.headline)
                    Text("行情暂不可用")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private extension Holding {
    var positionDetail: String? {
        if holdingKind == .interest {
            guard let annualRate else { return nil }
            return "年化 \(annualRate.formatted(.number.precision(.fractionLength(0...2))))% · \(interestMode?.title ?? "单利")"
        }

        guard let quantity else { return nil }
        let quantityText = "\(quantity.formatted(.number.precision(.fractionLength(0...6)))) 份"
        if holdingKind == .hybrid, let annualRate {
            return "\(quantityText) · 年化 \(annualRate.formatted(.number.precision(.fractionLength(0...2))))%"
        }
        return quantityText
    }
}

private extension HoldingKind {
    var shortTitle: String {
        switch self {
        case .market: "市场"
        case .interest: "生息"
        case .hybrid: "混合"
        case .dividend: "分红"
        }
    }
}
