import Combine
import Foundation

@MainActor
final class CalculatorViewModel: ObservableObject {
    let quickAmounts: [Double] = [100_000, 200_000, 300_000, 500_000, 800_000]

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
}
