import Foundation

enum EarnInterestCalculator {
    private static let secondsPerYear = 365.0 * 24 * 60 * 60

    /// Interest accrued since the last recorded payout. Interest is linear inside
    /// a payout cycle; compound products only increase principal when a payout
    /// entry is actually recorded.
    static func accruedInterest(
        product: EarnProduct,
        entries: [LedgerEntry],
        asOf date: Date,
        calendar: Calendar = .current
    ) throws -> Double {
        let calculationEnd = min(date, product.maturesAt ?? date)
        guard calculationEnd > product.startsAt else { return 0 }
        let activeEntries = activeEntries(in: entries, asOf: date)
        let productEntries = activeEntries.filter {
            $0.earnProductID == product.id && $0.occurredAt <= calculationEnd
        }
        let lastPayout = productEntries
            .filter { $0.kind == .interest && $0.occurredAt <= date }
            .map(\.occurredAt)
            .max()
        let start = max(product.startsAt, lastPayout ?? product.startsAt)
        guard calculationEnd > start else { return 0 }

        // 账户余额在申购提交时就转入 Earn，代表资金已锁定；计息本金则要
        // 到该笔申购的 Effective Date 才增加。不能直接用 LedgerProjection 的余额，
        // 否则 16:00 后提交的待建仓资金会被提前计息。
        let principalChanges = principalChanges(
            for: product,
            activeEntries: activeEntries,
            calendar: calendar
        )
        var principal = principalChanges
            .filter { $0.effectiveAt <= start }
            .reduce(0) { $0 + $1.quantity }
        var cursor = start
        var accrued = 0.0

        let balanceChanges = Dictionary(grouping: principalChanges.filter {
            $0.effectiveAt > start && $0.effectiveAt <= calculationEnd
        }, by: \.effectiveAt).mapValues { changes in
            changes.reduce(0) { $0 + $1.quantity }
        }
        let rateChangeDates = (product.rateHistory ?? [])
            .filter { $0.effectiveAt > start && $0.effectiveAt <= calculationEnd }
            .map(\.effectiveAt)
        let eventDates = Set(Array(balanceChanges.keys) + rateChangeDates).sorted()

        for eventDate in eventDates {
            accrued += segmentInterest(principal: principal, rate: product.annualRate(at: cursor), from: cursor, to: eventDate)
            cursor = eventDate
            principal += balanceChanges[eventDate, default: 0]
        }
        accrued += segmentInterest(principal: principal, rate: product.annualRate(at: cursor), from: cursor, to: calculationEnd)
        return max(0, accrued)
    }

    /// 某一时点已正式起息的本金。Earn 账户余额可能更高，因为它还包含已锁定但
    /// 仍处于「等待建仓」的申购。到期后不再有当日预估收益，因此返回 0。
    static func interestBearingPrincipal(
        product: EarnProduct,
        entries: [LedgerEntry],
        asOf date: Date,
        calendar: Calendar = .current
    ) -> Double {
        guard date >= product.startsAt else { return 0 }
        if let maturesAt = product.maturesAt, date >= maturesAt { return 0 }
        let active = activeEntries(in: entries, asOf: date)
        let principal = principalChanges(for: product, activeEntries: active, calendar: calendar)
            .filter { $0.effectiveAt <= date }
            .reduce(0) { $0 + $1.quantity }
        return max(0, principal)
    }

    private struct PrincipalChange {
        let effectiveAt: Date
        let quantity: Double
    }

    private static func activeEntries(in entries: [LedgerEntry], asOf date: Date) -> [LedgerEntry] {
        // Use the active set as of `date`, so a reversal voids the original
        // transaction throughout the calculation instead of leaving a phantom
        // subscription or payout in the interest timeline.
        let reversedEntryIDs = Set(entries.compactMap { entry in
            entry.kind == .reversal && entry.occurredAt <= date
                ? entry.reversesEntryID : nil
        })
        return entries.filter {
            $0.kind != .reversal
                && $0.occurredAt <= date
                && !reversedEntryIDs.contains($0.id)
        }
    }

