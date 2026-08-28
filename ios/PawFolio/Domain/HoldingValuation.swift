import Foundation

struct InterestPrincipalSegment: Equatable, Sendable {
    let startIndex: Int
    let endIndex: Int
    let principal: Double
    let startDate: String
    let endDate: String
    let effectiveDays: Int
}

struct InterestSettlement: Equatable, Sendable {
    let timestampMilliseconds: TimeInterval
    let date: String
    let amount: Double
}

struct InterestRecordEntry: Equatable, Identifiable, Sendable {
    let holdingID: String
    let timestampMilliseconds: TimeInterval
    let date: String
    let principal: Double
    let amount: Double

    var id: String { "\(holdingID)_\(date)" }
}

struct HoldingMetrics: Equatable, Sendable {
    let kind: HoldingKind
    let quantity: Double
    let cost: Double
    let marketPrice: Double?
    let value: Double?
    let profit: Double?
    let profitPercent: Double
    let accruedInterest: Double
    let confirmedDividends: Double

    var hasValue: Bool { value != nil }
}

enum HoldingValuation {
    static let dayMilliseconds: TimeInterval = 24 * 60 * 60 * 1_000

    static func firstInterestSettlementMilliseconds(startDate: String?) -> TimeInterval? {
        guard let components = dateComponents(from: startDate) else { return nil }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var utcComponents = DateComponents()
        utcComponents.calendar = calendar
        utcComponents.timeZone = calendar.timeZone
        utcComponents.year = components.year
        utcComponents.month = components.month
        utcComponents.day = components.day
        utcComponents.hour = 8

        guard let startAtEightUTC = calendar.date(from: utcComponents),
              let firstSettlement = calendar.date(byAdding: .day, value: 1, to: startAtEightUTC) else {
            return nil
        }
        return firstSettlement.timeIntervalSince1970 * 1_000
    }

    static func settledInterestDays(
        for holding: Holding,
        at timestampMilliseconds: TimeInterval
    ) -> Int {
        guard let first = firstInterestSettlementMilliseconds(startDate: holding.interestStartDate),
              timestampMilliseconds >= first else {
            return 0
        }

        return Int(floor((timestampMilliseconds - first) / dayMilliseconds)) + 1
    }

    static func principalSegments(
        for holding: Holding,
        at timestampMilliseconds: TimeInterval
    ) -> [InterestPrincipalSegment] {
        guard let first = firstInterestSettlementMilliseconds(startDate: holding.interestStartDate) else {
            return []
        }

        let count = settledInterestDays(for: holding, at: timestampMilliseconds)
        guard count > 0 else { return [] }

        struct Mark {
            let index: Int
            let delta: Double
        }

        let marks = holding.principalAdjustments.compactMap { adjustment -> Mark? in
            guard let settlement = firstInterestSettlementMilliseconds(startDate: adjustment.date) else {
                return nil
            }
            let unboundedIndex = Int(((settlement - first) / dayMilliseconds).rounded())
            let index = min(max(unboundedIndex, 0), count)
            let direction = adjustment.type == .reduce ? -1.0 : 1.0
            return Mark(index: index, delta: direction * abs(adjustment.amount))
        }
        .sorted { $0.index < $1.index }

        var principal = interestPrincipal(for: holding) - marks.reduce(0) { $0 + $1.delta }
        var start = 0
        var rawSegments: [(start: Int, end: Int, principal: Double)] = []

        for mark in marks {
            if mark.index > start {
                rawSegments.append((start, mark.index, principal))
                start = mark.index
            }
            principal += mark.delta
        }

        if start < count {
            rawSegments.append((start, count, principal))
        }

        let skippedDates = Set(holding.interestSkips)
        return rawSegments.map { segment in
            let startDate = beijingDateString(
                timestampMilliseconds: first + Double(segment.start) * dayMilliseconds
            )
            let endDate = beijingDateString(
                timestampMilliseconds: first + Double(segment.end - 1) * dayMilliseconds
            )
            let skippedCount = skippedDates.reduce(into: 0) { count, date in
                if date >= startDate && date <= endDate {
                    count += 1
                }
            }

            return InterestPrincipalSegment(
                startIndex: segment.start,
                endIndex: segment.end,
                principal: max(0, segment.principal),
                startDate: startDate,
                endDate: endDate,
                effectiveDays: max(0, segment.end - segment.start - skippedCount)
            )
        }
    }

    static func accruedInterest(
        for holding: Holding,
        at timestampMilliseconds: TimeInterval
    ) -> Double {
        guard holding.isInterestBearing else { return 0 }
        let dailyRate = max(0, holding.annualRate ?? 0) / 100 / 365
        guard dailyRate > 0 else { return 0 }

        return principalSegments(for: holding, at: timestampMilliseconds).reduce(0) { interest, segment in
            guard segment.effectiveDays > 0 else { return interest }

            switch holding.interestMode ?? .simple {
            case .compound:
                return (segment.principal + interest)
                    * pow(1 + dailyRate, Double(segment.effectiveDays))
                    - segment.principal
            case .simple:
                return interest + segment.principal * dailyRate * Double(segment.effectiveDays)
            }
        }
    }

