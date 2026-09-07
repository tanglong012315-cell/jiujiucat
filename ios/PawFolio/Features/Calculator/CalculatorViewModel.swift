import Combine
import Foundation

@MainActor
final class CalculatorViewModel: ObservableObject {
    let quickAmounts: [Double] = [100_000, 200_000, 500_000, 800_000, 1_000_000]

    @Published var principalText = "100,000"
    @Published var annualRatePercent = 8.0
    /// `47:774` 默认选中 SI。
    @Published var selectedMode = InterestMode.simple
    @Published var selectedPeriod = ForecastPeriod.day
    @Published private(set) var committedInput = InvestmentInput(
        principal: 100_000,
        annualRatePercent: 8,
        mode: .simple
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
        // 解不出来回落成 1：本金为 0 时整页收益全是 0，看着像坏了。
        let principal = AmountInput.parse(principalText) ?? 1

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
}