    /// 下一次允许登记派息的时间。首次以真实申购提交时间为准，并要求起息后完整经过
    /// 一个周期；已有派息后则从最后一笔有效派息继续排下一个周期。
    static func nextPayoutDate(
        product: EarnProduct,
        entries: [LedgerEntry],
        asOf date: Date,
        calendar: Calendar = .current
    ) -> Date? {
        let active = activeEntries(in: entries, asOf: date)
            .filter { $0.earnProductID == product.id }
        if let lastPayout = active
            .filter({ $0.kind == .interest })
            .map(\.occurredAt)
            .max() {
            return product.nextPayout(after: lastPayout, calendar: calendar)
        }
        let firstSubscription = active
            .filter { $0.kind == .earnSubscribe }
            .map(\.occurredAt)
            .min() ?? product.startsAt
        return product.firstPayoutDate(
            forSubscriptionAt: firstSubscription,
            calendar: calendar
        )
    }

    private static func principalChanges(
        for product: EarnProduct,
        activeEntries: [LedgerEntry],
        calendar: Calendar
    ) -> [PrincipalChange] {
        let earnAccount = LedgerAccountReference.earn(productID: product.id)
        return activeEntries.compactMap { entry in
            let quantity = entry.postings
                .filter { $0.account == earnAccount && $0.asset == product.asset }
                .reduce(0) { $0 + $1.quantity }
            guard abs(quantity) > LedgerEntry.balanceTolerance else { return nil }
            let effectiveAt = entry.kind == .earnSubscribe && entry.earnProductID == product.id
                ? product.subscriptionEffectiveDate(for: entry.occurredAt, calendar: calendar)
                : entry.occurredAt
            return PrincipalChange(effectiveAt: effectiveAt, quantity: quantity)
        }
    }

    private static func segmentInterest(principal: Double, rate: Double, from: Date, to: Date) -> Double {
        guard principal > 0, to > from else { return 0 }
        return principal * (rate / 100) * to.timeIntervalSince(from) / secondsPerYear
    }

    /// Holding 页汇总条的「Daily」（设计 `155:13496`）：按当前 APY 估**一天**的利息。
    /// 注意它和 `projectedPayout` 不是一回事——那个算的是一个派息周期，
    /// 周付产品的一天和一期差着七倍。
    static func dailyInterest(product: EarnProduct, principal: Double, asOf date: Date) -> Double {
        guard principal > 0 else { return 0 }
        let rate = product.annualRate(at: date)
        guard rate > 0 else { return 0 }
        return principal * (rate / 100) / 365
    }

    /// 申购弹层里那行「<频率> Profits」（设计 `158:17628`）：按当前 APY 估**一个完整
    /// 派息周期**的利息，用来回答「这笔钱每期能拿多少」。
    ///
    /// 周期从 Effective Date 开始量。首次派息现在也必须完整经过这个周期，因此这里与
    /// 真实首期完全一致，不再存在“起息当天就派息”的残缺首期。月付使用 Calendar 加月，
    /// 既不是固定 30 天，也不会把 1 月的 31 天错误截短。
    /// 返回 `nil` 表示估不出来（本金非正、或产品还没有可用的周期），由调用方显示 `--`。
    static func projectedPayout(
        product: EarnProduct,
        principal: Double,
        asOf date: Date,
        calendar: Calendar = .current
    ) -> Double? {
        guard principal > 0 else { return nil }
        let rate = product.annualRate(at: date)
        guard rate > 0 else { return 0 }

        let seconds: TimeInterval
        if product.payoutFrequency == .atMaturity {
            guard let maturesAt = product.maturesAt, maturesAt > product.startsAt else { return nil }
            seconds = maturesAt.timeIntervalSince(product.startsAt)
        } else {
            let cycleStart = product.subscriptionEffectiveDate(
                for: product.startsAt,
                calendar: calendar
            )
            let component: Calendar.Component
            switch product.payoutFrequency {
            case .hourly: component = .hour
            case .daily: component = .day
            case .weekly: component = .weekOfYear
            case .monthly: component = .month
            case .atMaturity: return nil
            }
            guard let cycleEnd = calendar.date(byAdding: component, value: 1, to: cycleStart),
                  cycleEnd > cycleStart else { return nil }
            seconds = cycleEnd.timeIntervalSince(cycleStart)
        }
        guard seconds > 0 else { return nil }
        return principal * (rate / 100) * seconds / secondsPerYear
    }
}
