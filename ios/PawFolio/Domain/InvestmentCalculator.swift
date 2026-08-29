import Foundation

enum InterestMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case compound
    case simple

    var id: Self { self }

    var title: String {
        switch self {
        case .compound: "复利"
        case .simple: "单利"
        }
    }
}

enum ForecastPeriod: String, CaseIterable, Identifiable, Sendable {
    case day
    case month
    case year

    var id: Self { self }

    var title: String {
        switch self {
        case .day: "日"
        case .month: "月"
        case .year: "年"
        }
    }

    var sampleCount: Int {
        switch self {
        case .day: 366
        case .month: 37
        case .year: 13
        }
    }

    func years(at index: Int) -> Double {
        switch self {
        case .day: Double(index) / 365
        case .month: Double(index) / 12
        case .year: Double(index)
        }
    }

    func axisLabel(at index: Int) -> String? {
        switch self {
        case .day:
            if index == 0 { return "现在" }
            if index == 365 { return "365天" }
        case .month:
            if index == 0 { return "现在" }
            if [12, 24, 36].contains(index) { return "\(index)月" }
        case .year:
            if index == 0 { return "现在" }
            if [3, 6, 9, 12].contains(index) { return "\(index)年" }
        }
        return nil
    }

    /// 长按扫描时说明落点在哪一期。`axisLabel` 只给几个刻度，这里每一点都有。
    func scrubLabel(at index: Int) -> String {
        if index == 0 { return "现在" }
        switch self {
        case .day: return "第 \(index) 天"
        case .month: return "第 \(index) 月"
        case .year: return "第 \(index) 年"
        }
    }

    var caption: String {
        switch self {
        case .day: "365 天预测"
        case .month: "36 个月预测"
        case .year: "12 年预测"
        }
    }
}

struct InvestmentInput: Equatable, Sendable {
    var principal: Double
    var annualRatePercent: Double
    var mode: InterestMode

    var sanitized: Self {
        Self(
            principal: principal.isFinite ? max(1, principal) : 1,
            annualRatePercent: annualRatePercent.isFinite ? max(0, annualRatePercent) : 0,
            mode: mode
        )
    }
}

struct InvestmentSummary: Equatable, Sendable {
    let dailyProfit: Double
    let monthlyProfit: Double
    let yearlyProfit: Double
}

struct ForecastPoint: Identifiable, Equatable, Sendable {
    let index: Int
    let years: Double
    let amount: Double

    var id: Int { index }
}

enum InvestmentCalculator {
    static func amount(afterYears years: Double, input: InvestmentInput) -> Double {
        let input = input.sanitized
        let rate = input.annualRatePercent / 100

        switch input.mode {
        case .compound:
            return input.principal * pow(1 + rate, max(0, years))
        case .simple:
            return input.principal * (1 + rate * max(0, years))
        }
    }

    static func summary(for input: InvestmentInput) -> InvestmentSummary {
        let input = input.sanitized
        return InvestmentSummary(
            dailyProfit: amount(afterYears: 1 / 365, input: input) - input.principal,
            monthlyProfit: amount(afterYears: 1 / 12, input: input) - input.principal,
            yearlyProfit: amount(afterYears: 1, input: input) - input.principal
        )
    }

    static func forecast(for input: InvestmentInput, period: ForecastPeriod) -> [ForecastPoint] {
        (0..<period.sampleCount).map { index in
            let years = period.years(at: index)
            return ForecastPoint(
                index: index,
                years: years,
                amount: amount(afterYears: years, input: input)
            )
        }
    }
}

