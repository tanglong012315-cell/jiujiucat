import Foundation

enum PortfolioHistoryRange: String, CaseIterable, Codable, Identifiable, Sendable {
    case day
    case week
    case month
    case year

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: "日"
        case .week: "周"
        case .month: "月"
        case .year: "年"
        }
    }

    var spanMilliseconds: TimeInterval {
        switch self {
        case .day: HoldingValuation.dayMilliseconds
        case .week: 7 * HoldingValuation.dayMilliseconds
        case .month: 30 * HoldingValuation.dayMilliseconds
        case .year: 365 * HoldingValuation.dayMilliseconds
        }
    }

    var sampleCount: Int {
        switch self {
        case .day: 48
        case .week: 169
        case .month: 180
        case .year: 183
        }
    }

    var prefersOneYearHistory: Bool {
        self == .month || self == .year
    }

    func timeline(endingAt timestampMilliseconds: TimeInterval) -> [TimeInterval] {
        let denominator = Double(sampleCount - 1)
        return (0..<sampleCount).map { index in
            timestampMilliseconds
                - spanMilliseconds * Double(sampleCount - 1 - index) / denominator
        }
    }
}

struct PortfolioHistoryPoint: Equatable, Identifiable, Sendable {
    let timestampMilliseconds: TimeInterval
    let value: Double

    var id: TimeInterval { timestampMilliseconds }
}

struct PortfolioHistoryResult: Equatable, Sendable {
    let range: PortfolioHistoryRange
    let points: [PortfolioHistoryPoint]
    let coverageStartsAtMilliseconds: TimeInterval?
    let estimatedSymbols: [String]

    var startValue: Double? { points.first?.value }
    var endValue: Double? { points.last?.value }

    var change: Double? {
        guard let startValue, let endValue else { return nil }
        return endValue - startValue
    }

    var changePercent: Double? {
        guard let startValue, let change, startValue > 0 else { return nil }
        return change / startValue * 100
    }
}

enum PortfolioHistoryBuilder {
    static func quantity(for holding: Holding, at timestampMilliseconds: TimeInterval) -> Double {
        let quantity = holding.positionAdjustments.reduce(holding.quantity ?? 0) { result, adjustment in
            guard adjustment.createdAt.isFinite,
                  adjustment.createdAt > timestampMilliseconds else {
                return result
            }
            return result + (adjustment.type == .reduce ? adjustment.quantity : -adjustment.quantity)
        }
        return max(0, quantity)
    }

    static func principal(for holding: Holding, at timestampMilliseconds: TimeInterval) -> Double {
        let beijingDate = HoldingValuation.beijingDateString(
            timestampMilliseconds: timestampMilliseconds
        )
        let principal = holding.principalAdjustments.reduce(holding.principal ?? 0) { result, adjustment in
            let isApplied: Bool
            if let at = adjustment.at, at.isFinite {
                isApplied = at <= timestampMilliseconds
            } else {
                isApplied = adjustment.date <= beijingDate
            }
            guard !isApplied else { return result }
            return result + (adjustment.type == .reduce ? adjustment.amount : -adjustment.amount)
        }
        return max(0, principal)
    }

