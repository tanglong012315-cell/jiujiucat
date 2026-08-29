import Combine
import Foundation

@MainActor
final class CalculatorViewModel: ObservableObject {
    let quickAmounts: [Double] = [100_000, 200_000, 300_000, 500_000, 800_000]

    private let exchangeRateClient: ExchangeRateServing

    init(exchangeRateClient: ExchangeRateServing = LiveExchangeRateClient()) {
        self.exchangeRateClient = exchangeRateClient
    }

    @Published var principalText = "10,000"
    @Published var annualRatePercent = 8.0
    @Published var selectedMode = InterestMode.compound
    @Published var selectedPeriod = ForecastPeriod.year
    @Published private(set) var committedInput = InvestmentInput(
        principal: 10_000,
        annualRatePercent: 8,
        mode: .compound
    )

    var summary: InvestmentSummary {
        InvestmentCalculator.summary(for: committedInput)
    }

    var forecast: [ForecastPoint] {
        InvestmentCalculator.forecast(for: committedInput, period: selectedPeriod)
    }

    var totalAtForecastEnd: Double {
        forecast.last?.amount ?? committedInput.principal
    }

    var forecastProfit: Double {
        totalAtForecastEnd - committedInput.principal
    }

    func selectQuickAmount(_ amount: Double) {
        principalText = amount.formatted(
            .number
                .grouping(.automatic)
                .precision(.fractionLength(0))
        )
        calculate()
    }

    func calculate() {
        let normalized = principalText
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let principal = Double(normalized) ?? 1

        committedInput = InvestmentInput(
            principal: principal,
            annualRatePercent: annualRatePercent,
            mode: selectedMode
        ).sanitized

        principalText = committedInput.principal.formatted(
            .number
                .grouping(.automatic)
                .precision(.fractionLength(0...2))
        )
        annualRatePercent = committedInput.annualRatePercent
    }

    // MARK: USD/CNY
    //
    // Web 的收益预估每一档都带一行人民币估值，标题旁还有一行实时汇率。

    @Published private(set) var usdToCny: Double?
    @Published private(set) var rateFetchedAt: Date?

    /// 汇率行文案。取不到时保持 Web 的等待措辞。
    var exchangeRateCaption: String {
        guard let usdToCny, let rateFetchedAt else {
            return "正在获取 USD/CNY 实时汇率…"
        }

        let rate = usdToCny.formatted(.number.precision(.fractionLength(4)))
        return "1 USD = \(rate) CNY · 更新于 \(Self.clockFormat.string(from: rateFetchedAt))"
    }

    /// 把美元金额换算成人民币展示串；没有汇率时返回 nil，界面据此隐藏该行。
    func cnyText(for usdAmount: Double, approximate: Bool = false) -> String? {
        guard let usdToCny else { return nil }

        let converted = usdAmount * usdToCny
        let formatted = converted.formatted(
            .number.grouping(.automatic).precision(.fractionLength(2))
        )
        return "\(approximate ? "≈" : "")¥\(formatted)"
    }

    /// Web 用 24 小时制显示更新时间，不跟随系统的 12 小时制偏好。
    private static let clockFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    func loadExchangeRate() async {
        guard usdToCny == nil else { return }

        do {
            let snapshot = try await exchangeRateClient.latestRates()
            guard let rate = snapshot.ratesPerUSD[.cny], rate.isFinite, rate > 0 else { return }
            usdToCny = rate
            rateFetchedAt = snapshot.fetchedAt
        } catch {
            // 汇率只是附加信息，取不到就保持等待文案，不打断计算。
        }
    }
}
