import Foundation

enum InterestMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case compound
    case simple

    var id: Self { self }

    var title: String {
        switch self {
        case .compound: "Compound"
        case .simple: "Simple"
        }
    }

    var abbreviation: String {
        switch self {
        case .compound: "CI"
        case .simple: "SI"
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
        case .day: "D"
        case .month: "M"
        case .year: "Y"
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
            if index == 0 { return "Now" }
            if index == 365 { return "365D" }
        case .month:
            if index == 0 { return "Now" }
            if [12, 24, 36].contains(index) { return "\(index)M" }
        case .year:
            if index == 0 { return "Now" }
            if [3, 6, 9, 12].contains(index) { return "\(index)Y" }
        }
        return nil
    }

    /// 长按扫描时说明落点在哪一期。`axisLabel` 只给几个刻度，这里每一点都有。
    func scrubLabel(at index: Int) -> String {
        if index == 0 { return "Now" }
        switch self {
        case .day: return "Day \(index)"
        case .month: return "Month \(index)"
        case .year: return "Year \(index)"
        }
    }

    var caption: String {
        switch self {
        case .day: "365-day forecast"
        case .month: "36-month forecast"
        case .year: "12-year forecast"
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
    let weeklyProfit: Double
    let monthlyProfit: Double
    let yearlyProfit: Double
    /// 用户 2026-09-06 调整结果区：第二行显示 Yearly / 5 Year / 10 Year。
    let fiveYearProfit: Double
    let tenYearProfit: Double
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
        func profit(afterYears years: Double) -> Double {
            amount(afterYears: years, input: input) - input.principal
        }

        return InvestmentSummary(
            dailyProfit: profit(afterYears: 1 / 365),
            weeklyProfit: profit(afterYears: 7 / 365),
            monthlyProfit: profit(afterYears: 1 / 12),
            yearlyProfit: profit(afterYears: 1),
            fiveYearProfit: profit(afterYears: 5),
            tenYearProfit: profit(afterYears: 10)
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