    static func build(
        holdings: [Holding],
        currentPrices: [String: Double],
        shortHistories: [String: MarketPriceHistory],
        oneYearHistories: [String: MarketPriceHistory],
        range: PortfolioHistoryRange,
        endingAt timestampMilliseconds: TimeInterval
    ) -> PortfolioHistoryResult? {
        let includedHoldings = holdings.filter { !$0.isDeleted }
        guard !includedHoldings.isEmpty else { return nil }

        let times = range.timeline(endingAt: timestampMilliseconds)
        guard let windowStart = times.first else { return nil }
        var values = Array(repeating: 0.0, count: times.count)
        var hasHistoricalChange = false
        var incompleteCoverageStart: TimeInterval?
        var estimatedSymbols = Set<String>()

        for holding in includedHoldings {
            let born = holding.createdAt.isFinite ? holding.createdAt : 0
            if born > windowStart, born <= timestampMilliseconds {
                hasHistoricalChange = true
            }

            if holding.holdingKind == .interest {
                if (holding.annualRate ?? 0) > 0 {
                    hasHistoricalChange = true
                }
                if hasPrincipalChange(holding, after: windowStart, through: timestampMilliseconds) {
                    hasHistoricalChange = true
                }

                for (index, time) in times.enumerated() where born <= 0 || time >= born {
                    values[index] += principal(for: holding, at: time)
                        + HoldingValuation.accruedInterest(for: holding, at: time)
                }
                continue
            }

            if holding.positionAdjustments.contains(where: {
                $0.createdAt > windowStart && $0.createdAt <= timestampMilliseconds
            }) {
                hasHistoricalChange = true
            }

            let symbol = holding.quoteSymbol.uppercased()
            let currentPrice = validPrice(currentPrices[symbol])
            let selectedHistory = preferredHistory(
                symbol: symbol,
                range: range,
                shortHistories: shortHistories,
                oneYearHistories: oneYearHistories
            )
            let series = normalizedUSDSeries(selectedHistory)

            if !holding.isClosed, currentPrice == nil {
                return nil
            }
            guard let baselinePrice = currentPrice ?? series.last?.price else {
                continue
            }

            var sampledPrices: [Double]
            if series.count > 1 {
                hasHistoricalChange = true
                sampledPrices = resample(series, on: times)

                if let firstTime = series.first?.timestampMilliseconds,
                   usesPrehistoryEstimate(
                       holding: holding,
                       firstPriceTime: firstTime,
                       times: times
                   ) {
                    incompleteCoverageStart = max(incompleteCoverageStart ?? 0, firstTime)
                }
            } else {
                sampledPrices = Array(repeating: baselinePrice, count: times.count)
                if times.contains(where: {
                    (born <= 0 || $0 >= born) && quantity(for: holding, at: $0) > 0
                }) {
                    estimatedSymbols.insert(holding.symbol.uppercased())
                }
            }

            if !holding.isClosed, let currentPrice {
                sampledPrices[sampledPrices.count - 1] = currentPrice
            }

            for (index, time) in times.enumerated() where born <= 0 || time >= born {
                values[index] += sampledPrices[index] * quantity(for: holding, at: time)
            }
        }

        guard hasHistoricalChange else { return nil }

        // The summary and the chart endpoint deliberately share this exact valuation path.
        var currentTotal = 0.0
        for holding in includedHoldings where !holding.isClosed {
            if holding.holdingKind == .interest {
                currentTotal += max(0, holding.principal ?? 0)
                    + HoldingValuation.accruedInterest(for: holding, at: timestampMilliseconds)
            } else {
                let symbol = holding.quoteSymbol.uppercased()
                guard let price = validPrice(currentPrices[symbol]) else { return nil }
                currentTotal += price * max(0, holding.quantity ?? 0)
            }
        }
        values[values.count - 1] = currentTotal

        let gapTolerance = range.spanMilliseconds * 0.03
        let disclosedCoverage = incompleteCoverageStart.flatMap {
            $0 - windowStart > gapTolerance ? $0 : nil
        }
        let points = zip(times, values).map {
            PortfolioHistoryPoint(timestampMilliseconds: $0.0, value: $0.1)
        }
        return PortfolioHistoryResult(
            range: range,
            points: points,
            coverageStartsAtMilliseconds: disclosedCoverage,
            estimatedSymbols: estimatedSymbols.sorted()
        )
    }

    private static func preferredHistory(
        symbol: String,
        range: PortfolioHistoryRange,
        shortHistories: [String: MarketPriceHistory],
        oneYearHistories: [String: MarketPriceHistory]
    ) -> MarketPriceHistory? {
        if range.prefersOneYearHistory,
           normalizedUSDSeries(oneYearHistories[symbol]).count > 1 {
            return oneYearHistories[symbol]
        }
        return shortHistories[symbol]
    }

    private static func normalizedUSDSeries(
        _ history: MarketPriceHistory?
    ) -> [MarketPricePoint] {
        guard let history, history.currency.uppercased() == "USD" else { return [] }
        let sorted = history.series
            .filter {
                $0.timestampMilliseconds.isFinite
                    && $0.price.isFinite
                    && $0.price > 0
            }
            .sorted { $0.timestampMilliseconds < $1.timestampMilliseconds }

        var normalized: [MarketPricePoint] = []
        for point in sorted {
            if normalized.last?.timestampMilliseconds == point.timestampMilliseconds {
                normalized[normalized.count - 1] = point
            } else {
                normalized.append(point)
            }
        }
        return normalized
    }

    private static func resample(
        _ series: [MarketPricePoint],
        on times: [TimeInterval]
    ) -> [Double] {
        var cursor = 0
        var lastPrice = series[0].price
        return times.map { time in
            while cursor < series.count,
                  series[cursor].timestampMilliseconds <= time {
                lastPrice = series[cursor].price
                cursor += 1
            }
            return lastPrice
        }
    }

    private static func usesPrehistoryEstimate(
        holding: Holding,
        firstPriceTime: TimeInterval,
        times: [TimeInterval]
    ) -> Bool {
        let born = holding.createdAt.isFinite ? holding.createdAt : 0
        return times.contains { time in
            time < firstPriceTime
                && (born <= 0 || time >= born)
                && quantity(for: holding, at: time) > 0
        }
    }

    private static func hasPrincipalChange(
        _ holding: Holding,
        after start: TimeInterval,
        through end: TimeInterval
    ) -> Bool {
        let startDate = HoldingValuation.beijingDateString(timestampMilliseconds: start)
        let endDate = HoldingValuation.beijingDateString(timestampMilliseconds: end)
        return holding.principalAdjustments.contains { adjustment in
            if let at = adjustment.at, at.isFinite {
                return at > start && at <= end
            }
            return adjustment.date >= startDate && adjustment.date <= endDate
        }
    }

    private static func validPrice(_ value: Double?) -> Double? {
        value.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
    }
}