    static func interestRecordEntries(
        for holding: Holding,
        at timestampMilliseconds: TimeInterval
    ) -> [InterestRecordEntry] {
        guard holding.isInterestBearing,
              let first = firstInterestSettlementMilliseconds(startDate: holding.interestStartDate) else {
            return []
        }

        let dailyRate = max(0, holding.annualRate ?? 0) / 100 / 365
        guard dailyRate > 0 else { return [] }

        let skippedDates = Set(holding.interestSkips)
        let isCompound = (holding.interestMode ?? .simple) == .compound
        var accrued = 0.0
        var entries: [InterestRecordEntry] = []

        for segment in principalSegments(for: holding, at: timestampMilliseconds) {
            for index in segment.startIndex..<segment.endIndex {
                let settlementTime = first + Double(index) * dayMilliseconds
                let date = beijingDateString(timestampMilliseconds: settlementTime)
                guard !skippedDates.contains(date) else { continue }

                let amount = (isCompound ? segment.principal + accrued : segment.principal) * dailyRate
                accrued += amount
                entries.append(
                    InterestRecordEntry(
                        holdingID: holding.id,
                        timestampMilliseconds: settlementTime,
                        date: date,
                        principal: segment.principal,
                        amount: amount
                    )
                )
            }
        }
        return entries
    }

    static func nextInterestSettlement(
        for holding: Holding,
        at timestampMilliseconds: TimeInterval
    ) -> InterestSettlement? {
        guard let first = firstInterestSettlementMilliseconds(startDate: holding.interestStartDate),
              (holding.annualRate ?? 0) > 0 else {
            return nil
        }

        let settlementTime = first
            + Double(settledInterestDays(for: holding, at: timestampMilliseconds)) * dayMilliseconds
        return InterestSettlement(
            timestampMilliseconds: settlementTime,
            date: beijingDateString(timestampMilliseconds: settlementTime),
            amount: accruedInterest(for: holding, at: settlementTime)
                - accruedInterest(for: holding, at: timestampMilliseconds)
        )
    }

    static func lastInterestSettlement(
        for holding: Holding,
        at timestampMilliseconds: TimeInterval
    ) -> InterestSettlement? {
        guard let first = firstInterestSettlementMilliseconds(startDate: holding.interestStartDate) else {
            return nil
        }

        let count = settledInterestDays(for: holding, at: timestampMilliseconds)
        guard count > 0 else { return nil }

        let settlementTime = first + Double(count - 1) * dayMilliseconds
        return InterestSettlement(
            timestampMilliseconds: settlementTime,
            date: beijingDateString(timestampMilliseconds: settlementTime),
            amount: accruedInterest(for: holding, at: timestampMilliseconds)
                - accruedInterest(for: holding, at: timestampMilliseconds - dayMilliseconds)
        )
    }

    static func confirmedDividendIncome(
        for holding: Holding,
        at timestampMilliseconds: TimeInterval
    ) -> Double {
        guard holding.holdingKind == .dividend,
              let assetType = holding.assetType,
              [.equity, .etf, .cryptocurrency].contains(assetType) else {
            return 0
        }

        let today = beijingDateString(timestampMilliseconds: timestampMilliseconds)
        return holding.dividendRecords.reduce(0) { total, record in
            guard !record.exDate.isEmpty, record.exDate <= today else { return total }
            return total + record.amount
        }
    }

    static func metrics(
        for holding: Holding,
        marketPrice: Double?,
        at timestampMilliseconds: TimeInterval
    ) -> HoldingMetrics {
        let interest = accruedInterest(for: holding, at: timestampMilliseconds)
        let dividends = confirmedDividendIncome(for: holding, at: timestampMilliseconds)

        if holding.holdingKind == .interest {
            let principal = max(0, holding.principal ?? 0)
            let value = principal > 0 ? principal + interest : nil
            return HoldingMetrics(
                kind: holding.holdingKind,
                quantity: principal,
                cost: principal,
                marketPrice: 1,
                value: value,
                profit: value == nil ? nil : interest,
                profitPercent: principal > 0 ? interest / principal * 100 : 0,
                accruedInterest: interest,
                confirmedDividends: 0
            )
        }

        let quantity = max(0, holding.quantity ?? 0)
        let cost = quantity * max(0, holding.costPerShare ?? 0)
        let validPrice = marketPrice.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        let value = validPrice.map { $0 * quantity }
        let profit = value.map { $0 - cost }

        return HoldingMetrics(
            kind: holding.holdingKind,
            quantity: quantity,
            cost: cost,
            marketPrice: validPrice,
            value: value,
            profit: profit,
            profitPercent: cost > 0 ? (profit ?? 0) / cost * 100 : 0,
            accruedInterest: interest,
            confirmedDividends: dividends
        )
    }

    static func beijingDateString(timestampMilliseconds: TimeInterval) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let date = Date(timeIntervalSince1970: timestampMilliseconds / 1_000)
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    private static func interestPrincipal(for holding: Holding) -> Double {
        if holding.holdingKind == .interest {
            return holding.principal ?? 0
        }
        return (holding.quantity ?? 0) * (holding.costPerShare ?? 0)
    }

    private static func dateComponents(from value: String?) -> (year: Int, month: Int, day: Int)? {
        guard let value else { return nil }
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]),
              (1...12).contains(month),
              (1...31).contains(day) else {
            return nil
        }
        return (year, month, day)
    }
}
