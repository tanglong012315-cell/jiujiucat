import Charts
import Nvwa
import SwiftUI

/// PawFolio V1.2.0 calculator screen（版式仍是 V1.1 的 `46:1483`，顶栏是新加的）。
struct CalculatorView: View {
    @StateObject private var model = CalculatorViewModel()
    @FocusState private var focusedField: Field?
    /// APR 输入框的文本镜像，见 `aprInput`。
    @State private var rateText = ""

    /// 视觉 QA：`SIMCTL_CHILD_PAWFOLIO_SCROLL_BOTTOM=1` 让页面直接停在底部，
    /// 否则「滚到底会不会被贴底导航挡住」这件事在模拟器上截不到。
    /// 原来长在 `PortfolioView` 上，那一页删了之后搬到这里——只剩这一个使用者。
    static var qaScrollsToBottom: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.environment["PAWFOLIO_SCROLL_BOTTOM"] == "1"
        #else
        return false
        #endif
    }

    let isSignedIn: Bool
    let profileInitials: String
    let profileAvatar: CatAvatar
    let onOpenAccount: () -> Void
    let onSignIn: () -> Void
    /// 顶栏右上角跟持仓页一样是「+」，但编辑器归 PawFolio 页所有，这里只发请求。

    init(
        isSignedIn: Bool = true,
        profileInitials: String = "",
        profileAvatar: CatAvatar = .faceHappy,
        onOpenAccount: @escaping () -> Void = {},
        onSignIn: @escaping () -> Void = {}
    ) {
        self.isSignedIn = isSignedIn
        self.profileInitials = profileInitials
        self.profileAvatar = profileAvatar
        self.onOpenAccount = onOpenAccount
        self.onSignIn = onSignIn
    }

    private enum Field {
        case principal
        case rate
    }

    var body: some View {
        // 顶栏由 `pawGlassTopBar` 挂成 safe-area inset，内容从它底下滑过去。
        // 状态栏那一截也归那层玻璃，所以不再叠 `pawStatusBarBackground()` 的实色
        // ——留着会盖住滑上去的内容，正好把玻璃挡没。
        scrollContent
            .background(Nvwa.backgroundMain)
            .pawGlassTopBar {
                PawTopNavigation(
                    isSignedIn: isSignedIn,
                    profileInitials: profileInitials,
                    profileAvatar: profileAvatar,
                    onOpenAccount: onOpenAccount,
                    onSignIn: onSignIn
                )
            }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focusedField = nil }
            }
        }
    }

    private var scrollContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                calculatorForm
                results
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .pawScrollBounceDisabled()
        }
        // Calculator 仍可在内容超出屏幕时滚动，但不允许上下边缘的拉伸回弹。
        .pawTabBarBottomMargin()
        .defaultScrollAnchor(Self.qaScrollsToBottom ? .bottom : .top)
        .scrollDismissesKeyboard(.interactively)
    }

    private var calculatorForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                fieldLabel("Interest Calculation")

                // `47:774` 现在是 SI 在前且默认选中，`allCases` 是 compound 在前。
                NvwaSegmentControl(
                    options: [InterestMode.simple, .compound],
                    selection: $model.selectedMode,
                    size: .normal,
                    expandsHorizontally: true,
                    title: \.abbreviation
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                investmentInput
                quickAmounts
            }

            VStack(alignment: .leading, spacing: 4) {
                aprInput
                NvwaSlider(value: $model.annualRatePercent, in: 0...30)
                    .accessibilityLabel("Annual percentage rate")
            }

            NvwaButton(
                "Calculate",
                kind: .primary,
                size: .huge,
                expandsHorizontally: true
            ) {
                focusedField = nil
                model.calculate()
            }
        }
    }

    private var investmentInput: some View {
        NvwaInputField(
            label: "Total Investment",
            placeholder: "0",
            text: $model.principalText,
            unit: "USD",
            monospacedDigits: true
        )
        .keyboardType(.decimalPad)
        .focused($focusedField, equals: .principal)
        .accessibilityLabel("Total investment")
    }

    private var quickAmounts: some View {
        HStack(spacing: 4) {
            ForEach(model.quickAmounts, id: \.self) { amount in
                NvwaSection(
                    quickAmountTitle(amount),
                    isSelected: model.committedInput.principal == amount,
                    expandsHorizontally: true
                ) {
                    focusedField = nil
                    model.selectQuickAmount(amount)
                }
            }
        }
    }

    /// APR 的真值是 `Double`（滑杆和计算都读它），而组件收的是文本，所以这里
    /// 架一座桥：打字时文本推模型，滑杆动时模型推文本。**只在没聚焦时回推**——
    /// 否则用户敲到一半的 `8.` 会被格式化成 `8`，光标当场跳走。
    private var aprInput: some View {
        NvwaInputField(
            label: "APR",
            placeholder: "0",
            text: $rateText,
            unit: "%",
            monospacedDigits: true
        )
        .keyboardType(.decimalPad)
        .focused($focusedField, equals: .rate)
        .accessibilityLabel("Annual percentage rate")
        .onAppear { rateText = Self.rateText(model.annualRatePercent) }
        .onChange(of: rateText) { _, typed in
            guard let value = Double(typed.replacingOccurrences(of: ",", with: "")) else { return }
            model.annualRatePercent = min(max(value, 0), 30)
        }
        .onChange(of: model.annualRatePercent) { _, value in
            guard focusedField != .rate else { return }
            rateText = Self.rateText(value)
        }
    }

    private static func rateText(_ value: Double) -> String {
        value.formatted(
            .number
                .locale(Locale(identifier: "en_US_POSIX"))
                .grouping(.never)
                .precision(.fractionLength(0...2))
        )
    }

    private var results: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Results")
                .font(Nvwa.bodyLarge)
                .tracking(0.08)
                .foregroundStyle(Nvwa.grayPrimary)
                .frame(height: 24, alignment: .leading)

            HStack(spacing: 10) {
                resultMetric(title: "Daily", amount: model.summary.dailyProfit)
                resultMetric(title: "Weekly", amount: model.summary.weeklyProfit)
                resultMetric(title: "Monthly", amount: model.summary.monthlyProfit)
            }

            HStack(spacing: 10) {
                resultMetric(title: "Yearly", amount: model.summary.yearlyProfit)
                resultMetric(title: "5 Year", amount: model.summary.fiveYearProfit)
                resultMetric(title: "10 Year", amount: model.summary.tenYearProfit)
            }
        }
    }

    private func resultMetric(title: String, amount: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(LocalizedStringKey(title))
                .font(Nvwa.bodySmall)
                .tracking(0.12)
                .foregroundStyle(Nvwa.textSecondary)

            Text(money(amount, includesCents: true) + " USD")
                .font(Nvwa.font(12, weight: .semibold).monospacedDigit())
                .tracking(0.12)
                .foregroundStyle(Nvwa.grayPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var forecastCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    Text(money(model.totalAtForecastEnd, includesCents: false))
                        .font(Nvwa.bodyLarge.monospacedDigit())
                        .tracking(0.08)
                        .foregroundStyle(Nvwa.grayPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Spacer(minLength: 0)

                    periodPicker
                }

                Text(forecastChange)
                    .font(Nvwa.bodySmall.monospacedDigit())
                    .tracking(0.12)
                    .foregroundStyle(forecastTone)
                    .lineLimit(1)
            }
            .frame(height: 44, alignment: .top)

            HStack(spacing: 24) {
                Chart(model.forecast) { point in
                    LineMark(
                        x: .value("Period", point.index),
                        y: .value("Amount", point.amount)
                    )
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(Nvwa.grayPrimary)

                    if point.id == model.forecast.last?.id {
                        PointMark(
                            x: .value("Period", point.index),
                            y: .value("Amount", point.amount)
                        )
                        .symbolSize(28)
                        .foregroundStyle(Nvwa.grayPrimary)
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartYScale(domain: chartDomain)
                .frame(maxWidth: .infinity, minHeight: 100, maxHeight: 100)

                VStack(alignment: .trailing) {
                    ForEach(Array(yAxisLabels.enumerated()), id: \.offset) { index, label in
                        if index > 0 { Spacer(minLength: 0) }
                        Text(label)
                            .font(Nvwa.caption2.monospacedDigit())
                            .tracking(0.1)
                            .foregroundStyle(Nvwa.textSecondary)
                            .frame(width: 24, alignment: .trailing)
                    }
                }
                .frame(width: 24, height: 100)
            }
            .frame(height: 100)

            VStack(spacing: 12) {
                PawDivider()

                HStack {
                    Text("Now")
                    Spacer()
                    Text(endAxisLabel)
                }
                .font(Nvwa.caption2.monospacedDigit())
                .tracking(0.1)
                .foregroundStyle(Nvwa.textSecondary)
            }
        }
        .padding(12)
        .frame(height: 228, alignment: .top)
        .background(
            Nvwa.backgroundInput,
            in: RoundedRectangle(cornerRadius: 15, style: .continuous)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(model.selectedPeriod.caption)
        .accessibilityValue(
            "Projected total \(money(model.totalAtForecastEnd, includesCents: true)) USD"
        )
    }

    private var periodPicker: some View {
        HStack(spacing: 4) {
            ForEach(ForecastPeriod.allCases) { period in
                NvwaSection(
                    period.title,
                    isSelected: model.selectedPeriod == period
                ) {
                    model.selectedPeriod = period
                }
                .accessibilityLabel(period.caption)
            }
        }
    }

    private func fieldLabel(_ title: String) -> some View {
        Text(LocalizedStringKey(title))
            .font(Nvwa.bodySmall)
            .tracking(0.12)
            .foregroundStyle(Nvwa.textSecondary)
            .frame(height: 20, alignment: .leading)
    }

    private var forecastTone: Color {
        if model.forecastProfit > 0 { return Nvwa.marketBuy }
        if model.forecastProfit < 0 { return Nvwa.marketSell }
        return Nvwa.textSecondary
    }

    private var forecastChange: String {
        let profit = model.forecastProfit
        let principal = model.committedInput.principal
        let percent = principal > 0 ? profit / principal * 100 : 0
        let sign = profit > 0 ? "+" : profit < 0 ? "-" : ""
        let percentSign = percent > 0 ? "+" : percent < 0 ? "-" : ""
        return sign + money(abs(profit), includesCents: true) + " USD ("
            + percentSign
            + abs(percent).formatted(.number.precision(.fractionLength(2)))
            + "%)"
    }

    private var chartDomain: ClosedRange<Double> {
        let values = model.forecast.map(\.amount)
        guard let minimum = values.min(), let maximum = values.max() else { return 0...1 }
        let spread = max(maximum - minimum, max(abs(maximum) * 0.002, 1))
        return (minimum - spread * 0.08)...(maximum + spread * 0.08)
    }

    private var yAxisLabels: [String] {
        let domain = chartDomain
        return [
            compactAxisAmount(domain.upperBound),
            compactAxisAmount((domain.lowerBound + domain.upperBound) / 2),
            compactAxisAmount(domain.lowerBound)
        ]
    }

    private var endAxisLabel: String {
        switch model.selectedPeriod {
        case .day: "365D"
        case .month: "36M"
        case .year: "12Y"
        }
    }

    private func money(_ amount: Double, includesCents: Bool) -> String {
        MoneyFormat.decimal(amount, fractionDigits: includesCents ? 2 : 0)
    }

    private func quickAmountTitle(_ amount: Double) -> String {
        if abs(amount) >= 1_000_000 {
            return (amount / 1_000).formatted(
                .number.grouping(.automatic).precision(.fractionLength(0))
            ) + "K"
        }
        if abs(amount) >= 1_000 {
            return (amount / 1_000).formatted(
                .number.precision(.fractionLength(0...1))
            ) + "K"
        }
        return amount.formatted(.number.precision(.fractionLength(0)))
    }

    private func compactAxisAmount(_ amount: Double) -> String {
        if abs(amount) >= 1_000 {
            return (amount / 1_000).formatted(
                .number.precision(.fractionLength(0...1))
            ) + "K"
        }
        return amount.formatted(.number.precision(.fractionLength(0)))
    }
}
