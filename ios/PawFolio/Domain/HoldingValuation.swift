import Foundation

struct InterestPrincipalSegment: Equatable, Sendable {
    let startIndex: Int
    let endIndex: Int
    let principal: Double
    /// 这一段生效的日利率。利率可以中途变（`Holding.rateAdjustments`），所以它
    /// 属于段而不属于持仓 —— 用持仓上那个标量去乘全部天数，会把改利率之前的
    /// 历史利息一起按新利率重算。
    let dailyRate: Double
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

        // 本金和利率各自有一组变更点，任何一处变化都要切一刀。生效日 D 一律指
        // 「D 当天那次结算就按新值算」，对应的结算序号是 D 与首次结算日的天数差。
        // `firstInterestSettlementMilliseconds` 给的是 D 的**次日**（起息日次日
        // 才首次结算），所以这里要往回退一天。
        func settlementIndex(onDate date: String) -> Int? {
            guard let settlement = firstInterestSettlementMilliseconds(startDate: date) else {
                return nil
            }
            let unbounded = Int(((settlement - dayMilliseconds - first) / dayMilliseconds).rounded())
            return min(max(unbounded, 0), count)
        }

        struct Mark {
            let index: Int
            let delta: Double
        }

        // 本金调整从用户选择的生效日当天开始计息。设计允许历史日期，因此这里
        // 不再按记录时间夹到「今天」；历史日期会明确重算该日及之后的已结算利息。
        let marks = holding.principalAdjustments.compactMap { adjustment -> Mark? in
            guard let index = settlementIndex(onDate: adjustment.date) else { return nil }
            let direction = adjustment.type == .reduce ? -1.0 : 1.0
            return Mark(index: index, delta: direction * abs(adjustment.amount))
        }
        .sorted { $0.index < $1.index }

        // 利率变更：按生效日排序，同一天有多条时后写入的胜出（createdAt 更大）。
        let rateChanges = holding.rateAdjustments
            .compactMap { change -> (index: Int, dailyRate: Double, createdAt: TimeInterval)? in
                guard let index = settlementIndex(onDate: change.date) else { return nil }
                return (index, max(0, change.annualRate) / 100 / 365, change.createdAt)
            }
            .sorted { $0.index == $1.index ? $0.createdAt < $1.createdAt : $0.index < $1.index }

        let baseDailyRate = max(0, holding.annualRate ?? 0) / 100 / 365

        /// 第 `index` 天生效的日利率：取最后一条生效日 ≤ index 的变更，没有就用初始利率。
        func dailyRate(atDayIndex index: Int) -> Double {
            rateChanges.last { $0.index <= index }?.dailyRate ?? baseDailyRate
        }

        // 切点 = 本金变更点 ∪ 利率变更点，去重后升序。
        let boundaries = Set(marks.map(\.index))
            .union(rateChanges.map(\.index))
            .filter { $0 > 0 && $0 < count }
            .sorted()

        var principal = interestPrincipal(for: holding) - marks.reduce(0) { $0 + $1.delta }
        // 生效日落在第 0 天（或更早）的本金变更直接并入起始本金，不单独成段 ——
        // 与改动前逐条 walk 的行为一致。
        principal += marks.filter { $0.index == 0 }.reduce(0) { $0 + $1.delta }

        var start = 0
        var rawSegments: [(start: Int, end: Int, principal: Double, dailyRate: Double)] = []

        for boundary in boundaries {
            rawSegments.append((start, boundary, principal, dailyRate(atDayIndex: start)))
            principal += marks.filter { $0.index == boundary }.reduce(0) { $0 + $1.delta }
            start = boundary
        }

        if start < count {
            rawSegments.append((start, count, principal, dailyRate(atDayIndex: start)))
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
                dailyRate: segment.dailyRate,
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

        // 利率按段取（segment.dailyRate），不再用持仓上的标量乘全程。
        return principalSegments(for: holding, at: timestampMilliseconds).reduce(0) { interest, segment in
            guard segment.effectiveDays > 0, segment.dailyRate > 0 else { return interest }

            switch holding.interestMode ?? .simple {
            case .compound:
                return (segment.principal + interest)
                    * pow(1 + segment.dailyRate, Double(segment.effectiveDays))
                    - segment.principal
            case .simple:
                return interest + segment.principal * segment.dailyRate * Double(segment.effectiveDays)
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

        let skippedDates = Set(holding.interestSkips)
        let isCompound = (holding.interestMode ?? .simple) == .compound
        var accrued = 0.0
        var entries: [InterestRecordEntry] = []

        for segment in principalSegments(for: holding, at: timestampMilliseconds) {
            guard segment.dailyRate > 0 else { continue }
            for index in segment.startIndex..<segment.endIndex {
                let settlementTime = first + Double(index) * dayMilliseconds
                let date = beijingDateString(timestampMilliseconds: settlementTime)
                guard !skippedDates.contains(date) else { continue }

                let amount = (isCompound ? segment.principal + accrued : segment.principal) * segment.dailyRate
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

    /// 某一刻实际生效的年化利率：最后一条生效日 ≤ 当天的 `rateAdjustments`，
    /// 没有就回落到 `annualRate`（旧数据只有这一个值）。
    ///
    /// 凡是要展示「当前利率」或判断「是否在生息」的地方都该走这里 —— 直接读
    /// `holding.annualRate` 会在利率变更后显示成旧值。
    static func effectiveAnnualRate(
        for holding: Holding,
        at timestampMilliseconds: TimeInterval
    ) -> Double {
        let today = beijingDateString(timestampMilliseconds: timestampMilliseconds)
        let applicable = holding.rateAdjustments
            .filter { $0.date <= today }
            .sorted { $0.date == $1.date ? $0.createdAt < $1.createdAt : $0.date < $1.date }
        return applicable.last?.annualRate ?? (holding.annualRate ?? 0)
    }

    static func nextInterestSettlement(
        for holding: Holding,
        at timestampMilliseconds: TimeInterval
    ) -> InterestSettlement? {
        guard let first = firstInterestSettlementMilliseconds(startDate: holding.interestStartDate),
              effectiveAnnualRate(for: holding, at: timestampMilliseconds) > 0 else {
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

    static func metrics(
        for holding: Holding,
        marketPrice: Double?,
        at timestampMilliseconds: TimeInterval
    ) -> HoldingMetrics {
        let interest = accruedInterest(for: holding, at: timestampMilliseconds)

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
                accruedInterest: interest
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
            accruedInterest: interest
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
