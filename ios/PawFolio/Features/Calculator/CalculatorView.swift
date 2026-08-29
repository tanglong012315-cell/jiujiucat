import Charts
import SwiftUI

/// Web `#panel-retirement` 的复刻。结构、间距与配色对照 `public/index.html`
/// 和 `public/styles.css`，不要改回 iOS 原生排版——见 `AGENTS.md`。
struct CalculatorView: View {
    @StateObject private var model = CalculatorViewModel()
    @FocusState private var focusedField: Field?
    /// 长按扫描到的下标；和投资组合那张图同一套交互。
    @State private var scrubIndex: Int?

    private enum Field {
        case principal
        case rate
    }

    /// 卡片内容宽度，用来复刻 Web `.metric-grid` 的 389px 断点。
    @State private var blockContentWidth: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: PawLayout.blockGap) {
                    planBlock
                    resultBlock
                }
                .padding(.horizontal, PawLayout.pageHorizontal)
                .padding(.top, 16)
                .padding(.bottom, PawLayout.pageHorizontal)
            }
            .onAppear {
                blockContentWidth = geometry.size.width
                    - PawLayout.pageHorizontal * 2
                    - PawLayout.blockPadding * 2
            }
            .onChange(of: geometry.size.width) { _, width in
                blockContentWidth = width
                    - PawLayout.pageHorizontal * 2
                    - PawLayout.blockPadding * 2
            }
        }
        // 贴底导航是浮层，滚动内容要自己留出它的高度。
        .contentMargins(.bottom, PawLayout.tabBarHeight, for: .scrollContent)
        // 视觉 QA：和投资组合页同一个开关，让页面直接停在底部。
        .defaultScrollAnchor(PortfolioView.qaScrollsToBottom ? .bottom : .top)
        .background(PawTheme.bg1)
        .scrollDismissesKeyboard(.interactively)
        .task { await model.loadExchangeRate() }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") {
                    focusedField = nil
                    model.calculate()
                }
            }
        }
    }

    // MARK: 投资计划

    private var planBlock: some View {
        PawBlock {
            VStack(alignment: .leading, spacing: 8) {
                PawFieldLabel("总投资")

                PawInputShell {
                    Text("$")
                        .font(PawFont.inter(14))
                        .foregroundStyle(PawTheme.ink40)

                    TextField("", text: $model.principalText)
                        .font(PawFont.inter(24, weight: .semibold).monospacedDigit())
                        .foregroundStyle(PawTheme.ink)
                        .keyboardType(.decimalPad)
                        .focused($focusedField, equals: .principal)
                        .accessibilityLabel("总投资，美元")

                    Text("USD")
                        .font(PawFont.inter(12))
                        .foregroundStyle(PawTheme.ink40)
                }

                PawQuickAmounts(
                    amounts: model.quickAmounts,
                    selected: model.committedInput.principal,
                    title: shortAmount
                ) { amount in
                    focusedField = nil
                    model.selectQuickAmount(amount)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                PawFieldLabel("年化收益率")

                HStack(spacing: 16) {
                    PawSlider(value: $model.annualRatePercent, range: 0.01...30)
                        .accessibilityLabel("年化收益率")
                        .accessibilityValue(
                            "\(model.annualRatePercent.formatted(.number.precision(.fractionLength(2)))) 百分比"
                        )

                    PawInputShell(height: 40, horizontalPadding: 12) {
                        TextField(
                            "",
                            value: $model.annualRatePercent,
                            format: .number.precision(.fractionLength(2))
                        )
                        .font(PawFont.inter(14, weight: .semibold).monospacedDigit())
                        .foregroundStyle(PawTheme.ink)
                        .keyboardType(.decimalPad)
                        .focused($focusedField, equals: .rate)
                        .accessibilityLabel("年化收益率百分比")

                        Text("%")
                            .font(PawFont.inter(12))
                            .foregroundStyle(PawTheme.ink40)
                    }
                    .frame(width: 112)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                PawFieldLabel("计息方式")

                PawSegmented(
                    options: InterestMode.allCases,
                    title: \.title,
                    selection: $model.selectedMode
                )
            }

            PawPrimaryButton(title: "计算收益") {
                focusedField = nil
                model.calculate()
            }
            .padding(.top, 8)
        }
    }

    // MARK: 收益预估

    /// Web 在计算页和汇率页把 `.card` 的外观整体去掉了
    /// （`#panel-retirement > .card { padding: 0; background: transparent }`），
    /// 只有「投资计划」那块保留卡片。这里因此是裸区块，不要包 `PawBlock`。
    private var resultBlock: some View {
        VStack(alignment: .leading, spacing: PawLayout.blockSpacing) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("收益预估")
                    .font(PawFont.inter(14, weight: .bold))
                    .foregroundStyle(PawTheme.ink)

                Text(model.exchangeRateCaption)
                    .font(PawFont.inter(12))
                    .foregroundStyle(PawTheme.ink40)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            metricGrid

            chartBlock
        }
    }

    /// Web 的 `.metric-grid` 在 `max-width: 389px` 时塌成一列，宽屏下始终是三等分
    /// 并让数字自己缩小，而不是换行。
    private var isNarrow: Bool {
        blockContentWidth > 0 && blockContentWidth < PawLayout.narrowContentWidth
    }

    @ViewBuilder
    private var metricGrid: some View {
        if isNarrow {
            VStack(spacing: 12) {
                ForEach(metrics, id: \.title) { metric in
                    PawMetricCard(
                        title: metric.title,
                        value: metric.value,
                        secondary: metric.secondary
                    )
                }
            }
        } else {
            HStack(spacing: 12) {
                ForEach(metrics, id: \.title) { metric in
                    PawMetricCard(
                        title: metric.title,
                        value: metric.value,
                        secondary: metric.secondary
                    )
                }
            }
        }
    }

    private struct Metric {
        let title: String
        let value: String
        let secondary: String?
    }

    private var metrics: [Metric] {
        let summary = model.summary
        return [
            Metric(
                title: "日收益",
                value: currency(summary.dailyProfit),
                secondary: model.cnyText(for: summary.dailyProfit)
            ),
            Metric(
                title: "月收益",
                value: currency(summary.monthlyProfit),
                secondary: model.cnyText(for: summary.monthlyProfit)
            ),
            Metric(
                title: "年收益",
                value: currency(summary.yearlyProfit),
                secondary: model.cnyText(for: summary.yearlyProfit)
            )
        ]
    }

    // MARK: 总资产变化

    private var chartBlock: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Text("总资产变化")
                    .font(PawFont.inter(14, weight: .bold))
                    .foregroundStyle(PawTheme.ink)

                Spacer(minLength: 0)

                PawPeriodTabs(
                    options: ForecastPeriod.allCases,
                    title: \.title,
                    selection: $model.selectedPeriod
                )
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(currency(scrubbedAmount ?? model.totalAtForecastEnd))
                        .font(PawTheme.moneyLarge)
                        .foregroundStyle(PawTheme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)

                    if let cny = model.cnyText(
                        for: scrubbedAmount ?? model.totalAtForecastEnd,
                        approximate: true
                    ) {
                        Text(cny)
                            .font(PawFont.inter(12).monospacedDigit())
                            .foregroundStyle(PawTheme.ink40)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                }

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(scrubCaption ?? signedCurrency(model.forecastProfit))
                    if scrubIndex == nil {
                        Text(signedPercent)
                    }
                }
                .font(PawFont.inter(12, weight: .semibold).monospacedDigit())
                // 预测图不谈盈亏方向，整张图只用黑白——涨跌色留给真实持仓。
                .foregroundStyle(PawTheme.ink40)
            }
            .accessibilityElement(children: .combine)

            forecastChart

            // X 轴独立一行，和投资组合那张图一致。
            HStack {
                ForEach(Array(axisTitles.enumerated()), id: \.offset) { index, title in
                    if index > 0 { Spacer(minLength: 4) }
                    Text(title)
                        .font(PawFont.inter(11).monospacedDigit())
                        .foregroundStyle(PawTheme.ink20)
                }
            }
        }
    }

    /// 扫描时顶部大数字换成那一点的金额。
    private var scrubbedAmount: Double? {
        guard let scrubIndex, model.forecast.indices.contains(scrubIndex) else { return nil }
        return model.forecast[scrubIndex].amount
    }

    /// 扫描时下面那行换成「第 N 年」这类位置说明。
    private var scrubCaption: String? {
        guard let scrubIndex, model.forecast.indices.contains(scrubIndex) else { return nil }
        return model.selectedPeriod.scrubLabel(at: scrubIndex)
    }

    private var axisTitles: [String] {
        axisValues(for: model.selectedPeriod).compactMap {
            model.selectedPeriod.axisLabel(at: $0)
        }
    }

    /// 和投资组合展开后那张图同一套画法：点阵填充、峰值标注、长按扫描。
    /// 差别只有两处——只用黑白（预测没有涨跌可言），以及矮一些。
    private var forecastChart: some View {
        PawPortfolioChart(
            values: model.forecast.map(\.amount),
            tone: PawTheme.ink,
            peakLabel: currency,
            scrubIndex: $scrubIndex,
            height: 150
        )
        .accessibilityLabel("\(model.selectedPeriod.caption)总资产预测")
        .accessibilityValue("期末预计 \(currency(model.totalAtForecastEnd))")
    }

    // MARK: 格式化

    private var changeColor: Color {
        let profit = model.forecastProfit
        if profit > 0 { return PawTheme.gain }
        if profit < 0 { return PawTheme.loss }
        return PawTheme.flat
    }

    private var signedPercent: String {
        let principal = model.committedInput.principal
        guard principal > 0 else { return "+0.00%" }

        let percent = model.forecastProfit / principal * 100
        let sign = percent > 0 ? "+" : ""
        return sign + percent.formatted(.number.precision(.fractionLength(2))) + "%"
    }

    private func currency(_ amount: Double) -> String {
        "$" + amount.formatted(.number.grouping(.automatic).precision(.fractionLength(2)))
    }

    private func signedCurrency(_ amount: Double) -> String {
        (amount > 0 ? "+" : amount < 0 ? "-" : "") + currency(abs(amount))
    }

    /// Web 图表 Y 轴用的紧凑写法，例如 `27K`。
    private func compactAmount(_ amount: Double) -> String {
        guard abs(amount) >= 1_000 else {
            return amount.formatted(.number.precision(.fractionLength(0)))
        }

        let thousands = amount / 1_000
        let digits = abs(thousands) >= 100 ? 0 : (thousands == thousands.rounded() ? 0 : 1)
        return thousands.formatted(.number.precision(.fractionLength(digits))) + "K"
    }

    private func axisValues(for period: ForecastPeriod) -> [Int] {
        switch period {
        case .day: [0, 365]
        case .month: [0, 12, 24, 36]
        case .year: [0, 3, 6, 9, 12]
        }
    }

    private func shortAmount(_ amount: Double) -> String {
        "\(Int(amount / 10_000))万"
    }
}
